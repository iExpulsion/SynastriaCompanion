local _, NS = ...

-- The style kit (UI/Style.lua, vendored from MaterialCraftUI) puts itself on the addon table.
local S = NS.Style
NS.SC.Style = S

-- The shared yellow theme of these addons: the Material 3 dark scheme for seed #ffc400, with surfaces from the
-- Neutral scheme, primary from the Fidelity scheme and error from the baseline.
S.SetTheme({
	surfaceLowest = "0f0e0c", surface = "151311", surfaceLow = "1d1b19", surfaceContainer = "211f1d",
	surfaceHigh = "2c2a27", onSurface = "e7e1dd", onSurfaceVariant = "cbc6c1", outline = "94908c",
	outlineVariant = "494643", primary = "ffc400", onPrimary = "3f2e00", error = "ffb4ab", errorContainer = "93000a",
})

-- the game's forge colors (Titanforged, Warforged, Lightforged), so forge levels read as they do in its tooltips
S.colors.forge = { { 0.71, 0.76, 1, 1 }, { 0.94, 0.49, 0.42, 1 }, { 0.94, 0.94, 0.69, 1 } }
