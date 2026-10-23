
local WFL = _G.WorldforgedLogger
local format = string.format

local ROWS, ROW_H = 13, 22
local selected

local panel = CreateFrame("Frame", "WorldforgedLoggerPanel", UIParent)
panel.name = "Worldforged Logger"

local function MakeCheck(name, label, tooltip, x, y, get, set)
	local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
	_G[name .. "Text"]:SetText(label)
	cb.tooltipText = tooltip
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb.Refresh = function(self) self:SetChecked(get()) end
	return cb
end

local function StatusText(st)
	if st == "yes" then return "|cff00ff00Yes|r" end
	if st == "other" then return "|cffffaa00Other map|r" end
	if st == "no" then return "|cffff4040No|r" end
	return "|cff888888?|r"
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Worldforged Logger")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
sub:SetWidth(590)
sub:SetJustifyH("LEFT")
sub:SetText("Logs every Worldforged item you loot from the world (item ID, map, coordinates) so you can add missing ones to LootCollector. /wfl opens this page, /wfl add [item] logs an item manually.")

local cbEnable = MakeCheck("WFLCheckEnable", "Enable logging", "Turn the whole logger on or off.", 16, -62,
	function() return WorldforgedLoggerDB.enabled end,
	function(v) WorldforgedLoggerDB.enabled = v end)

local cbChat = MakeCheck("WFLCheckChat", "Print to chat", "Show a chat line whenever an item is logged.", 190, -62,
	function() return WorldforgedLoggerDB.printToChat end,
	function(v) WorldforgedLoggerDB.printToChat = v end)

local cbCtx = MakeCheck("WFLCheckContext", "Only world loot", "Only log items that come right after a loot window / gather cast. Turn off to also log Worldforged items obtained any other way (at your current position).", 330, -62,
	function() return WorldforgedLoggerDB.requireContext end,
	function(v) WorldforgedLoggerDB.requireContext = v end)

local cbMissing = MakeCheck("WFLCheckMissing", "Only show items missing in LootCollector", "Hides entries that LootCollector already has (same item on the same map). Applies to the table AND the exports. Needs LootCollector to be loaded.", 16, -88,
	function() return WorldforgedLoggerDB.onlyMissing end,
	function(v) WorldforgedLoggerDB.onlyMissing = v; WFL:RefreshUI() end)

local countText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
countText:SetPoint("TOPLEFT", 20, -122)

local cols = {
	{ label = "Item", x = 22, w = 170 },
	{ label = "ID", x = 196, w = 52 },
	{ label = "Zone (map ID)", x = 252, w = 140 },
	{ label = "X / Y", x = 396, w = 74 },
	{ label = "#", x = 474, w = 26 },
	{ label = "In LootCollector", x = 504, w = 80 },
}
local headerTop = -140
for _, c in ipairs(cols) do
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", panel, "TOPLEFT", c.x, headerTop)
	fs:SetText(c.label)
end

local tableTop = headerTop - 16
local scroll = CreateFrame("ScrollFrame", "WFLScroll", panel, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, tableTop)
scroll:SetSize(570, ROWS * ROW_H)

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 28, -4)
bg:SetTexture(0, 0, 0, 0.35)

local view = {}
local rows = {}

