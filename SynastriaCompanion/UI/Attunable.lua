local _, NS = ...
local SC = NS.SC

-- Attunable Items: the game's attune search with every result shown, live filters and sortable columns. Replaces
-- the window the server opens with OpenAttuneMgr.
local Attunable = {}
SC.AttunableUI = Attunable

local S = SC.Style
local C = S.colors
local Attune = SC.Attune
local ZoneInfo = SC.ZoneInfo
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, tbl
local filter
local QUERY_DELAY = 0.15
local ROWS = 5

local CLASSES = {
	{ 1, "WARRIOR" }, { 2, "PALADIN" }, { 3, "HUNTER" }, { 4, "ROGUE" }, { 5, "PRIEST" }, { 6, "DEATHKNIGHT" },
	{ 7, "SHAMAN" }, { 8, "MAGE" }, { 9, "WARLOCK" }, { 11, "DRUID" },
}
local TRI = { { value = false, text = "Any" }, { value = 1, text = "Yes" }, { value = -1, text = "No" } }

local LEVELS = {
	{ value = Attune.NOT_ATTUNED, text = "Not Attuned", width = 84, tooltip = "Items you haven't attuned." },
	{ value = 2, text = "Attuned", width = 64, tooltip = "Items attuned, but not forged yet." },
	{ value = 4, text = "TF", width = 36, tooltip = "Items whose best attune is Titanforged." },
	{ value = 8, text = "WF", width = 38, tooltip = "Items whose best attune is Warforged." },
	{ value = 16, text = "LF", width = 36, tooltip = "Items whose best attune is Lightforged." },
}
local AFFIX_FORGES = {
	{ value = 0, text = "Base", width = 46, tooltip = "Count affixes attuned at the base level." },
	{ value = 1, text = "TF", width = 36, tooltip = "Count affixes attuned at Titanforged." },
	{ value = 2, text = "WF", width = 38, tooltip = "Count affixes attuned at Warforged." },
	{ value = 3, text = "LF", width = 36, tooltip = "Count affixes attuned at Lightforged." },
}
local BINDS = {
	{ value = Attune.BOP, text = "BoP", width = 44, tooltip = "Bind on pickup." },
	{ value = Attune.BOE, text = "BoE", width = 44, tooltip = "Bind on equip, bind on use, or not bound." },
}
local KINDS = {
	{ value = ZoneInfo.DUNGEON, text = "Dungeon", width = 64, tooltip = "Items that drop in a dungeon." },
	{ value = ZoneInfo.RAID, text = "Raid", width = 46, tooltip = "Items that drop in a raid." },
	{ value = ZoneInfo.WORLD, text = "World", width = 52, tooltip = "Items that drop in the open world." },
}
local EXPANSIONS = {
	{ value = ZoneInfo.CLASSIC, text = "Classic", width = 58, tooltip = "Items from Classic zones and instances." },
	{ value = ZoneInfo.TBC, text = "TBC", width = 42, tooltip = "Items from The Burning Crusade zones and instances." },
	{ value = ZoneInfo.WOTLK, text = "WotLK", width = 52, tooltip = "Items from Wrath of the Lich King zones and instances." },
}
local AFFIX_CHOICES = {
	{ value = false, text = "Any" },
	{ value = 1, text = "Has Affixes", tooltip = "Items that roll a random affix." },
	{ value = -1, text = "No Affixes", tooltip = "Items without a random affix." },
	{ value = "left", text = "Affixes Left", tooltip = "Items with affixes you haven't attuned yet at the Affix Forge level." },
}

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

local function waitingForSources()
	return Attune.NeedsSources(filter) and not Attune.sourcesRead
end

