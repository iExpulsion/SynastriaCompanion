local _, NS = ...
local SC = NS.SC

-- Minimap button (S.MinimapButton): left-click opens or closes the window, right-click opens a menu of the
-- screens. Position and visibility are saved in SynastriaCompanionDB.minimap. When a LibDataBroker display is
-- installed, a launcher is registered there too.
local MinimapButton = {}
SC.MinimapButton = MinimapButton

local S = SC.Style

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"
local button, menu

-- The screen menu: section headings and a row per screen, like the window's sidebar.
local ROW_H, MENU_W, MENU_ICON = 22, 170, 16
local function createMenu()
	menu = CreateFrame("Frame", "SynastriaCompanionMinimapMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetWidth(MENU_W)
	menu:EnableMouse(true)
	SC.PixelScale(menu)
	S.Frame(menu, "menu")
	menu:Hide()
	tinsert(UISpecialFrames, "SynastriaCompanionMinimapMenu")
	-- rows sit inside the menu's border, however thick the theme draws it
	local m = S.metrics.menuInset
	local y, section = 3 + m, nil
	for _, screen in ipairs(SC.Window.Ordered()) do
		if screen.section ~= section then
			section = screen.section
			S.SectionHeading(menu, section or "", S.PAD, -y - 4)
			y = y + 18
		end
		local item = CreateFrame("Button", nil, menu)
		item:SetHeight(ROW_H)
		item:SetPoint("TOPLEFT", m, -y)
		item:SetPoint("TOPRIGHT", -m, -y)
		item:SetWidth(MENU_W - 2 * m)
		S.Highlight(item)
		local icon = item:CreateTexture(nil, "ARTWORK")
		icon:SetSize(MENU_ICON, MENU_ICON)
		icon:SetPoint("LEFT", S.PAD + 6, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(SC.Window.ScreenIcon(screen))
		item.icon = icon
		local text = S.Text(item, "small")
		text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		text:SetText(screen.label)
		local function pick()
			menu:Hide()
			SC.Window.Open(screen.key)
		end
		item:SetScript("OnClick", pick)
		SC.SecureCast.Overlay(item, { spell = function() return SC.SecureCast.ScreenSpell(screen) end, onClick = pick })
		y = y + ROW_H
	end
	menu:SetHeight(y + 3 + m)
	S.TrackPopup(menu)
end

local function toggleMenu(owner)
	if not menu then createMenu() end
	if menu:IsShown() and menu.owner == owner then
		menu:Hide()
	else
		S.CloseMenus()
		menu.owner = owner
		menu:ClearAllPoints()
		-- open toward the middle of the screen from wherever the clicked button sits
		local x, y = owner:GetCenter()
		local right = x and x > UIParent:GetWidth() / 2
		local top = y and y > UIParent:GetHeight() / 2
		menu:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), owner,
			(top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"), 0, 0)
		menu:Show()
	end
end

local function onClick(owner, mouse)
	if mouse == "RightButton" then
		toggleMenu(owner or button)
	else
		if menu then menu:Hide() end
		SC.Window.Toggle()
	end
end

local function fillTooltip(tt)
	tt:AddLine("Synastria Companion", 1, 0.77, 0)
	tt:AddLine("Left-click to open or close the window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to pick a screen.", 0.8, 0.8, 0.8)
end

local function create()
	button = S.MinimapButton({
		name = "SynastriaCompanionMinimapButton", icon = ICON, db = SC.db.minimap, angle = 220,
		onClick = onClick, tooltip = fillTooltip, hint = "/scomp minimap hides it; /scomp minimap reset puts it back.",
		onDragStart = function() if menu then menu:Hide() end end,
	})

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

-- Registered while the addon loads, not at login: displays like ElvUI fill their panels on PLAYER_LOGIN before
-- our handler runs, and a launcher created after that never lands in the panel set to it.
LibStub("LibDataBroker-1.1"):NewDataObject("SynastriaCompanion", {
	type = "launcher",
	icon = ICON,
	label = "Synastria Companion",
	text = "Companion",
	OnClick = onClick,
	OnTooltipShow = fillTooltip,
})

function MinimapButton.Refresh()
	button:Refresh()
end

function MinimapButton.Toggle()
	SC.db.minimap.hide = not SC.db.minimap.hide
	button:Refresh()
	SC:Print(SC.db.minimap.hide and "Minimap button hidden. /scomp minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	button:ResetPosition()
	SC:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

SC:On("PLAYER_LOGIN", function()
	SC.db.minimap = SC.db.minimap or {}
	create()
end)
