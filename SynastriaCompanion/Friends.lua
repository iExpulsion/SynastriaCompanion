local _, NS = ...
local SC = NS.SC

-- Friends: attune counts shared over addon messages whispered to friends, kept account-wide, and
-- asking them who still needs an item. Messages are fields joined by ";", the second the protocol version:
-- S is a status, R a status that asks for theirs back, H asks without one (sharing is off), Q asks who needs an
-- item (by item string), N is a whispered "I need it".
local Friends = { queries = {} }
SC.Friends = Friends

local PREFIX, VERSION = "SComp", "1"
local SEND_GAP = 1.1
local LOGIN_DELAY, ONLINE_DELAY, ATTUNED_DELAY = 5, 10, 30
local HOVER_DELAY, DONE_DELAY = 0.5, 2
local HELLO_COOLDOWN = 60
local QUERY_COOLDOWN, ANSWER_TTL = 120, 600
local FORGET_AFTER = 60 * 86400

Friends.HELLO_COOLDOWN = HELLO_COOLDOWN

local function me()
	return UnitName("player")
end

-- Outgoing messages, one per SEND_GAP. The server mutes a character's chat when too many addon messages (every
-- addon's together) reach it in a short time, so they go out one at a time. The frame runs only while something
-- waits. A message can carry the item string of the question it ends;
-- questionSent and questionDropped (set further down) hear when it goes out or is dropped.
local queue = {}
local questionSent, questionDropped
local sender = CreateFrame("Frame")
sender:Hide()
local lastSent = -math.huge
local BYTE_S, BYTE_R = ("S"):byte(), ("R"):byte()

-- When each player was last whispered this character's status (S or R, sent on its own or as an answer), so asking
-- within a minute of getting it goes unanswered.
local sharedAt = {}

sender:SetScript("OnUpdate", function(self)
	if GetTime() - lastSent >= SEND_GAP then
		local m = table.remove(queue, 1)
		if m then
			SendAddonMessage(PREFIX, m[1], m[2], m[3])
			lastSent = GetTime()
			local kind = m[1]:byte()
			if m[2] == "WHISPER" and (kind == BYTE_S or kind == BYTE_R) then sharedAt[m[3]] = time() end
			if m[4] then questionSent(m[4]) end
		end
		if #queue == 0 then self:Hide() end
	end
end)

