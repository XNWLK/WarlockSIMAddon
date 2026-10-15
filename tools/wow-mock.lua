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
    SetPoint = function(self, p, rel) assert(type(p) == 'string', 'SetPoint needs a point name'); if type(rel) == 'table' then self.anchor = rel end end,
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
-- Forever's Escape: handlers asked in turn until one says it used the key (Blizzard_GameMenuEsc.lua)
UISpecialFrames = { 'ItemRefTooltip' }
-- the older way, the one the client of today uses: every listed window that is shown gets hidden
function MOCK.closeSpecialWindows() local found = false; for _, name in pairs(UISpecialFrames) do local f = _G[name]; if f and f:IsShown() then f:Hide(); found = true end end; return found end
GameMenuEscPriority = { Dialog = 1, Menu = 2, AddOn = 8 }
MOCK.escHandlers = {}
function RegisterGameMenuEscHandler(priority, handler) assert(priority and type(handler) == 'function'); MOCK.escHandlers[#MOCK.escHandlers + 1] = handler end
function MOCK.escape() for _, h in ipairs(MOCK.escHandlers) do if h() then return true end end; return false end
Minimap = newObject('Frame', 'Minimap'); Minimap.width = 140
Minimap.GetCenter = function() return 1200, 600 end
Minimap.GetEffectiveScale = function() return 1 end
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

-- items: the item link window, what is equipped, and what the game says about an item
MOCK.items = {
  [1001] = { name = 'Ring of Tests', loc = 'INVTYPE_FINGER', class = 4, sub = 0, api = { ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_POWER_SHORT = 20 },
             lines = { 'Ring of Tests', 'Finger', '+10 Intellect', 'Equip: Increases spell power by 20.', 'Equip: Improves spell hit by 1%.' } },
  [1002] = { name = 'Old Band', loc = 'INVTYPE_FINGER', class = 4, sub = 0, api = { ITEM_MOD_STAMINA_SHORT = 8 },
             lines = { 'Old Band', '+8 Stamina', 'Equip: Increases damage and healing done by magical spells and effects by up to 12.', 'Enchanted: +30 Spell Power' } },
  [1003] = { name = 'Plain Loop', loc = 'INVTYPE_FINGER', class = 4, sub = 0, api = {}, lines = { 'Plain Loop', '+3 Spirit', 'Use: Summons a cat. (10 Min Cooldown)' } },
  [1004] = { name = 'Great Staff', loc = 'INVTYPE_2HWEAPON', class = 2, sub = 10, api = { ITEM_MOD_SPELL_POWER_SHORT = 60, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, lines = { 'Great Staff', 'Two-Hand' } },
  [1005] = { name = 'Short Blade', loc = 'INVTYPE_WEAPONMAINHAND', class = 2, sub = 7, api = { ITEM_MOD_SPELL_POWER_SHORT = 30 }, lines = { 'Short Blade' } },
  [1006] = { name = 'Orb', loc = 'INVTYPE_HOLDABLE', class = 4, sub = 0, api = { ITEM_MOD_SPELL_POWER_SHORT = 15 }, lines = { 'Orb' } },
  [1007] = { name = 'Bread', loc = '', class = 0, sub = 0, api = {}, lines = { 'Bread' } },
  [1008] = { name = 'Robe of Tests', loc = 'INVTYPE_ROBE', class = 4, sub = 1, ench = 1891, api = { ITEM_MOD_INTELLECT_SHORT = 20 },
             lines = { 'Robe of Tests', '+20 Intellect', 'Equip: Improves spell hit by 1%.', 'Enchanted: +4 All Stats' } },
  [1009] = { name = 'Mish\226\128\153undare, Circlet of the Mind Flayer', loc = 'INVTYPE_HEAD', class = 4, sub = 1, ench = 2588, api = { ITEM_MOD_SPELL_POWER_SHORT = 35 },
             lines = { 'Mish\226\128\153undare, Circlet of the Mind Flayer', 'Enchanted: +18 Spell Damage and Healing / +1% Spell Hit', 'Enchanted: Minor Glow' } },
}
MOCK.equipped = { [11] = 1002, [12] = 1003, [16] = 1005, [17] = 1006 }
local function mockItem(info)
  if type(info) == 'number' then return MOCK.items[info], info end
  local id = tonumber(tostring(info):match('item:(%d+)'))
  return MOCK.items[id], id
end
function MOCK.link(id) return '|cffa335ee|Hitem:' .. id .. ':' .. (MOCK.items[id].ench or '') .. ':::::::60:::::|h[' .. MOCK.items[id].name .. ']|h|r' end
ItemRefTooltip = newObject('GameTooltip', 'ItemRefTooltip')
ItemRefTooltip.shown = false
TooltipUtil = { GetDisplayedItem = function(tt) if MOCK.refItem then return MOCK.items[MOCK.refItem].name, MOCK.link(MOCK.refItem), MOCK.refItem end end }
function GetInventoryItemLink(_, slot) local id = MOCK.equipped[slot]; return id and MOCK.link(id) or nil end
function GetInventoryItemID(_, slot) return MOCK.equipped[slot] end
C_Item.GetItemInfoInstant = function(info) local it, id = mockItem(info); if not it then return nil end; return id, 'Type', 'Sub', it.loc, 1, it.class, it.sub end
C_Item.GetItemStats = function(link) local it = mockItem(link); return it and it.api end
C_Item.GetItemNameByID = function(info) local it = mockItem(info); return it and it.name end
C_Item.GetItemQualityByID = function(info) local it = mockItem(info); return it and 4 end
C_TooltipInfo = { GetHyperlink = function(link)
  local it = mockItem(link); if not it then return nil end
  local lines = {}
  for i, t in ipairs(it.lines) do lines[i] = { leftText = t, type = t:find('^Enchanted') and 15 or 0 } end
  return { lines = lines }
end }
Enum = { TooltipDataLineType = { ItemEnchantmentPermanent = 15, GemSocket = 3 } }
ENCHANTED_TOOLTIP_LINE = 'Enchanted: %s'
function GetCombatRatingBonusForCombatRatingValue(id, v) return v / 14 end
ITEM_MOD_INTELLECT, ITEM_MOD_SPIRIT, ITEM_MOD_STAMINA, ITEM_MOD_AGILITY = '%c%s Intellect', '%c%s Spirit', '%c%s Stamina', '%c%s Agility'
ITEM_MOD_SPELL_POWER, ITEM_MOD_HIT_SPELL_RATING, ITEM_MOD_CRIT_SPELL_RATING = 'Increases spell power by %s.', 'Improves spell hit by %s.', 'Improves spell critical strike by %s.'
ITEM_SPELL_TRIGGER_ONEQUIP, ITEM_SPELL_TRIGGER_ONUSE, ITEM_SPELL_TRIGGER_ONPROC, ENCHANTED_TOOLTIP_LINE = 'Equip:', 'Use:', 'Chance on hit:', 'Enchanted: %s'

-- modified clicks on items (the game's own handler, hooked by the addon after the fact), modifier keys, the mouse
function HandleModifiedItemClick(link, itemLocation) return false end
function hooksecurefunc(name, hook)
  local original = _G[name]
  _G[name] = function(...) local a, b, c = original(...); hook(...); return a, b, c end
end
MOCK.keys = {}
function PaperDollItemSlotButton_OnModifiedClick(slot, button)
  if MOCK.keys.shift and not MOCK.keys.alt and not MOCK.keys.ctrl and MOCK.button == 'RightButton' then return end   -- the game's "socket this item" click ends here
  HandleModifiedItemClick(GetInventoryItemLink('player', slot:GetID()), MOCK.wornLocation(slot:GetID()))
end
function MOCK.slot(id) return { GetID = function() return id end } end
function IsAltKeyDown() return MOCK.keys.alt or false end
function IsShiftKeyDown() return MOCK.keys.shift or false end
function IsControlKeyDown() return MOCK.keys.ctrl or false end
function GetCursorPosition() return 640, 360 end
function GetMouseButtonClicked() return MOCK.button or 'LeftButton' end
-- where an item is: a bag slot or an equipment slot (like the game's ItemLocation objects)
function MOCK.bagLocation() return { IsEquipmentSlot = function() return false end } end
function MOCK.wornLocation(slot) return { IsEquipmentSlot = function() return true end, GetEquipmentSlot = function() return slot end } end

-- the character sheet: the frame, the model, and the item slots with their inventory slot numbers
PaperDollFrame = newObject('Frame', 'PaperDollFrame'); PaperDollFrame.shown = false
PaperDollItemsFrame = newObject('Frame', 'PaperDollItemsFrame')
CharacterModelScene = newObject('ModelScene', 'CharacterModelScene')
for name, id in pairs({ Head = 1, Neck = 2, Shoulder = 3, Back = 15, Chest = 5, Wrist = 9, Hands = 10, Waist = 6, Legs = 7, Feet = 8, Finger0 = 11, Finger1 = 12,
                        Trinket0 = 13, Trinket1 = 14, MainHand = 16, SecondaryHand = 17, Ranged = 18 }) do
  local b = newObject('Button', 'Character' .. name .. 'Slot')
  b.GetID = function() return id end
  _G['Character' .. name .. 'Slot'] = b
end
-- the text the addon put over a slot (color codes taken off)
function MOCK.sheetText(id)
  for _, f in ipairs(MOCK.frames) do
    if f.__kind == 'FontString' and f.anchor == _G[MOCK.slotName(id)] then return (f.text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) end
  end
  return nil
end
function MOCK.slotName(id) for _, n in ipairs({ 'Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Finger0', 'Finger1', 'Trinket0', 'Trinket1', 'MainHand', 'SecondaryHand', 'Ranged' }) do
  if _G['Character' .. n .. 'Slot']:GetID() == id then return 'Character' .. n .. 'Slot' end end end
tinsert, tremove = table.insert, table.remove
