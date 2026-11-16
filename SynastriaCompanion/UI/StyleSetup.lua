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

-- The saved skin, window size and pixel snapping (S.Settings) go on before anything is built; frames take their
-- look when they're made.
SC:OnLoad(function()
	S.Settings.Use(SC.db, { theme = YELLOW, name = "Synastria Companion",
		onRescaled = function() SC.Window.Rescaled() end })
end)

SC.WINDOW_SCALES = S.Settings.SCALES
SC.ScaleLabel = S.Settings.ScaleLabel
SC.SetWindowScale = S.Settings.SetWindowScale
SC.PixelScale = S.Settings.PixelScale
SC.SnapPosition = S.Settings.SnapPosition
SC.SetPixelScale = S.Settings.SetPixelScale
SC.SetSkin = S.Settings.SetSkin
