-- Items: what an item gives, as the sim's numbers, and your gear with one item swapped for another.
-- No game API in this file (ItemUI.lua asks the game); tools/check-items.js runs it outside the game.
--   WL.itemStats      from the game's stat list of an item and the lines of its tooltip -> { sp = 30, int = 12, hit = 1, ... }
--   WL.gearWithSwap   your gear numbers + the new item - the item(s) it replaces
local ADDON, WL = ...
local copy = WL.copy

-- The sim's stat, and the game's name for it on items. The game's stat list (GetItemStats) uses the name + "_SHORT" as
-- its key; the tooltip shows the text stored under the name itself, e.g. "Improves spell hit by %s.".
-- `rating`: the number may be a rating or a percentage (see WL.itemStats).
local ITEM_STATS = {
  { 'int', 'ITEM_MOD_INTELLECT' }, { 'spi', 'ITEM_MOD_SPIRIT' }, { 'sta', 'ITEM_MOD_STAMINA' }, { 'agi', 'ITEM_MOD_AGILITY' },
  { 'sp', 'ITEM_MOD_SPELL_POWER' }, { 'sp', 'ITEM_MOD_SPELL_DAMAGE_DONE' },
  { 'shadowSp', 'ITEM_MOD_SHADOW_DAMAGE_DONE' }, { 'fireSp', 'ITEM_MOD_FIRE_DAMAGE_DONE' },
  { 'hit', 'ITEM_MOD_HIT_SPELL_RATING', rating = true }, { 'hit', 'ITEM_MOD_HIT_RATING', rating = true },
  { 'crit', 'ITEM_MOD_CRIT_SPELL_RATING', rating = true }, { 'crit', 'ITEM_MOD_CRIT_RATING', rating = true },
  { 'haste', 'ITEM_MOD_HASTE_SPELL_RATING', rating = true }, { 'haste', 'ITEM_MOD_HASTE_RATING', rating = true },
  { 'mp5', 'ITEM_MOD_MANA_REGENERATION' }, { 'mp5', 'ITEM_MOD_POWER_REGEN0' },
  { 'pierce', 'ITEM_MOD_SPELL_PENETRATION' },
}
-- "Equip:" lines of items that still carry the classic wording (English).
local CLASSIC_LINES = {
  { 'sp', 'Increases damage and healing done by magical spells and effects by up to (%d+)' },
  { 'shadowSp', 'Increases damage done by Shadow spells and effects by up to (%d+)' },
  { 'fireSp', 'Increases damage done by Fire spells and effects by up to (%d+)' },
  { 'hit', 'Improves your chance to hit with spells by (%d+)%%', pct = true },
  { 'crit', 'Improves your chance to get a critical strike with spells by (%d+)%%', pct = true },
  { 'mp5', 'Restores (%d+) mana per 5 sec' },
  { 'pierce', 'Decreases the magical resistances of your spell targets by (%d+)' },
}
local RATING = { hit = true, crit = true, haste = true }
WL.ITEM_STAT_ORDER = { 'sp', 'shadowSp', 'fireSp', 'hit', 'crit', 'haste', 'int', 'spi', 'sta', 'agi', 'mp5', 'pierce' }
local STAT_WORDS = { sp = ' spell power', shadowSp = ' Shadow power', fireSp = ' Fire power', hit = '% hit', crit = '% crit', haste = '% haste',
                     int = ' Intellect', spi = ' Spirit', sta = ' Stamina', agi = ' Agility', mp5 = ' mana per 5 s', pierce = ' Spell Pierce' }

-- Where an item goes: the game's "equip location" -> inventory slot numbers (two for rings and trinkets).
WL.ITEM_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_THROWN = { 18 },
}

-- A text of the game with %s / %d in it -> a pattern that finds the number. "%c%s Intellect" -> "^([+-]?[%d.,]+)(%%?) Intellect%.?$"
local patternCache = {}
local function toPattern(fmt)
  local p = patternCache[fmt]
  if p then return p end
  p = fmt:gsub('%%c', ''):gsub('%%%d*%$?[sd]', '\1')
  p = p:gsub('%.$', '')
  p = p:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', function(c) return '%' .. c end)
  p = '^' .. p:gsub('\1', function() return '([%+%-]?[%d%.,]+)(%%?)' end) .. '%.?$'
  patternCache[fmt] = p
  return p