local function ShowRowTooltip(row)
	local e = row.entry
	if not e then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetText(e.name or "?") end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Item ID", tostring(e.id), 1, 0.82, 0, 1, 1, 1)
	if e.rawId and e.rawId ~= e.id then GameTooltip:AddDoubleLine("Looted ID", tostring(e.rawId), 1, 0.82, 0, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Continent / Map ID / iz", format("%d / %d / %d", e.c or 0, e.z or 0, e.iz or 0), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Position", format("%.4f / %.4f", e.x or 0, e.y or 0), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Zone", (e.zone or "") .. ((e.sub and e.sub ~= "") and (" - " .. e.sub) or ""), 1, 0.82, 0, 1, 1, 1)
	if e.target then GameTooltip:AddDoubleLine("Source", e.target, 1, 0.82, 0, 1, 1, 1) end
	GameTooltip:AddDoubleLine("First / last", date("%Y-%m-%d %H:%M", e.t0 or 0) .. " / " .. date("%m-%d %H:%M", e.ls or 0), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to select, then use 'Delete selected'.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

for i = 1, ROWS do
	local row = CreateFrame("Button", nil, panel)
	row:SetSize(560, ROW_H)
	row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
	row:EnableMouseWheel(true)
	row:RegisterForClicks("LeftButtonUp")

	row.hl = row:CreateTexture(nil, "BACKGROUND")
	row.hl:SetAllPoints()
	row.hl:SetTexture(1, 1, 1, 0.12)
	row.hl:Hide()

	row.sel = row:CreateTexture(nil, "BORDER")
	row.sel:SetAllPoints()
	row.sel:SetTexture(0.2, 0.6, 1, 0.3)
	row.sel:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 2, 0)

	local function FS(col)
		local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", col.x - 16, 0)
		fs:SetWidth(col.w)
		fs:SetJustifyH("LEFT")
		return fs
	end
	row.name = FS(cols[1]); row.name:SetPoint("LEFT", row, "LEFT", 24, 0); row.name:SetWidth(166)
	row.id = FS(cols[2])
	row.zone = FS(cols[3])
	row.xy = FS(cols[4])
	row.n = FS(cols[5])
	row.lc = FS(cols[6])

	row:SetScript("OnEnter", function(self) self.hl:Show(); ShowRowTooltip(self) end)
	row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		if self.entry then selected = self.entry; WFL:RefreshUI() end
	end)
	row:SetScript("OnMouseWheel", function(_, delta)
		local sb = _G["WFLScrollScrollBar"]
		sb:SetValue(sb:GetValue() - delta * ROW_H * 2)
	end)
	rows[i] = row
end

function WFL:UpdateRows()
	local offset = FauxScrollFrame_GetOffset(scroll)
	for i = 1, ROWS do
		local row, e = rows[i], view[i + offset]
		row.entry = e
		if e then
			row.name:SetText(WFL.QHex(e.q) .. (e.name or "?") .. "|r")
			row.icon:SetTexture(GetItemIcon(e.id) or GetItemIcon(e.rawId or 0) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.icon:Show()
			row.id:SetText(e.id)
			row.zone:SetText(format("%s (%d)", (e.zone and e.zone ~= "") and e.zone or "?", e.z or 0))
			row.xy:SetText(format("%.1f / %.1f", (e.x or 0) * 100, (e.y or 0) * 100))
			row.n:SetText(e.n or 1)
			row.lc:SetText(StatusText(WFL:LCStatus(e)))
			if e == selected then row.sel:Show() else row.sel:Hide() end
			row:Show()
		else
			row:Hide()
		end
	end
	FauxScrollFrame_Update(scroll, #view, ROWS, ROW_H)
end

scroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() WFL:UpdateRows() end)
end)

