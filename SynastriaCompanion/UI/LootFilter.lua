local _, NS = ...
local SC = NS.SC

-- Lootfilter: the rules on the left, the selected rule's name, match, action and conditions on the right, and the
-- loot options. Edits stay a draft until Apply. Replaces the window the game opens with OpenLootFilter.
local LFUI = {}
SC.LootFilterUI = LFUI

local S = SC.Style
local C = S.colors
local LF = SC.LootFilter
local K = LF.KINDS
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel
local server, draft
local sel
local LIST_W, ROW_H = 210, CONTROL_H + 4
local ARM_FOR = 4

local SHORT_ACTION = { [0] = "Skip", [1] = "DE/Sell", [2] = "Sell", [3] = "Loot", [4] = "Bag 2", [5] = "Bag 3",
	[6] = "Bag 4", [7] = "Bag 5" }

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function textOf(options, value)
	for _, o in ipairs(options) do
		if o.value == value then return o.text end
	end
	return "?"
end

local function dirty()
	return draft ~= nil and server ~= nil and not LF.Same(draft, server)
end

local render

local function load()
	server = LF.Read()
	draft = LF.Copy(server)
	if sel and sel > #draft.rules then sel = #draft.rules end
	if not sel and #draft.rules > 0 then sel = 1 end
	if #draft.rules == 0 then sel = nil end
end

local function message(text, color)
	panel.message = S.Hex(color or C.muted, text)
	panel.messageUntil = GetTime() + 5
end

local function changed()
	render()
end

-- Rule list ----------------------------------------------------------------------------------------------------

local function ruleCell(rule, key)
	local muted = not rule.enabled
	if key == "name" then
		local i = 0
		for n, r in ipairs(draft.rules) do if r == rule then i = n end end
		local name = rule.name ~= "" and rule.name or "Unnamed Rule"
		local current = not panel.showOptions and rule == draft.rules[sel]
		return ("%d. %s"):format(i, name), muted and C.disabled or (current and C.heading or C.text)
	end
	return muted and "Off" or SHORT_ACTION[rule.outcome] or "?", muted and C.disabled or C.muted
end

local function selectRule(rule)
	S.Dismiss()
	for i, r in ipairs(draft.rules) do
		if r == rule then sel = i end
	end
	panel.showOptions = false
	render()
end

local function moveRule(delta)
	local to = sel and sel + delta
	if to and to >= 1 and to <= #draft.rules then
		draft.rules[sel], draft.rules[to] = draft.rules[to], draft.rules[sel]
		sel = to
		changed()
	end
end

-- Conditions -------------------------------------------------------------------------------------------------

local conditionRows = {}

