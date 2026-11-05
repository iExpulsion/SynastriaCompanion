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
local RECENT_KEY = "\1recent"
local SEARCH_DELAY = 0.15

local function qualityColor(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and { c.r, c.g, c.b, 1 } or C.text
end

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

-- A searched list opens every group, so nothing that matches is hidden.
local function addGroup(rows, key, label, items, open)
	if #items > 0 then
		local collapsed = state.collapsed[key] and not open
		rows[#rows + 1] = { header = true, key = key,
			label = ("%s %s  " .. S.Hex(C.muted, "%d")):format(collapsed and "+" or "-", label, #items) }
		if not collapsed then
			sortItems(items)
			for _, i in ipairs(items) do rows[#rows + 1] = i end
		end
	end
end

local function refresh(keepScroll)
	panel.pending = nil
	local q = (state.search or ""):lower()
	local all, recent, groups, names = Bank.Items(), {}, {}, {}
	local shown, total = 0, 0
	local searching = q ~= ""
	for _, item in ipairs(all) do
		total = total + item.count
		if not searching or item.name:lower():find(q, 1, true) then
			shown = shown + 1
			if item.recent > 0 and not searching then recent[#recent + 1] = item end
			local key = state.grouped and item.group or ""
			if not groups[key] then
				groups[key] = {}
				names[#names + 1] = key
			end
			table.insert(groups[key], item)
		end
	end
	local rows = {}
	if state.grouped then
		addGroup(rows, RECENT_KEY, "Recently Looted", recent)
		table.sort(names)
		for _, key in ipairs(names) do addGroup(rows, key, key, groups[key], searching) end
	else
		local items = groups[""] or {}
		sortItems(items)
		rows = items
	end
	tbl:SetItems(rows, searching and "No Materials Match" or "The Resource Bank Is Empty", keepScroll)
	panel.status:SetText(("%s  " .. S.Hex(C.muted, "|  %s Stored")):format(S.Count(shown, "Material"), commas(total)))
end

local function message(text)
	panel.status:SetText(S.Hex(C.muted, text))
	panel.messageUntil = GetTime() + 3
end

local function onClick(row, button)
	if row.header then
		state.collapsed[row.key] = not state.collapsed[row.key] or nil
		refresh(true)
	elseif IsModifiedClick() then
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
	{ key = "name", label = "Material", width = 393 },
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
	state.collapsed = state.collapsed or {}
	state.sort = state.sort or "name"
	if state.grouped == nil then state.grouped = true end
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

	local groupCheck = S.Check(panel, 14, function(self)
		state.grouped = not state.grouped
		self:SetChecked(state.grouped)
		refresh()
	end)
	groupCheck:SetPoint("LEFT", panel.search, "RIGHT", PAD, 0)
	groupCheck:SetChecked(state.grouped)
	local groupLabel = S.Text(panel, "small")
	groupLabel:SetPoint("LEFT", groupCheck, "RIGHT", 6, 0)
	groupLabel:SetText("Group by Type")

	local expand = S.Button(panel, "Expand All", "ghost", 84, function()
		state.collapsed = {}
		refresh(true)
	end)
	expand:SetPoint("TOPRIGHT", -PAD, -PAD)
	local collapse = S.Button(panel, "Collapse All", "ghost", 90, function()
		for _, item in ipairs(Bank.Items()) do state.collapsed[item.group] = true end
		state.collapsed[RECENT_KEY] = true
		refresh(true)
	end)
	collapse:SetPoint("RIGHT", expand, "LEFT", -4, 0)

	local top = -PAD - CONTROL_H - GAP
	local footerH = PAD + CONTROL_H + PAD
	tbl = SC.Table.New(panel, "SynastriaCompanionBankTable", width - 2 * PAD, height + top - footerH, {
		columns = COLUMNS, rowH = 20, icons = true, cell = cell,
		icon = function(row) return row.icon end,
		header = function(row) return row.header and row.label end,
		tooltip = tooltip, onClick = onClick,
		onSort = function(key, desc)
			state.sort, state.desc = key, desc
			refresh(true)
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", PAD, top)
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
