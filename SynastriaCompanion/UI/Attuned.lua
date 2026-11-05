local _, NS = ...
local SC = NS.SC

-- Attuned Stats: the stats attuned items give, totaled for this character beside each part (Misc, its armor type,
-- Weapon) and what's attuned but inactive. Replaces the window the game opens with OpenAttuneSummary.
local AttunedUI = {}
SC.AttunedUI = AttunedUI

local S = SC.Style
local C = S.colors
local Attuned = SC.Attuned
local PAD, CONTROL_H = S.PAD, S.CONTROL_H

local panel, tbl, cols, state
local KEYS = { "total", "misc", "armor", "weapon", "inactive" }

local function commas(n)
	local text = tostring(n)
	local k
	repeat text, k = text:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return text
end

local function valueText(v, muted)
	local text, color = "", C.muted
	if v and v ~= 0 then
		-- the game keeps fractions; below 1 a whole number would read as a zero
		local size = math.abs(v)
		local shown = size < 1 and ("%.1f"):format(math.max(0.1, math.floor(size * 10) / 10)) or commas(math.floor(size))
		text = (v > 0 and "+" or "-") .. shown
		color = muted and C.disabled or v > 0 and C.good or C.bad
	end
	return text, color
end

local COLUMNS = {
	{ key = "stat", label = "Stat", width = 156 },
	{ key = "total", label = "Total", width = 110, justify = "RIGHT", defaultDesc = true,
		tooltip = "What this character gets: Misc, its armor type and Weapon added up." },
	{ key = "misc", label = "Misc", width = 106, justify = "RIGHT", defaultDesc = true,
		tooltip = "Jewelry, cloaks and other gear any class can wear." },
	{ key = "armor", label = "Armor", width = 106, justify = "RIGHT", defaultDesc = true,
		tooltip = "Armor of this character's type." },
	{ key = "weapon", label = "Weapon", width = 106, justify = "RIGHT", defaultDesc = true },
	{ key = "inactive", label = "Inactive", width = 118, justify = "RIGHT", defaultDesc = true,
		tooltip = "Attuned gear this character's armor type or class can't use, so it adds nothing here. Attune progress is account-wide." },
}

local function cell(row, key)
	if key == "stat" then return row.name, C.text end
	local col = cols[key]
	local text, color = valueText(col and col.stats[row.stat], key == "inactive")
	if key == "total" and text ~= "" then color = C.heading end
	return text, color
end

local function sortRows(rows)
	local key, desc = state.sort, state.desc
	table.sort(rows, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		local va, vb
		if key == "stat" or not cols[key] then
			va, vb = a.order, b.order
		else
			va, vb = cols[key].stats[a.stat] or 0, cols[key].stats[b.stat] or 0
		end
		if va == vb then return a.order < b.order end
		if desc then return va > vb end
		return va < vb
	end)
end

local function ago(t)
	local secs = time() - t
	if secs < 60 then return "Just Now" end
	if secs < 3600 then return ("%d Min Ago"):format(secs / 60) end
	return ("%d Hr Ago"):format(secs / 3600)
end

