local _, NS = ...
local SC = NS.SC

-- The Auto Loot templates sheet: whole filters or single rules, switched at the top; a name box to save the
-- screen's filter or selected rule, or rename the selected template; Load puts one in the screen's draft.
local Sheet = {}
SC.LootTemplateSheet = Sheet

local W, LIST_H, LABEL_W, BUTTON_W, SUMMARY_W = 480, 220, 44, 80, 190
local sheet
-- host: what the Auto Loot screen gives the sheet: filter() its draft, rule() the selected rule or nil, dirty(),
-- loaded(kind, template) after a load
local state = { kind = "filters", selected = nil, host = nil }
Sheet.state = state

local function trimmed()
	return (sheet.name:GetText():gsub("^%s+", ""):gsub("%s+$", ""))
end

local function note(text)
	sheet.note:SetText(text or "")
end

local function enable(b, on)
	if on then b:Enable() else b:Disable() end
end

local function confirm(which, name, onAccept)
	local popup = StaticPopup_Show(which, name)
	if popup then popup.data = onAccept end
end

-- Why the selected template can't load now, or nil.
local function loadBlocked(t)
	local reason
	if state.kind == "filters" and state.host.dirty() then
		reason = "Apply or Discard Your Changes First"
	elseif state.kind == "rules" and #state.host.filter().rules >= SC.LootFilter.MAX_RULES then
		reason = "You Have the Most Rules the Filter Holds"
	end
	return t and reason
end

local function canSave()
	return state.kind == "filters" or state.host.rule() ~= nil
end

function Sheet.Render()
	local LT = SC.LootTemplates
	local kind = LT.Kind(state.kind)
	sheet.title:SetText("Auto Loot Templates")
	sheet.sub:SetText(state.kind == "filters" and "Every rule and option. Loading one replaces the filter in the editor."
		or "One rule each. Loading one adds it at the bottom of your rules.")
	sheet.filtersTab:SetKind(state.kind == "filters" and "selected" or "secondary")
	sheet.rulesTab:SetKind(state.kind == "rules" and "selected" or "secondary")
	local selected = state.selected and LT.Get(state.kind, state.selected)
	if not selected then state.selected = nil end
	sheet.list:SetItems(LT.List(state.kind), ("No %s Templates Yet"):format(kind.one), true)
	local name = trimmed()
	enable(sheet.load, selected ~= nil and not loadBlocked(selected))
	enable(sheet.save, name ~= "" and canSave())
	enable(sheet.rename, selected ~= nil and name ~= "" and name ~= state.selected)
	enable(sheet.delete, selected ~= nil)
	sheet.save.tooltipText = state.kind == "filters"
		and "Save the filter as it is in the editor, rules and options, under the name in the box. Replaces a template of that name."
		or (canSave() and "Save the selected rule under the name in the box. Replaces a template of that name."
		or "Pick a rule in the Auto Loot screen first.")
	sheet.load.tooltipText = loadBlocked(selected) or (state.kind == "filters"
		and "Replace the filter in the editor with this one. Apply saves it; Discard takes it back."
		or "Add this rule at the bottom of your rules. Apply saves it.")
end

local function setKind(kind)
	state.kind, state.selected = kind, nil
	sheet.name:SetText("")
	sheet.name:UpdatePlaceholder()
	note()
	Sheet.Render()
end

local function load()
	local LT = SC.LootTemplates
	local t = LT.Get(state.kind, state.selected)
	if t and not loadBlocked(t) then
		if state.kind == "filters" then LT.LoadFilter(t, state.host.filter()) else LT.AddRule(t, state.host.filter()) end
		sheet:Hide()
		state.host.loaded(state.kind, t)
	end
end

local function save()
	local LT, S, C = SC.LootTemplates, SC.Style, SC.Style.colors
	local name = trimmed()
	local function commit()
		if state.kind == "filters" then LT.SaveFilter(name, state.host.filter()) else LT.SaveRule(name, state.host.rule()) end
		state.selected = name
		note(S.Hex(C.good, "Saved " .. name))
		Sheet.Render()
	end
	if LT.Get(state.kind, name) then confirm("SYNASTRIA_COMPANION_LOOT_TEMPLATE_REPLACE", name, commit) else commit() end
end

local function rename()
	local S, C = SC.Style, SC.Style.colors
	local name = trimmed()
	if SC.LootTemplates.Rename(state.kind, state.selected, name) then
		state.selected = name
		note(S.Hex(C.good, "Renamed to " .. name))
	else
		note(S.Hex(C.bad, "A Template Has That Name"))
	end
	Sheet.Render()
end

local function delete()
	local name = state.selected
	confirm("SYNASTRIA_COMPANION_LOOT_TEMPLATE_DELETE", name, function()
		SC.LootTemplates.Delete(state.kind, name)
		state.selected = nil
		sheet.name:SetText("")
		sheet.name:UpdatePlaceholder()
		note(SC.Style.Hex(SC.Style.colors.muted, "Deleted " .. name))
		Sheet.Render()
	end)
end

