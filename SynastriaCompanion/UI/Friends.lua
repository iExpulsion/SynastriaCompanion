local _, NS = ...
local SC = NS.SC

-- Friends: the attune counts friends, guildmates, the group and this account's other characters have shared,
-- online players first. Companion's own screen; the game has no window for it.
local FriendsUI = {}
SC.FriendsUI = FriendsUI

local S = SC.Style
local C = S.colors
local Friends = SC.Friends
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local panel, tbl, state

-- count index in a record's counts for each count column
local COUNT_INDEX = { acc = 1, tf = 2, wf = 3, lf = 4, char = 5 }

local COLUMNS = {
	{ key = "name", label = "Player", width = 150, stretch = true },
	{ key = "relation", label = "Relation", width = 70 },
	{ key = "acc", label = "Account", width = 74, defaultDesc = true,
		tooltip = "Items attuned on their whole account." },
	{ key = "char", label = "Character", width = 78, defaultDesc = true,
		tooltip = "Items attuned on the character that shared." },
	{ key = "tf", label = "Titanforged", width = 84, defaultDesc = true },
	{ key = "wf", label = "Warforged", width = 78, defaultDesc = true },
	{ key = "lf", label = "Lightforged", width = 82, defaultDesc = true },
	{ key = "seen", label = "Updated", width = 84, defaultDesc = true },
}

local RELATION_ORDER = { You = 1, Alt = 2, Group = 3, Friend = 4, Guild = 5, [""] = 6 }

local function count(n)
	return SC.Leaderboards.ValueText(n or 0, 1)
end

local function ago(t)
	local secs = time() - (t or 0)
	local text
	if secs < 60 then
		text = "Just Now"
	elseif secs < 3600 then
		text = ("%d Min Ago"):format(secs / 60)
	elseif secs < 86400 then
		text = ("%d Hr Ago"):format(secs / 3600)
	else
		local days = math.floor(secs / 86400)
		text = days == 1 and "1 Day Ago" or ("%d Days Ago"):format(days)
	end
	return text
end

