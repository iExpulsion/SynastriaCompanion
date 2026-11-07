local _, NS = ...
local SC = NS.SC

-- Perks: the character's perks by category with how many each category allows, and a detail pane for the selected
-- perk's effect, set, options, ability and what unlocks its next rank. Replaces the game's Perk Manager, read-only
-- from the View Perks spell and writable at an innkeeper.
local PerksUI = {}
SC.PerksUI = PerksUI

local S = SC.Style
local C = S.colors
local Perks = SC.Perks
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local LIST_W, SEGMENT_W = 380, 64
local ICON_ROW, ICON = 36, 28
local TOGGLE_Y = PAD + ICON_ROW + PAD
local SECTIONS_Y = TOGGLE_Y + CONTROL_H + PAD
local OPTION_H = 22
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local REFRESH_DELAY = 0.2
-- the server sends the new spec's perks a moment after the switch
local SPEC_DELAY = 2

local panel, state
local selected

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

local function categoryOf(perk, categories)
	for _, c in ipairs(categories) do
		if Perks.SameCategory(perk.cat, c.cat) then return c end
	end
end

-- List -------------------------------------------------------------------------------------------------------

-- Searching shows every group open, so a match is never hidden in a collapsed one.
local function collapsed(key, searching)
	return not searching and state.collapsed[key] == true
end

local function headerItem(key, label, counts, searching)
	local mark = collapsed(key, searching) and "+  " or "-  "
	return { header = S.Hex(C.muted, mark) .. label .. "   " .. counts, key = key }
end

local function categoryCounts(c)
	local count, limit = Perks.ActiveCount(c.cat), Perks.Limit(c.cat)
	local counts = limit and ("%d / %d"):format(count, limit) or tostring(count)
	return S.Hex(limit and count >= limit and C.warn or C.muted, counts)
end

local function matches(perk, q)
	return q == "" or (perk.name or ""):lower():find(q, 1, true) ~= nil
end

