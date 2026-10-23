
local ADDON_NAME = ...

local WFL = {}
_G.WorldforgedLogger = WFL

local floor, max, abs = math.floor, math.max, math.abs
local format, lower, find = string.format, string.lower, string.find
local tinsert, sort, concat = table.insert, table.sort, table.concat

local PREFIX = "|cff33ff99WFL|r: "
local CONTEXT_WINDOW = 20      
local SAME_SPOT_RADIUS = 0.03  

local defaults = {
	enabled = true,
	printToChat = true,
	requireContext = true,   
	onlyMissing = false,     
	entries = {},
}

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
WFL.Print = Print

local function QHex(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	if not c then return "|cffffffff" end
	return format("|cff%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end
WFL.QHex = QHex

local function Round4(v) return floor((tonumber(v) or 0) * 10000 + 0.5) / 10000 end


local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self)
	local now = GetTime()
	for i = #timers, 1, -1 do
		local t = timers[i]
		if now >= t.at then
			table.remove(timers, i)
			t.fn()
		end
	end
	if #timers == 0 then self:Hide() end
end)
local function After(delay, fn)
	tinsert(timers, { at = GetTime() + delay, fn = fn })
	timerFrame:Show()
end

local function LC() return _G.LootCollector end

local function LCBaseID(id, link)
	local lc = LC()
	if lc and lc.GetBaseItemID then
		local ok, base = pcall(lc.GetBaseItemID, lc, id, link)
		if ok and tonumber(base) and base > 0 then return base end
	end
	return id
end

local function LCKnowsWorldforged(id)
	local lc = LC()
	if lc and lc.IsWorldforgedListItem then
		local ok, res = pcall(lc.IsWorldforgedListItem, lc, id)
		return ok and res and true or false
	end
	return false
end

local function GetPlayerPosition()
	local lc = LC()
	local c, mapID, px, py
	if lc and lc.GetPlayerZoneMapPosition then
		local ok, a, b, x, y = pcall(lc.GetPlayerZoneMapPosition, lc)
		if ok then c, mapID, px, py = a, b, x, y end
	end
	if c == nil then
		local mapOpen = WorldMapFrame and WorldMapFrame:IsVisible()
		local sc, sz, sdl
		if mapOpen then
			sc, sz, sdl = GetCurrentMapContinent(), GetCurrentMapZone(), GetCurrentMapDungeonLevel()
		end
		SetMapToCurrentZone()
		px, py = GetPlayerMapPosition("player")
		mapID = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
		c = GetCurrentMapContinent() or 0
		if mapOpen then
			SetMapZoom(sc, sz)
			if SetDungeonMapLevel and sdl then SetDungeonMapLevel(sdl) end
		end
	end

	local iz = 0
	if lc and lc.GetModule then
		local ok, ZL = pcall(lc.GetModule, lc, "ZoneList", true)
		local info = ok and ZL and ZL.MapDataByID and ZL.MapDataByID[mapID]
		if info then
			c = info.continentID or c
		else
			iz = mapID
		end
	end
	return c or 0, mapID or 0, iz, Round4(px), Round4(py)
end

