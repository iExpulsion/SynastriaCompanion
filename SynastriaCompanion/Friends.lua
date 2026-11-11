local _, NS = ...
local SC = NS.SC

-- Friends: attune counts shared over addon messages with friends, guildmates and the group, kept account-wide, and
-- asking them who still needs an item. Messages are fields joined by ";", the second the protocol version:
-- H asks for statuses, S is a status, Q asks who needs an item (by item string), N is a whispered "I need it".
local Friends = { queries = {} }
SC.Friends = Friends

local PREFIX, VERSION = "SComp", "1"
local SEND_GAP = 0.2
local LOGIN_DELAY, GROUP_DELAY, ONLINE_DELAY, ATTUNED_DELAY = 5, 3, 10, 30
local HELLO_COOLDOWN = 60
local QUERY_COOLDOWN, ANSWER_TTL = 120, 600
local FORGET_AFTER = 60 * 86400

Friends.HELLO_COOLDOWN = HELLO_COOLDOWN

local function me()
	return UnitName("player")
end

-- Outgoing messages, one per SEND_GAP; the frame runs only while something waits.
local queue = {}
local sender = CreateFrame("Frame")
sender:Hide()
local sinceSend = 0
sender:SetScript("OnUpdate", function(self, dt)
	sinceSend = sinceSend + dt
	if sinceSend >= SEND_GAP then
		sinceSend = 0
		local m = table.remove(queue, 1)
		if m then SendAddonMessage(PREFIX, m[1], m[2], m[3]) end
		if #queue == 0 then self:Hide() end
	end
end)

