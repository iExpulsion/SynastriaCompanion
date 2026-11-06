-- Vendored from MaterialCraftUI v1.0.0-7-g1a7bc9b. Change it there, then run tools/sync_style.py.
-- Cognac: gold-framed painted controls on warm brown glass. Load it after Style.lua and Atlas.lua;
-- S.UseSkin("cognac") switches to it.
local _, NS = ...
local S = NS.Style
local ATLAS = "cognac"

-- the window border's corner and edge strips, and the sidebar card's corners
local CORNER, EDGE, CARD_CORNER = 36, 18, 26
-- how much of the card and search art is corner or cap, as fractions of the piece
local CARD_CUT_U, CARD_CUT_V = 34 / 225, 34 / 149
local SEARCH_CAP = 70 / 158

local TEXT = { primary = "accent", secondary = "text", selected = "accent", danger = "bad", ghost = "text" }

-- Runs layout(w, h) now and whenever the frame is resized or shown, so art sized in pixels follows it.
local function follow(frame, layout)
	local function run()
		local w, h = frame:GetWidth(), frame:GetHeight()
		if w and h and w > 0 and h > 0 then layout(w, h) end
	end
	frame:HookScript("OnSizeChanged", run)
	frame:HookScript("OnShow", run)
	run()
end

local function art(frame, layer, piece)
	local t = frame:CreateTexture(nil, layer)
	S.Art(t, ATLAS, piece)
	return t
end

-- A plate under the button's label (hidden until painted) and the additive hover glow, both sized to the button.
local function plate(b)
	b.plate = b:CreateTexture(nil, "BORDER")
	b.plate:Hide()
	b.glow = art(b, "HIGHLIGHT", "button_hover")
	b.glow:SetBlendMode("ADD")
	follow(b, function(w, h)
		S.PlaceArt(b.plate, b, ATLAS, b.platePiece or "button_normal", 0, 0, w, h)
		S.PlaceArt(b.glow, b, ATLAS, "button_hover", 0, 0, w, h)
	end)
end

-- A frame sized by its anchors has no size until it's laid out; follow places the plate once it has one.
local function showPlate(b, piece)
	b.platePiece = piece
	S.Art(b.plate, ATLAS, piece)
	local w, h = b:GetWidth(), b:GetHeight()
	if w and h and w > 0 and h > 0 then S.PlaceArt(b.plate, b, ATLAS, piece, 0, 0, w, h) end
	b.plate:Show()
end

-- Wide buttons get the gold plate, with its own pressed and disabled faces; a square one (an X or a +) gets the
-- round bezel so the plate isn't squashed, and the selected side of a segmented button the teal chip. Those two
-- only darken when pressed or disabled, so their shape doesn't change.
local function platePiece(b, enabled)
	local square = (b:GetWidth() or 0) > 0 and b:GetWidth() <= (b:GetHeight() or 0) + 4
	return b.kind == "selected" and "chip_selected" or square and "bezel" or not enabled and "button_disabled"
		or b.down and "button_pressed" or "button_normal"
end

-- The window border: corners and edge strips on the frame itself, under its children, which start inside it.
local function chrome(f)
	local pieces = {}
	for _, key in ipairs({ "corner_nw", "corner_ne", "corner_sw", "corner_se", "border_top", "border_bottom",
		"border_left", "border_right" }) do
		pieces[key] = art(f, "OVERLAY", key)
	end
	follow(f, function(w, h)
		local mw, mh = math.max(w - 2 * CORNER, 1), math.max(h - 2 * CORNER, 1)
		S.PlaceArt(pieces.corner_nw, f, ATLAS, "corner_nw", 0, 0, CORNER, CORNER)
		S.PlaceArt(pieces.corner_ne, f, ATLAS, "corner_ne", w - CORNER, 0, CORNER, CORNER)
		S.PlaceArt(pieces.corner_sw, f, ATLAS, "corner_sw", 0, h - CORNER, CORNER, CORNER)
		S.PlaceArt(pieces.corner_se, f, ATLAS, "corner_se", w - CORNER, h - CORNER, CORNER, CORNER)
		S.PlaceArt(pieces.border_top, f, ATLAS, "border_top", CORNER, 0, mw, EDGE)
		S.PlaceArt(pieces.border_bottom, f, ATLAS, "border_bottom", CORNER, h - EDGE, mw, EDGE)
		S.PlaceArt(pieces.border_left, f, ATLAS, "border_left", 0, CORNER, EDGE, mh)
		S.PlaceArt(pieces.border_right, f, ATLAS, "border_right", w - EDGE, CORNER, EDGE, mh)
	end)
end

