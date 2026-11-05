local _, NS = ...
local SC = NS.SC

-- Attuned Items: the stats attuned items give, totaled for this character beside each part (Misc, its armor type,
-- Weapon) and what's attuned but inactive. Replaces the window the game opens with OpenAttuneSummary.
local AttunedUI = {}
SC.AttunedUI = AttunedUI

local S = SC.Style
local C = S.colors
local Attuned = SC.Attuned
local PAD, GAP = S.PAD, S.GAP

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
		local whole = math.floor(math.abs(v))
		text = (v > 0 and "+" or "-") .. commas(whole)
		color = muted and C.disabled or v > 0 and C.good or C.bad
	end
	return text, color
end

local COLUMNS = {
	{ key = "stat", label = "Stat", width = 194 },
	{ key = "total", label = "Total", width = 110, justify = "RIGHT", defaultDesc = true },
	{ key = "misc", label = "Misc", width = 100, justify = "RIGHT", defaultDesc = true },
	{ key = "armor", label = "Armor", width = 100, justify = "RIGHT", defaultDesc = true },
	{ key = "weapon", label = "Weapon", width = 100, justify = "RIGHT", defaultDesc = true },
	{ key = "inactive", label = "Inactive", width = 100, justify = "RIGHT", defaultDesc = true },
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
	tbl:SetItems(rows, Attuned.HasData() and "No Attuned Stats Yet"
		or "Click Load Stats to Get Your Attuned Stats From the Server", true)
	panel.status:SetText(Attuned.receivedAt and ("Updated " .. ago(Attuned.receivedAt))
		or Attuned.HasData() and "" or S.Hex(C.muted, "Not Loaded"))
	panel.load:SetLabel(Attuned.HasData() and "Refresh" or "Load Stats")
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

	local title = S.Text(panel, "large")
	title:SetPoint("TOPLEFT", PAD, -PAD - 2)
	title:SetText("Stats From Attuned Items")
	local sub = S.Text(panel, "small", C.muted)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	sub:SetText("Total is what this character gets. Inactive is attuned gear its armor type or class can't use.")

	-- a look-alike the secure button covers; it's what shows while in combat, when it can't be clicked
	panel.load = S.Button(panel, "Load Stats", "primary", 100, function()
		panel.status:SetText(S.Hex(C.bad, "Can't Ask in Combat"))
	end, "Ask the server for your attuned stats (casts View Attuned Items).")
	panel.load:SetPoint("TOPRIGHT", -PAD, -PAD)

	local top = -PAD - 40 - GAP
	local footerH = PAD + 14 + PAD
	tbl = SC.Table.New(panel, "SynastriaCompanionAttunedTable", width - 2 * PAD, height + top - footerH, {
		columns = COLUMNS, rowH = 20, cell = cell,
		onSort = function(key, desc)
			state.sort, state.desc = key, desc
			refresh()
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", PAD, top)
	tbl:SetSort(state.sort, state.desc)
	panel.table = tbl

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("BOTTOMLEFT", PAD, PAD)
	local hint = S.Text(panel, "small", C.muted)
	hint:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	hint:SetText("Attune progress is account-wide; stats count only for gear this character can use")

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
	label = "Attuned Items",
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
