local _, NS = ...
local SC = NS.SC

-- Attunable Items: the game's attune search with every result shown, live filters and sortable columns, plus an
-- Advanced drawer of filters the game's window doesn't have. Replaces the window the server opens with
-- OpenAttuneMgr.
local Attunable = {}
SC.AttunableUI = Attunable

local S = SC.Style
local C = S.colors
local Attune = SC.Attune
local ZoneInfo = SC.ZoneInfo
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, drawer, tbl
local filter
local QUERY_DELAY = 0.15
local ROWS = 3
local ROW_GAP = 6
local DRAWER_W = 240
local DRAWER_HEAD_H = 36
local SECTION_GAP = 14

local CLASSES = {
	{ 1, "WARRIOR" }, { 2, "PALADIN" }, { 3, "HUNTER" }, { 4, "ROGUE" }, { 5, "PRIEST" }, { 6, "DEATHKNIGHT" },
	{ 7, "SHAMAN" }, { 8, "MAGE" }, { 9, "WARLOCK" }, { 11, "DRUID" },
}
local TRI = { { value = false, text = "Any" }, { value = 1, text = "Yes" }, { value = -1, text = "No" } }

local LEVELS_ATTUNED = {
	{ value = Attune.NOT_ATTUNED, text = "Not Attuned", width = 84, tooltip = "Items you haven't attuned." },
	{ value = 2, text = "Attuned", width = 64, tooltip = "Items attuned, but not forged yet." },
}
local LEVELS_FORGED = {
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
local AFFIX_PICKS = {
	{ value = false, text = "Any Affix" },
	{ value = "left", text = "Affixes Left", tooltip = "Items with affixes you haven't attuned yet at the Affix Forge level." },
}
local ZONE_EXTRAS = {
	{ value = false, text = "Any Zone" },
	{ value = "here", text = "Current Zone", tooltip = "The zone you're in now." },
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
	return Attune.NeedsSources(Attune.Effective(filter)) and not Attune.sourcesRead
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
		panel.result = Attune.Query(Attune.Effective(filter))
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

-- A column that's hidden can't stay the sort; the sort falls back to item level.
local function syncColumn(key, shown)
	tbl:SetColumnShown(key, shown)
	if not shown and filter.sort == key then
		filter.sort, filter.desc = "ilvl", true
		tbl:SetSort(filter.sort, filter.desc)
	end
end

-- The drawer hangs off the window's right edge, so the window's screen clamp is widened to keep it on screen.
local function syncDrawer()
	local open = filter.advanced and true or false
	setShown(drawer, open)
	local window = SC.Window.Frame()
	if window then window:SetClampRectInsets(0, open and (DRAWER_W - 1) or 0, 0, 0) end
	panel.advanced:SetKind(open and "selected" or "secondary")
	local n = Attune.AdvancedCount(filter)
	panel.advanced:SetText((open and n > 0) and ("Advanced (" .. n .. ")") or "Advanced")
end

local function syncControls()
	-- the Forge column only means something in modes that list attuned items
	syncColumn("forge", Attune.ShowsAttuned(filter.mode))
	syncColumn("affixes", filter.advanced and true or false)
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
	panel.affix:SetText("Affix: " .. textOf(TRI, filter.affix or false, "Any"))
	panel.sources:SetText("5+ Sources: " .. textOf(TRI, filter.sources or false, "Any"))
	for _, key in ipairs({ "minReq", "maxReq", "minLvl", "maxLvl" }) do
		panel[key]:SetText(filter[key] and tostring(filter[key]) or "")
	end
	panel.zone:SetText(SC.ZonePicker.Name(filter.zone) or "Any Zone")

	drawer.affixPick:SetText(textOf(AFFIX_PICKS, filter.affixPick or false, filter.affixPick or "Any Affix"))
	-- a single-choice row's default (stored as nil) shows only in its text color, so the fully selected look is
	-- left for filters that actually narrow the list
	for _, t in ipairs(panel.toggles) do
		local value = filter[t.key]
		local on, isDefault
		if t.single then
			on = (value or 0) == t.value
			isDefault = on and value == nil
		else
			on = bit.band(value or 0, t.value) ~= 0
		end
		t.button:SetKind((on and not isDefault) and "selected" or "secondary")
		t.button:SetText(isDefault and S.Hex(C.heading, t.text) or t.text)
	end
	syncDrawer()
end

local function set(key, value)
	filter[key] = value
	syncControls()
	requery()
end

local function triDropdown(width, key, tooltip)
	local d = S.Dropdown(panel, width, function(v) set(key, v or nil) end)
	d:SetOptions(TRI)
	d.tooltipText = tooltip
	return d
end

local function numberBox(name, key, width, placeholder)
	local e = S.Input(panel, name, width, placeholder, 3)
	e:SetNumeric(true)
	e:SetJustifyH("CENTER")
	e.placeholder:SetJustifyH("CENTER")
	e.placeholder:SetTextColor(unpack(C.outline))
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

-- Labels are a shade dimmer than the controls, so they read as headings for them.
local function label(parent, text, width)
	local fs = S.Text(parent, "small", C.outline)
	fs:SetText(text)
	if width then
		fs:SetWidth(width)
		fs:SetJustifyH("LEFT")
	end
	return fs
end

-- Button widths that fill `area` exactly (joined buttons overlap by their 1px border). Each option's width is its
-- minimum; the narrow ones grow first, so the buttons come out as even as their labels allow.
local function fitWidths(options, area)
	local n = #options
	local avail = area + n - 1
	local wide, wideW, even = {}, 0, 0
	local changed = true
	while changed do
		changed = false
		local count = 0
		for i = 1, n do
			if not wide[i] then count = count + 1 end
		end
		even = math.floor((avail - wideW) / math.max(1, count))
		for i, o in ipairs(options) do
			if not wide[i] and o.width > even then
				wide[i], wideW, changed = true, wideW + o.width, true
			end
		end
	end
	local widths, used = {}, 0
	for i, o in ipairs(options) do
		widths[i] = wide[i] and o.width or even
		used = used + widths[i]
	end
	widths[n] = widths[n] + avail - used
	return widths
end

-- A row of joined buttons for one filter in the drawer, filling `area` pixels from (x, y). kind "multi" keeps a bit
-- mask in filter[key] (nil: any); "single" keeps the chosen value, with 0 stored as nil; "clearable" is single,
-- and clicking the chosen button again clears it. Returns its buttons.
local function buttonRow(key, options, kind, x, y, area)
	local group, prev = {}, nil
	for i, width in ipairs(fitWidths(options, area)) do
		local o = options[i]
		local b = S.Button(drawer, o.text, "secondary", width, function()
			local value
			if kind == "multi" then
				value = bit.bxor(filter[key] or 0, o.value)
			elseif kind == "clearable" and filter[key] == o.value then
				value = 0
			else
				value = o.value
			end
			if key == "level" then filter.mode = Attune.ModeForLevel(filter.mode, value) end
			set(key, value ~= 0 and value or nil)
		end, o.tooltip)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("TOPLEFT", drawer, "TOPLEFT", x, y) end
		panel.toggles[#panel.toggles + 1] = { button = b, key = key, value = o.value, text = o.text,
			single = kind ~= "multi" }
		group[#group + 1] = b
		prev = b
	end
	return group
end

local function openAffixPicker(button)
	local items = {}
	for _, c in ipairs(AFFIX_PICKS) do items[#items + 1] = c end
	for _, name in ipairs(Attune.AffixNames()) do
		items[#items + 1] = { value = name, text = name,
			tooltip = "Items that can roll this affix and where you haven't attuned it yet at the Affix Forge level." }
	end
	SC.Picker.Open(button, {
		items = items, placeholder = "Search Affixes",
		isSelected = function(v) return v == (filter.affixPick or false) end,
		onPick = function(v) set("affixPick", v or nil) end,
	})
end

local function openZonePicker(button)
	SC.ZonePicker.Open(button, function(v)
		if v == "here" then
			local index = SC.ZonePicker.CurrentIndex()
			if index then set("zone", index) else panel.status:SetText(S.Hex(C.bad, "Couldn't Tell Which Zone You're In")) end
		else
			set("zone", v or nil)
		end
	end, filter.zone or false, ZONE_EXTRAS)
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
	{ key = "name", label = "Item", width = 251, stretch = true },
	{ key = "slot", label = "Slot", width = 100 },
	{ key = "ilvl", label = "iLvl", width = 52, defaultDesc = true },
	{ key = "req", label = "Req", width = 48, defaultDesc = true },
	{ key = "sources", label = "Sources", width = 66, defaultDesc = true },
	{ key = "affixes", label = "Affixes Left", width = 84, defaultDesc = true },
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
		-- a faint dash for items that can't roll affixes, so a blank never looks like a missing count
		local n = Attune.AffixesLeft(item, filter.affixForge or 0)
		if n then return tostring(n), n == 0 and C.good or C.text end
		return "-", C.outline
	elseif key == "forge" then return forgeCell(item)
	end
end

-- The Advanced drawer: one section per filter, each a dim heading over controls the drawer's full width.
local function createDrawer(window)
	drawer = CreateFrame("Frame", nil, panel)
	drawer:SetWidth(DRAWER_W)
	drawer:SetPoint("TOPLEFT", window, "TOPRIGHT", -1, 0)
	drawer:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", -1, 0)
	drawer:EnableMouse(true)
	S.Panel(drawer, C.window, C.border)
	drawer:Hide()
	panel.drawer = drawer

	local head = CreateFrame("Frame", nil, drawer)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(DRAWER_HEAD_H)
	S.Rule(head, "BOTTOM")
	local title = S.Text(head, "normal")
	title:SetPoint("LEFT", PAD, 0)
	title:SetText("Advanced Filters")

	local w = DRAWER_W - 2 * PAD
	local y = -DRAWER_HEAD_H - PAD
	local function section(text)
		S.SectionHeading(drawer, text, PAD, y, PAD)
		y = y - 20
	end
	local function row(key, options, kind)
		local group = buttonRow(key, options, kind, PAD, y, w)
		y = y - CONTROL_H - 4
		return group
	end
	local function endSection() y = y - SECTION_GAP + 4 end

	section("Affix")
	drawer.affixPick = S.AddArrow(S.Button(drawer, "Any Affix", "secondary", w, openAffixPicker,
		"Items with affixes left to attune, or that can roll one affix you haven't attuned."))
	drawer.affixPick:SetPoint("TOPLEFT", PAD, y)
	y = y - CONTROL_H - 4
	endSection()

	section("Affix Forge")
	row("affixForge", AFFIX_FORGES, "single")
	endSection()

	section("Attunement")
	row("level", LEVELS_ATTUNED, "multi")
	row("level", LEVELS_FORGED, "multi")
	endSection()

	section("Bind")
	row("bind", BINDS, "clearable")
	endSection()

	-- the filters that need the game's loot data
	local lootGroups = {}
	local function lootSection(text, key, options)
		local heading, rule = S.SectionHeading(drawer, text, PAD, y, PAD)
		y = y - 20
		local group = row(key, options, "multi")
		group[#group + 1], group[#group + 2] = heading, rule
		lootGroups[#lootGroups + 1] = group
		endSection()
	end
	lootSection("Source", "kind", KINDS)
	lootSection("Expansion", "exp", EXPANSIONS)
	drawer.lootGroups = lootGroups
end

local function create(parent, width, height)
	filter = SC.db.attunable
	filter.sort = filter.sort or "ilvl"
	if filter.desc == nil then filter.desc = true end
	panel = CreateFrame("Frame", nil, parent)
	panel.toggles = {}
	local x0, inner = PAD, width - 2 * PAD
	local function rowY(n) return -PAD - (n - 1) * (CONTROL_H + ROW_GAP) end
	-- the filters sit on four equal columns
	local colW = math.floor((inner - 3 * GAP) / 4)
	local function colX(n) return x0 + (n - 1) * (colW + GAP) end
	panel.colW = colW

	-- row 1: search (two columns unless the class dropdown needs one), mode, class; Advanced and Reset on the right
	panel.name = S.Input(panel, "SynastriaCompanionAttuneName", 2 * colW + GAP, "Search Items", 60)
	panel.name:SetPoint("TOPLEFT", x0, rowY(1))
	panel.name:HookScript("OnTextChanged", function(self, user)
		if user then
			filter.name = self:GetText()
			requery(QUERY_DELAY)
		end
	end)
	panel.name:SetScript("OnEnterPressed", panel.name.ClearFocus)

	panel.mode = S.Dropdown(panel, colW, function(v) set("mode", v) end)
	panel.mode:SetOptions(Attune.MODES)
	panel.mode:SetPoint("LEFT", panel.name, "RIGHT", GAP, 0)

	panel.class = S.Dropdown(panel, colW, function(v) set("class", v or nil) end)
	panel.class:SetPoint("LEFT", panel.mode, "RIGHT", GAP, 0)

	local reset = S.Button(panel, "Reset", "ghost", 56, function()
		for k in pairs(filter) do
			if k ~= "sort" and k ~= "desc" and k ~= "advanced" then filter[k] = nil end
		end
		syncControls()
		requery()
	end, "Clear every filter and the search, advanced ones too.")
	reset:SetPoint("TOPRIGHT", -PAD, rowY(1))
	panel.advanced = S.Button(panel, "Advanced", "secondary", colW - 56 - 4, function()
		S.CloseMenus()
		filter.advanced = not filter.advanced or nil
		syncControls()
		requery(0, true)
	end, "Filters the game's window doesn't have: affixes, forge levels, bind, source and expansion. They apply only while this is on.")
	panel.advanced:SetPoint("RIGHT", reset, "LEFT", -4, 0)

	-- row 2: the game's dropdown filters
	panel.rarity = S.Dropdown(panel, colW, function(v) set("rarity", v or nil) end)
	local rarities = { { value = false, text = "All" } }
	for _, r in ipairs(Attune.RARITIES) do rarities[#rarities + 1] = r end
	panel.rarity:SetOptions(rarities)
	panel.rarity:SetPoint("TOPLEFT", colX(1), rowY(2))

	panel.slot = S.Dropdown(panel, colW, function(v) set("slot", v or nil) end)
	local slots = { { value = false, text = "All" } }
	for _, s in ipairs(Attune.SLOTS) do slots[#slots + 1] = { value = s[1], text = s[2] } end
	panel.slot:SetOptions(slots)
	panel.slot:SetPoint("TOPLEFT", colX(2), rowY(2))

	panel.mythic = triDropdown(colW, "mythic")
	panel.mythic:SetPoint("TOPLEFT", colX(3), rowY(2))
	panel.affix = triDropdown(colW, "affix", "Items with or without a random affix.")
	panel.affix:SetPoint("TOPLEFT", colX(4), rowY(2))

	-- row 3: sources, the two level ranges, zone
	panel.sources = triDropdown(colW, "sources", "Items with more than five places they come from.")
	panel.sources:SetPoint("TOPLEFT", colX(1), rowY(3))

	local LABEL_W, DASH_W = 28, 12
	local boxW = math.floor((colW - LABEL_W - DASH_W) / 2)
	local function range(col, text, minKey, maxKey, minName, maxName)
		local fs = label(panel, text, LABEL_W)
		fs:SetPoint("LEFT", panel, "TOPLEFT", colX(col), rowY(3) - CONTROL_H / 2)
		panel[minKey] = numberBox(minName, minKey, boxW, "Min")
		panel[minKey]:SetPoint("TOPLEFT", colX(col) + LABEL_W, rowY(3))
		local dash = label(panel, "-", DASH_W)
		dash:SetJustifyH("CENTER")
		dash:SetPoint("LEFT", panel[minKey], "RIGHT", 0, 0)
		panel[maxKey] = numberBox(maxName, maxKey, colW - LABEL_W - DASH_W - boxW, "Max")
		panel[maxKey]:SetPoint("LEFT", dash, "RIGHT", 0, 0)
	end
	range(2, "Req", "minReq", "maxReq", "SynastriaCompanionAttuneMinReq", "SynastriaCompanionAttuneMaxReq")
	range(3, "iLvl", "minLvl", "maxLvl", "SynastriaCompanionAttuneMinLvl", "SynastriaCompanionAttuneMaxLvl")

	panel.zone = S.AddArrow(S.Button(panel, "Any Zone", "secondary", colW, openZonePicker,
		"Only items that come from one zone, or the one you're in."))
	panel.zone:SetPoint("TOPLEFT", colX(4), rowY(3))

	-- results
	local top = rowY(ROWS) - CONTROL_H - GAP
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

	createDrawer(parent:GetParent())

	panel:SetScript("OnUpdate", function()
		if Attune.scanning or Attune.sourcesReading then status() end
		if panel.pending and GetTime() >= panel.pending then query() end
	end)
	panel:SetScript("OnHide", function()
		panel.pending = nil
		local window = SC.Window.Frame()
		if window then window:SetClampRectInsets(0, 0, 0, 0) end
	end)

	Attune.onChange = function()
		if panel:IsVisible() then requery(0.5, true) else panel.stale = true end
	end
	return panel
end

local function show()
	local multi = CMCGetClassCount and CMCGetClassCount() >= 2
	setShown(panel.class, multi)
	panel.name:SetWidth(multi and panel.colW or 2 * panel.colW + GAP)
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
	if not zones then filter.zone = nil end
	for _, group in ipairs(drawer.lootGroups) do
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
