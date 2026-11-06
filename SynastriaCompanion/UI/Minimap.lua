local _, NS = ...
local SC = NS.SC

-- Minimap button: left-click opens or closes the window, right-click opens a menu of the screens, drag moves it
-- around the minimap and Shift-drag anywhere on screen. Position and visibility are saved in SynastriaCompanionDB.minimap. When a LibDataBroker
-- display is installed, a launcher is registered there too.
local MinimapButton = {}
SC.MinimapButton = MinimapButton

local S = SC.Style

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"
local DEFAULT_ANGLE = 220
local button, menu

-- Which quadrants of each minimap shape are round, in the order GetMinimapShape addons use.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Shift-drag frees the button: it moves to UIParent at a saved spot (db.minimap.free), so it stays up even when
-- the minimap is hidden. A plain drag puts it back on the minimap's edge.
local function place()
	local free = SC.db.minimap.free
	local parent = free and UIParent or Minimap
	if button:GetParent() ~= parent then
		button:SetParent(parent)
		button:SetFrameStrata("MEDIUM")
		button:SetFrameLevel(8)
	end
	button:ClearAllPoints()
	if free then
		button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", free.x, free.y)
	else
		local angle = math.rad(SC.db.minimap.angle or DEFAULT_ANGLE)
		local x, y = math.cos(angle), math.sin(angle)
		local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
		local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
		local radius = Minimap:GetWidth() / 2 + 5
		if (SHAPES[shape] or SHAPES.ROUND)[quadrant] then
			x, y = x * radius, y * radius
		else
			local diagonal = math.sqrt(2 * radius * radius) - 10
			x = math.max(-radius, math.min(x * diagonal, radius))
			y = math.max(-radius, math.min(y * diagonal, radius))
		end
		button:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end
end

-- The screen menu: section headings and a row per screen, like the window's sidebar.
local ROW_H, MENU_W = 22, 170
local function createMenu()
	menu = CreateFrame("Frame", "SynastriaCompanionMinimapMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetWidth(MENU_W)
	menu:EnableMouse(true)
	S.Frame(menu, "menu")
	menu:Hide()
	tinsert(UISpecialFrames, "SynastriaCompanionMinimapMenu")
	local y, section = 4, nil
	for _, screen in ipairs(SC.Window.Ordered()) do
		if screen.section ~= section then
			section = screen.section
			S.SectionHeading(menu, section or "", S.PAD, -y - 4)
			y = y + 18
		end
		local item = CreateFrame("Button", nil, menu)
		item:SetHeight(ROW_H)
		item:SetPoint("TOPLEFT", 1, -y)
		item:SetPoint("TOPRIGHT", -1, -y)
		item:SetWidth(MENU_W - 2)
		S.Highlight(item)
		local text = S.Text(item, "small")
		text:SetPoint("LEFT", S.PAD + 6, 0)
		text:SetText(screen.label)
		local function pick()
			menu:Hide()
			SC.Window.Open(screen.key)
		end
		item:SetScript("OnClick", pick)
		SC.SecureCast.Overlay(item, { spell = function() return SC.SecureCast.ScreenSpell(screen) end, onClick = pick })
		y = y + ROW_H
	end
	menu:SetHeight(y + 4)
	S.TrackPopup(menu)
end

local function toggleMenu()
	if not menu then createMenu() end
	if menu:IsShown() then
		menu:Hide()
	else
		S.CloseMenus()
		menu.owner = button
		menu:ClearAllPoints()
		-- open toward the middle of the screen from wherever the minimap sits
		local x, y = button:GetCenter()
		local right = x and x > UIParent:GetWidth() / 2
		local top = y and y > UIParent:GetHeight() / 2
		menu:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), button,
			(top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"), 0, 0)
		menu:Show()
	end
end

local function onClick(_, mouse)
	if mouse == "RightButton" then
		toggleMenu()
	else
		if menu then menu:Hide() end
		SC.Window.Toggle()
	end
end

local function fillTooltip(tt)
	tt:AddLine("Synastria Companion", 1, 0.77, 0)
	tt:AddLine("Left-click to open or close the window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to pick a screen.", 0.8, 0.8, 0.8)
	tt:AddLine("Drag to move it around the minimap, Shift-drag to place it anywhere.", 0.6, 0.6, 0.66)
	tt:AddLine("/scomp minimap hides it; /scomp minimap reset puts it back.", 0.6, 0.6, 0.66)
end

-- Ends on the mouse release itself: a reparent mid-drag can cost the OnDragStop.
local function onDragUpdate(self)
	if IsMouseButtonDown("LeftButton") then
		local px, py = GetCursorPosition()
		if SC.db.minimap.free then
			local scale = UIParent:GetEffectiveScale()
			SC.db.minimap.free.x, SC.db.minimap.free.y = px / scale, py / scale
		else
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			SC.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
		end
		place()
	else
		self:SetScript("OnUpdate", nil)
	end
end

local function create()
	button = CreateFrame("Button", "SynastriaCompanionMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.icon:SetSize(17, 17)
	button.icon:SetPoint("TOPLEFT", 7, -6)
	button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		fillTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		if menu then menu:Hide() end
		SC.db.minimap.free = IsShiftKeyDown() and (SC.db.minimap.free or {}) or nil
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	place()

	-- a left-click that opens the window on a screen needing its spell casts it too; closing never does
	SC.SecureCast.Overlay(button, {
		name = "SynastriaCompanionMinimapCast", right = true,
		spell = function()
			return not SC.Window.Current() and SC.SecureCast.ScreenSpell(SC.Window.Default()) or nil
		end,
		onClick = function(mouse) onClick(button, mouse) end,
		onDragStart = function() button:GetScript("OnDragStart")(button) end,
		onDragStop = function() button:GetScript("OnDragStop")(button) end,
	})
end

local function registerBroker()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb then
		ldb:NewDataObject("SynastriaCompanion", {
			type = "launcher",
			icon = ICON,
			label = "Synastria Companion",
			OnClick = onClick,
			OnTooltipShow = fillTooltip,
		})
	end
end

function MinimapButton.Refresh()
	if SC.db.minimap.hide then button:Hide() else button:Show() end
end

function MinimapButton.Toggle()
	SC.db.minimap.hide = not SC.db.minimap.hide
	MinimapButton.Refresh()
	SC:Print(SC.db.minimap.hide and "Minimap button hidden. /scomp minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	SC.db.minimap.free, SC.db.minimap.angle = nil, nil
	place()
	SC:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

SC:On("PLAYER_LOGIN", function()
	SC.db.minimap = SC.db.minimap or {}
	create()
	registerBroker()
	MinimapButton.Refresh()
end)
