local _, NS = ...
local SC = NS.SC

-- The character's perks, read and changed the way the game's Perk Manager does it. The server opens that window
-- with OpenPerkMgr(writeable): read-only from the View Perks spell, writable from an innkeeper's Manage Perks.
-- Activations need a writable session; options and chosen abilities change anywhere. A writable session keeps the
-- game's window shown, parked out of sight, so addons that check it (Synastria Build Suite) see the session.
local Perks = {}
SC.Perks = Perks

local FLAG_LOCKED, FLAG_SET_UNCOUNTED, FLAG_FORCED_UNLOCK, FLAG_ABILITY = 0x80, 0x800, 0x1000, 0x10000
local MAX_OPTION = 32
local MISC_CAT = 19

Perks.CLASS_NAMES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock",
	nil, "Druid" }

function Perks.HasData()
	return type(PerkMgrPerks) == "table" and next(PerkMgrPerks) ~= nil
end

function Perks.Rank(id)
	local rank = GetCustomGameData(1, id)
	return rank and rank > 0 and rank or nil
end

function Perks.Active(id)
	local on = GetCustomGameData(3, id)
	return on ~= nil and on >= 0.5
end

function Perks.Locked(perk)
	return bit.band(perk.flags or 0, FLAG_LOCKED) ~= 0
end

-- The limit index GetPerkLimit takes for a category (6 = Misc, no limit).
function Perks.LimitIndex(cat)
	local index = 0
	if cat == 15 then index = 1
	elseif cat == 16 then index = 2
	elseif cat == 17 then index = 3
	elseif cat == 18 then index = 4
	elseif cat == MISC_CAT then index = 6
	elseif (cat > 0 and cat <= 11) or cat == 13 then index = 5
	end
	return index
end

-- Each class's perks count on their own; category 13 counts with every class.
function Perks.SameCategory(a, b)
	return a ~= 0 and b ~= 0 and (a == b
		or (a == 13 and (b <= 11 or b == 13))
		or (b == 13 and a <= 11))
end

local function classMask()
	return CustomGetClassMask and CustomGetClassMask() or 0
end

-- The game's IsPerkHidden: perks for other classes, retired perks and ones the server hasn't offered.
function Perks.IsHidden(perk)
	local flags, req = perk.flags or 0, bit.band(perk.req or 0, 0x7FF)
	local wrongClass = false
	if bit.band(flags, 0x200) == 0 and req ~= 0 then
		if bit.band(flags, 0x8000) == 0 then
			wrongClass = bit.band(req, classMask()) == 0
		else
			wrongClass = bit.band(req, classMask()) ~= req
		end
	end
	return wrongClass
		or bit.band(flags, 0x400) ~= 0
		or (bit.band(flags, 0x4000) ~= 0 and GetCustomGameData(29, perk.id) == 0)
end

function Perks.ActiveCount(cat)
	local n = 0
	for i = 1, GetCustomGameDataCount(3) or 0 do
		local id = GetCustomGameDataIndex(3, i)
		local perk = id and id > 0 and PerkMgrPerks[id]
		if perk and Perks.Active(id) and Perks.SameCategory(cat, perk.cat) and not Perks.IsHidden(perk) then n = n + 1 end
	end
	return n
end

local function playerClass()
	return CustomGetClassId and CustomGetClassId() or 0
end

