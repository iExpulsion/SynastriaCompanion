-- Vendored from MaterialCraftUI v1.0.0-12-gebc7df5. Change it there, then run tools/sync_style.py.
-- Cognac: gold-framed painted controls on dark panels. Load it after Style.lua and Atlas.lua;
-- S.UseSkin("cognac") switches to it.
local _, NS = ...
local S = NS.Style
local ATLAS = "cognac"

-- How far a window's content starts in from its edges, inside the border.
local EDGE = 18
-- The border is drawn at one scale, so its corners and edges are the same thickness: CHROME screen pixels per art
-- pixel, with the outside of its bars OUTSIDE pixels in from the frame's edge. Its bars are BAR art pixels thick.
local CHROME, OUTSIDE, BAR = 0.16, 3, 46
-- Where each corner's bars run in its 256px cell: the outside edge of the bar along each side it touches, counted
-- in from that side of the cell. The four corners differ by a few pixels, so each is placed by its own.
local CORNERS = {
	corner_nw = { left = 26, top = 26 },
	corner_ne = { right = 40, top = 25 },
	corner_sw = { left = 41, bottom = 25 },
	corner_se = { right = 28, bottom = 25 },
}
-- The straight border pieces: the bar's rows (top and bottom) or columns (sides) in the cell, the part to sample
-- across it, and, on the top and bottom, the diamond in the middle that keeps its shape.
local HBAR, HBAND, DIAMOND = { 103, 160 }, { 93, 163 }, { 96, 160 }
local VBAR, VBAND = { 109, 146 }, { 106, 150 }
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

local function art(frame, layer, piece)
	local t = frame:CreateTexture(nil, layer)
	S.Art(t, ATLAS, piece)
	return t
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

-- The window border, on the frame itself under its children, which start inside it. Each corner is placed by
-- where its own bars run, and the straight edges between them are scaled across so their bars match the corners'
-- thickness, stretched only along their length, with the top and bottom diamonds kept whole. Corners draw over
-- the ends of the edges.
local function chrome(f)
	local s, o = CHROME, OUTSIDE
	local cell, bar = 256 * s, BAR * s
	local corners = {}
	for key in pairs(CORNERS) do corners[key] = art(f, "OVERLAY", key) end
	local function strips(n)
		local list = {}
		for i = 1, n do list[i] = f:CreateTexture(nil, "ARTWORK") end
		return list
	end
	local top, bottom, sides = strips(3), strips(3), strips(2)
	local kh, kv = bar / (HBAR[2] - HBAR[1]), bar / (VBAR[2] - VBAR[1])
	local bandH, bandW, diamondW = (HBAND[2] - HBAND[1]) * kh, (VBAND[2] - VBAND[1]) * kv, (DIAMOND[2] - DIAMOND[1]) * kh
	-- a top or bottom edge from x0 to x1: a run of bar each side of the diamond
	local function edge(list, piece, x0, x1, y)
		local mid = (x0 + x1) / 2
		local d0, d1 = mid - diamondW / 2, mid + diamondW / 2
		S.ArtPart(list[1], f, ATLAS, piece, 40, DIAMOND[1], HBAND[1], HBAND[2], x0, y, d0 - x0, bandH)
		S.ArtPart(list[2], f, ATLAS, piece, DIAMOND[1], DIAMOND[2], HBAND[1], HBAND[2], d0, y, diamondW, bandH)
		S.ArtPart(list[3], f, ATLAS, piece, DIAMOND[2], 216, HBAND[1], HBAND[2], d1, y, x1 - d1, bandH)
	end
	follow(f, function(w, h)
		local at = {
			corner_nw = { o - CORNERS.corner_nw.left * s, o - CORNERS.corner_nw.top * s },
			corner_ne = { w - o - (256 - CORNERS.corner_ne.right) * s, o - CORNERS.corner_ne.top * s },
			corner_sw = { o - CORNERS.corner_sw.left * s, h - o - (256 - CORNERS.corner_sw.bottom) * s },
			corner_se = { w - o - (256 - CORNERS.corner_se.right) * s, h - o - (256 - CORNERS.corner_se.bottom) * s },
		}
		for key, tex in pairs(corners) do S.PlaceArt(tex, f, ATLAS, key, at[key][1], at[key][2], cell, cell) end
		local nw, ne, sw, se = at.corner_nw, at.corner_ne, at.corner_sw, at.corner_se
		-- each edge runs from well inside one corner's bar to well inside the other's
		edge(top, "border_top", nw[1] + 200 * s, ne[1] + 50 * s, o - (HBAR[1] - HBAND[1]) * kh)
		edge(bottom, "border_bottom", sw[1] + 200 * s, se[1] + 40 * s, h - o - (HBAR[2] - HBAND[1]) * kh)
		S.ArtPart(sides[1], f, ATLAS, "border_left", VBAND[1], VBAND[2], 60, 200, o - (VBAR[1] - VBAND[1]) * kv,
			nw[2] + 200 * s, bandW, sw[2] + 40 * s - (nw[2] + 200 * s))
		S.ArtPart(sides[2], f, ATLAS, "border_right", VBAND[1], VBAND[2], 60, 200, w - o - (VBAR[2] - VBAND[1]) * kv,
			ne[2] + 200 * s, bandW, se[2] + 40 * s - (ne[2] + 200 * s))
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
	-- windows are a blue-black tint; selected rows and chips are teal, the selected sidebar entry mint
	colors = function(c)
		c.window = { 0.045, 0.045, 0.06, 0.98 }
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
	-- windows and popups are the blue-black tint in the gold border, close to solid so the game world and frames
	-- behind them don't show through; a menu stays a small flat panel
	frame = function(f, role)
		if role == "menu" then
			S.Panel(f, S.colors.panel, S.colors.border)
		else
			S.Panel(f, S.colors.window)
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