local function classHex(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	return c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffc0c0c0"
end

local function sortValue(row, key)
	local v
	if COUNT_INDEX[key] then
		v = row.counts[COUNT_INDEX[key]] or 0
	elseif key == "seen" then
		v = row.seen or 0
	elseif key == "relation" then
		v = RELATION_ORDER[row.relation] or 9
	else
		v = row.name:lower()
	end
	return v
end

-- Online players before offline ones, then by the chosen column, then by name.
local function sortRows(rows)
	local key, desc = state.sort, state.desc
	table.sort(rows, function(a, b)
		local result
		if a.online ~= b.online then
			result = a.online
		else
			local va, vb = sortValue(a, key), sortValue(b, key)
			if va == vb then
				result = a.name < b.name
			elseif desc then
				result = va > vb
			else
				result = va < vb
			end
		end
		return result
	end)
end

local function render()
	local rows = Friends.Rows()
	sortRows(rows)
	local others, online = 0, 0
	for _, r in ipairs(rows) do
		if not r.own then
			others = others + 1
			if r.online then online = online + 1 end
		end
	end
	tbl:SetItems(rows, "Nobody Has Shared Yet", true)
	panel.status:SetText(S.Count(others, "Player") .. S.Hex(C.muted, "  |  ") .. online .. " Online")
	panel.share:SetChecked(SC.db.share)
end

local function cell(row, key)
	local text, color
	if key == "name" then
		text = classHex(row.class) .. row.name .. "|r"
		if row.level and row.level > 0 then text = text .. S.Hex(C.muted, "  " .. row.level) end
		color = row.online and C.text or C.muted
	elseif key == "relation" then
		text, color = row.relation, C.muted
	elseif COUNT_INDEX[key] then
		text = count(row.counts[COUNT_INDEX[key]])
		color = row.online and C.text or C.muted
	elseif key == "seen" then
		text, color = ago(row.seen), C.muted
	end
	return text, color
end

local function tooltip(tt, row)
	tt:AddLine(classHex(row.class) .. row.name .. "|r")
	if row.relation ~= "" then
		tt:AddLine(row.relation .. (row.online and ", online" or ", offline"), unpack(C.muted))
	end
	local c = row.counts
	tt:AddLine(" ")
	tt:AddDoubleLine("Account", count(c[1]), 1, 1, 1, 1, 1, 1)
	tt:AddDoubleLine("   Titanforged / Warforged / Lightforged", count(c[2]) .. " / " .. count(c[3]) .. " / " .. count(c[4]),
		0.7, 0.7, 0.7, 1, 1, 1)
	tt:AddDoubleLine("Character", count(c[5]), 1, 1, 1, 1, 1, 1)
	tt:AddDoubleLine("   Titanforged / Warforged / Lightforged", count(c[6]) .. " / " .. count(c[7]) .. " / " .. count(c[8]),
		0.7, 0.7, 0.7, 1, 1, 1)
	tt:AddLine(" ")
	tt:AddLine("Updated " .. ago(row.seen):lower() .. ".", unpack(C.muted))
	if row.relation ~= "You" then tt:AddLine("Right-click to forget them.", unpack(C.muted)) end
end

local function onClick(row, button)
	if button == "RightButton" and row.relation ~= "You" then Friends.Forget(row.name) end
end

local function create(parent, width, height)
	SC.db.friendsScreen = SC.db.friendsScreen or { sort = "acc", desc = true }
	state = SC.db.friendsScreen
	panel = CreateFrame("Frame", nil, parent)

	panel.title = S.Text(panel, "large")
	panel.title:SetPoint("TOPLEFT", PAD, -PAD - 2)
	panel.title:SetText("Friends")
	panel.sub = S.Text(panel, "small", C.muted)
	panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
	panel.sub:SetText("Attunes shared by friends, guildmates and your group who use Synastria Companion.")
	panel.refresh = S.Button(panel, "Refresh", "ghost", 70, function()
		Friends.Refresh()
		render()
	end, "Ask everyone online for their attunes again. Asks at most once a minute.")
	panel.refresh:SetPoint("TOPRIGHT", -PAD, -PAD)

	local top = -PAD - CONTROL_H - GAP - 12
	local footerH = PAD + CONTROL_H + PAD
	tbl = SC.Table.New(panel, "SynastriaCompanionFriends", width - 2 * PAD, height + top - footerH, {
		columns = COLUMNS, rowH = 20, cell = cell, tooltip = tooltip, onClick = onClick,
		onSort = function(key, desc)
			state.sort, state.desc = key, desc
			render()
		end,
	})
	tbl.isSelected = function(row) return row.relation == "You" end
	tbl.frame:SetPoint("TOPLEFT", PAD, top)
	tbl:SetSort(state.sort, state.desc)
	panel.table = tbl

	panel.status = S.Text(panel, "small")
	panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)

	panel.shareLabel = S.Text(panel, "small")
	panel.shareLabel:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + CONTROL_H / 2)
	panel.shareLabel:SetText("Share My Attunes")
	panel.share = S.Check(panel, nil, function()
		Friends.SetShare(not SC.db.share)
	end)
	panel.share:SetPoint("RIGHT", panel.shareLabel, "LEFT", -6, 0)
	panel.share:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Share My Attunes", 1, 1, 1)
		GameTooltip:AddLine("Lets friends, your guild and your group see your attune counts, and tells them when "
			.. "you still need an item they're looking at.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	panel.share:HookScript("OnLeave", function() GameTooltip:Hide() end)

	Friends.onChange = function()
		if panel:IsVisible() then render() end
	end
	return panel
end

local function show()
	Friends.Status()
	Friends.Refresh()
	render()
end

SC.Window.AddScreen({
	key = "friends",
	label = "Friends",
	create = create,
	show = show,
})
