local _, NS = ...
local SC = NS.SC

-- A virtual table: a fixed pool of rows drawn over any number of items, with sortable column headers, a flat
-- scroll bar and mouse wheel scrolling. The first column can carry an icon.
local Table = {}
SC.Table = Table

local S = SC.Style
local C = S.colors

local HEADER_H, WHEEL_ROWS, BAR_SPACE = 22, 3, 10

local function newRow(self, i)
	local row = CreateFrame("Button", nil, self.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHeight(self.rowH)
	row:SetPoint("TOPLEFT", 0, -HEADER_H - (i - 1) * self.rowH)
	row:SetPoint("TOPRIGHT", 0, -HEADER_H - (i - 1) * self.rowH)
	if i % 2 == 0 then
		local stripe = S.Solid(row, "BACKGROUND", { C.text[1], C.text[2], C.text[3], 0.025 })
		stripe:SetAllPoints()
	end
	row.hoverTex = S.Solid(row, "BORDER", C.hover)
	row.hoverTex:SetAllPoints()
	row.hoverTex:Hide()
	row.selectedTex = S.Solid(row, "BORDER", C.selected)
	row.selectedTex:SetAllPoints()
	row.selectedTex:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(self.rowH - 4, self.rowH - 4)
	row.cells = {}
	for c, col in ipairs(self.columns) do
		local fs = S.Text(row, "small")
		fs:SetJustifyH(col.justify or "LEFT")
		fs:ClearAllPoints()
		local x = col.x + 6 + ((c == 1 and self.icons) and self.rowH or 0)
		fs:SetPoint("LEFT", row, "LEFT", x, 0)
		fs:SetWidth(col.width - 12 - (col.barInset or 0) - ((c == 1 and self.icons) and self.rowH or 0))
		fs:SetHeight(self.rowH)
		row.cells[c] = fs
	end
	if self.icons then row.icon:SetPoint("LEFT", row, "LEFT", self.columns[1].x + 6, 0) end
	-- a group header row: one label across the row on the header color
	row.headerTex = S.Solid(row, "BACKGROUND", C.panel)
	row.headerTex:SetDrawLayer("BACKGROUND", 1)
	row.headerTex:SetAllPoints()
	row.headerTex:Hide()
	row.headerText = S.Text(row, "small", C.heading)
	row.headerText:SetPoint("LEFT", 6, 0)
	row.headerText:SetPoint("RIGHT", -6 - BAR_SPACE, 0)
	row.headerText:Hide()

	row:SetScript("OnEnter", function(r)
		r.hoverTex:Show()
		if r.item and self.tooltip then
			GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
			self.tooltip(GameTooltip, r.item)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(r)
		r.hoverTex:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(r, button)
		if r.item and self.onClick then self.onClick(r.item, button) end
	end)
	return row
end

local function paintHeader(self)
	for _, h in ipairs(self.headers) do
		local on = self.sortKey == h.col.key
		h.label:SetTextColor(unpack(on and C.heading or C.muted))
		if on then
			h.arrow:SetTexCoord(0, 0.5625, self.sortDesc and 0 or 1, self.sortDesc and 1 or 0)
			h.arrow:Show()
		else
			h.arrow:Hide()
		end
	end
end

-- opts: columns = { { key, label, width, justify, sortable, defaultDesc, tooltip } }, rowH, icons (first column has an icon),
-- cell(item, key) -> text, icon(item) -> texture, tooltip(tt, item), onClick(item, button), onSort(key, desc),
-- header(item) -> label when the item is a group header row
function Table.New(parent, name, width, height, opts)
	local self = setmetatable({ columns = opts.columns, rowH = opts.rowH or 20, icons = opts.icons, cell = opts.cell,
		iconOf = opts.icon, tooltip = opts.tooltip, onClick = opts.onClick, onSort = opts.onSort, header = opts.header,
		items = {},
		offset = 0, rows = {}, headers = {} }, { __index = Table })
	-- the rows run under the scroll bar to the table's edge; the last column takes any spare width and keeps its
	-- text clear of the bar
	local x, columns = 0, {}
	for i, def in ipairs(opts.columns) do
		local col = {}
		for k, v in pairs(def) do col[k] = v end
		col.x = x
		x = x + col.width
		columns[i] = col
	end
	self.columns = columns
	local last = self.columns[#self.columns]
	last.width = last.width + math.max(0, width - 2 - x)
	last.barInset = BAR_SPACE

	self.frame = CreateFrame("Frame", name, parent)
	self.frame:SetSize(width, height)
	S.Panel(self.frame, C.well, C.border)
	self.content = CreateFrame("Frame", nil, self.frame)
	self.content:SetPoint("TOPLEFT", 1, -1)
	self.content:SetPoint("BOTTOMRIGHT", -1, 1)

	local header = S.Solid(self.content, "BACKGROUND", C.panel)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	local rule = S.Solid(self.content, "BORDER", C.border)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 0, -HEADER_H)
	rule:SetPoint("TOPRIGHT", 0, -HEADER_H)
	for _, col in ipairs(self.columns) do
		local h = CreateFrame("Button", nil, self.content)
		h:SetSize(col.width, HEADER_H)
		h:SetPoint("TOPLEFT", col.x, 0)
		h.col = col
		h.label = S.Text(h, "small", C.muted)
		h.label:SetPoint("LEFT", 6, 0)
		h.label:SetPoint("RIGHT", -16 - (col.barInset or 0), 0)
		h.label:SetJustifyH(col.justify or "LEFT")
		h.label:SetText(col.label or "")
		h.arrow = h:CreateTexture(nil, "OVERLAY")
		h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		h.arrow:SetSize(9, 8)
		h.arrow:SetPoint("RIGHT", -4 - (col.barInset or 0), 0)
		h.arrow:SetDesaturated(true)
		h.arrow:SetVertexColor(unpack(C.heading))
		h.arrow:Hide()
		if col.sortable ~= false then
			local hover = S.Solid(h, "HIGHLIGHT", C.hover)
			hover:SetAllPoints()
			h:SetScript("OnClick", function()
				if self.sortKey == col.key then
					self.sortDesc = not self.sortDesc
				else
					self.sortKey, self.sortDesc = col.key, col.defaultDesc or false
				end
				paintHeader(self)
				if self.onSort then self.onSort(self.sortKey, self.sortDesc) end
			end)
		end
		if col.tooltip then
			h:SetScript("OnEnter", function()
				GameTooltip:SetOwner(h, "ANCHOR_TOP")
				GameTooltip:SetText(col.tooltip, nil, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		self.headers[#self.headers + 1] = h
	end

	self.visible = math.floor((height - 2 - HEADER_H) / self.rowH)
	for i = 1, self.visible do self.rows[i] = newRow(self, i) end

	local bar = CreateFrame("Slider", nil, self.frame)
	bar:SetFrameLevel(self.content:GetFrameLevel() + 5)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	-- the same 2px gap below the header's rule as above the bottom border: 1px border, header, 1px rule, 2px
	bar:SetPoint("TOPRIGHT", -3, -1 - HEADER_H - 1 - 2)
	bar:SetPoint("BOTTOMRIGHT", -3, 3)
	local track = S.Solid(bar, "BACKGROUND", { C.text[1], C.text[2], C.text[3], 0.04 })
	track:SetAllPoints()
	bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 40)
	thumb:SetVertexColor(unpack(C.border))
	bar:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.outline)) end)
	bar:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.border)) end)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value)
		local offset = math.floor(value + 0.5)
		if offset ~= self.offset then
			self.offset = offset
			self:Redraw()
		end
	end)
	self.bar = bar

	self.frame:EnableMouseWheel(true)
	self.frame:SetScript("OnMouseWheel", function(_, delta)
		self:ScrollTo(self.offset - delta * (IsShiftKeyDown() and self.visible or WHEEL_ROWS))
	end)

	self.empty = S.Text(self.content, "normal", C.muted)
	self.empty:SetPoint("TOP", 0, -HEADER_H - 40)
	self.empty:SetJustifyH("CENTER")
	return self