end
local function number(s)
  if not s then return nil end
  return tonumber((s:gsub(',', '')))
end
local function clean(line, prefix)
  local s = line:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('^%s+', ''):gsub('%s+$', '')
  if prefix and prefix ~= '' and s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1):gsub('^%s+', '') end
  return s
end

-- api      the game's stat list of the item ({ ITEM_MOD_INTELLECT_SHORT = 12, ... }) or nil
-- lines    the tooltip's lines as texts (enchant lines left out by the caller)
-- strings  function(name) -> the game's text for that name, or nil
-- toPct    function(stat, rating) -> percent
-- Returns the stats ({ sp = 30, hit = 1, ... }; hit / crit / haste in percent) and the "Equip:" / "Use:" lines that were
-- not understood (they are not counted).
function WL.itemStats(api, lines, strings, toPct)
  strings = strings or function() return nil end
  local fromApi, apiRating, fromTip, tipIsPct = {}, {}, {}, {}
  if type(api) == 'table' then
    for i = 1, #ITEM_STATS do
      local e = ITEM_STATS[i]
      local v = api[e[2] .. '_SHORT']
      if type(v) == 'number' and v ~= 0 then fromApi[e[1]] = (fromApi[e[1]] or 0) + v end
    end
  end
  local equip, use, proc = strings('ITEM_SPELL_TRIGGER_ONEQUIP') or 'Equip:', strings('ITEM_SPELL_TRIGGER_ONUSE') or 'Use:', strings('ITEM_SPELL_TRIGGER_ONPROC') or 'Chance on hit:'
  local unknown = {}
  for li = 1, #(lines or {}) do
    local raw = type(lines[li]) == 'string' and clean(lines[li]) or ''
    local isEquip = raw:sub(1, #equip) == equip
    local s = isEquip and clean(raw, equip) or raw
    local found = false
    for i = 1, #ITEM_STATS do
      local e = ITEM_STATS[i]
      local fmt = strings(e[2])
      if type(fmt) == 'string' and fmt ~= '' then
        local n, pct = s:match(toPattern(fmt))
        n = number(n)
        if n then
          fromTip[e[1]] = (fromTip[e[1]] or 0) + n
          if pct == '%' then tipIsPct[e[1]] = true end
          found = true
          break
        end
      end
    end
    if not found then
      for i = 1, #CLASSIC_LINES do
        local c = CLASSIC_LINES[i]
        local n = number(s:match(c[2]))
        if n then
          fromTip[c[1]] = (fromTip[c[1]] or 0) + n
          if c.pct then tipIsPct[c[1]] = true end
          found = true
          break
        end
      end
    end
    if not found and (isEquip or raw:sub(1, #use) == use or raw:sub(1, #proc) == proc) then unknown[#unknown + 1] = raw end
  end
  local stats = {}
  for i = 1, #WL.ITEM_STAT_ORDER do
    local k = WL.ITEM_STAT_ORDER[i]
    local v
    if RATING[k] then
      -- a percentage written in the tooltip is taken as it stands; a bare number is a rating and goes through the game's conversion
      if fromTip[k] and tipIsPct[k] then v = fromTip[k]
      elseif fromApi[k] then v = toPct and toPct(k, fromApi[k]) or fromApi[k]
      elseif fromTip[k] then v = toPct and toPct(k, fromTip[k]) or fromTip[k] end
    else
      v = fromApi[k] or fromTip[k]
    end
    if v and v ~= 0 then stats[k] = v end
  end
  return stats, unknown
end

-- An enchant's text -> the sim's stats, as for items (hit / crit / haste in percent). The text is what the tooltip shows
-- after "Enchanted:", e.g. "+8 Intellect", "+30 Spell Damage and Healing", "Spell Power +18",
-- "+18 Spell Damage and Healing / +1% Spell Hit", "Mana Regen 4 per 5 sec.". Each part (split at "/" and ",") is read in
-- the game's own item wording first, then by its words. Returns the stats and whether every part was understood.
local function enchantWords(p, toPct)
  local n, pct = p:match('(%d+%.?%d*)(%%?)')
  n = tonumber(n)
  if not n then return {} end
  local lp = p:lower()
  local w = lp:gsub('%d+%.?%d*%%?', ' ')
  local function has(x) return w:find(x, 1, true) ~= nil end
  local function rated(k) return pct == '%' and n or (toPct and toPct(k, n) or n) end
  local s = {}
  if has('all stats') or has('all attributes') then s.int, s.spi, s.sta, s.agi = n, n, n, n
  elseif has('penetration') then s.pierce = n
  elseif has('mana') and (lp:find('per 5', 1, true) or lp:find('every 5', 1, true) or has('regen')) then s.mp5 = n
  elseif has('hit') then s.hit = rated('hit')
  elseif has('crit') then s.crit = rated('crit')
  elseif has('haste') then s.haste = rated('haste')
  elseif has('damage') or has('spell power') then               -- not "+24 Healing Spells": healing alone is no spell power
    if has('shadow') then s.shadowSp = n elseif has('fire') then s.fireSp = n else s.sp = n end
  elseif has('intellect') then s.int = n
  elseif has('spirit') then s.spi = n
  elseif has('stamina') then s.sta = n
  elseif has('agility') then s.agi = n end
  return s
end
function WL.enchantStats(text, strings, toPct)
  local stats, understood = {}, true
  for part in (tostring(text or '') .. '/'):gmatch('([^/,]*)[/,]') do
    local p = part:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if p ~= '' then
      local s = WL.itemStats(nil, { p }, strings, toPct)
      if next(s) == nil then s = enchantWords(p, toPct) end
      if next(s) == nil then understood = false end
      for k, v in pairs(s) do stats[k] = (stats[k] or 0) + v end
    end
  end
  return stats, understood
end

-- gear: the sim's gear numbers; new: the stats of the item put on; olds: a list of the stats of the item(s) taken off.
-- Returns the new gear and the difference per stat. Intellect also moves the sheet's crit (the sim's 60 Int = 1%).
function WL.gearWithSwap(gear, new, olds, cfg)
  local g, d = copy(gear), {}
  for i = 1, #WL.ITEM_STAT_ORDER do
    local k = WL.ITEM_STAT_ORDER[i]
    local v = new[k] or 0
    for j = 1, #olds do v = v - (olds[j][k] or 0) end
    d[k] = v
  end
  g.sp = (g.sp or 0) + d.sp; g.shadowSp = (g.shadowSp or 0) + d.shadowSp; g.fireSp = (g.fireSp or 0) + d.fireSp
  g.int = (g.int or 0) + d.int; g.spi = (g.spi or 0) + d.spi; g.sta = (g.sta or 0) + d.sta; g.agi = (g.agi or 0) + d.agi
  g.hitPct = (g.hitPct or 0) + d.hit
  g.critPct = (g.critPct or 0) + d.crit + d.int * cfg.combat.critPerInt
  g.hastePct = (g.hastePct or 0) + d.haste
  g.mp5 = (g.mp5 or 0) + d.mp5; g.pierce = (g.pierce or 0) + d.pierce
  return g, d
end

-- "+14 spell power, +7 Intellect, -1% hit"; "nothing the sim counts" when all are zero.
function WL.describeStats(d, signed)
  local parts = {}
  for i = 1, #WL.ITEM_STAT_ORDER do
    local k = WL.ITEM_STAT_ORDER[i]
    local v = d[k] or 0
    if math.abs(v) > 1e-9 then
      local n = math.floor(math.abs(v) * 100 + 0.5) / 100
      local text = n == math.floor(n) and string.format('%.0f', n) or tostring(n)
      parts[#parts + 1] = ((v < 0) and '-' or (signed and '+' or '')) .. text .. STAT_WORDS[k]
    end
  end
  if #parts == 0 then return 'nothing the sim counts' end
  return table.concat(parts, ', ')
end
