local _, NS = ...
local SC = NS.SC

-- The account's Resource Bank: what's in it, what was looted into it lately, and the server's withdraw and
-- deposit commands.
local Bank = {}
SC.ResourceBank = Bank

local STORED, RECENT = 13, 14
local WITHDRAW, DEPOSIT, DEPOSIT_ALL = 7, 8, 9

-- The game files many crafting materials as Trade Goods > Other; these words in a name (whole words, plural too,
-- first match wins) give them a group of their own or the group they belong with.
local OTHER_GROUPS = {
	{ "pigment", "Inscription" }, { "ink", "Inscription" }, { "parchment", "Inscription" },
	{ "vial", "Alchemy" }, { "flask", "Alchemy" }, { "oil", "Alchemy" }, { "mojo", "Alchemy" },
	{ "orb", "Orbs & Runes" }, { "rune", "Orbs & Runes" },
	{ "pearl", "Gem" },
	{ "snapper", "Cooking" }, { "fish", "Cooking" }, { "suckerfish", "Cooking" }, { "blackmouth", "Cooking" },
	{ "salmon", "Cooking" }, { "eel", "Cooking" }, { "squid", "Cooking" }, { "spice", "Cooking" },
	{ "scale", "Leather" },
	{ "saronite", "Metal & Stone" },
	{ "mote", "Elemental" }, { "sunmote", "Elemental" },
	{ "fang", "Creature Parts" }, { "sac", "Creature Parts" }, { "heart", "Creature Parts" },
	{ "claw", "Creature Parts" }, { "tooth", "Creature Parts" }, { "talon", "Creature Parts" },
	{ "ichor", "Creature Parts" }, { "eye", "Creature Parts" }, { "feather", "Creature Parts" },
	{ "wing", "Creature Parts" }, { "horn", "Creature Parts" },
	{ "thread", "Cloth" }, { "dye", "Cloth" },
	{ "flux", "Metal & Stone" }, { "salt", "Metal & Stone" }, { "vitriol", "Metal & Stone" },
}

local function otherGroup(name, fallback)
	local lower = (name or ""):lower()
	for _, rule in ipairs(OTHER_GROUPS) do
		if lower:find("%f[%a]" .. rule[1] .. "s?%f[%A]") then return rule[2] end
	end
	return fallback
end

-- Game groups shown under another name.
local RENAMED = { Meat = "Cooking" }

-- The group an item is listed under: its subclass for trade goods (Metal & Stone, Herb, Cloth...), otherwise its
-- class (Gem, Consumable...). Other and Miscellaneous are regrouped by name.
local function group(name, class, subclass)
	local classes = { GetAuctionItemClasses and GetAuctionItemClasses() }
	local trade, misc = classes[6] or "Trade Goods", classes[11] or "Miscellaneous"
	local result = (class and class ~= "") and class or "Other"
	if subclass and subclass ~= "" and class == trade then result = subclass end
	if result == "Other" or result == misc then result = otherGroup(name, result) end
	return RENAMED[result] or result
end
Bank.Group = group

-- Every stored item: { id, name, link, quality, icon, count, recent, group }.
function Bank.Items()
	local out = {}
	for i = 1, GetCustomGameDataCount(STORED) or 0 do
		local id = GetCustomGameDataIndex(STORED, i) or 0
		if id > 0 and id < 60000 then
			local name, link, quality, _, _, class, subclass, _, _, icon = GetItemInfoCustom(id)
			out[#out + 1] = { id = id, name = (name and name ~= "") and name or "Unknown Item", link = link,
				quality = quality or 1, icon = icon, count = GetCustomGameData(STORED, id) or 0,
				recent = GetCustomGameData(RECENT, id) or 0, group = group(name, class, subclass) }
		end
	end
	return out
end

function Bank.Withdraw(id)
	NotifyServer(2, WITHDRAW, tostring(id))
end

-- Sends every stack of one item from the bags to the bank.
function Bank.Deposit(id)
	NotifyServer(2, DEPOSIT, tostring(id))
end

-- Sends everything in the bags that the bank takes.
function Bank.DepositAll()
	NotifyServer(2, DEPOSIT_ALL, "")
end

function Bank.Changed()
	if Bank.onChange then Bank.onChange() end
end

SC:OnCustomEvent("SYNASTRIA_RESOURCE_BAG_CHANGED", Bank.Changed)
SC:On("BAG_UPDATE", Bank.Changed)
