local _, NS = ...
local SC = NS.SC

-- Transmog, laid out like the retail wardrobe: the look's name, specs and Activate along the top; your character
-- on the left with a button for each slot around it; and on the right, Items (a page of models wearing each
-- appearance you can pick for the selected slot) and Sets. Hovering an appearance or a set tries it on your
-- character. Replaces the game's Transmog window.
local TransmogUI = {}
SC.TransmogUI = TransmogUI

local S = SC.Style
local C = S.colors
local T = SC.Transmog
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local DOLL_W = 360
local SLOT_SIZE, SLOT_GAP, ENCHANT_SIZE = 36, 4, 22
local STRIP_H = CONTROL_H + GAP
-- The window's size for this screen, and the Items grid: as many cells of the game's window's size as fit (12 at
-- full size), stretched to fill, and never fewer than 3x2 when a small screen shrinks the window.
local WINDOW_W, WINDOW_H = 1230, 816
local CELL_W, CELL_H = 160, 192
-- the game's window's model frame in each box: 160 wide, the box's 192 less its 26 for the item button
local STOCK_MODEL_W, STOCK_MODEL_H = 160, 166
local MIN_COLS, MIN_ROWS = 3, 2
local NAME_H = 16
local LOOK_LABEL_W, TAB_W, PAGE_TEXT_W = 36, 80, 84
local ROW_H = 22
local SEARCH_DELAY = 0.2
local REFRESH_DELAY = 0.2
-- a weapon to show an enchant visual on when the hand has none, as the game's window uses
local DUMMY_WEAPON = 4925
local ENCHANT_ICON = 20711
local HIDDEN_MARK = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ROTATE_SPEED = 0.012
local QUARTER = 1.57079632
-- seconds after a cell first dresses when it's framed again
local SETTLE = { 0.2, 0.6 }

-- Slot buttons: the left column, the right column, and the weapons under the character.
local LEFT_SLOTS = { 1, 2, 3, 4, 5, 6, 7 }
local RIGHT_SLOTS = { 8, 9, 10, 11 }
local WEAPON_SLOTS = { 12, 13, 14 }

local panel, state

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

-- What's selected for editing: a slot, or a weapon hand's enchant visual.
local function selection()
	return state.slot or 1, state.hand
end

local function selectionLabel()
	local slot, hand = selection()
	return hand and (T.SLOTS[hand == 1 and T.MAIN_HAND or T.OFF_HAND].label .. " Enchant") or T.SLOTS[slot].label
end

local function currentValue()
	local slot, hand = selection()
	return hand and T.Enchant(state.look, hand) or T.Slot(state.look, slot)
end

-- Preview ----------------------------------------------------------------------------------------------------

-- A model can't wear anything until it has loaded the character, so what it should wear waits until then.
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

-- Weapons that can only go in the off hand. A preview model puts any other weapon in the main hand, whatever slot
-- it's tried in, and a two-hander replaces both, so the weapon tried last is the one that shows.
local OFF_HAND_ONLY = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

local function offHandOnly(id)
	return id ~= nil and OFF_HAND_ONLY[select(9, GetItemInfoCustom(id))] == true
end

-- What the look wears, with `override` = { slot, value }, { hand, value } or { set = { [slot] = item } } for what's
-- being tried, and only that when Naked is on (both weapons, for an enchant visual). The weapon in focus goes on
-- last so it's the one that shows: the off hand while it's being tried, else the main hand.
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
		local pairedWeapon = override ~= nil and override.hand ~= nil and def.enchant ~= nil
		if id and (not naked or tried or triedHand or pairedWeapon) then
			outfit[#outfit + 1] = { slot = slot, id = id, enchant = enchant }
		end
	end
	local offFocus = override ~= nil and (override.slot == T.OFF_HAND or override.hand == 2)
	local focus = offFocus and T.OFF_HAND or T.MAIN_HAND
	for i, piece in ipairs(outfit) do
		if piece.slot == focus then
			table.remove(outfit, i)
			outfit[#outfit + 1] = piece
			break
		end
	end
	return outfit
end

-- The preview is always dressed piece by piece. Your real character (SetUnit alone) isn't used for the look you're
-- wearing: the client draws two two-handers with only the off-hand one, in the left hand.
function TransmogUI.Preview(override)
	local p = panel.preview
	p.want = outfitFor(state.look, override)
	local bg = T.HasOption(T.BACKGROUND)
	for _, tex in ipairs(p.bg) do if bg then tex:Show() else tex:Hide() end end
	p.naked.check:SetChecked(T.HasOption(T.NAKED))
	p.background.check:SetChecked(bg)
end

-- What's being hovered stays on the preview through redraws (a click on what's hovered redraws the screen) until
-- the mouse leaves it.
function TransmogUI.Hover(override)
	panel.hover = override
	TransmogUI.Preview(override)
end

function TransmogUI.Unhover()
	panel.hover = nil
	TransmogUI.Preview(TransmogUI.ChosenPreview())
end

-- The race background is the dressing room's 320x384 picture in four files. Its last rows fade to black (the
-- dressing room's frame covers them), so only the picture down to BG_FLOOR is used: scaled to cover the pane
-- without stretching, kept to that bottom edge, and slid sideways toward the dressing room's model spot (its
-- top-left 231 columns). Textures can't be clipped to a frame, so each piece is cut to the part that shows.
local BG_W, BG_FLOOR = 320, 330
local BG_PIECES = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }
-- The dressing room's model is 231x320 on the picture; the character's feet sit about 80% down the model's frame.
-- The feet go on the near floor, FEET rows down the picture.
local MODEL_W, MODEL_H, FEET_AT, FEET = 231, 320, 0.8, 302
TransmogUI.FEET, TransmogUI.FLOOR = FEET, BG_FLOOR

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

-- The character: the background and model in an area of their own, and a frame over the area for the rotate drag.
-- The model's frame spans `fullW` (the whole panel), centered on the area, so wide weapons and their glow aren't
-- cut off at the area's sides; a model's size follows its frame's height, so the character doesn't change. It can
-- also run past the area's bottom (the space under the feet is empty), so it takes no clicks.
local function createCharacter(parent, x, y, w, h, fullW)
	local p = CreateFrame("Frame", nil, parent)
	p:SetPoint("TOPLEFT", x, -y)
	p:SetSize(w, h)
	p.bg = TransmogUI.Background(p, 0, w, h)
	local _, spot = TransmogUI.BackgroundLayout(w, h)
	local modelW = math.max(spot.w, fullW or spot.w)
	local model = CreateFrame("DressUpModel", "SynastriaCompanionTransmogModel", p)
	model:SetPoint("TOPLEFT", spot.x + (spot.w - modelW) / 2, -spot.y)
	model:SetSize(modelW, spot.h)
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
			local cx = GetCursorPosition()
			self.facing = self.facing + (cx - self.dragX) * ROTATE_SPEED
			self.dragX = cx
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
	p.model, p.drag = model, drag
	return p