local function send(msg, channel, target, lastOf)
	queue[#queue + 1] = { msg, channel, target, lastOf }
	sender:Show()
end

-- Drops waiting messages of one kind (the text before the first ";").
local function unqueue(kind)
	for i = #queue, 1, -1 do
		local m = queue[i]
		if m[1]:match("^[^;]*") == kind then
			table.remove(queue, i)
			if m[4] then questionDropped(m[4]) end
		end
	end
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

-- Whispers every online friend; the last whisper carries lastOf. Nothing goes to the guild or the group: most
-- guilds are a player's own alts, groups have other addons for this, and every message counts toward the server's
-- limit. knownOnly: just the friends whose Companion has sent a status before. Returns how many were queued.
function Friends.WhisperFriends(msg, lastOf, knownOnly)
	local count = 0
	for i = 1, GetNumFriends() do
		local name, _, _, _, connected = GetFriendInfo(i)
		local rec = name and SC.db.friends[name]
		if name and connected and (not knownOnly or (rec and not rec.own)) then
			send(msg, "WHISPER", name)
			count = count + 1
		end
	end
	if count > 0 then queue[#queue][4] = lastOf end
	return count
end

-- A random ID made once and kept in saved data, which every character on the WoW account shares, so others can
-- tell which characters are one player's.
function Friends.AccountId()
	if not SC.db.accountId then
		SC.db.accountId = ("%08x%06x"):format(time() % 0x100000000, math.random(0, 0xffffff))
	end
	return SC.db.accountId
end

-- Records: key -> { name, class (token), level, counts = { account, TF, WF, LF, character, TF, WF, LF }, seen, own,
-- account (the sender's account ID) }. Others are keyed by name, as their messages are; this account's own
-- characters by GUID, since they can share a name.
local function store(key, name, class, level, counts, own, account)
	local rec = SC.db.friends[key] or { counts = {} }
	SC.db.friends[key] = rec
	rec.name, rec.class, rec.level, rec.seen = name, class, tonumber(level) or 0, time()
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
		store(UnitGUID("player") or me(), me(), class, level, both, true, account)
		msg = table.concat({ "S", VERSION, class or "", level, both[1], both[2], both[3], both[4], both[5], both[6],
			both[7], both[8], account }, ";")
	end
	return msg
end

-- What asks someone for their status: this character's own status marked R when it's shared, else a bare H.
local function greeting()
	local status = SC.db.share and Friends.Status()
	return status and ("R" .. status:sub(2)) or ("H;" .. VERSION)
end

-- Whispers this character's status (if shared) to online friends; with hello the same message asks for theirs.
function Friends.SendStatus(hello)
	local msg
	if hello then
		msg = greeting()
		Friends.helloAt = time()
	else
		msg = SC.db.share and Friends.Status()
	end
	if msg then Friends.WhisperFriends(msg) end
end

-- Asks everyone again, at most once a minute; whether it asked.
function Friends.Refresh()
	local ask = not Friends.helloAt or time() - Friends.helloAt >= HELLO_COOLDOWN
	if ask then Friends.SendStatus(true) end
	return ask
end

-- One pending status send: the latest call's time wins, hello accumulates.
local timer = CreateFrame("Frame")
timer:Hide()
local statusAt, pendingHello = 0, false
timer:SetScript("OnUpdate", function(self)
	if GetTime() >= statusAt then
		self:Hide()
		local hello = pendingHello
		pendingHello = false
		Friends.SendStatus(hello)
	end
end)

function Friends.Schedule(delay, hello)
	statusAt = GetTime() + delay
	pendingHello = pendingHello or hello or false
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

-- Whether this account still needs an item variant: forge (best attuned, -1 none) and progress on this variant,
-- or nil when it doesn't. Attunes are account-wide, so this asks whether anyone could attune the item, not whether
-- the character playing now could.
function Friends.Need(str)
	local id = itemId(str)
	local forge, progress
	if id and (IsAttunableBySomeone and IsAttunableBySomeone(id) or SC.Attune.CanAttune({ id = id })) then
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

-- Tooltips: the item each one shows and the names already listed on it, so late answers are appended once.
local shown = {}

local function onScreen(str)
	for tt, entry in pairs(shown) do
		if entry.item == str and tt:IsShown() then return true end
	end
	return false
end

-- One pending question: it goes out once a tooltip has shown its item for HOVER_DELAY, so moving the mouse over a
-- bag full of items asks only about the one it stops on. A tooltip set again to the same item keeps the wait going.
-- A new question replaces older ones still waiting to go out, so hovering item after item at a vendor doesn't pile
-- them up.
local pendingQuery, queryAt = nil, 0
local finishQuestion
local querier = CreateFrame("Frame")
querier:Hide()
querier:SetScript("OnUpdate", function(self)
	if GetTime() >= queryAt then
		self:Hide()
		local str = pendingQuery
		pendingQuery = nil
		if str and onScreen(str) then
			local q = Friends.queries[str]
			q.asked = time()
			unqueue("Q")
			q.sentTo = Friends.WhisperFriends("Q;" .. VERSION .. ";" .. str, str, true)
			q.state = q.sentTo > 0 and "asking" or "done"
			if q.state == "done" then finishQuestion(str) end
		end
	end
end)

-- Asks who needs the item in a link, once its tooltip stays up, unless it was asked lately or nobody could attune
-- it. Returns its item string.
function Friends.Ask(link)
	local str = itemString(link)
	local id = str and itemId(str)
	local attunable = id and (not IsAttunableBySomeone or IsAttunableBySomeone(id))
	if attunable then
		local q = Friends.queries[str] or { asked = 0, answers = {} }
		Friends.queries[str] = q
		if time() - q.asked >= QUERY_COOLDOWN and pendingQuery ~= str then
			pendingQuery, queryAt = str, GetTime() + HOVER_DELAY
			querier:Show()
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

-- A question's progress, as tooltip labels: asking while it waits or is still being whispered, then how many
-- friends it reached.
local ASKING_TEXT, NO_FRIENDS_TEXT = "Asking Friends...", "No Friends with Companion Online"

local function askedText(q)
	local text = NO_FRIENDS_TEXT
	if q.sentTo > 0 then text = ("Asked %d %s"):format(q.sentTo, q.sentTo == 1 and "Friend" or "Friends") end
	return text
end

local function addStatus(tt, text)
	tt:AddLine(text, 0.6, 0.6, 0.6)
end

local function addDone(tt, entry, q)
	entry.done = true
	addStatus(tt, askedText(q))
end

-- Questions whose last whisper went out, done once DONE_DELAY has passed so quick answers land above the line.
local finishing = {}
local finisher = CreateFrame("Frame")
finisher:Hide()

finishQuestion = function(str)
	local q = Friends.queries[str]
	q.state = "done"
	for tt, entry in pairs(shown) do
		if entry.item == str and tt:IsShown() and not entry.done then
			addDone(tt, entry, q)
			tt:Show()
		end
	end
end

finisher:SetScript("OnUpdate", function(self)
	local now, waiting = GetTime(), false
	for str, at in pairs(finishing) do
		if now >= at then
			finishing[str] = nil
			finishQuestion(str)
		else
			waiting = true
		end
	end
	if not waiting then self:Hide() end
end)

questionSent = function(str)
	finishing[str] = GetTime() + DONE_DELAY
	finisher:Show()
end

-- A question cut short by a newer one can be asked again in full.
questionDropped = function(str)
	local q = Friends.queries[str]
	q.state, q.asked = nil, 0
end

local function addAnswer(tt, entry, a)
	if not entry.header then
		entry.header = true
		tt:AddLine("Needed by Friends", 1, 0.77, 0)
	end
	entry.names[a.name] = true
	tt:AddDoubleLine(a.name, Friends.NeedText(a.forge, a.progress), 1, 1, 1, 0.7, 0.7, 0.7)
end

-- Whether the tooltip shows an item nobody else could be given: soulbound, account bound or a quest item, unless
-- it's still inside its loot trade window.
local function bound(tt)
	local name = tt:GetName()
	local trade = BIND_TRADE_TIME_REMAINING and BIND_TRADE_TIME_REMAINING:match("^(.-)%%s")
	local found, tradable = false, false
	for i = 2, tt:NumLines() do
		local region = _G[name .. "TextLeft" .. i]
		local text = region and region:GetText()
		if text then
			found = found or text == ITEM_SOULBOUND or text == ITEM_ACCOUNTBOUND or text == ITEM_BIND_QUEST
			tradable = tradable or (trade ~= nil and trade ~= "" and text:find(trade, 1, true) == 1)
		end
	end
	return found and not tradable
end

-- Any item set on the tooltip starts it over; only items the player holds ask (showAsk, from the Set* hooks below,
-- which run after the client has set the item and so after this).
local function onTooltip(tt)
	local entry = shown[tt] or { names = {} }
	shown[tt] = entry
	entry.item, entry.header, entry.done = nil, false, false
	wipe(entry.names)
end

-- An item the player holds (bags, bank or guild bank) that could still be given away asks who needs it, and the
-- tooltip lists the question's progress and answers.
local function showAsk(tt, link)
	local str = SC.db.askItems and link and not bound(tt) and Friends.Ask(link) or nil
	local entry = shown[tt]
	if str and entry then
		entry.item = str
		local q = Friends.queries[str]
		local asking = pendingQuery == str or q.state == "asking"
		if asking then addStatus(tt, ASKING_TEXT) end
		for _, a in ipairs(Friends.Answers(str)) do addAnswer(tt, entry, a) end
		if not asking and q.state == "done" then addDone(tt, entry, q) end
		tt:Show()
	end
end

local function onTooltipCleared(tt)
	local entry = shown[tt]
	if entry then entry.item = nil end
end

-- Bags, the bank's main slots (-1) and bank bags; not the keyring.
local function onBagItem(tt, bag, slot)
	local held = bag and bag >= -1 and bag <= (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7)
	showAsk(tt, held and GetContainerItemLink(bag, slot) or nil)
end

-- The stock bank frame shows its main slots as inventory slots 40 to 67.
local function onInventoryItem(tt, unit, slot)
	local first = (BANK_CONTAINER_INVENTORY_OFFSET or 39) + 1
	local bank = unit == "player" and slot and slot >= first and slot < first + (NUM_BANKGENERIC_SLOTS or 28)
	showAsk(tt, bank and GetInventoryItemLink("player", slot) or nil)
end

local function onGuildBankItem(tt, tab, slot)
	showAsk(tt, tab and slot and GetGuildBankItemLink(tab, slot) or nil)
end

GameTooltip:HookScript("OnTooltipSetItem", onTooltip)
GameTooltip:HookScript("OnTooltipCleared", onTooltipCleared)
hooksecurefunc(GameTooltip, "SetBagItem", onBagItem)
hooksecurefunc(GameTooltip, "SetInventoryItem", onInventoryItem)
hooksecurefunc(GameTooltip, "SetGuildBankItem", onGuildBankItem)

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

-- Friends who came online, by when to ask them for their status. Their own login hello usually arrives first and
-- gets an answer, which drops the ask.
local askAt = {}

local function reply(from)
	askAt[from] = nil
	local status = SC.db.share and time() - (sharedAt[from] or 0) >= HELLO_COOLDOWN and Friends.Status()
	if status then
		sharedAt[from] = time()
		send(status, "WHISPER", from)
	end
end

-- Messages from the guild and group channels come from members (older versions still send there); a whisper counts
-- only from a friend, a guildmate or someone in the group, so strangers can't add rows or make this character
-- answer them.
function Friends.Receive(prefix, msg, channel, from)
	local known = from and (channel ~= "WHISPER" or Friends.Relations()[from] ~= nil)
	if prefix == PREFIX and known and from ~= me() then
		local f = { strsplit(";", msg) }
		local kind, version = f[1], f[2]
		if version == VERSION then
			if kind == "H" then
				reply(from)
			elseif kind == "S" or kind == "R" then
				store(from, from, f[3], f[4], { f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12] }, nil, f[13])
				if kind == "R" then reply(from) end
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
	local rows, byAccount, relations, guid = {}, {}, Friends.Relations(), UnitGUID("player")
	local order = Friends.RELATION_ORDER
	for key, rec in pairs(SC.db.friends) do
		local name = rec.name or key
		local rel = not rec.own and relations[name]
		local relation, online
		if rec.own and key == guid then
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
	SC:Print(on and "Your friends see your attunes and which items you need."
		or "Your attunes are no longer shared. You still see what others share.")
	if Friends.onChange then Friends.onChange() end
end

-- Turns asking who needs an item on or off; turning it off drops a question not yet sent. Sharing answers others'
-- questions either way.
function Friends.SetAskItems(on)
	SC.db.askItems = on and true or false
	if not on then
		pendingQuery = nil
		unqueue("Q")
	end
	SC:Print(on and "Item tooltips show which of your friends still need the item."
		or "Item tooltips no longer ask who needs the item. Others can still ask you.")
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
	for key, rec in pairs(SC.db.friends) do
		-- own characters used to be keyed by name, which same-named characters shared
		local stale = rec.own and not rec.name
		if stale or not rec.seen or now - rec.seen > FORGET_AFTER then SC.db.friends[key] = nil end
	end
	Friends.AccountId()
end)

local greeted = false
SC:On("PLAYER_ENTERING_WORLD", function()
	if not greeted then
		greeted = true
		if IsInGuild() then GuildRoster() end
		Friends.Schedule(LOGIN_DELAY, true)
	end
end)

-- A friend who comes online (Synastria's friends list follows the account, so also one switching characters) is
-- whispered this character's status and asked for theirs once their addons have loaded. The first friend list after
-- login only notes who's on, since the login hello reaches them; a friend who goes offline first isn't asked.
local onlineNow, onlineBefore, friendsKnown = {}, {}, false
local asker = CreateFrame("Frame")
asker:Hide()
asker:SetScript("OnUpdate", function(self)
	local now, waiting = GetTime(), false
	for name, at in pairs(askAt) do
		if now >= at then
			askAt[name] = nil
			send(greeting(), "WHISPER", name)
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
