local _, NS = ...
local SC = NS.SC

-- Other names a screen answers to in /scomp.
local ALIASES = { autoloot = "lootfilter", itemdb = "lootdb", stats = "attuned", tmog = "transmog" }

local function findScreen(key)
	key = ALIASES[key] or key
	for _, s in ipairs(SC.Window.screens) do
		if s.key == key then return s end
	end
end

local function themeNames()
	local names = {}
	for _, skin in ipairs(SC.Style.Skins()) do names[#names + 1] = skin.key end
	return table.concat(names, ", ")
end

local function usage()
	local keys = {}
	for _, s in ipairs(SC.Window.Ordered()) do keys[#keys + 1] = s.key end
	SC:Print("/scomp opens the window. /scomp <screen> opens a screen: %s.", table.concat(keys, ", "))
	SC:Print("/scomp minimap shows or hides the minimap button, and /scomp minimap reset puts it back on the minimap.")
	SC:Print("/scomp reset moves the window back to the top middle of the screen.")
	SC:Print("/scomp theme <name> switches the look after a reload: %s.", themeNames())
	SC:Print("/scomp scale <percent> makes the windows bigger or smaller, such as /scomp scale 150.")
	SC:Print("/scomp pixel: whether windows snap to whole screen pixels, for crisp borders.")
	SC:Print("/scomp replace <screen> on|off: whether the game's own window for a screen opens this one instead.")
	SC:Print("/scomp share: whether friends, your guild and your group see your attunes and which items you need.")
end

SLASH_SYNASTRIACOMPANION1 = "/scomp"
SLASH_SYNASTRIACOMPANION2 = "/companion"
SlashCmdList.SYNASTRIACOMPANION = function(msg)
	local cmd, arg, value = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	local replaced = findScreen(arg)
	if cmd == "" then
		SC.Window.Toggle()
	elseif cmd == "help" then
		usage()
	elseif cmd == "minimap" and arg == "reset" then
		SC.MinimapButton.ResetPosition()
	elseif cmd == "minimap" then
		SC.MinimapButton.Toggle()
	elseif cmd == "reset" then
		SC.Window.ResetPosition()
		SC:Print("Window moved back to the top middle of the screen.")
	elseif cmd == "theme" and arg ~= "" and not SC.SetSkin(arg) then
		SC:Print("No theme called %s. Themes: %s.", arg, themeNames())
	elseif cmd == "theme" and arg ~= "" and arg == SC.db.skin then
		SC:Print("Theme: %s. /reload if it hasn't switched yet.", arg)
	elseif cmd == "theme" then
		SC:Print("Theme: %s. Themes: %s.", SC.Style.Skin(), themeNames())
	elseif cmd == "scale" and SC.SetWindowScale(tonumber(arg) and tonumber(arg) / 100) then
		local f = SC.Window.Frame()
		if f then f.sizePicker:SetText(SC.ScaleLabel(SC.db.windowScale)) end
		SC:Print("Window size: %s.", SC.ScaleLabel(SC.db.windowScale))
	elseif cmd == "scale" then
		SC:Print("Window size: %s. /scomp scale <50-300> sets it, in percent.", SC.ScaleLabel(SC.db.windowScale))
	elseif cmd == "pixel" then
		SC.SetPixelScale(not SC.db.pixelScale)
		SC:Print(SC.db.pixelScale and "Windows snap to whole screen pixels." or
			"Windows follow the UI scale exactly; borders may blur at some scales.")
	elseif cmd == "share" then
		SC.Friends.SetShare(not SC.db.share)
	elseif cmd == "replace" and replaced and (value == "on" or value == "off") then
		SC.db.replace[replaced.key] = value == "on"
		SC:Print("%s: %s.", replaced.label, value == "on" and "opens here" or "opens the game's window")
	elseif findScreen(cmd) then
		SC.Window.Open(findScreen(cmd).key)
	else
		usage()
	end
end
