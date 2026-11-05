local _, NS = ...
local SC = NS.SC

-- Synastria's loot filter: rules checked top to bottom, the first that matches deciding what happens to an item.
-- Edits go to a draft; Apply writes the whole filter at once, as the game's Lootfilter window does. Turning a rule
-- on or off and the options take effect at once when nothing else is pending.
local LF = { MAX_RULES = 32, MAX_CONDITIONS = 8 }
SC.LootFilter = LF

LF.MATCH = {
	{ value = 0, text = "All Conditions", tooltip = "Every condition must be true." },
	{ value = 1, text = "Any Condition", tooltip = "At least one condition must be true." },
	{ value = 2, text = "First and Any Other", tooltip = "The first condition and at least one of the others must be true." },
}
LF.ACTIONS = {
	{ value = 3, text = "Loot" }, { value = 4, text = "Loot to Bag 2" }, { value = 5, text = "Loot to Bag 3" },
	{ value = 6, text = "Loot to Bag 4" }, { value = 7, text = "Loot to Bag 5" },
	{ value = 0, text = "Don't Loot" },
	{ value = 1, text = "Disenchant, Sell or Destroy" }, { value = 2, text = "Sell or Destroy" },
}
LF.OPS = {
	[0] = "Is Not", [1] = "Is", [2] = "Has Any", [3] = "Has None", [4] = ">", [5] = "<", [6] = ">=", [7] = "<=",
}
LF.OPTIONS = {
	{ bit = 0x1, text = "Auto Loot", tooltip = "Loot by the filter at all. Off turns every other option off too." },
	{ bit = 0x2, text = "Enemies" }, { bit = 0x4, text = "Herbalism" }, { bit = 0x8, text = "Mining" },
	{ bit = 0x10, text = "Skinning" }, { bit = 0x20, text = "Herbalism, Mining and Engineering on Enemies" },
	{ bit = 0x40, text = "Chests" },
	{ bit = 0x80, text = "Send to Resource Bank", tooltip = "Send looted materials the bank takes straight to it." },
	{ bit = 0x100, text = "Show Destroyed Messages" },
	{ bit = 0x200, text = "Don't Destroy Items", tooltip = "Leave items the filter would destroy in the corpse." },
	{ bit = 0x400, text = "Apply to Lockboxes" }, { bit = 0x800, text = "Apply to Clams" },
}

-- Value kinds: none, yes/no, number, one choice, several choices (a bit mask), item, zone. ops is the allowed
-- operators as a bit mask.
local NONE, YESNO, NUMBER, CHOICE, MASK, ITEM, ZONE = "none", "yesno", "number", "choice", "mask", "item", "zone"
LF.KINDS = { NONE = NONE, YESNO = YESNO, NUMBER = NUMBER, CHOICE = CHOICE, MASK = MASK, ITEM = ITEM, ZONE = ZONE }

local function opts(list)
	local out = {}
	for i = 1, #list, 2 do out[#out + 1] = { value = list[i], text = list[i + 1] } end
	return out
end

local CLASSES = opts({ 1, "Warrior", 2, "Paladin", 4, "Hunter", 8, "Rogue", 0x10, "Priest", 0x20, "Death Knight",
	0x40, "Shaman", 0x80, "Mage", 0x100, "Warlock", 0x400, "Druid" })

