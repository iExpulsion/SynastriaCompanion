local _, NS = ...
local SC = NS.SC

-- Transmog: a picker for the ten looks, the selected look's name, specs and slots on the left, and a preview of
-- your character wearing it on the right. Clicking a slot swaps the left side for a searchable list of the
-- appearances you can pick; hovering one tries it on the preview. Replaces the game's Transmog window.
local TransmogUI = {}
SC.TransmogUI = TransmogUI

local S = SC.Style
local C = S.colors
local T = SC.Transmog
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local PREVIEW_W, LABEL_W, LOOKS_W = 320, 46, 170
local ROW_H = 22
local SEARCH_DELAY = 0.2
local REFRESH_DELAY = 0.2
-- a weapon to show an enchant visual on when the hand has none, as the game's window uses
local DUMMY_WEAPON = 4925
local ENCHANT_ICON = 20711
local ROTATE_SPEED = 0.012

local panel, state
local picking

local function itemName(id)
	local name, _, quality = GetItemInfoCustom(id)
	return name and name ~= "" and name or ("Item #" .. id), quality or 1
end

-- The text and color for a slot or enchant visual's value.
local function valueText(value, enchant)
	local text, color
	if value == T.EQUIPPED then
		text, color = "Equipped Look", C.muted
	elseif value == T.HIDDEN then
		text, color = "Hidden", C.muted
	elseif enchant then
		text, color = "Enchant Visual #" .. value, C.text
	else
		local name, quality = itemName(value)
		text, color = name, T.Usable(value) and S.QualityColor(quality) or C.bad
	end
	return text, color
end

-- The tables put tooltips right of the row, over the preview; these go left of the window instead, level with
-- the row.
local function besideWindow(tt)
	local row, window = tt:GetOwner(), SC.Window.Frame()
	if row and window and row:GetLeft() and window:GetLeft() then
		tt:SetOwner(row, "ANCHOR_NONE")
		tt:ClearAllPoints()
		tt:SetPoint("TOPRIGHT", row, "TOPLEFT", window:GetLeft() - row:GetLeft() - 4, 0)
	end
end

-- Preview ----------------------------------------------------------------------------------------------------

-- The model can't wear anything until it has loaded the character, so what it should wear waits in `want` until
-- then.
local function modelReady(model)
	local file = model:GetModel()
	return type(file) == "string" and file ~= ""
end

local function dress(model, outfit)
	model:Undress()
	for _, piece in ipairs(outfit) do
		local link = "item:" .. piece.id .. (piece.enchant and (":" .. piece.enchant) or "")
		model:TryOn(link, T.SLOTS[piece.slot].name)
	end
end

-- What the look wears, with `override` = { slot, value } or { hand, value } for the appearance being tried, and
-- only that piece when Naked is on.
local function outfitFor(look, override)
	local outfit = {}
	local naked = override ~= nil and T.HasOption(T.NAKED)
	for slot, def in ipairs(T.SLOTS) do
		local id, enchant = T.Appearance(look, slot)
		local tried = override and override.slot == slot
		local triedHand = override and override.hand and def.enchant == override.hand
		if tried then
			local value = override.value
			if value == T.EQUIPPED then id = T.Equipped(slot) elseif value == T.HIDDEN then id = nil else id = value end
			if id == 0 then id = nil end
		elseif triedHand then
			id = id or DUMMY_WEAPON
			local value = override.value
			if value == T.EQUIPPED then enchant = select(2, T.Equipped(slot)) elseif value == T.HIDDEN then enchant = nil
			else enchant = value end
			if enchant == 0 then enchant = nil end
		end
		if id and (not naked or tried or triedHand) then
			outfit[#outfit + 1] = { slot = slot, id = id, enchant = enchant }
		end
	end
	return outfit
end

function TransmogUI.Preview(override)
	local p = panel.preview
	p.want = outfitFor(state.look, override)
	local bg = T.HasOption(T.BACKGROUND)
	for _, tex in ipairs(p.bg) do if bg then tex:Show() else tex:Hide() end end
end

-- The race background is the dressing room's 320x384 picture in four files. The dressing room puts its model over
-- the picture's top-left 231x320, which stands the character on the painted floor, so the model keeps that height
-- here: the picture is scaled to cover the pane without stretching, kept to its bottom edge, and slid sideways
-- toward the model's spot. Textures can't be clipped to a frame, so each piece is cut to the part that shows.
local BG_W, BG_H = 320, 384
local BG_PIECES = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }
local MODEL_W, MODEL_H = 231, 320

