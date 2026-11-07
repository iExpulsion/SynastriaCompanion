-- Vendored from MaterialCraftUI v1.0.0-28-ged1c622. Change it there, then run tools/sync_style.py.
-- Cognac: gold-framed painted controls on dark glass. Load it after Style.lua and Atlas.lua;
-- S.UseSkin("cognac") switches to it.
local _, NS = ...
local S = NS.Style
local ATLAS = "cognac"

-- How far a window's content starts in from its edges, inside the border.
local EDGE = 18
-- The border is drawn at one scale, so its corners and edges are the same thickness: CHROME screen pixels per art
-- pixel, with the outside of its bars OUTSIDE pixels in from the frame's edge. Its bars are BAR art pixels thick.
local CHROME, OUTSIDE, BAR = 0.16, 3, 46
-- The border is built from the two top corners, and the bottom half is their mirror image, since the painted bottom
-- corners sit a few pixels differently and their bars never quite met the edges. For each top corner: where its
-- bars' outside edges run in its 256px cell, counted in from the cell's sides; the part of it drawn, short of the
-- caps its bars end in (columns, then rows); and the stretch of its bar the edges are made of, so they meet it
-- seamlessly (columns along the top bar, rows along the side bar, and the rows or columns across each).
local NW = { left = 26, top = 26, crop = { 18, 200, 18, 200 }, along = { 170, 210 }, across = { 18, 80 } }
local NE = { right = 40, top = 25, crop = { 56, 225, 17, 200 }, along = { 170, 225 }, across = { 160, 225 } }
-- The top diamond, from the top edge piece, laid over the middle of the bar: the edge piece's bar rows, the rows to
-- sample, and the diamond's columns.
local HBAR, HBAND, DIAMOND = { 103, 160 }, { 93, 163 }, { 96, 160 }
-- the divider's spear: a tip at each end and a diamond in the middle keep their shape; the shafts between stretch
local SPEAR_W, SPEAR_COLS = 12, { 102, 153 }
local SPEAR = { { 16, 60, false }, { 60, 100, true }, { 100, 156, false }, { 156, 196, true }, { 196, 240, false } }
-- art pixels of corner kept unstretched on button plates and chips, on the card, and the search field's left cap
local PLATE_CUT, CARD_CUT, CARD_CORNER = 18, 34, 26
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

-- A plate under the button's label (hidden until painted) and the additive hover glow: nine-slices scaled to the
-- button's height, so their rims stay even however wide it is.
local function plate(b)
	b.plate = S.NineSlice(b, "BORDER", ATLAS, "button_normal", PLATE_CUT)
	b.plate:Hide()
	b.glow = S.NineSlice(b, "HIGHLIGHT", ATLAS, "button_hover", PLATE_CUT)
	b.glow:SetBlendMode("ADD")
	follow(b, function(w, h)
		b.plate:Layout(w, h)
		b.glow:Layout(w, h)
	end)
end

-- A frame sized by its anchors has no size until it's laid out; follow lays the plate out once it has one.
local function showPlate(b, piece)
	b.platePiece = piece
	b.plate:SetPiece(piece)
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