local function categoryItems(q)
	local items, first = {}, nil
	local searching = q ~= ""
	for _, c in ipairs(Perks.Categories()) do
		local rows = {}
		for _, perk in ipairs(Perks.InCategory(c.cat)) do
			local shown = state.filter ~= "active" or Perks.Active(perk.id) or perk.id == selected
			if matches(perk, q) and shown then rows[#rows + 1] = { perk = perk } end
		end
		if #rows > 0 then
			local key = "cat" .. c.cat
			items[#items + 1] = headerItem(key, c.label, categoryCounts(c), searching)
			if not collapsed(key, searching) then
				for _, row in ipairs(rows) do items[#items + 1] = row end
			end
			first = first or rows[1].perk.id
		end
	end
	return items, first
end

local function taskItems(q)
	local items, first = {}, nil
	local searching = q ~= ""
	for _, g in ipairs(Perks.TaskList()) do
		local rows = {}
		for _, t in ipairs(g.perks) do
			local perk = PerkMgrPerks[t.id]
			if matches(perk, q) then rows[#rows + 1] = { perk = perk, task = t } end
		end
		if #rows > 0 or (not searching and g.party > 0) then
			local key = "task" .. g.header
			local counts = S.Hex(C.muted, tostring(#g.perks))
			if g.party > 0 then counts = counts .. S.Hex(C.accent, ("  +%d From Party"):format(g.party)) end
			items[#items + 1] = headerItem(key, g.name, counts, searching)
			if not collapsed(key, searching) then
				for _, row in ipairs(rows) do items[#items + 1] = row end
			end
			first = first or rows[1] and rows[1].perk.id
		end
	end
	return items, first
end

local function listItems()
	local q = (state.search or ""):lower()
	if state.filter == "tasks" then return taskItems(q) end
	return categoryItems(q)
end

-- Progress counts can be fractional; whole numbers show without decimals.
local function amount(n)
	n = n or 0
	return n == math.floor(n) and tostring(n) or ("%.1f"):format(n)
end

local function cell(item, key)
	local perk, task = item.perk, item.task
	local rank = Perks.Rank(perk.id)
	local text, color
	if key == "name" then
		text, color = perk.name, rank and C.text or C.muted
		if task and task.short and task.short ~= "" then text = text .. "  " .. S.Hex(C.muted, task.short) end
	elseif key == "rank" and task then
		text, color = task.progress and amount(task.progress) .. " / " .. amount(task.max) or "", C.muted
	elseif key == "rank" then
		text, color = (rank or 0) .. "/" .. Perks.MaxRank(perk), rank and C.muted or C.warn
	elseif key == "on" then
		text, color = Perks.Active(perk.id) and "Active" or "", C.good
	end
	return text, color
end

local function rowTooltip(tt, item)
	local perk, task = item.perk, item.task
	if perk and task then
		tt:AddLine(perk.name, 1, 1, 1)
		tt:AddLine(task.text, 1, 1, 1, true)
		if task.progress then tt:AddLine(("Progress: %s / %s"):format(amount(task.progress), amount(task.max)), 1, 0.82, 0) end
		tt:AddLine("Click for details.", 0.6, 0.6, 0.66, true)
	elseif perk then
		tt:AddLine(perk.name, 1, 1, 1)
		local desc = Perks.Description(perk.id, Perks.Rank(perk.id) or 1)
		if desc then tt:AddLine(desc, 1, 1, 1, true) end
		local _, why = Perks.CanToggle(perk)
		tt:AddLine(why and "Click for details." or "Click for details. Right-click to " ..
			(Perks.Active(perk.id) and "deactivate" or "activate") .. " it.", 0.6, 0.6, 0.66, true)
	elseif item.key then
		tt:AddLine(collapsed(item.key, (state.search or "") ~= "") and "Click to expand." or "Click to collapse.", 0.8, 0.8, 0.8)
		if item.key:find("^task") then
			tt:AddLine("Perks working toward the same kind of task. Party members on it help it progress.", 0.6, 0.6, 0.66, true)
		end
	end
end

-- Detail pane ------------------------------------------------------------------------------------------------

local function pooled(pool, i, make)
	pool[i] = pool[i] or make()
	return pool[i]
end

local function newOption(parent, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, OPTION_H)
	S.Highlight(row)
	row.check = S.Check(row, nil, function() row:Click() end)
	row.check:SetPoint("LEFT", 4, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function(self)
		local o = self.option
		if not (o.on and o.required) and Perks.SetOption(self.perk, o.index, not o.on) then
			PlaySound(o.on and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
			PerksUI.Refresh(true)
		end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.option.name, 1, 1, 1)
		if self.option.tip and self.option.tip ~= "" then GameTooltip:AddLine(self.option.tip, 1, 0.82, 0, true) end
		if self.option.group then
			GameTooltip:AddLine(self.option.required and "One option in this group is always on; pick another to switch."
				or "Only one option in this group can be on; picking it turns the others off.", 0.6, 0.6, 0.66, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function newAction(parent)
	local b = S.Button(parent, "", "secondary", 120, function(self) self.option.run(self, self.option.index - 1) end)
	return b
end

local function renderDetail()
	local d = panel.detail
	local perk = selected and PerkMgrPerks and PerkMgrPerks[selected]
	if perk then d.child:Show() d.none:Hide() else d.child:Hide() d.none:Show() end
	if perk then
		local id, width = perk.id, d.innerW
		local rank, maxRank = Perks.Rank(id), Perks.MaxRank(perk)
		local category = categoryOf(perk, Perks.Categories())
		d.icon:SetTexture(spellIcon(perk.icon))
		d.name:SetText(perk.name)
		d.sub:SetText((category and category.label .. "   " or "") .. (rank and ("Rank %d/%d"):format(rank, maxRank)
			.. (rank >= maxRank and " (Max)" or "") or S.Hex(C.warn, "Not Learned Yet: Its Effect Is Off")))

		local on = Perks.Active(id)
		local ok, why = Perks.CanToggle(perk)
		d.toggle:SetLabel(on and "Deactivate" or "Activate")
		if ok then d.toggle:Enable() else d.toggle:Disable() end
		d.toggle.tooltipText = why
		d.state:SetText(on and S.Hex(C.good, "Active") or S.Hex(C.muted, "Inactive"))

		local y = SECTIONS_Y
		local function header(fs, text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", PAD, -y)
			fs:SetText(text)
			fs:Show()
			y = y + 18
		end
		local function body(fs, text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", PAD, -y)
			fs:SetWidth(width)
			fs:SetText(text)
			fs:Show()
			y = y + (fs:GetStringHeight() or 14) + PAD
		end
		local function section(head, fs, title, text)
			if text and text ~= "" then
				header(head, title)
				body(fs, text)
			else
				head:Hide()
				fs:Hide()
			end
		end

		section(d.currentHead, d.current, rank and ("Rank %d (Current)"):format(rank) or "", rank and Perks.Description(id, rank))
		local nextRank = (rank or 0) + 1
		section(d.nextHead, d.next, ("Rank %d (%s)"):format(nextRank, rank and "Next" or "Once Learned"),
			perk.levels[nextRank] and Perks.Description(id, nextRank))
		section(d.synergyHead, d.synergy, "Works With", Perks.Synergy(id))

		local hasAbility = Perks.HasAbility(perk)
		if hasAbility then
			header(d.abilityHead, "Ability")
			local spell = Perks.Ability(id)
			d.ability.spell = spell
			d.ability.icon:SetTexture(spellIcon(spell))
			d.ability:ClearAllPoints()
			d.ability:SetPoint("TOPLEFT", PAD, -y)
			d.ability:Show()
			d.abilityName:SetText(spell and (GetSpellInfo(spell) or tostring(spell)) or S.Hex(C.muted, "None Chosen"))
			d.choose.perk = id
			d.choose:Show()
			y = y + ICON + PAD
		else
			d.abilityHead:Hide()
			d.ability:Hide()
			d.choose:Hide()
		end

		local set = Perks.SetOf(id)
		if set then
			local members, count = Perks.SetMembers(set)
			local names = {}
			for _, member in ipairs(members) do
				names[#names + 1] = S.Hex(Perks.InSet(member) and C.good or C.muted, "    " .. PerkMgrPerks[member].name)
			end
			local lines = { table.concat(names, "\n") }
			for _, b in ipairs(Perks.SetBonuses(set)) do lines[#lines + 1] = b.text end
			if not Perks.SetCounts(id) then lines[#lines + 1] = S.Hex(C.muted, "This perk doesn't count toward the set.") end
			section(d.setHead, d.set, ("Set: %s   %s"):format(set.name or "", S.Hex(C.muted, ("%d / %d"):format(count, #members))),
				table.concat(lines, "\n\n"))
		else
			section(d.setHead, d.set)
		end

		local options = Perks.Options(id)
		local toggles, actions = 0, 0
		if #options > 0 then header(d.optionHead, "Options") else d.optionHead:Hide() end
		for _, o in ipairs(options) do
			if o.run then
				actions = actions + 1
				local b = pooled(d.actions, actions, function() return newAction(d.child) end)
				b.option = o
				b:SetLabel(o.name)
				b.tooltipText = o.tip
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", PAD, -y)
				b:Show()
				y = y + CONTROL_H + GAP
			else
				toggles = toggles + 1
				local row = pooled(d.options, toggles, function() return newOption(d.child, width + 8) end)
				row.perk, row.option = id, o
				row.label:SetText(o.name)
				row.check:SetChecked(o.on)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", PAD - 4, -y)
				row:Show()
				y = y + OPTION_H
			end
		end
		for i = toggles + 1, #d.options do d.options[i]:Hide() end
		for i = actions + 1, #d.actions do d.actions[i]:Hide() end
		if #options > 0 then y = y + PAD end

		local task = Perks.Task(id)
		if task then
			local lines = { task.text }
			if task.progress then
				lines[#lines + 1] = ("Progress: %s / %s"):format(S.Hex(C.heading, tostring(task.progress)), tostring(task.max))
			end
			if #task.notes > 0 then lines[#lines + 1] = S.Hex(C.muted, table.concat(task.notes, "\n")) end
			section(d.taskHead, d.task, task.unlock and "How to Unlock" or "How to Upgrade", table.concat(lines, "\n\n"))
		else
			section(d.taskHead, d.task)
		end

		local info = Perks.Info(id, rank)
		section(d.infoHead, d.info, "Notes", #info > 0 and S.Hex(C.muted, table.concat(info, "\n\n")) or nil)

		d.child:SetHeight(y)
		d.scroll:UpdateScrollChildRect()
		if d.scroll:GetVerticalScrollRange() > 0 then d.bar:Show() else d.bar:Hide() end
	end
end

-- Refresh ----------------------------------------------------------------------------------------------------

local function footer()
	local on = 0
	for id in pairs(PerkMgrPerks or {}) do
		if Perks.Active(id) and not Perks.IsHidden(PerkMgrPerks[id]) then on = on + 1 end
	end
	panel.status:SetText(S.Count(on, "Active Perk"))
	panel.session:SetText(Perks.Writable() and S.Hex(C.good, "At an Innkeeper: Perks Can Be Activated and Deactivated")
		or S.Hex(C.muted, "Visit an Innkeeper to Activate or Deactivate Perks"))
end

function PerksUI.Refresh(keepScroll)
	panel.pending = nil
	local tasks = state.filter == "tasks"
	panel.showAll:SetKind((state.filter ~= "active" and not tasks) and "selected" or "secondary")
	panel.showActive:SetKind(state.filter == "active" and "selected" or "secondary")
	panel.showTasks:SetKind(tasks and "selected" or "secondary")
	panel.table:SetColumnLabel("rank", tasks and "Progress" or "Rank")
	if Perks.HasData() then
		local items, first = listItems()
		if not (selected and PerkMgrPerks[selected] and not Perks.IsHidden(PerkMgrPerks[selected])) then selected = first end
		local empty = (state.search or "") ~= "" and "No Perks Match"
			or tasks and "No Tasks: Activate a Perk to Work Toward Its Next Rank" or "No Active Perks"
		panel.table:SetItems(items, empty, keepScroll)
		footer()
	else
		selected = nil
		panel.table:SetItems({}, "Perk Data Hasn't Arrived from the Server Yet")
		panel.status:SetText("")
		panel.session:SetText("")
	end
	renderDetail()
end

-- Asks for a refresh shortly, so a burst of updates from the server redraws once.
function PerksUI.Changed(delay)
	if panel and panel:IsVisible() then
		panel.pending = math.max(panel.pending or 0, GetTime() + (delay or REFRESH_DELAY))
		panel.keepScroll = true
	end
end

local function toggle(id)
	if Perks.Toggle(id) then
		PlaySound(Perks.Active(id) and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
		PerksUI.Refresh(true)
	end
end

-- Construction -----------------------------------------------------------------------------------------------

local function createAbility(d)
	local b = CreateFrame("Button", nil, d.child)
	b:SetSize(ICON, ICON)
	S.Panel(b, { 0, 0, 0, 1 }, C.border)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.spell then GameTooltip:SetHyperlink("spell:" .. self.spell) else GameTooltip:SetText("No ability chosen.") end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	d.ability = b
	d.abilityName = S.Text(d.child, "small")
	d.abilityName:SetPoint("LEFT", b, "RIGHT", GAP, 0)
	d.choose = S.Button(d.child, "Choose Ability", "secondary", 110, function(self)
		Perks.ChooseAbility(self.perk, function() PerksUI.Refresh(true) end)
	end, "Pick the ability this perk grants.")
	d.choose:SetPoint("LEFT", d.abilityName, "RIGHT", GAP, 0)
end

local function createDetail(width, height)
	local d = CreateFrame("Frame", nil, panel)
	d:SetSize(width, height)
	S.Well(d)
	local wi = 1 + S.metrics.wellInset
	d.scroll = CreateFrame("ScrollFrame", "SynastriaCompanionPerkDetail", d, "UIPanelScrollFrameTemplate")
	d.scroll:SetPoint("TOPLEFT", wi, -wi)
	d.scroll:SetPoint("BOTTOMRIGHT", -12 - wi, wi)
	d.bar = S.ScrollBar(d.scroll, "SynastriaCompanionPerkDetail")
	local child = CreateFrame("Frame", nil, d.scroll)
	child:SetSize(width - 12 - 2 * wi, height)
	d.scroll:SetScrollChild(child)
	d.child, d.innerW = child, width - 12 - 2 * wi - 2 * PAD

	d.none = S.Text(d, "small", C.muted)
	d.none:SetPoint("CENTER")
	d.none:SetText("Select a perk to see its details.")

	d.icon = child:CreateTexture(nil, "ARTWORK")
	d.icon:SetSize(ICON_ROW, ICON_ROW)
	d.icon:SetPoint("TOPLEFT", PAD, -PAD)
	d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	d.name = S.Text(child, "large")
	d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", GAP, -3)
	d.name:SetPoint("RIGHT", -PAD, 0)
	d.sub = S.Text(child, "small", C.muted)
	d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
	d.sub:SetPoint("RIGHT", -PAD, 0)
	d.toggle = S.Button(child, "Activate", "primary", 100, function() toggle(selected) end)
	d.toggle:SetPoint("TOPLEFT", PAD, -TOGGLE_Y)
	d.state = S.Text(child, "small")
	d.state:SetPoint("LEFT", d.toggle, "RIGHT", GAP, 0)

	for _, key in ipairs({ "current", "next", "synergy", "set", "task", "info" }) do
		d[key .. "Head"] = S.Text(child, "normal", C.heading)
		d[key] = S.Text(child, "small")
		d[key]:SetJustifyH("LEFT")
	end
	d.abilityHead = S.Text(child, "normal", C.heading)
	d.optionHead = S.Text(child, "normal", C.heading)
	d.options, d.actions = {}, {}
	createAbility(d)
	return d
end

local function create(parent, width, height)
	SC.db.perks = SC.db.perks or {}
	state = SC.db.perks
	state.collapsed = state.collapsed or {}
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	panel.showAll = S.Button(panel, "All", "selected", SEGMENT_W, function()
		state.filter = "all"
		PerksUI.Refresh()
	end, "Show every perk your character can have.")
	panel.showAll:SetPoint("TOPLEFT", PAD, -PAD)
	panel.showActive = S.Button(panel, "Active", "secondary", SEGMENT_W, function()
		state.filter = "active"
		PerksUI.Refresh()
	end, "Show only active perks.")
	panel.showActive:SetPoint("LEFT", panel.showAll, "RIGHT", -1, 0)
	panel.showTasks = S.Button(panel, "Tasks", "secondary", SEGMENT_W, function()
		state.filter = "tasks"
		PerksUI.Refresh()
	end, "Show what your active perks are working toward, and your progress on each.")
	panel.showTasks:SetPoint("LEFT", panel.showActive, "RIGHT", -1, 0)
	local searchW = LIST_W - 3 * SEGMENT_W + 2 - GAP
	panel.search = S.Input(panel, "SynastriaCompanionPerkSearch", searchW, "Search Perks", 40)
	panel.search:SetPoint("LEFT", panel.showTasks, "RIGHT", GAP, 0)
	panel.search:HookScript("OnTextChanged", function(self, user)
		if user then
			state.search = self:GetText()
			panel.pending = GetTime() + 0.15
			panel.keepScroll = false
		end
	end)
	panel.search:SetScript("OnEnterPressed", panel.search.ClearFocus)

	local top = -PAD - CONTROL_H - GAP
	local footerH = PAD + CONTROL_H + PAD
	local listH = height + top - footerH

	panel.table = SC.Table.New(panel, "SynastriaCompanionPerkTable", LIST_W, listH, {
		columns = {
			{ key = "name", label = "Perk", width = 190, stretch = true, sortable = false },
			{ key = "rank", label = "Rank", width = 84, sortable = false },
			{ key = "on", label = "Active", width = 52, sortable = false },
		},
		rowH = 20, icons = true, cell = cell,
		icon = function(item) return item.perk and spellIcon(item.perk.icon) end,
		header = function(item) return item.header end,
		isSelected = function(item) return item.perk ~= nil and item.perk.id == selected end,
		tooltip = rowTooltip,
		onClick = function(item, button)
			if item.key and (state.search or "") == "" then
				state.collapsed[item.key] = not state.collapsed[item.key] or nil
				PerksUI.Refresh(true)
			elseif item.perk then
				selected = item.perk.id
				if button == "RightButton" then toggle(selected) else PerksUI.Refresh(true) end
			end
		end,
	})
	panel.table.frame:SetPoint("TOPLEFT", PAD, top)

	panel.detail = createDetail(width - 2 * PAD - LIST_W - GAP, listH)
	panel.detail:SetPoint("TOPLEFT", panel.table.frame, "TOPRIGHT", GAP, 0)

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	panel.session = S.Text(panel, "small")
	panel.session:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + CONTROL_H / 2)

	panel:SetScript("OnUpdate", function()
		if panel.pending and GetTime() >= panel.pending then PerksUI.Refresh(panel.keepScroll) end
	end)
	-- a writable session lasts while the window is open, as the game's lasts while its window is
	panel:SetScript("OnHide", function()
		local window = SC.Window.Frame()
		if not (window and window:IsShown()) and not PerksUI.BuildSuiteShown() then Perks.End() end
	end)
	Perks.onChange = function() PerksUI.Changed() end
	return panel
end

local function show()
	panel.search:SetText(state.search or "")
	PerksUI.Refresh()
end

SC:On("ACTIVE_TALENT_GROUP_CHANGED", function() PerksUI.Changed(SPEC_DELAY) end)

-- Synastria Build Suite's innkeeper line opens its own window and then picks Manage Perks, so the server's open
-- call arrives with Build Suite already showing. Then the session starts without this window covering it, and
-- lasts until both windows are closed.
local watchedBuildSuite

function PerksUI.BuildSuiteShown()
	local f = _G.SynastriaBuildSuiteFrame
	return f ~= nil and f:IsShown() == true
end

local function watchBuildSuite()
	local f = _G.SynastriaBuildSuiteFrame
	if f and watchedBuildSuite ~= f then
		watchedBuildSuite = f
		f:HookScript("OnHide", function()
			local window = SC.Window.Frame()
			if not (window and window:IsShown()) then Perks.End() end
		end)
	end
end

local function openPerks(writeable)
	Perks.Begin(writeable)
	if writeable and PerksUI.BuildSuiteShown() and SC.Window.Current() ~= "perks" then
		watchBuildSuite()
	else
		SC.Window.Open("perks")
	end
end

SC.Window.AddScreen({
	key = "perks",
	label = "Perks",
	create = create,
	show = show,
	-- the game's window opens with the session this one has
	gameArgs = function() return Perks.Writable() end,
	hook = {
		open = "OpenPerkMgr",
		close = "ClosePerkMgr",
		extra = {
			OpenPerkMgr = openPerks,
			ClosePerkMgr = function()
				Perks.End()
				SC.Window.Close("perks")
			end,
			UpdatePerkMgr = function(...)
				local original = SC.Hooks.originals.UpdatePerkMgr
				if original then original(...) end
				PerksUI.Changed()
			end,
		},
	},
})
