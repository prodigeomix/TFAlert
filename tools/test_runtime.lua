-- tools/test_runtime.lua
-- Runtime scenario harness for TFAlert. MUST be executed with Lua 5.0.3
-- (tools/bin/lua50/lua50.exe from the HolyPriest toolbase), not a newer Lua.
-- Usage: lua50.exe tools/test_runtime.lua <path-to-TFAlert.lua>

local addonFile = arg and arg[1] or "TFAlert.lua"
local passed, failed = 0, 0

local function check(cond, label)
  if cond then
    passed = passed + 1
    print("  [PASS] " .. label)
  else
    failed = failed + 1
    print("  [FAIL] " .. label)
  end
end

-- ---------------------------------------------------------------------------
-- 1.12.1 client API mocks
-- ---------------------------------------------------------------------------
getglobal = function(n) return _G[n] end
setglobal = function(n, v) _G[n] = v end
BOOKTYPE_SPELL = "spell"
this, arg1 = nil, nil

ChatMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(ChatMessages, m) end }
SoundsPlayed = {}
PlaySound = function(s) table.insert(SoundsPlayed, s) end
SlashCmdList = {}
UIParent = {}

S = {
  class = "DRUID", power = 3, combat = nil, dead = nil,
  buff = nil, buffLeft = 18, knows = 1,
}

UnitClass = function(u) return "Druid", S.class end
UnitPowerType = function(u) return S.power end
UnitIsDeadOrGhost = function(u) return S.dead end
UnitAffectingCombat = function(u) return S.combat end
GetNumShapeshiftForms = function() return 3 end
GetShapeshiftFormInfo = function(i)
  if i == 1 then return "Interface\\Icons\\Ability_Racial_BearForm", "Bear Form", (S.power == 1) and 1 or nil, 1 end
  if i == 2 then return "Interface\\Icons\\Ability_Druid_AquaticForm", "Aquatic Form", nil, 1 end
  if i == 3 then return "Interface\\Icons\\Ability_Druid_CatForm", "Cat Form", (S.power == 3) and 1 or nil, 1 end
end
GetNumSpellTabs = function() return 2 end
GetSpellTabInfo = function(t)
  if t == 1 then return "General", "", 0, 5 end
  return "Feral Combat", "", 5, 10
end
GetSpellTexture = function(i)
  if S.knows and i == 8 then return "Interface\\Icons\\Ability_Mount_JungleTiger" end
  return "Interface\\Icons\\Spell_Nature_HealingTouch"
end
GetSpellName = function(i)
  if S.knows and i == 8 then return "Tiger's Fury", "Rank 4" end
  return "Claw", "Rank 1"
end
GetPlayerBuff = function(i, f)
  if i == 0 and S.buff then return 0 end
  return -1
end
GetPlayerBuffTexture = function(b)
  if b == 0 and S.buff then return "Interface\\Icons\\Ability_Mount_JungleTiger" end
end
GetPlayerBuffTimeLeft = function(b) return S.buffLeft end
UnitBuff = function(u, i)
  if i == 1 and S.buff then return "Interface\\Icons\\Ability_Mount_JungleTiger", 1 end
end

local function newFrame(name)
  local f = { _shown = nil, _scripts = {}, _w = 128, _h = 128, _v = 0, _name = name,
              _p = "CENTER", _rp = "CENTER", _x = 0, _y = 0 }
  function f:SetClampedToScreen() end
  function f:SetFrameStrata() end
  function f:SetMovable() end
  function f:EnableMouse() end
  function f:RegisterForDrag() end
  function f:RegisterEvent() end
  function f:SetWidth(w) self._w = w end
  function f:SetHeight(h) self._h = h end
  function f:GetWidth() return self._w end
  function f:ClearAllPoints() end
  function f:SetPoint(p, rel, rp, x, y) self._p, self._rp, self._x, self._y = p, rp, x, y end
  function f:GetPoint() return self._p, UIParent, self._rp, self._x, self._y end
  function f:Show() self._shown = 1 end
  function f:Hide() self._shown = nil end
  function f:IsVisible() return self._shown end
  function f:SetScript(h, fn) self._scripts[h] = fn end
  function f:GetScript(h) return self._scripts[h] end
  function f:StartMoving() end
  function f:StopMovingOrSizing() end
  function f:SetMinMaxValues() end
  function f:SetValueStep() end
  function f:SetOrientation() end
  function f:SetValue(v) self._v = v; if self._scripts.OnValueChanged then self._scripts.OnValueChanged() end end
  function f:GetValue() return self._v end
  function f:GetName() return self._name end
  function f:CreateTexture()
    local t = {}
    function t:SetAllPoints() end
    function t:SetTexture(p) self.path = p end
    return t
  end
  return f
end

CreateFrame = function(kind, name, parent, template)
  local f = newFrame(name)
  if name then
    _G[name] = f
    local lbl = { SetText = function() end }
    _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"] = lbl, lbl, lbl
  end
  return f
end

