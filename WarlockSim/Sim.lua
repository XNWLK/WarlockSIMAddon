-- The fight itself, carried over from the sim's engine/sim.js function by function (same names, same order).
-- One call of WL.simulateOnce = one fight; WL.simulate = many fights averaged.
-- Event order at equal timestamps: periodic ticks (0) -> cast completions (1) -> player decisions (2).
-- Left out on purpose (nothing here changes a fight): the event log, the aura intervals / uptimes for the timeline,
-- the vulnerable-hit counters and the notes about skipped DoTs. tools/check-engine.js compares damage, mana and health.
local ADDON, WL = ...

local floor, min, max, huge = math.floor, math.min, math.max, math.huge
local sub = string.sub
local makeRng, xorSeed, indexOf, copy, racialOf = WL.makeRng, WL.xorSeed, WL.indexOf, WL.copy, WL.racialOf
local NIGHTFALL, SIPHON_SET, WRACK_SET = WL.NIGHTFALL_SET, WL.SOUL_SIPHON_SET, WL.WRACK_DEBUFF_SET
local SIPHON_LIST = WL.SOUL_SIPHON_EFFECTS
local EPS = 1e-9
local TWO32 = 4294967296

local function round(x) return floor(x + 0.5) end

-- Event order in the heap, "x before y": x.t earlier (by more than 1e-9), or the same time and a lower order number o,
-- or the same order and pushed earlier (seq). Written out inside push and pop below: it is the most called piece of a fight.

-- caches over all fights: is this damage row a pet's; a row's spell without its "x2:" target prefix
local ISPET, BASEK, XKEY = {}, {}, { [2] = {}, [3] = {} }
local function xkey(ti, key)
  local t = XKEY[ti]
  local v = t[key]
  if not v then v = 'x' .. ti .. ':' .. key; t[key] = v end
  return v
end

local NOT_ALT = { bane = 1, baneOfAgony = 1, corruption = 1, siphonLife = 1, immolate = 1, multiDot = 1, curseOfElements = 1, lifeTapPet = 1, lifeTapBelow = 1,
                  swapToImp = 1, swapToSuccubus = 1, shadowBoltSpread = 1, isbUpkeep = 1, deathCoilFinisher = 1 }
local FEL_CONC = { drainLife = 1, drainSoul = 1, wrack = 1 }

-- Custom cooldown timeline (options.activesTimeline) as { slot = { sorted times } }.
function WL.cdTime(x, cfg, dur)
  if x == 'exec' then return (dur or cfg.fight.duration) * (1 - cfg.fight.executePct / 100) end
  if x == 'doom' then return 60 end
  return x
