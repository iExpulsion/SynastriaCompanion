local _, NS = ...
local SC = NS.SC

-- Attunable Items: the game's attune search with every result shown, live filters and sortable columns. Replaces
-- the window the server opens with OpenAttuneMgr.
local Attunable = {}
SC.AttunableUI = Attunable

local S = SC.Style
local C = S.colors
local Attune = SC.Attune
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, tbl
local filter
local QUERY_DELAY = 0.15

local CLASSES = {
	{ 1, "WARRIOR" }, { 2, "PALADIN" }, { 3, "HUNTER" }, { 4, "ROGUE" }, { 5, "PRIEST" }, { 6, "DEATHKNIGHT" },
	{ 7, "SHAMAN" }, { 8, "MAGE" }, { 9, "WARLOCK" }, { 11, "DRUID" },
}
local TRI = { { value = false, text = "Any" }, { value = 1, text = "Yes" }, { value = -1, text = "No" } }

local qualityColor = S.QualityColor

local function textOf(options, value, fallback)
	for _, o in ipairs(options) do
		if o.value == value then return o.text end
	end
	return fallback
end

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function status()
	local text
	if Attune.scanning then
		text = ("Scanning Items %d%%"):format(Attune.progress * 100)
	elseif panel.result then
		local r = panel.result
		local pct = r.pool > 0 and r.attuned * 100 / r.pool or 0
		if pct >= 100 and r.attuned < r.pool then pct = 99.99 end
		text = ("%s  " .. S.Hex(C.muted, "|  %d of %d Attuned (%.2f%%)")):format(
			S.Count(#r.items, "Item"), r.attuned, r.pool, pct)
	end
	panel.status:SetText(text or "")
end

local function query()
	panel.pending = nil
	if Attune.items then
		panel.result = Attune.Query(filter)
		Attune.Sort(panel.result.items, filter.sort, filter.desc)
		tbl:SetItems(panel.result.items, "No Items Match These Filters", panel.keepScroll)
		panel.keepScroll = nil
	end
	status()
end

-- Queries on the next frame, or after a short pause while typing, so a burst of changes runs one query.
local function requery(delay, keepScroll)
	panel.pending = GetTime() + (delay or 0)
	panel.keepScroll = keepScroll
end

-- The Forge column only shows in modes that list attuned items; a sort on it falls back to item level.
local function syncForgeColumn()
	local shown = Attune.ShowsAttuned(filter.mode)
	tbl:SetColumnShown("forge", shown)
	if not shown and filter.sort == "forge" then
		filter.sort, filter.desc = "ilvl", true
		tbl:SetSort(filter.sort, filter.desc)
	end
end

local function syncControls()
	syncForgeColumn()
	panel.name:SetText(filter.name or "")
	panel.mode:SetText(textOf(Attune.MODES, filter.mode or 0, "Attunable (Char)"))
	local class = "Mine"
	for _, c in ipairs(CLASSES) do
		if c[1] == filter.class then class = LOCALIZED_CLASS_NAMES_MALE[c[2]] or c[2] end
	end
	panel.class:SetText("Class: " .. class)
	panel.rarity:SetText("Rarity: " .. textOf(Attune.RARITIES, filter.rarity, "All"))
	local slot = "All"
	for _, s in ipairs(Attune.SLOTS) do
		if s[1] == filter.slot then slot = s[2] end
	end
	panel.slot:SetText("Slot: " .. slot)
	panel.mythic:SetText("Mythic: " .. textOf(TRI, filter.mythic or false, "Any"))
	panel.affix:SetText("Affix: " .. textOf(TRI, filter.affix or false, "Any"))
	panel.sources:SetText("5+ Sources: " .. textOf(TRI, filter.sources or false, "Any"))
	for _, key in ipairs({ "minReq", "maxReq", "minLvl", "maxLvl" }) do
		panel[key]:SetText(filter[key] and tostring(filter[key]) or "")
	end
	panel.zone:SetText(SC.ZonePicker.Name(filter.zone) or "Any Zone")
	if filter.zone ~= nil then panel.zoneClear:Enable() else panel.zoneClear:Disable() end
end

local function set(key, value)
	filter[key] = value
	syncControls()
	requery()
end

local function triDropdown(parent, width, key)
	local d = S.Dropdown(parent, width, function(v) set(key, v or nil) end)
	d:SetOptions(TRI)
	return d
end

local function numberBox(parent, name, key)
	local e = S.Input(parent, name, 44, "", 3)
	e:SetNumeric(true)
	e:SetJustifyH("CENTER")
	e:HookScript("OnTextChanged", function(self, user)
		if user then
			local n = tonumber(self:GetText())
			filter[key] = (n and n > 0) and n or nil
			requery(QUERY_DELAY)
		end
	end)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	return e
end

local function label(parent, text)
	local fs = S.Text(parent, "small", C.muted)
	fs:SetText(text)
	return fs
end

local function onRowClick(item, button)
	if IsModifiedClick() then
		HandleModifiedItemClick(Attune.Link(item))
	elseif button == "LeftButton" and OpenLootDb then
		OpenLootDb(item.id)
	end
end

local function forgeCell(item)
	local forge = Attune.Forge(item)
	if forge >= 0 then return Attune.FORGES[forge] or Attune.FORGES[0], C.forge[forge] or C.good end
	return ""
end

local COLUMNS = {
	{ key = "name", label = "Item", width = 305 },
	{ key = "slot", label = "Slot", width = 112 },
	{ key = "ilvl", label = "iLvl", width = 52, justify = "RIGHT", defaultDesc = true },
	{ key = "req", label = "Req", width = 48, justify = "RIGHT", defaultDesc = true },
	{ key = "sources", label = "Sources", width = 66, justify = "RIGHT", defaultDesc = true },
	{ key = "forge", label = "Forge", width = 110, defaultDesc = true },
}

local function cell(item, key)
	if key == "name" then return item.name, qualityColor(item.quality)
	elseif key == "slot" then return Attune.SlotLabel(item.equipLoc), C.muted
	elseif key == "ilvl" then return tostring(item.ilvl)
	elseif key == "req" then return item.req > 0 and tostring(item.req) or "", C.muted
	elseif key == "sources" then
		local n = Attune.SourceCount(item)
		return n > 0 and tostring(n) or "", C.muted
	elseif key == "forge" then return forgeCell(item)
	end
end

local function create(parent, width, height)
	filter = SC.db.attunable
	filter.sort = filter.sort or "ilvl"
	if filter.desc == nil then filter.desc = true end
	panel = CreateFrame("Frame", nil, parent)
	local x0, inner = PAD, width - 2 * PAD

	-- row 1: search, mode, class, reset
	panel.name = S.Input(panel, "SynastriaCompanionAttuneName", 260, "Search Items", 60)
	panel.name:SetPoint("TOPLEFT", x0, -PAD)
	panel.name:HookScript("OnTextChanged", function(self, user)
		if user then
			filter.name = self:GetText()
			requery(QUERY_DELAY)
		end
	end)
	panel.name:SetScript("OnEnterPressed", panel.name.ClearFocus)

	panel.mode = S.Dropdown(panel, 150, function(v) set("mode", v) end)
	panel.mode:SetOptions(Attune.MODES)
	panel.mode:SetPoint("LEFT", panel.name, "RIGHT", GAP, 0)

	panel.class = S.Dropdown(panel, 150, function(v) set("class", v or nil) end)
	panel.class:SetPoint("LEFT", panel.mode, "RIGHT", GAP, 0)

	local reset = S.Button(panel, "Reset Filters", "ghost", 100, function()
		for k in pairs(filter) do
			if k ~= "sort" and k ~= "desc" then filter[k] = nil end
		end
		syncControls()
		requery()
	end, "Clear every filter and the search.")
	reset:SetPoint("TOPRIGHT", -PAD, -PAD)

	-- row 2: rarity, slot, yes/no filters
	local y2 = -PAD - CONTROL_H - GAP
	panel.rarity = S.Dropdown(panel, 150, function(v) set("rarity", v or nil) end)
	local rarities = { { value = false, text = "All" } }
	for _, r in ipairs(Attune.RARITIES) do rarities[#rarities + 1] = r end
	panel.rarity:SetOptions(rarities)
	panel.rarity:SetPoint("TOPLEFT", x0, y2)

	panel.slot = S.Dropdown(panel, 160, function(v) set("slot", v or nil) end)
	local slots = { { value = false, text = "All" } }
	for _, s in ipairs(Attune.SLOTS) do slots[#slots + 1] = { value = s[1], text = s[2] } end
	panel.slot:SetOptions(slots)
	panel.slot:SetPoint("LEFT", panel.rarity, "RIGHT", GAP, 0)

	panel.mythic = triDropdown(panel, 112, "mythic")
	panel.mythic:SetPoint("LEFT", panel.slot, "RIGHT", GAP, 0)
	panel.affix = triDropdown(panel, 112, "affix")
	panel.affix:SetPoint("LEFT", panel.mythic, "RIGHT", GAP, 0)
	panel.sources = triDropdown(panel, 130, "sources")
	panel.sources:SetPoint("LEFT", panel.affix, "RIGHT", GAP, 0)
	panel.sources.tooltipText = "Items with more than five places they come from."

	-- row 3: level ranges and zone
	local y3 = y2 - CONTROL_H - GAP
	local reqLabel = label(panel, "Req. Level")
	reqLabel:SetPoint("TOPLEFT", x0, y3 - 6)
	panel.minReq = numberBox(panel, "SynastriaCompanionAttuneMinReq", "minReq")
	panel.minReq:SetPoint("LEFT", reqLabel, "RIGHT", GAP, 0)
	panel.maxReq = numberBox(panel, "SynastriaCompanionAttuneMaxReq", "maxReq")
	panel.maxReq:SetPoint("LEFT", panel.minReq, "RIGHT", 4, 0)

	local lvlLabel = label(panel, "Item Level")
	lvlLabel:SetPoint("LEFT", panel.maxReq, "RIGHT", PAD, 0)
	panel.minLvl = numberBox(panel, "SynastriaCompanionAttuneMinLvl", "minLvl")
	panel.minLvl:SetPoint("LEFT", lvlLabel, "RIGHT", GAP, 0)
	panel.maxLvl = numberBox(panel, "SynastriaCompanionAttuneMaxLvl", "maxLvl")
	panel.maxLvl:SetPoint("LEFT", panel.minLvl, "RIGHT", 4, 0)

	panel.zone = S.AddArrow(S.Button(panel, "Any Zone", "secondary", 170, function(self)
		SC.ZonePicker.Open(self, function(index) set("zone", index) end, filter.zone)
	end, "Only items that come from one zone."))
	panel.zone:SetPoint("LEFT", panel.maxLvl, "RIGHT", PAD, 0)
	panel.zoneHere = S.Button(panel, "Current", "secondary", 64, function()
		local index = SC.ZonePicker.CurrentIndex()
		if index then set("zone", index) else panel.status:SetText(S.Hex(C.bad, "Couldn't Tell Which Zone You're In")) end
	end, "Only items from the zone you're in.")
	panel.zoneHere:SetPoint("LEFT", panel.zone, "RIGHT", 4, 0)
	panel.zoneClear = S.Button(panel, "Clear", "secondary", 52, function() set("zone", nil) end, "Any zone again.")
	panel.zoneClear:SetPoint("LEFT", panel.zoneHere, "RIGHT", 4, 0)

	-- results
	local top = -PAD - 3 * (CONTROL_H + GAP)
	local footerH = PAD + 14 + PAD
	tbl = SC.Table.New(panel, "SynastriaCompanionAttuneTable", inner, height + top - footerH, {
		columns = COLUMNS, rowH = 20, icons = true, cell = cell,
		icon = function(item) return item.icon end,
		tooltip = function(tt, item)
			local link = Attune.Link(item)
			if link then tt:SetHyperlink(link) end
		end,
		onClick = onRowClick,
		onSort = function(key, desc)
			filter.sort, filter.desc = key, desc
			Attune.Sort(panel.result and panel.result.items or {}, key, desc)
			tbl:SetItems(panel.result and panel.result.items or {}, "No Items Match These Filters")
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", x0, top)
	tbl:SetSort(filter.sort, filter.desc)

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("BOTTOMLEFT", x0, PAD)
	local hint = S.Text(panel, "small", C.muted)
	hint:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	hint:SetText("Click: Item Database  |  Shift-Click: Link")

	panel:SetScript("OnUpdate", function()
		if Attune.scanning then status() end
		if panel.pending and GetTime() >= panel.pending then query() end
	end)
	panel:SetScript("OnHide", function() panel.pending = nil end)

	Attune.onChange = function()
		if panel:IsVisible() then requery(0.5, true) else panel.stale = true end
	end
	return panel
end

local function show()
	local multi = CMCGetClassCount and CMCGetClassCount() >= 2
	setShown(panel.class, multi)
	if multi then
		local options = { { value = false, text = "Mine" } }
		for _, c in ipairs(CLASSES) do
			if CMCHasClass(c[1]) then
				options[#options + 1] = { value = c[1], text = LOCALIZED_CLASS_NAMES_MALE[c[2]] or c[2] }
			end
		end
		panel.class:SetOptions(options)
	else
		filter.class = nil
	end
	local zones = SC.ZonePicker.Available() and ItemLocIsLoaded and (ItemLocIsLoaded() or 0) ~= 0
	setShown(panel.zone, zones)
	setShown(panel.zoneHere, zones)
	setShown(panel.zoneClear, zones)
	if not zones then filter.zone = nil end
	syncControls()
	if panel.stale or not panel.result then
		panel.stale = nil
		Attune.Scan(function() requery() end)
	end
	status()
end

SC.Window.AddScreen({
	key = "attunable",
	label = "Attunable Items",
	create = create,
	show = show,
	hook = { open = "OpenAttuneMgr", close = "CloseAttuneMgr", frame = "AttuneMgrFrame" },
})