-- The framed card: a nine-slice of the card art, so its filigree corners keep their size.
local function card(f)
	local cuts = { { 0, CARD_CUT_U }, { CARD_CUT_U, 1 - CARD_CUT_U }, { 1 - CARD_CUT_U, 1 } }
	local vcuts = { { 0, CARD_CUT_V }, { CARD_CUT_V, 1 - CARD_CUT_V }, { 1 - CARD_CUT_V, 1 } }
	local slices = {}
	for row = 1, 3 do
		for col = 1, 3 do
			local t = f:CreateTexture(nil, "BACKGROUND")
			S.Art(t, ATLAS, "card", cuts[col][1], cuts[col][2], vcuts[row][1], vcuts[row][2])
			slices[#slices + 1] = { t, col, row }
		end
	end
	follow(f, function(w, h)
		local xs = { 0, CARD_CORNER, w - CARD_CORNER }
		local ws = { CARD_CORNER, math.max(w - 2 * CARD_CORNER, 1), CARD_CORNER }
		local ys = { 0, CARD_CORNER, h - CARD_CORNER }
		local hs = { CARD_CORNER, math.max(h - 2 * CARD_CORNER, 1), CARD_CORNER }
		for _, s in ipairs(slices) do
			local t, col, row = s[1], s[2], s[3]
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", f, "TOPLEFT", xs[col], -ys[row])
			t:SetWidth(ws[col])
			t:SetHeight(hs[row])
		end
	end)
end

-- A one-line field: three slices of the search plate, so its corners stay square as it widens. The art has no
-- right cap, so the left one is mirrored.
local function searchField(e)
	local left, middle, right = e:CreateTexture(nil, "BACKGROUND"), e:CreateTexture(nil, "BACKGROUND"),
		e:CreateTexture(nil, "BACKGROUND")
	S.Art(left, ATLAS, "search", 0, SEARCH_CAP)
	S.Art(middle, ATLAS, "search", SEARCH_CAP, 1)
	S.Art(right, ATLAS, "search", SEARCH_CAP, 0)
	e.slices = { left, middle, right }
	follow(e, function(w, h)
		local cap = math.max(14, math.floor(h * 0.7))
		if cap * 2 > w - 8 then cap = math.max(8, math.floor(w / 4)) end
		local spots = { { 0, cap }, { cap, math.max(w - 2 * cap, 1) }, { w - cap, cap } }
		for i, t in ipairs(e.slices) do
			t:ClearAllPoints()
			t:SetPoint("LEFT", e, "LEFT", spots[i][1], 0)
			t:SetWidth(spots[i][2])
			t:SetHeight(h)
		end
	end)
end

S.RegisterSkin("cognac", {
	label = "Cognac",
	credit = "Art by Jeff, from AttuneNext.",
	roles = {
		surfaceLowest = "0e0c0a", surface = "1a1510", surfaceLow = "14110e", surfaceContainer = "241e18",
		surfaceHigh = "2e2820", onSurface = "e6e1d6", onSurfaceVariant = "a9a396", outline = "9a8458",
		outlineVariant = "6e5a38", primary = "f0d090", onPrimary = "2a220c", error = "e07068", errorContainer = "6a2824",
	},
	-- the glass is a blue-black tint over the tooltip background; selected rows and chips are teal, the selected
	-- sidebar entry mint
	colors = function(c)
		c.window = { 0.045, 0.045, 0.06, 0.96 }
		c.sidebar = { 16 / 255, 16 / 255, 24 / 255, 1 }
		c.rowHover = { 0.94, 0.78, 0.45, 0.16 }
		c.rowSelected = { 0.25, 0.82, 0.78, 0.18 }
		c.navSelected = { 0.2, 1, 0.6, 1 }
		c.arrow = c.accent
		c.scrollThumb = c.accent
		c.scrollThumbHover = { 1, 0.95, 0.75, 1 }
	end,
	metrics = { edge = EDGE, inset = EDGE, navInset = 8, wellInset = 6 },
	button = plate,
	paintButton = function(b, enabled)
		local piece = platePiece(b, enabled)
		showPlate(b, piece)
		b.glow:SetAlpha(enabled and 1 or 0)
		local shaped = piece == "bezel" or piece == "chip_selected"
		local shade = shaped and (not enabled and 0.45 or b.down and 0.72) or 1
		b.plate:SetVertexColor(shade, shade, shade)
		b.label:SetTextColor(unpack(S.colors[enabled and TEXT[b.kind] or "disabled"] or S.colors.text))
	end,
	-- windows and popups are the same glass in the gold border; a menu stays a small flat panel
	frame = function(f, role)
		if role == "menu" then
			S.Panel(f, S.colors.panel, S.colors.border)
		else
			f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
			f:SetBackdropColor(unpack(S.colors.window))
			chrome(f)
		end
	end,
	-- the framed card, like the sidebar's
	well = function(f)
		card(f)
	end,
	-- the card behind the entries, and the spear dividing it from the page, which paints over both
	sidebar = function(side)
		card(side)
		local holder = CreateFrame("Frame", nil, side:GetParent())
		holder:SetFrameLevel(side:GetParent():GetFrameLevel() + 20)
		holder:SetPoint("TOPLEFT", side, "TOPRIGHT", -5, 0)
		holder:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", -5, 0)
		holder:SetWidth(10)
		local spear = art(holder, "ARTWORK", "divider_v")
		follow(holder, function(w, h) S.PlaceArt(spear, holder, ATLAS, "divider_v", 0, 0, w, h) end)
	end,
	highlight = function(f)
		plate(f)
	end,
	navEntry = function(b)
		plate(b)
		b.label:SetPoint("LEFT", S.PAD, 0)
	end,
	paintNav = function(b, on)
		if on then showPlate(b, "chip_selected") else b.plate:Hide() end
	end,
	input = function(e, tall)
		e.tall = tall
		if tall then S.Panel(e, S.colors.well, S.colors.border) else searchField(e) end
	end,
	-- a tall box keeps a flat rule that takes the accent while focused; a one-line field brightens its plate
	paintInput = function(e)
		if e.tall then
			e:SetBackdropBorderColor(unpack(e.focused and S.colors.accent or e.hovered and S.colors.outline or S.colors.border))
		else
			local r, g, b = 1, 1, 1
			if e.focused then r, g, b = 1, 0.93, 0.72 elseif e.hovered then r, g, b = 1, 0.97, 0.88 end
			for _, t in ipairs(e.slices) do t:SetVertexColor(r, g, b) end
		end
	end,
})
