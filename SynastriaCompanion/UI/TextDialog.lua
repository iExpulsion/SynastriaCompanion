local _, NS = ...
local SC = NS.SC

-- A dialog with a multi-line text box, for copying out an export string or pasting one in.
local TextDialog = {}
SC.TextDialog = TextDialog

local S = SC.Style
local C = S.colors
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H

-- the text box: shorter on import, to make room for the Import button under it
local W, WELL_H = 460, 196
local dialog

-- Top to bottom: title, a note that wraps (below Close in the corner), the text box, then on import its button. The
-- contents keep their width in every skin, the dialog grows around them by the skin's padding, and it's as tall as
-- they are.
local function create()
	local inset = S.metrics.inset
	dialog = CreateFrame("Frame", "SynastriaCompanionTextDialog", UIParent)
	dialog:SetWidth(W - 2 * PAD + 2 * inset)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	SC.PixelScale(dialog)
	S.Frame(dialog, "popup")
	tinsert(UISpecialFrames, "SynastriaCompanionTextDialog")
	dialog.stack = S.Stack(dialog, { width = W - 2 * PAD,
		onLayout = function(bottom) dialog:SetHeight(bottom + inset) end })

	-- Close sits top right, beside the title, as in Build Suite; the bottom row is for Import alone
	dialog.cancel = S.Button(dialog, "Close", "ghost", 70, function() dialog:Hide() end)
	dialog.cancel:SetPoint("TOPRIGHT", -inset, -(inset - 4))
	dialog.title = dialog.stack:Add(S.Text(dialog, "normal", C.heading))
	dialog.title:SetHeight(16)
	dialog.note = dialog.stack:Add(S.Wrapped(dialog, "small", C.muted), { gap = 4 })

	local well = CreateFrame("Frame", nil, dialog)
	well:SetSize(W - 2 * PAD, WELL_H)
	well:Show()
	dialog.stack:Add(well, { gap = GAP })
	dialog.well = well
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

	dialog.okRow = CreateFrame("Frame", nil, dialog)
	dialog.okRow:SetHeight(CONTROL_H)
	dialog.stack:Add(dialog.okRow, { gap = GAP, fill = true })
	dialog.ok = S.Button(dialog.okRow, "Import", "primary", 90, function()
		local text = edit:GetText()
		dialog:Hide()
		if dialog.onOk then dialog.onOk(text) end
	end)
	dialog.ok:SetPoint("RIGHT")
	dialog:SetScript("OnHide", function() edit:ClearFocus() end)
	S.OnDismiss(function() dialog:Hide() end)
end

-- The text box runs to the bottom when exporting, and stops above the Import button when importing.
local function fitWell(importing)
	dialog.well:SetHeight(importing and WELL_H - CONTROL_H - GAP or WELL_H)
	if importing then dialog.okRow:Show() else dialog.okRow:Hide() end
	dialog.stack:Layout()
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