-- The window border, on the frame itself under its children, which start inside it. The top corners are placed by
-- where their bars run; the top edge and both sides are stretches of those same bars, so they meet the corners
-- seamlessly; and the bottom corners, bottom edge and bottom diamond are the top ones flipped. Corners draw over
-- the ends of the edges.
local function chrome(f)
	local s, o = CHROME, OUTSIDE
	local bar = BAR * s
	local function tex(layer) return f:CreateTexture(nil, layer) end
	local corners = { nw = tex("OVERLAY"), ne = tex("OVERLAY"), sw = tex("OVERLAY"), se = tex("OVERLAY") }
	local runs = { top = tex("BORDER"), bottom = tex("BORDER"), left = tex("BORDER"), right = tex("BORDER") }
	local diamonds = { top = tex("ARTWORK"), bottom = tex("ARTWORK") }
	local kh = bar / (HBAR[2] - HBAR[1])
	local diamondW, diamondH = (DIAMOND[2] - DIAMOND[1]) * kh, (HBAND[2] - HBAND[1]) * kh
	follow(f, function(w, h)
		-- whole screen pixels, so pieces that should meet don't land a fraction of a pixel apart
		local function snap(v) return S.Snap(f, v) end
		local k = snap(256 * s) / 256
		-- part of a piece (its pixels x0..x1, y0..y1) at x, y by ww, hh, and the same mirrored into the bottom half:
		-- anchored to the frame's bottom edge by the same offset, since its height isn't always whole screen pixels
		local function draw(t, mirror, piece, x0, x1, y0, y1, x, y, ww, hh)
			S.ArtPart(t, f, ATLAS, piece, x0, x1, y0, y1, x, y, ww, hh)
			if mirror then
				local pw, ph = S.ArtSize(ATLAS, piece)
				S.Art(mirror, ATLAS, piece, x0 / pw, x1 / pw, y1 / ph, y0 / ph)
				mirror:ClearAllPoints()
				mirror:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
				mirror:SetWidth(math.max(ww, 1))
				mirror:SetHeight(math.max(hh, 1))
			end
		end
		local nw = { snap(o - NW.left * k), snap(o - NW.top * k) }
		local ne = { snap(w - o - (256 - NE.right) * k), snap(o - NE.top * k) }
		local c = NW.crop
		draw(corners.nw, corners.sw, "corner_nw", c[1], c[2], c[3], c[4], nw[1] + c[1] * k, nw[2] + c[3] * k,
			(c[2] - c[1]) * k, (c[4] - c[3]) * k)
		c = NE.crop
		draw(corners.ne, corners.se, "corner_ne", c[1], c[2], c[3], c[4], ne[1] + c[1] * k, ne[2] + c[3] * k,
			(c[2] - c[1]) * k, (c[4] - c[3]) * k)
		-- the top edge: the top-left corner's bar from where its slice sits to inside the top-right corner
		local x0 = nw[1] + NW.along[1] * k
		draw(runs.top, runs.bottom, "corner_nw", NW.along[1], NW.along[2], NW.across[1], NW.across[2], x0,
			nw[2] + NW.across[1] * k, ne[1] + 60 * k - x0, (NW.across[2] - NW.across[1]) * k)
		-- the sides: each top corner's side bar, rows along and columns across, down to its mirror at the bottom
		local ly = nw[2] + NW.along[1] * k
		draw(runs.left, nil, "corner_nw", NW.across[1], NW.across[2], NW.along[1], NW.along[2],
			nw[1] + NW.across[1] * k, ly, (NW.across[2] - NW.across[1]) * k, h - 2 * ly)
		local ry = ne[2] + NE.along[1] * k
		draw(runs.right, nil, "corner_ne", NE.across[1], NE.across[2], NE.along[1], NE.along[2],
			ne[1] + NE.across[1] * k, ry, (NE.across[2] - NE.across[1]) * k, h - 2 * ry)
		-- the diamond on the middle of the top bar, and its mirror on the bottom
		draw(diamonds.top, diamonds.bottom, "border_top", DIAMOND[1], DIAMOND[2], HBAND[1], HBAND[2],
			snap((w - diamondW) / 2), snap(o - (HBAR[1] - HBAND[1]) * kh), diamondW, diamondH)
	end)
end

-- The framed card: a nine-slice of the card art, so its filigree corners keep their size.
local function card(f)
	local slices = S.NineSlice(f, "BACKGROUND", ATLAS, "card", CARD_CUT, CARD_CORNER / CARD_CUT)
	follow(f, function(w, h) slices:Layout(w, h) end)
end

-- The spear dividing a sidebar from the page: its tips and diamond keep their shape, its shafts stretch.
local function spear(holder)
	local parts = {}
	for i = 1, #SPEAR do parts[i] = holder:CreateTexture(nil, "ARTWORK") end
	follow(holder, function(w, h)
		local k = w / (SPEAR_COLS[2] - SPEAR_COLS[1])
		local fixed, stretch = 0, 0
		for _, seg in ipairs(SPEAR) do
			if seg[3] then stretch = stretch + 1 else fixed = fixed + (seg[2] - seg[1]) * k end
		end
		local y = 0
		for i, seg in ipairs(SPEAR) do
			local len = seg[3] and math.max((h - fixed) / stretch, 1) or (seg[2] - seg[1]) * k
			S.ArtPart(parts[i], holder, ATLAS, "divider_v", SPEAR_COLS[1], SPEAR_COLS[2], seg[1], seg[2], 0, y, w, len)
			y = y + len
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
	-- the glass is a blue-black tint; selected rows and chips are teal, the selected sidebar entry mint
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
	-- a window is see-through glass, the blue-black tint over the tooltip background, in the gold border; a popup,
	-- which sits over a window, is the same tint but solid, so the window's contents don't show through it; a menu
	-- stays a small flat panel
	-- the fill starts halfway into the border's bars, so nothing of it shows outside the gold
	frame = function(f, role)
		local inset = math.floor(OUTSIDE + BAR * CHROME / 2 + 0.5)
		local insets = { left = inset, right = inset, top = inset, bottom = inset }
		if role == "window" then
			f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
				insets = insets })
			f:SetBackdropColor(unpack(S.colors.window))
			chrome(f)
		elseif role == "popup" then
			local c = S.colors.window
			f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", insets = insets })
			f:SetBackdropColor(c[1], c[2], c[3], 0.98)
			chrome(f)
		else
			S.Panel(f, S.colors.panel, S.colors.border)
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
		holder:SetPoint("TOPLEFT", side, "TOPRIGHT", -SPEAR_W / 2, 0)
		holder:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", -SPEAR_W / 2, 0)
		holder:SetHeight(side:GetHeight() or 1)
		holder:SetWidth(SPEAR_W)
		spear(holder)
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