local function itemSearch(text)
	local out = {}
	if #text >= 2 then
		for _, item in ipairs(SC.LootDB.Search(text)) do
			out[#out + 1] = { value = item.id, text = item.name, link = item.link, icon = item.icon }
		end
	end
	return out
end

local function openValuePicker(row)
	local rule = draft.rules[sel]
	local c = rule and rule.cond[row.index]
	if c then
		local v = LF.Value(c.type)
		if v.kind == K.MASK then
			SC.Picker.Open(row.valueButton, { items = v.options, multi = true, placeholder = "Search Choices",
				isSelected = function(value) return bit.band(c.value or 0, value) ~= 0 end,
				onPick = function(value)
					c.value = bit.bxor(c.value or 0, value)
					changed()
				end })
		elseif v.kind == K.ITEM then
			SC.Picker.Open(row.valueButton, { search = itemSearch, placeholder = "Type an Item Name",
				emptyText = "Type at Least Two Letters", isSelected = function(id) return id == c.value end,
				onPick = function(id)
					c.value = id
					changed()
				end })
		elseif v.kind == K.ZONE then
			SC.ZonePicker.Open(row.valueButton, function(index)
				c.value = ALL_ZONE_LIST[index].v
				changed()
			end, SC.ZonePicker.IndexOf(c.value))
		end
	end
end

local function newConditionRow(parent, index)
	local row = { index = index }
	row.frame = CreateFrame("Frame", nil, parent)
	row.frame:SetHeight(CONTROL_H)

	row.typeButton = S.Button(row.frame, "", "secondary", 176, function(self)
		local items = {}
		for _, c in ipairs(LF.CONDITIONS) do items[#items + 1] = { value = c.id, text = c.name, tooltip = c.tooltip } end
		local rule = draft.rules[sel]
		SC.Picker.Open(self, { items = items, placeholder = "Search Conditions",
			isSelected = function(id) return rule and rule.cond[row.index] and rule.cond[row.index].type == id end,
			onPick = function(id)
				LF.Retype(rule.cond[row.index], id)
				changed()
			end })
	end)
	row.typeButton.label:ClearAllPoints()
	row.typeButton.label:SetPoint("LEFT", 8, 0)
	row.typeButton.label:SetPoint("RIGHT", -8, 0)
	row.typeButton.label:SetJustifyH("LEFT")
	row.typeButton:SetPoint("LEFT")

	row.op = S.Dropdown(row.frame, 76, function(op)
		draft.rules[sel].cond[row.index].op = op
		changed()
	end)
	row.op:SetPoint("LEFT", row.typeButton, "RIGHT", 4, 0)

	local valueX, valueW = 176 + 4 + 76 + 4, 170
	row.choice = S.Dropdown(row.frame, valueW, function(value)
		draft.rules[sel].cond[row.index].value = value
		changed()
	end)
	row.choice:SetPoint("LEFT", valueX, 0)
	row.number = S.Input(row.frame, nil, valueW, "Number", 8)
	row.number:SetNumeric(true)
	row.number:SetPoint("LEFT", valueX, 0)
	row.number:HookScript("OnTextChanged", function(self, user)
		if user then
			draft.rules[sel].cond[row.index].value = tonumber(self:GetText()) or 0
			panel.pendingRender = true
		end
	end)
	row.number:SetScript("OnEnterPressed", row.number.ClearFocus)
	row.valueButton = S.Button(row.frame, "", "secondary", valueW, function() openValuePicker(row) end)
	row.valueButton.label:ClearAllPoints()
	row.valueButton.label:SetPoint("LEFT", 8, 0)
	row.valueButton.label:SetPoint("RIGHT", -8, 0)
	row.valueButton.label:SetJustifyH("LEFT")
	row.valueButton:SetPoint("LEFT", valueX, 0)
	-- an item value shows its icon, and its tooltip on hover
	row.valueIcon = row.valueButton:CreateTexture(nil, "OVERLAY")
	row.valueIcon:SetSize(16, 16)
	row.valueIcon:SetPoint("LEFT", 5, 0)
	row.valueButton:HookScript("OnEnter", function(self)
		if self.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:Show()
		end
	end)
	row.valueButton:HookScript("OnClick", function(self)
		if self.link and IsModifiedClick() then
			S.CloseMenus()
			HandleModifiedItemClick(self.link)
		end
	end)
	row.noValue = S.Text(row.frame, "small", C.muted)
	row.noValue:SetPoint("LEFT", row.op, "LEFT", 8, 0)
	row.noValue:SetText("Needs no value")

	row.remove = S.Button(row.frame, "X", "ghost", 24, function()
		local rule = draft.rules[sel]
		table.remove(rule.cond, row.index)
		changed()
	end, "Remove this condition.")
	row.remove:SetPoint("RIGHT")
	row.copy = S.Button(row.frame, "+", "ghost", 24, function()
		local rule = draft.rules[sel]
		local c = rule.cond[row.index]
		if #rule.cond < LF.MAX_CONDITIONS then
			table.insert(rule.cond, row.index + 1, { type = c.type, op = c.op, value = c.value })
			changed()
		end
	end, "Copy this condition into a new one below it.")
	row.copy:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
	function row.copy:SetEnabled(on) if on then self:Enable() else self:Disable() end end
	return row
end

local function renderConditions(rule)
	for i, row in ipairs(conditionRows) do
		local c = rule and rule.cond[i]
		setShown(row.frame, c ~= nil)
		if c then
			local def = LF.Condition(c.type)
			row.typeButton:SetText(def and def.name or ("Condition " .. c.type))
			row.typeButton.tooltipText = def and def.tooltip
			local v = LF.Value(c.type)
			local ops = LF.Ops(c.type)
			setShown(row.op, #ops > 0)
			if #ops > 0 then
				row.op:SetOptions(ops)
				row.op:SetText(LF.OPS[c.op] or "?")
			end
			setShown(row.noValue, v.kind == K.NONE)
			setShown(row.choice, v.kind == K.CHOICE or v.kind == K.YESNO)
			if v.kind == K.YESNO then
				row.choice:SetOptions({ { value = 0, text = "Yes" }, { value = 1, text = "No" } })
				row.choice:SetText(LF.ValueText(c))
			elseif v.kind == K.CHOICE then
				row.choice:SetOptions(v.options)
				row.choice:SetText(LF.ValueText(c))
			end
			setShown(row.number, v.kind == K.NUMBER)
			if v.kind == K.NUMBER and not row.number.focused then row.number:SetText(tostring(c.value or 0)) end
			local picked = v.kind == K.MASK or v.kind == K.ITEM or v.kind == K.ZONE
			setShown(row.valueButton, picked)
			if picked then
				local link, quality, icon
				if v.kind == K.ITEM and (c.value or 0) > 0 then
					_, link, quality, _, _, _, _, _, _, icon = GetItemInfoCustom(c.value)
				end
				local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
				local text = LF.ValueText(c)
				row.valueButton:SetText(color and color.hex and (color.hex .. text .. "|r") or text)
				row.valueButton.link = link
				row.valueButton.tooltipText = v.kind == K.MASK and text or nil
				row.valueIcon:SetTexture(icon)
				setShown(row.valueIcon, icon ~= nil)
				row.valueButton.label:ClearAllPoints()
				row.valueButton.label:SetPoint("LEFT", icon and 26 or 8, 0)
				row.valueButton.label:SetPoint("RIGHT", -8, 0)
			end
		end
	end
	local count = rule and #rule.cond or 0
	for _, row in ipairs(conditionRows) do row.copy:SetEnabled(count < LF.MAX_CONDITIONS) end
	local full = count >= LF.MAX_CONDITIONS
	panel.condTop:SetText("Conditions  " .. S.Hex(full and C.warn or C.muted, ("%d/%d"):format(count, LF.MAX_CONDITIONS)))
	panel.addCondition:ClearAllPoints()
	panel.addCondition:SetPoint("TOPLEFT", panel.condTop, "BOTTOMLEFT", 0, -GAP - count * ROW_H)
	setShown(panel.addCondition, rule ~= nil and count < LF.MAX_CONDITIONS)
end

-- Render -------------------------------------------------------------------------------------------------------

function render()
	panel.pendingRender = nil
	local available = draft ~= nil
	panel.rules:SetItems(draft and draft.rules or {}, available and "No Rules Yet" or "The Server Hasn't Enabled the Loot Filter", true)
	local rule = draft and sel and draft.rules[sel]
	local ruleCount = draft and #draft.rules or 0
	panel.rules:SetColumnLabel("name", available and ("Rules  " .. S.Hex(ruleCount >= LF.MAX_RULES and C.warn or C.muted,
		("%d/%d"):format(ruleCount, LF.MAX_RULES))) or "Rules")
	panel.newRule:SetEnabled(available and #draft.rules < LF.MAX_RULES)
	panel.delete:SetEnabled(rule ~= nil)
	panel.up:SetEnabled(rule ~= nil and sel > 1)
	panel.down:SetEnabled(rule ~= nil and sel < #draft.rules)

	setShown(panel.options, panel.showOptions and available)
	setShown(panel.editor, not panel.showOptions and rule ~= nil)
	setShown(panel.empty, not panel.showOptions and rule == nil)
	panel.empty:SetText(available and "Pick a rule, or make a new one." or "The loot filter isn't enabled by the server.")
	if rule and not panel.showOptions then
		if not panel.name.focused then panel.name:SetText(rule.name) end
		panel.enabled:SetChecked(rule.enabled)
		panel.match:SetText(textOf(LF.MATCH, rule.type))
		panel.action:SetText(textOf(LF.ACTIONS, rule.outcome))
		panel.position:SetText(("Rule %d of %d. Rules are checked top to bottom; the first one that matches decides.")
			:format(sel, #draft.rules))
		renderConditions(rule)
	end
	if panel.showOptions and available then
		local on = bit.band(draft.options or 0, LF.AUTO_LOOT.bit) ~= 0
		for _, box in ipairs(panel.optionBoxes) do
			box:SetChecked(bit.band(draft.options or 0, box.bit) ~= 0)
			-- the others still change while Auto Loot is off, but they don't apply, so they're dimmed
			local alpha = (box == panel.autoLoot or on) and 1 or 0.45
			box:SetAlpha(alpha)
			box.text:SetAlpha(alpha)
			box.desc:SetAlpha(alpha)
		end
	end

	panel.optionsButton:SetKind(panel.showOptions and available and "selected" or "secondary")
	local isDirty = dirty()
	panel.apply:SetEnabled(isDirty)
	panel.discard:SetEnabled(isDirty)
	local status = panel.message or (isDirty and S.Hex(C.warn, "Unsaved Changes") or (available and S.Hex(C.muted, "Saved") or ""))
	panel.status:SetText(status)
end

local function apply()
	S.Dismiss()
	local err = LF.Write(draft)
	if err then
		sel = err.rule
		message(("Rule %d, Condition %d: %s"):format(err.rule, err.cond, err.message), C.bad)
	else
		load()
		message("Saved", C.good)
	end
	render()
end

local function armButton(button, label, armedLabel, run)
	if button.armedAt and GetTime() - button.armedAt < ARM_FOR then
		button.armedAt = nil
		button:SetLabel(label)
		run()
	else
		button.armedAt = GetTime()
		button:SetLabel(armedLabel)
	end
end

local function exportChoice(choice)
	if dirty() then
		message("Apply or Discard Your Changes First; Exports Use the Saved Filter", C.warn)
	elseif choice == "filter" then
		SC.TextDialog.ShowExport("Export Loot Filter", "Every rule and option. Copy it with Ctrl+C.", LF.Export() or "")
	elseif draft.rules[sel] then
		SC.TextDialog.ShowExport("Export Rule", "This rule only. Copy it with Ctrl+C.", LF.ExportRule(draft.rules[sel].index) or "")
	end
	render()
end

local function importChoice(choice)
	if dirty() then
		message("Apply or Discard Your Changes First", C.warn)
	elseif choice == "filter" then
		SC.TextDialog.AskImport("Import Loot Filter", "Replaces your whole loot filter, options too.", function(text)
			if LF.Import(text) then message("Imported", C.good) else message("The Game Couldn't Read That", C.bad) end
			load()
			render()
		end)
	elseif #draft.rules < LF.MAX_RULES then
		SC.TextDialog.AskImport("Import Rule", "Adds the rule at the bottom of your list.", function(text)
			local filter = LF.Copy(server)
			filter.rules[#filter.rules + 1] = LF.NewRule()
			LF.Write(filter)
			if LF.ImportRule(#filter.rules, text) then
				message("Imported", C.good)
				load()
				sel = #draft.rules
			else
				LF.Write(server)
				load()
				message("The Game Couldn't Read That", C.bad)
			end
			render()
		end)
	else
		message("You Have the Most Rules the Filter Holds", C.warn)
	end
	render()
end

local function label(parent, text)
	local fs = S.Text(parent, "small", C.muted)
	fs:SetText(text)
	return fs
end

local function create(parent, width, height)
	panel = CreateFrame("Frame", nil, parent)
	local footerY = PAD
	local listH = height - 2 * PAD - CONTROL_H - GAP - CONTROL_H - GAP

	-- rule list and its buttons
	panel.rules = SC.Table.New(panel, "SynastriaCompanionLFRules", LIST_W, listH, {
		columns = { { key = "name", label = "Rule", width = 138, sortable = false },
			{ key = "action", label = "Action", width = 70, sortable = false } },
		rowH = 20, cell = ruleCell, onClick = selectRule,
		tooltip = function(tt, rule)
			tt:AddLine(rule.name ~= "" and rule.name or "Unnamed Rule", 1, 1, 1)
			tt:AddLine(textOf(LF.MATCH, rule.type) .. ", then " .. textOf(LF.ACTIONS, rule.outcome), unpack(C.muted))
			for _, c in ipairs(rule.cond) do
				local def = LF.Condition(c.type)
				local op = #LF.Ops(c.type) > 0 and (" " .. (LF.OPS[c.op] or "")) or ""
				tt:AddLine((def and def.name or "?") .. op .. (LF.Value(c.type).kind ~= K.NONE and (" " .. LF.ValueText(c)) or ""),
					1, 1, 1, true)
			end
		end,
	})
	panel.rules.isSelected = function(rule) return draft and not panel.showOptions and rule == draft.rules[sel] end
	panel.rules.frame:SetPoint("TOPLEFT", PAD, -PAD)

	panel.newRule = S.Button(panel, "New", "secondary", 51, function()
		draft.rules[#draft.rules + 1] = LF.NewRule()
		sel = #draft.rules
		panel.showOptions = false
		changed()
	end, "Add a rule at the bottom.")
	panel.newRule:SetPoint("TOPLEFT", panel.rules.frame, "BOTTOMLEFT", 0, -GAP)
	panel.delete = S.Button(panel, "Delete", "danger", 51, function()
		table.remove(draft.rules, sel)
		if sel > #draft.rules then sel = #draft.rules > 0 and #draft.rules or nil end
		changed()
	end, "Remove the selected rule. Nothing is saved until Apply.")
	panel.delete:SetPoint("LEFT", panel.newRule, "RIGHT", 2, 0)
	panel.up = S.Button(panel, "Up", "secondary", 51, function() moveRule(-1) end, "Check this rule earlier.")
	panel.up:SetPoint("LEFT", panel.delete, "RIGHT", 2, 0)
	panel.down = S.Button(panel, "Down", "secondary", 51, function() moveRule(1) end, "Check this rule later.")
	panel.down:SetPoint("LEFT", panel.up, "RIGHT", 2, 0)
	for _, b in ipairs({ panel.newRule, panel.delete, panel.up, panel.down, }) do
		function b:SetEnabled(on) if on then self:Enable() else self:Disable() end end
	end

	-- the rule editor
	local x = PAD + LIST_W + GAP
	local editorW = width - x - PAD
	local editor = CreateFrame("Frame", nil, panel)
	editor:SetPoint("TOPLEFT", x, -PAD)
	editor:SetPoint("BOTTOMRIGHT", -PAD, PAD + CONTROL_H + GAP)
	panel.editor = editor

	panel.name = S.Input(editor, "SynastriaCompanionLFName", 300, "Rule Name", 30)
	panel.name:SetPoint("TOPLEFT")
	panel.name:HookScript("OnTextChanged", function(self, user)
		if user and draft.rules[sel] then
			draft.rules[sel].name = self:GetText()
			panel.pendingRender = true
		end
	end)
	panel.name:SetScript("OnEnterPressed", panel.name.ClearFocus)
	panel.enabled = S.Check(editor, 14, function(self)
		local rule = draft.rules[sel]
		local on = not rule.enabled
		-- with nothing else pending it saves at once, by the rule's saved place
		if not dirty() and rule.index then
			LF.SetEnabledNow(rule.index, on)
			server.rules[sel].enabled = on
		end
		rule.enabled = on
		self:SetChecked(on)
		changed()
	end)
	panel.enabled:SetPoint("LEFT", panel.name, "RIGHT", PAD, 0)
	panel.enabled.tooltipText = "Turn this rule on or off. Saves at once when nothing else is waiting for Apply."
	local onLabel = S.Text(editor, "small")
	onLabel:SetPoint("LEFT", panel.enabled, "RIGHT", 6, 0)
	onLabel:SetText("Rule On")

	local matchLabel = label(editor, "Match")
	matchLabel:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -GAP - 6)
	panel.match = S.Dropdown(editor, 170, function(v)
		draft.rules[sel].type = v
		changed()
	end)
	panel.match:SetOptions(LF.MATCH)
	panel.match:SetPoint("LEFT", matchLabel, "RIGHT", GAP, 0)
	local actionLabel = label(editor, "Then")
	actionLabel:SetPoint("LEFT", panel.match, "RIGHT", PAD, 0)
	panel.action = S.Dropdown(editor, 190, function(v)
		draft.rules[sel].outcome = v
		changed()
	end)
	panel.action:SetOptions(LF.ACTIONS)
	panel.action:SetPoint("LEFT", actionLabel, "RIGHT", GAP, 0)

	panel.condTop = label(editor, "Conditions")
	panel.condTop:SetPoint("TOPLEFT", matchLabel, "BOTTOMLEFT", 0, -PAD - 6)
	for i = 1, LF.MAX_CONDITIONS do
		local row = newConditionRow(editor, i)
		row.frame:SetPoint("TOPLEFT", panel.condTop, "BOTTOMLEFT", 0, -GAP - (i - 1) * ROW_H)
		row.frame:SetWidth(editorW)
		conditionRows[i] = row
	end
	panel.conditionRows = conditionRows
	panel.addCondition = S.Button(editor, "Add Condition", "secondary", 110, function()
		local rule = draft.rules[sel]
		rule.cond[#rule.cond + 1] = { type = 0, op = 0, value = 0 }
		changed()
	end)
	panel.position = S.Text(editor, "small", C.muted)
	panel.position:SetPoint("BOTTOMLEFT", 0, 0)
	panel.position:SetPoint("RIGHT")

	panel.empty = S.Text(panel, "normal", C.muted)
	panel.empty:SetPoint("TOP", editor, "TOP", 0, -60)

	-- the loot options
	local options = CreateFrame("Frame", nil, panel)
	options:SetAllPoints(editor)
	panel.options = options
	local title = S.Text(options, "large")
	title:SetPoint("TOPLEFT")
	title:SetText("Loot Options")
	local note = S.Text(options, "small", C.muted)
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	note:SetText("These save as soon as you change them.")
	-- Auto Loot on top, then the groups: Loot From and Gathering in the left column, Items in the right
	panel.optionBoxes = {}
	local OPTION_H, colW = 36, editorW / 2
	local function optionRow(opt, left, y, size)
		local box = S.Check(options, 14, function(self)
			draft.options = bit.bxor(draft.options or 0, self.bit)
			server.options = bit.bxor(server.options or 0, self.bit)
			LF.SetOptionsNow(server.options)
			changed()
		end)
		box.bit = opt.bit
		box:SetPoint("TOPLEFT", options, "TOPLEFT", left, y)
		box.text = S.Text(options, size or "small")
		box.text:SetPoint("LEFT", box, "RIGHT", 8, 0)
		box.text:SetText(opt.text)
		box.desc = S.Text(options, "small", C.muted)
		box.desc:SetPoint("TOPLEFT", box.text, "BOTTOMLEFT", 0, -3)
		box.desc:SetWidth(colW - 34)
		box.desc:SetText(opt.desc)
		panel.optionBoxes[#panel.optionBoxes + 1] = box
		return box
	end
	local top = -44
	panel.autoLoot = optionRow(LF.AUTO_LOOT, 0, top, "normal")
	panel.autoLoot.desc:SetWidth(editorW - 34)
	local rule = S.Solid(options, "BORDER", C.border)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 0, top - OPTION_H - 4)
	rule:SetPoint("TOPRIGHT", 0, top - OPTION_H - 4)
	local columns = { { x = 0, y = top - OPTION_H - 16 }, { x = colW, y = top - OPTION_H - 16 } }
	for g, group in ipairs(LF.OPTION_GROUPS) do
		local col = columns[g == #LF.OPTION_GROUPS and 2 or 1]
		local heading = S.Text(options, "small", C.heading)
		heading:SetPoint("TOPLEFT", options, "TOPLEFT", col.x, col.y)
		heading:SetText(group.label)
		col.y = col.y - 20
		for _, opt in ipairs(group.options) do
			optionRow(opt, col.x, col.y)
			col.y = col.y - OPTION_H
		end
		col.y = col.y - GAP
	end

	-- footer
	local optionsButton = S.Button(panel, "Options", "secondary", 70, function()
		S.Dismiss()
		panel.showOptions = not panel.showOptions
		render()
	end, "Turn auto looting and its parts on or off.")
	optionsButton:SetPoint("BOTTOMLEFT", PAD, footerY)
	panel.optionsButton = optionsButton
	local export = S.Dropdown(panel, 84, exportChoice)
	export:SetOptions({ { value = "filter", text = "Whole Filter" }, { value = "rule", text = "This Rule" } })
	export:SetText("Export")
	export:SetPoint("LEFT", optionsButton, "RIGHT", 4, 0)
	export.menu:SetWidth(120)
	local import = S.Dropdown(panel, 84, importChoice)
	import:SetOptions({ { value = "filter", text = "Whole Filter", tooltip = "Replace your loot filter with a shared one." },
		{ value = "rule", text = "One Rule", tooltip = "Add a shared rule at the bottom." } })
	import:SetText("Import")
	import:SetPoint("LEFT", export, "RIGHT", 4, 0)
	import.menu:SetWidth(120)
	panel.reset = S.Button(panel, "Reset to Default", "danger", 120, function(self)
		armButton(self, "Reset to Default", "Click to Confirm", function()
			LF.ResetToDefault()
			message("Reset to the Server's Default", C.muted)
			panel.reloadAt = GetTime() + 1
		end)
		render()
	end, "Replace every rule and option with the server's default filter. Asks you to click again.")
	panel.reset:SetPoint("LEFT", import, "RIGHT", 4, 0)

	panel.apply = S.Button(panel, "Apply", "primary", 80, apply, "Save your changes to the loot filter.")
	panel.apply:SetPoint("BOTTOMRIGHT", -PAD, footerY)
	panel.discard = S.Button(panel, "Discard", "ghost", 70, function()
		S.Dismiss()
		load()
		render()
	end, "Throw away your changes and go back to the saved filter.")
	panel.discard:SetPoint("RIGHT", panel.apply, "LEFT", -4, 0)
	for _, b in ipairs({ panel.apply, panel.discard }) do
		function b:SetEnabled(on) if on then self:Enable() else self:Disable() end end
	end
	panel.status = S.Text(panel, "small")
	panel.status:SetJustifyH("RIGHT")
	panel.status:SetPoint("RIGHT", panel.discard, "LEFT", -GAP, 0)
	panel.status:SetPoint("LEFT", panel.reset, "RIGHT", GAP, 0)

	panel:SetScript("OnUpdate", function()
		local now = GetTime()
		if panel.messageUntil and now >= panel.messageUntil then
			panel.message, panel.messageUntil = nil, nil
			render()
		end
		if panel.reset.armedAt and now - panel.reset.armedAt >= ARM_FOR then
			panel.reset.armedAt = nil
			panel.reset:SetLabel("Reset to Default")
		end
		if panel.reloadAt and now >= panel.reloadAt then
			panel.reloadAt = nil
			load()
			render()
		end
		if panel.pendingRender then render() end
	end)
	return panel
end

local function show()
	if LF.Available() then
		if not draft or not dirty() then load() end
	else
		server, draft, sel = nil, nil, nil
	end
	render()
end

-- Another addon or the game changed the saved filter: take it in unless there are edits waiting.
local function savedChanged()
	if panel and panel:IsVisible() and LF.Available() and not dirty() then
		load()
		render()
	end
end

SC.Window.AddScreen({
	key = "lootfilter",
	label = "Lootfilter",
	create = create,
	show = show,
	hook = {
		open = "OpenLootFilter", close = "CloseLootFilter", frame = "LFilterFrame",
		extra = {
			UpdateLootFilter = function(...)
				local fn = SC.Hooks.originals.UpdateLootFilter
				if fn then fn(...) end
				savedChanged()
			end,
		},
	},
})
