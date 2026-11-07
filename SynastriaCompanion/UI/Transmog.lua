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
local picking, browsing

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

-- What the look wears, with `override` = { slot, value }, { hand, value } or { set = { [slot] = item } } for what's
-- being tried, and only that when Naked is on.
local function outfitFor(look, override)
	local outfit = {}
	local naked = override ~= nil and T.HasOption(T.NAKED)
	for slot, def in ipairs(T.SLOTS) do
		local id, enchant = T.Appearance(look, slot)
		local value
		if override and override.set then value = override.set[slot]
		elseif override and override.slot == slot then value = override.value
		end
		local tried = value ~= nil
		local triedHand = override ~= nil and override.hand ~= nil and def.enchant == override.hand
		if tried then
			if value == T.EQUIPPED then id = T.Equipped(slot) elseif value == T.HIDDEN then id = nil else id = value end
			if id == 0 then id = nil end
		elseif triedHand then
			id = id or DUMMY_WEAPON
			local chosen = override.value
			if chosen == T.EQUIPPED then enchant = select(2, T.Equipped(slot)) elseif chosen == T.HIDDEN then enchant = nil
			else enchant = chosen end
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

-- The race background is the dressing room's 320x384 picture in four files. Its last rows fade to black (the
-- dressing room's frame covers them), so only the picture down to BG_FLOOR is used: scaled to cover the pane
-- without stretching, kept to that bottom edge, and slid sideways toward the dressing room's model spot (its
-- top-left 231 columns). Textures can't be clipped to a frame, so each piece is cut to the part that shows.
local BG_W, BG_FLOOR = 320, 330
local BG_PIECES = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }
-- The dressing room's model is 231x320 on the picture; the character's feet sit about 80% down the model's frame.
-- The feet go on the near floor, FEET rows down the picture.
local MODEL_W, MODEL_H, FEET_AT, FEET = 231, 320, 0.8, 318

-- Where each piece goes inside a w x h pane: { x, y, w, h, left, right, top, bottom } with texture coordinates, or
-- nil for a piece that falls outside it; and the model's { x, y, w, h }, which may run past the pane's bottom: the
-- space under the feet is empty.
function TransmogUI.BackgroundLayout(w, h)
	local scale = math.max(w / BG_W, h / BG_FLOOR)
	local viewW, viewH = w / scale, h / scale
	local vx = math.max(0, math.min(BG_W - viewW, MODEL_W / 2 - viewW / 2))
	local vy = BG_FLOOR - viewH
	local model = { w = math.min(w, MODEL_W * scale), h = MODEL_H * scale }
	model.x = (w - model.w) / 2
	model.y = (FEET - vy) * scale - FEET_AT * model.h
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

	-- the model stands on the background's floor, with or without the background shown; its frame can run past the
	-- pane's bottom, so it takes no clicks and a frame over the pane does the dragging
	local _, spot = TransmogUI.BackgroundLayout(width - 2 * wi, height - 2 * wi)
	local model = CreateFrame("DressUpModel", "SynastriaCompanionTransmogModel", p)
	model:SetPoint("TOPLEFT", wi + spot.x, -wi - spot.y)
	model:SetSize(spot.w, spot.h)
	model:SetFrameLevel(p:GetFrameLevel() + 2)
	model:EnableMouse(false)
	model:SetUnit("player")
	model.facing = 0
	local drag = CreateFrame("Frame", nil, p)
	drag:SetAllPoints(p)
	drag:SetFrameLevel(p:GetFrameLevel() + 3)
	drag:EnableMouse(true)
	drag:SetScript("OnMouseDown", function() model.dragX = GetCursorPosition() end)
	drag:SetScript("OnMouseUp", function() model.dragX = nil end)
	drag:SetScript("OnHide", function() model.dragX = nil end)
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

	p.hint = S.Text(drag, "small", C.muted)
	p.hint:SetPoint("TOP", 0, -wi - 6)
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
	local message = panel.message and GetTime() < panel.message.untilTime and panel.message.text
	panel.status:SetText(message or bad > 0 and S.Hex(C.bad, S.Count(bad, "Slot") .. " Won't Apply: Not Attuned or Acquired")
		or active and S.Hex(C.good, "Active Look") or S.Hex(C.muted, T.Active() == 0 and "No Look Active" or "Not Active"))
	panel.hint:SetText("")
