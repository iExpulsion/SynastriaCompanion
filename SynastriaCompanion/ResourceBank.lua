local _, NS = ...
local SC = NS.SC

-- The account's Resource Bank: what's in it, what was looted into it lately, and the server's withdraw and
-- deposit commands.
local Bank = {}
SC.ResourceBank = Bank

local STORED, RECENT = 13, 14
local WITHDRAW, DEPOSIT, DEPOSIT_ALL = 7, 8, 9

-- The group an item is listed under: its subclass for trade goods (Metal & Stone, Herb, Cloth...), otherwise its
-- class (Gem, Consumable...).
local function group(class, subclass)
	local trade = select(6, GetAuctionItemClasses and GetAuctionItemClasses() or nil)
	if subclass and subclass ~= "" and (class == trade or class == "Trade Goods") then return subclass end
	return (class and class ~= "") and class or "Other"
end

-- Every stored item: { id, name, link, quality, icon, count, recent, group }.
function Bank.Items()
	local out = {}
	for i = 1, GetCustomGameDataCount(STORED) or 0 do
		local id = GetCustomGameDataIndex(STORED, i) or 0
		if id > 0 and id < 60000 then
			local name, link, quality, _, _, class, subclass, _, _, icon = GetItemInfoCustom(id)
			out[#out + 1] = { id = id, name = (name and name ~= "") and name or "Unknown Item", link = link,
				quality = quality or 1, icon = icon, count = GetCustomGameData(STORED, id) or 0,
				recent = GetCustomGameData(RECENT, id) or 0, group = group(class, subclass) }
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