end
function WL.activesTimelineOf(cfg)
  local src, C, out = (cfg.options and cfg.options.activesTimeline) or {}, cfg.consumables or {}, {}
  local function first(test, fallback)
    for i = 1, #WL.CONSUMABLE_ORDER do
      local k = WL.CONSUMABLE_ORDER[i]
      if C[k] and C[k].on and test(C[k]) then return k end
    end
    return fallback
  end
  local legacy = { potion = first(function(c) return c.cdGroup == 'potion' end, 'majorSpellblasting'), rune = 'demonicRune', sapper = 'goblinSapper',
                   explosive = first(function(c) return c.explosive and c.explosive.cdGroup ~= 'sapper' end, 'denseDynamite') }
  local function put(k, v)
    local a = {}
    if type(v) == 'table' then
      for i = 1, #v do
        local x = v[i]
        if x ~= 'exec' and x ~= 'doom' then x = tonumber(x) end
        if x ~= nil and (type(x) == 'string' or (x == x and x ~= huge and x >= 0)) and not indexOf(a, x) then a[#a + 1] = x end
      end
    end
    for i = 2, #a do                                   -- stable insertion sort by the second an entry stands for
      local x, j = a[i], i - 1
      while j >= 1 and WL.cdTime(a[j], cfg) > WL.cdTime(x, cfg) do a[j + 1] = a[j]; j = j - 1 end
      a[j + 1] = x
    end
    if #a > 0 then out[k] = a end
  end
  local keys = {}
  for k in pairs(src) do keys[#keys + 1] = k end
  table.sort(keys)
  for i = 1, #keys do if legacy[keys[i]] then put(legacy[keys[i]], src[keys[i]]) end end
  for i = 1, #keys do if not legacy[keys[i]] then put(keys[i], src[keys[i]]) end end
  return out
end

function WL.simulateOnce(build, raceKey, cfg, opt)
  opt = opt or {}
  local stats = opt.stats or WL.computeStats(build, raceKey, cfg)
  local tbl = opt.table or WL.buildSpellTable(build, stats, cfg)
  local SPELLS = WL.spellsFor(cfg)
  local seed0 = opt.seed
  if seed0 == nil then seed0 = floor((opt.rng or makeRng(cfg.fight.seed))() * TWO32) end
  -- Independent random streams per roll type (common random numbers for stat weights).
  local Rhit, Rcrit, Rproc = makeRng(xorSeed(seed0, 0x1B873593)), makeRng(xorSeed(seed0, 0x85EBCA6B)), makeRng(xorSeed(seed0, 0xC2B2AE35))
  local Rvuln, Rpet, Rjow = makeRng(xorSeed(seed0, 0x27D4EB2F)), makeRng(xorSeed(seed0, 0x165667B1)), makeRng(xorSeed(seed0, 0x3C6EF372))
  local Rpush = makeRng(xorSeed(seed0, 0x61C88647))
  local dur, cb, fight = opt.duration or cfg.fight.duration, cfg.combat, cfg.fight
  local executePct = fight.executePct
  local race = WL.RACES[raceKey]
  local racialCd, racialProc = racialOf(race, 'cooldown'), racialOf(race, 'proc')
  local talentValue = WL.talentValue
  local TVC = {}
  local function tv(k, f)
    local c = TVC[k]
    if not c then c = {}; TVC[k] = c end
    local q = f or ''
    local v = c[q]
    if v == nil then v = talentValue(build, k, f); c[q] = v end
    return v
  end
  local tick = WL.onTick                                 -- the game's frame budget (nil outside the game)
  local evCount = 0

  -- ---------- tiny binary heap ----------
  local HA, HN, HSEQ = {}, 0, 0
  local function push(ev)
    local seq = HSEQ
    ev.seq = seq; HSEQ = seq + 1
    local i = HN + 1
    HN = i
    local t, o = ev.t, ev.o
    while i > 1 do                                         -- the new event moves up while it comes before its parent
      local p = (i - i % 2) / 2
      local y = HA[p]
      local d = t - y.t
      if d < -1e-9 or (d <= 1e-9 and (o < y.o or (o == y.o and seq < y.seq))) then HA[i] = y; i = p else break end
    end
    HA[i] = ev
  end
  local function pop()
    local top, last = HA[1], HA[HN]
    HA[HN] = nil
    local n = HN - 1
    HN = n
    if n > 0 then                                          -- the last event moves down from the top: below the earlier of its children
      local i = 1
      local lt, lo, lseq = last.t, last.o, last.seq
      while true do
        local l = 2 * i
        if l > n then break end
        local m
        local c = HA[l]
        local mt, mo, mseq = lt, lo, lseq
        local d = c.t - lt
        if d < -1e-9 or (d <= 1e-9 and (c.o < lo or (c.o == lo and c.seq < lseq))) then m = l; mt, mo, mseq = c.t, c.o, c.seq end
        if l < n then
          local e = HA[l + 1]
          d = e.t - mt
          if d < -1e-9 or (d <= 1e-9 and (e.o < mo or (e.o == mo and e.seq < mseq))) then m = l + 1 end
        end
        if not m then break end
        HA[i] = HA[m]; i = m
      end
      HA[i] = last
    end
    return top
  end

  -- ---------- state ----------
  local cds, dots, buffs = {}, {}, {}
  local S = {
    t = 0, remaining = dur, cfg = cfg, build = build,
    mana = stats.maxMana, health = stats.maxHealth, shards = huge,
    busyUntil = 0, gcdReady = 0, lastRegen = 0,
    lastSpend = -huge, spendAt = nil, innervateUntil = 0,
    cds = cds, dots = dots, buffs = buffs, channel = nil,
    targetHpPct = 100,
  }
  local inst, decideToken = 0, 0
  local bySpell = {}
  local res = { bySpell = bySpell, lifeTaps = 0, manaFromTaps = 0, manaFromSpirit = 0, fsrOutTime = 0, manaFromSac = 0, threat = 0,
    health = { min = stats.maxHealth, tap = 0, self = 0, healed = 0, leech = 0, sac = 0, blocked = 0 }, minMana = stats.maxMana,
    total = 0, oom = 0, clipped = 0, idle = 0, pushbacks = 0, pushbackTime = 0, pushResisted = 0, petOomTime = 0, exDmg = 0 }
  local resHealth = res.health

  local function row(key)
    local r = bySpell[key]
    if not r then
      r = { casts = 0, landed = 0, misses = 0, crits = 0, hits = 0, ticks = 0, tickCrits = 0, dmg = 0, castTime = 0, glances = 0, threat = 0 }
      bySpell[key] = r
    end
    return r
  end

  -- ---------- helpers exposed to rotation conditions ----------
  local function has(k) return tbl[k] ~= nil end
  local function ready(k) local c = cds[k]; return not c or c <= S.t + EPS end
  local function buff(n) local e = buffs[n]; return e ~= nil and e > S.t + EPS end
  local function dotLeft(k) local d = dots[k]; return (d and d.expires > S.t + EPS) and d.expires - S.t or 0 end
  local hasteBase = 1 + stats.hastePct / 100
  local BERSERK = racialCd and racialCd.hastePct                -- Berserking's haste %, nil for every race but the Troll
  local function hasteFactor()
    if not BERSERK then return hasteBase end
    return hasteBase * (buff('berserking') and 1 + BERSERK / 100 or 1)
  end
  local function castTime(k)
    local c = tbl[k].cast
    if k == 'soulFire' then
      if buff('decimation') then c = c * (1 - tv('decimation', 'sfCastRedPct') / 100) end
    elseif k == 'shadowBolt' then
      local e = buffs.shadowTrance
      if e ~= nil and e > S.t + EPS then c = 0 end
    end
    return c / (BERSERK and hasteFactor() or hasteBase)
  end
  local function gcd() return max(cb.minGcd, cb.gcd / (BERSERK and hasteFactor() or hasteBase)) end
  S.has, S.ready, S.buff, S.dotLeft, S.hasteFactor, S.castTime, S.gcd = has, ready, buff, dotLeft, hasteFactor, castTime, gcd

  -- Spirit regeneration per second outside the 5-second rule: (base + per Spirit x Spirit) per 2 s, accrued continuously.
  local FSR = (cb.fsrSeconds or 0) > 0 and cb.fsrSeconds or 0
  local SPI_REGEN = FSR ~= 0 and (cb.spiritRegenBase + cb.spiritRegenPerSpi * stats.spi) / 2 or 0
  local function spiritRegen(a, b)
    if S.lastSpend == -huge then return end
    if S.channel then return end
    local from = max(a, S.lastSpend + FSR, S.innervateUntil)
    if b <= from then return end
    local before = S.mana
    S.mana = min(stats.maxMana, S.mana + SPI_REGEN * (b - from))
    res.manaFromSpirit = res.manaFromSpirit + (S.mana - before); res.fsrOutTime = res.fsrOutTime + (b - from)
  end
  local function updateTime(t)
    S.t = t; S.remaining = max(0, dur - t)
    S.targetHpPct = 100 * (1 - t / dur)
    if stats.mp5 ~= 0 then S.mana = min(stats.maxMana, S.mana + stats.mp5 / 5 * (t - S.lastRegen)) end
    if SPI_REGEN > 0 then
      if S.spendAt ~= nil and S.spendAt <= t + EPS then
        local mid = min(t, max(S.lastRegen, S.spendAt))
        spiritRegen(S.lastRegen, mid); S.lastSpend = S.spendAt; S.spendAt = nil; spiritRegen(mid, t)
      elseif S.lastSpend ~= -huge and not S.channel and t > S.lastSpend + FSR then spiritRegen(S.lastRegen, t) end
    end
    S.lastRegen = t
  end

  -- ---------- damage ----------
  -- Eureka! (Gnome): an 8 s buff (buffs.eureka = when it ends). +10% damage and -10% mana cost for every damaging spell
  -- that FINISHES while it is up: a cast-time spell when its cast completes (pushback can push it out), an instant when
  -- it is cast (a projectile keeps it after travel). A channel: its cost when it starts inside the buff, each tick that
  -- comes while the buff is up. DoTs never. The +10% adds to the spell's own modifier group.
  local EUREKA = (racialCd and racialCd.dmgPct) and racialCd or nil   -- nil for every race but the Gnome
  local function eurekaAt(key, t)
    if not EUREKA then return false end
    local k = SPELLS[key].kind
    if k == 'utility' or k == 'dot' then return false end
    local e = buffs.eureka
    return e ~= nil and e > t + EPS
  end
  local function eurekaMult(key, periodic)
    local e = tbl[key]
    local g = e and (periodic and e.op22 or e.op0) or 0
    return (1 + g + EUREKA.dmgPct / 100) / (1 + g)
  end
  local function eurekaTick(key, periodic)
    if periodic and SPELLS[key].kind == 'channel' and eurekaAt(key, S.t) then return eurekaMult(key, true) end
    return 1
  end
  -- When a cast of `key` started now would finish: a channel counts from its start (its cost is paid then).
  local function finishesAt(key) return S.t + (SPELLS[key].kind == 'channel' and 0 or castTime(key)) end
  local function addOp0(key, pct) local g = (tbl[key] and tbl[key].op0) or 0; return (1 + g + pct / 100) / (1 + g) end
  local buffList = WL.activeBuffs(cfg)
  local PI
  local manaBuffs = {}
  for i = 1, #buffList do
    local b = buffList[i]
    if not PI and b.spellDmgPct and b.spellDmgPct ~= 0 then PI = b end
    if b.tide or b.innervate then manaBuffs[#manaBuffs + 1] = { b = b, left = max(1, floor((b.count or 1) + 0.5)), upTo = 0 } end   -- count: several Druids
  end
  local coePct = SPELLS.curseOfElements.dmgTakenPct
  local function liveMult(key, periodic)
    local s = SPELLS[key]
    local m = EUREKA and eurekaTick(key, periodic) or 1
    local now = S.t + EPS
    local e = buffs.coe
    if e ~= nil and e > now then m = m * (1 + coePct / 100) end
    if PI and buff('powerInfusion') then m = m * (1 + PI.spellDmgPct / 100) end
    if s.school == 'shadow' then
      e = buffs.isb
      if e ~= nil and e > now then m = m * (1 + tv('improvedShadowBolt', 'debuffPct') / 100) end
      e = buffs.snfShadow
      if e ~= nil and e > now then m = m * (1 + tv('shadowAndFlame', 'schoolPct') / 100) end
    elseif s.school == 'fire' then
      e = buffs.snfFire
      if e ~= nil and e > now then m = m * (1 + tv('shadowAndFlame', 'schoolPct') / 100) end
    end
    if periodic and S.channel and S.channel.key == 'wrack' and WRACK_SET[key] then m = m * (1 + SPELLS.wrack.debuffPct / 100) end
    if s.drain and tv('soulSiphon') ~= 0 then
      local n = 0
      for i = 1, #SIPHON_LIST do
        local e = SIPHON_LIST[i]
        if e == 'curseOfElements' then if buff('coe') then n = n + 1 end elseif dotLeft(e) > 0 then n = n + 1 end
      end
      m = m * (1 + min(n * tv('soulSiphon', 'perEffectPct'), tv('soulSiphon', 'maxPct')) / 100)
    end
    return m
  end
  local armorRed = WL.armorReduction(cfg)

  -- ---------- health ----------
  local HEAL = ((fight.healAmount or 0) > 0 and (fight.healEvery or 0) > 0) and { amt = fight.healAmount, every = fight.healEvery } or nil
  local TAP_HP = SPELLS.lifeTap.healthCost or 0
  local function gainHealth(amt, src)
    local before = S.health
    S.health = min(stats.maxHealth, S.health + amt)
    resHealth[src] = resHealth[src] + (S.health - before)
  end
  local function loseHealth(amt, src)
    S.health = S.health - amt
    resHealth[src] = resHealth[src] + amt
    if S.health < resHealth.min then resHealth.min = S.health end
  end
  local function canTap() return S.health > TAP_HP end
  local function selfTakenMult() return (1 - tv('moltenSkin', 'dmgTakenPct') / 100) * (stats.petActive and 1 - tv('soulLink', 'toPetPct') / 100 or 1) end
  local spNow                                            -- defined below
  local function selfTick(key)
    local s = SPELLS[key]
    return s.selfDamage and round((s.tickBase + s.tickCoef * spNow(tbl[key])) * selfTakenMult()) or 0
  end
  local function healsDue(untilT) return HEAL and HEAL.amt * (floor((untilT + EPS) / HEAL.every) - floor((S.t + EPS) / HEAL.every)) or 0 end
  local function healthOk(k)
    local s = SPELLS[k]
    return not s or not s.selfDamage or S.health + healsDue(S.t + s.duration) > selfTick(k) * tbl[k].ticks
  end
  -- ---------- threat ----------
  local THREAT_ALL
  do
    local m, best, groups = 1, {}, {}
    for i = 1, #buffList do
      local b = buffList[i]
      if b.threatPct and b.threatPct ~= 0 then
        if b.group then
          if best[b.group] == nil then groups[#groups + 1] = b.group end
          best[b.group] = max(best[b.group] or 0, b.threatPct)
        else m = m * (1 - b.threatPct / 100) end
      end
    end
    for i = 1, #groups do m = m * (1 - best[groups[i]] / 100) end
    THREAT_ALL = (1 - tv('suppression', 'threatPct') / 100) * m
  end
  local THREAT = {}                                            -- per spell, worked out at its first hit of the fight
  local function threatMult(bk)
    local s = SPELLS[bk]
    local m = THREAT_ALL * ((s and s.threatMult) or 1)
    if bk == 'searingPain' then m = m * (1 - tv('demonicBrand', 'threatRedPct') / 100) end
    THREAT[bk] = m
    return m
  end
  local function manaBuffCheck()
    if #manaBuffs == 0 or S.mana >= 0.5 * stats.maxMana then return end
    for i = 1, #manaBuffs do
      local mb = manaBuffs[i]
      if not (mb.left <= 0 or S.t < mb.upTo - EPS) then             -- the next one when the last one is over
        mb.left = mb.left - 1
        mb.upTo = S.t + (mb.b.innervate and mb.b.innervate.duration or mb.b.tide.ticks * mb.b.tide.every)
        if mb.b.tide then
          for j = 0, mb.b.tide.ticks - 1 do push({ t = S.t + j * mb.b.tide.every, o = 0, type = 'mana', amount = mb.b.tide.amount }) end
        end
        if mb.b.innervate then
          local perTick = (cb.spiritRegenBase + cb.spiritRegenPerSpi * stats.spi) * mb.b.innervate.mult
          for j = 1, floor(mb.b.innervate.duration / 2) do push({ t = S.t + j * 2, o = 0, type = 'mana', amount = perTick }) end
          S.innervateUntil = S.t + mb.b.innervate.duration
        end
      end
    end
  end
  -- Consumables used during the fight.
  local conList = WL.activeConsumables(cfg)
  local spPot
  local manaItems, explosives = {}, {}
  for i = 1, #conList do
    local c = conList[i]
    if not spPot and c.spPotion then spPot = c end
    if c.manaRestore then manaItems[#manaItems + 1] = c end
    if c.explosive then explosives[#explosives + 1] = c end
  end
  local function potSp() return (spPot and buff('spPotion')) and spPot.spPotion.sp or 0 end

  -- When the short cooldowns are popped for the first time (options.activesPolicy): 'pull', 'doom', 'execute', 'custom'.
  local ACT_POL = (cfg.options and cfg.options.activesPolicy) or 'pull'
  local actOpen, doomSeen = ACT_POL == 'pull', false
  local ACT_DOOM = nil
  local ACT_TL = nil
  local ROT, TL                                           -- set below
  if ACT_POL == 'custom' then
    ACT_TL = {}
    local tlSrc = WL.activesTimelineOf(cfg)
    for k, list in pairs(tlSrc) do
      local t = {}
      for i = 1, #list do t[i] = list[i] == 'exec' and WL.cdTime(list[i], cfg, dur) or list[i] end
      ACT_TL[k] = { t = t, i = 1 }
    end
  end
  local RSLOT = (cfg.options and cfg.options.activesRacialSplit) and ('racial_' .. raceKey) or 'racial'
  local gateKey = nil
  local function castsDoom()
    if ACT_DOOM == nil then
      ACT_DOOM = indexOf(ROT, 'bane') ~= nil
      if not ACT_DOOM and build.timeline then
        for i = 1, #build.timeline do if build.timeline[i].k == 'baneOfDoom' then ACT_DOOM = true end end
      end
    end
    return ACT_DOOM
  end
  local function doomDue()
    castsDoom()
    local d = dots.baneOfDoom
    if d then doomSeen = true end
    if not d or d.expires <= S.t + EPS then return doomSeen or not ACT_DOOM or dots.baneOfAgony ~= nil end
    local toBoom = d.expires - S.t
    if toBoom > S.remaining then return true end
    if not gateKey then return false end
    local sp = SPELLS[gateKey]
    local len = sp.kind == 'channel' and sp.duration or max(castTime(gateKey), gcd())
    return toBoom <= len + EPS
  end
  local function slotDue(x)
    if x == 'doom' then return doomDue() end
    return S.t >= x - EPS
  end
  local function slotGate(k)
    local sl = ACT_TL and ACT_TL[k]
    if not sl or sl.i > #sl.t then return 2 end
    return slotDue(sl.t[sl.i]) and 1 or 0
  end
  local function slotUsed(k)
    local sl = ACT_TL and ACT_TL[k]
    if sl and sl.i <= #sl.t and slotDue(sl.t[sl.i]) then sl.i = sl.i + 1 end
  end
  local function activesOk(key)
    if actOpen then return true end
    if ACT_POL == 'execute' then actOpen = S.targetHpPct < executePct; return actOpen end
    castsDoom()
    local d = dots.baneOfDoom
    if d then doomSeen = true end
    if not d or d.expires <= S.t + EPS then actOpen = doomSeen or not ACT_DOOM or dots.baneOfAgony ~= nil; return actOpen end
    local toBoom, sp = d.expires - S.t, SPELLS[key]
    local len = sp.kind == 'channel' and sp.duration or max(castTime(key), gcd())
    actOpen = toBoom > S.remaining or toBoom <= len + EPS
    return actOpen
  end
  -- count = how many Priests give you their Power Infusion; each has its own cooldown, and the next one comes when the
  -- last one has run out (it does not stack with itself).
  local piCd = {}
  local function usePowerInfusion()
    if not PI or buff('powerInfusion') then return false end
    local n, i = max(1, floor((PI.count or 1) + 0.5)), nil
    for q = 1, n do if (piCd[q] or 0) <= S.t + EPS then i = q; break end end
    if not i then return false end
    piCd[i] = S.t + PI.cd
    local lo = n > #piCd and 0 or huge
    for q = 1, #piCd do if piCd[q] < lo then lo = piCd[q] end end
    cds.powerInfusion = lo; buffs.powerInfusion = S.t + PI.duration
    return true
  end
  local function useSpPotion()
    if not spPot or not ready('cd:' .. spPot.cdGroup) then return false end
    cds['cd:' .. spPot.cdGroup] = S.t + spPot.cd; buffs.spPotion = S.t + spPot.spPotion.duration
    return true
  end
  local function eurekaPopOk(key)
    local s = SPELLS[key]
    local len = s.kind == 'channel' and s.duration or castTime(key)
    return (s.kind == 'direct' or s.kind == 'channel') and len >= 1.4
  end
  local function useRacials(key)
    local cd = racialCd
    if not cd or not ready('racial') then return false end
    if cd == EUREKA and key and not eurekaPopOk(key) then return false end
    cds.racial = S.t + cd.cd
    if cd.spPct then buffs.bloodFury = S.t + cd.duration end
    if cd.hastePct then buffs.berserking = S.t + cd.duration end
    if cd == EUREKA then buffs.eureka = S.t + cd.duration end   -- 8 s
    return true
  end
  -- Racial cooldown, Spellblasting potion and Power Infusion, right before a damaging cast.
  local function popActives(key)
    if not ACT_TL then
      if activesOk(key) then useRacials(key); useSpPotion(); usePowerInfusion() end
      return
    end
    gateKey = key
    local g = slotGate(RSLOT)
    if g == 1 or (g == 2 and (ACT_TL[RSLOT] or activesOk(key))) then if useRacials(key) then slotUsed(RSLOT) end end
    if spPot then
      g = slotGate(spPot.key)
      if g == 1 or (g == 2 and (ACT_TL[spPot.key] or activesOk(key))) then if useSpPotion() then slotUsed(spPot.key) end end
    end
    g = slotGate('pi')
    if g == 1 or (g == 2 and (ACT_TL.pi or activesOk(key))) then if usePowerInfusion() then slotUsed('pi') end end
    gateKey = nil
  end
  -- Mana potion / rune: when at least their amount of mana is missing.
  local function useManaItems()
    for i = 1, #manaItems do
      local c = manaItems[i]
      local amt = c.manaRestore.amount or stats.maxMana * c.manaRestore.pct / 100
      local miss = stats.maxMana - S.mana
      local slot = c.key
      local g = slotGate(slot)
      local skip = g == 0 or not ready('cd:' .. c.cdGroup)
      if not skip then if g == 1 then skip = miss <= EPS else skip = miss < amt end end
      if not skip and c.healthCost then
        local hc = round(c.healthCost * selfTakenMult())
        if S.health <= hc then skip = true else loseHealth(hc, 'self') end
      end
      if not skip then
        if amt > miss then amt = miss end
        cds['cd:' .. c.cdGroup] = S.t + c.cd; S.mana = S.mana + amt
        res.manaFromConsumables = (res.manaFromConsumables or 0) + amt
        slotUsed(slot)
      end
    end
  end
  -- Your spell power right now for this spell: sheet + school + Spellblasting potion, x Blood Fury.
  local FURY = racialCd and racialCd.spPct                      -- Blood Fury's spell power %, nil for every race but the Orc
  spNow = function(e)
    local sp = e.sp + ((spPot and buff('spPotion')) and spPot.spPotion.sp or 0)
    if FURY and buff('bloodFury') then return sp * (1 + FURY / 100) end
    return sp
  end

  -- Resistance / Spell Pierce roll for one Warlock damage event. ti > 1 = an extra target with its own curse.
  local resCache = { [true] = {}, [false] = {} }            -- [curse up?][school]
  local xDotLeft, xDebLeft                                -- defined below
  local function resProfile(school, ti)
    local coe
    if (ti or 0) > 1 then coe = xDebLeft(ti, 'coe') > 0
    else
      local e = buffs.coe
      coe = e ~= nil and e > S.t + EPS
    end
    local c = resCache[coe]
    local pr = c[school]
    if not pr then pr = WL.resistProfile(cfg, stats.pierce, school, coe, stats.spellPen); c[school] = pr end
    return pr
  end
  local function vulnMult(school, ti)
    local pr = resProfile(school, ti)
    local m, dist = pr.flat, pr.dist
    local n = #dist
    if n > 1 then
      local x, acc = Rvuln(), 0
      for i = 1, n do
        acc = acc + dist[i].p
        if x < acc or i == n then m = m * (1 + dist[i].pct / 100); break end
      end
    end
    return m
  end

  local HAV = ((fight.targets and fight.targets ~= 0) and fight.targets or 1) >= 2 and tv('baneOfHavoc') > 0 and tbl.baneOfHavoc and SPELLS.baneOfHavoc.havocPct / 100 or 0
  local NT = max(1, min(3, (fight.targets and fight.targets ~= 0) and fight.targets or 1))
  local HAV_T = HAV ~= 0 and 2 or 0
  ROT = WL.effectiveRotation(build, cfg)
  local ACTS = {}                                        -- the action of each entry: built-in, or one of the build's rules
  for i = 1, #ROT do ACTS[i] = WL.actionOf(ROT[i], build) end
  -- Fight timeline: an optional list of spells at fixed start times on top of the priority.
  if build.timeline and #build.timeline > 0 then
    local list = {}
    for i = 1, #build.timeline do list[i] = build.timeline[i] end
    for i = 2, #list do                                  -- stable sort by time
      local x, j = list[i], i - 1
      while j >= 1 and list[j].t > x.t do list[j + 1] = list[j]; j = j - 1 end
      list[j + 1] = x
    end
    TL = { list = list, i = 1, turn = false, wake = nil }
  end
  local xdots, xdeb = {}, {}
  for ti0 = 2, NT do xdots[ti0] = {}; xdeb[ti0] = {} end
  S.xdots, S.xdeb = xdots, xdeb
  S.multiTargets = NT; S.havocTarget = HAV_T; S.nextTarget = 0
  xDotLeft = function(ti, key)
    local d = xdots[ti] and xdots[ti][key]
    return (d and d.expires > S.t + EPS) and d.expires - S.t or 0
  end
  xDebLeft = function(ti, name)
    local e = xdeb[ti] and xdeb[ti][name]
    return (e and e > S.t + EPS) and e - S.t or 0
  end
  S.xDotLeft, S.xDebLeft = xDotLeft, xDebLeft

  local function deal(key, amount, crit, isTick, target)
    local r = bySpell[key] or row(key)
    r.dmg = r.dmg + amount; res.total = res.total + amount
    if isTick then
      r.ticks = r.ticks + 1
      if crit then r.tickCrits = r.tickCrits + 1 end
    else
      r.hits = r.hits + 1
      if crit then r.crits = r.crits + 1 end
    end
    local copied = 0
    local pet = ISPET[key]
    if pet == nil then pet = sub(key, 1, 4) == 'pet:'; ISPET[key] = pet end
    if HAV ~= 0 and not pet and target ~= HAV_T and buff('havoc') then
      local h = row('baneOfHavoc')
      copied = amount * HAV; h.dmg = h.dmg + copied; h.hits = h.hits + 1; res.total = res.total + copied
    end
    if S.targetHpPct < executePct then res.exDmg = res.exDmg + (amount + copied) end
    if not pet then
      local bk = BASEK[key]
      if not bk then
        bk = (sub(key, 1, 1) == 'x' and sub(key, 3, 3) == ':') and sub(key, 4) or key
        BASEK[key] = bk
      end
      local th = (amount + copied) * (THREAT[bk] or threatMult(bk))
      r.threat = r.threat + th; res.threat = res.threat + th
      local lz = bk == 'touchOfTheGrave' and 1 or ((SPELLS[bk] and SPELLS[bk].leech) or 0)
      if lz ~= 0 then gainHealth(amount * lz, 'leech') end
    end
  end

  -- ---------- scheduling ----------
  local LAT = max(0, (fight.latencyMs or 0) / 1000)
  local TRAVEL = max(0, (fight.travelMs or 0) / 1000)
  local function scheduleDecide(t)
    decideToken = decideToken + 1
    push({ t = t > EPS and t + LAT or t, o = 2, type = 'decide', token = decideToken })
  end
  local MV = ((fight.moveEvery or 0) > 0 and (fight.moveDuration or 0) > 0) and { every = fight.moveEvery, dur = fight.moveDuration } or nil
  local function isMoving(t)
    if not MV then return false end
    local k = floor((t + EPS) / MV.every)
    return k >= 1 and t + EPS - k * MV.every < MV.dur
  end
  local function canCastNow(k)
    if not MV then return true end
    local s = SPELLS[k]
    local len = (s and s.kind == 'channel') and s.duration or castTime(k)
    if len <= EPS then return true end
    if isMoving(S.t) then return false end
    local nxt = (floor((S.t + EPS) / MV.every) + 1) * MV.every
    return S.t + len <= nxt + EPS
  end
  S.isMoving = function() return isMoving(S.t) end

  -- Damage taken -> pushback.
  local HIT = (fight.hitEvery or 0) > 0 and fight.hitEvery or 0
  local AURA_PUSH = 0
  for i = 1, #WL.BUFF_ORDER do
    local b = cfg.buffs and cfg.buffs[WL.BUFF_ORDER[i]]
    if b and b.on and b.pushbackResistPct and b.pushbackResistPct ~= 0 then AURA_PUSH = AURA_PUSH + b.pushbackResistPct end
  end
  S.cast = nil
  local function pushResistPct(key)
    local s, p = SPELLS[key], AURA_PUSH
    if s.tree == 'destruction' then p = p + tv('intensity', 'resistPct') end
    if FEL_CONC[key] then p = p + tv('felConcentration', 'resistPct') end
    return min(100, p)
  end
  local function takeHit()
    local c = S.channel
    local k
    if c then k = c.key elseif S.cast and S.t < S.cast.finish - EPS then k = S.cast.key end
    if not k then return end
    local pr = pushResistPct(k)
    if pr > 0 and Rpush() * 100 < pr then res.pushResisted = res.pushResisted + 1; return end
    local lost
    if c then
      local newEnd = max(S.t, c.finish - 0.25 * SPELLS[k].duration)
      lost = c.finish - newEnd; c.finish = newEnd
      local r = row(k); r.castTime = r.castTime - lost
      push({ t = c.finish, o = 1, type = 'chanEnd', inst = c.inst })
    else
      local cs = S.cast
      local step = max(0.2, 1 - 0.2 * cs.n)
      local finish = min(cs.finish + step, S.t + cs.full)
      lost = finish - cs.finish; cs.n = cs.n + 1
      if lost <= EPS then return end
      cs.finish = finish; cs.ev.dead = true
      if tbl[cs.key] and tbl[cs.key].cd ~= 0 and cds[cs.key] and cds[cs.key] ~= 0 then cds[cs.key] = cds[cs.key] + lost end
      if S.spendAt ~= nil then S.spendAt = S.spendAt + lost end
      local old, ne = cs.ev, {}
      for kk, vv in pairs(old) do ne[kk] = vv end
      ne.t = old.t + lost; ne.dead = false
      cs.ev = ne
      push(ne)
      local r = row(cs.rk); r.castTime = r.castTime + lost
    end
    res.pushbacks = res.pushbacks + 1; res.pushbackTime = res.pushbackTime + lost
    S.busyUntil = c and c.finish or S.cast.finish
    scheduleDecide(max(S.busyUntil, S.gcdReady))
  end

  local function applyDot(key, snap)
    local s, e = SPELLS[key], tbl[key]
    inst = inst + 1
    local id = inst
    if s.bane then dots.baneOfAgony = nil; dots.baneOfDoom = nil end
    dots[key] = { inst = id, applied = S.t, expires = S.t + s.duration, tick = 0, ticks = e.ticks, snap = snap }
    for i = 1, e.ticks do push({ t = S.t + i * s.tickEvery, o = 0, type = 'dotTick', key = key, inst = id, i = i - 1 }) end
  end

  -- ---------- extra targets (multi-DoT; per-target Curse of the Elements / Improved Shadow Bolt) ----------
  local function liveMultX(key, ti, periodic)
    local s = SPELLS[key]
    local m = EUREKA and eurekaTick(key, periodic) or 1
    if xDebLeft(ti, 'coe') > 0 then m = m * (1 + coePct / 100) end
    if s.school == 'shadow' and xDebLeft(ti, 'isb') > 0 then m = m * (1 + tv('improvedShadowBolt', 'debuffPct') / 100) end
    if PI and buff('powerInfusion') then m = m * (1 + PI.spellDmgPct / 100) end
    if s.school == 'shadow' and buff('snfShadow') then m = m * (1 + tv('shadowAndFlame', 'schoolPct') / 100) end
    if s.school == 'fire' and buff('snfFire') then m = m * (1 + tv('shadowAndFlame', 'schoolPct') / 100) end
    return m
  end
  local function applyDotX(ti, key, snap)
    local s, e = SPELLS[key], tbl[key]
    inst = inst + 1
    local id = inst
    xdots[ti][key] = { inst = id, applied = S.t, expires = S.t + s.duration, ticks = e.ticks, snap = snap }
    for i = 1, e.ticks do push({ t = S.t + i * s.tickEvery, o = 0, type = 'dotTickX', ti = ti, key = key, inst = id, i = i - 1 }) end
  end
  local function nightfallRoll(key)
    if NIGHTFALL[key] and tv('nightfall') ~= 0 and Rproc() * 100 < tv('nightfall', 'procPct') then buffs.shadowTrance = S.t + 10 end
  end
  local function periodicTickX(ti, key, snap, i)
    local s, e, rk = SPELLS[key], tbl[key], xkey(ti, key)
    local amt = (s.tickBase + s.tickCoef * spNow(e)) * e.periodicMult * liveMultX(key, ti, true) * (snap.castMult or 1)
    if s.ramp then amt = amt * s.ramp[i + 1] end
    amt = amt * vulnMult(s.school, ti)
    local crit = Rcrit() * 100 < e.critPct
    if crit then amt = amt * e.critMult end
    deal(rk, amt, crit, true, ti)
    nightfallRoll(key)
  end
  local makeSnap, touchOfTheGrave, jowProc               -- defined below
  local P = nil                                          -- the pet
  local function landExtra(key, eureka, castMult, ti)
    local s, e, rk = SPELLS[key], tbl[key], xkey(ti, key)
    local r = row(rk)
    if Rhit() * 100 >= stats.hitPct then r.misses = r.misses + 1; return false end
    r.landed = r.landed + 1
    if s.kind == 'utility' then
      if key == 'curseOfElements' then xdeb[ti].coe = S.t + s.duration end
      return true
    end
    if s.kind == 'hybrid' or s.kind == 'direct' then
      local amt = (s.base + s.coef * spNow(e)) * e.directMult * liveMultX(key, ti, false) * (eureka and eurekaMult(key, false) or 1)
      local execute = S.targetHpPct < executePct
      if (key == 'shadowBolt' or key == 'searingPain') and execute and tv('decimation') ~= 0 then
        amt = amt * addOp0(key, tv('decimation', 'dmgPct')); buffs.decimation = S.t + 10
      end
      amt = amt * vulnMult(s.school, ti)
      local crit = Rcrit() * 100 < e.critPct
      if crit then amt = amt * e.critMult end
      deal(rk, amt, crit, false, ti)
      if key == 'shadowBolt' and crit and tv('improvedShadowBolt') ~= 0 then xdeb[ti].isb = S.t + 12 end
    end
    if s.kind ~= 'direct' then applyDotX(ti, key, makeSnap(castMult)) end
    touchOfTheGrave(ti)
    return true
  end

  -- castMult multiplies every tick of this cast as a whole (Amplify Curse).
  makeSnap = function(castMult) return { castMult = castMult or 1 } end

  local function periodicTick(key, snap, i)
    local s, e = SPELLS[key], tbl[key]
    local amt = (s.tickBase + s.tickCoef * spNow(e)) * e.periodicMult * liveMult(key, true) * (snap.castMult or 1)
    if s.ramp then amt = amt * s.ramp[i + 1] end
    amt = amt * vulnMult(s.school)
    local crit = Rcrit() * 100 < e.critPct
    if crit then amt = amt * e.critMult end
    deal(key, amt, crit, true)
    nightfallRoll(key)
  end

  -- A tick of an area channel (Hellfire, Rain of Fire): every target takes its own damage event.
  local function aoeTick(key, i)
    local s, e = SPELLS[key], tbl[key]
    for ti = 1, NT do
      local rk = ti > 1 and xkey(ti, key) or key
      local r = row(rk)
      if Rhit() * 100 >= stats.hitPct then r.misses = r.misses + 1
      else
        local amt = (s.tickBase + s.tickCoef * spNow(e)) * e.periodicMult * (ti > 1 and liveMultX(key, ti, true) or liveMult(key, true))
        amt = amt * vulnMult(s.school, ti)
        local crit = Rcrit() * 100 < e.critPct
        if crit then amt = amt * e.critMult end
        deal(rk, amt, crit, true, ti)
      end
    end
    if s.selfDamage then loseHealth(selfTick(key), 'self') end
  end

  -- Direct-damage landing (cast finished or instant). Returns true if it hit.
  local function land(key, eureka, castMult, target)
    if (target or 0) > 1 then return landExtra(key, eureka, castMult, target) end
    local s, e, r = SPELLS[key], tbl[key], bySpell[key] or row(key)
    if Rhit() * 100 >= stats.hitPct then r.misses = r.misses + 1; return false end
    r.landed = r.landed + 1
    if s.kind == 'utility' then
      if key == 'curseOfElements' then buffs.coe = S.t + s.duration end
      jowProc(false)
      return true
    end
    if s.kind == 'dot' then applyDot(key, makeSnap(castMult)); touchOfTheGrave(); jowProc(false); return true end
    -- direct or hybrid
    local sp = spNow(e)
    local amt = (s.base + s.coef * sp) * e.directMult * liveMult(key, false) * (eureka and eurekaMult(key, false) or 1)
    if key == 'incinerate' and dotLeft('immolate') > 0 then amt = amt * (1 + s.immolateBonusPct / 100) end
    local execute = S.targetHpPct < executePct
    if (key == 'shadowBolt' or key == 'searingPain') and execute and tv('decimation') ~= 0 then
      amt = amt * addOp0(key, tv('decimation', 'dmgPct'))
      buffs.decimation = S.t + 10
    end
    amt = amt * vulnMult(s.school)
    local crit = Rcrit() * 100 < e.critPct
    if crit then amt = amt * e.critMult end
    deal(key, amt, crit, false)
    if key == 'shadowBolt' and crit and tv('improvedShadowBolt') ~= 0 then buffs.isb = S.t + 12 end
    if key == 'searingPain' and tv('demonicBrand') ~= 0 and P then
      buffs.brand = S.t + cfg.demonicBrand.duration; S.brandCharges = tv('demonicBrand', 'charges')
    end
    if key == 'conflagrate' then
      if tv('shadowAndFlame') ~= 0 then buffs.snfShadow = S.t + 20 end
      if not (tv('shadowAndFlame') ~= 0 and Rproc() * 100 < tv('shadowAndFlame', 'procPct')) then dots.immolate = nil end
    end
    if key == 'shadowburn' and tv('shadowAndFlame') ~= 0 then
      buffs.snfFire = S.t + 20
      if Rproc() * 100 < tv('shadowAndFlame', 'procPct') then S.shards = S.shards + 1 end
    end
    if s.kind == 'hybrid' then applyDot(key, makeSnap(castMult)) end
    touchOfTheGrave()
    jowProc(false)
    return true
  end
  -- Judgement of Wisdom on the boss: each landed spell you cast at it and each landed pet attack may restore mana.
  local JOW = (cfg.debuffs and cfg.debuffs.judgementOfWisdom and cfg.debuffs.judgementOfWisdom.on) and cfg.debuffs.judgementOfWisdom.jow or nil
  local petRegen                                         -- defined below
  jowProc = function(pet)
    if not JOW or Rjow() * 100 >= JOW.chancePct then return end
    if pet then
      if not P then return end
      petRegen()
      local pb = P.mana
      P.mana = min(P.maxMana, P.mana + JOW.mana)
      res.petManaFromJow = (res.petManaFromJow or 0) + (P.mana - pb)
      return
    end
    local before = S.mana
    S.mana = min(stats.maxMana, S.mana + JOW.mana)
    res.manaFromJow = (res.manaFromJow or 0) + (S.mana - before)
  end
  -- Touch of the Grave (Undead): rolls once per landed cast of a spell with a damage component. 5% of your maximum
  -- health; nothing multiplies it. 30% chance, then a 25 s internal cooldown (no roll while it runs).
  touchOfTheGrave = function(ti)
    local tog = racialProc
    if tog and not (S.togReady and S.togReady > S.t + EPS) and Rproc() * 100 < tog.chancePct then
      S.togReady = S.t + (tog.icd or 0)
      local td = stats.maxHealth * tog.maxHealthPct / 100
      deal('touchOfTheGrave', td, false, false, ((ti or 0) > 1) and ti or nil)
      local r = row('touchOfTheGrave'); r.casts = r.casts + 1
    end
  end

  -- Engineering explosives: thrown on cooldown; instant, 1 s item GCD; fixed damage, spell hit roll, crit at the sheet crit.
  local function useExplosive()
    if S.t >= dur - EPS then return false end
    for i = 1, #explosives do
      local c = explosives[i]
      local x, key = c.explosive, 'item:' .. c.key
      local r = row(key)
      local ok = ready('cd:' .. x.cdGroup) and slotGate(c.key) ~= 0
      if ok and x.selfMax then
        local sm = selfTakenMult()
        if S.health <= x.selfMax * sm then ok = false
        else loseHealth(round((x.selfMin + x.selfMax) / 2 * sm), 'self') end
      end
      if ok then
        cds['cd:' .. x.cdGroup] = S.t + x.cd; slotUsed(c.key)
        r.casts = r.casts + 1; r.castTime = r.castTime + cb.minGcd
        S.busyUntil = S.t; S.gcdReady = S.t + cb.minGcd
        if Rhit() * 100 >= stats.hitPct then r.misses = r.misses + 1
        else
          r.landed = r.landed + 1
          local amt = x.min + (x.max - x.min) * Rproc()
          if buff('coe') then amt = amt * (1 + coePct / 100) end
          local crit = Rcrit() * 100 < cfg.gear.critPct
          if crit then amt = amt * cb.critMultiplier end
          deal(key, amt, crit, false)
        end
        scheduleDecide(S.gcdReady)
        return true
      end
    end
    return false
  end

  -- ---------- casting ----------
  local function effectiveCost(key)
    local c = tbl[key].cost
    if eurekaAt(key, finishesAt(key)) then c = c * (1 - EUREKA.costRedPct / 100) end
    return c
  end
  -- Cost if Eureka! were popped now (used to decide whether popping racials is worthwhile before this cast).
  local function discountedCost(key)
    local cd, c = racialCd, tbl[key].cost
    if cd and cd.costRedPct and (buff('eureka') or ready('racial')) then c = c * (1 - cd.costRedPct / 100) end
    return c
  end
  local function minManaCheck() if S.mana < res.minMana then res.minMana = S.mana end end

  local function startCast(key, target, fromTL, actIdx)
    local s, e = SPELLS[key], tbl[key]
    local rk = (target or 0) > 1 and xkey(target, key) or key
    local castT, gcdT = castTime(key), gcd()
    local instantTrance = key == 'shadowBolt' and buff('shadowTrance')
    local paid = effectiveCost(key)
    S.mana = S.mana - paid
    if paid > 0 then
      if castT > EPS and s.kind ~= 'channel' then S.spendAt = S.t + castT else S.lastSpend = S.t end
    end
    -- Amplify Curse: off the GCD, next Bane of Agony +50% (its final tick value after all calculations x 1.5); 3 min cooldown.
    local castMult = 1
    if key == 'baneOfAgony' and tv('amplifyCurse') ~= 0 and ready('amplifyCurse') and slotGate('amplifyCurse') ~= 0 then
      castMult = 1 + tv('amplifyCurse', 'boaPct') / 100; cds.amplifyCurse = S.t + 180; slotUsed('amplifyCurse')
    end
    if s.shards and not (key == 'soulFire' and buff('decimation')) then S.shards = S.shards - s.shards end
    if key == 'soulFire' and buff('decimation') then buffs.decimation = nil end
    if instantTrance then buffs.shadowTrance = nil end
    -- A cooldown starts when the cast is COMPLETE, not when it begins.
    if e.cd ~= 0 then cds[key] = S.t + castT + e.cd end
    local rr = bySpell[rk] or row(rk); rr.casts = rr.casts + 1
    minManaCheck()

    S.cast = nil
    if s.kind == 'channel' then
      local r = row(key)
      if not s.aoe and Rhit() * 100 >= stats.hitPct then
        r.misses = r.misses + 1
        if fromTL then TL.turn = true end
        S.busyUntil = S.t; S.gcdReady = S.t + gcdT; scheduleDecide(S.gcdReady)
        return
      end
      r.landed = r.landed + 1
      touchOfTheGrave()
      jowProc(false)
      inst = inst + 1
      local id = inst
      S.channel = { key = key, inst = id, snap = makeSnap(), start = S.t, finish = S.t + s.duration, tl = fromTL and true or false, idx = actIdx }
      for i = 1, e.ticks do push({ t = S.t + i * s.tickEvery, o = 0, type = 'chanTick', key = key, inst = id, i = i - 1 }) end
      S.busyUntil = S.t + s.duration; S.gcdReady = S.t + gcdT
      r.castTime = r.castTime + s.duration
      scheduleDecide(S.busyUntil)
    elseif castT > EPS then
      S.busyUntil = S.t + castT; S.gcdReady = S.t + gcdT
      rr.castTime = rr.castTime + castT
      local ce = { t = S.busyUntil + (s.projectile and TRAVEL or 0), o = 1, type = 'castEnd', key = key, castMult = castMult, target = target, tl = fromTL }
      push(ce)
      S.cast = { key = key, rk = rk, full = castT, finish = S.busyUntil, ev = ce, n = 0 }
      scheduleDecide(max(S.busyUntil, S.gcdReady))
    else
      S.busyUntil = S.t; S.gcdReady = S.t + gcdT
      rr.castTime = rr.castTime + gcdT
      if s.projectile and TRAVEL > EPS then
        push({ t = S.t + TRAVEL, o = 1, type = 'castEnd', key = key, castMult = castMult, target = target, tl = fromTL })
      else
        if not land(key, eurekaAt(key, S.t), castMult, target) and fromTL then TL.turn = true end
      end
      scheduleDecide(S.gcdReady)
    end
  end

  local function lifeTap(moving)
    if not canTap() then resHealth.blocked = resHealth.blocked + 0.1; res.idle = res.idle + 0.1; scheduleDecide(S.t + 0.1); return end
    loseHealth(TAP_HP, 'tap')
    local gain = (SPELLS.lifeTap.manaBase + stats.spi) * (1 + tv('improvedLifeTap', 'manaPct') / 100)
    local before = S.mana
    S.mana = min(stats.maxMana, S.mana + gain)
    res.lifeTaps = res.lifeTaps + 1; res.manaFromTaps = res.manaFromTaps + (S.mana - before)
    local r = row('lifeTap'); r.casts = r.casts + 1
    S.busyUntil = S.t; S.gcdReady = S.t + gcd()
    res.tapTime = (res.tapTime or 0) + gcd()
    if moving then res.movingTaps = (res.movingTaps or 0) + 1 end
    if P and tv('demonicEnergies') ~= 0 then
      petRegen(); P.mana = min(P.maxMana, P.mana + (S.mana - before) * tv('demonicEnergies', 'tapPct') / 100)
    end
    scheduleDecide(S.gcdReady)
  end

  -- ---------- pet actor ----------
  local petGen = 0
  local function makePet(key)
    if not key or not cfg.options.includePetDamage then return nil end
    local pc = cfg.pets[key]
    petGen = petGen + 1
    local p = { key = key, c = pc, maxMana = pc.mana * (1 + tv('felVitality', 'manaPct') / 100), lastRegen = S.t, lashReady = 0, gen = petGen }
    p.mana = p.maxMana
    return p
  end
  P = makePet(build.pet)
  petRegen = function() P.mana = min(P.maxMana, P.mana + P.c.manaRegen * (S.t - P.lastRegen)); P.lastRegen = S.t end
  S.petManaPct = function() if not P then return 100 end; petRegen(); return 100 * P.mana / P.maxMana end
  S.petSpellCost = function() return (P and P.c.spell) and P.c.spell.cost or huge end
  S.petMana = function() if not P then return huge end; petRegen(); return P.mana end
  S.tapGain = function() return (SPELLS.lifeTap.manaBase + stats.spi) * (1 + tv('improvedLifeTap', 'manaPct') / 100) end
  S.maxMana = stats.maxMana
  local petAct, petSpellHit, petSwing
  do
  local UNHOLY, MASTER = 1 + tv('unholyPower', 'petDmgPct') / 100, 1 + tv('masterDemonologist', 'schoolPct') / 100
  local CMD = racialOf(race, 'petDmgPct')                       -- Command (Orc): the demon deals 5% more, all of it
  CMD = CMD and 1 + CMD.value / 100
  local function petMult(school)
    local m = UNHOLY * stats.mult.all
    if CMD then m = m * CMD end
    if (build.pet == 'succubus' and school == 'shadow') or (build.pet == 'imp' and school == 'fire') then m = m * MASTER end
    if school ~= 'physical' then
      local e = buffs.coe
      if e ~= nil and e > S.t + EPS then m = m * (1 + coePct / 100) end
    end
    return m
  end
  local function warlockSpNow()
    local sp = stats.sp + ((spPot and buff('spPotion')) and spPot.spPotion.sp or 0)
    if FURY and buff('bloodFury') then return sp * (1 + FURY / 100) end
    return sp
  end
  local function petSp() return warlockSpNow() * (cfg.petSpPct ~= nil and cfg.petSpPct or 100) / 100 + (stats.dkSp or 0) end
  -- Demonic Brand: a landed pet attack on a branded target spends a charge and adds bonus damage.
  local function brandProc()
    if not buff('brand') or not ((S.brandCharges or 0) > 0) then return end
    S.brandCharges = S.brandCharges - 1
    local db, school = cfg.demonicBrand, build.pet == 'imp' and 'fire' or 'shadow'
    local m = petMult(school)
    local amt = ((db.baseMin + db.baseMax) / 2 + db.shadowSpCoef * (warlockSpNow() + (stats.schoolSp.shadow or 0))) * m
    deal('pet:brand', amt, false, false)
    local r = row('pet:brand'); r.casts = r.casts + 1
  end
  petSpellHit = function(sp)
    local key = sp.rowKey
    if not key then key = 'pet:' .. sp.key; sp.rowKey = key end
    local r = bySpell[key] or row(key)
    r.casts = r.casts + 1
    if Rpet() * 100 >= stats.hitPct then r.misses = r.misses + 1; return end
    r.landed = r.landed + 1
    jowProc(true)
    local base = sp.base * (sp.key == 'lashOfPain' and 1 + tv('improvedSayaad', 'lashPct') / 100 or 1)
    local amt = (base + sp.coef * petSp()) * petMult(sp.school)
    if sp.key == 'firebolt' then amt = amt * (1 + tv('improvedImp', 'firebolt') / 100) end
    local crit = Rpet() * 100 < stats.critPct
    if crit then amt = amt * cb.critMultiplier end
    deal(key, amt, crit, false)
    brandProc()
  end
  petAct = function()
    if not P or not P.c.spell or S.t >= dur - EPS then return end
    petRegen()
    local sp = P.c.spell
    local hasCd = sp.cd and sp.cd ~= 0
    if hasCd and P.lashReady > S.t + EPS then push({ t = P.lashReady, o = 2, type = 'petAct', gen = P.gen }); return end
    if P.mana < sp.cost then
      local wait = max(0.1, (sp.cost - P.mana) / P.c.manaRegen)
      res.petOomTime = res.petOomTime + min(wait, dur - S.t)
      push({ t = S.t + wait, o = 2, type = 'petAct', gen = P.gen }); return
    end
    P.mana = P.mana - sp.cost
    if hasCd then P.lashReady = S.t + sp.cd end
    if sp.cast and sp.cast ~= 0 then
      push({ t = S.t + sp.cast + (sp.projectile and TRAVEL or 0), o = 1, type = 'petLand', gen = P.gen })
      push({ t = S.t + sp.cast, o = 2, type = 'petAct', gen = P.gen })
    else
      petSpellHit(sp)
      push({ t = (P.lashReady ~= 0 and P.lashReady) or (S.t + 1.5), o = 2, type = 'petAct', gen = P.gen })
    end
  end
  local function petMeleeAttack(rk, roll)       -- one swing; true if it landed
    local m, r, tb = P.c.melee, bySpell[rk] or row(rk), cb.petMelee
    r.casts = r.casts + 1
    local hitBonus = WL.petMeleeHit(stats, cb)       -- her melee hit: 8/17 of your spell hit, all of it counts
    local miss = max(0, tb.missPct - hitBonus)
    local critCh = max(0, (m.critPct or 0) + (m.inheritSpellCrit and stats.critPct or 0) - tb.critSuppressionPct)
    if roll >= miss + tb.dodgePct then
      r.landed = r.landed + 1
      jowProc(true)
      local dps = m.baseDps + m.apPerSp * warlockSpNow() / m.apPerDps
      local amt = dps * m.swing * (1 - armorRed) * petMult('physical')
      local glance = roll < miss + tb.dodgePct + tb.glancePct
      local crit = not glance and roll < miss + tb.dodgePct + tb.glancePct + critCh
      if glance then amt = amt * (tb.glanceDmgPct / 100); r.glances = r.glances + 1 end
      if crit then amt = amt * 2 end
      deal(rk, amt, crit, false)
      brandProc()
      return true
    end
    r.misses = r.misses + 1
    return false
  end
  petSwing = function()
    if S.t >= dur - EPS then return end
    petMeleeAttack('pet:melee', Rpet() * 100)
    push({ t = S.t + P.c.melee.swing, o = 0, type = 'petSwing', gen = P.gen })
  end
  end

  -- ---------- mid-fight pet swap ----------
  local PS = cfg.petSwap or nil
  S.swapped = false
  S.canSwap = function(to)
    local gs = slotGate('petSwap')
    return PS ~= nil and not S.swapped and build.pet ~= nil and build.pet ~= to
      and (gs == 1 or (gs == 2 and not (ACT_TL and ACT_TL.petSwap) and S.targetHpPct < executePct))
      and tv('felDomination') > 0 and tv('demonicSacrifice') > 0 and tv('demonicPact') > 0 and ready('felDomination')
  end
  local finishSummon, doSwap
  do
  local function summonCost(to)
    local ms = tv('masterSummoner')
    local red = PS.felDom.costRedPct + (ms ~= 0 and PS.masterSummoner.costRedPct[ms] or 0)
    return WL.WARLOCK_BASE_60.mana * PS.summonCostPctBase[to] / 100 * max(0, 1 - red / 100)
  end
  local function summonCast()
    local ms = tv('masterSummoner')
    return max(0, PS.summonCast - PS.felDom.castRed - (ms ~= 0 and PS.masterSummoner.castRed[ms] or 0))
  end
  local function rebuild(b)
    build = b; S.build = b
    stats = WL.computeStats(b, raceKey, cfg); tbl = WL.buildSpellTable(b, stats, cfg)
    hasteBase = 1 + stats.hastePct / 100
    S.maxMana = stats.maxMana; S.mana = min(S.mana, stats.maxMana)
  end
  finishSummon = function(to)
    local nb = copy(build); nb.pet = to; rebuild(nb)
    P = makePet(to)
    if P and P.c.spell then push({ t = S.t, o = 2, type = 'petAct', gen = P.gen }) end
    if P and P.c.melee then push({ t = S.t, o = 0, type = 'petSwing', gen = P.gen }) end
  end
  doSwap = function(to)
    local cost = summonCost(to)
    if S.mana < cost then lifeTap(); return end
    local from, nb = build.pet, copy(build)
    S.swapped = true; res.swapAt = S.t; slotUsed('petSwap')
    nb.sacrifice = from; nb.pet = nil; P = nil; rebuild(nb)
    cds.felDomination = S.t + PS.felDom.cd
    S.mana = S.mana - cost; minManaCheck()
    if cost > 0 then S.lastSpend = S.t end
    local castT, gcdT = summonCast() / hasteFactor(), gcd()
    S.busyUntil = S.t + castT; S.gcdReady = S.t + gcdT
    if castT > EPS then push({ t = S.busyUntil, o = 1, type = 'summonEnd', to = to })
    else finishSummon(to) end
    scheduleDecide(max(S.busyUntil, S.gcdReady))
  end
  end

  -- ---------- end-of-fight DoT check ----------
  do                                                     -- (a block: these names are only needed in here)
  local DOT_END = not (cfg.options and cfg.options.dotEndCheck == false)
  local function expVuln(school, ti)
    local pr = resProfile(school, ti)
    local a = 0
    for i = 1, #pr.dist do a = a + pr.dist[i].p * (1 + pr.dist[i].pct / 100) end
    return pr.flat * a
  end
  local function expCrit(critPct, critMult) return 1 + max(0, min(100, critPct)) / 100 * (critMult - 1) end
  local function lmult(key, ti, periodic)
    if (ti or 0) > 1 then return liveMultX(key, ti, periodic) end
    return liveMult(key, periodic)
  end
  local function hitChance() return min(100, stats.hitPct) / 100 end
  local function occupies(key) return SPELLS[key].kind == 'channel' and SPELLS[key].duration or max(castTime(key), gcd()) end
  -- Expected damage of one cast of a direct spell or a full channel right now.
  local function expCast(key, ti, noImmolate)
    local s, e = SPELLS[key], tbl[key]
    local amt
    if s.aoe then
      local sum = 0
      for tj = 1, NT do sum = sum + e.ticks * (s.tickBase + s.tickCoef * spNow(e)) * e.periodicMult * lmult(key, tj, true) * expVuln(s.school, tj) end
      return hitChance() * sum * expCrit(e.critPct, e.critMult)
    end
    if s.kind == 'channel' then
      amt = 0
      for i = 1, e.ticks do amt = amt + (s.tickBase + s.tickCoef * spNow(e)) * e.periodicMult * lmult(key, ti, true) * (s.ramp and s.ramp[i] or 1) end
    else
      amt = (s.base + s.coef * spNow(e)) * e.directMult * lmult(key, ti, false)
      if key == 'incinerate' and not noImmolate and dotLeft('immolate') > 0 then amt = amt * (1 + s.immolateBonusPct / 100) end
      if (key == 'shadowBolt' or key == 'searingPain') and S.targetHpPct < executePct and tv('decimation') ~= 0 then amt = amt * addOp0(key, tv('decimation', 'dmgPct')) end
    end
    return hitChance() * amt * expVuln(s.school, ti) * expCrit(e.critPct, e.critMult)
  end
  -- What the rotation would cast instead of the DoT: the first action below it that picks a damaging direct spell or channel.
  local function altBelow(idx)
    for i = (idx or 0) + 1, #ROT do
      local a = ACTS[i]
      if a and not NOT_ALT[ROT[i]] then
        local k = a.pick(S)
        local s = k and SPELLS[k]
        if s and tbl[k] and (s.kind == 'direct' or s.kind == 'channel') then return k end
      end
    end
    return tbl.shadowBolt and 'shadowBolt' or nil
  end
  -- Is recasting DoT `key` on target `ti` now worth more than the filler in the same time?
  local function dotValueWorth(key, ti)
    local s, e = SPELLS[key], tbl[key]
    local castT = castTime(key)
    local tL = S.t + castT
    local f = altBelow(S.actionIndex)
    local fRate = f and expCast(f, 0, key == 'immolate') / (occupies(f) + LAT) or 0
    local cost = (occupies(key) + LAT) * fRate
    local finish, g, value = min(dur, tL + s.duration), gcd(), 0
    local castMult = (key == 'baneOfAgony' and tv('amplifyCurse') ~= 0 and ready('amplifyCurse') and slotGate('amplifyCurse') ~= 0) and 1 + tv('amplifyCurse', 'boaPct') / 100 or 1
    local tickAmt = (s.tickBase + s.tickCoef * spNow(e)) * castMult * e.periodicMult * lmult(key, ti, true) * expVuln(s.school, ti) * expCrit(e.critPct, e.critMult)
    if f == 'wrack' and WRACK_SET[key] then tickAmt = tickAmt * (1 + SPELLS.wrack.debuffPct / 100) end
    local hit, tConf, keep = hitChance(), huge, 1
    local cfx = indexOf(ROT, 'conflagrateExpire') ~= nil and indexOf(ROT, 'conflagrate') == nil
    if key == 'immolate' and ti <= 1 and (indexOf(ROT, 'conflagrate') or indexOf(ROT, 'conflagrateSnF') or cfx) and has('conflagrate') then
      tConf = max(cfx and tL + s.duration - WL.CONFLAG_EXPIRE_S or tL, cds.conflagrate or 0)
      if tConf < finish - 1e-6 and tConf <= dur - g + EPS then
        keep = tv('shadowAndFlame') ~= 0 and tv('shadowAndFlame', 'procPct') / 100 or 0
        value = value + hit * (expCast('conflagrate', 0) - g * fRate)
      else tConf = huge end
    end
    local nTicks, ticks = 0, 0
    for i = 1, e.ticks do
      local tt = tL + i * s.tickEvery
      if tt > dur + EPS then break end
      nTicks = nTicks + 1
      ticks = ticks + tickAmt * (s.ramp and s.ramp[i] or 1) * (tt > tConf + EPS and keep or 1)
    end
    value = value + hit * ticks
    if s.kind == 'hybrid' then value = value + expCast(key, ti) end
    local up = max(0, finish - (S.t + occupies(key)))
    if key == 'immolate' and ti <= 1 and f == 'incinerate' then
      value = value + hit * up / occupies('incinerate') * expCast('incinerate', 0, true) * SPELLS.incinerate.immolateBonusPct / 100
    end
    local sbKey = (tbl.shadowBolt and (indexOf(ROT, 'shadowTrance') or (f and f == 'shadowBolt'))) and 'shadowBolt' or nil
    if NIGHTFALL[key] and tv('nightfall') ~= 0 and sbKey then
      local procTicks = 0
      for j = 1, nTicks do if tL + j * s.tickEvery <= dur - g + EPS then procTicks = procTicks + 1 end end
      local sbNow, sbCast = expCast(sbKey, 0), tbl[sbKey].cast / hasteFactor()
      value = value + hit * procTicks * tv('nightfall', 'procPct') / 100 * max(0, sbNow - g * (sbKey == f and sbNow / max(sbCast, g) or fRate))
    end
    if f and SPELLS[f].drain and tv('soulSiphon') ~= 0 and ti <= 1 and SIPHON_SET[key] then
      local others, per, cap = 0, tv('soulSiphon', 'perEffectPct'), tv('soulSiphon', 'maxPct')
      for i = 1, #SIPHON_LIST do
        local x = SIPHON_LIST[i]
        if x ~= key then
          if x == 'curseOfElements' then if buff('coe') then others = others + 1 end elseif dotLeft(x) > 0 then others = others + 1 end
        end
      end
      local now = 1 + min((others + (dotLeft(key) > 0 and 1 or 0)) * per, cap) / 100
      local gain = (min((others + 1) * per, cap) - min(others * per, cap)) / 100
      value = value + hit * up * fRate / now * gain
    end
    return value >= cost
  end
  -- Used by the rotation (dotNeeded, bane, multiDot): true = recast, nil = check off (the rotation uses the old rule).
  S.dotWorth = function(key, ti)
    if not DOT_END then return nil end
    local s = SPELLS[key]
    if not tbl[key] or S.t + castTime(key) + s.duration <= dur + EPS then return true end
    return dotValueWorth(key, ti or 0)
  end
  end

  -- Time a priority spell takes before the next decision (cast or GCD, whichever is longer).
  local function tlOccupies(k)
    if k == 'lifeTap' or not SPELLS[k] or sub(k, 1, 5) == 'swap:' then return gcd() end
    return max(castTime(k), gcd())
  end
  local function pickAction(excludeFrom, fitBy)
    for i = 1, #ROT do
      if excludeFrom ~= nil and i >= excludeFrom then return nil end
      local a = ACTS[i]
      if not a then error('Unknown priority action: ' .. tostring(ROT[i])) end
      S.nextTarget = 0
      S.actionIndex = i
      local k = a.pick(S)
      if k then
        if sub(k, 1, 5) == 'swap:' then return k, i, 0 end
        local skip = fitBy ~= nil and tbl[k] and SPELLS[k].kind ~= 'channel' and S.t + tlOccupies(k) > fitBy + EPS
        if not skip and k == 'lifeTap' and not canTap() then skip = true end
        if not skip and tbl[k] and canCastNow(k) and healthOk(k) then return k, i, S.nextTarget or 0 end
      end
    end
    return nil
  end

  -- ---------- fight timeline ----------
  local timelineStep
  do
  local function tlUsable(k)
    if k == 'conflagrate' then return dotLeft('immolate') > 0 end
    if k == 'shadowburn' then return S.shards > 0 end
    if k == 'soulFire' then return buff('decimation') or S.shards > 0 end
    return true
  end
  -- Casts the next due timeline entry (true = handled). Sets TL.wake = when the timeline needs the caster next.
  timelineStep = function()
    TL.wake = nil
    while TL.i <= #TL.list do
      local e = TL.list[TL.i]
      local k = e.k
      if e.t > dur - EPS then TL.i = #TL.list + 1; break end
      if S.t + EPS < e.t then TL.wake = e.t; return false end
      if k == 'lifeTap' then TL.i = TL.i + 1; lifeTap(); return true end
      if not tbl[k] or not has(k) or (SPELLS[k].talent and tv(SPELLS[k].talent) == 0) or not tlUsable(k) then
        TL.i = TL.i + 1
      elseif not ready(k) then TL.wake = cds[k]; return false
      elseif not canCastNow(k) then TL.wake = S.t + 0.1; return false
      elseif S.mana < effectiveCost(k) then
        if stats.maxMana < effectiveCost(k) then TL.i = TL.i + 1
        else lifeTap(); return true end
      else
        TL.i = TL.i + 1
        if SPELLS[k].kind ~= 'utility' and S.mana >= discountedCost(k) then popActives(k) end
        startCast(k, 0, true)
        return true
      end
    end
    return false
  end
  end

  local function decide()
    if S.t >= dur - EPS then return end
    if HAV ~= 0 and not buff('havoc') then
      S.mana = S.mana - tbl.baneOfHavoc.cost; buffs.havoc = S.t + SPELLS.baneOfHavoc.duration
      if tbl.baneOfHavoc.cost > 0 then S.lastSpend = S.t end
      local r = row('baneOfHavoc'); r.casts = r.casts + 1
    end
    manaBuffCheck()
    useManaItems()
    if #explosives > 0 and useExplosive() then return end
    if TL and not TL.turn and timelineStep() then return end
    local fit = (TL and not TL.turn and TL.wake ~= nil) and TL.wake or nil
    local key, index, target = pickAction(nil, fit)
    if TL and TL.turn then TL.turn = false end
    if not key and TL and TL.wake ~= nil and TL.wake > S.t + EPS then res.idle = res.idle + (TL.wake - S.t); scheduleDecide(TL.wake); return end
    if not key and MV and fight.lifeTapWhileMoving and S.mana < stats.maxMana - EPS and canTap() then lifeTap(true); return end
    if not key then res.idle = res.idle + 0.1; scheduleDecide(S.t + 0.1); return end
    if key == 'lifeTap' then lifeTap(); return end
    if sub(key, 1, 5) == 'swap:' then doSwap(sub(key, 6)); return end
    -- Racial cooldowns fire only right before an actual damaging cast (never before a curse or a Life Tap).
    local damaging = SPELLS[key].kind ~= 'utility'
    if damaging and S.mana >= discountedCost(key) then popActives(key) end
    if S.mana < effectiveCost(key) then
      if stats.maxMana < effectiveCost(key) then res.oom = res.oom + 1; scheduleDecide(S.t + 1); return end
      lifeTap(); return
    end
    startCast(key, target, false, index)
  end

  local function chanTick(ev)
    local c = S.channel
    if not c or c.inst ~= ev.inst then return end          -- clipped
    if ev.t > c.finish + EPS then return end               -- cut off by pushback; chanEnd closes the channel
    if SPELLS[ev.key].aoe then aoeTick(ev.key, ev.i) else periodicTick(ev.key, c.snap, ev.i) end
    local last = ev.i == tbl[ev.key].ticks - 1
    if last then
      S.channel = nil; return
    end
    if SPELLS[ev.key].selfDamage and S.health <= selfTick(ev.key) then   -- the next Hellfire tick would kill you
      S.channel = nil; res.clipped = res.clipped + 1
      local r = row(ev.key); r.castTime = r.castTime - (c.finish - S.t)
      S.busyUntil = S.t; scheduleDecide(max(S.t, S.gcdReady)); return
    end
    -- A priority channel in a timeline gap ends when the next timeline entry is due.
    if TL and TL.i <= #TL.list and TL.list[TL.i].t <= S.t + EPS and not c.tl then
      S.channel = nil; res.clipped = res.clipped + 1
      local r = row(ev.key); r.castTime = r.castTime - (c.finish - S.t)
      S.busyUntil = S.t; scheduleDecide(S.t); return
    end
    -- Clip the channel when something higher in the priority list is ready (and the GCD allows it).
    if S.t >= S.gcdReady - EPS and not c.tl then
      local idx = c.idx ~= nil and c.idx or indexOf(ROT, ev.key)
      local higher = pickAction(idx or (#ROT + 1))
      if higher then
          S.channel = nil; res.clipped = res.clipped + 1
        local r = row(ev.key); r.castTime = r.castTime - (c.finish - S.t)
        S.busyUntil = S.t
        scheduleDecide(S.t)
      end
    end
  end

  -- ---------- main loop ----------
  if cfg.debuffs and cfg.debuffs.coeOther and cfg.debuffs.coeOther.on then buffs.coe = dur + 1 end
  -- Precast: a spell with a cast bar that completes exactly as the fight timer starts.
  local PRE = WL.precastOf(build, cfg, tbl)
  if PRE then
    local preCast, preCost = castTime(PRE), tbl[PRE].cost
    local preGcd = max(0, gcd() - preCast)
    S.mana = S.mana - preCost
    if preCost > 0 then S.lastSpend = 0 end
    if tbl[PRE].cd ~= 0 then cds[PRE] = tbl[PRE].cd end
    if SPELLS[PRE].shards then S.shards = S.shards - SPELLS[PRE].shards end
    S.gcdReady = preGcd
    local r = row(PRE); r.casts = r.casts + 1; r.castTime = r.castTime + preGcd
    minManaCheck()
    push({ t = SPELLS[PRE].projectile and TRAVEL or 0, o = -1, type = 'castEnd', key = PRE, castMult = 1, target = 0 })
    decideToken = decideToken + 1
    push({ t = preGcd + LAT, o = 2, type = 'decide', token = decideToken })
  else scheduleDecide(0) end
  if HEAL then
    local ht = HEAL.every
    while ht < dur - EPS do push({ t = ht, o = 0, type = 'heal' }); ht = ht + HEAL.every end
  end
  local SAC = cfg.demonicSacrifice
  if SAC and (build.sacrifice == 'voidwalker' or build.sacrifice == 'felhunter') then
    local st = SAC.every
    while st < dur - EPS do push({ t = st, o = 0, type = 'sacTick' }); st = st + SAC.every end
  end
  if HIT ~= 0 then push({ t = Rpush() * HIT, o = 1, type = 'dmgTaken' }) end
  if P then
    if P.c.spell then push({ t = 0, o = 2, type = 'petAct', gen = P.gen }) end
    if P.c.melee then push({ t = 0, o = 0, type = 'petSwing', gen = P.gen }) end
  end
  while HN > 0 do
    local ev = pop()
    if ev.t > dur + EPS then break end
    updateTime(ev.t)
    local ty = ev.type
    if ty == 'decide' then
      if ev.token == decideToken then decide() end
    elseif ty == 'dotTick' then
      local d = dots[ev.key]
      if d and d.inst == ev.inst then                      -- else: refreshed or consumed
        periodicTick(ev.key, d.snap, ev.i)
        if ev.i == d.ticks - 1 then dots[ev.key] = nil end
      end
    elseif ty == 'castEnd' then
      if not ev.dead then                                  -- pushed back: a later copy of this event lands it
        local fin = ev.t - ((SPELLS[ev.key].projectile and TRAVEL > EPS) and TRAVEL or 0)   -- when the cast finished (a projectile flies on)
        if not land(ev.key, eurekaAt(ev.key, fin), ev.castMult, ev.target) and ev.tl and TL then TL.turn = true end
      end
    elseif ty == 'chanTick' then
      chanTick(ev)
    elseif ty == 'petAct' then
      if P and ev.gen == P.gen then petAct() end
    elseif ty == 'petLand' then
      if P and ev.gen == P.gen then petSpellHit(P.c.spell) end
    elseif ty == 'petSwing' then
      if P and ev.gen == P.gen then petSwing() end
    elseif ty == 'dotTickX' then
      local dx = xdots[ev.ti][ev.key]
      if dx and dx.inst == ev.inst then
        periodicTickX(ev.ti, ev.key, dx.snap, ev.i)
        if ev.i == dx.ticks - 1 then xdots[ev.ti][ev.key] = nil end
      end
    elseif ty == 'heal' then
      gainHealth(HEAL.amt, 'healed')
    elseif ty == 'mana' then
      local before = S.mana
      S.mana = min(stats.maxMana, S.mana + ev.amount); res.manaFromBuffs = (res.manaFromBuffs or 0) + (S.mana - before)
    elseif ty == 'summonEnd' then
      finishSummon(ev.to)
    elseif ty == 'sacTick' then
      if stats.sacrificeActive then
        if build.sacrifice == 'voidwalker' then
          local vb = S.mana
          S.mana = min(stats.maxMana, S.mana + stats.maxMana * SAC.voidwalker.manaPct / 100); res.manaFromSac = res.manaFromSac + (S.mana - vb)
        elseif build.sacrifice == 'felhunter' then gainHealth(stats.maxHealth * SAC.felhunter.healthPct / 100, 'sac') end
      end
    elseif ty == 'dmgTaken' then
      takeHit()
      push({ t = S.t + HIT, o = 1, type = 'dmgTaken' })
    elseif ty == 'chanEnd' then
      local ch = S.channel
      if ch and ch.inst == ev.inst and not (ch.finish > S.t + EPS) then
        S.channel = nil
      end
    end
    if tick then
      evCount = evCount + 1
      if evCount >= 100 then evCount = 0; tick() end
    end
  end

  local petDmg = 0
  for k, r in pairs(bySpell) do if sub(k, 1, 4) == 'pet:' then petDmg = petDmg + r.dmg end end
  res.petDmg = petDmg
  res.dps = res.total / dur
  res.duration = dur
  res.exTime = dur * executePct / 100; res.preTime = dur - res.exTime; res.preDmg = res.total - res.exDmg
  res.endMana = S.mana
  resHealth.finish = S.health
  return res
end

-- Seed and length of fight i (0-based) of a run. Fight length varies per fight (uniform +-durationVarPct).
function WL.fightParams(cfg, i)
  local fseed = (cfg.fight.seed * 7919 + i) % TWO32
  local vp = cfg.fight.durationVarPct or 0
  return fseed, cfg.fight.duration * (1 + vp / 100 * (2 * makeRng(xorSeed(fseed, 0x5bd1e995))() - 1))
end

local ROW_FIELDS = { 'casts', 'landed', 'misses', 'crits', 'hits', 'ticks', 'tickCrits', 'dmg', 'castTime', 'glances', 'threat' }
local HP_FIELDS = { 'tap', 'self', 'healed', 'leech', 'sac', 'blocked' }

-- Monte-Carlo wrapper: averages `iterations` fights. opt.onFight(i, n) is called after each fight (progress).
-- Addon only (not in the sim's engine): opt.stop(i, dps of fight i) -> true ends the run after fight i ("exact
-- enough"); every average is then over the fights played. Without opt.stop the run is exactly the sim's.
function WL.simulate(build, raceKey, cfg, opt)
  opt = opt or {}
  local n = opt.iterations or cfg.fight.iterations
  local stats = WL.computeStats(build, raceKey, cfg)
  local tbl = WL.buildSpellTable(build, stats, cfg)
  local dpsList, agg, rowOrder = {}, {}, {}
  local lifeTaps, movingTaps, minMana, clipped, durSum = 0, 0, huge, 0, 0
  local tapPct, petOomFights, petOomSec, idleSec, spiRegen, sacMana, oom = 0, 0, 0, 0, 0, 0, 0
  local tpsSum, hp = 0, { min = huge, tap = 0, self = 0, healed = 0, leech = 0, sac = 0, blocked = 0 }
  local exDmg, exTime, preDmg, preTime = 0, 0, 0, 0
  local onFight, stop, planned = opt.onFight, opt.stop, n
  for i = 0, planned - 1 do
    local fseed, fdur = WL.fightParams(cfg, i)
    local r = WL.simulateOnce(build, raceKey, cfg, { stats = stats, table = tbl, seed = fseed, duration = fdur })
    dpsList[i + 1] = r.dps; durSum = durSum + r.duration; lifeTaps = lifeTaps + r.lifeTaps; movingTaps = movingTaps + (r.movingTaps or 0)
    clipped = clipped + r.clipped; minMana = min(minMana, r.minMana); oom = oom + r.oom
    tapPct = tapPct + 100 * (r.tapTime or 0) / r.duration; idleSec = idleSec + r.idle; spiRegen = spiRegen + (r.manaFromSpirit or 0); sacMana = sacMana + (r.manaFromSac or 0)
    tpsSum = tpsSum + r.threat / r.duration; hp.min = min(hp.min, r.health.min)
    for j = 1, #HP_FIELDS do local k = HP_FIELDS[j]; hp[k] = hp[k] + r.health[k] end
    exDmg = exDmg + r.exDmg; exTime = exTime + r.exTime; preDmg = preDmg + r.preDmg; preTime = preTime + r.preTime
    if r.petOomTime > 1e-9 then petOomFights = petOomFights + 1; petOomSec = petOomSec + r.petOomTime end
    for k, b in pairs(r.bySpell) do
      local a = agg[k]
      if not a then
        a = { casts = 0, landed = 0, misses = 0, crits = 0, hits = 0, ticks = 0, tickCrits = 0, dmg = 0, castTime = 0, glances = 0, threat = 0 }
        agg[k] = a; rowOrder[#rowOrder + 1] = k
      end
      for j = 1, #ROW_FIELDS do local f = ROW_FIELDS[j]; a[f] = a[f] + (b[f] or 0) end
    end
    if onFight then onFight(i + 1, planned) end
    if stop and i + 1 < planned and stop(i + 1, r.dps) then n = i + 1; break end
  end
  for _, a in pairs(agg) do for j = 1, #ROW_FIELDS do local f = ROW_FIELDS[j]; a[f] = a[f] / n end end
  for j = 1, #HP_FIELDS do local k = HP_FIELDS[j]; hp[k] = hp[k] / n end
  local sum = 0
  for i = 1, n do sum = sum + dpsList[i] end
  local mean = sum / n
  local sorted = {}
  for i = 1, n do sorted[i] = dpsList[i] end
  table.sort(sorted)
  local median = n % 2 == 1 and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2
  local sq = 0
  for i = 1, n do sq = sq + (dpsList[i] - mean) * (dpsList[i] - mean) end
  local sd = math.sqrt(sq / max(1, n - 1))
  return {
    tps = tpsSum / n,
    health = { max = stats.maxHealth, min = hp.min, tapAvg = hp.tap, selfAvg = hp.self, healedAvg = hp.healed, leechAvg = hp.leech, sacAvg = hp.sac, blockedSecAvg = hp.blocked },
    mana = { max = stats.maxMana, sacAvg = sacMana / n, spiritRegenAvg = spiRegen / n, tapTimePct = tapPct / n, petOomFightsPct = 100 * petOomFights / n,
             petOomSecAvg = petOomFights > 0 and petOomSec / petOomFights or 0, idleSecAvg = idleSec / n, oomAvg = oom / n },
    build = build, race = raceKey, stats = stats, table = tbl, iterations = n,
    dps = mean, dpsMedian = median, dpsSd = sd, dpsMin = sorted[1], dpsMax = sorted[n],
    dpsList = dpsList,                                  -- every fight's DPS in order (item comparisons pair them up)
    dpsErr = 1.96 * sd / math.sqrt(n),
    dpsPre = preTime ~= 0 and preDmg / preTime or nil, dpsExec = exTime ~= 0 and exDmg / exTime or nil,
    execPct = cfg.fight.executePct,
    bySpell = agg, avgDuration = durSum / n, lifeTaps = lifeTaps / n, movingTaps = movingTaps / n, minMana = minMana, clipped = clipped / n,
  }
end

-- Stat weights: DPS gained per 1 SP, per 1% hit, per 1% crit, per 1% haste, per 1 Int, per 1 Spell Pierce.
-- Common random numbers: the baseline and every +stat run use the same seeds, so most of the noise cancels.
function WL.statWeightRun(build, raceKey, cfg, n, k, onFight)
  local c = cfg
  if k then
    c = copy(cfg); c.extra = c.extra or {}
    c.extra[k] = (c.extra[k] or 0) + cfg.weightDeltas[k]
  end
  return WL.simulate(build, raceKey, c, { iterations = n, onFight = onFight }).dps
end
-- Pet melee hit: 8/17 of your spell hit above the base, from the hit stat itself (not capped). Her spells keep your hit.
function WL.petMeleeHit(stats, cb)
  local t = cb.petMelee
  return max(0, stats.hitPctUncapped - cb.baseHitPct) * (t.hitFromSpell ~= nil and t.hitFromSpell or 1)
end
function WL.combineWeights(cfg, base, dpsByKey)
  local out = { base = base }
  for i = 1, #WL.STAT_WEIGHT_KEYS do
    local k = WL.STAT_WEIGHT_KEYS[i]
    out[k] = (dpsByKey[k] - base) / cfg.weightDeltas[k]
  end
  return out
end
