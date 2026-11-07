local _, NS = ...
local SC = NS.SC

-- A dialog with a multi-line text box, for copying out an export string or pasting one in.
local TextDialog = {}
SC.TextDialog = TextDialog

local S = SC.Style
local C = S.colors
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

local W, H = 460, 260
local dialog

-- The contents keep their size in every skin; the dialog grows around them by the skin's padding.
local function create()
	local inset = S.metrics.inset
	dialog = CreateFrame("Frame", "SynastriaCompanionTextDialog", UIParent)
	dialog:SetSize(W - 2 * PAD + 2 * inset, H - 2 * PAD + 2 * inset)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	SC.PixelScale(dialog)
	S.Frame(dialog, "popup")
	tinsert(UISpecialFrames, "SynastriaCompanionTextDialog")

	-- Close sits top right, beside the title, as in Build Suite; the bottom row is for Import alone
	dialog.cancel = S.Button(dialog, "Close", "ghost", 70, function() dialog:Hide() end)
	dialog.cancel:SetPoint("TOPRIGHT", -inset, -(inset - 4))
	dialog.title = S.Text(dialog, "normal", C.heading)
	dialog.title:SetPoint("TOPLEFT", inset, -inset)
	dialog.note = S.Text(dialog, "small", C.muted)
	dialog.note:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -4)
	dialog.note:SetPoint("RIGHT", dialog.cancel, "LEFT", -GAP, 0)

	local well = CreateFrame("Frame", nil, dialog)
	well:SetPoint("TOPLEFT", inset, -inset - 40)
	well:SetSize(W - 2 * PAD, H - 2 * PAD - 40)
	dialog.well, dialog.inset = well, inset
	S.Well(well)
	local wi = 6 + S.metrics.wellInset
	local scroll = CreateFrame("ScrollFrame", "SynastriaCompanionTextDialogScroll", well, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", wi, -wi)
	scroll:SetPoint("BOTTOMRIGHT", -16 - S.metrics.wellInset, wi)
	S.ScrollBar(scroll, "SynastriaCompanionTextDialogScroll")
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetWidth(W - 2 * PAD - 26 - 2 * S.metrics.wellInset)
	S.SetFont(edit, "small")
	edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
	scroll:SetScrollChild(edit)
	well:EnableMouse(true)
	well:SetScript("OnMouseDown", function() edit:SetFocus() end)
	dialog.edit = edit
	S.TrackInput(edit, well)

	dialog.ok = S.Button(dialog, "Import", "primary", 90, function()
		local text = edit:GetText()
		dialog:Hide()
		if dialog.onOk then dialog.onOk(text) end
	end)
	dialog.ok:SetPoint("BOTTOMRIGHT", -inset, inset)
	dialog:SetScript("OnHide", function() edit:ClearFocus() end)
	S.OnDismiss(function() dialog:Hide() end)
end

-- The text box runs to the bottom when exporting, and stops above the Import button when importing.
local function fitWell(importing)
	local inset = dialog.inset
	dialog.well:ClearAllPoints()
	dialog.well:SetPoint("TOPLEFT", inset, -inset - 40)
	dialog.well:SetPoint("BOTTOMRIGHT", -inset, inset + (importing and CONTROL_H + GAP or 0))
	if importing then dialog.ok:Show() else dialog.ok:Hide() end
end

-- Shows text to copy; the text is selected so Ctrl+C copies it.
function TextDialog.ShowExport(title, note, text)
	if not dialog then create() end
	dialog.title:SetText(title)
	dialog.note:SetText(note or "")
	dialog.edit:SetText(text or "")
	fitWell(false)
	dialog.onOk = nil
	dialog:ClearAllPoints()
	dialog:SetPoint("CENTER", SC.Window.Frame() or UIParent, "CENTER")
	dialog:Show()
	dialog.edit:SetFocus()
	dialog.edit:HighlightText()
end

-- Asks for text to paste; onOk(text) runs on Import.
function TextDialog.AskImport(title, note, onOk)
	if not dialog then create() end
	dialog.title:SetText(title)
	dialog.note:SetText(note or "")
	dialog.edit:SetText("")
	fitWell(true)
	dialog.onOk = onOk
	dialog:ClearAllPoints()
	dialog:SetPoint("CENTER", SC.Window.Frame() or UIParent, "CENTER")
	dialog:Show()
end
