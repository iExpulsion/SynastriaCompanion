local _, NS = ...
local SC = NS.SC

-- Item Database: search items, see where one comes from, and see what a creature or object drops, with Back
-- going through everything opened since the search. Replaces the window the game opens with OpenLootDb.
local LootUI = {}
SC.LootDatabaseUI = LootUI

local S = SC.Style
local C = S.colors
local LootDB = SC.LootDB
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel
local stack = {}
local SEARCH_DELAY = 0.25
local HEADER_H = 36

local qualityColor = S.QualityColor

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function attuneStatus(id)
	local text, color = "", C.muted
	if LootDB.IsAttuned(id) then
		text, color = "Attuned", C.good
	elseif LootDB.IsAttunable(id) then
		text, color = "Attunable", C.warn
	end
	return text, color
end

local function sortRows(rows, key, desc, getters)
	local get = getters[key]
	if get then
		local values = {}
		for _, r in ipairs(rows) do values[r] = get(r) end
		table.sort(rows, function(a, b)
			local va, vb = values[a], values[b]
			if va == vb then return (a.name or "") < (b.name or "") end
			if desc then return va > vb end
			return va < vb
		end)
	end
end

local ITEM_SORT = {
	name = function(r) return r.name:upper() end,
	kind = function(r) return r.kind end,
	ilvl = function(r) return r.ilvl end,
	status = function(r) return LootDB.IsAttuned(r.id) and 2 or LootDB.IsAttunable(r.id) and 1 or 0 end,
	type = function(r) return LootDB.TypeLabel(r.srcType) end,
	chance = function(r) return r.chance end,
	per = function(r) return r.per end,
}
local SOURCE_SORT = {
	name = function(r) return r.name:upper() end,
	type = function(r) return LootDB.TypeLabel(r.srcType) end,
	zone = function(r) return r.zone end,
	chance = function(r) return r.chance end,
	per = function(r) return r.per end,
}

