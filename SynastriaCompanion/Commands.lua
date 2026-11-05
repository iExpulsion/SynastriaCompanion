local _, NS = ...
local SC = NS.SC

local function usage()
	local keys = {}
	for _, s in ipairs(SC.Window.screens) do keys[#keys + 1] = s.key end
	SC:Print("/scomp opens the window. /scomp <screen> opens a screen: %s.", table.concat(keys, ", "))
	SC:Print("/scomp replace <screen> on|off: whether the game's own window for a screen opens this one instead.")
end

local function findScreen(key)
	for _, s in ipairs(SC.Window.screens) do
		if s.key == key then return s end
	end
end

SLASH_SYNASTRIACOMPANION1 = "/scomp"
SLASH_SYNASTRIACOMPANION2 = "/companion"
SlashCmdList.SYNASTRIACOMPANION = function(msg)
	local cmd, arg, value = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	if cmd == "" then
		SC.Window.Toggle()
	elseif cmd == "help" then
		usage()
	elseif cmd == "replace" and findScreen(arg) and (value == "on" or value == "off") then
		SC.db.replace[arg] = value == "on"
		SC:Print("%s: %s.", findScreen(arg).label, value == "on" and "opens here" or "opens the game's window")
	elseif findScreen(cmd) then
		SC.Window.Open(cmd)
	else
		usage()
	end
end
