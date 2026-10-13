-- A stand-in for the game, just enough to run the addon's window code outside it (tools/check-ui.js).
-- Frames answer every method; the few that matter (scripts, text, shown, checked) behave like the real ones.
-- It cannot tell whether the window looks right - only that no line of the addon's own code fails.
MOCK = { frames = {}, chat = {}, calls = 0 }

local function newObject(kind, name)
  local o = { __kind = kind, __name = name, scripts = {}, shown = true, text = '', events = {}, width = 100, height = 20 }
  local methods = {
    SetScript = function(self, k, f) self.scripts[k] = f end,
    GetScript = function(self, k) return self.scripts[k] end,
    HookScript = function(self, k, f) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end; f(...) end end,
    Show = function(self) local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end,
    Hide = function(self) local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end,
    SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
    IsShown = function(self) return self.shown end,
    IsVisible = function(self) return self.shown end,
    SetText = function(self, t) assert(type(t) == 'string' or type(t) == 'number', 'SetText needs text, got ' .. type(t)); self.text = tostring(t) end,
    GetText = function(self) return self.text end,
    SetChecked = function(self, v) self.checked = v and true or false end,
    GetChecked = function(self) return self.checked end,
    SetSize = function(self, w, h) assert(type(w) == 'number' and type(h) == 'number', 'SetSize needs numbers'); self.width, self.height = w, h end,
    SetWidth = function(self, w) assert(type(w) == 'number'); self.width = w end,
    SetHeight = function(self, h) assert(type(h) == 'number'); self.height = h end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    GetStringWidth = function(self) return #self.text * 6 end,
    GetPoint = function() return 'CENTER', nil, 'CENTER', 0, 0 end,
    SetPoint = function(self, p) assert(type(p) == 'string', 'SetPoint needs a point name') end,
    HasFocus = function() return false end,
    RegisterEvent = function(self, e) self.events[e] = true end,
    CreateFontString = function(self) return newObject('FontString') end,
    CreateTexture = function(self) return newObject('Texture') end,
    SetValue = function(self, v) assert(type(v) == 'number', 'SetValue needs a number'); self.value = v end,
    SetEnabled = function(self, v) self.enabled = v and true or false end,
    IsEnabled = function(self) return self.enabled ~= false end,
    GetName = function(self) return self.__name end,
  }
  setmetatable(o, { __index = function(t, k)
    if methods[k] then return methods[k] end
    if type(k) == 'string' and k:match('^[A-Z]') then return function() MOCK.calls = MOCK.calls + 1 end end   -- any other method: accepted, does nothing
    return nil
  end })
  MOCK.frames[#MOCK.frames + 1] = o
  return o
end

function CreateFrame(kind, name, parent, template)
  assert(type(kind) == 'string', 'CreateFrame needs a frame type')
  local f = newObject(kind, name)
  f.template = template
  if name then _G[name] = f end
  if kind == 'Frame' and parent == nil then f.shown = true end
  return f
end
UIParent = newObject('Frame', 'UIParent')
GameTooltip = newObject('GameTooltip', 'GameTooltip')
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) MOCK.chat[#MOCK.chat + 1] = m end }
BackdropTemplateMixin = {}
ChatFontNormal = {}
SlashCmdList = {}

function MOCK.fire(event, ...)
  for _, f in ipairs(MOCK.frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
-- one frame of the game: every shown frame's OnUpdate
function MOCK.frame()
  for i = 1, #MOCK.frames do
    local f = MOCK.frames[i]
    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
  end
end
function MOCK.find(kind, text)
  for _, f in ipairs(MOCK.frames) do if f.__kind == kind and f.text == text then return f end end
  error('no ' .. kind .. ' with the text "' .. text .. '"')
end
function MOCK.findLike(kind, pattern)
  for _, f in ipairs(MOCK.frames) do if f.__kind == kind and f.text:find(pattern) then return f end end
  return nil
end
function MOCK.click(text) local b = MOCK.find('Button', text); assert(b.scripts.OnClick, text .. ' has no click handler'); b.scripts.OnClick(b, 'LeftButton') end

-- the game's functions the addon calls
local clock = os.clock
function debugprofilestop() return clock() * 1000 end
function GetTime() return clock() end
time, date = os.time, os.date
function strtrim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
function strsplit(sep, s) local out = {}; for part in (s .. sep):gmatch('(.-)%' .. sep) do out[#out + 1] = part end; return table.unpack(out) end
function issecretvalue() return false end
function InCombatLockdown() return MOCK.combat or false end
function GetBuildInfo() return '1.60.1', '99999', 'Oct 1 2026', 16001 end
function UnitClass() return 'Warlock', MOCK.class or 'WARLOCK' end
function UnitRace() return 'Orc', 'Orc' end
function UnitName() return 'Tester' end
function GetRealmName() return 'Mock' end
function UnitLevel() return MOCK.level or 60 end
function UnitStat(_, i) local v = ({ 60, 62, 430, 420, 260 })[i]; return v - 30, v, 30, 0 end
function GetSpellBonusDamage(school) return 712 + (school == 6 and 21 or 0) end
function GetSpellCritChance(school) return 18.4 + (school == 6 and 5 or 0) end
function GetCombatRatingBonus() return 0 end
function GetSpellHitModifier() return 9 end
function UnitSpellHaste() return 2 end
function GetManaRegen() return 30, 8 end
function GetSpellPenetration() return 0 end
function UnitHealthMax() return 5200 end
function UnitPowerMax() return 7100 end
function UnitExists(u) return u == 'pet' and MOCK.pet ~= nil end
function UnitGUID(u) return u == 'pet' and ('Pet-0-4615-1-959-' .. MOCK.pet .. '-0200320073') or 'Player-1-0001' end
function GetInventoryItemID() return 18873 end
MOCK.pet = '416'
MOCK.auras = { { name = 'Arcane Intellect', spellId = 10157 }, { name = 'Demon Armor', spellId = 11735 }, { name = 'Touch of Shadow', spellId = 18791 }, { name = 'Greater Blessing of Kings', spellId = 25898 } }
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return MOCK.auras[i] end }
C_Spell = { GetSpellName = function(id) return 'Spell ' .. id end, GetSpellTexture = function(id) return 136197 end }
C_Item = { GetItemInfoInstant = function(id) return id, 'Weapon', 'Staves', 'INVTYPE_2HWEAPON', 1, 2, 10 end, GetWeaponEnchantInfo = function() return true, 100000, 0, 2628 end }
C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 777 end }
-- the talent tree: the talents of MOCK.talents (set by the test from a ready build), found by node id
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 5 } } end,
  GetTreeNodes = function() local ids = {}; for i = 1, #WLX.TALENTS do ids[i] = WLX.TALENTS[i].wid end; return ids end,
  GetNodeInfo = function(_, nodeID)
    for i = 1, #WLX.TALENTS do
      local t = WLX.TALENTS[i]
      if t.wid == nodeID then
        local r = MOCK.talents[t.key] or 0
        return { ID = nodeID, activeRank = r, currentRank = r, ranksPurchased = r, maxRanks = t.ranks, entryIDs = { nodeID + 1000000 }, activeEntry = r > 0 and { entryID = nodeID + 1000000, rank = r } or nil }
      end
    end
    return { ID = 0, activeRank = 0, ranksPurchased = 0, maxRanks = 0, entryIDs = {} }
  end,
  GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1 } end,
  GetDefinitionInfo = function(defID) return { spellID = defID + 1 } end,
}
