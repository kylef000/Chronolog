--[[
  Chronolog - UI
  --------------
  A movable window showing:
    * headline stats about your tracked playtime
    * an aggregate stacked composition bar (combat/travel/afk/other)
    * a scrollable per-level list, each row with its own stacked bar,
      kill count and total time, plus a detailed hover tooltip.
]]

local addonName, ns = ...

local FormatTime = ns.FormatTime

-- Category colors, order: combat, travel, afk, other.
local COLORS = {
  { 0.85, 0.30, 0.30 }, -- combat  (red)
  { 0.30, 0.55, 0.95 }, -- travel  (blue)
  { 0.60, 0.60, 0.62 }, -- afk     (gray)
  { 0.40, 0.75, 0.45 }, -- other   (green)
}
local LABELS = { "Combat", "Travel", "AFK", "Other" }

local ROW_H = 20
local ROW_BAR_W = 170

local frame -- main window
local rows = {} -- pooled per-level row frames
local summaryLines = {}

--------------------------------------------------------------------------------
-- Stacked bar helper
--------------------------------------------------------------------------------
local function CreateStackedBar(parent, height)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(height)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(true)
  bar.bg:SetTexture(0, 0, 0, 0.35)
  bar.segs = {}
  for i = 1, 4 do
    local t = bar:CreateTexture(nil, "ARTWORK")
    local c = COLORS[i]
    t:SetTexture(c[1], c[2], c[3], 1)
    bar.segs[i] = t
  end
  return bar
end

-- vals = {combat, travel, afk, other}
local function UpdateStackedBar(bar, vals, width)
  local sum = (vals[1] or 0) + (vals[2] or 0) + (vals[3] or 0) + (vals[4] or 0)
  local x = 0
  for i = 1, 4 do
    local seg = bar.segs[i]
    local w = (sum > 0) and (vals[i] / sum) * width or 0
    seg:ClearAllPoints()
    if w > 0.5 then
      seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
      seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
      seg:SetWidth(w)
      seg:Show()
      x = x + w
    else
      seg:Hide()
    end
  end
end

-- Shared with Widget.lua
ns.CreateStackedBar = CreateStackedBar
ns.UpdateStackedBar = UpdateStackedBar
ns.COLORS = COLORS
ns.LABELS = LABELS

