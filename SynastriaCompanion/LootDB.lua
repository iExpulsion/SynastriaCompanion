local _, NS = ...
local SC = NS.SC

-- Loot Database data: item search, where an item comes from, and what a creature or object drops, read from
-- Synastria's item source data, plus tracking a source on the map.
local LootDB = {}
SC.LootDB = LootDB

function LootDB.Available()
	local loaded = ItemLocIsLoaded and ItemLocIsLoaded()
	return loaded ~= nil and loaded ~= false and loaded ~= 0
end

-- What each source type is, and how a row of it is tracked or opened: track = what to track on the map (0 creature,
-- 1 object, 2 quest), item = the source is an item to open, loot = its loot can be listed (as that object type).
LootDB.TYPES = {
	[0] = { label = "Drop", track = 0, loot = 0 },
	[1] = { label = "Container", track = 1, loot = 1 },
	[2] = { label = "Quest", track = 2 },
	[3] = { label = "Contained In", item = true },
	[4] = { label = "Special" },
	[5] = { label = "Trainer", track = 0 },
	[6] = { label = "Recipe", item = true },
	[7] = { label = "Fishing" },
	[8] = { label = "Fishing Pool", track = 1, loot = 1 },
	[9] = { label = "Vendor", track = 0 },
	[10] = { label = "Milling", item = true },
	[11] = { label = "Prospecting", item = true },
	[12] = { label = "Disenchant" },
	[13] = { label = "Skinning", track = 0, loot = 0 },
	[14] = { label = "Pickpocket", track = 0, loot = 0 },
	[15] = { label = "Achievement" },
	[16] = { label = "Special NPC", track = 0 },
	[17] = { label = "Special Object", track = 1 },
	[18] = { label = "Special Item", item = true },
	[19] = { label = "Player" },
	[20] = { label = "Mythic Drop", track = 0, loot = 0 },
	[21] = { label = "Mythic Container", track = 1, loot = 1 },
}

function LootDB.TypeLabel(srcType)
	local t = LootDB.TYPES[srcType]
	return t and t.label or "Other"
end

local function trimZeros(text)
	if text:find(".", 1, true) then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text
end

-- A drop chance as the game shows it: "N/A" over 100, then whole numbers from 10%, one decimal from 1%, two below.
function LootDB.ChanceText(ch)
	local text
	if not ch or ch > 100.5 then
		text = "N/A"
	elseif ch <= 0 then
		text = "0%"
	elseif ch >= 100 then
		text = "100%"
	else
		local raw = ch >= 10 and ("%d"):format(ch) or ch >= 1 and ("%.1f"):format(ch) or ("%.2f"):format(ch)
		text = (raw == "0.00" and "~0.01" or trimZeros(raw)) .. "%"
	end
	return text
end

function LootDB.PerText(per)
	local text
	if not per or per <= 0 then
		text = "~0"
	else
		local raw = per >= 10 and ("%d"):format(per) or per >= 1 and ("%.1f"):format(per) or ("%.2f"):format(per)
		text = raw == "0.00" and "~0.01" or trimZeros(raw)
	end
	return text
end

local function itemEntry(id)
	local name, link, quality, ilvl, _, class, subclass, _, equipLoc, icon = GetItemInfoCustom(id)
	return { id = id, name = (name and name ~= "") and name or "Unknown Item", link = link, quality = quality or 1,
		ilvl = ilvl or 0, kind = (subclass and subclass ~= "") and subclass or class or "", equipLoc = equipLoc,
		icon = icon }
end
LootDB.Item = itemEntry

-- Placeholder items the game hides from its search.
local function hidden(id)
	return id >= 63680 and id <= 63710
end

-- Items whose name contains text.
function LootDB.Search(text)
	local out = {}
	if text and text ~= "" then
		Custom_SetItemSelectFilter(text)
		for i = 1, Custom_GetItemSelectCount() or 0 do
			local id = Custom_GetItemSelect(i) or 0
			if id > 0 and not hidden(id) then out[#out + 1] = itemEntry(id) end
		end
	end
	return out
end

-- A quest for the other faction, or nil; with a faction note ("Horde", "Alliance") for one-faction quests.
local function questFaction(questId)
	local bad, note = false, nil
	local q = Custom_GetQuestData and Custom_GetQuestData(questId)
	if q then
		if bit.band(q, 12) ~= 4 then
			bad = true
		else
			local side = bit.band(q, 3)
			note = side == 2 and "Horde" or side == 1 and "Alliance" or nil
		end
	end
	return bad, note
end

-- Where an item comes from, leaving out sources with no known zone and quests for the other faction.
function LootDB.Sources(itemId)
	local out = {}
	for i = 1, ItemLocGetSourceCount(itemId) or 0 do
		local srcType, objType, objId, chance, per, name, zone, spawns, zid = ItemLocGetSourceAt(itemId, i)
		local bad, faction = false, nil
		if objType == 2 then bad, faction = questFaction(objId) end
		if srcType and zone and zone ~= "" and zone ~= "?" and not bad then
			out[#out + 1] = { srcType = srcType, objType = objType, objId = objId, chance = chance or 0,
				per = per or 0, name = name or "?", zone = zone, spawns = spawns, zid = zid, faction = faction }
		end
	end
	return out
end

local function fixup(objType, objId)
	return ItemLocFixupObjId and ItemLocFixupObjId(objType, objId) or objId
end

-- What a creature (objType 0) or object (1) drops.
function LootDB.Drops(objType, objId)
	local out = {}
	local id = fixup(objType, objId)
	for i = 1, ItemLocGetObjCount(objType, id) or 0 do
		local srcType, itemId, chance, per = ItemLocGetObjAt(objType, id, i)
		if srcType and itemId and itemId > 0 then
			local entry = itemEntry(itemId)
			entry.srcType, entry.chance, entry.per = srcType, chance or 0, per or 0
			out[#out + 1] = entry
		end
	end
	return out
end

function LootDB.HasDrops(objType, objId)
	return (ItemLocGetObjCount(objType, fixup(objType, objId)) or 0) > 0
end

-- The creature ID of a unit, or nil for players and pets.
function LootDB.UnitNpcId(unit)
	local guid = UnitGUID(unit)
	local id = guid and not UnitIsPlayer(unit) and tonumber(guid:sub(-11, -7), 16)
	return (id and id > 0) and id or nil
end

function LootDB.CanTrack(source)
	local t = LootDB.TYPES[source.srcType]
	return t ~= nil and t.track ~= nil
end

-- Asks the server to show a source on the map.
function LootDB.Track(source)
	local t = LootDB.TYPES[source.srcType]
	if t and t.track then NotifyServer(12, t.track, ("%d"):format(source.objId)) end
end

function LootDB.IsAttunable(id)
	return CanAttuneItemHelper ~= nil and (CanAttuneItemHelper(id) or 0) > 0
end

function LootDB.IsAttuned(id)
	return HasAttunedAnyVariantOfItem ~= nil and HasAttunedAnyVariantOfItem(id) and true or false
end

-- An item ID from a number, an item link or an item name, or nil.
function LootDB.ResolveItem(item)
	local id
	if type(item) == "number" then
		id = item
	elseif type(item) == "string" then
		id = CustomExtractItemId and CustomExtractItemId(item)
		if (not id or id == 0) and Custom_GetItemIdFromName then id = Custom_GetItemIdFromName(item) end
	end
	return (id and id > 0) and id or nil
end
