local _, NS = ...
local SC = NS.SC

-- A searchable list that opens under a button, for choices too long for a dropdown. It closes like a dropdown
-- menu. In multi mode clicking toggles entries and it stays open.
local Picker = {}
SC.Picker = Picker

local S = SC.Style
local C = S.colors

local W, H = 300, 360
local popup, spec

-- spec: items = { { value, text, tooltip } } or search(text) -> items, placeholder, multi, isSelected(value),
-- onPick(value), emptyText
local function refresh()
	local q = popup.search:GetText() or ""
	local items
	if spec.search then
		items = spec.search(q)
	else
		items = {}
		local lower = q:lower()
		for _, item in ipairs(spec.items or {}) do
			if lower == "" or item.text:lower():find(lower, 1, true) then items[#items + 1] = item end
		end
	end
	popup.list:SetItems(items, spec.emptyText or "Nothing Matches", popup.keepScroll)
	popup.keepScroll = nil
end

-- The list and search keep their size in every skin; the popup grows around them by the skin's padding.
local function create()
	local inset, innerW, innerH = S.metrics.inset, W - 2 * S.PAD, H - 2 * S.PAD
	popup = CreateFrame("Frame", "SynastriaCompanionPicker", UIParent)
	popup:SetSize(innerW + 2 * inset, innerH + 2 * inset)
	popup:SetFrameStrata("DIALOG")
	popup:SetToplevel(true)
	popup:EnableMouse(true)
	SC.PixelScale(popup)
	S.Frame(popup, "popup")
	tinsert(UISpecialFrames, "SynastriaCompanionPicker")

	popup.search = S.Input(popup, "SynastriaCompanionPickerSearch", innerW, "Search", 60)
	popup.search:SetPoint("TOPLEFT", inset, -inset)
	popup.search:HookScript("OnTextChanged", function(_, user)
		if user then refresh() end
	end)

	popup.list = SC.Table.New(popup, nil, innerW, innerH - S.PAD - S.CONTROL_H, {
		columns = { { key = "text", label = "", width = innerW - 2, sortable = false } },
		cell = function(item)
			local on = spec.isSelected and spec.isSelected(item.value)
			if spec.multi then return (on and "|cffffc400+|r  " or "    ") .. item.text, on and C.heading or C.text end
			return item.text, on and C.heading or C.text
		end,
		icon = function(item) return item.icon end,
		tooltip = function(tt, item)
			if item.link then
				tt:SetHyperlink(item.link)
			elseif item.tooltip then
				tt:SetText(item.text, 1, 1, 1)
				tt:AddLine(item.tooltip, nil, nil, nil, true)
			end
		end,
		onClick = function(item)
			if not spec.multi then popup:Hide() end
			if spec.onPick then spec.onPick(item.value) end
			if spec.multi then
				popup.keepScroll = true
				refresh()
			end
		end,
	})
	popup.list.frame:SetPoint("TOPLEFT", popup.search, "BOTTOMLEFT", 0, -S.GAP)
	popup:SetScript("OnHide", function() popup.search:ClearFocus() end)
	S.TrackPopup(popup)
end

-- Opens under anchor; opening it from the same button again closes it.
function Picker.Open(anchor, newSpec)
	if not popup then create() end
	local open = popup:IsShown() and popup.owner == anchor
	S.CloseMenus()
	if not open then
		spec = newSpec
		popup.owner = anchor
		popup:ClearAllPoints()
		popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		popup.search:SetText("")
		popup.search.placeholder:SetText(spec.placeholder or "Search")
		popup.search:UpdatePlaceholder()
		refresh()
		popup:Show()
	end
end

function Picker.Close()
	if popup then popup:Hide() end
end