function WFL:RefreshUI()
	if not panel:IsVisible() then return end
	view = WFL:GetView()
	local stillThere = false
	for _, e in ipairs(view) do if e == selected then stillThere = true break end end
	if not stillThere then selected = nil end

	local total = #WorldforgedLoggerDB.entries
	if #view == total then
		countText:SetText(format("%d logged item%s", total, total == 1 and "" or "s"))
	else
		countText:SetText(format("%d of %d logged items shown (filter active)", #view, total))
	end
	cbEnable:Refresh(); cbChat:Refresh(); cbCtx:Refresh(); cbMissing:Refresh()
	WFL:UpdateRows()
end

local exportFrame
local function BuildExportFrame()
	local f = CreateFrame("Frame", "WorldforgedLoggerExportFrame", UIParent)
	f:SetSize(640, 440)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:Hide()
	tinsert(UISpecialFrames, "WorldforgedLoggerExportFrame")

	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -18)

	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
	f.hint:SetText("The text is selected - press Ctrl+C to copy it, then paste it into a text file.")

	local sf = CreateFrame("ScrollFrame", "WFLExportScroll", f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 20, -58)
	sf:SetPoint("BOTTOMRIGHT", -40, 52)

	local eb = CreateFrame("EditBox", "WFLExportEditBox", sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	eb:SetFontObject(ChatFontNormal)
	eb:SetMaxLetters(0)
	eb:SetWidth(560)
	eb:SetHeight(300)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
	eb:SetScript("OnTextChanged", function(self, user)
		if user and f.text and self:GetText() ~= f.text then
			self:SetText(f.text) -- read-only
			self:HighlightText()
		end
	end)
	sf:SetScrollChild(eb)
	f.edit = eb

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 24)
	close:SetPoint("BOTTOMRIGHT", -20, 18)
	close:SetText(CLOSE)
	close:SetScript("OnClick", function() f:Hide() end)

	local sel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	sel:SetSize(120, 24)
	sel:SetPoint("RIGHT", close, "LEFT", -8, 0)
	sel:SetText("Select all")
	sel:SetScript("OnClick", function() eb:SetFocus(); eb:HighlightText() end)

	return f
end

local formats = {
	lua = { title = "Export: full data (Lua)", fn = "ExportLua" },
	coord = { title = "Export: LootCollector CoordAuthority rows", fn = "ExportCoordAuthority" },
	csv = { title = "Export: CSV", fn = "ExportCSV" },
}

function WFL:ShowExport(kind)
	local fmt = formats[kind] or formats.lua
	exportFrame = exportFrame or BuildExportFrame()
	local text = WFL[fmt.fn](WFL)
	exportFrame.text = text
	exportFrame.title:SetText(fmt.title)
	exportFrame:Show()
	local eb = exportFrame.edit
	eb:SetText(text)
	local _, lines = text:gsub("\n", "\n")
	eb:SetHeight(math.max(300, (lines + 2) * 14))
	eb:SetFocus()
	eb:HighlightText()
end

local function MakeButton(label, w, x, y, onClick)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(w, 24)
	b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local btnY = tableTop - ROWS * ROW_H - 14
MakeButton("Export (full Lua)", 130, 16, btnY, function() WFL:ShowExport("lua") end)
MakeButton("Export (CoordAuthority)", 160, 152, btnY, function() WFL:ShowExport("coord") end)
MakeButton("Export (CSV)", 110, 318, btnY, function() WFL:ShowExport("csv") end)
MakeButton("Delete selected", 120, 16, btnY - 30, function()
	if selected then WFL:DeleteEntry(selected); selected = nil; WFL:RefreshUI() end
end)
MakeButton("Clear all", 100, 142, btnY - 30, function() StaticPopup_Show("WFL_CLEAR_ALL") end)
MakeButton("Refresh", 90, 248, btnY - 30, function() WFL:RefreshLCIndex(); WFL:RefreshUI() end)

StaticPopupDialogs["WFL_CLEAR_ALL"] = {
	text = "Delete ALL logged Worldforged items? This cannot be undone.",
	button1 = YES, button2 = NO,
	OnAccept = function() WFL:ClearAll(); selected = nil; WFL:RefreshUI() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

panel:SetScript("OnShow", function() WFL:RefreshLCIndex(); WFL:RefreshUI() end)
panel.refresh = function() WFL:RefreshUI() end
panel.okay = function() end
panel.cancel = function() end
panel.default = function() end
InterfaceOptions_AddCategory(panel)

function WFL:OpenOptions()
	InterfaceOptionsFrame_OpenToCategory(panel)
	InterfaceOptionsFrame_OpenToCategory(panel)
end