local VALUES = {
	[0] = { kind = NONE, ops = 0 },
	[1] = { kind = YESNO, ops = 0 },
	[2] = { kind = NUMBER, ops = 0xF3 },
	[3] = { kind = MASK, ops = 0xC, options = CLASSES },
	[4] = { kind = CHOICE, ops = 0x3, options = opts({ 0, "None", 1, "Pickup", 2, "Equip", 3, "Use" }) },
	[5] = { kind = CHOICE, ops = 0xF3, options = opts({ 0, "Poor", 1, "Common", 2, "Uncommon", 3, "Rare", 4, "Epic",
		5, "Legendary", 7, "Heirloom" }) },
	[6] = { kind = CHOICE, ops = 0xF3, options = opts({ 0, "None", 1, "Titanforged", 2, "Warforged", 3, "Lightforged" }) },
	[7] = { kind = MASK, ops = 0xC, options = opts({ 1, "Consumable", 2, "Container", 4, "Weapon", 8, "Gem", 0x10, "Armor",
		0x20, "Reagent", 0x40, "Ammo", 0x80, "Trade Goods", 0x100, "Generic", 0x200, "Recipe", 0x400, "Currency",
		0x800, "Quiver", 0x1000, "Quest", 0x2000, "Key", 0x8000, "Misc", 0x10000, "Glyph" }) },
	[8] = { kind = MASK, ops = 0xC, options = opts({ 1, "Consumable", 2, "Potion", 4, "Elixir", 8, "Flask", 0x10, "Scroll",
		0x20, "Food", 0x40, "Item Enhancement", 0x80, "Bandage", 0x100, "Other" }) },
	[9] = { kind = MASK, ops = 0xC, options = opts({ 1, "Normal", 2, "Soul Shard", 4, "Herbalism", 8, "Enchanting",
		0x10, "Engineering", 0x20, "Jewelcrafting", 0x40, "Mining", 0x80, "Leatherworking", 0x100, "Inscription" }) },
	[10] = { kind = MASK, ops = 0xC, options = opts({ 1, "One-Handed Axe", 2, "Two-Handed Axe", 4, "Bow", 8, "Gun",
		0x10, "One-Handed Mace", 0x20, "Two-Handed Mace", 0x40, "Polearm", 0x80, "One-Handed Sword",
		0x100, "Two-Handed Sword", 0x400, "Staff", 0x2000, "Fist Weapon", 0x4000, "Misc", 0x8000, "Dagger",
		0x10000, "Thrown", 0x40000, "Crossbow", 0x80000, "Wand", 0x100000, "Fishing Pole" }) },
	[11] = { kind = MASK, ops = 0xC, options = opts({ 1, "Red", 2, "Blue", 4, "Yellow", 8, "Purple", 0x10, "Green",
		0x20, "Orange", 0x40, "Meta", 0x80, "Simple", 0x100, "Prismatic" }) },
	[12] = { kind = MASK, ops = 0xC, options = opts({ 1, "Misc", 2, "Cloth", 4, "Leather", 8, "Mail", 0x10, "Plate",
		0x40, "Shield", 0x80, "Libram", 0x100, "Idol", 0x200, "Totem", 0x400, "Sigil" }) },
	[13] = { kind = MASK, ops = 0xC, options = opts({ 4, "Arrow", 8, "Bullet" }) },
	[14] = { kind = MASK, ops = 0xC, options = opts({ 1, "Trade Goods", 2, "Parts", 4, "Explosives", 8, "Devices",
		0x10, "Jewelcrafting", 0x20, "Cloth", 0x40, "Leather", 0x80, "Metal & Stone", 0x100, "Meat", 0x200, "Herb",
		0x400, "Elemental", 0x800, "Other", 0x1000, "Enchanting", 0x2000, "Material", 0x4000, "Armor Enhancement",
		0x8000, "Weapon Enhancement" }) },
	[15] = { kind = MASK, ops = 0xC, options = opts({ 1, "Book", 2, "Leatherworking", 4, "Tailoring", 8, "Engineering",
		0x10, "Blacksmithing", 0x20, "Cooking", 0x40, "Alchemy", 0x80, "First Aid", 0x100, "Enchanting", 0x200, "Fishing",
		0x400, "Jewelcrafting" }) },
	[16] = { kind = MASK, ops = 0xC, options = opts({ 1, "Junk", 2, "Reagent", 4, "Pet", 8, "Event", 0x10, "Other",
		0x20, "Mount" }) },
	[17] = { kind = MASK, ops = 0xC, options = opts({ 0x1, "Head", 0x2, "Neck", 0x4, "Shoulder", 0x8, "Shirt",
		0x10, "Chest", 0x20, "Waist", 0x40, "Legs", 0x80, "Feet", 0x100, "Wrist", 0x200, "Hands", 0x400, "Finger",
		0x800, "Trinket", 0x1000, "Main Hand", 0x4000, "Ranged", 0x8000, "Cloak", 0x10000, "Two-Handed",
		0x20000, "Tabard", 0x40000, "Off-Hand", 0x80000, "Relic" }) },
	[18] = { kind = CHOICE, ops = 0x3, options = opts({ 2, "Mining", 3, "Skinning", 4, "Herbalism", 5, "Enemy", 7, "Chest",
		9, "Mining, Herbalism or Engineering on an Enemy", 10, "Clam or Spell", 11, "Lockbox" }) },
	[19] = { kind = ITEM, ops = 0x3 },
	[20] = { kind = ZONE, ops = 0x3 },
	[21] = { kind = ITEM, ops = 0x40 },
	[22] = { kind = ITEM, ops = 0x80 },
}