end

function Table:SetColumnLabel(key, text)
	for _, h in ipairs(self.headers) do
		if h.col.key == key then h.label:SetText(text) end
	end
end

function Table:SetSort(key, desc)
	self.sortKey, self.sortDesc = key, desc
	paintHeader(self)
end

function Table:ScrollTo(offset)
	local max = math.max(0, #self.items - self.visible)
	offset = math.max(0, math.min(max, offset))
	self.bar:SetValue(offset)
	if offset ~= self.offset then
		self.offset = offset
		self:Redraw()
	end
end

-- Shows new items; keepScroll leaves the scroll position where it is (clamped) instead of going to the top.
function Table:SetItems(items, emptyText, keepScroll)
	self.items = items
	local max = math.max(0, #items - self.visible)
	self.bar:SetMinMaxValues(0, max)
	if max > 0 then self.bar:Show() else self.bar:Hide() end
	self.offset = keepScroll and math.min(self.offset, max) or 0
	self.bar:SetValue(self.offset)
	self.empty:SetText(#items == 0 and (emptyText or "") or "")
	self:Redraw()
end

function Table:Redraw()
	for i, row in ipairs(self.rows) do
		local item = self.items[self.offset + i]
		row.item = item
		local header = item and self.header and self.header(item)
		if header then
			for _, fs in ipairs(row.cells) do fs:SetText("") end
			row.icon:Hide()
			row.headerText:SetText(header)
			row.headerText:Show()
			row.headerTex:Show()
		else
			row.headerText:Hide()
			row.headerTex:Hide()
		end
		if item and not header then
			for c, col in ipairs(self.columns) do
				local text, color = self.cell(item, col.key)
				row.cells[c]:SetText(text or "")
				row.cells[c]:SetTextColor(unpack(color or C.text))
			end
			if self.icons then
				local tex = self.iconOf and self.iconOf(item)
				row.icon:SetTexture(tex)
				if tex then row.icon:Show() else row.icon:Hide() end
			end
		end
		if item then
			if self.isSelected and self.isSelected(item) then row.selectedTex:Show() else row.selectedTex:Hide() end
			row:Show()
		else
			row:Hide()
		end
	end
	if GameTooltip:IsOwned(self.rows[1]) then GameTooltip:Hide() end
end

function Table:Show() self.frame:Show() end
function Table:Hide() self.frame:Hide() end
