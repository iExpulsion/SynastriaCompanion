local _, NS = ...
local SC = NS.SC

-- The game's zones (ALL_ZONE_LIST) in the Picker. Picking one calls onPick(index into ALL_ZONE_LIST).
local ZonePicker = {}
SC.ZonePicker = ZonePicker

function ZonePicker.Name(index)
	local zone = index and ALL_ZONE_LIST and ALL_ZONE_LIST[index]
	return zone and (zone.n or (Custom_GetZoneName and Custom_GetZoneName(zone.v)))
end

local function zones()
	local items = {}
	for i in ipairs(ALL_ZONE_LIST or {}) do
		items[#items + 1] = { value = i, text = ZonePicker.Name(i) or "?" }
	end
	table.sort(items, function(a, b) return a.text < b.text end)
	return items
end

function ZonePicker.Available()
	return ALL_ZONE_LIST ~= nil and #ALL_ZONE_LIST > 0
end

function ZonePicker.Open(anchor, pick, selected)
	SC.Picker.Open(anchor, { items = zones(), placeholder = "Search Zones", emptyText = "No Zones Match",
		isSelected = function(i) return i == selected end, onPick = pick })
end

-- The ALL_ZONE_LIST index of a zone code, or nil.
function ZonePicker.IndexOf(code)
	for i, zone in ipairs(ALL_ZONE_LIST or {}) do
		if zone.v == code then return i end
	end
end

-- The ALL_ZONE_LIST index of the zone the player is in, or nil.
function ZonePicker.CurrentIndex()
	local here = Custom_GetCurrentZoneOur and Custom_GetCurrentZoneOur()
	return here and ZonePicker.IndexOf(here)
end
