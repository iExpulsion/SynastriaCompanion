local _, NS = ...
local SC = NS.SC

-- Transmog looks, read and changed the way the game's Transmog window does it. There are ten looks; each has a
-- name, the specs that switch it on, an appearance for each of 14 slots, and an enchant visual for each weapon
-- hand. One look is active at a time. Every change goes to the server at once.
local Transmog = {}
SC.Transmog = Transmog

Transmog.MAX = 10
Transmog.SPECS = 6
Transmog.SPELL = 80469
Transmog.NAME_MAX = 15

-- A slot or enchant visual's value: 0 keeps the equipped item's look, 1 hides it, anything else is an item (or
-- enchant) ID.
Transmog.EQUIPPED, Transmog.HIDDEN = 0, 1

local DATA, NAMES = 26, 27
local CMD = 8
local MAIN_HAND, OFF_HAND = 12, 13

-- filter: which picker filter the slot gets (armor type, main hand, off hand or ranged weapon type)
Transmog.SLOTS = {
	{ name = "HeadSlot", label = "Head", filter = "armor" },
	{ name = "ShoulderSlot", label = "Shoulders", filter = "armor" },
	{ name = "BackSlot", label = "Back" },
	{ name = "ChestSlot", label = "Chest", filter = "armor" },
	{ name = "ShirtSlot", label = "Shirt" },
	{ name = "TabardSlot", label = "Tabard" },
	{ name = "WristSlot", label = "Wrists", filter = "armor" },
	{ name = "HandsSlot", label = "Hands", filter = "armor" },
	{ name = "WaistSlot", label = "Waist", filter = "armor" },
	{ name = "LegsSlot", label = "Legs", filter = "armor" },
	{ name = "FeetSlot", label = "Feet", filter = "armor" },
	{ name = "MainHandSlot", label = "Main Hand", filter = "mainHand", enchant = 1 },
	{ name = "SecondaryHandSlot", label = "Off Hand", filter = "offHand", enchant = 2 },
	{ name = "RangedSlot", label = "Ranged", filter = "ranged" },
}
Transmog.MAIN_HAND, Transmog.OFF_HAND = MAIN_HAND, OFF_HAND

local WEAPONS = {
	{ value = 768 + 1, text = "One-Handed Axe" }, { value = 768 + 2, text = "Two-Handed Axe" },
	{ value = 768 + 5, text = "One-Handed Mace" }, { value = 768 + 6, text = "Two-Handed Mace" },
	{ value = 768 + 7, text = "Polearm" }, { value = 768 + 8, text = "One-Handed Sword" },
	{ value = 768 + 9, text = "Two-Handed Sword" }, { value = 768 + 11, text = "Staff" },
	{ value = 768 + 14, text = "Fist Weapon" }, { value = 768 + 16, text = "Dagger" },
	{ value = 768 + 21, text = "Fishing Pole" },
}