-- ---------------------------------------------------------------------------
-- Load addon under Lua 5.0.3
-- ---------------------------------------------------------------------------
print("Interpreter: " .. tostring(_VERSION))
check(_VERSION == "Lua 5.0.3" or _VERSION == "Lua 5.0", "Running on Lua 5.0.x interpreter")

local chunk, err = loadfile(addonFile)
check(chunk ~= nil, "TFAlert.lua compiles under Lua 5.0 (" .. tostring(err) .. ")")
if not chunk then os.exit(1) end
local ok, rerr = pcall(chunk)
check(ok, "TFAlert.lua top-level executes without error " .. tostring(rerr or ""))

-- Simulate XML OnLoad with 'this'
this = newFrame("TFAlertFrame")
TFAlert_OnLoad()
check(this._scripts.OnUpdate ~= nil, "OnLoad registers OnUpdate handler")

local function fire(ev) TFAlert_OnEvent(ev) end
local function visible() return TFAlert and TFAlert:IsVisible() end

fire("VARIABLES_LOADED")
check(TFAlert ~= nil, "Icon frame created on VARIABLES_LOADED")
check(TFAlertDB and TFAlertDB.pixelSize == 128, "SavedVariables defaults applied (128px)")
check(TFAlert.texture.path == "Interface\\Icons\\Ability_Mount_JungleTiger", "Uses Tiger's Fury icon texture")

fire("PLAYER_ENTERING_WORLD")
check(table.getn(ChatMessages) >= 1, "Welcome message printed for Druid")
check(not visible(), "Hidden out of combat")

S.combat = 1; fire("PLAYER_REGEN_DISABLED")
check(visible(), "Shown: combat + Cat Form + no Tiger's Fury")

S.buff = 1; fire("PLAYER_AURAS_CHANGED")
check(not visible(), "Hidden: Tiger's Fury active")

S.buff = nil; fire("PLAYER_AURAS_CHANGED")
check(visible(), "Shown again: Tiger's Fury expired")

S.power = 1; fire("UPDATE_SHAPESHIFT_FORM")
check(not visible(), "Hidden: Bear Form")

S.power = 0; fire("UPDATE_SHAPESHIFT_FORM")
check(not visible(), "Hidden: caster form")

S.power = 3; fire("UPDATE_SHAPESHIFT_FORM")
check(visible(), "Shown: back in Cat Form")

S.dead = 1; fire("PLAYER_DEAD")
check(not visible(), "Hidden: dead")
S.dead = nil; fire("PLAYER_ALIVE")

S.combat = nil; fire("PLAYER_REGEN_ENABLED")
check(not visible(), "Hidden: left combat")

-- OnUpdate throttle path
TFAlert_OnUpdate(0.3)
check(not visible(), "OnUpdate poll keeps icon hidden out of combat")

-- Non-druid
S.class = "WARRIOR"; S.combat = 1; fire("PLAYER_REGEN_DISABLED")
check(not visible(), "Suppressed for non-Druid class")
S.combat = nil; fire("PLAYER_REGEN_ENABLED"); S.class = "DRUID"

-- Spell not learned
S.knows = nil; fire("SPELLS_CHANGED"); S.combat = 1; fire("PLAYER_REGEN_DISABLED")
check(not visible(), "Suppressed when Tiger's Fury not learned")
S.combat = nil; fire("PLAYER_REGEN_ENABLED"); S.knows = 1; fire("SPELLS_CHANGED")

-- /tfmove + slider
SlashCmdList["TFMOVE"]("")
check(visible() and TFAlertScaleSlider:IsVisible(), "/tfmove shows icon and slider")
TFAlertScaleSlider:SetValue(192)
check(TFAlert:GetWidth() == 192 and TFAlertDB.pixelSize == 192, "Slider resizes and saves 192px")
SlashCmdList["TFMOVE"]("")
check(not TFAlertScaleSlider:IsVisible() and not visible(), "/tfmove off hides slider and icon")

SlashCmdList["TFRESET"]("")
check(TFAlertDB.pixelSize == 128 and TFAlertDB.posX == 0, "/tfreset restores defaults")

SlashCmdList["TFTEST"]("")
check(visible(), "/tftest shows preview")
TFAlert_OnUpdate(5.1)
check(not visible(), "/tftest preview expires after 5s")

SlashCmdList["TFSOUND"]("")
SlashCmdList["TFTHRESHOLD"]("3")
check(TFAlertDB.sound and TFAlertDB.threshold == 3, "/tfsound and /tfthreshold saved")
S.combat = 1; S.buff = 1; S.buffLeft = 2; fire("PLAYER_AURAS_CHANGED")
check(visible(), "Early warning shown when buff time left <= threshold")
check(table.getn(SoundsPlayed) >= 1, "Sound played on alert")

SlashCmdList["TFTHRESHOLD"]("abc")
check(TFAlertDB.threshold == 3, "Invalid /tfthreshold input ignored")

local helpOk = pcall(SlashCmdList["TFHELP"], "")
check(helpOk, "/tfhelp runs without error")

print("")
print(string.format("RESULT: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
os.exit(0)