end

-- Slot buttons ------------------------------------------------------------------------------------------------

local function slotValue(b)
	return b.hand and T.Enchant(state.look, b.hand) or T.Slot(state.look, b.slot)
end

local function slotLabel(b)
	return b.hand and (T.SLOTS[b.slot].label .. " Enchant") or T.SLOTS[b.slot].label
end

local function paintSlot(b)
	local value = slotValue(b)
	local slotName = T.SLOTS[b.slot].name
	local icon, alpha, bad = nil, 1, false
	if b.hand then
		icon = select(3, GetSpellInfo(ENCHANT_ICON))
		alpha = value == T.EQUIPPED and 0.5 or value == T.HIDDEN and 0.25 or 1
	elseif value > T.HIDDEN then
		icon = select(10, GetItemInfoCustom(value))
		bad = not T.Usable(value)
	elseif value == T.EQUIPPED then
		local equipped = T.Equipped(b.slot)
		icon = equipped > 0 and select(10, GetItemInfoCustom(equipped)) or nil
	end
	icon = icon or select(2, GetInventorySlotInfo(slotName))
	if value == T.HIDDEN and not b.hand then alpha = 0.3 end
	b.icon:SetTexture(icon)
	b.icon:SetAlpha(alpha)
	if value == T.HIDDEN then b.hiddenMark:Show() else b.hiddenMark:Hide() end
	if bad then b.icon:SetVertexColor(1, 0.3, 0.3) else b.icon:SetVertexColor(1, 1, 1) end
	local slot, hand = selection()
	local selected = b.hand == hand and (hand ~= nil or b.slot == slot)
	b:SetBackdropBorderColor(unpack(selected and C.accent or bad and C.bad or C.border))
end

