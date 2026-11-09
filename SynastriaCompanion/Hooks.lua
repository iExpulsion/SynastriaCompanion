local _, NS = ...
local SC = NS.SC

-- Takes over the game's own windows by replacing their global Open/Close functions. The game can rebuild a window
-- and redefine those functions at any time, so Check runs every second and puts the replacements back. A screen
-- the player turned off in SC.db.replace goes to the original.
local Hooks = { screens = {}, originals = {} }
SC.Hooks = Hooks

-- screen: { key, frame = global frame name, show(...), replace = { [global function name] = handler(...) },
-- open = the global name in replace that opens it }
function Hooks.Register(screen)
	Hooks.screens[#Hooks.screens + 1] = screen
end

function Hooks.Replacing(key)
	return SC.db ~= nil and SC.db.replace[key] ~= false
end

local function findScreen(key)
	for _, screen in ipairs(Hooks.screens) do
		if screen.key == key then return screen end
	end
end

function Hooks.HasOriginal(key)
	local screen = findScreen(key)
	return screen ~= nil and Hooks.originals[screen.open] ~= nil
end

-- Calls the game's own open function, for a screen not replaced or the Game Window button.
function Hooks.OpenOriginal(key, ...)
	local screen = findScreen(key)
	local fn = screen and Hooks.originals[screen.open]
	if fn then
		Hooks.allowStock = true
		fn(...)
		Hooks.allowStock = false
	end
end

local installed, frames = {}, {}

local function install(screen)
	for name, handler in pairs(screen.replace) do
		local current = _G[name]
		if current and current ~= installed[name] then
			Hooks.originals[name] = current
			local function replacement(...)
				if Hooks.Replacing(screen.key) then
					return handler(...)
				end
				return Hooks.originals[name](...)
			end
			installed[name] = replacement
			_G[name] = replacement
		end
	end
	local stock = screen.frame and _G[screen.frame]
	if stock and frames[screen.key] ~= stock then
		frames[screen.key] = stock
		stock:HookScript("OnShow", function(f)
			if Hooks.Replacing(screen.key) and not Hooks.allowStock then
				f:Hide()
				screen.show()
			end
		end)
	end
end

function Hooks.Check()
	for _, screen in ipairs(Hooks.screens) do install(screen) end
	SC:RegisterCustomEvents()
end

local elapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed >= 1 then
		elapsed = 0
		Hooks.Check()
	end
end)

SC:On("PLAYER_ENTERING_WORLD", Hooks.Check)

-- The server's Lua and data arrive in a different order on a fresh login than on a reload; SynastriaSafeInvoke runs
-- this once both are in.
function SynastriaCompanion_OnReady()
	SC.ready = true
	Hooks.Check()
end

SC:OnLoad(function()
	if SynastriaSafeInvoke then SynastriaSafeInvoke("SynastriaCompanion_OnReady") end
end)