-- Where each piece goes inside a w x h pane: { x, y, w, h, left, right, top, bottom } with texture coordinates, or
-- nil for a piece that falls outside it; and the model's { x, y, w, h }.
function TransmogUI.BackgroundLayout(w, h)
	local scale = math.max(w / BG_W, h / BG_H)
	local viewW, viewH = w / scale, h / scale
	local vx = math.max(0, math.min(BG_W - viewW, MODEL_W / 2 - viewW / 2))
	local vy = BG_H - viewH
	-- the floor runs the picture's whole width, so the model is centered across the pane; only its height follows
	-- the picture, which puts its feet on the floor
	local my = -vy * scale
	local model = { w = math.min(w, MODEL_W * scale), y = math.max(0, my) }
	model.x = (w - model.w) / 2
	model.h = math.min(h, my + MODEL_H * scale) - model.y
	local out = {}
	for i, piece in ipairs(BG_PIECES) do
		local px, py, pw, ph = piece[1], piece[2], piece[3], piece[4]
		local x0, x1 = math.max(px, vx), math.min(px + pw, vx + w / scale)
		local y0, y1 = math.max(py, vy), math.min(py + ph, vy + h / scale)
		if x1 > x0 and y1 > y0 then
			out[i] = { x = (x0 - vx) * scale, y = (y0 - vy) * scale, w = (x1 - x0) * scale, h = (y1 - y0) * scale,
				left = (x0 - px) / pw, right = (x1 - px) / pw, top = (y0 - py) / ph, bottom = (y1 - py) / ph }
		end
	end
	return out, model
end

