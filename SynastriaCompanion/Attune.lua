local _, NS = ...
local SC = NS.SC

-- Attunable items: one scan of every item ID builds a cache of items someone on the account could attune, then
-- queries filter that cache instantly. The rules follow the game's Attunable Items window.
local Attune = { items = nil, scanning = false, progress = 0 }
SC.Attune = Attune

Attune.MODES = {
	{ value = 0, text = "Attunable (Char)", tooltip = "Items this character can attune and hasn't yet." },
	{ value = 4, text = "Attunable (Acc)", tooltip = "Items any class on the account can attune that nobody has yet." },
	{ value = 1, text = "Attuned (Char)", tooltip = "Items this character can attune that are already attuned." },
	{ value = 2, text = "Attuned (Acc)", tooltip = "Every attuned item." },
	{ value = 3, text = "All", tooltip = "Every item anyone on the account can attune." },
}
local CHAR_POOL = { [0] = true, [1] = true }
local UNATTUNED_ONLY = { [0] = true, [4] = true }
local ATTUNED_ONLY = { [1] = true, [2] = true }

-- Primary equip slot, label, and the other slots it covers.
Attune.SLOTS = {
	{ "INVTYPE_HEAD", "Head" }, { "INVTYPE_NECK", "Neck" }, { "INVTYPE_SHOULDER", "Shoulders" },
	{ "INVTYPE_BODY", "Shirt" }, { "INVTYPE_CHEST", "Chest", "INVTYPE_ROBE" }, { "INVTYPE_WAIST", "Waist" },
	{ "INVTYPE_LEGS", "Legs" }, { "INVTYPE_FEET", "Feet" }, { "INVTYPE_WRIST", "Wrists" },
	{ "INVTYPE_HAND", "Hands" }, { "INVTYPE_FINGER", "Finger" }, { "INVTYPE_TRINKET", "Trinket" },
	{ "INVTYPE_CLOAK", "Cloak" },
	{ "INVTYPE_WEAPON", "One-Hand", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" },
	{ "INVTYPE_2HWEAPON", "Two-Hand" }, { "INVTYPE_SHIELD", "Shield" }, { "INVTYPE_HOLDABLE", "Held in Off-Hand" },
	{ "INVTYPE_RANGED", "Ranged", "INVTYPE_THROWN", "INVTYPE_RANGEDRIGHT" }, { "INVTYPE_RELIC", "Relic" },
	{ "INVTYPE_TABARD", "Tabard" },
}
local slotOf, slotLabel = {}, {}
for _, s in ipairs(Attune.SLOTS) do
	slotLabel[s[1]] = s[2]
	for i = 1, #s do
		if i ~= 2 then slotOf[s[i]] = s[1] end
	end
end

function Attune.SlotLabel(equipLoc)
	return slotLabel[slotOf[equipLoc] or ""] or (equipLoc and _G[equipLoc]) or ""
end

Attune.RARITIES = {
	{ value = 0, text = "Poor" }, { value = 1, text = "Common" }, { value = 2, text = "Uncommon" },
	{ value = 3, text = "Rare" }, { value = 4, text = "Epic" }, { value = 5, text = "Legendary" },
	{ value = 6, text = "Heirloom and Other" },
}

Attune.FORGES = { [0] = "Attuned", "Titanforged", "Warforged", "Lightforged" }

local function band(a, b) return bit.band(a or 0, b) ~= 0 end

local function readItem(id)
	local name, _, quality, ilvl, req, _, _, _, equipLoc, icon = GetItemInfoCustom(id)
	local item
	if name then
		local tags1, tags2 = GetItemTagsCustom(id)
		item = { id = id, name = name, quality = quality or 1, ilvl = ilvl or 0, req = req or 0,
			equipLoc = equipLoc or "", icon = icon, disabled = band(tags1, 32), mythic = band(tags1, 128),
			affix = band(tags2, 1), prop = band(tags2, 8), tracksAffix = band(tags2, 16), bop = band(tags2, 0x80) }
		if item.affix then item.name = name .. " of the ..." end
		item.upper = item.name:upper()
	end
	return item
end

-- The cache holds thousands of items, so links (long strings) are looked up only when one is needed.
function Attune.Link(item)
	return select(2, GetItemInfoCustom(item.id))
end

local SCAN_PER_FRAME = 3000
local scanner = CreateFrame("Frame")
scanner:Hide()
local waiting = {}

-- Builds the cache over several frames, then calls every onDone. Calls it at once when the cache is ready.
function Attune.Scan(onDone)
	if Attune.items then
		if onDone then onDone() end
	else
		if onDone then waiting[#waiting + 1] = onDone end
		if not Attune.scanning then
			Attune.scanning = true
			local found, nextId, last = {}, 1, MAX_ITEMID or 0
			scanner:SetScript("OnUpdate", function(self)
				local stop = math.min(last, nextId + SCAN_PER_FRAME - 1)
				for id = nextId, stop do
					if IsAttunableBySomeone(id) then
						local item = readItem(id)
						if item then found[#found + 1] = item end
					end
				end
				nextId = stop + 1
				Attune.progress = last > 0 and stop / last or 1
				if nextId > last then
					self:Hide()
					Attune.items, Attune.scanning = found, false
					local done = waiting
					waiting = {}
					for _, fn in ipairs(done) do fn() end
				end
			end)
			scanner:Show()
		end
	end
end

-- Source types that are drops from a creature or object, as opposed to quests, vendors and crafting.
local DROPS = { [0] = true, [1] = true, [3] = true, [7] = true, [8] = true, [10] = true, [11] = true, [12] = true,
	[13] = true, [14] = true, [20] = true, [21] = true }
local SOURCES_PER_FRAME = 4000
local sourceReader = CreateFrame("Frame")
sourceReader:Hide()
local sourcesWaiting = {}
Attune.sourcesRead, Attune.sourcesReading, Attune.sourceProgress = false, false, 0

-- Whether the game's loot data is there to read sources from.
function Attune.HasLootData()
	return ItemLocIsLoaded ~= nil and (ItemLocIsLoaded() or 0) ~= 0 and ItemLocGetSourceAt ~= nil
end

-- Reads every cached item's sources over several frames into item.kind (dungeon, raid, world: places it drops) and
-- item.exp (expansions it comes from), then calls every onDone. Calls it at once when that's done already.
function Attune.ReadSources(onDone)
	if Attune.sourcesRead then
		if onDone then onDone() end
	else
		if onDone then sourcesWaiting[#sourcesWaiting + 1] = onDone end
		if not Attune.sourcesReading and Attune.items and Attune.HasLootData() then
			Attune.sourcesReading = true
			local items, index, src = Attune.items, 1, 1
			local ZoneInfo = SC.ZoneInfo
			sourceReader:SetScript("OnUpdate", function(self)
				local budget = SOURCES_PER_FRAME
				while budget > 0 and index <= #items do
					local item = items[index]
					local count = Attune.SourceCount(item)
					while src <= count and budget > 0 do
						local srcType, _, _, _, _, _, _, _, zone = ItemLocGetSourceAt(item.id, src)
						local kind, exp = ZoneInfo.Classify(zone)
						if exp then item.exp = bit.bor(item.exp or 0, exp) end
						if kind and DROPS[srcType] then item.kind = bit.bor(item.kind or 0, kind) end
						src, budget = src + 1, budget - 1
					end
					if src > count then
						item.exp = item.exp or ZoneInfo.ExpansionForLevel(item.req)
						item.kind = item.kind or 0
						index, src, budget = index + 1, 1, budget - 1
					end
				end
				Attune.sourceProgress = #items > 0 and (index - 1) / #items or 1
				if index > #items then
					self:Hide()
					Attune.sourcesRead, Attune.sourcesReading = true, false
					local done = sourcesWaiting
					sourcesWaiting = {}
					for _, fn in ipairs(done) do fn() end
				end
			end)
			sourceReader:Show()
		end
	end
end

-- Affixes: the game's affix list gives each affix bit a name, separately for suffixes ("of the Bear") and random
-- properties. byName[prop][name] = the bits with that name.
-- Index 52 ("of X Protection", "of X Resistance") is a stand-in for every resistance school that no item rolls;
-- the schools themselves are indexes 0 to 4.
local GROUPS = { [52] = { 0, 1, 2, 3, 4 } }
local byName, affixNames
local function affixTables()
	if not byName and ItemAttuneAffix then
		byName, affixNames = { [true] = {}, [false] = {} }, {}
		local seen = {}
		for _, afx in ipairs(ItemAttuneAffix) do
			for _, name in ipairs({ afx.name or false, afx.name2 or false }) do
				if name then
					local list = byName[afx.prop and true or false][name] or {}
					byName[afx.prop and true or false][name] = list
					for _, index in ipairs(GROUPS[afx.index] or { afx.index }) do list[#list + 1] = index end
					if not seen[name] then
						seen[name] = true
						affixNames[#affixNames + 1] = name
					end
				end
			end
		end
		table.sort(affixNames, function(a, b) return a:upper() < b:upper() end)
	end
	return byName, affixNames
end

-- Every affix name, sorted, for the affix picker.
function Attune.AffixNames()
	local _, names = affixTables()
	return names or {}
end

-- An item's affix masks at a forge level (0 base to 3 Lightforged), cached until something is attuned:
-- { possible1, possible2, has1, has2 }, or false for an item that doesn't track affixes.
local maskCache = { [0] = {}, {}, {}, {} }
local function masks(item, forge)
	local cache = maskCache[forge or 0]
	local m = cache[item.id]
	if m == nil then
		m = false
		if item.tracksAffix and GetItemAffixMask then
			local p1, p2, h1, h2 = GetItemAffixMask(bit.bor(item.id, bit.lshift(forge or 0, 24)))
			if p1 and p2 and (p1 ~= 0 or p2 ~= 0) then m = { p1, p2, h1 or 0, h2 or 0 } end
		end
		cache[item.id] = m
	end
	return m
end

local function affixLeftAt(m, index)
	local word = index < 32 and 1 or 2
	local b = bit.lshift(1, index % 32)
	return bit.band(m[word], b) ~= 0 and bit.band(m[word + 2], b) == 0
end

-- How many of an item's affixes aren't attuned yet at a forge level; nil for an item that doesn't track affixes.
function Attune.AffixesLeft(item, forge)
	local m = masks(item, forge)
	local left
	if m then
		left = 0
		for index = 0, 63 do
			if affixLeftAt(m, index) then left = left + 1 end
		end
	end
	return left
end

-- Whether an item can roll an affix (by name) that isn't attuned yet at a forge level.
function Attune.AffixOpen(item, name, forge)
	local m = masks(item, forge)
	local tables = affixTables()
	if m and tables then
		for _, index in ipairs(tables[item.prop and true or false][name] or {}) do
			if affixLeftAt(m, index) then return true end
		end
	end
	return false
end

-- Whether a class (nil: this character) can attune an item, cached per class.
local canCache = {}
function Attune.CanAttune(item, classId)
	local key = classId or 0
	local cache = canCache[key] or {}
	canCache[key] = cache
	local ok = cache[item.id]
	if ok == nil then
		ok = (CanAttuneItemHelperEx(item.id, classId) or 0) > 0
		cache[item.id] = ok
	end
	return ok
end

function Attune.IsAttuned(item)
	return HasAttunedAnyVariantOfItem(item.id) and true or false
end

function Attune.SourceCount(item)
	if item.sources == nil then
		item.sources = ItemLocGetSourceCount and ItemLocGetSourceCount(item.id) or 0
	end
	return item.sources
end

-- Index into Attune.FORGES for an attuned item, -1 for one that isn't.
function Attune.Forge(item)
	local forge = -1
	if item.attuned then forge = math.max(0, GetItemAttuneForge and GetItemAttuneForge(item.id) or 0) end
	return forge
end

-- Whether a mode can list attuned items, which is when the Forge column means something.
function Attune.ShowsAttuned(mode)
	return not UNATTUNED_ONLY[mode or 0]
end

local function tri(want, has)
	return want == nil or (want > 0) == has
end

-- Bit flags for the multi-choice filters; none set means any.
Attune.BOP, Attune.BOE = 1, 2
Attune.NOT_ATTUNED = 1

-- The mode an Attunement Level choice needs: attuned levels need a mode that lists attuned items (keeping Char or
-- Acc), Not Attuned needs one that lists unattuned items, and both need All. Any other mode is kept.
local TO_ATTUNED, TO_UNATTUNED = { [0] = 1, [4] = 2 }, { [1] = 0, [2] = 4 }
function Attune.ModeForLevel(mode, level)
	mode = mode or 0
	local attuned = bit.band(level or 0, 2 + 4 + 8 + 16) ~= 0
	local unattuned = bit.band(level or 0, Attune.NOT_ATTUNED) ~= 0
	if attuned and unattuned then mode = 3
	elseif attuned then mode = TO_ATTUNED[mode] or mode
	elseif unattuned then mode = TO_UNATTUNED[mode] or mode
	end
	return mode
end

-- The Attunement Level flag for an item: Not Attuned, or 2, 4, 8, 16 for Attuned through Lightforged.
local function levelFlag(item, isAttuned)
	local flag = Attune.NOT_ATTUNED
	if isAttuned then flag = bit.lshift(2, math.max(0, GetItemAttuneForge and GetItemAttuneForge(item.id) or 0)) end
	return flag
end

local function anyOf(mask, flags)
	return mask == nil or bit.band(mask, flags or 0) ~= 0
end

-- The affix filter: nil any, 1 has random affixes, -1 doesn't, "left" has affixes not attuned yet, or an affix name.
local function affixMatches(item, f)
	local want = f.affix
	local ok = true
	if want == "left" then ok = (Attune.AffixesLeft(item, f.affixForge) or 0) > 0
	elseif type(want) == "string" then ok = Attune.AffixOpen(item, want, f.affixForge)
	elseif want ~= nil then ok = tri(want, item.affix)
	end
	return ok
end

local function matches(item, f, isAttuned)
	local zone = f.zone and ALL_ZONE_LIST and ALL_ZONE_LIST[f.zone]
	return (f.rarity == nil or math.min(6, item.quality) == f.rarity)
		and (f.slot == nil or slotOf[item.equipLoc] == f.slot)
		and anyOf(f.bind, item.bop and Attune.BOP or Attune.BOE)
		and anyOf(f.kind, item.kind) and anyOf(f.exp, item.exp)
		and (f.level == nil or anyOf(f.level, levelFlag(item, isAttuned)))
		and tri(f.mythic, item.mythic) and affixMatches(item, f)
		and (f.sources == nil or tri(f.sources, Attune.SourceCount(item) > 5))
		and (f.minReq == nil or item.req >= f.minReq) and (f.maxReq == nil or item.req <= f.maxReq)
		and (f.minLvl == nil or item.ilvl >= f.minLvl) and (f.maxLvl == nil or item.ilvl <= f.maxLvl)
		and (zone == nil or ItemLocItemIsInZone(item.id, zone.v or 0xFFFF))
		and (f.nameUpper == nil or item.upper:find(f.nameUpper, 1, true) ~= nil)
end

-- The items a filter shows, plus the pool it was drawn from: { items, pool, attuned }. A disabled item counts only
-- once some variant of it is attuned, as in the game's window.
function Attune.Query(f)
	local out, pool, attuned = {}, 0, 0
	local mode = f.mode or 0
	f.nameUpper = (f.name and f.name ~= "") and f.name:upper() or nil
	for _, item in ipairs(Attune.items or {}) do
		local isAttuned = Attune.IsAttuned(item)
		if (isAttuned or not item.disabled) and (not CHAR_POOL[mode] or Attune.CanAttune(item, f.class))
			and matches(item, f, isAttuned) then
			pool = pool + 1
			if isAttuned then attuned = attuned + 1 end
			if not (UNATTUNED_ONLY[mode] and isAttuned) and not (ATTUNED_ONLY[mode] and not isAttuned) then
				item.attuned = isAttuned
				out[#out + 1] = item
			end
		end
	end
	return { items = out, pool = pool, attuned = attuned }
end

local SORT_KEYS = {
	name = function(i) return i.upper end,
	ilvl = function(i) return i.ilvl end,
	req = function(i) return i.req end,
	slot = function(i) return Attune.SlotLabel(i.equipLoc) end,
	sources = Attune.SourceCount,
	forge = Attune.Forge,
}

-- Sorts by the Affixes Left column at the filter's forge level; items without affixes go last.
function Attune.SetAffixSortForge(forge)
	SORT_KEYS.affixes = function(i) return Attune.AffixesLeft(i, forge) or -1 end
end
Attune.SetAffixSortForge(0)

-- Whether a filter needs the item sources read first.
function Attune.NeedsSources(f)
	return f.kind ~= nil or f.exp ~= nil
end

-- Sorts by a column, breaking ties by item level (highest first) and then name.
function Attune.Sort(items, key, desc)
	local get = SORT_KEYS[key] or SORT_KEYS.ilvl
	local values = {}
	for _, item in ipairs(items) do values[item] = get(item) end
	table.sort(items, function(a, b)
		local va, vb = values[a], values[b]
		if va ~= vb then
			if desc then return va > vb end
			return va < vb
		end
		if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
		return a.upper < b.upper
	end)
end

-- Attuning changes what each mode shows; the cache of items itself stays.
function Attune.Changed()
	for forge = 0, 3 do maskCache[forge] = {} end
	if Attune.onChange then Attune.onChange() end
end

-- Which items a character can attune depends on its level (armor types, for one).
SC:On("PLAYER_LEVEL_UP", function()
	canCache = {}
	Attune.Changed()
end)
SC:OnCustomEvent("SYNASTRIA_ITEM_ATTUNED", Attune.Changed)
SC:OnCustomEvent("SYNASTRIA_ITEM_ATTUNE_PCT_CHANGED", Attune.Changed)