local scanTip
local function HasWorldforgedTag(link)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "WFLScanTip", nil, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	scanTip:ClearLines()
	scanTip:SetHyperlink(link)
	for i = 2, 8 do
		local fs = _G["WFLScanTipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text and find(lower(text), "worldforged", 1, true) then return true end
	end
	local l1 = _G["WFLScanTipTextLeft1"]
	local t1 = l1 and l1:GetText()
	if not t1 or t1 == "" or t1 == RETRIEVING_ITEM_INFO or t1 == "Retrieving item information..." then
		return nil
	end
	return false
end

function WFL:IsWorldforged(link)
	local id = tonumber(link:match("item:(%d+)"))
	if id and LCKnowsWorldforged(id) then return true end
	return HasWorldforgedTag(link)
end

local ctx          
local chanCtx     

local function Stamp()
	local c, mapID, iz, x, y = GetPlayerPosition()
	local target, targetGUID
	if UnitExists("target") then
		target = UnitName("target")
		targetGUID = UnitGUID("target")
	end
	return {
		t = GetTime(), c = c, z = mapID, iz = iz, x = x, y = y,
		zone = GetRealZoneText() or "", sub = GetSubZoneText() or "",
		target = target, targetGUID = targetGUID,
	}
end

local function Valid(s) return s and (GetTime() - s.t) <= CONTEXT_WINDOW end

local blockerFrames = { "MerchantFrame", "MailFrame", "TradeFrame", "AuctionFrame", "BankFrame", "GuildBankFrame", "QuestFrame" }
local function BlockedByWindow()
	for _, n in ipairs(blockerFrames) do
		local f = _G[n]
		if f and f.IsShown and f:IsShown() then return true end
	end
	return false
end

function WFL:AddEntry(link, stamp, src)
	local rawID = tonumber(link:match("item:(%d+)"))
	if not rawID then return end
	local id = LCBaseID(rawID, link)
	local name, _, quality = GetItemInfo(link)
	name = name or link:match("%[(.-)%]") or ("item:" .. id)
	quality = quality or 1

	local db = WorldforgedLoggerDB
	local now = time()
	local e

	for _, old in ipairs(db.entries) do
		if old.id == id and old.z == stamp.z and abs(old.x - stamp.x) <= SAME_SPOT_RADIUS and abs(old.y - stamp.y) <= SAME_SPOT_RADIUS then
			e = old
			break
		end
	end

	if e then
		e.n = (e.n or 1) + 1
		e.ls = now
		Print(format("%s already logged here (x%d).", name, e.n))
	else
		e = {
			id = id, rawId = rawID, name = name, link = link, q = quality,
			c = stamp.c, z = stamp.z, iz = stamp.iz, x = stamp.x, y = stamp.y,
			zone = stamp.zone, sub = stamp.sub,
			t0 = now, ls = now, n = 1,
			by = UnitName("player"), src = src or "world_loot",
			target = stamp.target, targetGUID = stamp.targetGUID,
		}
		tinsert(db.entries, e)
		if db.printToChat then
			Print(format("logged %s%s|r (ID %d) in %s  %.1f / %.1f", QHex(quality), name, id, stamp.zone ~= "" and stamp.zone or ("map " .. stamp.z), stamp.x * 100, stamp.y * 100))
		end
	end
	if WFL.RefreshUI then WFL:RefreshUI() end
	return e
end

local lastSeen = {}
function WFL:HandleLoot(link, tries, forcedStamp)
	tries = tries or 0
	local db = WorldforgedLoggerDB
	if not db.enabled and not forcedStamp then return end

	local isWF = self:IsWorldforged(link)
	if isWF == nil then
		if tries < 8 then
			After(0.7, function() WFL:HandleLoot(link, tries + 1, forcedStamp) end)
		end
		return
	end
	if not isWF then
		if forcedStamp then Print("That item is not Worldforged (no Worldforged tooltip line).") end
		return
	end

	local stamp = forcedStamp
	if not stamp then
		if Valid(ctx) then
			stamp = ctx
		elseif Valid(chanCtx) then
			stamp = chanCtx
		elseif not db.requireContext then
			stamp = Stamp()
		else
			return 
		end
	end
	self:AddEntry(link, stamp, forcedStamp and "manual" or "world_loot")
end

local function ToPattern(s)
	if not s then return nil end
	s = s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
	s = s:gsub("%%%%s", "(.+)")
	s = s:gsub("%%%%d", "%%d+")
	return "^" .. s .. "$"
end
local otherLootPatterns = { ToPattern(LOOT_ITEM), ToPattern(LOOT_ITEM_PUSHED), ToPattern(LOOT_ITEM_MULTIPLE), ToPattern(LOOT_ITEM_PUSHED_MULTIPLE) }

local function IsOtherPlayersLoot(msg)
	for _, p in ipairs(otherLootPatterns) do
		if p and msg:match(p) then return true end
	end
	return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
	local h = WFL[event]
	if h then h(WFL, ...) end
end)