local function status()
	local text
	if Attune.scanning then
		text = ("Scanning Items %d%%"):format(Attune.progress * 100)
	elseif waitingForSources() then
		text = ("Reading Item Sources %d%%"):format(Attune.sourceProgress * 100)
	elseif panel.result then
		local r = panel.result
		local pct = r.pool > 0 and r.attuned * 100 / r.pool or 0
		if pct >= 100 and r.attuned < r.pool then pct = 99.99 end
		text = ("%s  " .. S.Hex(C.muted, "|  %d of %d Attuned (%.2f%%)")):format(
			S.Count(#r.items, "Item"), r.attuned, r.pool, pct)
	end
	panel.status:SetText(text or "")
end

local requery

local function query()
	panel.pending = nil
	if Attune.items and waitingForSources() then
		panel.result = nil
		tbl:SetItems({}, "Reading Item Sources")
		Attune.ReadSources(function() requery(0, true) end)
	elseif Attune.items then
		panel.result = Attune.Query(filter)
		Attune.Sort(panel.result.items, filter.sort, filter.desc)
		tbl:SetItems(panel.result.items, "No Items Match These Filters", panel.keepScroll)
		panel.keepScroll = nil
	end
	status()
end

-- Queries on the next frame, or after a short pause while typing, so a burst of changes runs one query.
function requery(delay, keepScroll)
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

local function affixLabel()
	local text = textOf(AFFIX_CHOICES, filter.affix or false, nil)
	if not text then text = type(filter.affix) == "string" and filter.affix or "Any" end
	return "Affix: " .. text
end

local function syncControls()
	syncForgeColumn()
	Attune.SetAffixSortForge(filter.affixForge or 0)
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
	panel.sources:SetText("5+ Sources: " .. textOf(TRI, filter.sources or false, "Any"))
	panel.affix:SetText(affixLabel())
	for _, t in ipairs(panel.toggles) do
		local value = filter[t.key]
		local on
		if t.single then on = (value or 0) == t.value else on = bit.band(value or 0, t.value) ~= 0 end
		t.button:SetKind(on and "selected" or "secondary")
	end
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

-- A label and a row of joined buttons for one filter. Multi groups keep a bit mask in filter[key] (nil: any);
-- a single group keeps the chosen value, with 0 stored as nil. Returns the label and the last button.
local function toggleGroup(text, key, options, single)
	local fs = label(panel, text)
	local group = { fs }
	local prev
	for _, o in ipairs(options) do
		local b = S.Button(panel, o.text, "secondary", o.width, function()
			local value
			if single then
				value = o.value
			else
				value = bit.bxor(filter[key] or 0, o.value)
			end
			if key == "level" then filter.mode = Attune.ModeForLevel(filter.mode, value) end
			set(key, value ~= 0 and value or nil)
		end, o.tooltip)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("LEFT", fs, "RIGHT", GAP, 0) end
		panel.toggles[#panel.toggles + 1] = { button = b, key = key, value = o.value, single = single }
		group[#group + 1] = b
		prev = b
	end
	return fs, prev, group
end

local function openAffixPicker(button)
	local items = {}
	for _, c in ipairs(AFFIX_CHOICES) do items[#items + 1] = c end
	for _, name in ipairs(Attune.AffixNames()) do
		items[#items + 1] = { value = name, text = name,
			tooltip = "Items that can roll this affix and where you haven't attuned it yet at the Affix Forge level." }
	end
	SC.Picker.Open(button, {
		items = items, placeholder = "Search Affixes",
		isSelected = function(v) return v == (filter.affix or false) end,
		onPick = function(v) set("affix", v or nil) end,
	})
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
	{ key = "name", label = "Item", width = 251 },
	{ key = "slot", label = "Slot", width = 100 },
	{ key = "ilvl", label = "iLvl", width = 52, justify = "RIGHT", defaultDesc = true },
	{ key = "req", label = "Req", width = 48, justify = "RIGHT", defaultDesc = true },
	{ key = "sources", label = "Sources", width = 66, justify = "RIGHT", defaultDesc = true },
	{ key = "affixes", label = "Affixes Left", width = 84, justify = "RIGHT", defaultDesc = true },
	{ key = "forge", label = "Forge", width = 92, defaultDesc = true },
}

local function cell(item, key)
	if key == "name" then return item.name, qualityColor(item.quality)
	elseif key == "slot" then return Attune.SlotLabel(item.equipLoc), C.muted
	elseif key == "ilvl" then return tostring(item.ilvl)
	elseif key == "req" then return item.req > 0 and tostring(item.req) or "", C.muted
	elseif key == "sources" then
		local n = Attune.SourceCount(item)
		return n > 0 and tostring(n) or "", C.muted
	elseif key == "affixes" then
		local n = Attune.AffixesLeft(item, filter.affixForge or 0)
		return n and tostring(n) or "", n == 0 and C.good or C.text
	elseif key == "forge" then return forgeCell(item)
	end
end

local function create(parent, width, height)
	filter = SC.db.attunable
	filter.sort = filter.sort or "ilvl"
	if filter.desc == nil then filter.desc = true end
	panel = CreateFrame("Frame", nil, parent)
	panel.toggles = {}
	local x0, inner = PAD, width - 2 * PAD
	local function rowY(n) return -PAD - (n - 1) * (CONTROL_H + GAP) end

	-- row 1: search, mode, class, reset
	panel.name = S.Input(panel, "SynastriaCompanionAttuneName", 260, "Search Items", 60)
	panel.name:SetPoint("TOPLEFT", x0, rowY(1))
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
	reset:SetPoint("TOPRIGHT", -PAD, rowY(1))

	-- row 2: rarity, slot, yes/no filters, affix
	panel.rarity = S.Dropdown(panel, 120, function(v) set("rarity", v or nil) end)
	local rarities = { { value = false, text = "All" } }
	for _, r in ipairs(Attune.RARITIES) do rarities[#rarities + 1] = r end
	panel.rarity:SetOptions(rarities)
	panel.rarity:SetPoint("TOPLEFT", x0, rowY(2))

	panel.slot = S.Dropdown(panel, 130, function(v) set("slot", v or nil) end)
	local slots = { { value = false, text = "All" } }
	for _, s in ipairs(Attune.SLOTS) do slots[#slots + 1] = { value = s[1], text = s[2] } end
	panel.slot:SetOptions(slots)
	panel.slot:SetPoint("LEFT", panel.rarity, "RIGHT", GAP, 0)

	panel.mythic = triDropdown(panel, 100, "mythic")
	panel.mythic:SetPoint("LEFT", panel.slot, "RIGHT", GAP, 0)
	panel.sources = triDropdown(panel, 120, "sources")
	panel.sources:SetPoint("LEFT", panel.mythic, "RIGHT", GAP, 0)
	panel.sources.tooltipText = "Items with more than five places they come from."
	panel.affix = S.AddArrow(S.Button(panel, "Affix: Any", "secondary", 196, openAffixPicker,
		"Items with or without affixes, with affixes left to attune, or that can roll one affix you haven't attuned."))
	panel.affix:SetPoint("LEFT", panel.sources, "RIGHT", GAP, 0)

	-- row 3: attunement level, the forge level affixes are counted at
	local levelLabel, levelEnd = toggleGroup("Attunement", "level", LEVELS)
	levelLabel:SetPoint("TOPLEFT", x0, rowY(3) - 6)
	local forgeLabel = toggleGroup("Affix Forge", "affixForge", AFFIX_FORGES, true)
	forgeLabel:SetPoint("LEFT", levelEnd, "RIGHT", PAD, 0)

	-- row 4: bind, then the filters that need the game's loot data
	local bindLabel, bindEnd = toggleGroup("Bind", "bind", BINDS)
	bindLabel:SetPoint("TOPLEFT", x0, rowY(4) - 6)
	local kindLabel, kindEnd, kindGroup = toggleGroup("Source", "kind", KINDS)
	kindLabel:SetPoint("LEFT", bindEnd, "RIGHT", PAD, 0)
	local expLabel, _, expGroup = toggleGroup("Expansion", "exp", EXPANSIONS)
	expLabel:SetPoint("LEFT", kindEnd, "RIGHT", PAD, 0)
	panel.lootGroups = { kindGroup, expGroup }

	-- row 5: level ranges and zone
	local reqLabel = label(panel, "Req. Level")
	reqLabel:SetPoint("TOPLEFT", x0, rowY(5) - 6)
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
	local top = rowY(ROWS + 1)
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
		if Attune.scanning or Attune.sourcesReading then status() end
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
	local lootData = Attune.HasLootData()
	local zones = SC.ZonePicker.Available() and lootData
	setShown(panel.zone, zones)
	setShown(panel.zoneHere, zones)
	setShown(panel.zoneClear, zones)
	if not zones then filter.zone = nil end
	for _, group in ipairs(panel.lootGroups) do
		for _, region in ipairs(group) do setShown(region, lootData) end
	end
	if not lootData then filter.kind, filter.exp = nil, nil end
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
