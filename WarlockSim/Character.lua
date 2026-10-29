-- From a character as the game shows it to something the sim can play. No game API in this file (Reader.lua does the
-- reading); tools/check-character.js runs it outside the game.
--   WL.gearFromSheet    the character sheet's totals -> the sim's "gear" numbers (what is left when the sim's own additions
--                       are taken off again: race, talents, the pet, and the raid buffs that were on you while reading)
--   WL.bestTemplate     the ready build whose talents are closest to yours
--   WL.characterBuild   your talents and pet + a build's priority list = a build the sim can play
local ADDON, WL = ...
local copy, indexOf = WL.copy, WL.indexOf

local function round4(x) return math.floor(x * 10000 + 0.5) / 10000 end

-- sheet: { int, spi, sta, sp, spShadow, spFire, hit, crit, haste, mp5, pierce, spellPen } - totals read off the character
-- (spellPen: added up from the items worn).
-- state: { raceKey, talents, pet, sacrifice, buffs = { buffKey = true }, hitHasSuppression } - as it was while reading.
function WL.gearFromSheet(sheet, state)
  local cfg = copy(WL.DEFAULT_CONFIG)
  for k, b in pairs(cfg.buffs) do b.on = state.buffs and state.buffs[k] and true or false end
  for _, c in pairs(cfg.consumables) do c.on = false end
  local g = { name = 'From your character', sp = 0, shadowSp = 0, fireSp = 0, hitPct = 0, critPct = 0, critIncludesAll = false, hastePct = 0,
              pierce = 0, spellPen = 0, int = 0, spi = 0, sta = 0, mp5 = 0 }
  cfg.gear = g
  cfg.extra = {}
  local build = { talents = state.talents or {}, pet = state.pet, sacrifice = state.sacrifice, oil = 'none', rotation = {} }
  local race = WL.RACES[state.raceKey] and state.raceKey or WL.BASELINE_RACE
  local function solve(field, get, target)
    g[field] = 0
    local a = get(WL.computeStats(build, race, cfg))
    g[field] = 100
    local b = get(WL.computeStats(build, race, cfg))
    local slope = (b - a) / 100
    g[field] = slope ~= 0 and round4((target - a) / slope) or 0
  end
  solve('int', function(s) return s.int end, sheet.int or 0)
  solve('spi', function(s) return s.spi end, sheet.spi or 0)
  solve('sta', function(s) return s.sta end, sheet.sta or 0)
  solve('sp', function(s) return s.sp end, sheet.sp or 0)
  g.shadowSp = math.max(0, round4((sheet.spShadow or sheet.sp or 0) - (sheet.sp or 0)))
  g.fireSp = math.max(0, round4((sheet.spFire or sheet.sp or 0) - (sheet.sp or 0)))
  local supp = WL.talentValue(build, 'suppression', 'hitPct')
  solve('hitPct', function(s) return s.hitPctUncapped end, cfg.combat.baseHitPct + (sheet.hit or 0) + (state.hitHasSuppression and 0 or supp))
  solve('hastePct', function(s) return s.hastePct end, sheet.haste or 0)
  solve('mp5', function(s) return s.mp5 end, sheet.mp5 or 0)
  solve('pierce', function(s) return s.pierce end, sheet.pierce or 0)
  solve('spellPen', function(s) return s.spellPen end, sheet.spellPen or 0)
  solve('critPct', function(s) return s.critPct end, sheet.crit or 0)     -- last: it depends on the Intellect found above
  return g
end

-- The build (of `builds`, a list) that shares the most talent points with `talents`; its key, or nil.
function WL.bestTemplate(talents, builds, pet)
  local best, bestScore
  for i = 1, #builds do
    local b, score = builds[i], 0
    for k, pts in pairs(talents or {}) do score = score + math.min(pts, b.talents[k] or 0) end
    if pet and b.pet == pet then score = score + 0.5 end                -- a tie goes to the build with your demon
    if not bestScore or score > bestScore then best, bestScore = b, score end
  end
  return best and best.key or nil
end

