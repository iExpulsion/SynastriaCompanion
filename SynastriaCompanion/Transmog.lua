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
function Transmog.Usable(value)
	return value <= Transmog.HIDDEN or (HasAttunedAnyVariantOfItem(value) and true or false)
		or (Custom_HasAcquiredItem ~= nil and Custom_HasAcquiredItem(value) and true or false)
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

-- What the preview wears in a slot: the look's item, or the equipped one for Equipped Look, nil when hidden or
-- empty. Weapons also get their enchant visual.
function Transmog.Appearance(look, slot)
	local value = Transmog.Slot(look, slot)
	local id, enchant = nil, nil
	if value == Transmog.EQUIPPED then
		id, enchant = Transmog.Equipped(slot)
	elseif value ~= Transmog.HIDDEN then
		id = value
	end
	local hand = Transmog.SLOTS[slot].enchant
	if hand then
		local chosen = Transmog.Enchant(look, hand)
		if chosen == Transmog.HIDDEN then enchant = nil
		elseif chosen ~= Transmog.EQUIPPED then enchant = chosen
		elseif value ~= Transmog.EQUIPPED then enchant = select(2, Transmog.Equipped(slot))
		end
	else
		enchant = nil
	end
	return (id and id > 0) and id or nil, (enchant and enchant > 0) and enchant or nil
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

function Transmog.Changed()
	changed()
end