-- The categories the Perk Manager lists, in its order: { cat, label, limitIndex }. A character with two different
-- classes gets a class category for each.
function Perks.Categories()
	local list = {
		{ cat = 15, label = "Offensive" }, { cat = 16, label = "Defensive" }, { cat = 17, label = "Support" },
		{ cat = 18, label = "Utility" },
	}
	local first = playerClass()
	local second = CMCGetClassCount and CMCGetClassCount() >= 2 and not (CMCIsDualSingleClass and CMCIsDualSingleClass())
		and CMCGetClassAt and CMCGetClassAt(2) or 0
	local dual = second ~= 0 and second ~= first
	list[#list + 1] = { cat = first, label = dual and (Perks.CLASS_NAMES[first] or "Class") .. " Class" or "Class" }
	if dual then list[#list + 1] = { cat = second, label = (Perks.CLASS_NAMES[second] or "Class") .. " Class" } end
	list[#list + 1] = { cat = MISC_CAT, label = "Misc" }
	for _, c in ipairs(list) do c.limitIndex = Perks.LimitIndex(c.cat) end
	return list
end

-- The category's limit, or nil for Misc, which has none.
function Perks.Limit(cat)
	local index = Perks.LimitIndex(cat)
	return index ~= 6 and (GetPerkLimit and GetPerkLimit(index) or 0) or nil
end

-- The perks a category lists: not hidden, in the game's order (its sort group, then name).
function Perks.InCategory(cat)
	local list = {}
	for _, perk in pairs(PerkMgrPerks or {}) do
		if Perks.SameCategory(perk.cat, cat) and not Perks.IsHidden(perk) then list[#list + 1] = perk end
	end
	table.sort(list, function(a, b)
		if (a.sort or 0) ~= (b.sort or 0) then return (a.sort or 0) < (b.sort or 0) end
		return (a.name or ""):upper() < (b.name or ""):upper()
	end)
	return list
end

-- Sessions ---------------------------------------------------------------------------------------------------

local session = { writable = false }
Perks.session = session

function Perks.Writable()
	return session.writable and PerkMgrReadOnly == false
end

local function park(frame)
	if not session.parked then
		local point, rel, relPoint, x, y = frame:GetPoint()
		session.parked = { point = point, rel = rel, relPoint = relPoint, x = x, y = y, alpha = frame:GetAlpha() }
	end
	frame:SetAlpha(0)
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -200, -200)
end

local function unpark(frame)
	local saved = session.parked
	session.parked = nil
	frame:Hide()
	frame:ClearAllPoints()
	if saved and saved.point then
		frame:SetPoint(saved.point, saved.rel or UIParent, saved.relPoint, saved.x, saved.y)
	else
		frame:SetPoint("CENTER", 0, 0)
	end
	frame:SetAlpha(saved and saved.alpha or 1)
end

-- What the game's OpenPerkMgr(writeable) sets up, without showing its window unless the session is writable.
function Perks.Begin(writeable)
	PerkMgrReadOnly = not writeable
	session.writable = writeable and true or false
	local frame = PerkMgrFrame
	if frame and session.writable then
		park(frame)
		if UpdatePerkMgr then UpdatePerkMgr(true) end
		frame:Show()
	elseif frame and session.parked then
		unpark(frame)
	end
	if Perks.onChange then Perks.onChange() end
end

-- Ends a writable session: the parked window closes and goes back where it was.
function Perks.End()
	local frame = PerkMgrFrame
	if frame and session.parked then unpark(frame) end
	if session.writable then PerkMgrReadOnly = true end
	session.writable = false
	if Perks.onChange then Perks.onChange() end
end

-- Toggling --------------------------------------------------------------------------------------------------

-- Whether the perk can be turned on or off right now, and why not.
function Perks.CanToggle(perk)
	local reason
	if Perks.Locked(perk) then
		reason = "This perk can't be activated or deactivated."
	elseif not Perks.Writable() then
		reason = "Perks are activated and deactivated at an innkeeper: talk to one and pick Manage Perks."
	elseif not Perks.Active(perk.id) then
		local limit = Perks.Limit(perk.cat)
		if limit and Perks.ActiveCount(perk.cat) >= limit then
			reason = "This category is full. Deactivate another perk in it first."
		end
	end
	return reason == nil, reason
end

-- Turns the perk on or off, as the Perk Manager's Toggle button does. Returns whether it sent anything.
function Perks.Toggle(id)
	local perk = PerkMgrPerks and PerkMgrPerks[id]
	local ok = perk ~= nil and Perks.CanToggle(perk)
	if ok then
		if Perks.Active(id) then
			NotifyServer(2, 2, tostring(id))
			SetCustomGameData(3, id, 0)
		else
			NotifyServer(2, 1, tostring(id))
			SetCustomGameData(3, id, 1)
		end
		if UpdatePerkMgr then UpdatePerkMgr() end
		if Perks.onChange then Perks.onChange() end
	end
	return ok
end

-- Options and abilities --------------------------------------------------------------------------------------

-- The perk's options this character can use: toggles { index, name, tip, group, required, on } and action
-- buttons { index, name, tip, run }. A group's toggles are pick-one; a group of 256 or more always keeps one on.
function Perks.Options(id)
	local list = {}
	local perk = PerkMgrPerks and PerkMgrPerks[id]
	local info = perk and (perk.options or 0) ~= 0 and GetPerkOptionsInfo and GetPerkOptionsInfo(id)
	local have = GetCustomGameData(10, id) or 0
	for i = 1, info and MAX_OPTION or 0 do
		local opt = info[i]
		if opt and opt.n ~= "NULL" and (not opt.cond or opt.cond()) and (not opt.cl or CustomIsClass(opt.cl)) then
			if opt.b then
				list[#list + 1] = { index = i, name = opt.n, tip = opt.t, run = opt.b }
			else
				list[#list + 1] = { index = i, name = opt.n, tip = opt.t, group = opt.grp, required = (opt.grp or 0) >= 256,
					on = bit.band(have, bit.lshift(1, i - 1)) ~= 0 }
			end
		end
	end
	return list
end

function Perks.SetOption(id, index, on)
	return ChangePerkOption(id, index, on) == true
end

function Perks.HasAbility(perk)
	return bit.band(perk.flags or 0, FLAG_ABILITY) ~= 0
end

-- The ability chosen for the perk, or nil.
function Perks.Ability(id)
	local spell = GetCustomGameData(24, id)
	return spell and spell ~= 0 and spell or nil
end

-- Opens the game's ability picker; onPick runs once a choice is made.
function Perks.ChooseAbility(id, onPick)
	if OpenDruidSpec then OpenDruidSpec(id, function() if onPick then onPick() end end) end
end

-- Descriptions -----------------------------------------------------------------------------------------------

local DESC_COLORS = { text = "|cffffffff", symbol = "|cff8080ff", symbol2 = "|cffffffff" }

local function isDouble(perk)
	return IsPerkDouble ~= nil and IsPerkDouble(perk) == true
end

-- The perk's effect at a rank, built as the Perk Manager builds it (GeneratePerkDescription is local there).
function Perks.Description(id, rank)
	local perk = PerkMgrPerks[id]
	local level = perk and perk.levels and (perk.levels[rank] or perk.levels[1])
	local text
	if level and CustomGenerateDescription then
		local raw = (isDouble(perk) and level.amounts2 or level.amounts) or {}
		local amounts = {}
		for i = 1, 5 do
			amounts[i] = GetModifiedPerkValue and GetModifiedPerkValue(raw[i] or 0, id, i) or raw[i] or 0
		end
		amounts[6] = GetCustomGameData(29, id)
		text = CustomGenerateDescription(perk.desc or "", amounts, DESC_COLORS)
	end
	return text
end

function Perks.MaxRank(perk)
	return perk.levels and #perk.levels or 0
end

-- How the perk works with others, as the Perk Manager shows it under the effect.
function Perks.Synergy(id)
	return GetPerkSynergy and GetPerkSynergy(id, "|cffc0c0c0", "|cffc0c0c0", 1) or nil
end

-- The Perk Manager's "Additional information" notes, by perk.info bit (ProcessInfo is local there).
local INFO = {
	[0x1] = "This amount is based on your character level.",
	[0x8] = "Resource means mana, energy, rage, runic power or focus.",
	[0x10] = "Pets also include totems, minions and guardians.",
	[0x20] = "Slower weapons have higher chance to proc.",
	[0x40] = "Ally means party member or anyone you summoned.",
	[0x80] = "Enemy means anyone you are currently in combat with.",
	[0x100] = "Enemies with breakable crowd control effect are not targeted.",
	[0x200] = "This does not work in battlegrounds, arena or duel.",
	[0x400] = "This does not count as a healing effect.",
	[0x800] = "Effects that increase regeneration do not count as generating resources.",
	[0x1000] = "This effect does not stack.",
	[0x2000] = "Highest amount is selected at any given moment.",
	[0x4000] = "This effect does not cause any threat.",
	[0x8000] = "This doesn't work for pets.",
	[0x10000] = "This effect does not stack if applied from multiple characters.",
	[0x20000] = "Only applied when manually using the ability.",
	[0x40000] = "Same target can be chosen more than once.",
	[0x80000] = "Slower weapons have higher effect.",
	[0x100000] = "You need to have learned the ability for this effect to work.",
	[0x200000] = "This can not critically hit.",
	[0x400000] = "Ability means skill, spell, talent or item, but NOT perk.",
}
local CHANCE_NOTE = "Chance above 100 per-cent means it can happen more than once."

-- The class requirement line, green when the character has one of the classes.
local function requirement(perk)
	local req = bit.band(perk.req or 0, 0x7FF)
	local line
	if req ~= 0 and req ~= 0x7FF then
		local names = {}
		for id = 1, 11 do
			local name = Perks.CLASS_NAMES[id]
			if name and bit.band(req, bit.lshift(1, id - 1)) ~= 0 then names[#names + 1] = name end
		end
		table.sort(names)
		local text = names[#names]
		if #names > 1 then text = table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names] end
		line = (bit.band(req, classMask()) ~= 0 and "|cff40ff40" or "|cffff4040") .. "Requires " .. text .. ".|r"
	end
	return line
end

function Perks.Info(id, rank)
	local perk = PerkMgrPerks[id]
	local lines = {}
	local info = perk and perk.info or 0
	local level = perk and perk.levels and (perk.levels[rank or 1] or perk.levels[1])
	local amounts = level and (isDouble(perk) and level.amounts2 or level.amounts)
	for bitValue = 0, 22 do
		local flag = bit.lshift(1, bitValue)
		if flag == 2 then
			if bit.band(info, 2) ~= 0 or (bit.band(info, 4) ~= 0 and amounts and (amounts[1] or 0) > 100) then
				lines[#lines + 1] = CHANCE_NOTE
			end
		elseif bit.band(info, flag) ~= 0 and INFO[flag] then
			lines[#lines + 1] = INFO[flag]
		end
	end
	for _, x in ipairs(perk and GetPerkInfoInfo and GetPerkInfoInfo(id) or {}) do
		if x and x.t and x.t ~= "" then lines[#lines + 1] = x.t end
	end
	local req = perk and requirement(perk)
	if req then lines[#lines + 1] = req end
	return lines
end

-- Sets -------------------------------------------------------------------------------------------------------
-- PerkMgrSets[id] = { id, name, perks = { perk IDs }, bonus = { { count, desc, amounts, amounts2, perkid } } }.
-- Perks flagged 0x800 belong to a set but don't count toward its bonuses. A perk counts while it's on and learned.

local setOf, setOfSource

function Perks.SetOf(id)
	if PerkMgrSets and setOfSource ~= PerkMgrSets then
		setOf, setOfSource = {}, PerkMgrSets
		for _, set in pairs(PerkMgrSets) do
			for _, perkId in ipairs(set.perks or {}) do setOf[perkId] = set end
		end
	end
	return setOf and setOf[id]
end

function Perks.SetCounts(id)
	local perk = PerkMgrPerks[id]
	return perk ~= nil and bit.band(perk.flags or 0, FLAG_SET_UNCOUNTED) == 0
end

function Perks.InSet(id)
	return Perks.Active(id) and Perks.Rank(id) ~= nil
end

-- The set's counted perks sorted by name, and how many of them count now.
function Perks.SetMembers(set)
	local members, count = {}, 0
	for _, id in ipairs(set.perks or {}) do
		if Perks.SetCounts(id) then
			members[#members + 1] = id
			if Perks.InSet(id) then count = count + 1 end
		end
	end
	table.sort(members, function(a, b) return (PerkMgrPerks[a].name or ""):upper() < (PerkMgrPerks[b].name or ""):upper() end)
	return members, count
end

local SET_COLORS = {
	[true] = { text = "|cff60ff60", symbol = "|cff60ff60", symbol2 = "|cff60ff60" },
	[false] = { text = "|cff808080", symbol = "|cff808080", symbol2 = "|cff808080" },
}

-- Some bonuses scale with the share of extra ranks learned across the set's counted perks that are in.
local function rankScale(set)
	local learned, possible, any = 0, 0, false
	for _, id in ipairs(set.perks or {}) do
		local rank = Perks.SetCounts(id) and Perks.Active(id) and Perks.Rank(id)
		if rank then
			any = true
			learned = learned + (rank - 1)
			possible = possible + (Perks.MaxRank(PerkMgrPerks[id]) - 1)
		end
	end
	return learned > 0 and math.max(0, math.min(1, learned / possible)) or any and 1 or 0
end

-- The set's bonuses as { count, active, text }, built as the Perk Manager builds them (GenerateSetDescription is
-- local there): green when active, gray when not.
function Perks.SetBonuses(set)
	local _, count = Perks.SetMembers(set)
	local scale = rankScale(set)
	local out = {}
	for _, b in ipairs(set.bonus or {}) do
		if b.desc and b.desc ~= "" then
			local active = count >= (b.count or 0)
			local raw = (IsPerkDouble and IsPerkDouble(b.perkid, true) and b.amounts2 or b.amounts) or {}
			local amounts = {}
			for i = 1, 5 do amounts[i] = GetModifiedPerkValue(raw[i] or 0, b.perkid, i) end
			amounts[6] = scale
			local colors = SET_COLORS[active]
			out[#out + 1] = { count = b.count or 0, active = active,
				text = colors.text .. ("(%d) "):format(b.count or 0) .. CustomGenerateDescription(b.desc, amounts, colors) .. "|r" }
		end
	end
	local synergy = GetPerkSynergy and GetPerkSynergy(-set.id, "|cff808080", "|cff60ff60", count)
	if synergy then out[#out + 1] = { count = 0, active = false, text = synergy } end
	return out
end

-- Unlocking and upgrading ------------------------------------------------------------------------------------

local function progressMax(task)
	local flags = task.flags or 0
	local max
	if bit.band(flags, 0x80) ~= 0 then max = task.req3
	elseif bit.band(flags, 2) ~= 0 then max = task.req2
	else max = task.req0
	end
	return max or 1
end

local function taskText(task, guid)
	local text = task.text or "Unknown"
	local ref = text:match("^#(%d+)$")
	if ref then
		local other = PerkMgrTaskAll and PerkMgrTaskAll[tonumber(ref)]
		text = other and other.text and other.text ~= "" and other.text or "Unknown"
	end
	if text:find("$", 1, true) and CustomGenerateDescription then
		local colors = { text = "|cffffffff", symbol = "|cffff8080", symbol2 = "|cffffffff" }
		local amounts = { task.req0, task.req1, task.req2, task.req3, PerkMgrTaskStr and PerkMgrTaskStr[guid] or "(null)" }
		text = CustomGenerateDescription(text, amounts, colors)
	end
	return text
end

-- What the perk needs next: { unlock = true when not learned yet, text, progress, max, notes = { lines } }, or nil
-- at its top rank. Progress is left out for tasks the game doesn't count.
function Perks.Task(id)
	local perk = PerkMgrPerks[id]
	local rank = perk and Perks.Rank(id)
	local forced = perk and bit.band(perk.flags or 0, FLAG_FORCED_UNLOCK) ~= 0
	local guid = GetCustomGameData(6, id)
	local task, unlock
	if perk and (not rank or forced) then
		unlock = true
		task = PerkMgrTaskAll and perk.unlock and PerkMgrTaskAll[perk.unlock] or { text = "Unknown" }
	elseif perk and perk.levels[rank + 1] then
		local taskId = guid and GetCustomGameData(7, guid)
		task = taskId and PerkMgrTaskAll and PerkMgrTaskAll[taskId] or { text = "Unknown" }
	end
	local out
	if task then
		out = { unlock = unlock, text = taskText(task, guid), notes = {} }
		local flags = task.flags or 0
		if bit.band(flags, 0x1000) == 0 then
			out.progress = guid and GetCustomGameData(4, guid) or 0
			out.max = progressMax(task)
			if bit.band(flags, 0x10) ~= 0 then out.notes[#out.notes + 1] = "Only progresses in raids and heroic dungeons."
			elseif bit.band(flags, 0x20) ~= 0 then out.notes[#out.notes + 1] = "Only progresses in raids."
			end
			out.notes[#out.notes + 1] = "Doesn't progress at a target dummy."
			if not Perks.Active(id) then out.notes[#out.notes + 1] = "|cffff4040The perk must be on before the task progresses.|r" end
		end
	end
	return out
end

-- The task list the Perk Manager's Task List button shows: the tasks of perks that are on, grouped by task header,
-- each { header, name, party = party members on the same kind of task, perks = { { id, text, short, progress,
-- max } } }, the biggest groups first and Other last. Party-only groups are listed too.
function Perks.TaskList()
	local byHeader, groups = {}, {}
	local function group(header)
		local g = byHeader[header]
		if not g then
			local info = PerkMgrTaskHeader and PerkMgrTaskHeader[header]
			g = { header = header, name = header == 0 and "Other" or info and info.text or "Unknown",
				party = header ~= 0 and GetCustomGameData(9, header) or 0, perks = {},
				short = info and bit.band(info.flags or 0, 4) ~= 0 }
			byHeader[header] = g
			groups[#groups + 1] = g
		end
		return g
	end
	for i = 1, GetCustomGameDataCount(6) or 0 do
		local id = GetCustomGameDataIndex(6, i)
		local guid = id and GetCustomGameData(6, id)
		local taskId = guid and GetCustomGameData(7, guid)
		local task = taskId and PerkMgrTaskAll and PerkMgrTaskAll[taskId]
		local perk = PerkMgrPerks and PerkMgrPerks[id]
		if perk and task and task.header and task.header ~= 0 and Perks.Active(id) then
			local g = group(task.header)
			local entry = { id = id, text = taskText(task, guid) }
			if bit.band(task.flags or 0, 0x1000) == 0 then
				entry.progress, entry.max = GetCustomGameData(4, guid) or 0, progressMax(task)
			end
			if g.short then entry.short = (task.text or ""):match("%$c(.-)%$C") end
			g.perks[#g.perks + 1] = entry
		end
	end
	for i = 1, GetCustomGameDataCount(9) or 0 do
		local header = GetCustomGameDataIndex(9, i)
		if header and header > 0 and (GetCustomGameData(9, header) or 0) > 0 then group(header) end
	end
	for _, g in ipairs(groups) do
		table.sort(g.perks, function(a, b) return (PerkMgrPerks[a.id].name or ""):upper() < (PerkMgrPerks[b.id].name or ""):upper() end)
	end
	table.sort(groups, function(a, b)
		local sa, sb = #a.perks + a.party - (a.header == 0 and 999 or 0), #b.perks + b.party - (b.header == 0 and 999 or 0)
		if sa ~= sb then return sa > sb end
		return a.name < b.name
	end)
	return groups
end

-- The share of the current task done, 0 to 1, for the list's rank bar; 1 at the top rank, nil when not learned.
function Perks.Progress(id)
	local share
	local perk = PerkMgrPerks[id]
	local rank = perk and Perks.Rank(id)
	if rank then
		local task = Perks.Task(id)
		share = 1
		if task and not task.unlock and task.progress and task.max and task.max > 0 and task.progress < task.max then
			share = math.max(0, task.progress / task.max)
		end
	end
	return share
end
