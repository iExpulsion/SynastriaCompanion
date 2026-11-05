local _, NS = ...
local SC = NS.SC

-- Stats from attuned items, as the server sends them (ItemAttuneStats) when the View Attuned Items spell is cast:
-- nine categories, each with a count, whether it's active for this character, and its stats. They're summed here
-- into Misc, the character's armor type and Weapon, plus what's attuned but inactive.
local Attuned = {}
SC.Attuned = Attuned

Attuned.SPELL = 80189

-- category index -> column
local KIND = { "misc", "misc", "armor", "armor", "armor", "armor", "armor", "weapon", "weapon" }
local ARMOR_NAMES = { [3] = "Cloth", [4] = "Leather", [5] = "Mail", [6] = "Plate" }

Attuned.STAT_ORDER = { 1, 0, 7, 5, 4, 3, 6, 45, 38, 39, 12, 13, 14, 15, 31, 32, 36, 35, 37, 44, 43, 46, 47, 48, 49, 50,
	51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62 }
Attuned.STAT_NAMES = {
	[0] = "Mana", [1] = "Health", [3] = "Agility", [4] = "Strength", [5] = "Intellect", [6] = "Spirit",
	[7] = "Stamina", [12] = "Defense Rating", [13] = "Dodge Rating", [14] = "Parry Rating", [15] = "Block Rating",
	[31] = "Hit Rating", [32] = "Crit Rating", [35] = "Resilience Rating", [36] = "Haste Rating",
	[37] = "Expertise Rating", [38] = "Attack Power", [39] = "Ranged Attack Power", [43] = "Mana Regen",
	[44] = "Armor Penetration", [45] = "Spell Power", [46] = "Health Regen", [47] = "Spell Penetration",
	[48] = "Block Value", [49] = "Armor", [50] = "Holy Resistance", [51] = "Fire Resistance",
	[52] = "Nature Resistance", [53] = "Frost Resistance", [54] = "Shadow Resistance", [55] = "Arcane Resistance",
	[56] = "Physical Power", [57] = "Holy Power", [58] = "Fire Power", [59] = "Nature Power", [60] = "Frost Power",
	[61] = "Shadow Power", [62] = "Arcane Power",
}

function Attuned.HasData()
	local stats = ItemAttuneStats
	return type(stats) == "table" and next(stats) ~= nil
end

local function newColumn(label)
	return { label = label, count = 0, stats = {} }
end

local function add(column, data)
	column.count = column.count + (data.count or 0)
	for stat, value in pairs(data.stats or {}) do
		column.stats[stat] = (column.stats[stat] or 0) + value
	end
end

-- { misc, armor, weapon, inactive, total } columns, each { label, count, stats = { [stat] = value } }, plus
-- rows: the stats any column has, in the game's order, each { stat, name, order }.
function Attuned.Read()
	local cols = { misc = newColumn("Misc"), armor = newColumn("Armor"), weapon = newColumn("Weapon"),
		inactive = newColumn("Inactive"), total = newColumn("Total") }
	local stats = Attuned.HasData() and ItemAttuneStats or {}
	for i = 1, #KIND do
		local data = stats[i]
		if data then
			if data.valid then
				add(cols[KIND[i]], data)
				add(cols.total, data)
				if ARMOR_NAMES[i] then cols.armor.label = ARMOR_NAMES[i] end
			else
				add(cols.inactive, data)
			end
		end
	end
	local rows = {}
	for order, stat in ipairs(Attuned.STAT_ORDER) do
		local any = false
		for _, col in pairs(cols) do
			if (col.stats[stat] or 0) ~= 0 then any = true end
		end
		if any then rows[#rows + 1] = { stat = stat, name = Attuned.STAT_NAMES[stat] or ("Stat " .. stat), order = order } end
	end
	return cols, rows
end

-- The macro that asks the server for the stats: casting View Attuned Items.
function Attuned.RequestMacro()
	return "/cast " .. (GetSpellInfo(Attuned.SPELL) or "View Attuned Items")
end

function Attuned.Received()
	Attuned.receivedAt = time()
	if Attuned.onChange then Attuned.onChange() end
end
