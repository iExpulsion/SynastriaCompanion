local _, NS = ...
local SC = NS.SC

-- The style kit (UI/Style.lua, vendored from MaterialCraftUI) puts itself on the addon table, and its skins
-- (UI/Skins) register with it.
local S = NS.Style
SC.Style = S
-- the kit's virtual table, which every list and table on Companion's screens is
SC.Table = S.Table

-- The shared yellow theme of these addons: the Material 3 dark scheme for seed #ffc400, with surfaces from the
-- Neutral scheme, primary from the Fidelity scheme and error from the baseline. Skins with a scheme of their own,
-- such as Cognac, use theirs instead.
local YELLOW = {
	surfaceLowest = "0f0e0c", surface = "151311", surfaceLow = "1d1b19", surfaceContainer = "211f1d",
	surfaceHigh = "2c2a27", onSurface = "e7e1dd", onSurfaceVariant = "cbc6c1", outline = "94908c",
	outlineVariant = "494643", primary = "ffc400", onPrimary = "3f2e00", error = "ffb4ab", errorContainer = "93000a",
}
S.SetTheme(YELLOW)

-- the game's forge colors (Titanforged, Warforged, Lightforged), so forge levels read as they do in its tooltips
S.colors.forge = { { 0.71, 0.76, 1, 1 }, { 0.94, 0.49, 0.42, 1 }, { 0.94, 0.94, 0.69, 1 } }

local function known(key)
	for _, skin in ipairs(S.Skins()) do
		if skin.key == key then return true end
	end
	return false
end

-- The saved skin goes on before anything is built; frames take their look when they're made.
SC:OnLoad(function()
	if not known(SC.db.skin) then SC.db.skin = "material" end
	S.UseSkin(SC.db.skin, YELLOW)
end)

-- Companion's windows, dialogs and popups are pixel-scaled (S.PixelScale) unless the player turned it off, so their
-- edges and 1px borders land on whole screen pixels. SC.PixelScale registers one as it's made.
local pixelFrames = {}

function SC.PixelScale(frame)
	pixelFrames[#pixelFrames + 1] = frame
	S.PixelScale(frame, SC.db.pixelScale)
	return frame
end

-- Snaps a window's position to whole pixels, when pixel scaling is on.
function SC.SnapPosition(frame)
	if SC.db.pixelScale then S.SnapPosition(frame) end
end

function SC.SetPixelScale(on)
	SC.db.pixelScale = on
	for _, frame in ipairs(pixelFrames) do
		S.PixelScale(frame, on)
		SC.SnapPosition(frame)
	end
end

StaticPopupDialogs.SYNASTRIA_COMPANION_RELOAD = {
	text = "Synastria Companion switches to the %s theme after a reload. Reload now?",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Saves a skin for the next load and offers to reload. Returns false for a skin that doesn't exist.
function SC.SetSkin(key)
	local ok = known(key)
	if ok and key ~= SC.db.skin then
		SC.db.skin = key
		local label = key
		for _, skin in ipairs(S.Skins()) do
			if skin.key == key then label = skin.label end
		end
		StaticPopup_Show("SYNASTRIA_COMPANION_RELOAD", label)
	end
	return ok
end
