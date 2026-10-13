-- ============================================================================
-- TFAlert (Tiger's Fury Alert) for Turtle WoW / Vanilla 1.12.1
--
-- Credits & Attribution:
--   - Original Addon (BSAlert-TW): FSuhas / GondoLeon (https://github.com/FSuhas/BSAlert-TW)
--   - Concept & Feature Request: Wonky (for Turtle WoW Feral Druid Tiger's Fury rework)
--   - Adapted & Enhanced by: Open-source community
-- ============================================================================

-- Global references & compatibility aliases
TFAlert = nil
BSAlert = nil
TFAlert_combat = nil
TFAlert_moveMode = false
TFAlert_testMode = false
TFAlert_hasSpell = nil

local testTimer = 0
local updateThrottle = 0

-- ----------------------------------------------------------------------------
-- SavedVariables Management
-- ----------------------------------------------------------------------------
local function LoadSavedData()
  if not TFAlertDB then
    -- Inherit from BSAlertDB if migrating from the original addon
    if BSAlertDB and (BSAlertDB.posX or BSAlertDB.pixelSize) then
      TFAlertDB = {
        posX = BSAlertDB.posX or 0,
        posY = BSAlertDB.posY or 0,
        point = BSAlertDB.point or "CENTER",
        relativePoint = BSAlertDB.relativePoint or "CENTER",
        pixelSize = BSAlertDB.pixelSize or 128,
        combatOnly = true,
        catFormOnly = true,
        threshold = 0,
        sound = false,
      }
    else
      TFAlertDB = {}
    end
  end

  TFAlertDB.posX = TFAlertDB.posX or 0
  TFAlertDB.posY = TFAlertDB.posY or 0
  TFAlertDB.point = TFAlertDB.point or "CENTER"
  TFAlertDB.relativePoint = TFAlertDB.relativePoint or "CENTER"
  TFAlertDB.pixelSize = TFAlertDB.pixelSize or 128
  if TFAlertDB.combatOnly == nil then TFAlertDB.combatOnly = true end
  if TFAlertDB.catFormOnly == nil then TFAlertDB.catFormOnly = true end
  if TFAlertDB.threshold == nil then TFAlertDB.threshold = 0 end
  if TFAlertDB.sound == nil then TFAlertDB.sound = false end

  -- Keep BSAlertDB alias synced
  BSAlertDB = TFAlertDB
end

local function SaveCurrentState()
  if not TFAlert then return end
  local point, relativeTo, relativePoint, x, y = TFAlert:GetPoint()
  TFAlertDB.point = point or "CENTER"
  TFAlertDB.relativePoint = relativePoint or "CENTER"
  TFAlertDB.posX = x or 0
  TFAlertDB.posY = y or 0
  TFAlertDB.pixelSize = TFAlert:GetWidth() or 128
  BSAlertDB = TFAlertDB
end

local function ApplyPixelSize(frame, size)
  if not frame then return end
  local s = math.max(32, math.min(256, size or 128))
  frame:SetWidth(s)
  frame:SetHeight(s)
end

local function ApplyPosition(frame)
  if not frame then return end
  frame:ClearAllPoints()
  local point = TFAlertDB.point or "CENTER"
  local relPoint = TFAlertDB.relativePoint or "CENTER"
  local x = TFAlertDB.posX or 0
  local y = TFAlertDB.posY or 0
  frame:SetPoint(point, UIParent, relPoint, x, y)
end

-- ----------------------------------------------------------------------------
-- Druid & Buff / Spell Detection
-- ----------------------------------------------------------------------------

-- Check if player is currently in Cat Form
local function IsInCatForm()
  -- Cat Form always uses Energy (PowerType 3) in Vanilla 1.12.1
  if UnitPowerType("player") == 3 then
    return true
  end

  -- Stance / Shapeshift bar fallback
  local numForms = GetNumShapeshiftForms()
  if numForms and numForms > 0 then
    for i = 1, numForms do
      local icon, name, active = GetShapeshiftFormInfo(i)
      if (active == 1 or active == true) and icon and string.find(string.lower(icon), "ability_druid_catform") then
        return true
      end
    end
  end

  return false
end

-- Check if Tiger's Fury buff is present and retrieve remaining duration
local function GetTigersFuryStatus()
  -- Check via GetPlayerBuff (provides accurate remaining duration)
  for i = 0, 31 do
    local buffIndex = GetPlayerBuff(i, "HELPFUL")
    if buffIndex and buffIndex > -1 then
      local texture = GetPlayerBuffTexture(buffIndex)
      if texture and string.find(string.lower(texture), "ability_mount_jungletiger") then
        local timeLeft = GetPlayerBuffTimeLeft(buffIndex)
        return true, (timeLeft or 0)
      end
    end
  end

  -- Fallback via UnitBuff
  local i = 1
  while true do
    local texture = UnitBuff("player", i)
    if not texture then break end
    if string.find(string.lower(texture), "ability_mount_jungletiger") then
      return true, 999
    end
    i = i + 1
  end

  return false, 0
end

-- Check if player has learned Tiger's Fury in their spellbook
local function CheckHasTigersFurySpell()
  local _, class = UnitClass("player")
  if class ~= "DRUID" then
    TFAlert_hasSpell = false
    return false
  end

  local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
  if numTabs > 0 then
    for tab = 1, numTabs do
      local _, _, offset, numSpells = GetSpellTabInfo(tab)
      if offset and numSpells then
        for i = offset + 1, offset + numSpells do
          local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
          if tex and string.find(string.lower(tex), "ability_mount_jungletiger") then
            TFAlert_hasSpell = true
            return true
          end
          local name = GetSpellName(i, BOOKTYPE_SPELL)
          if name and string.find(string.lower(name), "tiger") then
            TFAlert_hasSpell = true
            return true
          end
        end
      end
    end
    -- Spellbook tabs scanned and spell not found
    TFAlert_hasSpell = false
    return false
  end

  -- Spellbook tabs not yet ready, assume true for now
  TFAlert_hasSpell = true
  return true
end

-- Determine if the alert icon should be shown
local function TFAlert_ShouldShow()
  if TFAlert_moveMode or TFAlert_testMode then
    return true
  end

  -- Only for Druids
  local _, class = UnitClass("player")
  if class ~= "DRUID" then
    return false
  end

  -- Dead / ghost players should not see alert
  if UnitIsDeadOrGhost("player") then
    return false
  end

  -- Only if the Druid has learned Tiger's Fury
  if TFAlert_hasSpell == false then
    return false
  end

  -- Cat Form requirement (default: true)
  if TFAlertDB.catFormOnly and not IsInCatForm() then
    return false
  end

  -- Combat requirement (default: true)
  local inCombat = TFAlert_combat or UnitAffectingCombat("player")
  if TFAlertDB.combatOnly and not inCombat then
    return false
  end

  -- Buff check: Tiger's Fury
  local hasBuff, timeLeft = GetTigersFuryStatus()
  if not hasBuff then
    return true
  end

  -- Early expiration threshold check (if configured)
  local threshold = TFAlertDB.threshold or 0
  if threshold > 0 and timeLeft <= threshold then
    return true
  end

  return false
end

-- Refresh display state
function TFAlert_Update()
  if not TFAlert then return end

  if TFAlert_moveMode or TFAlert_testMode then
    TFAlert:Show()
    return
  end

  local shouldShow = TFAlert_ShouldShow()

  if shouldShow then
    if not TFAlert:IsVisible() then
      if TFAlertDB.sound then
        PlaySound("TellMessage")
      end
      TFAlert:Show()
    end
  else
    if TFAlert:IsVisible() then
      TFAlert:Hide()
    end
  end
end

-- ----------------------------------------------------------------------------
-- UI Components & Slider
-- ----------------------------------------------------------------------------
local function CreateScaleSlider(parent)
  local slider = CreateFrame("Slider", "TFAlertScaleSlider", parent, "OptionsSliderTemplate")
  slider:SetMinMaxValues(64, 256)
  slider:SetValueStep(16)
  slider:SetOrientation("HORIZONTAL")
  slider:SetWidth(128)
  slider:SetHeight(16)
  slider:SetPoint("TOP", parent, "BOTTOM", 0, -8)

  local low = getglobal(slider:GetName().."Low")
  local high = getglobal(slider:GetName().."High")
  local text = getglobal(slider:GetName().."Text")
  if low then low:SetText("64") end
  if high then high:SetText("256") end
  if text then text:SetText("Size") end

  slider:SetScript("OnValueChanged", function()
    if not TFAlert then return end
    local size = slider:GetValue()
    ApplyPixelSize(TFAlert, size)
    TFAlertDB.pixelSize = size
    SaveCurrentState()
  end)

  slider:Hide()
  return slider
end

local function CreateTFIcon()
  local f = CreateFrame("Frame", "TFAlert", UIParent)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetWidth(128)
  f:SetHeight(128)

  f:SetScript("OnDragStart", function()
    if TFAlert_moveMode then this:StartMoving() end
  end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    SaveCurrentState()
  end)

  -- Tiger's Fury icon texture
  local tex = f:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints(f)
  tex:SetTexture("Interface\\Icons\\Ability_Mount_JungleTiger")
  f.texture = tex

  LoadSavedData()
  ApplyPosition(f)
  ApplyPixelSize(f, TFAlertDB.pixelSize)

  f.scaleSlider = CreateScaleSlider(f)
  f.scaleSlider:SetValue(TFAlertDB.pixelSize)
  f:Hide()

  return f
end

-- ----------------------------------------------------------------------------
-- Event & Update Handlers
-- ----------------------------------------------------------------------------
function TFAlert_OnLoad()
  this:RegisterEvent("VARIABLES_LOADED")
  this:RegisterEvent("PLAYER_ENTERING_WORLD")
  this:RegisterEvent("PLAYER_REGEN_DISABLED")
  this:RegisterEvent("PLAYER_REGEN_ENABLED")
  this:RegisterEvent("PLAYER_AURAS_CHANGED")
  this:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  this:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  this:RegisterEvent("PLAYER_DEAD")
  this:RegisterEvent("PLAYER_ALIVE")
  this:RegisterEvent("PLAYER_UNGHOST")
  this:RegisterEvent("SPELLS_CHANGED")
  this:RegisterEvent("LEARNED_SPELL_IN_TAB")

  this:SetScript("OnUpdate", function()
    TFAlert_OnUpdate(arg1)
  end)
end

function TFAlert_OnEvent(event)
  if event == "VARIABLES_LOADED" then
    LoadSavedData()
    if not TFAlert then
      TFAlert = CreateTFIcon()
      BSAlert = TFAlert
    end
    CheckHasTigersFurySpell()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    LoadSavedData()
    if not TFAlert then
      TFAlert = CreateTFIcon()
      BSAlert = TFAlert
    end
    CheckHasTigersFurySpell()
    local _, class = UnitClass("player")
    if class == "DRUID" then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0aTF|rAlert |cff00ff96Turtle|r: |cff00ffffType /tfhelp|r for options.")
    end
    TFAlert_Update()
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    TFAlert_combat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    TFAlert_combat = nil
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
    CheckHasTigersFurySpell()
  end

  TFAlert_Update()
end

function TFAlert_OnUpdate(elapsed)
  if not elapsed then elapsed = 0 end

  -- Handle test preview timer
  if TFAlert_testMode then
    testTimer = testTimer - elapsed
    if testTimer <= 0 then
      TFAlert_testMode = false
      DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Test preview ended.")
      TFAlert_Update()
    end
    return
  end

  -- Periodic check (every 0.25s) when relevant
  updateThrottle = updateThrottle + elapsed
  if updateThrottle >= 0.25 then
    updateThrottle = 0
    if TFAlert and not TFAlert_moveMode then
      TFAlert_Update()
    end
  end
end

-- Backward compatibility aliases for XML
BSAlert_OnLoad = TFAlert_OnLoad
BSAlert_OnEvent = TFAlert_OnEvent
BSAlert_OnUpdate = TFAlert_OnUpdate

-- ----------------------------------------------------------------------------
-- Slash Commands
-- ----------------------------------------------------------------------------

-- /tfmove (or /bsmove): Toggle edit mode to reposition and resize icon
SLASH_TFMOVE1 = "/tfmove"
SLASH_TFMOVE2 = "/bsmove"
SlashCmdList["TFMOVE"] = function()
  if not TFAlert then return end
  TFAlert_moveMode = not TFAlert_moveMode

  if TFAlert_moveMode then
    TFAlert_testMode = false
    TFAlert:Show()
    TFAlert:EnableMouse(true)
    TFAlert:SetScript("OnMouseDown", TFAlert:GetScript("OnDragStart"))
    TFAlert:SetScript("OnMouseUp", TFAlert:GetScript("OnDragStop"))
    if TFAlert.scaleSlider then
      TFAlert.scaleSlider:SetValue(TFAlertDB.pixelSize)
      TFAlert.scaleSlider:Show()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Edit mode enabled. Drag icon to move, use slider to resize.")
  else
    TFAlert:EnableMouse(false)
    TFAlert:SetScript("OnMouseDown", nil)
    TFAlert:SetScript("OnMouseUp", nil)
    if TFAlert.scaleSlider then
      TFAlert.scaleSlider:Hide()
    end
    TFAlert_Update()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Edit mode disabled.")
  end
end
SlashCmdList["BSMOVE"] = SlashCmdList["TFMOVE"]

-- /tfreset (or /bsreset): Reset position and size
SLASH_TFRESET1 = "/tfreset"
SLASH_TFRESET2 = "/bsreset"
SlashCmdList["TFRESET"] = function()
  if not TFAlert then return end
  TFAlertDB.posX = 0
  TFAlertDB.posY = 0
  TFAlertDB.point = "CENTER"
  TFAlertDB.relativePoint = "CENTER"
  TFAlertDB.pixelSize = 128
  ApplyPosition(TFAlert)
  ApplyPixelSize(TFAlert, 128)
  SaveCurrentState()
  if TFAlert.scaleSlider then
    TFAlert.scaleSlider:SetValue(128)
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Position and size have been reset to center (128px).")
end
SlashCmdList["BSRESET"] = SlashCmdList["TFRESET"]

-- /tftest: Preview icon display for 5 seconds
SLASH_TFTEST1 = "/tftest"
SlashCmdList["TFTEST"] = function()
  if not TFAlert then return end
  if TFAlert_moveMode then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Please disable edit mode (/tfmove) first.")
    return
  end
  TFAlert_testMode = not TFAlert_testMode
  if TFAlert_testMode then
    testTimer = 5
    TFAlert:Show()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Test preview active for 5 seconds.")
  else
    TFAlert_Update()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Test preview stopped.")
  end
end

-- /tfcombat: Toggle alert only in combat
SLASH_TFCOMBAT1 = "/tfcombat"
SlashCmdList["TFCOMBAT"] = function()
  TFAlertDB.combatOnly = not TFAlertDB.combatOnly
  DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Combat-only requirement is now " .. (TFAlertDB.combatOnly and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. ".")
  TFAlert_Update()
end

-- /tfcatform: Toggle Cat Form requirement
SLASH_TFCATFORM1 = "/tfcatform"
SlashCmdList["TFCATFORM"] = function()
  TFAlertDB.catFormOnly = not TFAlertDB.catFormOnly
  DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Cat Form requirement is now " .. (TFAlertDB.catFormOnly and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. ".")
  TFAlert_Update()
end

-- /tfsound: Toggle sound alert
SLASH_TFSOUND1 = "/tfsound"
SlashCmdList["TFSOUND"] = function()
  TFAlertDB.sound = not TFAlertDB.sound
  DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Sound alert is now " .. (TFAlertDB.sound and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. ".")
end

-- /tfthreshold: Set early alert threshold before expiration (0-18 sec)
SLASH_TFTHRESHOLD1 = "/tfthreshold"
SlashCmdList["TFTHRESHOLD"] = function(msg)
  local val = tonumber(msg)
  if val and val >= 0 and val <= 18 then
    TFAlertDB.threshold = val
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Alert threshold set to |cffffff00" .. val .. "s|r before expiration.")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert]:|r Usage: /tfthreshold <0-18> (Current: " .. (TFAlertDB.threshold or 0) .. "s)")
  end
  TFAlert_Update()
end

-- /tfhelp (or /bshelp, /tf): Show help menu
SLASH_TFHELP1 = "/tfhelp"
SLASH_TFHELP2 = "/bshelp"
SLASH_TFHELP3 = "/tf"
SlashCmdList["TFHELP"] = function()
  DEFAULT_CHAT_FRAME:AddMessage("|cffff7d0a[TFAlert Help]|r Available commands:")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfmove|r (or /bsmove) - Toggle edit mode to move and resize the icon.")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfreset|r (or /bsreset) - Reset icon position and size to default.")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tftest|r - Test preview the icon for 5 seconds.")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfcombat|r - Toggle alert only in combat (Currently: " .. (TFAlertDB.combatOnly and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. ")")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfcatform|r - Toggle Cat Form requirement (Currently: " .. (TFAlertDB.catFormOnly and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. ")")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfsound|r - Toggle sound alert on buff drop (Currently: " .. (TFAlertDB.sound and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. ")")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfthreshold <0-18>|r - Early warning before expiration (Currently: " .. (TFAlertDB.threshold or 0) .. "s)")
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/tfhelp|r - Show this help message.")
end
SlashCmdList["BSHELP"] = SlashCmdList["TFHELP"]
SlashCmdList["TF"] = SlashCmdList["TFHELP"]
