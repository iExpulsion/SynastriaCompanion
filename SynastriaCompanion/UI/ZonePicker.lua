local _, NS = ...
local SC = NS.SC

-- A searchable list of the game's zones (ALL_ZONE_LIST), opened beside a button. Picking one calls
-- onPick(index into ALL_ZONE_LIST).
local ZonePicker = {}
SC.ZonePicker = ZonePicker

local S = SC.Style
local C = S.colors

local W, H = 300, 360
local popup, onPick

local function refresh()
	local q = popup.search:GetText():lower()
	local items = {}
	for i, zone in ipairs(ALL_ZONE_LIST or {}) do
		local name = zone.n or (Custom_GetZoneName and Custom_GetZoneName(zone.v)) or "?"
		if q == "" or name:lower():find(q, 1, true) then items[#items + 1] = { index = i, name = name } end
	end
	table.sort(items, function(a, b) return a.name < b.name end)
	popup.list:SetItems(items, "No Zones Match")
end

local function create()
	popup = CreateFrame("Frame", "SynastriaCompanionZonePicker", UIParent)
	popup:SetSize(W, H)
	popup:SetFrameStrata("DIALOG")
	popup:SetToplevel(true)
	popup:EnableMouse(true)
	S.Panel(popup, C.panel, C.border)
	tinsert(UISpecialFrames, "SynastriaCompanionZonePicker")

	popup.search = S.Input(popup, "SynastriaCompanionZoneSearch", W - 2 * S.PAD, "Search Zones", 40)
	popup.search:SetPoint("TOPLEFT", S.PAD, -S.PAD)
	popup.search:HookScript("OnTextChanged", refresh)

	popup.list = SC.Table.New(popup, nil, W - 2 * S.PAD, H - 3 * S.PAD - S.CONTROL_H, {
		columns = { { key = "name", label = "Zone", width = W - 2 * S.PAD - 14, sortable = false } },
		cell = function(item) return item.name end,
		onClick = function(item)
			popup:Hide()
			if onPick then onPick(item.index) end
		end,
	})
	popup.list.frame:SetPoint("TOPLEFT", popup.search, "BOTTOMLEFT", 0, -S.GAP)
	popup:SetScript("OnHide", function() popup.search:ClearFocus() end)
	S.OnDismiss(function() popup:Hide() end)
end

function ZonePicker.Available()
	return ALL_ZONE_LIST ~= nil and #ALL_ZONE_LIST > 0
end

function ZonePicker.Open(anchor, pick)
	if not popup then create() end
	onPick = pick
	popup:ClearAllPoints()
	popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	popup.search:SetText("")
	refresh()
	popup:Show()
end

function ZonePicker.Name(index)
	local zone = index and ALL_ZONE_LIST and ALL_ZONE_LIST[index]
	return zone and (zone.n or (Custom_GetZoneName and Custom_GetZoneName(zone.v)))
end

-- The ALL_ZONE_LIST index of the zone the player is in, or nil.
function ZonePicker.CurrentIndex()
	local here = Custom_GetCurrentZoneOur and Custom_GetCurrentZoneOur()
	if here then
		for i, zone in ipairs(ALL_ZONE_LIST or {}) do
			if zone.v == here then return i end
		end
	end
end