local function refresh()
	local rows
	cols, rows = Attuned.Read()
	for _, key in ipairs(KEYS) do
		local col = cols[key]
		tbl:SetColumnLabel(key, col.count > 0 and ("%s (%s)"):format(col.label, commas(col.count)) or col.label)
	end
	sortRows(rows)
	local shown, group = {}, nil
	for _, row in ipairs(rows) do
		if row.group ~= group then
			group = row.group
			shown[#shown + 1] = { header = true, label = Attuned.GROUPS[group].label }
		end
		shown[#shown + 1] = row
	end
	tbl:SetItems(shown, Attuned.HasData() and "No Attuned Stats Yet"
		or "Click Load Stats to Get Your Attuned Stats From the Server", true)
	panel.status:SetText(Attuned.receivedAt and ("Updated " .. ago(Attuned.receivedAt))
		or Attuned.HasData() and "" or S.Hex(C.muted, "Not Loaded"))
	panel.load:SetText(Attuned.HasData() and "Refresh" or "Load Stats")
end

-- The request is a spell cast, which only a secure button the player clicks can make. Secure buttons can't be
-- shown or moved in combat, and lock what they're anchored to, so this one sits on UIParent over the
-- placeholder button, follows it each frame out of combat, and hides when combat starts or the screen does.
local secure

local function hideSecure()
	if secure and not InCombatLockdown() then secure:Hide() end
end

local function placeSecure()
	local spot = panel.load
	if not InCombatLockdown() and spot:IsVisible() then
		if not secure then
			secure = CreateFrame("Button", "SynastriaCompanionAttunedLoad", UIParent, "SecureActionButtonTemplate")
			secure:SetFrameStrata("HIGH")
			secure:RegisterForClicks("LeftButtonUp")
			secure:SetAttribute("type", "macro")
			secure:SetScript("OnEnter", function() spot:GetScript("OnEnter")(spot) end)
			secure:SetScript("OnLeave", function() spot:GetScript("OnLeave")(spot) end)
			secure:HookScript("OnClick", function() panel.status:SetText(S.Hex(C.muted, "Asking the Server...")) end)
		end
		secure:SetAttribute("macrotext", Attuned.RequestMacro())
		local scale = spot:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local left, bottom, w, h = spot:GetLeft(), spot:GetBottom(), spot:GetWidth(), spot:GetHeight()
		if left and bottom then
			secure:ClearAllPoints()
			secure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
			secure:SetSize(w * scale, h * scale)
			secure:SetFrameLevel(spot:GetFrameLevel() + 10)
			secure:Show()
		end
	end
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_REGEN_DISABLED")
watch:SetScript("OnEvent", function()
	-- fires just before the lockdown starts, so it can still hide here
	if secure then secure:Hide() end
end)

local function create(parent, width, height)
	SC.db.attuned = SC.db.attuned or {}
	state = SC.db.attuned
	state.sort = state.sort or "stat"
	panel = CreateFrame("Frame", nil, parent)

	-- a look-alike the secure button covers; it's what shows while in combat, when it can't be clicked
	panel.load = S.Button(panel, "Load Stats", "primary", 100, function()
		panel.status:SetText(S.Hex(C.bad, "Can't Ask in Combat"))
	end, "Ask the server for your attuned stats (casts View Attuned Items).")
	panel.load:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	local top = -PAD
	local footerH = PAD + CONTROL_H + PAD
	tbl = SC.Table.New(panel, "SynastriaCompanionAttunedTable", width - 2 * PAD, height + top - footerH, {
		columns = COLUMNS, rowH = 20, cell = cell,
		header = function(row) return row.header and row.label end,
		onSort = function(key, desc)
			state.sort, state.desc = key, desc
			refresh()
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", PAD, top)
	tbl:SetSort(state.sort, state.desc)
	panel.table = tbl

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	local hint = S.Text(panel, "small", C.muted)
	hint:SetPoint("RIGHT", panel.load, "LEFT", -PAD, 0)
	hint:SetText("Hover a Column for What It Counts")

	panel:SetScript("OnUpdate", placeSecure)
	panel:SetScript("OnHide", hideSecure)
	S.OnDismiss(hideSecure)
	Attuned.onChange = function()
		if panel:IsVisible() then refresh() end
	end
	return panel
end

local function show()
	refresh()
end

SC.Window.AddScreen({
	key = "attuned",
	label = "Attuned Stats",
	create = create,
	show = show,
	hook = {
		open = "OpenAttuneSummary", close = "CloseAttuneSummary", frame = "ItemAttuneFrame",
		-- the server calls these once it has sent the stats
		extra = {
			OpenAttuneSummary = function()
				SC.Window.Open("attuned")
				Attuned.Received()
			end,
			UpdateAttuneSummary = function() Attuned.Received() end,
		},
	},
})
