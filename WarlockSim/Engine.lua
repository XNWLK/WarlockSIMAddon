-- The DPS sim's rules outside the fight loop, carried over from the sim's engine/*.js function by function:
-- rng.js, stats.js, spelltable.js, resist.js, rotation.js, custom-builds.js and settings-code.js.
-- Same formulas, same order of additions, same random numbers: tools/check-engine.js compares both engines fight by fight.
-- No game API in this file (it also runs outside the game in the check).
local ADDON, WL = ...

local floor, ceil, min, max, abs, huge = math.floor, math.ceil, math.min, math.max, math.abs, math.huge
local bxor, bor = bit.bxor, bit.bor
local TWO32 = 4294967296

-- ---------------------------------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------------------------------
local function copy(v)
  if type(v) ~= 'table' then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return setmetatable(o, getmetatable(v))
end
WL.copy = copy

local function indexOf(list, v)
  if list then for i = 1, #list do if list[i] == v then return i end end end
  return nil
end
WL.indexOf = indexOf

local function round(x) return floor(x + 0.5) end           -- Math.round
local function roundTo(x, d) return floor(x * d + 0.5) / d end -- +x.toFixed(n) for the values used here
WL.round = round

-- ---------------------------------------------------------------------------------------------------------------------
-- rng.js: seeded PRNG (mulberry32). All values are kept as unsigned 32-bit numbers.
-- ---------------------------------------------------------------------------------------------------------------------
local function imul(a, b)
  local ah, al = floor(a / 65536), a % 65536
  local bh, bl = floor(b / 65536), b % 65536
  return (((ah * bl + al * bh) % 65536) * 65536 + al * bl) % TWO32
end
-- Written out in full (the two 32-bit multiplications, see imul above, and the shifts as divisions): it is called a few
-- hundred times a fight and every function call counts.
function WL.makeRng(seed)
  local a = floor(seed) % TWO32
  return function()
    a = (a + 0x6D2B79F5) % TWO32
    local x = bxor(a, (a - a % 32768) / 32768) % TWO32
    local y = bor(a, 1) % TWO32
    local xl, yl = x % 65536, y % 65536
    local t = ((((x - xl) / 65536 * yl + xl * ((y - yl) / 65536)) % 65536) * 65536 + xl * yl) % TWO32
    x = bxor(t, (t - t % 128) / 128) % TWO32
    y = bor(t, 61) % TWO32
    xl, yl = x % 65536, y % 65536
    t = bxor(t, (t + ((((x - xl) / 65536 * yl + xl * ((y - yl) / 65536)) % 65536) * 65536 + xl * yl) % TWO32) % TWO32) % TWO32
    return (bxor(t, (t - t % 16384) / 16384) % TWO32) / TWO32
  end
end
function WL.xorSeed(a, b) return bxor(a % TWO32, b) % TWO32 end

-- ---------------------------------------------------------------------------------------------------------------------
-- data set-up
-- ---------------------------------------------------------------------------------------------------------------------
WL.TALENT_BY_KEY = {}
for i = 1, #WL.TALENTS do WL.TALENT_BY_KEY[WL.TALENTS[i].key] = WL.TALENTS[i] end
WL.BUILD_BY_KEY = {}
for i = 1, #WL.BUILDS do WL.BUILD_BY_KEY[WL.BUILDS[i].key] = WL.BUILDS[i] end

local function setOf(list) local s = {}; for i = 1, #list do s[list[i]] = true end; return s end
local PANDEMIC, NIGHTFALL = setOf(WL.PANDEMIC_SPELLS), setOf(WL.NIGHTFALL_SPELLS)
WL.NIGHTFALL_SET = NIGHTFALL
WL.SOUL_SIPHON_SET = setOf(WL.SOUL_SIPHON_EFFECTS)
WL.WRACK_DEBUFF_SET = setOf(WL.SPELLS.wrack.debuffSpells)

function WL.spellsFor(cfg)
  if not (cfg and cfg.options and cfg.options.bookRanks) then return WL.SPELLS end
  if not WL._bookSpells then
    local s = {}
    for k, v in pairs(WL.SPELLS) do s[k] = v end
    for k, v in pairs(WL.BOOK_SPELLS) do s[k] = v end
    WL._bookSpells = s
  end
  return WL._bookSpells
end
function WL.isShadowBolt(k) return k == 'shadowBolt' end

-- ---------------------------------------------------------------------------------------------------------------------
-- stats.js
-- ---------------------------------------------------------------------------------------------------------------------
function WL.talentValue(build, key, field)
  local pts = build.talents[key] or 0
  if pts == 0 then return 0 end
  if not field then return pts end
  return WL.TALENT_BY_KEY[key].v[field][pts]
end

function WL.buffExcl(b)
  if not b or not b.excl then return {} end
  if type(b.excl) == 'table' then return b.excl end
  return { b.excl }
end
function WL.buffsClash(a, b)
  if a == b then return false end
  local x, y = WL.buffExcl(a), WL.buffExcl(b)
  for i = 1, #y do if indexOf(x, y[i]) then return true end end
  return false
end
function WL.activeBuffs(cfg)
  local B, seen, out = cfg.buffs or {}, {}, {}
  for i = 1, #WL.BUFF_ORDER do
    local b = B[WL.BUFF_ORDER[i]]
    if b and b.on and not (b.requires and not (B[b.requires] and B[b.requires].on)) then
      local x, clash = WL.buffExcl(b), false
      for j = 1, #x do if seen[x[j]] then clash = true end end
      if not clash then
        for j = 1, #x do seen[x[j]] = true end
        out[#out + 1] = b
      end
    end
  end
  return out
end

function WL.activeConsumables(cfg)
  local C, seen, prof, out = cfg.consumables or {}, {}, cfg.professions or {}, {}
  for i = 1, #WL.CONSUMABLE_ORDER do
    local k = WL.CONSUMABLE_ORDER[i]
    local c = C[k]
    if c and c.on and not seen[c.group] and not (c.requires and not prof[c.requires]) then
      seen[c.group] = true
      c.key = k
      out[#out + 1] = c
    end
  end
  return out
end

function WL.weaponEffects(build, cfg)
  local act, out = WL.activeConsumables(cfg), {}
  local stone, w
  for i = 1, #act do
    if not stone and act[i].group == 'stone' then stone = act[i] end
    if not w and act[i].group == 'weapon' then w = act[i] end
  end
  if not cfg.consumables or next(cfg.consumables) == nil then stone = { buildOil = true } end
  if stone and stone.buildOil and WL.OILS[build.oil] and build.oil ~= 'none' then out[#out + 1] = WL.OILS[build.oil] end
  if w and w.oil then out[#out + 1] = { name = w.name, sp = w.oil.sp or 0, critPct = w.oil.critPct or 0, mp5 = w.oil.mp5 or 0, hastePct = 0 } end
  return out
end

function WL.bossArmor(cfg)
  local D, byGroup, groups, loose = cfg.debuffs or {}, {}, {}, 0
  for i = 1, #WL.DEBUFF_ORDER do
    local d = D[WL.DEBUFF_ORDER[i]]
    if d and d.on and d.armor and d.armor ~= 0 then
      if d.group then
        if byGroup[d.group] == nil then groups[#groups + 1] = d.group end
        byGroup[d.group] = max(byGroup[d.group] or 0, d.armor)
      else loose = loose + d.armor end
    end
  end
  local grouped = 0
  for i = 1, #groups do grouped = grouped + byGroup[groups[i]] end
  return max(0, cfg.combat.bossArmor - grouped - loose)
end
function WL.armorReduction(cfg)
  local a = WL.bossArmor(cfg)
  return a / (a + 400 + 85 * 60)
end

local function racialOf(race, effect)
  local r = race.racials
  for i = 1, #r do if r[i].effect == effect then return r[i] end end
  return nil
end
WL.racialOf = racialOf

function WL.computeStats(build, raceKey, cfg)
  local race, base, gear, cb = WL.RACES[raceKey], WL.WARLOCK_BASE_60, cfg.gear, cfg.combat
  local function tv(k, f) return WL.talentValue(build, k, f) end
  local oils = WL.weaponEffects(build, cfg)
  local bd = {}
  local function add(stat, source, value)
    if value and value ~= 0 then bd[#bd + 1] = { stat = stat, source = source, value = value } end
    return value
  end
  local function oilStat(stat, f)
    local sum = 0
    for i = 1, #oils do sum = sum + add(stat, oils[i].name, oils[i][f or stat] or 0) end
    return sum
  end
  local function racial(effect) return racialOf(race, effect) end

  -- Primary stats. Buffs that share a `group` do not stack: only the biggest value of a stat counts.
  local act = WL.activeBuffs(cfg)
  local function buffStat(s)
    local sum, best = 0, {}
    for i = 1, #act do
      local b = act[i]
      if b[s] and b[s] ~= 0 and b.group and (not best[b.group] or b[s] > best[b.group][s]) then best[b.group] = b end
    end
    for i = 1, #act do
      local b = act[i]
      if b[s] and b[s] ~= 0 and (not b.group or best[b.group] == b) then sum = sum + add(s, b.name, b[s]) end
    end
    return sum
  end
  local cons = {}
  do
    local all = WL.activeConsumables(cfg)
    for i = 1, #all do if all[i].group ~= 'weapon' and all[i].group ~= 'stone' then cons[#cons + 1] = all[i] end end
  end
  local function conStat(s)
    local sum = 0
    for i = 1, #cons do local c = cons[i]; if c[s] and c[s] ~= 0 then sum = sum + add(s, c.name, c[s]) end end
    return sum
  end
  -- Crit from consumables: items that share a critGroup do not stack their crit.
  local function conCrit()
    local sum, best = 0, {}
    for i = 1, #cons do
      local c = cons[i]
      if c.critPct and c.critPct ~= 0 and c.critGroup and (not best[c.critGroup] or c.critPct > best[c.critGroup].critPct) then best[c.critGroup] = c end
    end
    for i = 1, #cons do
      local c = cons[i]
      if c.critPct and c.critPct ~= 0 then
        if not c.critGroup then sum = sum + add('critPct', c.name, c.critPct)
        elseif best[c.critGroup] == c then sum = sum + add('critPct', c.name, c.critPct) end
      end
    end
    return sum
  end
  local kingsPct = 0
  for i = 1, #act do kingsPct = kingsPct + (act[i].statPct or 0) end
  local ex = cfg.extra or {}
  local intFlat = add('int', 'Base (level 60 Warlock)', base.int) + add('int', race.name, race.offset.int)
          + add('int', 'Gear', gear.int) + buffStat('int') + conStat('int') + add('int', 'Stat-weight test', ex.int or 0)
  local int = intFlat * (1 + kingsPct / 100)
  if kingsPct ~= 0 then add('int', 'Blessing of Kings', int - intFlat) end
  local spiFlat = add('spi', 'Base (level 60 Warlock)', base.spi) + add('spi', race.name, race.offset.spi)
          + add('spi', 'Gear', gear.spi) + buffStat('spi') + conStat('spi')
  local spiPct = racial('spiritPct') and racial('spiritPct').value or 0
  local spi = spiFlat * (1 + spiPct / 100) * (1 + kingsPct / 100)
  if spiPct ~= 0 then add('spi', 'The Human Spirit', spiFlat * spiPct / 100) end
  if kingsPct ~= 0 then add('spi', 'Blessing of Kings', spi - spiFlat * (1 + spiPct / 100)) end
  local staFlat = add('sta', 'Base (level 60 Warlock)', base.sta) + add('sta', race.name, race.offset.sta)
          + add('sta', 'Gear', gear.sta) + buffStat('sta') + conStat('sta')
  local staPct = tv('demonicEmbrace', 'staPct')
  local sta = staFlat * (1 + staPct / 100) * (1 + kingsPct / 100)
  if staPct ~= 0 then add('sta', 'Demonic Embrace', staFlat * staPct / 100) end
  if kingsPct ~= 0 then add('sta', 'Blessing of Kings', sta - staFlat * (1 + staPct / 100)) end

  local agiFlat = add('agi', 'Base (level 60 Warlock)', base.agi or 0) + add('agi', race.name, race.offset.agi or 0)
          + add('agi', 'Gear', gear.agi or 0) + buffStat('agi') + conStat('agi')
  local agi = agiFlat * (1 + kingsPct / 100)
  if kingsPct ~= 0 then add('agi', 'Blessing of Kings', agi - agiFlat) end

  -- Pools
  local manaFlat = base.mana + 20 + cb.manaPerInt * (int - 20)
  local manaPct = tv('felVitality', 'manaPct') + (racial('manaPct') and racial('manaPct').value or 0)
  local maxMana = manaFlat * (1 + manaPct / 100)
  maxMana = maxMana + conStat('maxMana')
  local maxHealth = base.health + 20 + 10 * (sta - 20)

  -- Pet state
  local petActive = build.pet ~= nil and build.pet ~= false
  local sacrificeActive = (build.sacrifice ~= nil and build.sacrifice ~= false) and (not petActive or tv('demonicPact') > 0)

  -- Spell power
  local sp = add('sp', 'Gear', gear.sp) + add('sp', 'Stat-weight test', ex.sp or 0) + conStat('sp') + oilStat('sp')
  local dkSp = 0
  if petActive and tv('demonicKnowledge') ~= 0 then
    dkSp = round(60 * tv('demonicKnowledge', 'levelPct') / 100)
    sp = sp + add('sp', 'Demonic Knowledge', dkSp)
  end
  local schoolSp = { shadow = add('shadowSp', 'Gear', gear.shadowSp or 0), fire = add('fireSp', 'Gear', gear.fireSp or 0) }
  for i = 1, #oils do
    local o = oils[i]
    if o.schoolSp then for s, v in pairs(o.schoolSp) do schoolSp[s] = (schoolSp[s] or 0) + add(s .. 'Sp', o.name, v) end end
  end
  for i = 1, #cons do
    local c = cons[i]
    if c.schoolSp then for s, v in pairs(c.schoolSp) do schoolSp[s] = (schoolSp[s] or 0) + add(s .. 'Sp', c.name, v) end end
  end

  -- Hit
  local hitRaw = add('hitPct', 'Base against a level 63 boss', cb.baseHitPct)
             + add('hitPct', 'Suppression', tv('suppression', 'hitPct'))
             + add('hitPct', 'Gear', gear.hitPct or 0)
             + add('hitPct', 'Stat-weight test', ex.hitPct or 0) + conStat('hitPct')
  local hitPct = min(cb.maxHitPct, hitRaw)

  -- Crit: gear.critPct is the character-sheet total (base + Int + gear); extra Int from buffs adds crit on top.
  local intAboveSheet = int - (base.int + race.offset.int + gear.int)
  local critPct = add('critPct', 'Character sheet', gear.critPct or 0)
              + add('critPct', 'Extra Intellect', intAboveSheet * cb.critPerInt)
              + add('critPct', 'Stat-weight test', ex.critPct or 0)
  critPct = critPct + (buffStat('critPct') + conCrit())
  if not gear.critIncludesAll then
    critPct = critPct + oilStat('critPct')
    local rc = racial('critPct')                                         -- Ruthless (Human), Savage (Orc)
    if rc then critPct = critPct + add('critPct', rc.name, rc.value) end
  end

  -- Melee crit: 2.0% + Agility / 20 + Ruthless / Savage; no spell-crit sources.
  local agiPer = cb.agiPerMeleeCrit
  if not agiPer or agiPer == 0 then agiPer = 20 end
  local meleeCritPct = add('meleeCritPct', 'Base (level 60 Warlock)', cb.meleeCritBasePct ~= nil and cb.meleeCritBasePct or 2)
                   + add('meleeCritPct', 'Agility', agi / agiPer)
  local rcM = racial('critPct')
  if rcM then meleeCritPct = meleeCritPct + add('meleeCritPct', rcM.name, rcM.value) end

  -- Haste, Spell Pierce, MP5
  local hastePct = add('hastePct', 'Gear', gear.hastePct or 0)
               + add('hastePct', 'Stat-weight test', ex.hastePct or 0)
               + oilStat('hastePct') + conStat('hastePct')
  local pierce = add('pierce', 'Gear', gear.pierce or 0) + add('pierce', 'Stat-weight test', ex.pierce or 0)
  local mp5 = add('mp5', 'Gear', gear.mp5 or 0) + buffStat('mp5') + conStat('mp5') + oilStat('mp5')

  -- Static caster damage auras per school (they multiply with each other and with the talent spell modifiers).
  local mult = { shadow = 1, fire = 1, all = 1 }
  local function mul(school, source, pct)
    if pct and pct ~= 0 then mult[school] = mult[school] * (1 + pct / 100); add(school .. 'DmgPct', source, pct) end
  end
  if sacrificeActive and build.sacrifice == 'imp' then mul('shadow', 'Demonic Sacrifice (Imp)', 15) end
  if sacrificeActive and build.sacrifice == 'succubus' then mul('fire', 'Demonic Sacrifice (Succubus)', 15) end
  if petActive and build.pet == 'succubus' then mul('shadow', 'Master Demonologist (Succubus)', tv('masterDemonologist', 'schoolPct')) end
  if petActive and build.pet == 'imp' then mul('fire', 'Master Demonologist (Imp)', tv('masterDemonologist', 'schoolPct')) end
  if petActive then mul('all', 'Soul Link', tv('soulLink', 'dmgPct')) end

  local oilNames = {}
  for i = 1, #oils do oilNames[i] = oils[i].name end
  return {
    race = raceKey, int = int, spi = spi, sta = sta, agi = agi, meleeCritPct = meleeCritPct, maxMana = maxMana, maxHealth = maxHealth,
    sp = sp, dkSp = dkSp, schoolSp = schoolSp, hitPct = hitPct, hitPctUncapped = hitRaw, critPct = critPct, hastePct = hastePct, mp5 = mp5, pierce = pierce,
    mult = mult, petActive = petActive, sacrificeActive = sacrificeActive,
    oilName = #oils > 0 and table.concat(oilNames, ' + ') or WL.OILS.none.name, breakdown = bd,
  }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- spelltable.js: per-spell static values for one build + race
-- ---------------------------------------------------------------------------------------------------------------------
function WL.buildSpellTable(build, stats, cfg)
  local function tv(k, f) return WL.talentValue(build, k, f) end
  local tbl, SPELLS = {}, WL.spellsFor(cfg)
  for i = 1, #WL.SPELL_ORDER do
    local key = WL.SPELL_ORDER[i]
    local s = SPELLS[key]
    if not (s.talent and (build.talents[s.talent] or 0) == 0) then
      local e = { key = key, spell = s }

      local cast = s.cast or 0
      if key == 'shadowBolt' or key == 'immolate' or key == 'incinerate' then cast = cast - tv('bane', 'castRed') end
      if key == 'soulFire' then cast = cast - tv('bane', 'sfCastRed') end
      if key == 'corruption' then cast = cast - tv('improvedCorruption', 'castRed') end
      e.cast = max(0, roundTo(cast, 1000))

      e.cd = s.cd or 0
      if key == 'soulFire' and tv('decimation') ~= 0 then e.cd = s.cd * (1 - tv('decimation', 'sfCdRedPct') / 100) end

      e.range = (s.range and s.range ~= 0) and roundTo(s.range * (1 + tv('destructiveReach', 'rangePct') / 100), 100) or 0
      if s.radius then e.radius = s.radius end

      e.cost = s.cost or 0
      if s.tree == 'destruction' and tv('cataclysm') ~= 0 then e.cost = e.cost * (1 - tv('cataclysm', 'costRedPct') / 100) end

      e.sp = stats.sp + (stats.schoolSp[s.school] or 0)

      e.critPct = stats.critPct
      if s.school == 'shadow' and not cfg.gear.critIncludesAll then e.critPct = e.critPct + tv('malevolence', 'shadowCritPct') end
      if key == 'searingPain' then e.critPct = e.critPct + tv('agonizingFlames', 'spCritPct') end
      if key == 'conflagrate' then e.critPct = e.critPct + tv('fireAndBrimstone', 'conflagCritPct') end

      local bonus, bonusPct = cfg.combat.critMultiplier - 1, 0
      if s.tree == 'destruction' then bonusPct = bonusPct + tv('ruin', 'critBonusPct') end
      if PANDEMIC[key] then bonusPct = bonusPct + tv('pandemic', 'critBonusPct') end
      e.critMult = 1 + bonus * (1 + bonusPct / 100)

      local aura = (stats.mult[s.school] or 1) * stats.mult.all
      local sm = s.school == 'shadow' and tv('shadowMastery', 'shadowPct') or 0
      local agf = (s.tree == 'destruction' and not s.noAgonizingFlames) and tv('agonizingFlames', 'dmgPct') or 0
      local op0 = sm + agf + (key == 'immolate' and tv('aftermath', 'immoInitPct') or 0)
      local op22 = sm + agf
        + (key == 'corruption' and tv('improvedCorruption', 'dmgPct') or 0)
        + (key == 'baneOfAgony' and tv('improvedBaneOfAgony', 'dmgPct') or 0)
        + (s.drain and tv('improvedDrains', 'dmgPct') or 0)
      e.op0 = op0 / 100; e.op22 = op22 / 100
      e.directMult = aura * (1 + e.op0)
      e.periodicMult = aura * (1 + e.op22)

      if s.base ~= nil then e.directDmg = (s.base + s.coef * e.sp) * e.directMult end
      if s.tickBase ~= nil then
        e.ticks = round(s.duration / s.tickEvery)
        e.tickDmg = (s.tickBase + s.tickCoef * e.sp) * e.periodicMult
      end
      tbl[key] = e
    end
  end
  return tbl
end

-- ---------------------------------------------------------------------------------------------------------------------
-- resist.js: resistance and Spell Pierce
-- ---------------------------------------------------------------------------------------------------------------------
function WL.levelResist(cfg)
  local lr = cfg.combat.levelResist
  return (lr and lr.on) and lr.perLevel * lr.levelDiff or 0
end
function WL.effectiveResist(cfg, pierce, school, coeActive)
  local cb = cfg.combat
  local base = ((cb.targetResist and cb.targetResist[school]) or 0) + WL.levelResist(cfg)
  return max(0, base - (coeActive and cb.coeResistReduction or 0)) - (pierce or 0)
end

-- weights over the steps k = 0 .. maxK (list index k + 1) of a triangle around c
local function triWeights(c, maxK, step, spread)
  local w, sum = {}, 0
  for k = 0, maxK do local x = max(0, spread - abs(k * step - c)); w[k + 1] = x; sum = sum + x end
  for k = 1, maxK + 1 do w[k] = w[k] / sum end
  return w
end
local function triMean(c, maxK, step, spread)
  local w, a = triWeights(c, maxK, step, spread), 0
  for k = 0, maxK do a = a + w[k + 1] * k * step end
  return a
end
function WL.vulnerableDist(m, step, spread)
  if not (m > 1e-12) then return { { pct = 0, p = 1 } } end
  local maxK = ceil((m + 2 * spread) / step) + 1
  local lo, hi = -spread + 1e-9, m + spread
  for _ = 1, 80 do local mid = (lo + hi) / 2; if triMean(mid, maxK, step, spread) < m then lo = mid else hi = mid end end
  local w, out = triWeights((lo + hi) / 2, maxK, step, spread), {}
  for k = 0, maxK do
    if w[k + 1] > 1e-12 then out[#out + 1] = { pct = roundTo(k * step * 100, 1000000), p = w[k + 1] } end
  end
  return out
end
function WL.partialResistDist(m)
  m = min(0.75, max(0, m))
  if not (m > 1e-12) then return { { pct = 0, p = 1 } } end
  local step, half = 0.25, 0.5
  local lo, hi = -half + 1e-9, 1 + half
  for _ = 1, 100 do local mid = (lo + hi) / 2; if triMean(mid, 4, step, half) < m then lo = mid else hi = mid end end
  local w, out = triWeights((lo + hi) / 2, 4, step, half), {}
  for k = 0, 4 do
    if w[k + 1] > 1e-12 then out[#out + 1] = { pct = -k * 25, p = w[k + 1] } end
  end
  return out
end
function WL.resistProfile(cfg, pierce, school, coeActive)
  local cb, R = cfg.combat, WL.effectiveResist(cfg, pierce, school, coeActive)
  if R > 0 then
    local mr = min(0.75, cb.pierceAvgPerPoint * R)
    return { R = R, flat = 1, dist = WL.partialResistDist(mr), mean = -mr }
  end
  if R == 0 then return { R = 0, flat = 1, dist = { { pct = 0, p = 1 } }, mean = 0 } end
  local m = cb.pierceAvgPerPoint * -R
  return { R = R, flat = 1, dist = WL.vulnerableDist(m, cb.vulnerableStepPct / 100, cb.vulnerableSpread), mean = m }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- rotation.js: priority actions. Conditions read the fight state S (see Sim.lua).
-- ---------------------------------------------------------------------------------------------------------------------
local function dotWorthOr(S, key, ti, oldRule)
  local w = S.dotWorth and S.dotWorth(key, ti)
  if w == nil then return oldRule end
  return w
end
local function dotNeeded(S, key, minTicks)
  local s = WL.SPELLS[key]
  if not S.has(key) then return false end
  if S.dotLeft(key) > S.castTime(key) then return false end
  return dotWorthOr(S, key, 0, S.remaining - S.castTime(key) >= s.tickEvery * (minTicks or 2))
end

function WL.minDotLeft(S)
  local rot, m = S.build.rotation, huge
  for i = 1, #rot do
    local d = WL.DOT_ACTIONS[rot[i]]
    if d then
      local left = S.dotLeft(d)
      if left > 0 and left < m then m = left end
    end
  end
  return m
end

local MULTI_ORDER = { 'curseOfElements', 'corruption', 'siphonLife', 'baneOfAgony', 'immolate' }
local SPREAD_DOTS = { 'corruption', 'siphonLife', 'baneOfAgony', 'immolate' }
local PICK = {
  curseOfElements = function(S) return (S.cfg.options.useCurseOfElements and not S.buff('coe') and S.remaining > 10) and 'curseOfElements' or nil end,
  shadowTrance = function(S) return S.buff('shadowTrance') and 'shadowBolt' or nil end,
  bane = function(S)
    if S.dotLeft('baneOfDoom') > 0 or S.dotLeft('baneOfAgony') > 0 then return nil end
    if S.ready('baneOfDoom') and S.remaining >= 60 then return 'baneOfDoom' end
    if S.has('baneOfAgony') and dotWorthOr(S, 'baneOfAgony', 0, S.remaining >= 12) then return 'baneOfAgony' end
    return nil
  end,
  baneOfAgony = function(S)
    if S.dotLeft('baneOfDoom') > 0 or S.dotLeft('baneOfAgony') > 0 then return nil end
    return (S.has('baneOfAgony') and dotWorthOr(S, 'baneOfAgony', 0, S.remaining >= 12)) and 'baneOfAgony' or nil
  end,
  corruption = function(S) return dotNeeded(S, 'corruption') and 'corruption' or nil end,
  siphonLife = function(S) return dotNeeded(S, 'siphonLife') and 'siphonLife' or nil end,
  immolate = function(S)
    if indexOf(S.build.rotation, 'conflagrateExpire') and S.has('conflagrate') and S.ready('conflagrate') and S.dotLeft('immolate') > 0 then return nil end
    return dotNeeded(S, 'immolate') and 'immolate' or nil
  end,
  conflagrate = function(S) return (S.has('conflagrate') and S.ready('conflagrate') and S.dotLeft('immolate') > 0) and 'conflagrate' or nil end,
  conflagrateExpire = function(S)
    if not S.has('conflagrate') or not S.ready('conflagrate') then return nil end
    local left = S.dotLeft('immolate')
    return (left > 0 and left <= WL.CONFLAG_EXPIRE_S) and 'conflagrate' or nil
  end,
  shadowburn = function(S) return (S.has('shadowburn') and S.ready('shadowburn') and S.shards > 0) and 'shadowburn' or nil end,
  shadowburnSnF = function(S)
    if not S.has('shadowburn') or (S.build.talents.shadowAndFlame or 0) == 0 or not S.ready('shadowburn') or not (S.shards > 0) then return nil end
    local left = S.buff('snfFire') and S.buffs.snfFire - S.t or 0
    return left <= 3 and 'shadowburn' or nil
  end,
  conflagrateSnF = function(S)
    if not S.has('conflagrate') or (S.build.talents.shadowAndFlame or 0) == 0 or not S.ready('conflagrate') or not (S.dotLeft('immolate') > 0) then return nil end
    local left = S.buff('snfShadow') and S.buffs.snfShadow - S.t or 0
    return left <= 3 and 'conflagrate' or nil
  end,
  multiDot = function(S)
    for ti = 2, (S.multiTargets or 1) do
      for j = 1, #MULTI_ORDER do
        local k = MULTI_ORDER[j]
        if k == 'curseOfElements' then
          if S.cfg.options.useCurseOfElements and S.xDebLeft(ti, 'coe') <= 0 and S.remaining > 10 then S.nextTarget = ti; return k end
        elseif not (not S.has(k) or (k == 'baneOfAgony' and ti == S.havocTarget)) then
          if not (S.xDotLeft(ti, k) > S.castTime(k)) then
            if dotWorthOr(S, k, ti, S.remaining - S.castTime(k) >= WL.SPELLS[k].tickEvery * 2) then S.nextTarget = ti; return k end
          end
        end
      end
    end
    return nil
  end,
  shadowBoltSpread = function(S)
    if (S.build.talents.improvedShadowBolt or 0) == 0 then return nil end
    for ti = 2, (S.multiTargets or 1) do
      if not (S.xDebLeft(ti, 'isb') > S.castTime('shadowBolt')) then
        local any = false
        for j = 1, #SPREAD_DOTS do if S.xDotLeft(ti, SPREAD_DOTS[j]) > 0 then any = true; break end end
        if any then S.nextTarget = ti; return 'shadowBolt' end
      end
    end
    return nil
  end,
  isbUpkeep = function(S)
    if (S.build.talents.improvedShadowBolt or 0) == 0 then return nil end
    local left = S.buff('isb') and S.buffs.isb - S.t or 0
    return left <= S.castTime('shadowBolt') and 'shadowBolt' or nil
  end,
  deathCoil = function(S) return S.ready('deathCoil') and 'deathCoil' or nil end,
  deathCoilFinisher = function(S)
    if not S.ready('deathCoil') then return nil end
    local rot, f = S.build.rotation, nil
    local i = 1
    while i <= #rot and not f do
      local A = WL.ACTIONS[rot[i]]
      if A and (A.filler or A.preFiller) then f = A.pick(S) end
      i = i + 1
    end
    local sf = f and WL.SPELLS[f]
    local need
    if not f then need = S.gcd() elseif sf.kind == 'channel' then need = sf.tickEvery else need = max(S.castTime(f), 0.001) end
    local travel = max(0, (S.cfg.fight.travelMs or 0) / 1000)
    return (S.remaining < need - 1e-6 and S.remaining > travel + 1e-6) and 'deathCoil' or nil
  end,
  swapToImp = function(S) return (S.canSwap and S.canSwap('imp')) and 'swap:imp' or nil end,
  swapToSuccubus = function(S) return (S.canSwap and S.canSwap('succubus')) and 'swap:succubus' or nil end,
  searingPainExecute = function(S) return S.targetHpPct < S.cfg.fight.executePct and 'searingPain' or nil end,
  searingPainDecimation = function(S)
    local rank, rot = S.build.talents.decimation or 0, S.build.rotation
    if rank == 0 or not (S.targetHpPct < S.cfg.fight.executePct) then return nil end
    if not indexOf(rot, 'soulFire') and not indexOf(rot, 'soulFireShards') then return nil end
    local cd = max(0, (S.cds.soulFire or 0) - S.t)
    local up = S.buff('decimation') and S.buffs.decimation - S.t or 0
    if up > cd then return nil end
    local sp = S.castTime('searingPain')
    if cd > sp then return nil end
    local sf = S.castTime('soulFire') * (S.buff('decimation') and 1 or 1 - WL.TALENT_BY_KEY.decimation.v.sfCastRedPct[rank] / 100)
    return S.remaining >= max(sp, S.gcd()) + sf and 'searingPain' or nil
  end,
  soulFire = function(S) return (S.buff('decimation') and S.ready('soulFire')) and 'soulFire' or nil end,
  lifeTapPet = function(S)
    if (S.build.talents.demonicEnergies or 0) == 0 or not S.build.pet then return nil end
    if S.petMana() >= 2 * S.petSpellCost() then return nil end
    return S.maxMana - S.mana >= S.tapGain() and 'lifeTap' or nil
  end,
  lifeTapBelow = function(S)
    local p = S.build.params and S.build.params.lifeTapBelow
    local pct = (p and p.pct ~= nil) and p.pct or 40
    local sec = (p and p.sec ~= nil) and p.sec or 25
    return (S.mana < S.maxMana * pct / 100 and S.remaining > sec) and 'lifeTap' or nil
  end,
  searingPainBrand = function(S)
    if (S.build.talents.demonicBrand or 0) == 0 or not S.build.pet then return nil end
    return (not S.buff('brand') or not ((S.brandCharges or 0) > 0)) and 'searingPain' or nil
  end,
  soulFireShards = function(S) return (S.ready('soulFire') and (S.buff('decimation') or S.shards > 0)) and 'soulFire' or nil end,
  wrackDots = function(S)
    if not S.has('wrack') then return nil end
    local p = S.build.params and S.build.params.wrackDots
    local sec = (p and p.sec ~= nil) and p.sec or 6
    return WL.minDotLeft(S) > sec and 'wrack' or nil
  end,
  wrack = function(S) return S.has('wrack') and 'wrack' or nil end,
  shadowBolt = function() return 'shadowBolt' end,
  incinerate = function(S) return S.has('incinerate') and 'incinerate' or nil end,
  drainLife = function() return 'drainLife' end,
  hellfire = function() return 'hellfire' end,
  rainOfFire = function() return 'rainOfFire' end,
  searingPain = function() return 'searingPain' end,
}
WL.ACTIONS, WL.ACTION_ORDER, WL.ACTIONS_MISSING = {}, {}, {}
for i = 1, #WL.ACTION_META do
  local m = WL.ACTION_META[i]
  WL.ACTION_ORDER[i] = m.key
  if PICK[m.key] then
    m.pick = PICK[m.key]
    WL.ACTIONS[m.key] = m
  else
    WL.ACTIONS_MISSING[#WL.ACTIONS_MISSING + 1] = m.key   -- a priority action of the sim that this addon does not know yet
  end
end

function WL.effectiveRotation(build, cfg)
  local rot, f = {}, (cfg and cfg.fight) or {}
  for i = 1, #build.rotation do rot[i] = build.rotation[i] end
  if f.multiDot and ((f.targets and f.targets ~= 0) and f.targets or 1) >= 2 and not indexOf(rot, 'multiDot') then
    local fi
    for i = 1, #rot do
      local a = WL.ACTIONS[rot[i]]
      if a and (a.filler or a.preFiller) then fi = i; break end
    end
    local si = indexOf(rot, 'shadowBoltSpread')
    if si and (not fi or si < fi) then fi = si end
    table.insert(rot, fi or (#rot + 1), 'multiDot')
  end
  return rot
end

WL.PRECAST_SPELLS = {}
for i = 1, #WL.SPELL_ORDER do
  local k = WL.SPELL_ORDER[i]
  local s = WL.SPELLS[k]
  if (s.cast or 0) > 0 and s.kind ~= 'channel' and s.kind ~= 'utility' then WL.PRECAST_SPELLS[#WL.PRECAST_SPELLS + 1] = k end
end
function WL.precastOf(build, cfg, tbl)
  local k = cfg and cfg.fight and cfg.fight.precast
  if not k or k == '' or not indexOf(WL.PRECAST_SPELLS, k) or not tbl or not tbl[k] or not (tbl[k].cast > 0) then return nil end
  return k
end

-- ---------------------------------------------------------------------------------------------------------------------
-- custom-builds.js: validation and the numbers of priority actions
-- ---------------------------------------------------------------------------------------------------------------------
function WL.actionParams(b, key)
  local A, out = WL.ACTIONS[key], {}
  local own = (b and b.params and b.params[key]) or {}
  if A and A.params then
    for i = 1, #A.params do local p = A.params[i]; out[p.key] = own[p.key] ~= nil and own[p.key] or p.def end
  end
  return out
end
function WL.actionLabel(b, key)
  local A = WL.ACTIONS[key]
  if not A then return key end
  if not A.params then return A.label end
  local v, i = WL.actionParams(b, key), 0
  return (A.label:gsub('_', function() i = i + 1; local p = A.params[i]; return p and tostring(v[p.key]) or '_' end))
end
function WL.cleanParams(params, rotation)
  local out, any = {}, false
  for a, own in pairs(params or {}) do
    local A = WL.ACTIONS[a]
    if A and A.params and not (rotation and not indexOf(rotation, a)) and type(own) == 'table' then
      for i = 1, #A.params do
        local p = A.params[i]
        local v = own[p.key]
        if type(v) == 'number' and v == v and v ~= huge and v ~= -huge then out[a] = out[a] or {}; out[a][p.key] = v; any = true end
      end
    end
  end
  return any and out or nil
end

local R2_ACTIONS = { shadowBoltR2 = 'shadowBolt', isbUpkeepR2 = 'isbUpkeep', shadowBoltR2LowMana = false }
function WL.migrateRotation(rot)
  local out = {}
  for i = 1, #rot do
    local a = rot[i]
    local m = a
    if R2_ACTIONS[a] ~= nil then m = R2_ACTIONS[a] end
    if m and not indexOf(out, m) then out[#out + 1] = m end
  end
  return out
end

-- Talents a Forever patch removed: old build codes still load. Malediction became Grim Reach in the same place of the
-- tree: its points move there as far as they fit, the rest are left unspent. Returns the talents and what was moved.
function WL.migrateTalents(t)
  local out, notes, R = {}, {}, WL.RETIRED_TALENTS or {}
  for k, v in pairs(t or {}) do if not R[k] and type(v) == 'number' and v ~= 0 then out[k] = v end end
  for k, v in pairs(t or {}) do
    local r, n = R[k], type(v) == 'number' and v or 0
    if r and n ~= 0 then
      local to = WL.TALENT_BY_KEY[r.to]
      local m = math.min(n, to.ranks - (out[r.to] or 0))
      if m > 0 then out[r.to] = (out[r.to] or 0) + m end
      local pts = n > 1 and 's' or ''
      notes[#notes + 1] = r.name .. ' no longer exists: ' .. (m > 0 and (m .. ' of its ' .. n .. ' point' .. pts .. ' moved to ' .. to.name)
        or ('its ' .. n .. ' point' .. (n > 1 and 's are' or ' is') .. ' unspent')) .. ((m > 0 and n > m) and (', ' .. (n - m) .. ' unspent') or '')
    end
  end
  return out, notes
end

local GATED = { conflagrate = 'conflagrate', conflagrateExpire = 'conflagrate', shadowburn = 'shadowburn', incinerate = 'incinerate', wrack = 'wrack', wrackDots = 'wrack', siphonLife = 'siphonLife',
  searingPainBrand = 'demonicBrand', searingPainDecimation = 'decimation', lifeTapPet = 'demonicEnergies', shadowburnSnF = 'shadowAndFlame', conflagrateSnF = 'shadowAndFlame', shadowBoltSpread = 'improvedShadowBolt', isbUpkeep = 'improvedShadowBolt' }
WL.GATED_ACTIONS = GATED

-- Returns a list of problems (empty = legal and simulatable). `loose` = a character read from the game: its talent
-- points need not add up to 51 and the row rules are the game's business.
function WL.validateBuild(b, loose)
  local errs, total, t = {}, 0, b.talents or {}
  local function err(s) errs[#errs + 1] = s end
  for k, pts in pairs(t) do
    local tal = WL.TALENT_BY_KEY[k]
    if not tal then err('Unknown talent "' .. tostring(k) .. '"')
    else
      total = total + pts
      if not (pts >= 1 and pts <= tal.ranks) then err(tal.name .. ': ' .. pts .. ' points (max ' .. tal.ranks .. ')') end
      if not loose then
        if tal.req and (t[tal.req] or 0) < tal.reqQty then err(tal.name .. ' needs ' .. tal.reqQty .. ' point(s) in ' .. WL.TALENT_BY_KEY[tal.req].name) end
        local below = 0
        for k2, p2 in pairs(t) do local t2 = WL.TALENT_BY_KEY[k2]; if t2 and t2.tree == tal.tree and t2.row < tal.row then below = below + p2 end end
        if below < tal.row * 5 then err(tal.name .. ' (row ' .. (tal.row + 1) .. ') needs ' .. tal.row * 5 .. ' points in ' .. WL.TREES[tal.tree].name .. ' above it (has ' .. below .. ')') end
      end
    end
  end
  if not loose and total ~= 51 then err('Spend exactly 51 points (now ' .. total .. ')') end
  if b.pet and not indexOf(WL.PET_KEYS, b.pet) then err('Unknown pet "' .. tostring(b.pet) .. '"') end
  if b.sacrifice and not indexOf(WL.SACRIFICE_KEYS, b.sacrifice) then err('Unknown sacrifice "' .. tostring(b.sacrifice) .. '"') end
  if b.sacrifice and (t.demonicSacrifice or 0) == 0 then err('A sacrifice needs the Demonic Sacrifice talent') end
  if b.sacrifice and b.pet and (t.demonicPact or 0) == 0 then err('Keeping a pet out after a sacrifice needs Demonic Pact') end
  if b.sacrifice and b.pet and b.pet == b.sacrifice then err('Demonic Pact: the sacrificed demon cannot be the one you keep out') end
  if not WL.OILS[b.oil] then err('Unknown weapon stone "' .. tostring(b.oil) .. '"') end
  local rot = b.rotation or {}
  if #rot == 0 then err('The priority list is empty') end
  for i = 1, #rot do if not WL.ACTIONS[rot[i]] then err('Unknown priority action "' .. tostring(rot[i]) .. '"') end end
  local fi
  for i = 1, #rot do if WL.ACTIONS[rot[i]] and WL.ACTIONS[rot[i]].filler then fi = i; break end end
  if not fi and #rot > 0 then err('The priority list needs a filler (Shadow Bolt, Searing Pain, Incinerate, ...) at the end')
  elseif fi and fi < #rot then err('Everything after the first filler (' .. WL.ACTIONS[rot[fi]].label .. ') is never cast - move the filler to the end') end
  if indexOf(rot, 'shadowburnSnF') and (t.shadowburn or 0) == 0 then err('"' .. WL.ACTIONS.shadowburnSnF.label .. '" needs the Shadowburn talent') end
  if indexOf(rot, 'conflagrateSnF') and (t.conflagrate or 0) == 0 then err('"' .. WL.ACTIONS.conflagrateSnF.label .. '" needs the Conflagrate talent') end
  for i = 1, #rot do
    local a = rot[i]
    if GATED[a] and (t[GATED[a]] or 0) == 0 and WL.ACTIONS[a] then err('"' .. WL.ACTIONS[a].label .. '" needs the ' .. WL.TALENT_BY_KEY[GATED[a]].name .. ' talent') end
  end
  for i = 1, #rot do
    local A = WL.ACTIONS[rot[i]]
    if A and A.params then
      local v = WL.actionParams(b, rot[i])
      for j = 1, #A.params do
        local p = A.params[j]
        if not (type(v[p.key]) == 'number' and v[p.key] >= p.min and v[p.key] <= p.max) then
          err('"' .. A.label:gsub('_', '...') .. '": ' .. p.name .. ' must be a number from ' .. p.min .. ' to ' .. p.max)
        end
      end
    end
  end
  if (indexOf(rot, 'searingPainBrand') or indexOf(rot, 'lifeTapPet')) and not b.pet then err('Demonic Brand upkeep / Life Tap for the pet need a pet out') end
  local swaps = { { 'swapToImp', 'imp' }, { 'swapToSuccubus', 'succubus' } }
  for i = 1, 2 do
    local s = swaps[i]
    if indexOf(rot, s[1]) then
      local lab = '"' .. WL.ACTIONS[s[1]].label .. '"'
      local need = { 'demonicSacrifice', 'demonicPact', 'felDomination' }
      for j = 1, 3 do if (t[need[j]] or 0) == 0 then err(lab .. ' needs the ' .. WL.TALENT_BY_KEY[need[j]].name .. ' talent') end end
      if not b.pet then err(lab .. ' needs a pet out at the start (it is the one that gets sacrificed)')
      elseif b.pet == s[2] then err(lab .. ': that demon is already out - pick the other swap') end
    end
  end
  if indexOf(rot, 'swapToImp') and indexOf(rot, 'swapToSuccubus') then err('Only one pet swap per fight - keep one of the two swap actions') end
  if indexOf(rot, 'bane') and indexOf(rot, 'baneOfAgony') then err('Keep one Bane action: "' .. WL.ACTIONS.bane.label .. '" or "' .. WL.ACTIONS.baneOfAgony.label .. '"') end
  if b.timeline then
    if type(b.timeline) ~= 'table' then err('The fight timeline is damaged')
    else
      for i = 1, #b.timeline do
        local e = b.timeline[i]
        local s = e and WL.SPELLS[e.k]
        if not s or not indexOf(WL.TIMELINE_SPELLS, e.k) then err('Timeline entry ' .. i .. ': unknown spell "' .. tostring(e and e.k) .. '"')
        elseif s.talent and (t[s.talent] or 0) == 0 then err('Timeline: ' .. s.name .. ' needs the ' .. WL.TALENT_BY_KEY[s.talent].name .. ' talent') end
        if not (e and type(e.t) == 'number' and e.t >= 0 and e.t ~= huge) then err('Timeline entry ' .. i .. ': bad start time') end
      end
    end
  end
  return errs
end