-- Condition types: id, label, value type, tooltip.
LF.CONDITIONS = {}
local function cond(id, name, vtype, tooltip)
	LF.CONDITIONS[#LF.CONDITIONS + 1] = { id = id, name = name, vtype = vtype, tooltip = tooltip }
end
cond(0, "Anything", 0, "Always true.")
cond(1, "Attunable (Character)", 1, "This character can attune it and hasn't yet.")
cond(2, "Attunable (Account)", 1, "Some character on the account can attune it and nobody has yet.")
cond(3, "Required Level", 2)
cond(4, "Item Level", 2)
cond(5, "Attunable for Class", 3, "A class can attune it. Doesn't check whether it's attuned already.")
cond(6, "Binding", 4)
cond(7, "Goes in Resource Bank", 1)
cond(8, "Quest Item", 1, "Marked as a quest item. Some quests ask for items that aren't.")
cond(9, "Count in Bags", 2, "How many of this exact item you carry. Each affix counts as its own item.")
cond(10, "Rarity", 5)
cond(11, "Is Learnable", 1, "Teaches something, like a recipe or a mount.")
cond(12, "Is Learned", 1, "You already know what it teaches.")
cond(13, "Allowed for My Class", 1)
cond(14, "Allowed for My Race", 1)
cond(15, "Starts a Quest", 1)
cond(16, "Is Consumable", 1)
cond(17, "Is Equipment", 1)
cond(18, "Is Mythic", 1)
cond(19, "Forged", 6)
cond(20, "Specific Item", 19)
cond(21, "Is Attuned", 1, "This item with this affix at this forge level is attuned.")
cond(22, "Any Affix Attuned", 1, "This item at this forge level is attuned with any affix.")
cond(23, "Contains Loot", 1, "Opens for loot, like a lockbox or a raid bag.")
cond(24, "Item Type", 7)
cond(25, "Consumable Type", 8)
cond(26, "Container Type", 9)
cond(27, "Weapon Type", 10)
cond(28, "Gem Type", 11)
cond(29, "Armor Type", 12)
cond(30, "Ammo Type", 13)
cond(31, "Trade Goods Type", 14)
cond(32, "Recipe Type", 15)
cond(33, "Misc Type", 16)
cond(34, "Glyph Class", 3)
cond(35, "Equip Slot", 17)
cond(36, "Looting From", 18, "How you're looting right now.")
cond(37, "Looting From ID", 2, "The ID of what you're looting right now.")
cond(38, "Attunable by Anyone", 1, "Anyone can attune it at all. Doesn't check whether it's attuned.")
cond(39, "Is Armor Token", 1, "A token a vendor takes for armor.")
cond(40, "Has Resistance Affix", 1)
cond(41, "Is Key", 1)
cond(42, "Zone", 20)
cond(43, "Bounty", 2)
cond(44, "Is Affix Item", 1, "Has a random affix, like \"of the Bear\".")
cond(45, "Specific Item or Higher ID", 21, "This item, or any with a higher ID.")
cond(46, "Specific Item or Lower ID", 22, "This item, or any with a lower ID.")
table.sort(LF.CONDITIONS, function(a, b) return a.name < b.name end)
local byId = {}
for _, c in ipairs(LF.CONDITIONS) do byId[c.id] = c end

function LF.Condition(id)
	return byId[id]
end

-- The value type of a condition type.
function LF.Value(condId)
	local c = byId[condId]
	return VALUES[c and c.vtype or 0] or VALUES[0]
end

-- The operators a condition type allows, in order, as { value, text }.
function LF.Ops(condId)
	local out, mask = {}, LF.Value(condId).ops
	for op = 0, 7 do
		if bit.band(mask, 2 ^ op) ~= 0 then out[#out + 1] = { value = op, text = LF.OPS[op] } end
	end
	return out
end

-- A condition of a new type, keeping the operator when the new type allows it.
function LF.Retype(c, condId)
	local ops = LF.Ops(condId)
	local keep = false
	for _, o in ipairs(ops) do
		if o.value == c.op then keep = true end
	end
	c.type = condId
	c.op = keep and c.op or (ops[1] and ops[1].value or 0)
	c.value = 0
end

-- Server data --------------------------------------------------------------------------------------------------

function LF.Available()
	return Custom_GetLootFilter ~= nil and Custom_GetLootFilter() ~= nil
end

local DISABLED = 0x80

-- The filter as the server has it: { options, rules = { { type, enabled, outcome, notify, name, cond, index } } }.
function LF.Read()
	local count, options = Custom_GetLootFilter()
	local filter = { options = options or 0, rules = {} }
	for i = 1, count or 0 do
		local rtype, condCount, outcome, notify, name = Custom_GetLootFilterRule(i)
		if rtype then
			local rule = { type = bit.band(rtype, 0x7F), enabled = bit.band(rtype, DISABLED) == 0, outcome = outcome or 0,
				notify = notify or 0, name = name or "", cond = {}, index = i }
			for j = 1, condCount or 0 do
				local ctype, op, value = Custom_GetLootFilterRuleEntry(i, j)
				if ctype then rule.cond[#rule.cond + 1] = { type = ctype, op = op or 0, value = value or 0 } end
			end
			filter.rules[#filter.rules + 1] = rule
		end
	end
	return filter
end

local WRITE_ERRORS = { [1] = "Not an allowed comparison", [2] = "Value is too big", [3] = "Comparison doesn't fit the value" }

-- Writes a whole filter. Returns nil, or { rule, cond, message } for the first condition the server refuses, in
-- which case nothing is saved.
function LF.Write(filter)
	for i, rule in ipairs(filter.rules) do
		for j, c in ipairs(rule.cond) do
			local err = Custom_SetLootFilterRuleEntry(i, j, c.type, c.op, c.value)
			if err then return { rule = i, cond = j, message = WRITE_ERRORS[err] or ("Error " .. tostring(err)) } end
		end
		local rtype = rule.enabled and rule.type or bit.bor(rule.type, DISABLED)
		Custom_SetLootFilterRule(i, rtype, #rule.cond, rule.outcome, rule.notify or 0, rule.name or "")
	end
	Custom_SetLootFilter(#filter.rules, filter.options or 0)
	for i, rule in ipairs(filter.rules) do rule.index = i end
	-- the game's own window keeps a copy; this makes it read the new one
	if UpdateLootFilter then UpdateLootFilter() end
	return nil
end

function LF.SetEnabledNow(serverIndex, on)
	Custom_SetLootFilterRuleEnabled(serverIndex, on and 1 or 0)
end

function LF.SetOptionsNow(mask)
	Custom_SetLootFilterOptions(mask)
end

-- The applied filter as the game's share string, or nil.
function LF.Export()
	return Custom_LootFilterExport and Custom_LootFilterExport()
end

function LF.ExportRule(serverIndex)
	return Custom_LootFilterExportRule and Custom_LootFilterExportRule(serverIndex)
end

-- Replaces the whole filter with a share string. True when the game took it.
function LF.Import(text)
	return Custom_LootFilterImport ~= nil and Custom_LootFilterImport(text) and true or false
end

function LF.ImportRule(serverIndex, text)
	return Custom_LootFilterImportRule ~= nil and Custom_LootFilterImportRule(serverIndex, text) and true or false
end

function LF.ResetToDefault()
	Custom_LootFilterResetToDefault()
end

function LF.NewRule()
	return { type = 0, enabled = true, outcome = 3, notify = 0, name = "New Rule", cond = { { type = 0, op = 0, value = 0 } } }
end

function LF.Copy(filter)
	local out = { options = filter.options, rules = {} }
	for i, r in ipairs(filter.rules) do
		local rule = { type = r.type, enabled = r.enabled, outcome = r.outcome, notify = r.notify, name = r.name,
			index = r.index, cond = {} }
		for j, c in ipairs(r.cond) do rule.cond[j] = { type = c.type, op = c.op, value = c.value } end
		out.rules[i] = rule
	end
	return out
end

-- Whether two filters would save the same.
function LF.Same(a, b)
	local same = #a.rules == #b.rules
	for i = 1, #a.rules do
		local x, y = a.rules[i], b.rules[i]
		same = same and y ~= nil and x.type == y.type and x.enabled == y.enabled and x.outcome == y.outcome
			and x.name == y.name and #x.cond == #y.cond
		for j = 1, same and #x.cond or 0 do
			local p, q = x.cond[j], y.cond[j]
			same = same and p.type == q.type and p.op == q.op and p.value == q.value
		end
	end
	return same
end

-- A short text for a condition's value, for the rule summary and buttons.
function LF.ValueText(c)
	local v = LF.Value(c.type)
	local text = ""
	if v.kind == YESNO then
		text = c.value == 0 and "Yes" or "No"
	elseif v.kind == NUMBER then
		text = tostring(c.value or 0)
	elseif v.kind == CHOICE then
		for _, o in ipairs(v.options) do if o.value == c.value then text = o.text end end
	elseif v.kind == MASK then
		local names = {}
		for _, o in ipairs(v.options) do
			if bit.band(c.value or 0, o.value) ~= 0 then names[#names + 1] = o.text end
		end
		text = #names > 0 and table.concat(names, ", ") or "Nothing"
	elseif v.kind == ITEM then
		text = (c.value or 0) > 0 and (GetItemInfoCustom(c.value) or ("Item " .. c.value)) or "Pick an Item"
	elseif v.kind == ZONE then
		text = Custom_GetZoneName and (c.value or 0) > 0 and Custom_GetZoneName(c.value) or "Pick a Zone"
	end
	return text
end