local NEEDS_PET = { searingPainBrand = true, lifeTapPet = true, swapToImp = true, swapToSuccubus = true }
local SWAP_TALENTS = { 'demonicSacrifice', 'demonicPact', 'felDomination' }
-- char: { talents, pet, sacrifice, oil }; template: a build whose priority list is used.
-- Returns the build and a list of plain sentences about what had to be changed.
function WL.characterBuild(char, template)
  local t, notes = char.talents or {}, {}
  local function has(k) return (t[k] or 0) > 0 end
  local b = { key = 'character', short = 'My character', name = 'My character', talents = copy(t), pet = char.pet, sacrifice = char.sacrifice,
              oil = WL.OILS[char.oil or 'none'] and (char.oil or 'none') or 'none', rotation = {}, params = copy(template.params) }
  if b.sacrifice and not has('demonicSacrifice') then
    notes[#notes + 1] = 'No sacrifice: you do not have the Demonic Sacrifice talent.'; b.sacrifice = nil
  end
  if b.sacrifice and b.pet and not has('demonicPact') then
    notes[#notes + 1] = 'A demon is out, so the sacrifice was dropped: keeping both needs Demonic Pact.'; b.sacrifice = nil
  end
  if b.sacrifice and b.pet and b.sacrifice == b.pet then
    notes[#notes + 1] = 'The sacrificed demon cannot be the one that is out: the sacrifice was dropped.'; b.sacrifice = nil
  end
  local dropped = {}
  for i = 1, #template.rotation do
    local a = template.rotation[i]
    local A = WL.ACTIONS[a]
    local ok = A ~= nil
    local g = WL.GATED_ACTIONS[a]
    if ok and g and not has(g) then ok = false end
    if ok and a == 'shadowburnSnF' and not has('shadowburn') then ok = false end
    if ok and a == 'conflagrateSnF' and not has('conflagrate') then ok = false end
    if ok and NEEDS_PET[a] and not b.pet then ok = false end
    if ok and (a == 'swapToImp' or a == 'swapToSuccubus') then
      for j = 1, 3 do if not has(SWAP_TALENTS[j]) then ok = false end end
      if b.pet == (a == 'swapToImp' and 'imp' or 'succubus') then ok = false end
    end
    if ok then
      if not indexOf(b.rotation, a) then b.rotation[#b.rotation + 1] = a end
    elseif A then dropped[#dropped + 1] = WL.actionLabel(template, a) end
  end
  if type(template.actWhen) == 'table' then                    -- conditions on the actions that were kept (Wrack waits for its DoTs)
    for k, w in pairs(template.actWhen) do
      if indexOf(b.rotation, k) then b.actWhen = b.actWhen or {}; b.actWhen[k] = copy(w) end
    end
  end
  local filler                                                 -- a filler with a condition is no filler: the one below it is
  for i = 1, #b.rotation do local A = WL.actionOf(b.rotation[i], b); if A and A.filler then filler = i; break end end
  if not filler then
    b.rotation[#b.rotation + 1] = 'shadowBolt'
    notes[#notes + 1] = 'Shadow Bolt is the filler: you do not have the talent for the filler of "' .. (template.short or template.key or '?') .. '".'
  elseif filler < #b.rotation then
    for i = #b.rotation, filler + 1, -1 do table.remove(b.rotation, i) end
  end
  if #dropped > 0 then notes[#notes + 1] = 'Left out of the priority list (talent or demon missing): ' .. table.concat(dropped, '; ') .. '.' end
  if template.timeline then
    b.timeline = {}
    for i = 1, #template.timeline do
      local e = template.timeline[i]
      local s = WL.SPELLS[e.k]
      if s and not (s.talent and not has(s.talent)) then b.timeline[#b.timeline + 1] = { t = e.t, k = e.k } end
    end
    if #b.timeline == 0 then b.timeline = nil end
  end
  b.params = WL.cleanParams(b.params, b.rotation)
  return b, notes
end

-- ---------- the trinkets and main-hand enchant you wear, for the fight (WL.TRINKET_FX / WL.ENCHANT_FX) ----------
-- worn = { trinket1 = item id, trinket2 = item id, mainHand = item id, mainEnchant = enchant id } (Reader.lua).
WL.FX_SLOTS = { [13] = 'trinket1', [14] = 'trinket2', [16] = 'mainHand' }   -- inventory slot -> the fight's slot name
-- The fight's cfg.gearBuilder for what you wear, or nil when nothing of it has an effect the sim knows.
function WL.wornGearBuilder(worn)
  if type(worn) ~= 'table' then return nil end
  local gb = { on = true, slots = {}, enchants = {} }
  for _, k in ipairs({ 'trinket1', 'trinket2', 'mainHand' }) do if worn[k] then gb.slots[k] = { id = worn[k] } end end
  if worn.mainEnchant then gb.enchants.mainHand = { id = worn.mainEnchant } end
  local c = { gearBuilder = gb }
  if #WL.equippedTrinkets(c) == 0 and #WL.equippedEnchantFx(c) == 0 then return nil end
  return gb
end
-- What you wear with the item in inventory slot `inv` changed to `id` (nil = the slot empty). The enchant stays on the
-- main hand, as the stats of your enchants do in an item sim; an empty main hand has no enchant.
function WL.wornSwap(worn, inv, id)
  local w = copy(worn or {})
  local k = WL.FX_SLOTS[inv]
  if k then w[k] = id end
  return w
end
-- The names of what counts in the fight beyond plain stats, e.g. { 'The Black Book', 'Revelation' }.
function WL.wornEffectNames(worn)
  local gb, out = WL.wornGearBuilder(worn), {}
  if not gb then return out end
  local c = { gearBuilder = gb }
  local t, e = WL.equippedTrinkets(c), WL.equippedEnchantFx(c)
  for i = 1, #t do out[#out + 1] = t[i].fx.name end
  for i = 1, #e do out[#out + 1] = e[i].fx.name end
  return out
end
-- A short text of the effects in a config, for cache keys (the settings snapshot leaves them out).
function WL.fxKey(cfg)
  local gb = cfg and cfg.gearBuilder
  if not gb then return '' end
  local s = gb.slots or {}
  local function id(x) return x and tostring(x.id) or '-' end
  return '|fx:' .. id(s.trinket1) .. ',' .. id(s.trinket2) .. ',' .. id(s.mainHand) .. ',' .. id(gb.enchants and gb.enchants.mainHand)
end

-- Talent points per tree as "21/30/0", and their sum.
function WL.talentSplit(talents)
  local per, total = {}, 0
  for k, pts in pairs(talents or {}) do
    local t = WL.TALENT_BY_KEY[k]
    if t then per[t.tree] = (per[t.tree] or 0) + pts; total = total + pts end
  end
  local parts = {}
  for i = 1, #WL.TREE_ORDER do parts[i] = tostring(per[WL.TREE_ORDER[i]] or 0) end
  return table.concat(parts, '/'), total
end