local function top()
	return stack[#stack]
end

-- Views -------------------------------------------------------------------------------------------------------

local render

local function push(view)
	S.Dismiss()
	stack[#stack + 1] = view
	render()
end

local function openItem(id)
	push({ kind = "item", id = id })
end

local function openLoot(objType, objId, name, zone)
	push({ kind = "loot", objType = objType, objId = objId, name = name, zone = zone })
end

local function back()
	S.Dismiss()
	if #stack > 1 then stack[#stack] = nil end
	render()
end

local function itemClick(row, button)
	if IsModifiedClick() then
		HandleModifiedItemClick(row.link)
	elseif button == "LeftButton" then
		openItem(row.id)
	end
end

local function sourceClick(source, button)
	local t = LootDB.TYPES[source.srcType] or {}
	if button == "RightButton" then
		if LootDB.CanTrack(source) then LootDB.Track(source) end
	elseif t.item then
		openItem(source.objId)
	elseif t.loot and LootDB.HasDrops(t.loot, source.objId) then
		openLoot(t.loot, source.objId, source.name, source.zone)
	elseif LootDB.CanTrack(source) then
		LootDB.Track(source)
	end
end

local function sourceTooltip(tt, s)
	local t = LootDB.TYPES[s.srcType] or {}
	tt:AddLine(s.name, 1, 1, 1)
	tt:AddLine(LootDB.TypeLabel(s.srcType) .. (s.faction and (" (" .. s.faction .. ")") or ""), unpack(C.muted))
	if s.zone then tt:AddLine(s.zone, unpack(C.muted)) end
	if s.chance and s.chance <= 100.5 and s.srcType ~= 2 and s.srcType ~= 9 then
		tt:AddDoubleLine("Chance", LootDB.ChanceText(s.chance), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine("Per 1000", LootDB.PerText(s.per), 1, 1, 1, 1, 1, 1)
	end
	if s.spawns and s.spawns > 0 then tt:AddDoubleLine("Spawned", LootDB.PerText(s.spawns), 1, 1, 1, 1, 1, 1) end
	if t.item then
		tt:AddLine("Click: Open Item", unpack(C.heading))
	elseif t.loot and LootDB.HasDrops(t.loot, s.objId) then
		tt:AddLine("Click: Show Its Loot", unpack(C.heading))
	end
	if LootDB.CanTrack(s) then tt:AddLine(t.loot and "Right-Click: Track on Map" or "Click: Track on Map", unpack(C.heading)) end
end

-- Builders ----------------------------------------------------------------------------------------------------

local SEARCH_COLUMNS = {
	{ key = "name", label = "Item", width = 360 },
	{ key = "kind", label = "Type", width = 160 },
	{ key = "ilvl", label = "iLvl", width = 60, justify = "RIGHT", defaultDesc = true },
	{ key = "status", label = "Status", width = 113, defaultDesc = true },
}
local SOURCE_COLUMNS = {
	{ key = "name", label = "Source", width = 236 },
	{ key = "type", label = "Type", width = 110 },
	{ key = "zone", label = "Zone", width = 177 },
	{ key = "chance", label = "Chance", width = 80, justify = "RIGHT", defaultDesc = true },
	{ key = "per", label = "Per 1000", width = 90, justify = "RIGHT", defaultDesc = true },
}
local LOOT_COLUMNS = {
	{ key = "name", label = "Item", width = 300 },
	{ key = "type", label = "Type", width = 120 },
	{ key = "chance", label = "Chance", width = 80, justify = "RIGHT", defaultDesc = true },
	{ key = "per", label = "Per 1000", width = 90, justify = "RIGHT", defaultDesc = true },
	{ key = "status", label = "Status", width = 103, defaultDesc = true },
}

local function itemCell(row, key)
	if key == "name" then return row.name, qualityColor(row.quality)
	elseif key == "kind" then return row.kind, C.muted
	elseif key == "ilvl" then return row.ilvl > 0 and tostring(row.ilvl) or "", C.muted
	elseif key == "status" then return attuneStatus(row.id)
	elseif key == "type" then return LootDB.TypeLabel(row.srcType), C.muted
	elseif key == "chance" then return LootDB.ChanceText(row.chance)
	elseif key == "per" then return LootDB.PerText(row.per), C.muted
	end
end

local function sourceCell(s, key)
	if key == "name" then
		local t = LootDB.TYPES[s.srcType] or {}
		return s.name .. (s.faction and (" (" .. s.faction .. ")") or ""), (t.loot or t.item) and C.text or C.muted
	elseif key == "type" then return LootDB.TypeLabel(s.srcType), C.muted
	elseif key == "zone" then return s.zone, C.muted
	elseif key == "chance" then
		return (s.srcType == 2 or s.srcType == 9) and "" or LootDB.ChanceText(s.chance)
	elseif key == "per" then
		return (s.srcType == 2 or s.srcType == 9) and "" or LootDB.PerText(s.per), C.muted
	end
end

local function newTable(name, columns, cell, onClick, tooltip, getters, sortKey, height, icons)
	local tbl
	tbl = SC.Table.New(panel, name, panel.tableW, height, {
		columns = columns, rowH = 20, icons = icons, cell = cell, icon = function(r) return r.icon end,
		tooltip = tooltip, onClick = onClick,
		onSort = function(key, desc)
			tbl.sortKey, tbl.sortDesc = key, desc
			sortRows(tbl.items, key, desc, getters)
			tbl:SetItems(tbl.items, tbl.emptyText, true)
		end,
	})
	tbl.sortKey, tbl.sortDesc = sortKey, sortKey ~= "name"
	tbl.getters = getters
	tbl:SetSort(tbl.sortKey, tbl.sortDesc)
	return tbl
end

local function fill(tbl, rows, emptyText)
	tbl.emptyText = emptyText
	sortRows(rows, tbl.sortKey, tbl.sortDesc, tbl.getters)
	tbl:SetItems(rows, emptyText)
end

local function runSearch()
	panel.pending = nil
	local text = panel.search:GetText() or ""
	local available = LootDB.Available()
	local rows = available and LootDB.Search(text) or {}
	fill(panel.results, rows, not available and "The Game's Loot Data Isn't Loaded"
		or text == "" and "Type an Item Name to Search" or "No Items Match")
	panel.status:SetText(text == "" and "" or S.Count(#rows, "Item"))
end

local function showHeader(icon, title, titleColor, sub)
	panel.headIcon.tex:SetTexture(icon)
	setShown(panel.headIcon, icon ~= nil)
	panel.headTitle:ClearAllPoints()
	panel.headTitle:SetPoint("TOPLEFT", panel.back, "BOTTOMLEFT", icon and (HEADER_H + GAP) or 0, -GAP - 2)
	panel.headTitle:SetText(title or "")
	panel.headTitle:SetTextColor(unpack(titleColor or C.text))
	panel.headSub:SetText(sub or "")
end

function render()
	local view = top()
	panel.back:SetEnabled(#stack > 1)
	setShown(panel.search, view.kind == "search")
	for _, t in ipairs({ panel.results, panel.sources, panel.loot }) do t:Hide() end
	if view.kind == "search" then
		showHeader(nil, "", C.text, "")
		panel.results:Show()
		runSearch()
	elseif view.kind == "item" then
		local item = LootDB.Item(view.id)
		panel.headIcon.link = item.link
		local rows = LootDB.Sources(view.id)
		local status = attuneStatus(view.id)
		showHeader(item.icon, item.name, qualityColor(item.quality),
			S.Count(#rows, "Source") .. (status ~= "" and ("  |  " .. status) or ""))
		panel.sources:Show()
		fill(panel.sources, rows, "Nobody Knows Where This Comes From")
		panel.status:SetText("")
	else
		local rows = LootDB.Drops(view.objType, view.objId)
		if panel.attunableOnly.on then
			local kept = {}
			for _, r in ipairs(rows) do
				if LootDB.IsAttunable(r.id) and not LootDB.IsAttuned(r.id) then kept[#kept + 1] = r end
			end
			rows = kept
		end
		showHeader(nil, view.name or "Unknown", C.text, (view.zone and (view.zone .. "  |  ") or "") .. S.Count(#rows, "Item"))
		panel.loot:Show()
		fill(panel.loot, rows, panel.attunableOnly.on and "Nothing Left to Attune Here" or "No Known Loot")
		panel.status:SetText("")
	end
	setShown(panel.attunableOnly, view.kind == "loot")
	setShown(panel.attunableLabel, view.kind == "loot")
	panel.hint:SetText(view.kind == "item" and "Click: Open or Show Loot  |  Right-Click: Track on Map"
		or "Click: Where It Comes From  |  Shift-Click: Link")
end

local function viewTarget()
	local id = LootDB.UnitNpcId("target")
	if id and LootDB.HasDrops(0, id) then
		openLoot(0, id, UnitName("target"), GetZoneText and GetZoneText() or nil)
	else
		panel.status:SetText(S.Hex(C.bad, id and "No Known Loot for Your Target" or "Target a Creature First"))
	end
end

local function create(parent, width, height)
	panel = CreateFrame("Frame", nil, parent)
	panel.tableW = width - 2 * PAD

	panel.back = S.Button(panel, "Back", "secondary", 64, back, "Go back to what you looked at before.")
	panel.back:SetPoint("TOPLEFT", PAD, -PAD)
	function panel.back:SetEnabled(on) if on then self:Enable() else self:Disable() end end

	panel.search = S.Input(panel, "SynastriaCompanionLootSearch", 260, "Search Items", 60)
	panel.search:SetPoint("LEFT", panel.back, "RIGHT", GAP, 0)
	panel.search:HookScript("OnTextChanged", function(_, user)
		if user then panel.pending = GetTime() + SEARCH_DELAY end
	end)
	panel.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		runSearch()
	end)

	local options = S.Button(panel, "Options", "ghost", 70, function()
		if InterfaceOptionsFrame_OpenToCategory then
			InterfaceOptionsFrame_OpenToCategory("[Syn] Loot DB")
			InterfaceOptionsFrame_OpenToCategory("[Syn] Loot DB")
		end
	end, "The game's Loot Database options: Alt-click to open items here, and the source lines in tooltips.")
	options:SetPoint("TOPRIGHT", -PAD, -PAD)
	local target = S.Button(panel, "Target's Loot", "secondary", 104, viewTarget, "Show what your target drops.")
	target:SetPoint("RIGHT", options, "LEFT", -GAP, 0)

	panel.headIcon = CreateFrame("Button", nil, panel)
	panel.headIcon:SetSize(HEADER_H, HEADER_H)
	panel.headIcon:SetPoint("TOPLEFT", panel.back, "BOTTOMLEFT", 0, -GAP)
	panel.headIcon.tex = panel.headIcon:CreateTexture(nil, "ARTWORK")
	panel.headIcon.tex:SetAllPoints()
	panel.headIcon:SetScript("OnEnter", function(self)
		if self.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:Show()
		end
	end)
	panel.headIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.headIcon:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
	end)
	panel.headTitle = S.Text(panel, "large")
	panel.headSub = S.Text(panel, "small", C.muted)
	panel.headSub:SetPoint("TOPLEFT", panel.headTitle, "BOTTOMLEFT", 0, -3)

	panel.attunableOnly = S.Check(panel, 14, function(self)
		self:SetChecked(not self.on)
		render()
	end)
	panel.attunableOnly:SetPoint("TOPRIGHT", -PAD - 110, -PAD - CONTROL_H - GAP - 10)
	panel.attunableLabel = S.Text(panel, "small")
	panel.attunableLabel:SetPoint("LEFT", panel.attunableOnly, "RIGHT", 6, 0)
	panel.attunableLabel:SetText("Still to Attune")

	-- the search has no header, so its table starts right under the search row
	local tableTop = -PAD - CONTROL_H - GAP - HEADER_H - GAP
	local searchTop = -PAD - CONTROL_H - GAP
	local footerH = PAD + 14 + PAD
	local tableH = height + tableTop - footerH
	panel.results = newTable("SynastriaCompanionLootResults", SEARCH_COLUMNS, itemCell, itemClick,
		function(tt, r) if r.link then tt:SetHyperlink(r.link) end end, ITEM_SORT, "name", height + searchTop - footerH, true)
	panel.sources = newTable("SynastriaCompanionLootSources", SOURCE_COLUMNS, sourceCell, sourceClick,
		sourceTooltip, SOURCE_SORT, "chance", tableH, false)
	panel.loot = newTable("SynastriaCompanionLootDrops", LOOT_COLUMNS, itemCell, itemClick,
		function(tt, r) if r.link then tt:SetHyperlink(r.link) end end, ITEM_SORT, "chance", tableH, true)
	panel.results.frame:SetPoint("TOPLEFT", PAD, searchTop)
	for _, t in ipairs({ panel.sources, panel.loot }) do t.frame:SetPoint("TOPLEFT", PAD, tableTop) end

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("BOTTOMLEFT", PAD, PAD)
	panel.hint = S.Text(panel, "small", C.muted)
	panel.hint:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	panel:SetScript("OnUpdate", function()
		if panel.pending and GetTime() >= panel.pending then runSearch() end
	end)
	stack = { { kind = "search" } }
	return panel
end

-- Opened from the sidebar it keeps its place; opened by the game for an item it shows that item, with Back going
-- to the search.
local function show(_, item)
	local id = LootDB.ResolveItem(item)
	if id then
		local view = top()
		if not (view.kind == "item" and view.id == id) then
			if not panel.opened then stack = { { kind = "search" } } end
			stack[#stack + 1] = { kind = "item", id = id }
		end
	end
	panel.opened = true
	render()
end

SC.Window.AddScreen({
	key = "lootdb",
	label = "Item Database",
	create = create,
	show = show,
	hook = { open = "OpenLootDb", close = "CloseLootDb", frame = "LootDBFrame" },
})
