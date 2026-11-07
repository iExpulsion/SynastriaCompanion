local _, NS = ...
local SC = NS.SC

-- The Companion window: a movable panel with a sidebar of screens on the left and the selected screen on the
-- right. Each screen builds its own content once and is told when it's shown. The skin's border (S.metrics.edge)
-- goes around the same content area, so screens are the same size in every skin.
local Window = { screens = {} }
SC.Window = Window

local S = SC.Style
local C = S.colors

local W, H = 900, 600
local TITLE_H, SIDEBAR_W, NAV_H, SECTION_H = 36, 170, 30, 20
Window.CONTENT_W, Window.CONTENT_H = W - SIDEBAR_W, H - TITLE_H

local frame
local current

-- The sidebar's sections and the screens in each, in order.
Window.SECTIONS = {
	{ label = "Character", screens = { "perks", "transmog" } },
	{ label = "Attunes", screens = { "attuned", "attunable" } },
	{ label = "Loot", screens = { "lootfilter", "bank", "lootdb" } },
	{ label = "Community", screens = { "leaderboards" } },
}

-- The screens in sidebar order, each with its section label; screens no section names come last. It's asked for
-- every frame (by the minimap button's cast check), so it's built once and kept until a screen is added.
local ordered
local function buildOrder()
	local out, placed = {}, {}
	for _, section in ipairs(Window.SECTIONS) do
		for _, key in ipairs(section.screens) do
			for _, screen in ipairs(Window.screens) do
				if screen.key == key then
					screen.section = section.label
					out[#out + 1] = screen
					placed[screen] = true
				end
			end
		end
	end
	for _, screen in ipairs(Window.screens) do
		if not placed[screen] then out[#out + 1] = screen end
	end
	return out
end

function Window.Ordered()
	ordered = ordered or buildOrder()
	return ordered
end

-- The screen the window opens on when no screen is named: the last one shown, or the first.
function Window.Default()
	local first = Window.Ordered()[1]
	local last = SC.db and SC.db.lastScreen
	for _, screen in ipairs(Window.screens) do
		if screen.key == last then return screen end
	end
	return first
end

-- screen: { key, label, create(parent, width, height) -> panel, show(panel, ...), spell = the game's View spell
-- for it, needsSpell() = true while its data only comes from casting that spell, gameArgs() = what the Game Window
-- button passes the game's open function,
-- hook = { open = global, close = global, frame = global frame name, extra = { [global] = handler } } }
function Window.AddScreen(screen)
	Window.screens[#Window.screens + 1] = screen
	ordered = nil
	local hook = screen.hook
	if hook then
		local function show(...) Window.Open(screen.key, ...) end
		local replace = { [hook.open] = show }
		if hook.close then replace[hook.close] = function() Window.Close(screen.key) end end
		for name, fn in pairs(hook.extra or {}) do replace[name] = fn end
		SC.Hooks.Register({ key = screen.key, frame = hook.frame, open = hook.open, show = show, replace = replace })
	end
end

local function find(key)
	for _, screen in ipairs(Window.screens) do
		if screen.key == key then return screen end
	end
end

-- The default spot is the style kit's, top middle of the screen, shared with Build Suite and Rotation Assist.
local function placeDefault(f)
	S.PlaceWindow(f)
end

local function savePosition(f)
	SC.SnapPosition(f)
	local point, _, relPoint, x, y = f:GetPoint()
	SC.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function paintNav()
	for _, b in ipairs(frame.nav) do b:SetSelected(b.screen.key == current) end
end

-- The theme picker: every skin the kit has, with who made it on hover. A change applies after a reload.
local function createThemePicker(bar, anchor)
	local label = S.Text(bar, "small", C.muted)
	label:SetPoint("LEFT", anchor, "RIGHT", 2 * S.GAP, 0)
	label:SetText("Theme")
	local options, inUse = {}, nil
	for _, skin in ipairs(S.Skins()) do
		options[#options + 1] = { value = skin.key, text = skin.label, tooltip = skin.credit }
		if skin.key == S.Skin() then inUse = skin.label end
	end
	local picker
	picker = S.Dropdown(bar, 96, function(key)
		SC.SetSkin(key)
		for _, opt in ipairs(options) do
			if opt.value == key then picker:SetText(opt.text) end
		end
	end)
	picker:SetOptions(options)
	picker:SetText(inUse or "")
	picker:SetPoint("LEFT", label, "RIGHT", S.GAP, 0)
end

local function createTitleBar(f, edge)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", edge, -edge)
	bar:SetPoint("TOPRIGHT", -edge, -edge)
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		S.Dismiss()
		SC.SecureCast.SetSuspended(true)
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePosition(f)
		SC.SecureCast.SetSuspended(false)
	end)
	S.Rule(bar, "BOTTOM")

	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", S.PAD, 0)
	title:SetText("Synastria " .. S.Hex(C.accent, "Companion"))
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", S.GAP, 0)
	version:SetText("v" .. SC.version)
	createThemePicker(bar, version)

	local inset = (TITLE_H - S.CONTROL_H) / 2
	local close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("RIGHT", -inset, 0)
	f.gameWindow = S.Button(bar, "Game Window", "ghost", 96, function()
		local key = current
		local screen = find(key)
		local arg = screen and screen.gameArgs and screen.gameArgs()
		f:Hide()
		SC.Hooks.OpenOriginal(key, arg)
	end, "Open the game's own window for this screen.")
	f.gameWindow:SetPoint("RIGHT", close, "LEFT", -S.GAP, 0)
end

local function createSidebar(f, edge)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", edge, -edge - TITLE_H)
	side:SetPoint("BOTTOMLEFT", edge, edge)
	side:SetWidth(SIDEBAR_W)
	side:SetHeight(H - TITLE_H)
	S.Sidebar(side)
	local inset = 1 + S.metrics.navInset

	f.nav = {}
	local y, section = S.GAP, nil
	for i, screen in ipairs(Window.Ordered()) do
		if screen.section ~= section then
			section = screen.section
			S.SectionHeading(side, section or "", inset + S.PAD - 1, -y - (i > 1 and S.GAP or 0) - 4)
			y = y + (i > 1 and S.GAP or 0) + SECTION_H
		end
		local b = CreateFrame("Button", nil, side)
		b:SetHeight(NAV_H)
		b:SetPoint("TOPLEFT", inset, -y)
		b:SetPoint("TOPRIGHT", -inset, -y)
		b:SetWidth(SIDEBAR_W - 2 * inset)
		y = y + NAV_H
		S.NavEntry(b, screen.label)
		b.screen = screen
		b:SetScript("OnClick", function() Window.Open(screen.key) end)
		-- a screen that needs its spell cast gets it cast by the same click
		SC.SecureCast.Overlay(b, { spell = function() return SC.SecureCast.ScreenSpell(screen) end,
			onClick = function() Window.Open(screen.key) end })
		f.nav[i] = b
	end
end

local function create()
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaCompanionFrame", UIParent)
	frame = f
	local edge = S.metrics.edge
	f:SetSize(W + 2 * edge, H + 2 * edge)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	SC.PixelScale(f)
	local pos = SC.db.window
	if pos and pos.point then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y) else placeDefault(f) end
	SC.SnapPosition(f)
	S.Frame(f, "window")
	tinsert(UISpecialFrames, "SynastriaCompanionFrame")
	f:Hide()

	createTitleBar(f, edge)
	createSidebar(f, edge)
	f.main = CreateFrame("Frame", nil, f)
	f.main:SetPoint("TOPLEFT", edge + SIDEBAR_W, -edge - TITLE_H)
	f.main:SetPoint("BOTTOMRIGHT", -edge, edge)
	f.panels = {}

	f:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		S.Dismiss()
		-- closing mid-drag (Escape) can skip OnDragStop
		f:StopMovingOrSizing()
		SC.SecureCast.SetSuspended(false)
	end)
	return f
end

-- Shows the window on a screen (default: the last one), passing the rest on to that screen.
function Window.Open(key, ...)
	frame = frame or create()
	local screen = find(key or current) or Window.Default()
	S.Dismiss()
	current = screen.key
	SC.db.lastScreen = current
	for k, panel in pairs(frame.panels) do
		if k ~= current then panel:Hide() end
	end
	local panel = frame.panels[current]
	if not panel then
		panel = screen.create(frame.main, Window.CONTENT_W, Window.CONTENT_H)
		panel:SetAllPoints(frame.main)
		frame.panels[current] = panel
	end
	if SC.Hooks.HasOriginal(current) then frame.gameWindow:Show() else frame.gameWindow:Hide() end
	paintNav()
	frame:Show()
	panel:Show()
	if screen.show then screen.show(panel, ...) end
end

-- Hides the window if it's on that screen (or on any screen without a key).
function Window.Close(key)
	if frame and (key == nil or key == current) then frame:Hide() end
end

-- Forgets the saved position and puts the window back at its default spot.
function Window.ResetPosition()
	SC.db.window = {}
	if frame then
		placeDefault(frame)
		SC.SnapPosition(frame)
	end
end

function Window.Toggle(key)
	if frame and frame:IsShown() and (key == nil or key == current) then frame:Hide() else Window.Open(key) end
end

function Window.Current()
	return frame and frame:IsShown() and current
end

function Window.Frame()
	return frame
end
