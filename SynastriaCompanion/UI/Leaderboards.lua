local _, NS = ...
local SC = NS.SC

-- Leaderboards: every board in one list (general boards, then dungeons and raids by expansion, then prestiged
-- runs), with the selected board's ranks beside it and your own place highlighted. Replaces the window the game
-- opens with OpenLeaderboards.
local LBUI = {}
SC.LeaderboardsUI = LBUI

local S = SC.Style
local C = S.colors
local LB = SC.Leaderboards
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, rail, tbl, state
local RAIL_W = 180

local function boardName(t, arg)
	local name, group
	for _, section in ipairs(LB.Tree()) do
		for _, e in ipairs(section.entries) do
			if e.boards then
				for _, b in ipairs(e.boards) do
					if b.type == t and b.arg == arg then name, group = b.name, section.label .. ": " .. e.name end
				end
			elseif e.type == t and e.arg == arg then
				name = e.name
			end
		end
	end
	return name, group
end

local function railEntries()
	local entries = {}
	for _, section in ipairs(LB.Tree()) do
		entries[#entries + 1] = { header = true, label = section.label }
		for _, e in ipairs(section.entries) do
			if e.boards then
				local open = state.open == e.arg
				entries[#entries + 1] = { group = e.arg, label = (open and "-  " or "+  ") .. e.name }
				if open then
					for _, b in ipairs(e.boards) do
						entries[#entries + 1] = { type = b.type, arg = b.arg, label = "     " .. b.name }
					end
				end
			else
				entries[#entries + 1] = { type = e.type, arg = e.arg, label = e.name }
			end
		end
	end
	return entries
end

local function centerOnSelf(rows)
	for i, r in ipairs(rows) do
		if r.self then
			tbl:ScrollTo(i - math.floor(tbl.visible / 2))
			return
		end
	end
end

local function render(scrollToSelf)
	rail:SetItems(railEntries(), "Leaderboards Aren't Available", true)
	local t, arg = state.type, state.arg
	if t then
		local name, group = boardName(t, arg)
		panel.title:SetText(name or "Leaderboard")
		panel.sub:SetText(group or "General")
		local data = LB.Data(t, arg)
		local rows, extras = LB.Rows(data)
		panel.vtype = data and data.vtype
		local notes = {}
		for _, e in ipairs(extras) do
			local label = (e.name or e.acc or ""):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
			notes[#notes + 1] = S.Hex(C.muted, label .. ": ") .. LB.ValueText(e.value, panel.vtype)
		end
		panel.notes:SetText(table.concat(notes, "    "))
		-- only some boards (the dungeon and raid runs) send dates; the others get the wider table
		local dated = false
		for _, r in ipairs(rows) do
			if r.ts and r.ts ~= "" then dated = true end
		end
		tbl = dated and panel.dated or panel.plain
		panel.table = tbl
		panel.plain.frame:Hide()
		panel.dated.frame:Hide()
		tbl.frame:Show()
		tbl:SetItems(rows, data and "Nobody Is Ranked Yet" or "Waiting for the Server...", not scrollToSelf)
		if scrollToSelf then centerOnSelf(rows) end
		local mine
		for _, r in ipairs(rows) do
			if r.self and r.place then mine = r.place end
		end
		local count = 0
		for _, r in ipairs(rows) do if r.place then count = count + 1 end end
		panel.status:SetText(data and (S.Count(count, "Ranked Player") .. (mine and ("  " .. S.Hex(C.muted, "|  Your Place: ") .. mine) or ""))
			or S.Hex(C.muted, "Asked the Server"))
		panel.refresh:Show()
	else
		panel.title:SetText("Leaderboards")
		panel.sub:SetText("Pick a board on the left.")
		panel.notes:SetText("")
		panel.dated.frame:Hide()
		tbl = panel.plain
		panel.table = tbl
		tbl.frame:Show()
		tbl:SetItems({}, "Pick a Board")
		panel.status:SetText("")
		panel.refresh:Hide()
	end
end

local function selectBoard(t, arg)
	S.Dismiss()
	state.type, state.arg = t, arg
	if arg ~= 0 then state.open = arg end
	LB.Request(t, arg)
	render(true)
end

local PLAIN_COLUMNS = {
	{ key = "place", label = "#", width = 46, justify = "RIGHT" },
	{ key = "name", label = "Player", width = 330 },
	{ key = "value", label = "Score", width = 140, justify = "RIGHT" },
}
local DATED_COLUMNS = {
	{ key = "place", label = "#", width = 46, justify = "RIGHT" },
	{ key = "name", label = "Player", width = 260 },
	{ key = "value", label = "Score", width = 110, justify = "RIGHT" },
	{ key = "ts", label = "Date", width = 100 },
}

-- A name of "!" is a character the server no longer knows (usually deleted); the account shows in its class color.
local function charName(row)
	return row.name ~= "!" and row.name or nil
end

local function tooltip(tt, row)
	local name = charName(row)
	tt:AddLine(name or row.acc or "?", 1, 1, 1)
	if row.acc and row.acc ~= name then tt:AddLine("Account: " .. row.acc, unpack(C.muted)) end
	tt:AddDoubleLine("Score", LB.ValueText(row.value, panel.vtype), 1, 1, 1, 1, 1, 1)
	if row.place then tt:AddDoubleLine("Place", tostring(row.place), 1, 1, 1, 1, 1, 1) end
	if row.ts and row.ts ~= "" then tt:AddDoubleLine("Date", row.ts, 1, 1, 1, 1, 1, 1) end
end

local function cell(row, key)
	if key == "place" then return row.place and (row.place .. ".") or "", C.muted
	elseif key == "name" then
		local name = charName(row)
		local text
		if name and name ~= row.acc then
			text = LB.ClassColor(row.cl) .. name .. "|r" .. (row.acc and S.Hex(C.muted, "  " .. row.acc) or "")
		elseif name then
			text = LB.ClassColor(row.cl) .. name .. "|r"
		else
			text = LB.ClassColor(row.cl) .. (row.acc or "?") .. "|r"
		end
		return text
	elseif key == "value" then return LB.ValueText(row.value, panel.vtype), row.self and C.heading or C.text
	elseif key == "ts" then return row.ts or "", C.muted
	end
end

local function create(parent, width, height)
	SC.db.leaderboards = SC.db.leaderboards or {}
	state = SC.db.leaderboards
	panel = CreateFrame("Frame", nil, parent)

	local top = -PAD - CONTROL_H - GAP - 12
	local footerH = PAD + 14 + PAD
	local listH = height - PAD - footerH

	rail = SC.Table.New(panel, "SynastriaCompanionLBoards", RAIL_W, listH, {
		columns = { { key = "label", label = "Board", width = RAIL_W - 2, sortable = false } },
		rowH = 18,
		header = function(e) return e.header and e.label end,
		cell = function(e)
			local on = e.type and e.type == state.type and e.arg == state.arg
			return e.label, on and C.heading or C.text
		end,
		onClick = function(e)
			if e.group then
				state.open = state.open ~= e.group and e.group or nil
				render()
			elseif e.type then
				selectBoard(e.type, e.arg)
			end
		end,
	})
	rail.isSelected = function(e) return e.type ~= nil and e.type == state.type and e.arg == state.arg end
	rail.frame:SetPoint("TOPLEFT", PAD, -PAD)

	local x = PAD + RAIL_W + GAP
	panel.title = S.Text(panel, "large")
	panel.title:SetPoint("TOPLEFT", x, -PAD - 2)
	panel.sub = S.Text(panel, "small", C.muted)
	panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
	panel.refresh = S.Button(panel, "Refresh", "ghost", 70, function()
		if state.type then
			LB.Request(state.type, state.arg)
			render()
		end
	end, "Ask the server for this board again. It answers at most once a minute per board.")
	panel.refresh:SetPoint("TOPRIGHT", -PAD, -PAD)
	-- the board's notes, like the times a speed buff needs, under Refresh on the subtitle's line
	panel.notes = S.Text(panel, "small")
	panel.notes:SetJustifyH("RIGHT")
	panel.notes:SetPoint("BOTTOMRIGHT", panel.refresh, "BOTTOMRIGHT", -8, -16)

	for key, columns in pairs({ plain = PLAIN_COLUMNS, dated = DATED_COLUMNS }) do
		local t = SC.Table.New(panel, nil, width - x - PAD, height + top - footerH, {
			columns = columns, rowH = 20, cell = cell, tooltip = tooltip,
		})
		t.isSelected = function(row) return row.self end
		t.frame:SetPoint("TOPLEFT", x, top)
		panel[key] = t
	end
	tbl = panel.plain
	panel.dated.frame:Hide()
	panel.table, panel.rail = tbl, rail

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("BOTTOMLEFT", x, PAD)
	local hint = S.Text(panel, "small", C.muted)
	hint:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	hint:SetText("Boards Update Every 8 Hours")

	LB.onChange = function(t, arg)
		if panel:IsVisible() and t == state.type and arg == state.arg then render(true) end
	end
	return panel
end

local function show()
	if state.type then LB.Request(state.type, state.arg) end
	render(true)
end

local function original(name, ...)
	local fn = SC.Hooks.originals[name]
	if fn then return fn(...) end
end

SC.Window.AddScreen({
	key = "leaderboards",
	label = "Leaderboards",
	create = create,
	show = show,
	hook = {
		open = "OpenLeaderboards", close = "CloseLeaderboards", frame = "LBoardFrame",
		extra = {
			OpenLeaderboardsTo = function(t, arg)
				SC.Window.Open("leaderboards")
				if t and arg and t > 0 and arg > 0 then selectBoard(t, arg) end
			end,
			-- the server's answers; the game's window keeps them too
			LBoardCallback = function(t, arg, data)
				LB.Received(t, arg, data)
				original("LBoardCallback", t, arg, data)
			end,
			ResetLBCache = function(silent)
				LB.Reset()
				original("ResetLBCache", silent)
			end,
		},
	},
})