function WFL:ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	WorldforgedLoggerDB = WorldforgedLoggerDB or {}
	for k, v in pairs(defaults) do
		if WorldforgedLoggerDB[k] == nil then
			if type(v) == "table" then WorldforgedLoggerDB[k] = {} else WorldforgedLoggerDB[k] = v end
		end
	end
	frame:UnregisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("LOOT_OPENED")
	frame:RegisterEvent("UNIT_SPELLCAST_START")
	frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	frame:RegisterEvent("CHAT_MSG_LOOT")
end

function WFL:PLAYER_ENTERING_WORLD()
	ctx, chanCtx = nil, nil
end

function WFL:LOOT_OPENED()
	if not WorldforgedLoggerDB.enabled then return end
	if Valid(chanCtx) then
		ctx = chanCtx
		ctx.t = GetTime()
		if UnitExists("target") then ctx.target, ctx.targetGUID = UnitName("target"), UnitGUID("target") end
	else
		ctx = Stamp()
	end
end

local gatherWords = { "opening", "mining", "herb", "gather", "loot", "skinning", "disenchant", "prospect", "fishing" }
local function OwnGatherCast(unit, spell)
	if unit ~= "player" then return end
	local s = lower(tostring(spell or ""))
	if s == "" then return end
	for _, w in ipairs(gatherWords) do
		if find(s, w, 1, true) then
			if WorldforgedLoggerDB and WorldforgedLoggerDB.enabled then chanCtx = Stamp() end
			return
		end
	end
end
function WFL:UNIT_SPELLCAST_START(unit, spell) OwnGatherCast(unit, spell) end
function WFL:UNIT_SPELLCAST_CHANNEL_START(unit, spell) OwnGatherCast(unit, spell) end

function WFL:CHAT_MSG_LOOT(msg)
	if not WorldforgedLoggerDB.enabled or not msg then return end
	if IsOtherPlayersLoot(msg) then return end
	local link = msg:match("(|c%x+|Hitem:[^|]+|h%[[^%]]-%]|h|r)")
	if not link then return end
	if BlockedByWindow() then return end

	local now = GetTime()
	if lastSeen[link] and now - lastSeen[link] < 1 then return end
	lastSeen[link] = now

	self:HandleLoot(link)
end

local lcIndex, lcIndexTime
function WFL:RefreshLCIndex()
	lcIndex, lcIndexTime = nil, GetTime()
	local lc = LC()
	if not (lc and lc.GetDiscoveriesDB) then return end
	local ok, db = pcall(lc.GetDiscoveriesDB, lc)
	if not ok or type(db) ~= "table" then return end
	local idx = {}
	for _, rec in pairs(db) do
		if type(rec) == "table" and rec.i then
			local t = idx[rec.i]
			if not t then t = {}; idx[rec.i] = t end
			t[tonumber(rec.z) or 0] = true
		end
	end
	lcIndex = idx
end

function WFL:LCStatus(e)
	if not lcIndexTime or GetTime() - lcIndexTime > 20 then self:RefreshLCIndex() end
	if not lcIndex then return nil end
	local t = lcIndex[e.id]
	if not t then return "no" end
	if t[e.z] then return "yes" end
	return "other"
end

function WFL:GetView()
	local view = {}
	local onlyMissing = WorldforgedLoggerDB.onlyMissing
	for _, e in ipairs(WorldforgedLoggerDB.entries) do
		if not onlyMissing or self:LCStatus(e) ~= "yes" then
			tinsert(view, e)
		end
	end
	sort(view, function(a, b) return (a.ls or 0) > (b.ls or 0) end)
	return view
end

function WFL:DeleteEntry(entry)
	local list = WorldforgedLoggerDB.entries
	for i = #list, 1, -1 do
		if list[i] == entry then table.remove(list, i) return true end
	end
end

function WFL:ClearAll()
	wipe(WorldforgedLoggerDB.entries)
