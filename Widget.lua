--[[
  Chronolog - Widget
  ------------------
  A small standalone box showing the CURRENT level's stats, independent of the
  main window. Drag to move (position is saved), right-click to hide, hover for
  a full breakdown. Toggle with /chrono widget. Its shown state persists.
]]

local addonName, ns = ...

local FormatTime = ns.FormatTime

local widget

local function GetWidgetDB()
  local db = ns.EnsureDB()
  if type(db.widget) ~= "table" then
    db.widget = { shown = false }
  end
  return db.widget
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
function ns.RefreshWidget()
  if not widget or not widget:IsShown() then return end

  local db = ns.EnsureDB()
  local lvl = ns.state.currentLevel
  local row = ns.GetRow(db, lvl)
  widget.data = { lvl = lvl, row = row }

  widget.title:SetText("Level " .. lvl)
  widget.total:SetText("|cffffffff" .. FormatTime(row.total) .. "|r played")
  ns.UpdateStackedBar(widget.bar, { row.combat, row.travel, row.afk, row.other }, widget.bar.width or 160)
  widget.stat1:SetText(string.format("|cffcfcfcfKills|r %d   |cffcfcfcfQuests|r %d", row.kills, row.quests or 0))
  widget.stat2:SetText(string.format("|cffcfcfcfDungeons|r %d   |cffcfcfcfGrouped|r %s",
    row.dungeons or 0, FormatTime(row.grouped or 0)))
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------
local function ShowTooltip(self)
  local d = self.data
  if not d then return end
  local C = ns.COLORS
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
  GameTooltip:AddLine("Level " .. d.lvl .. " (current)", 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Combat", FormatTime(d.row.combat), C[1][1], C[1][2], C[1][3], 1, 1, 1)
  GameTooltip:AddDoubleLine("Travel", FormatTime(d.row.travel), C[2][1], C[2][2], C[2][3], 1, 1, 1)
  GameTooltip:AddDoubleLine("AFK", FormatTime(d.row.afk), C[3][1], C[3][2], C[3][3], 1, 1, 1)
  GameTooltip:AddDoubleLine("Other", FormatTime(d.row.other), C[4][1], C[4][2], C[4][3], 1, 1, 1)
  GameTooltip:AddDoubleLine("  of which idle", FormatTime(d.row.idle or 0), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Grouped", FormatTime(d.row.grouped or 0), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Kills", tostring(d.row.kills), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Quests", tostring(d.row.quests or 0), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Dungeons", tostring(d.row.dungeons or 0), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Drag to move, right-click to hide.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function BuildWidget()
  widget = CreateFrame("Frame", "ChronologWidget", UIParent)
  widget:SetWidth(180)
  widget:SetHeight(88)
  widget:SetFrameStrata("MEDIUM")
  widget:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  widget:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
  widget:SetClampedToScreen(true)
  widget:EnableMouse(true)
  widget:SetMovable(true)
  widget:RegisterForDrag("LeftButton")
  widget:SetScript("OnDragStart", widget.StartMoving)
  widget:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    local wdb = GetWidgetDB()
    wdb.point, wdb.x, wdb.y = point, x, y
  end)
  widget:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      ns.ToggleWidget(false)
    end
  end)
  widget:SetScript("OnEnter", ShowTooltip)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)

  widget.title = widget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  widget.title:SetPoint("TOPLEFT", widget, "TOPLEFT", 10, -8)
  widget.title:SetTextColor(1, 0.82, 0)

  widget.total = widget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  widget.total:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -10, -11)

  widget.bar = ns.CreateStackedBar(widget, 12)
  widget.bar:SetPoint("TOPLEFT", widget, "TOPLEFT", 10, -28)
  widget.bar:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -10, -28)
  widget.bar.width = 160

  widget.stat1 = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  widget.stat1:SetPoint("TOPLEFT", widget, "TOPLEFT", 10, -50)

  widget.stat2 = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  widget.stat2:SetPoint("TOPLEFT", widget, "TOPLEFT", 10, -68)

  -- Restore saved position.
  local wdb = GetWidgetDB()
  widget:ClearAllPoints()
  if wdb.point then
    widget:SetPoint(wdb.point, UIParent, wdb.point, wdb.x or 0, wdb.y or 0)
  else
    widget:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end

  widget:SetScript("OnShow", function()
    -- keep the bar width in sync once laid out
    local w = widget.bar:GetWidth()
    if w and w > 0 then widget.bar.width = w end
    ns.RefreshWidget()
    widget.elapsed = 0
  end)
  widget:SetScript("OnUpdate", function(self, e)
    self.elapsed = (self.elapsed or 0) + e
    if self.elapsed >= 1 then
      self.elapsed = 0
      local w = self.bar:GetWidth()
      if w and w > 0 then self.bar.width = w end
      ns.RefreshWidget()
    end
  end)
end

-- force = true/false to explicitly show/hide; omit to toggle.
function ns.ToggleWidget(force)
  if not widget then BuildWidget() end
  local wdb = GetWidgetDB()

  local show
  if force == nil then
    show = not widget:IsShown()
  else
    show = force and true or false
  end

  if show then
    widget:Show()
  else
    widget:Hide()
  end
  wdb.shown = show
end

--------------------------------------------------------------------------------
-- Restore on login
--------------------------------------------------------------------------------
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
  local wdb = GetWidgetDB()
  if wdb.shown then
    ns.ToggleWidget(true)
  end
end)
