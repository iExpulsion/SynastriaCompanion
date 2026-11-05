local _, NS = ...
local SC = NS.SC

-- Other names a screen answers to in /scomp.
local ALIASES = { autoloot = "lootfilter", itemdb = "lootdb", stats = "attuned" }

local function findScreen(key)
	key = ALIASES[key] or key
	for _, s in ipairs(SC.Window.screens) do
		if s.key == key then return s end
	end
end

local function usage()
	local keys = {}
	for _, s in ipairs(SC.Window.Ordered()) do keys[#keys + 1] = s.key end
	SC:Print("/scomp opens the window. /scomp <screen> opens a screen: %s.", table.concat(keys, ", "))
	SC:Print("/scomp minimap shows or hides the minimap button.")
	SC:Print("/scomp replace <screen> on|off: whether the game's own window for a screen opens this one instead.")
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
	elseif cmd == "minimap" then
		SC.MinimapButton.Toggle()
	elseif cmd == "replace" and replaced and (value == "on" or value == "off") then
		SC.db.replace[replaced.key] = value == "on"
		SC:Print("%s: %s.", replaced.label, value == "on" and "opens here" or "opens the game's window")
	elseif findScreen(cmd) then
		SC.Window.Open(findScreen(cmd).key)
	else
		usage()
	end
end