-- The pieces sit on a frame of their own above the pane: the 3.3.5 client has no texture sublevels, so textures on
-- the pane's own layer could draw under its fill.
function TransmogUI.Background(parent, inset, w, h)
	local path = DressUpTexturePath and DressUpTexturePath() or nil
	local layout = TransmogUI.BackgroundLayout(w, h)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	holder:SetFrameLevel(parent:GetFrameLevel() + 1)
	local list = {}
	for i = 1, #BG_PIECES do
		local cut = layout[i]
		if cut and path then
			local tex = holder:CreateTexture(nil, "BACKGROUND")
			tex:SetTexture(path .. i)
			tex:SetTexCoord(cut.left, cut.right, cut.top, cut.bottom)
			tex:SetSize(cut.w, cut.h)
			tex:SetPoint("TOPLEFT", inset + cut.x, -inset - cut.y)
			tex:Hide()
			list[#list + 1] = tex
		end
	end
	return list
end

local function createPreview(width, height)
	local p = CreateFrame("Frame", nil, panel)
	p:SetSize(width, height)
	S.Well(p)
	local wi = 1 + S.metrics.wellInset
	p.bg = TransmogUI.Background(p, wi, width - 2 * wi, height - 2 * wi)

	-- the model stands where the dressing room puts it on the background, with or without the background shown
	local _, spot = TransmogUI.BackgroundLayout(width - 2 * wi, height - 2 * wi)
	local model = CreateFrame("DressUpModel", "SynastriaCompanionTransmogModel", p)
	model:SetPoint("TOPLEFT", wi + spot.x, -wi - spot.y)
	model:SetSize(spot.w, spot.h)
	model:SetFrameLevel(p:GetFrameLevel() + 2)
	model:SetUnit("player")
	model.facing = 0
	model:EnableMouse(true)
	model:SetScript("OnMouseDown", function(self)
		self.dragX = GetCursorPosition()
	end)
	model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
	model:SetScript("OnHide", function(self) self.dragX = nil end)
	model:SetScript("OnUpdate", function(self)
		if self.dragX then
			local x = GetCursorPosition()
			self.facing = self.facing + (x - self.dragX) * ROTATE_SPEED
			self.dragX = x
			self:SetFacing(self.facing)
		end
		if p.want and modelReady(self) then
			dress(self, p.want)
			p.want = nil
		end
	end)
	model:SetScript("OnShow", function(self)
		self:SetUnit("player")
		self:SetFacing(self.facing)
	end)
	p.model = model

	local over = CreateFrame("Frame", nil, p)
	over:SetAllPoints(p)
	over:SetFrameLevel(p:GetFrameLevel() + 3)
	p.hint = S.Text(over, "small", C.muted)
	p.hint:SetPoint("BOTTOM", 0, wi + 6)
	p.hint:SetText("Drag to Rotate")
	return p
end

-- Editor -----------------------------------------------------------------------------------------------------

local function slotRows()
	local rows = {}
	for slot, def in ipairs(T.SLOTS) do
		rows[#rows + 1] = { slot = slot, label = def.label }
		if def.enchant then rows[#rows + 1] = { hand = def.enchant, label = def.label .. " Enchant" } end
	end
	return rows
end
local SLOT_ROWS = slotRows()

local function rowValue(row)
	return row.hand and T.Enchant(state.look, row.hand) or T.Slot(state.look, row.slot)
end

local function slotIcon(row)
	local value = rowValue(row)
	local icon
	if row.hand then
		icon = select(3, GetSpellInfo(ENCHANT_ICON))
	elseif value > T.HIDDEN then
		icon = select(10, GetItemInfoCustom(value))
	else
		icon = select(2, GetInventorySlotInfo(T.SLOTS[row.slot].name))
	end
	return icon
end

local function slotTooltip(tt, row)
	besideWindow(tt)
	local value = rowValue(row)
	if not row.hand and value > T.HIDDEN then
		tt:SetHyperlink("item:" .. value)
		if not T.Usable(value) then
			tt:AddLine("Not attuned or acquired on your account, so it won't apply.", 1, 0.3, 0.3, true)
		end
	else
		tt:AddLine(row.label, 1, 1, 1)
		tt:AddLine(value == T.EQUIPPED and "Shows the look of what you have equipped."
			or value == T.HIDDEN and "Shows nothing in this slot." or valueText(value, true), 0.8, 0.8, 0.8, true)
	end
	tt:AddLine("Click to choose. Right-click to go back to your equipped look.", 0.6, 0.6, 0.66, true)
end

local function openPicker(row)
	picking = { slot = row.slot, hand = row.hand, label = row.label, filter = 0, search = "" }
	panel.picker.search:SetText("")
	TransmogUI.Refresh()
end

-- Picker -----------------------------------------------------------------------------------------------------

local function choiceValue(row)
	return row.value
end

local function currentPick()
	return picking.hand and T.Enchant(state.look, picking.hand) or T.Slot(state.look, picking.slot)
end

local function choiceCell(row, key)
	local text, color
	if key == "name" then
		text, color = valueText(row.value, picking.hand ~= nil)
		if not row.owned then color = C.bad end
	elseif key == "type" and not picking.hand and row.value > T.HIDDEN then
		local _, _, _, _, _, _, subclass = GetItemInfoCustom(row.value)
		text, color = subclass or "", C.muted
	end
	return text, color
end

local function choiceIcon(row)
	local icon
	if row.value > T.HIDDEN and not picking.hand then icon = select(10, GetItemInfoCustom(row.value)) end
	return icon
end

local function choiceTooltip(tt, row)
	besideWindow(tt)
	local value = row.value
	if not picking.hand and value > T.HIDDEN then
		tt:SetHyperlink("item:" .. value)
	else
		tt:AddLine((valueText(value, picking.hand ~= nil)), 1, 1, 1)
	end
	if not row.owned then tt:AddLine("Not attuned or acquired on your account, so it won't apply.", 1, 0.3, 0.3, true) end
	tt:AddLine("Showing on the preview. Click to choose it.", 0.6, 0.6, 0.66, true)
	TransmogUI.Preview(picking.hand and { hand = picking.hand, value = value } or { slot = picking.slot, value = value })
end

local function pick(row)
	if picking.hand then T.SetEnchant(state.look, picking.hand, row.value) else T.SetSlot(state.look, picking.slot, row.value) end
	PlaySound("igMainMenuOptionCheckBoxOn")
	picking = nil
	TransmogUI.Refresh()
end

local function renderPicker()
	local pk = panel.picker
	pk.title:SetText(picking.label)
	local def = picking.slot and T.SLOTS[picking.slot]
	local filters = def and def.filter and T.FILTERS[def.filter]
	if filters then
		pk.filter:SetOptions(filters)
		for _, o in ipairs(filters) do if o.value == picking.filter then pk.filter:SetText(o.text) end end
		pk.filter:Show()
	else
		pk.filter:Hide()
	end
	local searchable = T.HasSearch() and not picking.hand
	if searchable then pk.search:Show() pk.dupes:Show() else pk.search:Hide() pk.dupes:Hide() end
	pk.naked.check:SetChecked(T.HasOption(T.NAKED))
	pk.background.check:SetChecked(T.HasOption(T.BACKGROUND))
	pk.dupes.check:SetChecked(T.HasOption(T.DUPLICATES))

	local rows = picking.hand and T.EnchantChoices(state.look, picking.hand)
		or T.Choices(state.look, picking.slot, picking.filter, picking.search)
	pk.table:SetItems(rows, "Nothing to Pick for This Slot", pk.keepScroll)
	pk.keepScroll = nil
	local items = math.max(0, #rows - 2)
	panel.status:SetText(S.Count(items, picking.hand and "Enchant Visual" or "Appearance"))
	panel.hint:SetText("Hover: Preview  |  Click: Choose")
end

-- Refresh ----------------------------------------------------------------------------------------------------

-- The look picker lists all ten, with the active one marked.
local function lookText(look)
	return T.Name(look) .. (T.Active() == look and "  " .. S.Hex(C.good, "Active") or "")
end

local function renderLooks()
	local options = {}
	for look = 1, T.MAX do options[look] = { value = look, text = lookText(look) } end
	panel.looks:SetOptions(options)
	panel.looks:SetText(lookText(state.look))
	panel.lookOptions = options
end

local function renderEditor()
	local look = state.look
	if not panel.name.focused then panel.name:SetText(T.Name(look)) end
	for spec, box in ipairs(panel.specs) do box:SetChecked(T.HasSpec(look, spec)) end
	panel.slots:SetItems(SLOT_ROWS, nil, true)
	local active = T.Active() == look
	panel.activate:SetLabel(active and "Deactivate" or "Activate")
	local bad = #T.Unusable(look)
	panel.status:SetText(bad > 0 and S.Hex(C.bad, S.Count(bad, "Slot") .. " Won't Apply: Not Attuned or Acquired")
		or active and S.Hex(C.good, "Active Look") or S.Hex(C.muted, T.Active() == 0 and "No Look Active" or "Not Active"))
	panel.hint:SetText("")
end

function TransmogUI.Refresh()
	panel.pending = nil
	local editing = picking == nil
	for _, f in ipairs(panel.editorParts) do if editing then f:Show() else f:Hide() end end
	if editing then panel.picker:Hide() else panel.picker:Show() end
	if T.HasData() then
		if editing then
			renderLooks()
			renderEditor()
		else
			renderPicker()
		end
		TransmogUI.Preview()
	else
		panel.status:SetText(S.Hex(C.muted, "Your Looks Haven't Arrived from the Server Yet"))
	end
end

function TransmogUI.Changed(delay)
	if panel and panel:IsVisible() then
		panel.pending = math.max(panel.pending or 0, GetTime() + (delay or REFRESH_DELAY))
	end
end

-- Construction -----------------------------------------------------------------------------------------------

local function labeledCheck(parent, label, tooltip, onClick)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(CONTROL_H)
	row.check = S.Check(row, nil, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
	row.label:SetText(label)
	row:SetWidth(S.CHECK_H + 6 + row.label:GetStringWidth() + 4)
	row:SetScript("OnClick", function() onClick(not row.check.on) end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function option(flag)
	return function(on)
		T.SetOption(flag, on)
		if panel.picker:IsShown() then panel.picker.keepScroll = true end
		TransmogUI.Refresh()
	end
end

local function createPicker(width, height)
	local pk = CreateFrame("Frame", nil, panel)
	pk:SetSize(width, height)
	pk.back = S.Button(pk, "Back", "secondary", 70, function()
		picking = nil
		TransmogUI.Refresh()
	end, "Back to the look.")
	pk.back:SetPoint("TOPLEFT", 0, 0)
	pk.title = S.Text(pk, "large")
	pk.title:SetPoint("LEFT", pk.back, "RIGHT", PAD, 0)

	pk.filter = S.Dropdown(pk, 150, function(value)
		picking.filter = value or 0
		TransmogUI.Refresh()
	end)
	pk.filter:SetPoint("TOPLEFT", 0, -(CONTROL_H + GAP))
	pk.search = S.Input(pk, "SynastriaCompanionTransmogSearch", width - 150 - GAP, "Search Appearances", 63)
	pk.search:SetPoint("LEFT", pk.filter, "RIGHT", GAP, 0)
	pk.search:HookScript("OnTextChanged", function(self, user)
		if user and picking then
			picking.search = self:GetText()
			panel.pending = GetTime() + SEARCH_DELAY
		end
	end)
	pk.search:SetScript("OnEnterPressed", pk.search.ClearFocus)

	local checksY = -2 * (CONTROL_H + GAP)
	pk.naked = labeledCheck(pk, "Naked", "Show only the appearance you're trying, with nothing else on.", option(T.NAKED))
	pk.naked:SetPoint("TOPLEFT", 0, checksY)
	pk.background = labeledCheck(pk, "Show Background", "Show your race's background behind the preview.", option(T.BACKGROUND))
	pk.background:SetPoint("LEFT", pk.naked, "RIGHT", PAD, 0)
	pk.dupes = labeledCheck(pk, "Show Duplicates", "Also list items that look the same as one already listed. A search always shows them.",
		option(T.DUPLICATES))
	pk.dupes:SetPoint("LEFT", pk.background, "RIGHT", PAD, 0)

	local top = 3 * (CONTROL_H + GAP)
	pk.table = SC.Table.New(pk, "SynastriaCompanionTransmogChoices", width, height - top, {
		columns = {
			{ key = "name", label = "Appearance", width = 200, stretch = true, sortable = false },
			{ key = "type", label = "Type", width = 130, sortable = false },
		},
		rowH = ROW_H, icons = true, cell = choiceCell, icon = choiceIcon, tooltip = choiceTooltip,
		isSelected = function(row) return picking ~= nil and choiceValue(row) == currentPick() end,
		onClick = function(row) pick(row) end,
	})
	pk.table.frame:SetPoint("TOPLEFT", 0, -top)
	-- leaving a row puts the look back on the preview; entering the next one tries that one on
	for _, row in ipairs(pk.table.rows) do
		row:HookScript("OnLeave", function() if picking then TransmogUI.Preview() end end)
	end
	pk:Hide()
	return pk
end

StaticPopupDialogs.SYNASTRIA_COMPANION_TRANSMOG_RESET = {
	text = "Reset %s? Every slot goes back to your equipped look.",
	button1 = "Reset",
	button2 = "Cancel",
	OnAccept = function(_, look)
		T.Reset(look)
		TransmogUI.Refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function create(parent, width, height)
	SC.db.transmog = SC.db.transmog or {}
	state = SC.db.transmog
	state.look = state.look or (T.HasData() and T.Active() > 0 and T.Active()) or 1
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)
	panel.editorParts = {}
	local function part(f)
		panel.editorParts[#panel.editorParts + 1] = f
		return f
	end

	local footerH = PAD + CONTROL_H + PAD
	local bodyH = height - PAD - footerH

	local editX = PAD
	local editW = width - 2 * PAD - PREVIEW_W - GAP

	local lookLabel = part(S.Text(panel, "small", C.muted))
	lookLabel:SetPoint("TOPLEFT", editX, -PAD - 5)
	lookLabel:SetText("Look")
	panel.looks = part(S.Dropdown(panel, LOOKS_W, function(look)
		state.look = look
		TransmogUI.Refresh()
	end))
	panel.looks:SetPoint("TOPLEFT", editX + LABEL_W, -PAD)
	panel.name = part(S.Input(panel, "SynastriaCompanionTransmogName", editW - LABEL_W - LOOKS_W - GAP, "Look Name",
		T.NAME_MAX))
	panel.name:SetPoint("LEFT", panel.looks, "RIGHT", GAP, 0)
	local function rename(self)
		if state then self:SetText(T.Rename(state.look, self:GetText())) end
		renderLooks()
	end
	panel.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	panel.name:HookScript("OnEditFocusLost", rename)

	local specY = -PAD - CONTROL_H - GAP
	local specLabel = part(S.Text(panel, "small", C.muted))
	specLabel:SetPoint("TOPLEFT", editX, specY - 5)
	specLabel:SetText("Specs")
	panel.specs = {}
	for spec = 1, T.SPECS do
		local row = part(labeledCheck(panel, tostring(spec), ("Activate this look when you switch to spec %d."):format(spec),
			function(on)
				T.SetSpec(state.look, spec, on)
				TransmogUI.Refresh()
			end))
		row:SetPoint("TOPLEFT", editX + LABEL_W + (spec - 1) * 38, specY)
		panel.specs[spec] = row.check
	end

	local slotsY = specY - CONTROL_H - GAP
	panel.slots = SC.Table.New(panel, "SynastriaCompanionTransmogSlots", editW, bodyH + slotsY + PAD, {
		columns = {
			{ key = "label", label = "Slot", width = 136, sortable = false },
			{ key = "value", label = "Appearance", width = 140, stretch = true, sortable = false },
		},
		rowH = ROW_H, icons = true,
		cell = function(row, key)
			if key == "label" then return row.label, C.muted end
			return valueText(rowValue(row), row.hand ~= nil)
		end,
		icon = slotIcon, tooltip = slotTooltip,
		onClick = function(row, button)
			if button == "RightButton" then
				if row.hand then T.SetEnchant(state.look, row.hand, T.EQUIPPED) else T.SetSlot(state.look, row.slot, T.EQUIPPED) end
				TransmogUI.Refresh()
			else
				openPicker(row)
			end
		end,
	})
	panel.slots.frame:SetPoint("TOPLEFT", editX, slotsY)
	part(panel.slots.frame)

	panel.picker = createPicker(width - 2 * PAD - PREVIEW_W - GAP, bodyH)
	panel.picker:SetPoint("TOPLEFT", PAD, -PAD)

	panel.preview = createPreview(PREVIEW_W, bodyH)
	panel.preview:SetPoint("TOPRIGHT", -PAD, -PAD)

	local footerY = PAD + CONTROL_H / 2
	panel.activate = part(S.Button(panel, "Activate", "primary", 100, function()
		T.Activate(T.Active() == state.look and 0 or state.look)
		TransmogUI.Refresh()
	end, "Wear this look, or turn transmog off while it's the active one."))
	panel.activate:SetPoint("BOTTOMLEFT", PAD, PAD)
	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD + 100 + PAD, footerY)

	panel.reset = part(S.Button(panel, "Reset", "danger", 70, function()
		local popup = StaticPopup_Show("SYNASTRIA_COMPANION_TRANSMOG_RESET", T.Name(state.look))
		if popup then popup.data = state.look end
	end, "Put every slot back to your equipped look."))
	panel.reset:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	panel.export = part(S.Button(panel, "Export", "secondary", 70, function()
		SC.TextDialog.ShowExport("Export Look", "This look's appearances. Copy it with Ctrl+C.", T.Export(state.look) or "")
	end, "Copy this look as text to share it or keep it."))
	panel.export:SetPoint("RIGHT", panel.reset, "LEFT", -GAP, 0)
	panel.import = part(S.Button(panel, "Import", "secondary", 70, function()
		local look = state.look
		SC.TextDialog.AskImport("Import Look", "Replaces " .. T.Name(look) .. " with the pasted look.", function(text)
			if T.Import(look, text) then
				panel.status:SetText(S.Hex(C.good, "Imported"))
			else
				panel.status:SetText(S.Hex(C.bad, "The Game Couldn't Read That"))
			end
			TransmogUI.Refresh()
		end)
	end, "Paste a shared look into this one."))
	panel.import:SetPoint("RIGHT", panel.export, "LEFT", -GAP, 0)
	panel.useEquipped = part(S.Button(panel, "Use Equipped", "secondary", 100, function()
		T.UseEquipped(state.look)
		TransmogUI.Refresh()
	end, "Set every slot to the item you have equipped there."))
	panel.useEquipped:SetPoint("RIGHT", panel.import, "LEFT", -GAP, 0)
	panel.hint = S.Text(panel, "small", C.muted)
	panel.hint:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -PAD, footerY)

	panel:SetScript("OnUpdate", function()
		if panel.pending and GetTime() >= panel.pending then
			if picking then panel.picker.keepScroll = true end
			TransmogUI.Refresh()
		end
	end)
	panel:SetScript("OnHide", function() picking = nil end)
	T.onChange = function() TransmogUI.Changed() end
	return panel
end

local function show()
	TransmogUI.Refresh()
end

SC:On("PLAYER_EQUIPMENT_CHANGED", function() TransmogUI.Changed() end)
SC:On("ACTIVE_TALENT_GROUP_CHANGED", function() TransmogUI.Changed(1) end)

SC.Window.AddScreen({
	key = "transmog",
	label = "Transmog",
	create = create,
	show = show,
	spell = T.SPELL,
	needsSpell = function() return not T.HasData() end,
	hook = {
		open = "OpenTransmog",
		close = "CloseTransmog",
		frame = "TransmogFrame",
		extra = {
			UpdateTransmogMenu = function(...)
				local original = SC.Hooks.originals.UpdateTransmogMenu
				if original then original(...) end
				TransmogUI.Changed()
			end,
		},
	},
})
