local _, NS = ...
local SC = NS.SC

-- Leaderboards: the boards the game lists (LBoardData), asking the server for one, and its answers, which arrive
-- through LBoardCallback. Boards are (type, arg) pairs: arg 0 is a general board, type 0 a group of boards that
-- share its arg.
local LB = { cache = {} }
SC.Leaderboards = LB

local COOLDOWN = 60

-- Names spelled out where the game abbreviates them.
local NAMES = {
	["Char. Attunes"] = "Character Attunes", ["Char. Affixes"] = "Character Affixes",
	["Achieve Points"] = "Achievement Points", ["Lightf. Attunes"] = "Lightforged Attunes",
}
-- group arg -> section and label
local GROUPS = {
	[1] = { "Dungeons & Raids", "WotLK" }, [2] = { "Dungeons & Raids", "TBC" }, [3] = { "Dungeons & Raids", "Classic" },
	[4] = { "Dungeons & Raids", "Mythic WotLK" }, [5] = { "Dungeons & Raids", "Mythic TBC" },
	[6] = { "Prestiged", "WotLK" }, [7] = { "Prestiged", "TBC" }, [8] = { "Prestiged", "Classic" },
	[9] = { "Prestiged", "Mythic WotLK" }, [10] = { "Prestiged", "Mythic TBC" },
}

function LB.Available()
	return type(LBoardData) == "table" and #LBoardData > 0
end

function LB.Key(t, arg)
	return t .. ":" .. arg
end

-- { sections = { { label, entries } } }: General's entries are boards; the others' are groups, each with boards.
-- A board is { type, arg, name }, a group { arg, name, boards }.
function LB.Tree()
	local general, sections, byLabel, groups = {}, {}, {}, {}
	for _, d in ipairs(LBoardData or {}) do
		if d.arg == 0 then
			general[#general + 1] = { type = d.type, arg = 0, name = NAMES[d.name] or d.name }
		elseif d.type == 0 and GROUPS[d.arg] then
			local g = { arg = d.arg, name = GROUPS[d.arg][2], boards = {} }
			groups[d.arg] = g
			local label = GROUPS[d.arg][1]
			if not byLabel[label] then
				byLabel[label] = { label = label, entries = {} }
				sections[#sections + 1] = byLabel[label]
			end
			table.insert(byLabel[label].entries, g)
		end
	end
	for _, d in ipairs(LBoardData or {}) do
		local g = d.type ~= 0 and groups[d.arg]
		if g then table.insert(g.boards, { type = d.type, arg = d.arg, name = d.name }) end
	end
	table.insert(sections, 1, { label = "General", entries = general })
	return sections
end

-- The board's last answer, or nil.
function LB.Data(t, arg)
	local c = LB.cache[LB.Key(t, arg)]
	return c and c.data
end

function LB.AskedAt(t, arg)
	local c = LB.cache[LB.Key(t, arg)]
	return c and c.asked
end

-- Asks the server for a board unless it was asked in the last minute, as the game's window does.
function LB.Request(t, arg)
	local key = LB.Key(t, arg)
	local c = LB.cache[key] or {}
	LB.cache[key] = c
	local now = time()
	if not c.asked or now - c.asked >= COOLDOWN then
		c.asked = now
		NotifyServer(3, 0, t .. " " .. arg)
	end
end

function LB.Received(t, arg, data)
	local key = LB.Key(t, arg)
	LB.cache[key] = LB.cache[key] or {}
	LB.cache[key].data = data
	LB.cache[key].received = time()
	if LB.onChange then LB.onChange(t, arg) end
end

-- The server refreshed every board; asking again may give new ranks.
function LB.Reset()
	for _, c in pairs(LB.cache) do c.asked = nil end
end

local function commas(n)
	local text = tostring(math.floor(n))
	local k
	repeat text, k = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return text
end

-- A value as its board shows it: a count, a time in milliseconds, or a percentage.
function LB.ValueText(value, vtype)
	local text
	value = value or 0
	if vtype == 1 then
		text = commas(value)
	elseif vtype == 2 then
		local ms = math.floor(value % 1000)
		local s = math.floor(value / 1000) % 60
		local m = math.floor(value / 60000) % 60
		local h = math.floor(value / 3600000) % 24
		local d = math.floor(value / 86400000)
		if d > 0 then
			text = ("%dd %02d:%02d:%02d"):format(d, h, m, s)
		elseif h > 0 then
			text = ("%d:%02d:%02d"):format(h, m, s)
		elseif m > 0 then
			text = ("%d:%02d"):format(m, s)
		else
			text = ("%d.%03ds"):format(s, ms)
		end
	elseif vtype == 3 then
		text = ("%.2f%%"):format(value)
	else
		text = tostring(value)
	end
	return text
end

-- The color code for a rank's class, or grey.
function LB.ClassColor(cl)
	local color = "|cff808080"
	if cl and cl > 0 and CMCGetClassNameColor then
		if cl >= 0x10 then cl = bit.band(cl, 0xF) + bit.lshift(bit.band(cl, 0xF0), 4) end
		local _, _, _, code = CMCGetClassNameColor(cl)
		if code and code ~= "" then color = code end
	end
	return color
end

-- Ranks with their place numbers: rows marked h (an extra row, like your own place below the list) get none.
function LB.Rows(data)
	local rows, place = {}, 0
	for _, r in ipairs(data and data.ranks or {}) do
		local row = { name = r.name, acc = r.acc, cl = r.cl, value = r.value, ts = r.ts, self = r.self }
		if not r.h then
			place = place + 1
			row.place = place
		end
		rows[#rows + 1] = row
	end
	return rows
end