end

-- Shows a status line for a few seconds, over the usual one.
local function flash(text)
	panel.message = { text = text, untilTime = GetTime() + 4 }
	panel.pending = GetTime() + 4.1
end

-- Sets -------------------------------------------------------------------------------------------------------

local function setMatches(set, q)
	return (state.setClass == "all" or T.SetForClass(set))
		and ((state.setArmor or 0) == 0 or set.armor == state.setArmor or set.armor == 0)
		and (q == "" or set.name:lower():find(q, 1, true) ~= nil)
end

local SET_SORT = {
	name = function(row) return row.set.name:upper() end,
	level = function(row) return row.set.level end,
	pieces = function(row) return row.usable * 100 + row.total end,
}

local function renderSets()
	local sv = panel.sets
	sv.class:SetText(state.setClass == "all" and "All Classes" or "Your Class")
	sv.armor:SetText(state.setArmor == 0 and "Any Armor" or T.ARMOR_TYPES[state.setArmor])
	local q = (state.setSearch or ""):lower()
	local rows = {}
	for _, set in ipairs(T.Sets()) do
		if setMatches(set, q) then
			local usable, total = T.SetCount(set)
			rows[#rows + 1] = { set = set, usable = usable, total = total }
		end
	end
	local get = SET_SORT[state.setSort] or SET_SORT.name
	table.sort(rows, function(a, b)
		local va, vb = get(a), get(b)
		if va == vb then return a.set.name:upper() < b.set.name:upper() end
		if state.setDesc then return va > vb end
		return va < vb
	end)
	sv.table:SetItems(rows, "No Sets Match", sv.keepScroll)
	sv.keepScroll = nil
	panel.status:SetText(S.Count(#rows, "Set"))
	panel.hint:SetText("Hover: Preview  |  Click: Put On")
end

local function setPreview(row)
	local pieces = {}
	for _, piece in ipairs(T.SetPieces(row.set)) do pieces[piece.slot] = piece.id end
	return { set = pieces }
end

local function setTooltip(tt, row)
	besideWindow(tt)
	tt:AddLine(row.set.name, 1, 1, 1)
	for _, piece in ipairs(T.SetPieces(row.set)) do
		local name = itemName(piece.id)
		if piece.usable then
			tt:AddDoubleLine(T.SLOTS[piece.slot].label, name, 0.6, 0.6, 0.66, 1, 1, 1)
		else
			tt:AddDoubleLine(T.SLOTS[piece.slot].label, name, 0.6, 0.6, 0.66, 1, 0.3, 0.3)
		end
	end
	if row.usable < row.total then
		tt:AddLine("Red pieces aren't attuned or acquired on your account, so they're left out.", 1, 0.3, 0.3, true)
	end
	tt:AddLine("Showing on the preview. Click to put it on this look.", 0.6, 0.6, 0.66, true)
	TransmogUI.Preview(setPreview(row))
end

local function putOn(row)
	local applied, skipped = T.ApplySet(state.look, row.set)
	PlaySound("igMainMenuOptionCheckBoxOn")
	browsing = false
	local text = ("Put On %d of %d Pieces"):format(applied, applied + skipped)
	if skipped > 0 then text = text .. ": " .. S.Count(skipped, "Piece") .. " Not Attuned or Acquired" end
	flash(applied > 0 and S.Hex(C.good, text) or S.Hex(C.bad, text))
	TransmogUI.Refresh()
end

function TransmogUI.Refresh()
	panel.pending = nil
	local editing = picking == nil and not browsing
	for _, f in ipairs(panel.editorParts) do if editing then f:Show() else f:Hide() end end
	if picking then panel.picker:Show() else panel.picker:Hide() end
	if browsing then panel.sets:Show() else panel.sets:Hide() end
	if T.HasData() then
		if editing then
			renderLooks()
			renderEditor()
		elseif browsing then
			renderSets()
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

local function createSets(width, height)
	local sv = CreateFrame("Frame", nil, panel)
	sv:SetSize(width, height)
	sv.back = S.Button(sv, "Back", "secondary", 70, function()
		browsing = false
		TransmogUI.Refresh()
	end, "Back to the look.")
	sv.back:SetPoint("TOPLEFT", 0, 0)
	sv.title = S.Text(sv, "large")
	sv.title:SetPoint("LEFT", sv.back, "RIGHT", PAD, 0)
	sv.title:SetText("Item Sets")

	sv.class = S.Dropdown(sv, 120, function(value)
		state.setClass = value
		TransmogUI.Refresh()
	end)
	sv.class:SetOptions({ { value = "mine", text = "Your Class" }, { value = "all", text = "All Classes" } })
	sv.class:SetPoint("TOPLEFT", 0, -(CONTROL_H + GAP))
	sv.armor = S.Dropdown(sv, 110, function(value)
		state.setArmor = value
		TransmogUI.Refresh()
	end)
	local armors = { { value = 0, text = "Any Armor" } }
	for id = 1, 4 do armors[#armors + 1] = { value = id, text = T.ARMOR_TYPES[id] } end
	sv.armor:SetOptions(armors)
	sv.armor:SetPoint("LEFT", sv.class, "RIGHT", GAP, 0)
	sv.search = S.Input(sv, "SynastriaCompanionTransmogSetSearch", width - 230 - 2 * GAP, "Search Sets", 40)
	sv.search:SetPoint("LEFT", sv.armor, "RIGHT", GAP, 0)
	sv.search:HookScript("OnTextChanged", function(self, user)
		if user then
			state.setSearch = self:GetText()
			panel.pending = GetTime() + SEARCH_DELAY
		end
	end)
	sv.search:SetScript("OnEnterPressed", sv.search.ClearFocus)

	local checksY = -2 * (CONTROL_H + GAP)
	sv.naked = labeledCheck(sv, "Naked", "Show only the set's pieces, with nothing else on.", option(T.NAKED))
	sv.naked:SetPoint("TOPLEFT", 0, checksY)
	sv.background = labeledCheck(sv, "Show Background", "Show your race's background behind the preview.", option(T.BACKGROUND))
	sv.background:SetPoint("LEFT", sv.naked, "RIGHT", PAD, 0)

	local top = 3 * (CONTROL_H + GAP)
	sv.table = SC.Table.New(sv, "SynastriaCompanionTransmogSets", width, height - top, {
		columns = {
			{ key = "name", label = "Set", width = 200, stretch = true },
			{ key = "level", label = "Level", width = 56, defaultDesc = true,
				tooltip = "The highest item level among the set's pieces." },
			{ key = "pieces", label = "Pieces", width = 70, defaultDesc = true,
				tooltip = "Pieces you can use, out of the slots the set covers." },
		},
		rowH = ROW_H,
		cell = function(row, key)
			if key == "name" then return row.set.name, row.usable > 0 and C.text or C.muted end
			if key == "level" then return tostring(row.set.level), C.muted end
			return ("%d / %d"):format(row.usable, row.total),
				row.usable == row.total and C.good or row.usable > 0 and C.text or C.muted
		end,
		tooltip = setTooltip,
		onClick = function(row) putOn(row) end,
		onSort = function(key, desc)
			state.setSort, state.setDesc = key, desc
			sv.keepScroll = true
			TransmogUI.Refresh()
		end,
	})
	sv.table.frame:SetPoint("TOPLEFT", 0, -top)
	sv.table:SetSort(state.setSort or "name", state.setDesc)
	for _, row in ipairs(sv.table.rows) do
		row:HookScript("OnLeave", function() if browsing then TransmogUI.Preview() end end)
	end
	sv:Hide()
	return sv
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
	state.setClass = state.setClass or "mine"
	state.setArmor = state.setArmor or T.BestArmor()
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
	panel.setsButton = part(S.Button(panel, "Sets", "secondary", 70, function()
		browsing = true
		panel.sets.search:SetText(state.setSearch or "")
		TransmogUI.Refresh()
	end, "Browse item sets and put one on this look."))
	panel.setsButton:SetPoint("TOPRIGHT", panel, "TOPLEFT", editX + editW, specY)

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
	panel.sets = createSets(width - 2 * PAD - PREVIEW_W - GAP, bodyH)
	panel.sets:SetPoint("TOPLEFT", PAD, -PAD)
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
				flash(S.Hex(C.good, "Imported"))
			else
				flash(S.Hex(C.bad, "The Game Couldn't Read That"))
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
	panel:SetScript("OnHide", function()
		picking = nil
		browsing = false
	end)
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