local function create()
	local S, C = SC.Style, SC.Style.colors
	-- the theme's dialog padding; the dialog grows by the difference from the kit's, so its contents keep their size
	local PAD, GAP, CONTROL_H = S.metrics.inset, S.GAP, S.CONTROL_H
	local grow = 2 * (PAD - S.PAD)
	local innerW = W - 2 * S.PAD
	local switchY = PAD + 16 + 4 + 12 + PAD
	local listTop = switchY + CONTROL_H + GAP
	local nameY = listTop + LIST_H + GAP + CONTROL_H / 2
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaCompanionLootTemplates", UIParent)
	f:SetSize(W + grow, nameY + CONTROL_H / 2 + PAD + CONTROL_H + PAD)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	SC.PixelScale(f)
	S.Frame(f, "popup")
	tinsert(UISpecialFrames, "SynastriaCompanionLootTemplates")
	f:HookScript("OnHide", S.Dismiss)
	f:Hide()

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	-- one line within the dialog's padding, so a wide font or skin cuts it short rather than past the edge
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.sub:SetWidth(innerW)
	f.sub:SetWordWrap(false)
	local close = S.Button(f, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD, -(PAD - 4))

	-- a segmented switch: the halves share their 1px border
	local rulesW = math.floor((innerW + 1) / 2)
	f.filtersTab = S.Button(f, "Filters", "secondary", innerW + 1 - rulesW, function() setKind("filters") end,
		"Whole filters: every rule and option.")
	f.filtersTab:SetPoint("TOPLEFT", PAD, -switchY)
	f.rulesTab = S.Button(f, "Rules", "secondary", rulesW, function() setKind("rules") end,
		"Single rules, to add to any filter.")
	f.rulesTab:SetPoint("LEFT", f.filtersTab, "RIGHT", -1, 0)

	f.list = SC.Table.New(f, "SynastriaCompanionLootTemplateList", innerW, LIST_H, {
		columns = { { key = "name", label = "Template", width = innerW - SUMMARY_W, sortable = false },
			{ key = "summary", label = "", width = SUMMARY_W, sortable = false } },
		rowH = 20,
		cell = function(t, key)
			local text, color = t.name, C.text
			if key == "summary" then text, color = SC.LootTemplates.Describe(state.kind, t), C.muted end
			return text, color
		end,
		isSelected = function(t) return t.name == state.selected end,
		onClick = function(t)
			state.selected = t.name
			sheet.name:SetText(t.name)
			sheet.name:UpdatePlaceholder()
			note()
			Sheet.Render()
		end,
	})
	f.list.frame:SetPoint("TOPLEFT", PAD, -listTop)

	-- the name box takes the row's spare width, so Rename ends in line with the list and Load
	local nameLabel = S.Text(f, "small", C.muted)
	nameLabel:SetPoint("LEFT", f, "TOPLEFT", PAD, -nameY)
	nameLabel:SetText("Name")
	local nameW = innerW - LABEL_W - 2 * (BUTTON_W + GAP)
	f.name = S.Input(f, "SynastriaCompanionLootTemplateName", nameW, "Template Name", 40)
	f.name:SetPoint("LEFT", f, "TOPLEFT", PAD + LABEL_W, -nameY)
	f.name:HookScript("OnTextChanged", function(_, userInput)
		if userInput then Sheet.Render() end
	end)
	f.save = S.Button(f, "Save", "secondary", BUTTON_W, save)
	f.save:SetPoint("LEFT", f.name, "RIGHT", GAP, 0)
	f.rename = S.Button(f, "Rename", "secondary", BUTTON_W, rename, "Give the selected template the name in the box.")
	f.rename:SetPoint("LEFT", f.save, "RIGHT", GAP, 0)

	-- Delete and Load sit under Save and Rename, the four buttons one block in the corner
	f.load = S.Button(f, "Load", "primary", BUTTON_W, load)
	f.load:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.delete = S.Button(f, "Delete", "danger", BUTTON_W, delete, "Delete the selected template.")
	f.delete:SetPoint("RIGHT", f.load, "LEFT", -GAP, 0)
	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	f.note:SetPoint("RIGHT", f.delete, "LEFT", -PAD, 0)
	return f
end

-- Opens the sheet on `kind` ("filters" or "rules") for the Auto Loot screen's `host`. With `saving` the name box
-- starts with a fresh name: the selected rule's for a rule.
function Sheet.Open(kind, host, saving)
	SC.Style.Dismiss()
	sheet = sheet or create()
	state.kind, state.host, state.selected = kind, host, nil
	local rule = host.rule()
	local base = kind == "rules" and rule and rule.name ~= "" and rule.name or "My Filter"
	sheet.name:SetText(saving and SC.LootTemplates.UniqueName(kind, base) or "")
	sheet.name:UpdatePlaceholder()
	note()
	Sheet.Render()
	sheet:Show()
	sheet:Raise()
end

function Sheet.Hide()
	if sheet then sheet:Hide() end
end

function Sheet.Frame()
	return sheet
end

StaticPopupDialogs["SYNASTRIA_COMPANION_LOOT_TEMPLATE_REPLACE"] = {
	text = "A template named \"%s\" already exists. Replace it?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SYNASTRIA_COMPANION_LOOT_TEMPLATE_DELETE"] = {
	text = "Delete template \"%s\"?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
