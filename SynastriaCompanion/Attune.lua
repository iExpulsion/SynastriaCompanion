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
	local name, link, quality, ilvl, req, _, _, _, equipLoc, icon = GetItemInfoCustom(id)
	local item
	if name then
		local tags1, tags2 = GetItemTagsCustom(id)
		item = { id = id, name = name, link = link, quality = quality or 1, ilvl = ilvl or 0, req = req or 0,
			equipLoc = equipLoc or "", icon = icon, disabled = band(tags1, 32), mythic = band(tags1, 128),
			affix = band(tags2, 1) }
		if item.affix then item.name = name .. " of the ..." end
		item.upper = item.name:upper()
	end
	return item
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

-- 0..100 for an item not yet attuned.
function Attune.Progress(item)
	return GetItemAttuneProgress and GetItemAttuneProgress(item.id) or 0
end

local function tri(want, has)
	return want == nil or (want > 0) == has
end

local function matches(item, f)
	local zone = f.zone and ALL_ZONE_LIST and ALL_ZONE_LIST[f.zone]
	return (f.rarity == nil or math.min(6, item.quality) == f.rarity)
		and (f.slot == nil or slotOf[item.equipLoc] == f.slot)
		and tri(f.affix, item.affix) and tri(f.mythic, item.mythic)
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
			and matches(item, f) then
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
	status = function(i) return i.attuned and 101 or Attune.Progress(i) end,
}

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
	if Attune.onChange then Attune.onChange() end
end

-- Which items a character can attune depends on its level (armor types, for one).
SC:On("PLAYER_LEVEL_UP", function()
	canCache = {}
	Attune.Changed()
end)
SC:OnCustomEvent("SYNASTRIA_ITEM_ATTUNED", Attune.Changed)
SC:OnCustomEvent("SYNASTRIA_ITEM_ATTUNE_PCT_CHANGED", Attune.Changed)