local function slotTooltip(b)
	local value = slotValue(b)
	GameTooltip:SetOwner(b, b.anchor)
	if not b.hand and value > T.HIDDEN then
		GameTooltip:SetHyperlink("item:" .. value)
		if not T.Usable(value) then
			GameTooltip:AddLine("Not attuned or acquired on your account, so it won't apply.", 1, 0.3, 0.3, true)
		end
	else
		GameTooltip:AddLine(slotLabel(b), 1, 1, 1)
		GameTooltip:AddLine(value == T.EQUIPPED and "Shows the look of what you have equipped."
			or value == T.HIDDEN and "Shows nothing in this slot." or valueText(value, true), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Click to pick its appearance. Right-click to go back to your equipped look.", 0.6, 0.6, 0.66, true)
	GameTooltip:Show()
end

local function newSlotButton(parent, slot, hand, size, anchor)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	S.Panel(b, { 0, 0, 0, 1 }, C.border)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hover = S.Solid(b, "HIGHLIGHT", { 1, 1, 1, 0.15 })
	hover:SetAllPoints(b.icon)
	-- a cross in the corner marks a hidden slot, which otherwise looks like an empty one
	b.hiddenMark = b:CreateTexture(nil, "OVERLAY")
	b.hiddenMark:SetTexture(HIDDEN_MARK)
	b.hiddenMark:SetSize(math.floor(size * 0.5), math.floor(size * 0.5))
	b.hiddenMark:SetPoint("BOTTOMRIGHT", -1, 1)
	b.hiddenMark:Hide()
	b.slot, b.hand, b.anchor = slot, hand, anchor
	b:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			if self.hand then T.SetEnchant(state.look, self.hand, T.EQUIPPED) else T.SetSlot(state.look, self.slot, T.EQUIPPED) end
		else
			state.slot, state.hand, state.tab = self.slot, self.hand, "items"
			panel.items.page, panel.items.searchText = nil, nil
			panel.items.search:SetText("")
			PlaySound("igMainMenuOptionCheckBoxOn")
		end
		TransmogUI.Refresh()
	end)
	b:SetScript("OnEnter", slotTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Items grid -------------------------------------------------------------------------------------------------

-- Each cell is a model of your character wearing one appearance, framed the way the game's window frames it:
-- armor on its zoomed camera (Synastria's GetTransmogOffsets gives the zoom, position and facing for your race),
-- weapons and enchant visuals on the full camera, turned sideways.

local function weaponSelection()
	local slot, hand = selection()
	return hand ~= nil or slot >= T.MAIN_HAND
end

-- What a cell wears: the look without the selected slot, then the appearance it shows. Armor cells leave weapons
-- off, since their glow fills a zoomed-in cell; the ranged slot leaves the hands empty, as the game's window does
-- it. An enchant visual is shown on the pair of weapons, the other hand keeping its own, even with Naked on.
local function cellOutfit(value)
	local slot, hand = selection()
	local naked = T.HasOption(T.NAKED)
	local outfit = {}
	local weaponSlot = hand and (hand == 1 and T.MAIN_HAND or T.OFF_HAND)
	local armor = not weaponSelection()
	for i in ipairs(T.SLOTS) do
		local isWeapon = i == T.MAIN_HAND or i == T.OFF_HAND
		local skip = i == slot or i == 14 or i == weaponSlot or (isWeapon and (armor or (slot == 14 and not hand)))
		local otherHand = hand ~= nil and isWeapon and i ~= weaponSlot
		if (not naked or otherHand) and not skip then
			local id, enchant = T.Appearance(state.look, i)
			if id then outfit[#outfit + 1] = { slot = i, id = id, enchant = enchant } end
		end
	end
	local shown
	if hand then
		local weapon = T.Appearance(state.look, weaponSlot) or DUMMY_WEAPON
		local enchant = value
		if value == T.EQUIPPED then enchant = select(2, T.Equipped(weaponSlot)) elseif value == T.HIDDEN then enchant = nil end
		outfit[#outfit + 1] = { slot = weaponSlot, id = weapon, enchant = (enchant or 0) > 0 and enchant or nil }
		shown = weapon
	else
		local id = value
		if value == T.EQUIPPED then id = T.Equipped(slot) elseif value == T.HIDDEN then id = nil end
		if id and id > 0 then outfit[#outfit + 1] = { slot = slot, id = id } end
		shown = id or 0
	end
	return outfit, shown
end

local function frameCell(model, shown)
	local slot, hand = selection()
	if hand or slot >= T.MAIN_HAND then
		-- the side the weapon is on faces the camera: the left only for off-hand-only items, since anything else
		-- lands in the main hand (see OFF_HAND_ONLY)
		model:SetFacing(offHandOnly(shown) and -QUARTER or QUARTER)
	elseif GetTransmogOffsets then
		local cam = GetTransmogOffsets(slot, shown or 0)
		if cam.scale then model:SetModelScale(cam.scale) end
		if cam.x and cam.y and cam.z then model:SetPosition(cam.x, cam.y, cam.z) end
		if cam.o then model:SetFacing(cam.o) end
	end
end

local function applyCell(cell)
	local model = cell.model
	if not weaponSelection() then
		model:SetCamera(2)
		if Custom_SetDressupFacing then Custom_SetDressupFacing(model, -QUARTER) end
	end
	local outfit, shown = cellOutfit(cell.value)
	dress(model, outfit)
	frameCell(model, shown)
end

-- Sets the cell up for a new appearance; the model dresses once it has loaded.
local function loadCell(cell, entry)
	local model = cell.model
	local weapon = weaponSelection()
	if cell.weapon ~= weapon then
		cell.weapon = weapon
		model:SetModelScale(1)
		model:SetPosition(0, 0, 0)
		model:SetFacing(0)
		model:SetCamera(1)
		model:SetUnit("player")
	end
	cell.value, cell.owned, cell.want = entry.value, entry.owned, true
end

local function cellTooltip(cell)
	local _, hand = selection()
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if not hand and cell.value > T.HIDDEN then
		GameTooltip:SetHyperlink("item:" .. cell.value)
	else
		GameTooltip:AddLine((valueText(cell.value, hand ~= nil)), 1, 1, 1)
	end
	if not cell.owned then GameTooltip:AddLine("Not attuned or acquired on your account, so it won't apply.", 1, 0.3, 0.3, true) end
	GameTooltip:AddLine("Showing on your character. Click to choose it.", 0.6, 0.6, 0.66, true)
	GameTooltip:Show()
	local slot = selection()
	TransmogUI.Hover(hand and { hand = hand, value = cell.value } or { slot = slot, value = cell.value })
end

local function pick(cell)
	local slot, hand = selection()
	if hand then T.SetEnchant(state.look, hand, cell.value) else T.SetSlot(state.look, slot, cell.value) end
	PlaySound("igMainMenuOptionCheckBoxOn")
	TransmogUI.Refresh()
end

local function newCell(parent, w, h)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(w, h)
	S.Panel(cell, C.well, C.border)
	cell.bg = TransmogUI.Background(cell, 1, w - 2, h - 2 - NAME_H)
	-- the model's frame has the shape of the game's window's (its offsets were tuned for it), as wide as the cell
	-- and centered above the name, so each item lands centered as the game frames it
	local areaH = h - 2 - NAME_H
	local modelW = w - 2
	local modelH = math.min(areaH, modelW * STOCK_MODEL_H / STOCK_MODEL_W)
	local model = CreateFrame("DressUpModel", nil, cell)
	model:SetSize(modelW, modelH)
	model:SetPoint("TOP", 0, -1 - (areaH - modelH) / 2)
	model:SetFrameLevel(cell:GetFrameLevel() + 2)
	model:EnableMouse(false)
	model:SetUnit("player")
	-- A model reports its file before it has finished loading, and finishing resets its camera and position, so a
	-- cell is framed again twice after it first dresses.
	model:SetScript("OnUpdate", function(self)
		local now = GetTime()
		if cell.want and modelReady(self) then
			cell.want = nil
			applyCell(cell)
			cell.settle = { now + SETTLE[1], now + SETTLE[2] }
		elseif cell.settle and now >= cell.settle[1] then
			table.remove(cell.settle, 1)
			if #cell.settle == 0 then cell.settle = nil end
			applyCell(cell)
		end
	end)
	model:SetScript("OnShow", function()
		if cell.value then cell.want = true end
	end)
	cell.model = model
	local hover = S.Solid(cell, "HIGHLIGHT", { 1, 1, 1, 0.08 })
	hover:SetPoint("TOPLEFT", 1, -1)
	hover:SetPoint("BOTTOMRIGHT", -1, 1)
	cell.name = S.Text(cell, "small")
	cell.name:SetPoint("BOTTOMLEFT", 4, 2)
	cell.name:SetPoint("BOTTOMRIGHT", -4, 2)
	cell.name:SetHeight(NAME_H - 2)
	cell.name:SetWordWrap(false)
	cell:SetScript("OnClick", pick)
	cell:SetScript("OnEnter", cellTooltip)
	cell:SetScript("OnLeave", function()
		GameTooltip:Hide()
		TransmogUI.Unhover()
	end)
	return cell
end

-- What the cells show depends on the look and options too, so they reload when any of it changes.
local function cellsKey(choicesKey)
	local parts = { choicesKey, state.look, T.Options() }
	for i in ipairs(T.SLOTS) do parts[#parts + 1] = T.Slot(state.look, i) end
	parts[#parts + 1] = T.Enchant(state.look, 1)
	parts[#parts + 1] = T.Enchant(state.look, 2)
	return table.concat(parts, ":")
end

local function renderItems()
	local iv = panel.items
	local slot, hand = selection()
	local def = not hand and T.SLOTS[slot]
	local filters = def and def.filter and T.FILTERS[def.filter]
	iv.filterValue = iv.filterKey == (hand and "h" .. hand or slot) and iv.filterValue or 0
	iv.filterKey = hand and "h" .. hand or slot
	if filters then
		iv.filter:SetOptions(filters)
		for _, o in ipairs(filters) do if o.value == iv.filterValue then iv.filter:SetText(o.text) end end
		iv.filter:Show()
	else
		iv.filter:Hide()
	end
	local searchable = T.HasSearch() and not hand
	if searchable then iv.search:Show() iv.dupes:Show() else iv.search:Hide() iv.dupes:Hide() end
	iv.dupes.check:SetChecked(T.HasOption(T.DUPLICATES))

	local key = table.concat({ iv.filterKey, iv.filterValue, iv.searchText or "", T.Options(), state.look }, ":")
	if key ~= iv.choicesKey then
		iv.choicesKey = key
		iv.choices = hand and T.EnchantChoices(state.look, hand) or T.Choices(state.look, slot, iv.filterValue, iv.searchText or "")
		iv.page = nil
	end
	local choices, current = iv.choices, currentValue()
	local perPage = #iv.cells
	local pages = math.max(1, math.ceil(#choices / perPage))
	if not iv.page then
		iv.page = 1
		for i, entry in ipairs(choices) do
			if entry.value == current then iv.page = math.ceil(i / perPage) end
		end
	end
	iv.page = math.max(1, math.min(pages, iv.page))
	iv.pageText:SetText(("Page %d / %d"):format(iv.page, pages))
	if iv.page > 1 then iv.prev:Enable() else iv.prev:Disable() end
	if iv.page < pages then iv.next:Enable() else iv.next:Disable() end

	local reload = cellsKey(key .. ":" .. iv.page) ~= iv.cellsKey
	iv.cellsKey = cellsKey(key .. ":" .. iv.page)
	if reload and Custom_ClearDressupFacing then Custom_ClearDressupFacing() end
	for i, cell in ipairs(iv.cells) do
		local entry = choices[(iv.page - 1) * perPage + i]
		if entry then
			if reload or cell.value ~= entry.value then loadCell(cell, entry) end
			local text, color = valueText(entry.value, hand ~= nil)
			cell.name:SetText(text)
			cell.name:SetTextColor(unpack(entry.owned and color or C.bad))
			cell:SetBackdropBorderColor(unpack(entry.value == current and C.accent or C.border))
			for _, tex in ipairs(cell.bg) do if T.HasOption(T.BACKGROUND) then tex:Show() else tex:Hide() end end
			cell:Show()
		else
			cell.value = nil
			cell:Hide()
		end
	end
	iv.empty:SetText(#choices == 0 and "Nothing to Pick for This Slot" or "")
	iv.count = math.max(0, #choices - 2)
end

-- Sets -------------------------------------------------------------------------------------------------------

-- A set and its recolors are one row; a set with recolors opens to list each version under it. The row shows its
-- best version's pieces, and hovering it previews that version.

local function setMatches(set, q)
	local named = q == ""
	for _, version in ipairs(set.versions) do
		named = named or version.name:lower():find(q, 1, true) ~= nil
	end
	return (state.setClass == "all" or T.SetForClass(set))
		and ((state.setArmor or 0) == 0 or set.armor == state.setArmor or set.armor == 0)
		and named
end

local function levelRange(set)
	local low, high = set.level, set.level
	for _, version in ipairs(set.versions) do
		low, high = math.min(low, version.level), math.max(high, version.level)
	end
	return low, high
end

local SET_SORT = {
	name = function(row) return row.set.name:upper() end,
	level = function(row) return select(2, levelRange(row.set)) end,
	pieces = function(row) return row.usable * 100 + row.total end,
}

local function versionRow(version)
	local usable, total = T.SetCount(version)
	return { set = version, shows = version, usable = usable, total = total }
end

local function renderSets()
	local sv = panel.sets
	sv.class:SetText(state.setClass == "all" and "All Classes" or "Your Class")
	sv.armor:SetText(state.setArmor == 0 and "Any Armor" or T.ARMOR_TYPES[state.setArmor])
	local q = (state.setSearch or ""):lower()
	local groups = {}
	T.Batch(function()
		for _, set in ipairs(T.Sets()) do
			if setMatches(set, q) then
				local best = T.BestVersion(set)
				local row = versionRow(best)
				row.set, row.shows, row.child = set, best, false
				row.recolored = #set.versions > 1
				groups[#groups + 1] = row
			end
		end
	end)
	local get = SET_SORT[state.setSort] or SET_SORT.name
	table.sort(groups, function(a, b)
		local va, vb = get(a), get(b)
		if va == vb then return a.set.name:upper() < b.set.name:upper() end
		if state.setDesc then return va > vb end
		return va < vb
	end)
	local rows = {}
	T.Batch(function()
		for _, group in ipairs(groups) do
			rows[#rows + 1] = group
			group.open = group.recolored and (state.setOpen[group.set.name] or q ~= "")
			if group.open then
				for _, version in ipairs(group.set.versions) do
					local row = versionRow(version)
					row.child = true
					rows[#rows + 1] = row
				end
			end
		end
	end)
	sv.table:SetItems(rows, "No Sets Match", sv.keepScroll)
	sv.keepScroll = nil
	sv.count = #groups
end

local function setCell(row, key)
	local text, color
	if key == "name" and row.child then
		text, color = "      " .. row.set.name, row.usable > 0 and C.text or C.muted
	elseif key == "name" then
		text = row.set.name
		if row.recolored then
			text = S.Hex(C.muted, row.open and "-  " or "+  ") .. text .. "  " .. S.Hex(C.muted, #row.set.versions .. " Versions")
		end
		color = row.usable > 0 and C.text or C.muted
	elseif key == "level" and row.child then
		text, color = tostring(row.set.level), C.muted
	elseif key == "level" then
		local low, high = levelRange(row.set)
		text, color = low == high and tostring(low) or (low .. "-" .. high), C.muted
	else
		text = ("%d / %d"):format(row.usable, row.total)
		color = row.usable == row.total and C.good or row.usable > 0 and C.text or C.muted
	end
	return text, color
end

local function setPreview(version)
	local pieces = {}
	for _, piece in ipairs(T.SetPieces(version)) do pieces[piece.slot] = piece.id end
	return { set = pieces }
end

-- Each slot's piece, and the item with the same look that goes in when it's not the set's own.
local function pieceLines(tt, version)
	for _, piece in ipairs(T.SetPieces(version)) do
		local name = itemName(piece.piece)
		if piece.usable then
			tt:AddDoubleLine(T.SLOTS[piece.slot].label, name, 0.6, 0.6, 0.66, 1, 1, 1)
			if piece.id ~= piece.piece and itemName(piece.id) ~= name then
				tt:AddDoubleLine(" ", "Same look: " .. itemName(piece.id), 1, 1, 1, 0.6, 0.6, 0.66)
			end
		else
			tt:AddDoubleLine(T.SLOTS[piece.slot].label, name, 0.6, 0.6, 0.66, 1, 0.3, 0.3)
		end
	end
end

local function setTooltip(tt, row)
	tt:AddLine(row.set.name, 1, 1, 1)
	if row.recolored and not row.child then
		for _, version in ipairs(row.set.versions) do
			local usable, total = T.SetCount(version)
			local done = usable == total
			tt:AddDoubleLine(version.name .. " (" .. version.level .. ")", ("%d / %d"):format(usable, total),
				1, 1, 1, done and 0.3 or 1, 1, done and 0.3 or 1)
		end
		tt:AddLine("Showing " .. row.shows.name .. ", the version you have the most of. Click to "
			.. (row.open and "close" or "see each version") .. ".", 0.6, 0.6, 0.66, true)
	else
		pieceLines(tt, row.shows)
		if row.usable < row.total then
			tt:AddLine("Red pieces aren't attuned or acquired on your account, so they're left out.", 1, 0.3, 0.3, true)
		end
		tt:AddLine("Showing on your character. Click to choose which of its pieces to put on.", 0.6, 0.6, 0.66, true)
	end
	TransmogUI.Hover(setPreview(row.shows))
end

-- Shows a status line for a few seconds, over the usual one.
local function flash(text)
	panel.message = { text = text, untilTime = GetTime() + 4 }
	panel.pending = GetTime() + 4.1
end

-- Choosing a set (or a version of one) shows its pieces beside the list, the usable ones checked; nothing goes on
-- the look until Put On Selected. Changes save at once, so a stray click on a row can't overwrite slots.
local function choose(version)
	local checked = {}
	for _, piece in ipairs(T.SetPieces(version)) do
		if piece.usable then checked[piece.slot] = true end
	end
	panel.chosen, panel.checked = version, checked
	PlaySound("igMainMenuOptionCheckBoxOn")
end

-- What the preview wears while a set is chosen on the Sets tab: the look with the checked pieces on.
function TransmogUI.ChosenPreview()
	local override
	if state.tab == "sets" and panel.chosen then
		local pieces = {}
		for _, piece in ipairs(T.SetPieces(panel.chosen)) do
			if panel.checked[piece.slot] then pieces[piece.slot] = piece.id end
		end
		override = { set = pieces }
	end
	return override
end

local function putOn()
	local version = panel.chosen
	local applied, total, missing = 0, 0, 0
	for _, piece in ipairs(T.SetPieces(version)) do
		total = total + 1
		if piece.usable and panel.checked[piece.slot] then
			T.SetSlot(state.look, piece.slot, piece.id)
			applied = applied + 1
		elseif not piece.usable then
			missing = missing + 1
		end
	end
	PlaySound("igMainMenuOptionCheckBoxOn")
	local text = ("Put On %d of %d Pieces"):format(applied, total)
	if missing > 0 then text = text .. ": " .. S.Count(missing, "Piece") .. " Not Attuned or Acquired" end
	flash(applied > 0 and S.Hex(C.good, text) or S.Hex(C.bad, text))
	TransmogUI.Refresh()
end

-- The chosen set's pieces, one row per slot.
local function renderDetail()
	local dv = panel.sets.detail
	local version = panel.chosen
	if version then dv.none:Hide() dv.content:Show() else dv.none:Show() dv.content:Hide() end
	if version then
		dv.title:SetText(version.name)
		local usable, total = T.SetCount(version)
		local checkedCount = 0
		local pieces = T.SetPieces(version)
		for i, row in ipairs(dv.rows) do
			local piece = pieces[i]
			if piece then
				local name, quality = itemName(piece.piece)
				row.piece = piece
				row.icon:SetTexture(select(10, GetItemInfoCustom(piece.id)))
				row.slotText:SetText(T.SLOTS[piece.slot].label)
				row.name:SetText(name)
				row.name:SetTextColor(unpack(piece.usable and S.QualityColor(quality) or C.bad))
				row.check:SetChecked(panel.checked[piece.slot] == true)
				row.check:SetEnabled(piece.usable)
				if panel.checked[piece.slot] then checkedCount = checkedCount + 1 end
				row:Show()
			else
				row.piece = nil
				row:Hide()
			end
		end
		dv.sub:SetText(S.Hex(C.muted, ("Level %d   |   %d / %d Pieces You Can Use"):format(version.level, usable, total)))
		dv.putOn:SetLabel(("Put On %d Selected"):format(checkedCount))
		if checkedCount > 0 then dv.putOn:Enable() else dv.putOn:Disable() end
	end
end

-- Refresh ----------------------------------------------------------------------------------------------------

-- The look picker lists all ten, with the active one marked.
local function lookText(look)
	return T.Name(look) .. (T.Active() == look and "  " .. S.Hex(C.good, "Active") or "")
end

local function renderTop()
	local look = state.look
	local options = {}
	for i = 1, T.MAX do options[i] = { value = i, text = lookText(i) } end
	panel.looks:SetOptions(options)
	panel.looks:SetText(lookText(look))
	panel.lookOptions = options
	if not panel.name.focused then panel.name:SetText(T.Name(look)) end
	for spec, box in ipairs(panel.specs) do box:SetChecked(T.HasSpec(look, spec)) end
	panel.activate:SetLabel(T.Active() == look and "Deactivate" or "Activate")
end

local function renderStatus(items)
	local look = state.look
	local active = T.Active() == look
	local bad = #T.Unusable(look)
	local message = panel.message and GetTime() < panel.message.untilTime and panel.message.text
	local count = items and S.Count(panel.items.count or 0, state.hand and "Enchant Visual" or "Appearance")
		or S.Count(panel.sets.count or 0, "Set")
	panel.status:SetText(message or bad > 0 and S.Hex(C.bad, S.Count(bad, "Slot") .. " Won't Apply: Not Attuned or Acquired")
		or (active and S.Hex(C.good, "Active Look") or S.Hex(C.muted, T.Active() == 0 and "No Look Active" or "Not Active"))
		.. S.Hex(C.muted, "   |   " .. count))
end

function TransmogUI.Refresh()
	panel.pending = nil
	local items = state.tab ~= "sets"
	panel.itemsTab:SetKind(items and "selected" or "secondary")
	panel.setsTab:SetKind(items and "secondary" or "selected")
	panel.title:SetText(items and selectionLabel() or "Item Sets")
	if items then panel.items:Show() panel.sets:Hide() else panel.items:Hide() panel.sets:Show() end
	panel.pick:SetText("")
	if T.HasData() then
		renderTop()
		for _, b in ipairs(panel.slotButtons) do paintSlot(b) end
		if items then
			local text, color = valueText(currentValue(), state.hand ~= nil)
			panel.pick:SetText(text)
			panel.pick:SetTextColor(unpack(color))
		end
		if items then
			renderItems()
		else
			renderSets()
			renderDetail()
		end
		renderStatus(items)
		TransmogUI.Preview(panel.hover or TransmogUI.ChosenPreview())
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
	row.w = S.CHECK_H + 6 + row.label:GetStringWidth() + 4
	row:SetWidth(row.w)
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
		panel.sets.keepScroll = true
		TransmogUI.Refresh()
	end
end

local function createTop(width)
	local label = S.Text(panel, "small", C.muted)
	label:SetPoint("TOPLEFT", PAD, -PAD - 5)
	label:SetText("Look")
	-- the look picker and its name fill the width of the character panel under them
	local room = DOLL_W - LOOK_LABEL_W - GAP
	local looksW = math.floor(room * 0.55)
	panel.looks = S.Dropdown(panel, looksW, function(look)
		state.look = look
		TransmogUI.Refresh()
	end)
	panel.looks:SetPoint("TOPLEFT", PAD + LOOK_LABEL_W, -PAD)
	panel.name = S.Input(panel, "SynastriaCompanionTransmogName", room - looksW, "Look Name", T.NAME_MAX)
	panel.name:SetPoint("LEFT", panel.looks, "RIGHT", GAP, 0)
	panel.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	panel.name:HookScript("OnEditFocusLost", function(self)
		if state then self:SetText(T.Rename(state.look, self:GetText())) end
		TransmogUI.Refresh()
	end)
	panel.activate = S.Button(panel, "Activate", "primary", 96, function()
		T.Activate(T.Active() == state.look and 0 or state.look)
		TransmogUI.Refresh()
	end, "Wear this look, or turn transmog off while it's the active one.")
	panel.activate:SetPoint("TOPRIGHT", -PAD, -PAD)
end

local function createDoll(top, height)
	local doll = CreateFrame("Frame", nil, panel)
	doll:SetPoint("TOPLEFT", PAD, -top)
	doll:SetSize(DOLL_W, height)
	S.Well(doll)
	local wi = 1 + S.metrics.wellInset
	local edge = wi + 6
	local weaponY = height - wi - STRIP_H - GAP - ENCHANT_SIZE - SLOT_GAP - SLOT_SIZE
	local areaX = edge + SLOT_SIZE + GAP
	local area = createCharacter(doll, areaX, wi, DOLL_W - 2 * areaX, weaponY - GAP - wi, DOLL_W - 2 * wi)
	panel.preview = area
	panel.slotButtons = {}
	local function add(b) panel.slotButtons[#panel.slotButtons + 1] = b return b end
	for i, slot in ipairs(LEFT_SLOTS) do
		local b = add(newSlotButton(doll, slot, nil, SLOT_SIZE, "ANCHOR_LEFT"))
		b:SetPoint("TOPLEFT", edge, -edge - (i - 1) * (SLOT_SIZE + SLOT_GAP))
	end
	for i, slot in ipairs(RIGHT_SLOTS) do
		local b = add(newSlotButton(doll, slot, nil, SLOT_SIZE, "ANCHOR_RIGHT"))
		b:SetPoint("TOPRIGHT", -edge, -edge - (i - 1) * (SLOT_SIZE + SLOT_GAP))
	end
	local rowW = #WEAPON_SLOTS * SLOT_SIZE + (#WEAPON_SLOTS - 1) * (SLOT_GAP * 3)
	for i, slot in ipairs(WEAPON_SLOTS) do
		local b = add(newSlotButton(doll, slot, nil, SLOT_SIZE, "ANCHOR_LEFT"))
		b:SetPoint("TOPLEFT", (DOLL_W - rowW) / 2 + (i - 1) * (SLOT_SIZE + SLOT_GAP * 3), -weaponY)
		local hand = T.SLOTS[slot].enchant
		if hand then
			local e = add(newSlotButton(doll, slot, hand, ENCHANT_SIZE, "ANCHOR_LEFT"))
			e:SetPoint("TOP", b, "BOTTOM", 0, -SLOT_GAP)
		end
	end
	for _, b in ipairs(panel.slotButtons) do b:SetFrameLevel(doll:GetFrameLevel() + 6) end

	-- the specs that switch the look on, in the open space above the character, between the slot columns
	local specs = CreateFrame("Frame", nil, doll)
	specs:SetFrameLevel(doll:GetFrameLevel() + 6)
	local specLabel = S.Text(specs, "small", C.muted)
	specLabel:SetPoint("TOP", 0, -4)
	specLabel:SetText("Auto Activate on Spec")
	panel.specs = {}
	local checks, specsW = {}, 0
	for spec = 1, T.SPECS do
		local row = labeledCheck(specs, tostring(spec), ("Activate this look when you switch to spec %d."):format(spec),
			function(on)
				T.SetSpec(state.look, spec, on)
				TransmogUI.Refresh()
			end)
		checks[spec] = row
		specsW = specsW + row.w + (spec > 1 and 6 or 0)
		panel.specs[spec] = row.check
	end
	panel.specBar, panel.specRows = specs, checks
	local x = -specsW / 2
	for _, row in ipairs(checks) do
		row:SetPoint("TOPLEFT", specs, "TOP", x, -18)
		x = x + row.w + 6
	end
	specs:SetSize(math.max(specsW, 140) + 2 * GAP, 18 + CONTROL_H + 4)
	specs:SetPoint("TOP", doll, "TOP", 0, -edge)
	S.Solid(specs, "BACKGROUND", { 0, 0, 0, 0.45 }):SetAllPoints()

	local strip = CreateFrame("Frame", nil, doll)
	strip:SetPoint("BOTTOMLEFT", wi, wi)
	strip:SetPoint("BOTTOMRIGHT", -wi, wi)
	strip:SetHeight(STRIP_H)
	area.naked = labeledCheck(strip, "Naked", "Show only what you're trying, with nothing else on.", option(T.NAKED))
	area.background = labeledCheck(strip, "Show Background", "Show your race's background behind your character.",
		option(T.BACKGROUND))
	area.naked:SetPoint("LEFT", strip, "LEFT", GAP, 0)
	area.background:SetPoint("LEFT", area.naked, "RIGHT", PAD, 0)
	local hint = S.Text(strip, "small", C.muted)
	hint:SetPoint("RIGHT", strip, "RIGHT", -GAP, 0)
	hint:SetText("Drag to Rotate")
	return doll
end

local function createItems(width, height)
	local iv = CreateFrame("Frame", nil, panel)
	iv:SetSize(width, height)
	iv.filter = S.Dropdown(iv, 130, function(value)
		iv.filterValue = value or 0
		TransmogUI.Refresh()
	end)
	iv.filter:SetPoint("TOPLEFT", 0, 0)

	-- one row: the type filter, the search filling what's left, Show Duplicates, and the page arrows
	iv.next = S.Button(iv, ">", "secondary", 28, function()
		iv.page = (iv.page or 1) + 1
		TransmogUI.Refresh()
	end, "Next page.")
	iv.next:SetPoint("TOPRIGHT", 0, 0)
	iv.pageText = S.Text(iv, "small", C.muted)
	iv.pageText:SetWidth(PAGE_TEXT_W)
	iv.pageText:SetJustifyH("CENTER")
	iv.pageText:SetPoint("RIGHT", iv.next, "LEFT", -GAP, 0)
	iv.prev = S.Button(iv, "<", "secondary", 28, function()
		iv.page = (iv.page or 1) - 1
		TransmogUI.Refresh()
	end, "Previous page.")
	iv.prev:SetPoint("RIGHT", iv.pageText, "LEFT", -GAP, 0)
	iv.dupes = labeledCheck(iv, "Show Duplicates", "Also list items that look the same as one already listed. A search always shows them.",
		option(T.DUPLICATES))
	iv.dupes:SetPoint("RIGHT", iv.prev, "LEFT", -PAD, 0)
	iv.search = S.Input(iv, "SynastriaCompanionTransmogSearch", 200, "Search Appearances", 63)
	iv.search:SetPoint("LEFT", iv.filter, "RIGHT", GAP, 0)
	iv.search:SetPoint("RIGHT", iv.dupes, "LEFT", -PAD, 0)
	iv.search:HookScript("OnTextChanged", function(self, user)
		if user then
			iv.searchText = self:GetText()
			panel.pending = GetTime() + SEARCH_DELAY
		end
	end)
	iv.search:SetScript("OnEnterPressed", iv.search.ClearFocus)

	local gridTop = CONTROL_H + GAP
	local gridH = height - gridTop
	local cols = math.max(MIN_COLS, math.floor((width + GAP) / (CELL_W + GAP)))
	local rows = math.max(MIN_ROWS, math.floor((gridH + GAP) / (CELL_H + GAP)))
	local cellW = (width - (cols - 1) * GAP) / cols
	local cellH = (gridH - (rows - 1) * GAP) / rows
	iv.cells, iv.cols, iv.rows = {}, cols, rows
	for r = 1, rows do
		for c = 1, cols do
			local cell = newCell(iv, cellW, cellH)
			cell:SetPoint("TOPLEFT", (c - 1) * (cellW + GAP), -gridTop - (r - 1) * (cellH + GAP))
			iv.cells[#iv.cells + 1] = cell
		end
	end
	iv.empty = S.Text(iv, "normal", C.muted)
	iv.empty:SetPoint("TOP", 0, -gridTop - 60)
	iv:EnableMouseWheel(true)
	iv:SetScript("OnMouseWheel", function(_, delta)
		iv.page = (iv.page or 1) - delta
		TransmogUI.Refresh()
	end)
	return iv
end

-- The chosen set's pieces: a check, icon, slot and name for each, and Put On Selected at the bottom.
local DETAIL_ROW_H = 28
local function createDetail(sv, x, width, height)
	local dv = CreateFrame("Frame", nil, sv)
	dv:SetPoint("TOPLEFT", x, 0)
	dv:SetSize(width, height)
	S.Well(dv)
	dv.none = S.Text(dv, "small", C.muted)
	dv.none:SetPoint("CENTER")
	dv.none:SetText("Choose a set to pick its pieces.")
	dv.content = CreateFrame("Frame", nil, dv)
	dv.content:SetAllPoints(dv)
	dv.title = S.Text(dv.content, "normal", C.heading)
	dv.title:SetPoint("TOPLEFT", PAD, -PAD)
	dv.title:SetPoint("RIGHT", -PAD, 0)
	dv.title:SetJustifyH("LEFT")
	dv.title:SetWordWrap(false)
	dv.sub = S.Text(dv.content, "small")
	dv.sub:SetPoint("TOPLEFT", dv.title, "BOTTOMLEFT", 0, -4)
	dv.rows = {}
	for i = 1, #T.SLOTS do
		local row = CreateFrame("Button", nil, dv.content)
		row:SetSize(width - 2 * PAD, DETAIL_ROW_H)
		row:SetPoint("TOPLEFT", PAD, -PAD - 40 - (i - 1) * DETAIL_ROW_H)
		S.Highlight(row)
		row.check = S.Check(row, nil, function() row:Click() end)
		row.check:SetPoint("LEFT", 0, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(DETAIL_ROW_H - 6, DETAIL_ROW_H - 6)
		row.icon:SetPoint("LEFT", row.check, "RIGHT", GAP, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.slotText = S.Text(row, "small", C.muted)
		row.slotText:SetPoint("LEFT", row.icon, "RIGHT", GAP, 0)
		row.slotText:SetWidth(66)
		row.slotText:SetJustifyH("LEFT")
		row.name = S.Text(row, "small")
		row.name:SetPoint("LEFT", row.slotText, "RIGHT", 4, 0)
		row.name:SetPoint("RIGHT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			local piece = self.piece
			if piece and piece.usable then
				panel.checked[piece.slot] = not panel.checked[piece.slot] or nil
				PlaySound(panel.checked[piece.slot] and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
				TransmogUI.Refresh()
			end
		end)
		row:SetScript("OnEnter", function(self)
			local piece = self.piece
			if piece then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("item:" .. piece.id)
				if piece.id ~= piece.piece and itemName(piece.id) ~= itemName(piece.piece) then
					GameTooltip:AddLine("Same look as " .. itemName(piece.piece) .. ", from the set.", 0.6, 0.6, 0.66, true)
				end
				if not piece.usable then
					GameTooltip:AddLine("Not attuned or acquired on your account, so it can't go on.", 1, 0.3, 0.3, true)
				end
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		dv.rows[i] = row
	end
	dv.putOn = S.Button(dv.content, "Put On Selected", "primary", width - 2 * PAD, function() putOn() end,
		"Put the checked pieces on this look. The slots the set doesn't cover keep what they have.")
	dv.putOn:SetPoint("BOTTOMLEFT", PAD, PAD)
	dv.content:Hide()
	return dv
end

local SET_DETAIL_W = 280

local function createSets(width, height)
	local sv = CreateFrame("Frame", nil, panel)
	sv:SetSize(width, height)
	local listW = width - SET_DETAIL_W - GAP
	sv.detail = createDetail(sv, listW + GAP, SET_DETAIL_W, height)
	sv.class = S.Dropdown(sv, 110, function(value)
		state.setClass = value
		TransmogUI.Refresh()
	end)
	sv.class:SetOptions({ { value = "mine", text = "Your Class" }, { value = "all", text = "All Classes" } })
	sv.class:SetPoint("TOPLEFT", 0, 0)
	sv.armor = S.Dropdown(sv, 100, function(value)
		state.setArmor = value
		TransmogUI.Refresh()
	end)
	local armors = { { value = 0, text = "Any Armor" } }
	for id = 1, 4 do armors[#armors + 1] = { value = id, text = T.ARMOR_TYPES[id] } end
	sv.armor:SetOptions(armors)
	sv.armor:SetPoint("LEFT", sv.class, "RIGHT", GAP, 0)
	sv.search = S.Input(sv, "SynastriaCompanionTransmogSetSearch", listW - 210 - 2 * GAP, "Search Sets", 40)
	sv.search:SetPoint("LEFT", sv.armor, "RIGHT", GAP, 0)
	sv.search:SetPoint("RIGHT", sv, "TOPLEFT", listW, -CONTROL_H / 2)
	sv.search:HookScript("OnTextChanged", function(self, user)
		if user then
			state.setSearch = self:GetText()
			panel.pending = GetTime() + SEARCH_DELAY
		end
	end)
	sv.search:SetScript("OnEnterPressed", sv.search.ClearFocus)

	local top = CONTROL_H + GAP
	sv.table = SC.Table.New(sv, "SynastriaCompanionTransmogSets", listW, height - top, {
		columns = {
			{ key = "name", label = "Set", width = 160, stretch = true },
			{ key = "level", label = "Level", width = 56, defaultDesc = true,
				tooltip = "The highest item level among the set's pieces." },
			{ key = "pieces", label = "Pieces", width = 62, defaultDesc = true,
				tooltip = "Pieces you can use, out of the slots the set covers." },
		},
		rowH = ROW_H,
		cell = setCell,
		tooltip = setTooltip,
		-- a set with versions opens (choosing its best one); a version, or a set without any, is chosen
		isSelected = function(row)
			local chosen = panel.chosen
			return chosen ~= nil and (row.set == chosen or (not row.child and not row.open and chosen.base == row.set))
		end,
		onClick = function(row)
			if row.recolored and not row.child then
				state.setOpen[row.set.name] = not row.open or nil
				sv.keepScroll = true
			end
			choose(row.shows)
			TransmogUI.Refresh()
		end,
		onSort = function(key, desc)
			state.setSort, state.setDesc = key, desc
			sv.keepScroll = true
			TransmogUI.Refresh()
		end,
	})
	sv.table.frame:SetPoint("TOPLEFT", 0, -top)
	sv.table:SetSort(state.setSort or "name", state.setDesc)
	for _, row in ipairs(sv.table.rows) do
		row:HookScript("OnLeave", function() TransmogUI.Unhover() end)
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

local function createFooter()
	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	panel.reset = S.Button(panel, "Reset", "danger", 70, function()
		local popup = StaticPopup_Show("SYNASTRIA_COMPANION_TRANSMOG_RESET", T.Name(state.look))
		if popup then popup.data = state.look end
	end, "Put every slot back to your equipped look.")
	panel.reset:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	panel.export = S.Button(panel, "Export", "secondary", 70, function()
		SC.TextDialog.ShowExport("Export Look", "This look's appearances. Copy it with Ctrl+C.", T.Export(state.look) or "")
	end, "Copy this look as text to share it or keep it.")
	panel.export:SetPoint("RIGHT", panel.reset, "LEFT", -GAP, 0)
	panel.import = S.Button(panel, "Import", "secondary", 70, function()
		local look = state.look
		SC.TextDialog.AskImport("Import Look", "Replaces " .. T.Name(look) .. " with the pasted look.", function(text)
			if T.Import(look, text) then flash(S.Hex(C.good, "Imported")) else flash(S.Hex(C.bad, "The Game Couldn't Read That")) end
			TransmogUI.Refresh()
		end)
	end, "Paste a shared look into this one.")
	panel.import:SetPoint("RIGHT", panel.export, "LEFT", -GAP, 0)
	panel.useEquipped = S.Button(panel, "Use Equipped", "secondary", 100, function()
		T.UseEquipped(state.look)
		TransmogUI.Refresh()
	end, "Set every slot to the item you have equipped there.")
	panel.useEquipped:SetPoint("RIGHT", panel.import, "LEFT", -GAP, 0)
end

local function create(parent, width, height)
	SC.db.transmog = SC.db.transmog or {}
	state = SC.db.transmog
	state.look = state.look or (T.HasData() and T.Active() > 0 and T.Active()) or 1
	state.setClass = state.setClass or "mine"
	state.setOpen = state.setOpen or {}
	state.setArmor = state.setArmor or T.BestArmor()
	state.slot = state.slot or 1
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	createTop(width)
	local top = PAD + CONTROL_H + GAP
	local bodyH = height - top - (PAD + CONTROL_H + PAD)
	createDoll(top, bodyH)

	local rightX = PAD + DOLL_W + GAP
	local rightW = width - rightX - PAD
	panel.itemsTab = S.Button(panel, "Items", "selected", TAB_W, function()
		state.tab = "items"
		TransmogUI.Refresh()
	end, "Pick an appearance for the selected slot.")
	-- the tabs, the slot's name and its current pick share the top bar, over the grid
	panel.itemsTab:SetPoint("TOPLEFT", rightX, -PAD)
	panel.setsTab = S.Button(panel, "Sets", "secondary", TAB_W, function()
		state.tab = "sets"
		panel.sets.search:SetText(state.setSearch or "")
		TransmogUI.Refresh()
	end, "Browse item sets and put one on this look.")
	panel.setsTab:SetPoint("LEFT", panel.itemsTab, "RIGHT", -1, 0)
	panel.title = S.Text(panel, "normal", C.heading)
	panel.title:SetPoint("LEFT", panel.setsTab, "RIGHT", PAD, 0)
	-- what the selected slot is set to now, which may not be on the page shown
	panel.pick = S.Text(panel, "small")
	panel.pick:SetPoint("LEFT", panel.title, "RIGHT", GAP, 0)
	panel.pick:SetPoint("RIGHT", panel.activate, "LEFT", -PAD, 0)
	panel.pick:SetJustifyH("LEFT")
	panel.pick:SetWordWrap(false)

	local viewTop, viewH = top, bodyH
	panel.items = createItems(rightW, viewH)
	panel.items:SetPoint("TOPLEFT", rightX, -viewTop)
	panel.sets = createSets(rightW, viewH)
	panel.sets:SetPoint("TOPLEFT", rightX, -viewTop)
	createFooter()

	panel:SetScript("OnUpdate", function()
		if panel.pending and GetTime() >= panel.pending then TransmogUI.Refresh() end
	end)
	panel:SetScript("OnHide", function()
		if Custom_ClearDressupFacing then Custom_ClearDressupFacing() end
		panel.items.cellsKey, panel.hover = nil, nil
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
	size = { WINDOW_W, WINDOW_H },
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