local function withAll(list, extra)
	local out = { { value = 0, text = "All" } }
	for _, o in ipairs(list) do out[#out + 1] = o end
	for _, o in ipairs(extra or {}) do out[#out + 1] = o end
	return out
end

-- The picker's type filter for each kind of slot, as the game's window offers it.
Transmog.FILTERS = {
	armor = withAll({ { value = 2, text = "Cloth" }, { value = 3, text = "Leather" }, { value = 4, text = "Mail" },
		{ value = 5, text = "Plate" } }),
	mainHand = withAll(WEAPONS),
	offHand = withAll(WEAPONS, { { value = 1280 + 1, text = "Held in Off Hand" }, { value = 1280 + 7, text = "Shield" } }),
	ranged = withAll({ { value = 768 + 3, text = "Bow" }, { value = 768 + 4, text = "Gun" },
		{ value = 768 + 17, text = "Thrown" }, { value = 768 + 19, text = "Crossbow" }, { value = 768 + 20, text = "Wand" } }),
}

-- Options shared by every look, as bits: 1 shows only the item being picked, 2 shows the race background, 4 lists
-- items that look the same as one already listed.
Transmog.NAKED, Transmog.BACKGROUND, Transmog.DUPLICATES = 1, 2, 4

local function get(key)
	return GetCustomGameData(DATA, key) or 0
end

local function send(sub, text)
	NotifyServer(CMD, sub, text)
end

local function changed()
	if Transmog.onChange then Transmog.onChange() end
end

-- Whether the server has sent the looks yet.
function Transmog.HasData()
	return GetCustomGameData(DATA, 1) ~= nil
end

-- The name filter and the duplicates option need a newer client patch.
function Transmog.HasSearch()
	return CLIENT_PATCH_VER ~= nil and CLIENT_PATCH_VER >= 25
end

function Transmog.Active()
	return get(1)
end

-- Makes the look active; 0 or nil turns transmog off.
function Transmog.Activate(id)
	local look = (type(id) == "number" and id >= 1 and id <= Transmog.MAX) and id or 0
	if look ~= Transmog.Active() then
		SetCustomGameData(DATA, 1, look)
		send(1, ("%d"):format(look))
		changed()
	end
end

function Transmog.Name(look)
	local name = GetCustomGameDataString(NAMES, look)
	return (name and name ~= "") and name or ("Transmog #" .. look)
end

-- Names lose their double quotes, which the server's command can't carry, and stop at 15 bytes.
function Transmog.Rename(look, name)
	local clean = (name or ""):gsub("\"", ""):sub(1, Transmog.NAME_MAX)
	if clean ~= (GetCustomGameDataString(NAMES, look) or "") then
		SetCustomGameDataString(NAMES, look, clean)
		send(3, ("%d \"%s\""):format(look, clean))
		changed()
	end
	return clean
end

-- Specs ------------------------------------------------------------------------------------------------------

function Transmog.SpecMask(look)
	return get(look * 100 + 1)
end

function Transmog.HasSpec(look, spec)
	return bit.band(Transmog.SpecMask(look), bit.lshift(1, spec - 1)) ~= 0
end

function Transmog.SetSpec(look, spec, on)
	local mask, flag = Transmog.SpecMask(look), bit.lshift(1, spec - 1)
	local new = on and bit.bor(mask, flag) or (bit.band(mask, flag) ~= 0 and mask - flag or mask)
	if new ~= mask then
		SetCustomGameData(DATA, look * 100 + 1, new)
		send(4, ("%d %d %d"):format(look, 0, new))
		changed()
	end
end

-- Slots and enchant visuals ----------------------------------------------------------------------------------

function Transmog.Slot(look, slot)
	return get(look * 100 + 10 + slot)
end

function Transmog.SetSlot(look, slot, value)
	if Transmog.Slot(look, slot) ~= value then
		SetCustomGameData(DATA, look * 100 + 10 + slot, value)
		send(4, ("%d %d %d"):format(look, slot, value))
		changed()
	end
end

-- hand: 1 main hand, 2 off hand
local function enchantKey(look, hand)
	return look * 100 + 3 + (hand - 1) * 2
end

function Transmog.Enchant(look, hand)
	return get(enchantKey(look, hand))
end

function Transmog.SetEnchant(look, hand, value)
	if Transmog.Enchant(look, hand) ~= value then
		SetCustomGameData(DATA, enchantKey(look, hand), value)
		send(4, ("%d %d %d"):format(look, 20 + (hand - 1) * 2, value))
		changed()
	end
end

-- Whether a chosen item applies: the account must have attuned it, or acquired it when it can't be attuned.
-- Inside Transmog.Batch the answers are remembered, since the set list asks about thousands of items per redraw.
local usableCache

function Transmog.Usable(value)
	local known = usableCache and usableCache[value]
	if known == nil then
		known = value <= Transmog.HIDDEN or (HasAttunedAnyVariantOfItem(value) and true or false)
			or (Custom_HasAcquiredItem ~= nil and Custom_HasAcquiredItem(value) and true or false)
		if usableCache then usableCache[value] = known end
	end
	return known
end

-- Runs fn with Usable's answers remembered until it returns.
function Transmog.Batch(fn)
	usableCache = {}
	local ok, err = pcall(fn)
	usableCache = nil
	if not ok then error(err, 0) end
end

-- The slots of the look that won't apply.
function Transmog.Unusable(look)
	local list = {}
	for slot in ipairs(Transmog.SLOTS) do
		if not Transmog.Usable(Transmog.Slot(look, slot)) then list[#list + 1] = slot end
	end
	return list
end

-- The equipped item in a slot, as an item ID and enchant ID (0 when none).
function Transmog.Equipped(slot)
	local link = GetInventoryItemLink("player", (GetInventorySlotInfo(Transmog.SLOTS[slot].name)))
	local id = link and CustomExtractItemId(link) or 0
	local enchant = link and CustomExtractItemEnchant and CustomExtractItemEnchant(link) or 0
	return id or 0, enchant or 0
end

-- Sets every slot to the item equipped in it, as the game's Import Equipped does.
function Transmog.UseEquipped(look)
	for slot in ipairs(Transmog.SLOTS) do
		local id = Transmog.Equipped(slot)
		if id ~= 0 and select(9, GetItemInfoCustom(id)) == "INVTYPE_RELIC" then id = 0 end
		Transmog.SetSlot(look, slot, Custom_FixupTransmogId and Custom_FixupTransmogId(id) or id)
	end
end

function Transmog.Reset(look)
	for slot in ipairs(Transmog.SLOTS) do Transmog.SetSlot(look, slot, Transmog.EQUIPPED) end
	for hand = 1, 2 do Transmog.SetEnchant(look, hand, Transmog.EQUIPPED) end
end

-- What a slot set to `value` shows, with `chosen` as its hand's enchant visual (weapons only): the item, or the
-- equipped one for Equipped Look, nil when hidden or empty, and the weapon's enchant visual.
local function appearance(slot, value, chosen)
	local id, enchant = nil, nil
	if value == Transmog.EQUIPPED then
		id, enchant = Transmog.Equipped(slot)
	elseif value ~= Transmog.HIDDEN then
		id = value
	end
	if Transmog.SLOTS[slot].enchant then
		if chosen == Transmog.HIDDEN then enchant = nil
		elseif chosen ~= Transmog.EQUIPPED then enchant = chosen
		elseif value ~= Transmog.EQUIPPED then enchant = select(2, Transmog.Equipped(slot))
		end
	else
		enchant = nil
	end
	return (id and id > 0) and id or nil, (enchant and enchant > 0) and enchant or nil
end

-- What the preview wears in a slot of the look.
function Transmog.Appearance(look, slot)
	local hand = Transmog.SLOTS[slot].enchant
	return appearance(slot, Transmog.Slot(look, slot), hand and Transmog.Enchant(look, hand))
end

-- Sharing ----------------------------------------------------------------------------------------------------

function Transmog.Export(look)
	return Custom_TransmogExport and Custom_TransmogExport(0, look) or nil
end

-- Reads a shared look into this one and sends the whole look to the server, as the game's Import does.
function Transmog.Import(look, text)
	local ok = Custom_TransmogExport ~= nil and Custom_TransmogExport(1, look, text) and true or false
	if ok then
		local values = { look, (GetCustomGameDataString(NAMES, look) or ""):gsub("\"", ""), get(look * 100 + 1) }
		for slot = 1, 14 do values[#values + 1] = get(look * 100 + 10 + slot) end
		for k = 3, 6 do values[#values + 1] = get(look * 100 + k) end
		send(2, ("%d \"%s\"" .. (" %d"):rep(19)):format(unpack(values)))
		changed()
	end
	return ok
end

-- Saved looks ------------------------------------------------------------------------------------------------

-- Looks kept for every character on the account, in the order the player put them. Each holds the game's export
-- string, which is what loads, and the slot and enchant values it had when saved, for previews and counts.
Transmog.SAVED_NAME_MAX = 40

function Transmog.SavedLooks()
	return SC.db.savedLooks
end

-- The saved looks by name, ignoring case.
function Transmog.SavedByName()
	local list = {}
	for i, saved in ipairs(SC.db.savedLooks) do list[i] = saved end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	return list
end

-- What a saved look shows in a slot, as it was when saved.
function Transmog.SavedAppearance(saved, slot)
	local hand = Transmog.SLOTS[slot].enchant
	local enchants = saved.enchants or {}
	return appearance(slot, (saved.slots or {})[slot] or Transmog.EQUIPPED, hand and (enchants[hand] or Transmog.EQUIPPED))
end

local function trim(text)
	return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Saves the look under `name` (the look's own name when blank). A saved look with the same name, in any case, is
-- replaced where it is. Returns the saved entry and whether it replaced one, or nil when the game can't export it.
function Transmog.SaveLook(look, name)
	local text = Transmog.Export(look)
	local saved, replaced = nil, false
	if text then
		local label = trim(name):sub(1, Transmog.SAVED_NAME_MAX)
		if label == "" then label = Transmog.Name(look) end
		saved = { name = label, text = text, slots = {}, enchants = {} }
		for slot in ipairs(Transmog.SLOTS) do saved.slots[slot] = Transmog.Slot(look, slot) end
		for hand = 1, 2 do saved.enchants[hand] = Transmog.Enchant(look, hand) end
		local list = SC.db.savedLooks
		local at = #list + 1
		for i, other in ipairs(list) do
			if other.name:lower() == label:lower() then
				at, replaced = i, true
				break
			end
		end
		list[at] = saved
		changed()
	end
	return saved, replaced
end

-- Loads a saved look into the look, replacing what it had.
function Transmog.LoadSaved(look, saved)
	return Transmog.Import(look, saved.text)
end

function Transmog.DeleteSaved(index)
	table.remove(SC.db.savedLooks, index)
	changed()
end

-- How many of the saved look's slots show an item, and how many of those the account can use.
function Transmog.SavedCount(saved)
	local usable, total = 0, 0
	for _, value in ipairs(saved.slots or {}) do
		if value ~= Transmog.EQUIPPED and value ~= Transmog.HIDDEN then
			total = total + 1
			if Transmog.Usable(value) then usable = usable + 1 end
		end
	end
	return usable, total
end

-- Options ----------------------------------------------------------------------------------------------------

function Transmog.Options()
	return get(2)
end

function Transmog.HasOption(flag)
	return bit.band(Transmog.Options(), flag) ~= 0
end

function Transmog.SetOption(flag, on)
	local opt = Transmog.Options()
	local new = on and bit.bor(opt, flag) or (bit.band(opt, flag) ~= 0 and opt - flag or opt)
	if new ~= opt then
		SetCustomGameData(DATA, 2, new)
		send(6, ("%d"):format(new))
		changed()
	end
end

-- Choices ----------------------------------------------------------------------------------------------------

-- The appearances the account can pick for a slot, from the game's own list: { value, owned }, with Equipped Look
-- and Hidden first. The game marks items the account hasn't attuned or acquired with a negative ID.
function Transmog.Choices(look, slot, filter, search)
	local list = {}
	local count = Custom_GetTransmogItem and Custom_GetTransmogItem(0, slot, Transmog.Slot(look, slot), filter or 0,
		Transmog.HasSearch() and search or "", Transmog.Options()) or 0
	for i = 1, count do
		local id = Custom_GetTransmogItem(1, i)
		if id then list[#list + 1] = { value = math.abs(id), owned = id >= 0 } end
	end
	return list
end

-- The enchant visuals the account can pick for a weapon hand: { value }, with Equipped Look and Hidden first.
function Transmog.EnchantChoices(look, hand)
	local list = {}
	local count = Custom_GetTransmogEnchant and Custom_GetTransmogEnchant(0, Transmog.Enchant(look, hand)) or 0
	for i = 1, count do
		local id = Custom_GetTransmogEnchant(1, i)
		if id then list[#list + 1] = { value = id, owned = true } end
	end
	return list
end

-- Item sets -------------------------------------------------------------------------------------------------
-- From Data/ItemSets.lua: { name, mask (0 = any class), armor (1 cloth .. 4 plate, 0 none), level,
-- pieces = { { id, slot } }, versions = { the set, then its recolors, each a set of its own } }. A slot can have
-- several items when copies of a piece share its look.

Transmog.ARMOR_TYPES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

local function pieceList(flat)
	local pieces = {}
	for i = 1, #flat, 2 do pieces[#pieces + 1] = { id = flat[i], slot = flat[i + 1] } end
	return pieces
end

local sets
function Transmog.Sets()
	if not sets then
		sets = {}
		for _, row in ipairs(NS.ItemSetData or {}) do
			local set = { name = row[1], mask = row[2], armor = row[3], level = row[4], pieces = pieceList(row[5]) }
			set.versions = { set }
			for _, v in ipairs(row[6] or {}) do
				set.versions[#set.versions + 1] = { name = v[1], mask = set.mask, armor = set.armor, level = v[2],
					pieces = pieceList(v[3]), base = set }
			end
			sets[#sets + 1] = set
		end
	end
	return sets
end

-- The version of a set with the most usable pieces; the set itself on a tie.
function Transmog.BestVersion(set)
	local best, bestCount = set, -1
	for _, version in ipairs(set.versions) do
		local usable = Transmog.SetCount(version)
		if usable > bestCount then best, bestCount = version, usable end
	end
	return best
end

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
	WARLOCK = 9, DRUID = 11 }
local BEST_ARMOR = { WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2 }

-- The character's classes as a mask; Synastria's dual-class characters have two.
function Transmog.ClassMask()
	local mask = CustomGetClassMask and CustomGetClassMask() or 0
	if mask == 0 then
		local _, token = UnitClass("player")
		mask = CLASS_BITS[token] and bit.lshift(1, CLASS_BITS[token] - 1) or 0
	end
	return mask
end

-- The heaviest armor any of the character's classes wears.
function Transmog.BestArmor()
	local best = 1
	for token, id in pairs(CLASS_BITS) do
		if bit.band(Transmog.ClassMask(), bit.lshift(1, id - 1)) ~= 0 then best = math.max(best, BEST_ARMOR[token] or 1) end
	end
	return best
end

function Transmog.SetForClass(set)
	return set.mask == 0 or bit.band(set.mask, Transmog.ClassMask()) ~= 0
end

-- The set's look, one piece per slot: the first item with that look the account can use, or the set's own piece.
-- { slot, id, usable, piece = the set's own item } in slot order. A slot lists the set's own piece first, then
-- every other item with the same look.
function Transmog.SetPieces(set)
	local bySlot, order = {}, {}
	for _, piece in ipairs(set.pieces) do
		local current = bySlot[piece.slot]
		if not current then
			order[#order + 1] = piece.slot
			bySlot[piece.slot] = { slot = piece.slot, id = piece.id, piece = piece.id, usable = Transmog.Usable(piece.id) }
		elseif not current.usable and Transmog.Usable(piece.id) then
			current.id, current.usable = piece.id, true
		end
	end
	table.sort(order)
	local list = {}
	for _, slot in ipairs(order) do list[#list + 1] = bySlot[slot] end
	return list
end

-- How many of the set's slots the account can use, out of how many it covers.
function Transmog.SetCount(set)
	local usable, total = 0, 0
	for _, piece in ipairs(Transmog.SetPieces(set)) do
		total = total + 1
		if piece.usable then usable = usable + 1 end
	end
	return usable, total
end

-- Puts the set's usable pieces into the look; slots the set doesn't cover, or only has unusable pieces for, keep
-- what they had. Returns how many pieces went in and how many were skipped.
function Transmog.ApplySet(look, set)
	local applied, skipped = 0, 0
	for _, piece in ipairs(Transmog.SetPieces(set)) do
		if piece.usable then
			Transmog.SetSlot(look, piece.slot, piece.id)
			applied = applied + 1
		else
			skipped = skipped + 1
		end
	end
	return applied, skipped
end

function Transmog.Changed()
	changed()
end
