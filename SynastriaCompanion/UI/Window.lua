local _, NS = ...
local SC = NS.SC

-- The Companion window: a movable flat panel with a sidebar of screens on the left and the selected screen on the
-- right. Each screen builds its own content once and is told when it's shown.
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
	{ label = "Attunes", screens = { "attuned", "attunable" } },
	{ label = "Loot", screens = { "lootfilter", "bank", "lootdb" } },
	{ label = "Community", screens = { "leaderboards" } },
}

-- The screens in sidebar order, each with its section label; screens no section names come last.
function Window.Ordered()
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
-- for it, needsSpell() = true while its data only comes from casting that spell,
-- hook = { open = global, close = global, frame = global frame name, extra = { [global] = handler } } }
function Window.AddScreen(screen)
	Window.screens[#Window.screens + 1] = screen
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

local function savePosition(f)
	local point, _, relPoint, x, y = f:GetPoint()
	SC.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function paintNav()
	for _, b in ipairs(frame.nav) do
		local on = b.screen.key == current
		if on then b.bar:Show() b.selectedTex:Show() else b.bar:Hide() b.selectedTex:Hide() end
		b.label:SetTextColor(unpack(on and C.heading or C.text))
	end
end

local function createTitleBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		S.Dismiss()
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePosition(f)
	end)
	S.Rule(bar, "BOTTOM")

	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", S.PAD, 0)
	title:SetText("Synastria " .. S.Hex(C.accent, "Companion"))
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", S.GAP, 0)
	version:SetText("v" .. SC.version)

	local inset = (TITLE_H - S.CONTROL_H) / 2
	local close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("RIGHT", -inset, 0)
	f.gameWindow = S.Button(bar, "Game Window", "ghost", 96, function()
		local key = current
		f:Hide()
		SC.Hooks.OpenOriginal(key)
	end, "Open the game's own window for this screen.")
	f.gameWindow:SetPoint("RIGHT", close, "LEFT", -S.GAP, 0)
end

local function createSidebar(f)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 0, -TITLE_H)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR_W)
	local fill = S.Solid(side, "BACKGROUND", C.sidebar)
	fill:SetPoint("TOPLEFT", 1, 0)
	fill:SetPoint("BOTTOMRIGHT", 0, 1)
	local edge = S.Solid(side, "BORDER", C.border)
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")

	f.nav = {}
	local y, section = S.GAP, nil
	for i, screen in ipairs(Window.Ordered()) do
		if screen.section ~= section then
			section = screen.section
			S.SectionHeading(side, section or "", S.PAD, -y - (i > 1 and S.GAP or 0) - 4)
			y = y + (i > 1 and S.GAP or 0) + SECTION_H
		end
		local b = CreateFrame("Button", nil, side)
		b:SetHeight(NAV_H)
		b:SetPoint("TOPLEFT", 1, -y)
		b:SetPoint("TOPRIGHT", -1, -y)
		y = y + NAV_H
		local hover = S.Solid(b, "HIGHLIGHT", C.hover)
		hover:SetAllPoints()
		b.selectedTex = S.Solid(b, "BACKGROUND", C.selected)
		b.selectedTex:SetAllPoints()
		b.bar = S.Solid(b, "BORDER", C.accent)
		b.bar:SetWidth(3)
		b.bar:SetPoint("TOPLEFT")
		b.bar:SetPoint("BOTTOMLEFT")
		b.label = S.Text(b, "normal")
		-- entries sit in from their section heading
		b.label:SetPoint("LEFT", S.PAD + 8, 0)
		b.label:SetText(screen.label)
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
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	local pos = SC.db.window
	if pos and pos.point then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y) else f:SetPoint("CENTER") end
	S.Panel(f, C.window, C.border)
	tinsert(UISpecialFrames, "SynastriaCompanionFrame")
	f:Hide()

	createTitleBar(f)
	createSidebar(f)
	f.main = CreateFrame("Frame", nil, f)
	f.main:SetPoint("TOPLEFT", SIDEBAR_W, -TITLE_H)
	f.main:SetPoint("BOTTOMRIGHT")
	f.panels = {}

	f:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		S.Dismiss()
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

function Window.Toggle(key)
	if frame and frame:IsShown() and (key == nil or key == current) then frame:Hide() else Window.Open(key) end
end

function Window.Current()
	return frame and frame:IsShown() and current
end

function Window.Frame()
	return frame
end
