local _, NS = ...
local SC = NS.SC

-- Resource Bank: the account's crafting materials grouped by type, with what you carry beside what's stored, and
-- withdraw and deposit on a click. Replaces the window the game opens with OpenResourceSummary.
local BankUI = {}
SC.ResourceBankUI = BankUI

local S = SC.Style
local C = S.colors
local Bank = SC.ResourceBank
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, tbl, state
local ALL_KEY, RECENT_KEY = "\1all", "\1recent"
local RAIL_W = 168
local SEARCH_DELAY = 0.15

local qualityColor = S.QualityColor

local function bags(item)
	return GetItemCount(item.id) or 0
end

local SORT = {
	name = function(i) return i.name:upper() end,
	count = function(i) return i.count end,
	bags = bags,
	recent = function(i) return i.recent end,
}

local function sortItems(items)
	local get = SORT[state.sort] or SORT.name
	local values = {}
	for _, i in ipairs(items) do values[i] = get(i) end
	table.sort(items, function(a, b)
		local va, vb = values[a], values[b]
		if va == vb then return a.name:upper() < b.name:upper() end
		if state.desc then return va > vb end
		return va < vb
	end)
end

local function commas(n)
	local text = tostring(n)
	local k
	repeat text, k = text:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return text
end

-- The type list and the materials of the selected type, both narrowed by the search. A type the search leaves
-- empty stays listed with no count, so the list doesn't jump while typing.
local function refresh(keepScroll)
	panel.pending = nil
	local q = (state.search or ""):lower()
	local searching = q ~= ""
	local counts, rows, total = { [ALL_KEY] = 0, [RECENT_KEY] = 0 }, {}, 0
	local present = {}
	for _, item in ipairs(Bank.Items()) do
		total = total + item.count
		if counts[item.group] == nil then
			counts[item.group] = 0
			present[item.group] = true
		end
		if not searching or item.name:lower():find(q, 1, true) then
			counts[ALL_KEY] = counts[ALL_KEY] + 1
			counts[item.group] = counts[item.group] + 1
			if item.recent > 0 then counts[RECENT_KEY] = counts[RECENT_KEY] + 1 end
			local selected = state.type or ALL_KEY
			if selected == ALL_KEY or selected == item.group or (selected == RECENT_KEY and item.recent > 0) then
				rows[#rows + 1] = item
			end
		end
	end
	if state.type and counts[state.type] == nil then
		state.type = nil
		return refresh(keepScroll)
	end
	local rail = { { key = ALL_KEY, label = "All" }, { key = RECENT_KEY, label = "Recently Looted" } }
	for _, section in ipairs(Bank.Sections(present)) do
		rail[#rail + 1] = { header = true, label = section.label }
		for _, g in ipairs(section.groups) do rail[#rail + 1] = { key = g, label = g } end
	end
	for _, entry in ipairs(rail) do entry.count = counts[entry.key] or 0 end
	panel.rail:SetItems(rail, nil, true)

	sortItems(rows)
	local empty = searching and "No Materials Match" or state.type == RECENT_KEY and "Nothing Looted Lately"
		or "The Resource Bank Is Empty"
	tbl:SetItems(rows, empty, keepScroll)
	panel.status:SetText(("%s  " .. S.Hex(C.muted, "|  %s Stored")):format(S.Count(#rows, "Material"), commas(total)))
end

local function message(text)
	panel.status:SetText(S.Hex(C.muted, text))
	panel.messageUntil = GetTime() + 3
end

local function onClick(row, button)
	if IsModifiedClick() then
		HandleModifiedItemClick(row.link)
	elseif button == "RightButton" then
		if bags(row) > 0 then
			Bank.Deposit(row.id)
			message("Depositing " .. row.name)
		else
			message("You Aren't Carrying Any " .. row.name)
		end
	elseif row.count > 0 then
		Bank.Withdraw(row.id)
		message("Withdrawing a Stack of " .. row.name)
	end
end

local function tooltip(tt, row)
	if row.link then
		tt:SetHyperlink(row.link)
		tt:AddLine(" ")
		tt:AddDoubleLine("In the Bank", tostring(row.count), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine("In Your Bags", tostring(bags(row)), 1, 1, 1, 1, 1, 1)
		tt:AddLine("Click: Withdraw a Stack", unpack(C.heading))
		tt:AddLine("Right-Click: Deposit All You Carry", unpack(C.heading))
	end
end

local COLUMNS = {
	{ key = "name", label = "Material", width = 228, stretch = true },
	{ key = "count", label = "In Bank", width = 100, justify = "RIGHT", defaultDesc = true },
	{ key = "bags", label = "In Bags", width = 100, justify = "RIGHT", defaultDesc = true },
	{ key = "recent", label = "Looted", width = 100, justify = "RIGHT", defaultDesc = true },
}

local function cell(row, key)
	if key == "name" then return row.name, qualityColor(row.quality)
	elseif key == "count" then return tostring(row.count)
	elseif key == "bags" then
		local n = bags(row)
		return n > 0 and tostring(n) or "", C.muted
	elseif key == "recent" then return row.recent > 0 and tostring(row.recent) or "", C.muted
	end
end

local function create(parent, width, height)
	SC.db.bank = SC.db.bank or {}
	state = SC.db.bank
	state.sort = state.sort or "name"
	panel = CreateFrame("Frame", nil, parent)

	panel.search = S.Input(panel, "SynastriaCompanionBankSearch", 260, "Search Materials", 60)
	panel.search:SetPoint("TOPLEFT", PAD, -PAD)
	panel.search:HookScript("OnTextChanged", function(self, user)
		if user then
			state.search = self:GetText()
			panel.pending = GetTime() + SEARCH_DELAY
		end
	end)
	panel.search:SetScript("OnEnterPressed", panel.search.ClearFocus)

	local top = -PAD - CONTROL_H - GAP
	local footerH = PAD + CONTROL_H + PAD
	local listH = height + top - footerH

	panel.rail = SC.Table.New(panel, "SynastriaCompanionBankTypes", RAIL_W, listH, {
		columns = { { key = "label", label = "Type", width = 120, sortable = false },
			{ key = "count", label = "", width = 46, justify = "RIGHT", sortable = false } },
		rowH = 18,
		header = function(entry) return entry.header and entry.label end,
		cell = function(entry, key)
			local color = entry.count > 0 and C.text or C.disabled
			if entry.key == (state.type or ALL_KEY) then color = C.heading end
			if key == "label" then return entry.label, color end
			return entry.count > 0 and tostring(entry.count) or "", C.muted
		end,
		onClick = function(entry)
			if entry.key then
				state.type = entry.key ~= ALL_KEY and entry.key or nil
				refresh()
			end
		end,
	})
	panel.rail.isSelected = function(entry) return entry.key == (state.type or ALL_KEY) end
	panel.rail.frame:SetPoint("TOPLEFT", PAD, top)

	tbl = SC.Table.New(panel, "SynastriaCompanionBankTable", width - 2 * PAD - RAIL_W - GAP, listH, {
		columns = COLUMNS, rowH = 20, icons = true, cell = cell,
		icon = function(row) return row.icon end,
		tooltip = tooltip, onClick = onClick,
		onSort = function(key, desc)
			state.sort, state.desc = key, desc
			refresh(true)
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", panel.rail.frame, "TOPRIGHT", GAP, 0)
	tbl:SetSort(state.sort, state.desc)
	panel.table = tbl

	local depositAll = S.Button(panel, "Deposit All", "primary", 110, function()
		Bank.DepositAll()
		message("Depositing Everything the Bank Takes")
	end, "Send every material in your bags that the bank takes.")
	depositAll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	local hint = S.Text(panel, "small", C.muted)
	hint:SetPoint("RIGHT", depositAll, "LEFT", -PAD, 0)
	hint:SetText("Click: Withdraw  |  Right-Click: Deposit")
	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)

	panel:SetScript("OnUpdate", function()
		if panel.pending and GetTime() >= panel.pending then refresh(panel.keepScroll) end
		if panel.messageUntil and GetTime() >= panel.messageUntil then
			panel.messageUntil = nil
			refresh(true)
		end
	end)
	Bank.onChange = function()
		if panel:IsVisible() then
			panel.pending = GetTime() + 0.2
			panel.keepScroll = true
		end
	end
	return panel
end

local function show()
	panel.search:SetText(state.search or "")
	refresh()
end

SC.Window.AddScreen({
	key = "bank",
	label = "Resource Bank",
	create = create,
	show = show,
	hook = { open = "OpenResourceSummary", close = "CloseResourceSummary", frame = "RBankFrame" },
})