local function send(msg, channel, target)
	queue[#queue + 1] = { msg, channel, target }
	sender:Show()
end

local function groupUnits()
	local raid, party = GetNumRaidMembers(), GetNumPartyMembers()
	if raid > 0 then return "raid", raid end
	return "party", party
end

-- Everyone a message can reach, as name -> { relation, online }: the group, friends, then the guild; the first
-- relation found wins.
function Friends.Relations()
	local out = {}
	local prefix, count = groupUnits()
	for i = 1, count do
		local unit = prefix .. i
		local name = UnitName(unit)
		if name and name ~= me() then
			out[name] = { relation = "Group", online = UnitIsConnected(unit) and true or false }
		end
	end
	for i = 1, GetNumFriends() do
		local name, _, _, _, connected = GetFriendInfo(i)
		if name and not out[name] then out[name] = { relation = "Friend", online = connected and true or false } end
	end
	if IsInGuild() then
		for i = 1, GetNumGuildMembers() do
			local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
			if name and not out[name] then out[name] = { relation = "Guild", online = online and true or false } end
		end
	end
	return out
end

-- Sends to the guild and the group, and whispers online friends neither reaches. groupOnly: just the group.
function Friends.Broadcast(msg, groupOnly)
	local reached = {}
	local prefix, count = groupUnits()
	if count > 0 then
		send(msg, prefix == "raid" and "RAID" or "PARTY")
		for i = 1, count do
			local name = UnitName(prefix .. i)
			if name then reached[name] = true end
		end
	end
	if not groupOnly then
		if IsInGuild() then
			send(msg, "GUILD")
			for i = 1, GetNumGuildMembers() do
				local name = GetGuildRosterInfo(i)
				if name then reached[name] = true end
			end
		end
		for i = 1, GetNumFriends() do
			local name, _, _, _, connected = GetFriendInfo(i)
			if name and connected and not reached[name] then send(msg, "WHISPER", name) end
		end
	end
end

-- A random ID made once and kept in saved data, which every character on the WoW account shares, so others can
-- tell which characters are one player's.
function Friends.AccountId()
	if not SC.db.accountId then
		SC.db.accountId = ("%08x%06x"):format(time() % 0x100000000, math.random(0, 0xffffff))
	end
	return SC.db.accountId
end

-- Records: name -> { class (token), level, counts = { account, TF, WF, LF, character, TF, WF, LF }, seen, own,
-- account (the sender's account ID) }.
local function store(name, class, level, counts, own, account)
	local rec = SC.db.friends[name] or { counts = {} }
	SC.db.friends[name] = rec
	rec.class, rec.level, rec.seen = class, tonumber(level) or 0, time()
	rec.own = own or rec.own or nil
	if account and account ~= "" then rec.account = account end
	for i = 1, 8 do rec.counts[i] = tonumber(counts[i]) or 0 end
	if Friends.onChange then Friends.onChange() end
	return rec
end

local accBuf, charBuf, both = {}, {}, {}

-- This character's status message, or nil while the counts can't be read. Stores this character's record too.
function Friends.Status()
	local msg
	if SC.Attuned.CanCount() and me() then
		SC.Attuned.Count(0, accBuf)
		SC.Attuned.Count(1, charBuf)
		for i = 1, 4 do both[i], both[i + 4] = accBuf[i], charBuf[i] end
		local _, class = UnitClass("player")
		local level = UnitLevel("player") or 0
		local account = Friends.AccountId()
		store(me(), class, level, both, true, account)
		msg = table.concat({ "S", VERSION, class or "", level, both[1], both[2], both[3], both[4], both[5], both[6],
			both[7], both[8], account }, ";")
	end
	return msg
end

-- Sends this character's status (if shared), and with hello asks everyone for theirs.
function Friends.SendStatus(hello, groupOnly)
	local status = SC.db.share and Friends.Status()
	if status then Friends.Broadcast(status, groupOnly) end
	if hello then
		Friends.Broadcast("H;" .. VERSION, groupOnly)
		if not groupOnly then Friends.helloAt = time() end
	end
end

-- Asks everyone again, at most once a minute; whether it asked.
function Friends.Refresh()
	local ask = not Friends.helloAt or time() - Friends.helloAt >= HELLO_COOLDOWN
	if ask then Friends.SendStatus(true) end
	return ask
end

-- One pending status send: the latest call's time wins, hello and groupOnly accumulate.
local timer = CreateFrame("Frame")
timer:Hide()
local statusAt, pendingHello, pendingGroupOnly = 0, false, true
timer:SetScript("OnUpdate", function(self)
	if GetTime() >= statusAt then
		self:Hide()
		local hello, groupOnly = pendingHello, pendingGroupOnly
		pendingHello, pendingGroupOnly = false, true
		Friends.SendStatus(hello, groupOnly)
	end
end)

function Friends.Schedule(delay, hello, groupOnly)
	statusAt = GetTime() + delay
	pendingHello = pendingHello or hello or false
	pendingGroupOnly = pendingGroupOnly and groupOnly or false
	timer:Show()
end

-- Item strings ("item:id:enchant:...") key queries: answers depend on the exact variant.
local function itemString(link)
	return link and link:match("|H(item:[%-%d:]+)|h")
end

local function itemId(str)
	return tonumber(str:match("^item:(%d+)"))
end

local function forgeOf(id)
	local forge
	if GetItemAttuneForge then
		forge = GetItemAttuneForge(id) or -1
	else
		forge = HasAttunedAnyVariantOfItem(id) and 0 or -1
	end
	return forge
end

-- Whether this character still needs an item variant: forge (best attuned, -1 none) and progress on this variant,
-- or nil when it doesn't.
function Friends.Need(str)
	local id = itemId(str)
	local forge, progress
	if id and SC.Attune.CanAttune({ id = id }) then
		local link = select(2, GetItemInfo(str)) or str
		forge = forgeOf(id)
		if GetItemLinkAttuneProgress then
			progress = GetItemLinkAttuneProgress(link) or 0
		else
			progress = forge >= 0 and 100 or 0
		end
	end
	if progress and progress < 100 then return forge, progress end
end

-- Asks who needs the item in a link, unless it was asked lately or nobody could attune it. Returns its item string.
function Friends.Ask(link)
	local str = itemString(link)
	local id = str and itemId(str)
	local attunable = id and (not IsAttunableBySomeone or IsAttunableBySomeone(id))
	if attunable then
		local q = Friends.queries[str] or { asked = 0, answers = {} }
		Friends.queries[str] = q
		if time() - q.asked >= QUERY_COOLDOWN then
			q.asked = time()
			Friends.Broadcast("Q;" .. VERSION .. ";" .. str)
		end
	end
	return attunable and str or nil
end

-- Who answered that they need an item variant, lately: { { name, forge, progress } } by name.
function Friends.Answers(str)
	local out = {}
	local q = Friends.queries[str]
	for name, a in pairs(q and q.answers or {}) do
		if time() - a.at < ANSWER_TTL then out[#out + 1] = { name = name, forge = a.forge, progress = a.progress } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- What an answer says, as a label: not attuned at all, or how far along this variant is.
function Friends.NeedText(forge, progress)
	local text
	if forge < 0 then
		text = "Not Attuned"
	elseif progress > 0 then
		text = ("This Variant %d%%"):format(progress)
	else
		text = "Needs This Variant"
	end
	return text
end

-- Tooltips: the item each one shows and the names already listed on it, so late answers are appended once.
local shown = {}

local function addAnswer(tt, entry, a)
	if not entry.header then
		entry.header = true
		tt:AddLine("Needed by Friends", 1, 0.77, 0)
	end
	entry.names[a.name] = true
	tt:AddDoubleLine(a.name, Friends.NeedText(a.forge, a.progress), 1, 1, 1, 0.7, 0.7, 0.7)
end

local function onTooltip(tt)
	local _, link = tt:GetItem()
	local str = Friends.Ask(link)
	local entry = shown[tt] or { names = {} }
	shown[tt] = entry
	entry.item, entry.header = str, false
	wipe(entry.names)
	if str then
		for _, a in ipairs(Friends.Answers(str)) do addAnswer(tt, entry, a) end
	end
end

local function onTooltipCleared(tt)
	local entry = shown[tt]
	if entry then entry.item = nil end
end

local function hookTooltip(tt)
	if tt then
		tt:HookScript("OnTooltipSetItem", onTooltip)
		tt:HookScript("OnTooltipCleared", onTooltipCleared)
	end
end
hookTooltip(GameTooltip)
hookTooltip(ItemRefTooltip)

local function answered(name, str, forge, progress)
	local q = Friends.queries[str]
	if q then
		q.answers[name] = { forge = tonumber(forge) or -1, progress = tonumber(progress) or 0, at = time() }
		for tt, entry in pairs(shown) do
			if entry.item == str and tt:IsShown() and not entry.names[name] then
				addAnswer(tt, entry, { name = name, forge = q.answers[name].forge, progress = q.answers[name].progress })
				tt:Show()
			end
		end
	end
end

-- When each player who asked for statuses was last answered, so asking over and over gets one answer a minute.
local repliedAt = {}

function Friends.Receive(prefix, msg, _, from)
	if prefix == PREFIX and from and from ~= me() then
		local f = { strsplit(";", msg) }
		local kind, version = f[1], f[2]
		if version == VERSION then
			if kind == "H" and SC.db.share and time() - (repliedAt[from] or 0) >= HELLO_COOLDOWN then
				local status = Friends.Status()
				if status then
					repliedAt[from] = time()
					send(status, "WHISPER", from)
				end
			elseif kind == "S" then
				store(from, f[3], f[4], { f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12] }, nil, f[13])
			elseif kind == "Q" and SC.db.share and f[3] then
				local forge, progress = Friends.Need(f[3])
				if forge then send(table.concat({ "N", VERSION, f[3], forge, progress }, ";"), "WHISPER", from) end
			elseif kind == "N" and f[3] then
				answered(from, f[3], f[4], f[5])
			end
		end
	end
end

-- Relations, closest first.
Friends.RELATION_ORDER = { You = 1, Alt = 2, Group = 3, Friend = 4, Guild = 5, [""] = 6 }

-- Whether character a should stand for its account over b: online first, then this character, then the latest.
local function shows(a, b)
	local result
	if a.online ~= b.online then
		result = a.online
	elseif (a.relation == "You") ~= (b.relation == "You") then
		result = a.relation == "You"
	else
		result = (a.seen or 0) > (b.seen or 0)
	end
	return result
end

-- One row per player: their characters that share an account ID (and all of this account's) merged under the one
-- online or seen last, with the others' names in `others`. A row's relation is the closest any of its characters
-- has (You, Alt, Group, Friend, Guild, or "" for someone heard from before); online if any of them is.
function Friends.Rows()
	local rows, byAccount, relations, player = {}, {}, Friends.Relations(), me()
	local order = Friends.RELATION_ORDER
	for name, rec in pairs(SC.db.friends) do
		local rel = relations[name]
		local relation, online
		if name == player then
			relation, online = "You", true
		elseif rec.own then
			relation, online = "Alt", false
		else
			relation, online = rel and rel.relation or "", rel and rel.online or false
		end
		local char = { name = name, class = rec.class, level = rec.level, counts = rec.counts, seen = rec.seen,
			relation = relation, online = online, own = rec.own, others = {} }
		local key = rec.own and "own" or rec.account or ("character:" .. name)
		local row = byAccount[key]
		if row and shows(char, row) then
			char.others, row.others = row.others, nil
			char.others[#char.others + 1] = row.name
			if order[row.relation] < order[char.relation] then char.relation = row.relation end
			char.online = char.online or row.online
			rows[row.index], char.index, byAccount[key] = char, row.index, char
		elseif row then
			row.others[#row.others + 1] = name
			if order[relation] < order[row.relation] then row.relation = relation end
		else
			char.index = #rows + 1
			rows[char.index], byAccount[key] = char, char
		end
	end
	for _, row in ipairs(rows) do table.sort(row.others) end
	return rows
end

-- Turns sharing on or off; turning it on sends this character's status at once.
function Friends.SetShare(on)
	SC.db.share = on and true or false
	if on then Friends.SendStatus(false) end
	SC:Print(on and "Friends, your guild and your group see your attunes and which items you need."
		or "Your attunes are no longer shared. You still see what others share.")
	if Friends.onChange then Friends.onChange() end
end

-- Forgets a row's player: every character merged into it.
function Friends.Forget(row)
	SC.db.friends[row.name] = nil
	for _, name in ipairs(row.others or {}) do SC.db.friends[name] = nil end
	if Friends.onChange then Friends.onChange() end
end

SC:OnLoad(function()
	local now = time()
	for name, rec in pairs(SC.db.friends) do
		if not rec.seen or now - rec.seen > FORGET_AFTER then SC.db.friends[name] = nil end
	end
	Friends.AccountId()
end)

local greeted, groupSize = false, 0
SC:On("PLAYER_ENTERING_WORLD", function()
	if not greeted then
		greeted = true
		if IsInGuild() then GuildRoster() end
		local _, count = groupUnits()
		groupSize = count
		Friends.Schedule(LOGIN_DELAY, true)
	end
end)

-- Someone joined the group: swap statuses with the group only.
local function groupChanged()
	local _, count = groupUnits()
	if count > groupSize and greeted then Friends.Schedule(GROUP_DELAY, true, true) end
	groupSize = count
end
SC:On("PARTY_MEMBERS_CHANGED", groupChanged)
SC:On("RAID_ROSTER_UPDATE", groupChanged)

-- A friend who comes online (Synastria's friends list follows the account, so also one switching characters) is
-- whispered this character's status and asked for theirs once their addons have loaded. The first friend list after
-- login only notes who's on, since the login hello reaches them; a friend who goes offline first isn't asked.
local onlineNow, onlineBefore, friendsKnown, askAt = {}, {}, false, {}
local asker = CreateFrame("Frame")
asker:Hide()
asker:SetScript("OnUpdate", function(self)
	local now, waiting = GetTime(), false
	for name, at in pairs(askAt) do
		if now >= at then
			askAt[name] = nil
			local status = SC.db.share and Friends.Status()
			if status then send(status, "WHISPER", name) end
			send("H;" .. VERSION, "WHISPER", name)
		else
			waiting = true
		end
	end
	if not waiting then self:Hide() end
end)

SC:On("FRIENDLIST_UPDATE", function()
	onlineNow, onlineBefore = onlineBefore, onlineNow
	wipe(onlineNow)
	for i = 1, GetNumFriends() do
		local name, _, _, _, connected = GetFriendInfo(i)
		if name and connected then
			onlineNow[name] = true
			if friendsKnown and not onlineBefore[name] then
				askAt[name] = GetTime() + ONLINE_DELAY
				asker:Show()
			end
		end
	end
	for name in pairs(askAt) do
		if not onlineNow[name] then askAt[name] = nil end
	end
	friendsKnown = true
end)

SC:On("CHAT_MSG_ADDON", Friends.Receive)

SC:OnCustomEvent("SYNASTRIA_ITEM_ATTUNED", function()
	Friends.Schedule(ATTUNED_DELAY, false)
end)