--------------------------------------------------------------------------------
-- Row pool
--------------------------------------------------------------------------------
local function AcquireRow(index, parent)
  local row = rows[index]
  if row then return row end

  row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_H)
  row:EnableMouse(true)

  row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.level:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.level:SetWidth(40)
  row.level:SetJustifyH("LEFT")

  row.bar = CreateStackedBar(row, ROW_H - 6)
  row.bar:SetPoint("LEFT", row, "LEFT", 46, 0)
  row.bar:SetWidth(ROW_BAR_W)

  row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.kills:SetPoint("LEFT", row.bar, "RIGHT", 10, 0)
  row.kills:SetWidth(52)
  row.kills:SetJustifyH("RIGHT")

  row.quests = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.quests:SetPoint("LEFT", row.kills, "RIGHT", 10, 0)
  row.quests:SetWidth(52)
  row.quests:SetJustifyH("RIGHT")

  row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.time:SetPoint("LEFT", row.quests, "RIGHT", 10, 0)
  row.time:SetWidth(90)
  row.time:SetJustifyH("RIGHT")

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints(true)
  row.highlight:SetTexture(1, 1, 1, 0.06)
  row.highlight:Hide()

  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Level " .. d.lvl, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Combat", FormatTime(d.row.combat), COLORS[1][1], COLORS[1][2], COLORS[1][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("Travel", FormatTime(d.row.travel), COLORS[2][1], COLORS[2][2], COLORS[2][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("AFK", FormatTime(d.row.afk), COLORS[3][1], COLORS[3][2], COLORS[3][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("Other", FormatTime(d.row.other), COLORS[4][1], COLORS[4][2], COLORS[4][3], 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Total time", FormatTime(d.row.total), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Grouped", FormatTime(d.row.grouped or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Mobs killed", tostring(d.row.kills), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Quests turned in", tostring(d.row.quests or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Dungeons completed", tostring(d.row.dungeons or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    GameTooltip:Hide()
  end)

  rows[index] = row
  return row
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
local function pct(part, whole)
  if not whole or whole <= 0 then return "0%" end
  return string.format("%.0f%%", part / whole * 100)
end

function ns.Refresh()
  if not frame or not frame:IsShown() then return end

  local agg = ns.GetAggregate()
  local t = agg.totals
  local db = agg.db

  -- Headline summary lines
  local hours = t.total / 3600
  local kph = (hours > 0) and (t.kills / hours) or 0

  local sinceTxt = db.startLevel and ("Lv " .. db.startLevel) or "?"
  summaryLines[1]:SetText("|cffffd200Tracked playtime:|r " .. FormatTime(t.total)
    .. "   |cff888888(since " .. sinceTxt .. ")|r")
  summaryLines[2]:SetText(string.format("|cffd94c4cCombat|r %s (%s)   |cff4c8cf2Travel|r %s (%s)",
    FormatTime(t.combat), pct(t.combat, t.total), FormatTime(t.travel), pct(t.travel, t.total)))
  summaryLines[3]:SetText(string.format("|cff9a9a9aAFK|r %s (%s)   |cff66bf72Other|r %s (%s)",
    FormatTime(t.afk), pct(t.afk, t.total), FormatTime(t.other), pct(t.other, t.total)))
  summaryLines[4]:SetText(string.format(
    "|cffffd200Mobs killed:|r %d   |cffffd200Quests:|r %d   |cffffd200Dungeons:|r %d",
    t.kills, t.quests, t.dungeons))

  summaryLines[5]:SetText(string.format(
    "|cffffd200Grouped:|r %s (%s)   |cff888888%.1f kills/hr|r",
    FormatTime(t.grouped), pct(t.grouped, t.total), kph))

  local busy = agg.busiestLevel
    and string.format("Lv %d (%.0f%% combat)", agg.busiestLevel, (agg.busiestRatio or 0) * 100) or "-"
  local lazy = agg.laziestLevel
    and string.format("Lv %d (%.0f%% idle)", agg.laziestLevel, (agg.laziestRatio or 0) * 100) or "-"
  summaryLines[6]:SetText("|cffffd200Busiest:|r " .. busy .. "   |cffffd200Laziest:|r " .. lazy)

  -- Aggregate composition bar
  UpdateStackedBar(frame.aggBar, { t.combat, t.travel, t.afk, t.other }, frame.aggBar.width)

  -- Per-level list
  local content = frame.content
  local levels = agg.levels
  local width = frame.scroll:GetWidth()
  if width and width > 0 then content:SetWidth(width) end

  local currentLevel = ns.state.currentLevel
  for i, lvl in ipairs(levels) do
    local row = AcquireRow(i, content)
    local data = db.levels[lvl]
    row.data = { lvl = lvl, row = data }
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW_H)

    if lvl == currentLevel then
      row.level:SetText("|cff00ff00Lv " .. lvl .. "|r")
    else
      row.level:SetText("Lv " .. lvl)
    end
    UpdateStackedBar(row.bar, { data.combat, data.travel, data.afk, data.other }, ROW_BAR_W)
    row.kills:SetText(data.kills > 0 and tostring(data.kills) or "|cff555555-|r")
    row.quests:SetText((data.quests or 0) > 0 and tostring(data.quests) or "|cff555555-|r")
    row.time:SetText(data.total > 0 and FormatTime(data.total) or "|cff555555-|r")
    row:Show()
  end
  for i = #levels + 1, #rows do
    rows[i]:Hide()
  end
  content:SetHeight(math.max(#levels * ROW_H, 1))
end

--------------------------------------------------------------------------------
-- Window construction
--------------------------------------------------------------------------------
local function CreateLegendSwatch(parent, index, anchorTo)
  local sw = parent:CreateTexture(nil, "ARTWORK")
  local c = COLORS[index]
  sw:SetTexture(c[1], c[2], c[3], 1)
  sw:SetWidth(10)
  sw:SetHeight(10)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetText(LABELS[index])
  if anchorTo then
    sw:SetPoint("LEFT", anchorTo, "RIGHT", 12, 0)
  else
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  end
  fs:SetPoint("LEFT", sw, "RIGHT", 3, 0)
  return fs
end

local function BuildWindow()
  frame = CreateFrame("Frame", "ChronologFrame", UIParent)
  frame:SetSize(560, 600)

  -- Restore saved position (falls back to screen center on first use).
  local wdb = ns.EnsureDB()
  frame:ClearAllPoints()
  if wdb.window and wdb.window.point then
    frame:SetPoint(wdb.window.point, UIParent, wdb.window.point, wdb.window.x or 0, wdb.window.y or 0)
  else
    frame:SetPoint("CENTER")
  end

  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    local db = ns.EnsureDB()
    db.window = db.window or {}
    db.window.point, db.window.x, db.window.y = point, x, y
  end)
  frame:SetClampedToScreen(true)
  frame:Hide()
  tinsert(UISpecialFrames, "ChronologFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -14)
  title:SetText("Chronolog")
  frame.title = title

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  -- Summary lines
  local prev
  for i = 1, 6 do
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if prev then
      fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -5)
    else
      fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
    end
    fs:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    summaryLines[i] = fs
    prev = fs
  end

  -- Aggregate composition bar + legend
  local aggLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aggLabel:SetPoint("TOPLEFT", summaryLines[6], "BOTTOMLEFT", 0, -12)
  aggLabel:SetText("|cffffd200Overall composition|r")

  local aggBar = CreateStackedBar(frame, 20)
  aggBar:SetPoint("TOPLEFT", aggLabel, "BOTTOMLEFT", 0, -4)
  aggBar:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
  aggBar.width = 520 - 20 -- approx; recomputed below after layout
  frame.aggBar = aggBar

  aggBar:EnableMouse(true)
  aggBar:SetScript("OnEnter", function(self)
    local t = ns.GetAggregate().totals
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Overall composition", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Combat", FormatTime(t.combat) .. "  (" .. pct(t.combat, t.total) .. ")", COLORS[1][1], COLORS[1][2], COLORS[1][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("Travel", FormatTime(t.travel) .. "  (" .. pct(t.travel, t.total) .. ")", COLORS[2][1], COLORS[2][2], COLORS[2][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("AFK", FormatTime(t.afk) .. "  (" .. pct(t.afk, t.total) .. ")", COLORS[3][1], COLORS[3][2], COLORS[3][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("Other", FormatTime(t.other) .. "  (" .. pct(t.other, t.total) .. ")", COLORS[4][1], COLORS[4][2], COLORS[4][3], 1, 1, 1)
    GameTooltip:AddDoubleLine("  of which idle", FormatTime(t.idle) .. "  (" .. pct(t.idle, t.total) .. ")", 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Total tracked", FormatTime(t.total), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Grouped", FormatTime(t.grouped) .. "  (" .. pct(t.grouped, t.total) .. ")", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:Show()
  end)
  aggBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Legend
  local swatchHolder = CreateFrame("Frame", nil, frame)
  swatchHolder:SetPoint("TOPLEFT", aggBar, "BOTTOMLEFT", 0, -6)
  swatchHolder:SetWidth(400)
  swatchHolder:SetHeight(14)
  local last
  for i = 1, 4 do
    last = CreateLegendSwatch(swatchHolder, i, last)
  end

  -- Column headers (aligned to the row columns in AcquireRow)
  local hdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdr:SetPoint("TOPLEFT", swatchHolder, "BOTTOMLEFT", 2, -10)
  hdr:SetText("Lvl")
  local hdrBar = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrBar:SetPoint("LEFT", hdr, "LEFT", 46, 0)
  hdrBar:SetText("Time composition")
  local hdrKills = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrKills:SetPoint("LEFT", hdr, "LEFT", 46 + ROW_BAR_W + 10, 0)
  hdrKills:SetWidth(52)
  hdrKills:SetJustifyH("RIGHT")
  hdrKills:SetText("Kills")
  local hdrQuests = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrQuests:SetPoint("LEFT", hdrKills, "RIGHT", 10, 0)
  hdrQuests:SetWidth(52)
  hdrQuests:SetJustifyH("RIGHT")
  hdrQuests:SetText("Quests")
  local hdrTime = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrTime:SetPoint("LEFT", hdrQuests, "RIGHT", 10, 0)
  hdrTime:SetWidth(90)
  hdrTime:SetJustifyH("RIGHT")
  hdrTime:SetText("Total")

  -- Scroll list
  local scroll = CreateFrame("ScrollFrame", "ChronologScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 32)
  frame.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  frame.content = content

  -- footer hint
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
  hint:SetText("/chrono help  •  hover a row for details")

  -- live refresh while shown
  frame:SetScript("OnShow", function(self)
    -- fix aggregate bar width now that it's laid out
    local w = self.aggBar:GetWidth()
    if w and w > 0 then self.aggBar.width = w end
    ns.Refresh()
    self.elapsed = 0
  end)
  frame:SetScript("OnUpdate", function(self, e)
    self.elapsed = (self.elapsed or 0) + e
    if self.elapsed >= 1 then
      self.elapsed = 0
      local w = self.aggBar:GetWidth()
      if w and w > 0 then self.aggBar.width = w end
      ns.Refresh()
    end
  end)
end

function ns.ToggleWindow()
  if not frame then BuildWindow() end
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end