end

local function Date(t) return date("%Y-%m-%d %H:%M:%S", t or time()) end

function WFL:ExportLua()
	local view = self:GetView()
	local out = { format("-- Worldforged Logger export, %s, %d entries", Date(), #view),
		"-- c = continent, z = map area ID, iz = instance zone (0 = outdoor), x/y = map position 0..1",
		"WorldforgedLoggerExport = {" }
	for _, e in ipairs(view) do
		local st = self:LCStatus(e)
		out[#out + 1] = format("\t{ id = %d, name = %q, c = %d, z = %d, iz = %d, x = %.4f, y = %.4f, zone = %q, sub = %q, count = %d, found = %q, last = %q, by = %q%s%s },",
			e.id, e.name or "", e.c or 0, e.z or 0, e.iz or 0, e.x or 0, e.y or 0, e.zone or "", e.sub or "", e.n or 1,
			Date(e.t0), Date(e.ls), e.by or "",
			e.target and format(", target = %q", e.target) or "",
			st and format(", inLootCollector = %q", st) or "")
	end
	out[#out + 1] = "}"
	return concat(out, "\n")
end

function WFL:ExportCoordAuthority()
	local view = self:GetView()
	local out = { format("-- Worldforged Logger -> LootCollector CoordAuthority rows, %s", Date()),
		"-- paste into L.CoordAuthority in Modules\\CoordAuthority.lua and bump CoordAuthorityRevision",
		"-- (only ONE spawn per item+map is possible there; extra spawns are commented out)" }
	-- oldest first so the first spawn wins
	local sorted = {}
	for _, e in ipairs(view) do sorted[#sorted + 1] = e end
	sort(sorted, function(a, b) return (a.t0 or 0) < (b.t0 or 0) end)
	local seen = {}
	for _, e in ipairs(sorted) do
		local key = e.id .. ":" .. e.z
		local line = format("[%d] = { [%d] = { c = %d, x = %.4f, y = %.4f } }, -- %s, %s", e.id, e.z or 0, e.c or 0, e.x or 0, e.y or 0, e.name or "?", e.zone ~= "" and e.zone or ("map " .. (e.z or 0)))
		if seen[key] then
			out[#out + 1] = "-- (other spawn) " .. line
		else
			out[#out + 1] = "    " .. line
			seen[key] = true
		end
	end
	return concat(out, "\n")
end

function WFL:ExportCSV()
	local view = self:GetView()
	local out = { "itemID,name,continent,mapID,iz,x,y,zone,subzone,count,firstSeen,lastSeen,finder,inLootCollector" }
	local function q(s) return '"' .. tostring(s or ""):gsub('"', '""') .. '"' end
	for _, e in ipairs(view) do
		out[#out + 1] = concat({
			e.id, q(e.name), e.c or 0, e.z or 0, e.iz or 0, format("%.4f", e.x or 0), format("%.4f", e.y or 0),
			q(e.zone), q(e.sub), e.n or 1, q(Date(e.t0)), q(Date(e.ls)), q(e.by), q(self:LCStatus(e) or "n/a"),
		}, ",")
	end
	return concat(out, "\n")
end

SLASH_WORLDFORGEDLOGGER1 = "/wfl"
SLASH_WORLDFORGEDLOGGER2 = "/wflog"
SlashCmdList["WORLDFORGEDLOGGER"] = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = lower(cmd or "")
	if cmd == "add" then
		local link = rest:match("(|c%x+|Hitem:[^|]+|h%[[^%]]-%]|h|r)")
		if not link then Print("Usage: /wfl add [item link]  (logs it at your current position)") return end
		WFL:HandleLoot(link, 0, Stamp())
	elseif cmd == "export" then
		if WFL.ShowExport then WFL:ShowExport("lua") end
	elseif cmd == "count" then
		Print(#WorldforgedLoggerDB.entries .. " entries logged.")
	else
		if WFL.OpenOptions then WFL:OpenOptions() end
	end
end
