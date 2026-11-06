local ADDON, NS = ...

local SC = { version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "dev" }
NS.SC = SC
_G.SynastriaCompanion = SC

local DEFAULTS = {
	window = {},
	-- per screen: false gives that screen back to the game's own window
	replace = {},
	attunable = {},
	-- the style kit's skin: "material" or "cognac"
	skin = "material",
	-- scale windows so their units are whole screen pixels
	pixelScale = true,
}

function SC:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffffc400Synastria Companion|r: " .. msg)
end

local function fill(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = type(v) == "table" and {} or v
		end
		if type(v) == "table" and type(db[k]) == "table" then fill(db[k], v) end
	end
end

-- Synastria's own events (RegisterForCustomEvent), as event name -> handlers. The game can rebuild its registry,
-- so registrations are renewed by SC.Hooks.Check.
SC.customHandlers = {}

function SC:OnCustomEvent(name, fn)
	local list = self.customHandlers[name] or {}
	self.customHandlers[name] = list
	list[#list + 1] = fn
	self:RegisterCustomEvents()
end

local registeredWith, registered = nil, {}
function SC:RegisterCustomEvents()
	if RegisterForCustomEvent then
		if registeredWith ~= RegisterForCustomEvent then
			registeredWith, registered = RegisterForCustomEvent, {}
		end
		for name, list in pairs(self.customHandlers) do
			if not registered[name] then
				registered[name] = true
				RegisterForCustomEvent(name, function(...)
					for _, fn in ipairs(list) do fn(...) end
				end)
			end
		end
	end
end

local events = CreateFrame("Frame")
SC.events = events
local handlers = {}

function SC:On(event, fn)
	handlers[event] = handlers[event] or {}
	table.insert(handlers[event], fn)
	events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

SC:On("ADDON_LOADED", function(name)
	if name == ADDON then
		SynastriaCompanionDB = SynastriaCompanionDB or {}
		fill(SynastriaCompanionDB, DEFAULTS)
		SC.db = SynastriaCompanionDB
		for _, fn in ipairs(SC.onLoad or {}) do fn() end
	end
end)

-- Runs fn once saved data is loaded.
function SC:OnLoad(fn)
	self.onLoad = self.onLoad or {}
	table.insert(self.onLoad, fn)
end
