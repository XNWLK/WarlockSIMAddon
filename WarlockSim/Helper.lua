-- The helper (off by default; Character tab "Helper", /wsim helper): on a raid boss, a small bar shows the spell the
-- sim would cast next with your character, the two after it, and how many seconds the boss has left to live.
--
-- It plays the sim's own priority list (the build of your character: WL.characterBuildNow) on a copy of the fight as
-- it happens:
--   - your casts: the game reports your own spells, so DoT timers, cooldowns, Life Taps, Curse of the Elements,
--     Decimation and Demonic Brand are followed from them, with the sim's durations;
--   - your mana, your buffs, the boss's debuffs and its health: read from the game while it shows them. In combat the
--     game hides many numbers from addons ("secret values"); then the copy works them out itself (mana from costs and
--     regeneration, debuffs from your casts) and the time to kill falls back to the fight length of the Fight tab.
-- The time to kill comes from how fast the boss's health went down in the last 20 seconds. The priority list uses it
-- as the time left in the fight (DoTs that would not pay off, Death Coil at the end, Life Tap by need) and the boss's
-- health for the execute phase.
-- Only raid bosses: a boss encounter in a raid, or a target the game calls a boss (world bosses). Not in 5-player
-- dungeons.
local ADDON, WL = ...

local H = { view = { keys = {}, extras = {} } }
WL.helper = H
local floor, max, min, huge = math.floor, math.max, math.min, math.huge
local sub = string.sub
local EPS = 1e-6
local WINDOW = 20                  -- seconds of boss health the time to kill is worked out from
local MATCH = 0.8                  -- share of a ready build's talent points your talents must have
local SHADOW_TRANCE = 17941        -- the buff Nightfall gives
local SOUL_SHARD = 6265
local DECIMATION_S, ISB_S, SNF_S = 10, 12, 20   -- the sim's durations (Sim.lua, land)
-- Actions that are never "the filler instead" (Sim.lua NOT_ALT)
local NOT_ALT = { bane = 1, baneOfAgony = 1, corruption = 1, siphonLife = 1, immolate = 1, multiDot = 1, curseOfElements = 1, lifeTapPet = 1, lifeTapBelow = 1, lifeTapNeed = 1,
                  swapToImp = 1, swapToSuccubus = 1, shadowBoltSpread = 1, isbUpkeep = 1, deathCoilFinisher = 1 }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
-- A number from the game, or nil when the call fails or the game hides it.
local function num(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or v == nil or isSecret(v) or type(v) ~= 'number' then return nil end
  return v
end
-- All results of a call, or nothing when it fails or any result is hidden.
local function checked(ok, ...)
  if not ok then return nil end
  for i = 1, select('#', ...) do if isSecret((select(i, ...))) then return nil end end
  return ...
end
local function call(fn, ...)
  if type(fn) ~= 'function' then return nil end
  return checked(pcall(fn, ...))
end
local function copyT(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end
local function indexOf(t, v) for i = 1, #t do if t[i] == v then return i end end; return nil end
local function spellName(id) local n = call(C_Spell and C_Spell.GetSpellName, id); return type(n) == 'string' and n or nil end
local function up(P, n, t) local e = P.buffs[n]; return e ~= nil and e > (t or P.t) + EPS end

function H.enabled() return WL.db ~= nil and WL.db.options.helper == true end

-- ---------------------------------------------------------------------------------------------------------------------
-- your character as the sim plays it
-- ---------------------------------------------------------------------------------------------------------------------
-- Do your talents fit the build the priority list comes from? (at least 80% of its points)
function H.match(talents, tpl)
  local total, share = 0, 0
  for k, pts in pairs(tpl and tpl.talents or {}) do total = total + pts; share = share + min(pts, (talents or {})[k] or 0) end
  return total > 0 and share >= MATCH * total - EPS, share, total
end

function H.context()
  if not WL.db or not WL.char then return nil, 'Read your character first (type /wsim).' end
  local build, _, tpl = WL.characterBuildNow()
  if not build or not tpl then return nil, 'Read your character first (type /wsim).' end
  if not H.match(WL.char.talents, tpl) then return nil, 'Your talents fit none of the sim\'s builds.' end
  local cfg = WL.characterConfig()
  cfg.fight.targets = 1; cfg.fight.multiDot = false            -- one boss
  local race = WL.raceKey()
  local stats = WL.computeStats(build, race, cfg)
  local tbl = WL.buildSpellTable(build, stats, cfg)
  local C = { build = build, tpl = tpl, cfg = cfg, race = race, stats = stats, tbl = tbl, SPELLS = WL.spellsFor(cfg),
              title = tpl.short or tpl.key, haste = 1 + stats.hastePct / 100, byId = {}, byName = {}, items = {} }
  C.rot = WL.effectiveRotation(build, cfg)
  C.acts = {}
  for i = 1, #C.rot do C.acts[i] = WL.actionOf(C.rot[i], build) end
  C.tapGain = (C.SPELLS.lifeTap.manaBase + stats.spi) * (1 + WL.talentValue(build, 'improvedLifeTap', 'manaPct') / 100)
  C.lat = max(0, (cfg.fight.latencyMs or 0) / 1000)
  local rc = WL.RACES[race] and WL.RACES[race].racials or {}
  for i = 1, #rc do if rc[i].effect == 'cooldown' then C.racial = rc[i] end end
  -- the game's spell ids (and names, for other ranks) -> the sim's spell keys
  for _, list in ipairs({ WL.SPELLS, C.SPELLS }) do
    for k, s in pairs(list) do
      if s.id then C.byId[s.id] = k; local n = spellName(s.id) or s.name; if n then C.byName[n] = k end end
    end
  end
  if C.racial then C.byId[C.racial.id] = 'racial' end
  -- items the sim uses in the fight: mana potion / rune, Spellblasting potion, trinkets with a use effect
  local con = WL.activeConsumables(cfg)
  for i = 1, #con do
    local c = con[i]
    if c.manaRestore or c.spPotion then
      local it = { key = c.key, id = c.id, cdGroup = c.cdGroup, cd = c.cd, mana = c.manaRestore and (c.manaRestore.amount or stats.maxMana * c.manaRestore.pct / 100), sp = c.spPotion ~= nil, name = c.name }
      C.items[#C.items + 1] = it
      local _, sid = call(C_Item and C_Item.GetItemSpell, c.id)
      if type(sid) == 'number' then C.byId[sid] = 'item:' .. #C.items end
    end
  end
  C.trinkets = WL.equippedTrinkets(cfg)
  C.precast = WL.precastOf(build, cfg, tbl)
  C.castsDoom = indexOf(C.rot, 'bane') ~= nil
  return C
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the copy of the fight
-- ---------------------------------------------------------------------------------------------------------------------
-- F (the fight as it happens) and P (a look ahead) share these fields: t (fight seconds), mana, tapMana, manaStart,
-- dots[key] / cds[key] / buffs[name] = fight second it ends, brandCharges, shards, lastSpend, actOpen, doomSeen.
function H.haste(C, P)
  local r = C.racial
  if r and r.hastePct and up(P, 'berserking') then return C.haste * (1 + r.hastePct / 100) end
  return C.haste
end
function H.castTime(C, P, k)
  local e = C.tbl[k]
  if not e then return 0 end
  local c = e.cast
  if k == 'soulFire' and up(P, 'decimation') then c = c * (1 - WL.talentValue(C.build, 'decimation', 'sfCastRedPct') / 100)
  elseif k == 'shadowBolt' and up(P, 'shadowTrance') then c = 0 end
  return c / H.haste(C, P)
end
function H.gcd(C, P) local cb = C.cfg.combat; return max(cb.minGcd, cb.gcd / H.haste(C, P)) end
function H.occupies(C, P, k)
  if k == 'lifeTap' then return H.gcd(C, P) end
  local s = C.SPELLS[k]
  if s and s.kind == 'channel' then return s.duration end
  return max(H.castTime(C, P, k), H.gcd(C, P))
end
-- Seconds the boss has left at fight second t, and its health in percent then.
function H.remaining(P, t) return max(0, P.rNow - (t - P.now)) end
function H.hpAt(P, t) return max(0, min(100, P.hpNow + P.slope * (t - P.now))) end

-- What a cast of `k` that completes at fight second t changes (the same rules as the sim's fight; a cast is assumed
-- to land: the game does not tell an addon about misses).
function H.effects(C, P, k, t)
  if k == 'racial' then
    local r = C.racial
    P.cds.racial = t + r.cd
    if r.spPct then P.buffs.bloodFury = t + r.duration end
    if r.hastePct then P.buffs.berserking = t + r.duration end
    if r.dmgPct then P.buffs.eureka = t + r.duration end
    return
  end
  if sub(k, 1, 5) == 'item:' then
    local it = C.items[tonumber(sub(k, 6))]
    if it then
      P.cds['cd:' .. it.cdGroup] = t + it.cd
      if it.mana then P.mana = min(C.stats.maxMana, P.mana + it.mana) end
    end
    return
  end
  local s, e = C.SPELLS[k], C.tbl[k]
  if not s or not e then return end
  if k == 'lifeTap' then
    local before = P.mana
    P.mana = min(C.stats.maxMana, P.mana + C.tapGain); P.tapMana = P.tapMana + (P.mana - before)
    return
  end
  if e.cost > 0 then P.mana = P.mana - e.cost; P.lastSpend = t end
  if e.cd ~= 0 then P.cds[k] = t + e.cd end
  local tv = function(key, f) return WL.talentValue(C.build, key, f) end
  if s.shards and P.shards and not (k == 'soulFire' and up(P, 'decimation', t)) then P.shards = P.shards - s.shards end
  if k == 'soulFire' and up(P, 'decimation', t) then P.buffs.decimation = nil end
  if k == 'shadowBolt' and up(P, 'shadowTrance', t) then P.buffs.shadowTrance = nil end
  if s.kind == 'dot' or s.kind == 'hybrid' then
    if s.bane then P.dots.baneOfAgony = nil; P.dots.baneOfDoom = nil end
    P.dots[k] = t + s.duration
    if k == 'baneOfDoom' then P.doomSeen = true end
  end
  if k == 'curseOfElements' then P.buffs.coe = t + s.duration end
  local exec = H.hpAt(P, t) < C.cfg.fight.executePct
  if (k == 'shadowBolt' or k == 'searingPain') and exec and tv('decimation') ~= 0 then P.buffs.decimation = t + DECIMATION_S end
  -- Improved Shadow Bolt comes from a Shadow Bolt crit; the game does not say which bolt crit, so every bolt counts.
  if k == 'shadowBolt' and tv('improvedShadowBolt') ~= 0 and not P.isbSeen then P.buffs.isb = t + ISB_S end
  if k == 'searingPain' and tv('demonicBrand') ~= 0 and C.build.pet then
    P.buffs.brand = t + C.cfg.demonicBrand.duration; P.brandCharges = tv('demonicBrand', 'charges')
  end
  if k == 'conflagrate' then
    if tv('shadowAndFlame') ~= 0 then P.buffs.snfShadow = t + SNF_S end
    P.dots.immolate = nil
  end
  if k == 'shadowburn' and tv('shadowAndFlame') ~= 0 then P.buffs.snfFire = t + SNF_S end
end

-- Mana that comes by itself once it is missing (a mana potion or rune, a mana trinket), as the sim's "Life Tap by need"
-- counts it. Innervate and Mana Tide from other players cannot be seen and are left out.
function H.freeMana(C, P)
  local lv, mx = 0, C.stats.maxMana
  for i = 1, #C.items do
    local it = C.items[i]
    if it.mana and it.have ~= false and not ((P.cds['cd:' .. it.cdGroup] or 0) > P.t + EPS) then lv = max(lv, mx - it.mana) end
  end
  for i = 1, #C.trinkets do
    local x = C.trinkets[i]
    local u = x.fx.use
    local pol = ((C.cfg.options.trinketUse or {})[x.slot]) or 'cds'
    if u and u.kind == 'mana' and pol ~= 'never' and not ((P.cds['tr:' .. x.slot] or 0) > P.t + EPS) then lv = max(lv, mx - u.amount) end
  end
  return lv
end

-- Near the end of the fight: is a DoT still worth its cast? A short form of the sim's check: the ticks that come before
-- the boss dies against the filler's damage in the same time.
function H.dotWorth(C, P, S, key)
  local s, e = C.SPELLS[key], C.tbl[key]
  if not s or not e or not e.tickDmg then return nil end
  local castT, rem = H.castTime(C, P, key), S.remaining
  local ticks = 0
  for i = 1, e.ticks do
    if castT + i * s.tickEvery > rem + EPS then break end
    ticks = ticks + (s.ramp and s.ramp[i] or 1)
  end
  local value = ticks * e.tickDmg + (s.kind == 'hybrid' and (e.directDmg or 0) or 0)
  local f = nil                                                 -- the filler: the first action below that casts a direct spell or channel
  for i = (S.actionIndex or 0) + 1, #C.rot do
    local a = C.acts[i]
    if a and not NOT_ALT[C.rot[i]] then
      local ok, k = pcall(a.pick, S)
      local fs = ok and k and C.SPELLS[k]
      if fs and C.tbl[k] and (fs.kind == 'direct' or fs.kind == 'channel') then f = k; break end
    end
  end
  f = f or (C.tbl.shadowBolt and 'shadowBolt')
  local fe = f and C.tbl[f]
  if not fe then return true end
  local fDmg = fe.directDmg or ((fe.tickDmg or 0) * (fe.ticks or 0))
  local rate = fDmg * (1 + (fe.critPct or 0) / 100 * ((fe.critMult or 1) - 1)) / (H.occupies(C, P, f) + C.lat)
  return value >= (H.occupies(C, P, key) + C.lat) * rate
end

-- The fight state as the sim's priority actions read it (the same names as in Sim.lua), over P.
function H.newS(C, P)
  local S = { cfg = C.cfg, build = C.build, maxMana = C.stats.maxMana, multiTargets = 1, nextTarget = 0, havocTarget = 0, swapped = false }
  S.has = function(k) return C.tbl[k] ~= nil end
  S.ready = function(k) local c = P.cds[k]; return not c or c <= P.t + EPS end
  S.buff = function(n) return up(P, n) end
  S.dotLeft = function(k) local d = P.dots[k]; return (d and d > P.t + EPS) and d - P.t or 0 end
  S.hasteFactor = function() return H.haste(C, P) end
  S.castTime = function(k) return H.castTime(C, P, k) end
  S.gcd = function() return H.gcd(C, P) end
  S.freeManaLevel = function() return H.freeMana(C, P) end
  S.manaNeedLeft = function() if P.t < 6 then return huge end; return max(0, (P.manaStart - P.mana + P.tapMana) / P.t) * S.remaining end
  S.tapGain = function() return C.tapGain end
  S.petMana = function() return P.petMana or huge end
  S.petSpellCost = function() return P.petCost or huge end
  S.petManaPct = function() return P.petManaPct or 100 end
  S.xDotLeft = function() return 0 end
  S.xDebLeft = function() return 0 end
  S.isMoving = function() return false end
  S.dotWorth = function(k) if C.cfg.options.dotEndCheck == false then return nil end; return H.dotWorth(C, P, S, k) end
  return S
end
function H.sync(S, P)
  S.t, S.remaining, S.targetHpPct, S.mana, S.shards, S.brandCharges = P.t, H.remaining(P, P.t), H.hpAt(P, P.t), P.mana, P.shards, P.brandCharges
  S.buffs, S.cds, S.dots = P.buffs, P.cds, P.dots
end

-- The spell the priority list casts at P.t (as the sim's pickAction and decide): its key and its place in the list.
-- excludeFrom: only actions above that place (a channel is cut for those).
function H.decide(C, P, S, excludeFrom)
  H.sync(S, P)
  local key, idx
  for i = 1, #C.rot do
    if excludeFrom and i >= excludeFrom then return nil end
    local a = C.acts[i]
    if a then
      S.nextTarget = 0; S.actionIndex = i
      local ok, k = pcall(a.pick, S)
      if ok and k and sub(k, 1, 5) ~= 'swap:' and C.tbl[k] then key, idx = k, i; break end
    end
  end
  if not key then return nil end
  if key ~= 'lifeTap' and P.mana < C.tbl[key].cost then
    if C.stats.maxMana < C.tbl[key].cost then return nil end
    key = 'lifeTap'                                             -- out of mana for it: Life Tap first, as the sim does
  end
  return key, idx
end

-- When the racial, the Spellblasting potion and "with cooldowns" trinkets may be used ("Pop cooldowns", Fight tab).
function H.activesOpen(C, P, S, key)
  if P.actOpen then return true end
  local pol = C.cfg.options.activesPolicy or 'pull'
  local open
  if pol == 'execute' then open = S.targetHpPct < C.cfg.fight.executePct
  elseif pol == 'doom' then
    local d = P.dots.baneOfDoom
    if not d or d <= P.t + EPS then open = P.doomSeen or not C.castsDoom or P.dots.baneOfAgony ~= nil
    else
      local toBoom = d - P.t
      open = toBoom > S.remaining or toBoom <= H.occupies(C, P, key) + EPS
    end
  else open = true end
  P.actOpen = open
  return open
end
-- What to use together with the next spell: cooldowns before a damaging cast, mana items once their mana is missing.
function H.extras(C, P, S, key)
  local out = {}
  local miss = C.stats.maxMana - P.mana
  for i = 1, #C.items do
    local it = C.items[i]
    if it.mana and it.have ~= false and miss >= it.mana and not ((P.cds['cd:' .. it.cdGroup] or 0) > P.t + EPS) then
      out[#out + 1] = { item = it.id, label = it.name }
    end
  end
  for i = 1, #C.trinkets do
    local x = C.trinkets[i]
    local u = x.fx.use
    if u and u.kind == 'mana' and ((C.cfg.options.trinketUse or {})[x.slot] or 'cds') ~= 'never' and miss >= u.amount and not ((P.cds['tr:' .. x.slot] or 0) > P.t + EPS) then
      out[#out + 1] = { item = x.id, label = x.fx.name }
    end
  end
  local s = C.SPELLS[key]
  if not s or s.kind == 'utility' or key == 'lifeTap' or P.mana < C.tbl[key].cost then return out end
  local open = H.activesOpen(C, P, S, key)
  local r = C.racial
  if r and open and S.ready('racial') then
    local ok = true
    if r.dmgPct then local len = s.kind == 'channel' and s.duration or H.castTime(C, P, key); ok = (s.kind == 'direct' or s.kind == 'channel') and len >= 1.4 end
    if ok then out[#out + 1] = { spell = r.id, label = r.name } end
  end
  for i = 1, #C.items do
    local it = C.items[i]
    if it.sp and open and it.have ~= false and not ((P.cds['cd:' .. it.cdGroup] or 0) > P.t + EPS) then out[#out + 1] = { item = it.id, label = it.name } end
  end
  for i = 1, #C.trinkets do
    local x = C.trinkets[i]
    local u = x.fx.use
    local pol = ((C.cfg.options.trinketUse or {})[x.slot]) or 'cds'
    if u and u.kind ~= 'mana' and pol ~= 'never' and not ((P.cds['tr:' .. x.slot] or 0) > P.t + EPS) then
      local ok = pol == 'ready' or (pol == 'cds' and open) or (pol == 'execute' and S.targetHpPct < C.cfg.fight.executePct)
      if ok then out[#out + 1] = { item = x.id, label = x.fx.name } end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- what the game tells
-- ---------------------------------------------------------------------------------------------------------------------
local function inRaid()
  local inInst, kind = call(IsInInstance)
  return inInst == true and kind == 'raid', kind
end
function H.isBoss(u)
  local e = call(UnitExists, u)
  if not e then return false end
  local dead = call(UnitIsDead, u)
  if dead then return false end
  local c = call(UnitClassification, u)
  if c == 'worldboss' then return true end
  return call(UnitIsBossMob, u) == true
end
-- The raid boss to follow: the target if it is one, else the first boss frame unit. nil when there is none (or in a
-- 5-player dungeon).
function H.bossUnit()
  local raid, kind = inRaid()
  if kind == 'party' then return nil end
  if H.isBoss('target') then return 'target' end
  for i = 1, 5 do local u = 'boss' .. i; if (H.encounter or raid) and call(UnitExists, u) then return u end end
  return nil
end

function H.keyOf(spellID)
  local C = H.ctx
  if not C or type(spellID) ~= 'number' or isSecret(spellID) then return nil end
  local k = C.byId[spellID]
  if k then return k end
  local n = spellName(spellID)
  return n and C.byName[n] or nil
end

-- Boss health, kept as samples over the last 20 seconds.
function H.sample(F, now)
  local u = H.bossUnit()
  F.unit = u
  local hp, mx = u and num(UnitHealth, u), u and num(UnitHealthMax, u)
  if not (hp and mx and mx > 0) then F.hpKnown = false; return end
  F.hpKnown = true; F.hpPct = 100 * hp / mx
  local s = F.samples
  local last = s[#s]
  if not last or now - last.t >= 0.2 then s[#s + 1] = { t = now, p = F.hpPct } end
  while #s > 2 and now - s[1].t > WINDOW do table.remove(s, 1) end
end
-- Health lost per second (least squares over the samples): the slope in percent per second (negative), and the span.
function H.slope(s)
  local n = #s
  if n < 3 then return nil, 0 end
  local mt, mp = 0, 0
  for i = 1, n do mt = mt + s[i].t; mp = mp + s[i].p end
  mt, mp = mt / n, mp / n
  local a, b = 0, 0
  for i = 1, n do local dt = s[i].t - mt; a = a + dt * (s[i].p - mp); b = b + dt * dt end
  if b <= EPS then return nil, 0 end
  return a / b, s[n].t - s[1].t
end
-- Seconds the boss has left, the health now, the slope, and whether it comes from the boss's health (else: the fight
-- length of the Fight tab, as the sim plays it).
function H.timeToKill(C, F, now)
  local dur = C.cfg.fight.duration
  local t = now - F.t0
  local fall = max(0, dur - t)
  if F.hpKnown then
    local sl, span = H.slope(F.samples)
    if sl and sl < -1e-4 and span >= 2 then
      local ttk = min(3600, F.hpPct / -sl)
      local w = min(1, span / 6)                                -- the first seconds lean on the fight length
      return w * ttk + (1 - w) * fall, F.hpPct, sl, true
    end
    return fall, F.hpPct, -F.hpPct / max(1, fall), true
  end
  return fall, 100 * (1 - min(t, dur) / dur), -100 / dur, false
end

-- Buffs and debuffs read from the game when it shows them (out of combat, or for auras it never hides).
function H.readAuras(C, F, now)
  local t0 = F.t0
  local function auraHidden(id)
    local s = call(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret, id)
    if s ~= nil then return s end
    return call(C_Secrets and C_Secrets.ShouldAurasBeSecret) ~= false
  end
  -- Shadow Trance: the buff, or the Shadow Bolt's cast time (0 while it is up)
  if C.tbl.shadowBolt and WL.talentValue(C.build, 'nightfall') ~= 0 then
    if not auraHidden(SHADOW_TRANCE) then
      local a = call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, SHADOW_TRANCE)
      if type(a) == 'table' and type(a.expirationTime) == 'number' and not isSecret(a.expirationTime) then
        F.buffs.shadowTrance = (a.expirationTime > 0 and a.expirationTime or now + 10) - t0
      else F.buffs.shadowTrance = nil end
    else
      local info = call(C_Spell and C_Spell.GetSpellInfo, C.SPELLS.shadowBolt.id)
      local ct = type(info) == 'table' and info.castTime
      if type(ct) == 'number' and not isSecret(ct) then
        if ct == 0 then F.buffs.shadowTrance = F.buffs.shadowTrance or (now - t0 + 10) else F.buffs.shadowTrance = nil end
      end
    end
  end
  -- the boss's debuffs: your DoTs, Improved Shadow Bolt, Curse of the Elements
  if not F.unit or call(C_Secrets and C_Secrets.ShouldAurasBeSecret) ~= false then F.auraSeen = false; return end
  local found, any = {}, false
  for i = 1, 40 do
    local a = call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex, F.unit, i, 'HARMFUL')
    if type(a) ~= 'table' then break end
    any = true
    local name, exp = a.name, a.expirationTime
    if not isSecret(name) and not isSecret(exp) and type(exp) == 'number' then
      local k = C.byName[name]
      local mine = a.sourceUnit == 'player' or a.isFromPlayerOrPlayerPet
      if k and (mine or k == 'curseOfElements') then found[k] = exp - t0 end
      if name == spellName(17800) then found.isb = exp - t0 end
    end
  end
  F.auraSeen = true
  for k, s in pairs(C.SPELLS) do
    if (s.kind == 'dot' or s.kind == 'hybrid') and C.tbl[k] then F.dots[k] = found[k] end
  end
  if found.curseOfElements then F.buffs.coe = found.curseOfElements elseif not (C.cfg.debuffs.coeOther and C.cfg.debuffs.coeOther.on) then F.buffs.coe = nil end
  if WL.talentValue(C.build, 'improvedShadowBolt') ~= 0 then F.isbSeen = true; F.buffs.isb = found.isb end
end

function H.readGame(C, F, now)
  local t = now - F.t0
  local mana = num(UnitPower, 'player', 0)
  if mana then F.mana = mana; F.manaReal = true
  else                                                          -- hidden: regeneration as in the sim (mp5 always, Spirit outside the 5-second rule)
    F.manaReal = false
    local dt = max(0, now - (F.lastRead or now))
    local cb, st = C.cfg.combat, C.stats
    local reg = (st.mp5 or 0) / 5
    if (cb.fsrSeconds or 0) > 0 and t > F.lastSpend + cb.fsrSeconds then reg = reg + (cb.spiritRegenBase + cb.spiritRegenPerSpi * st.spi) / 2 end
    F.mana = min(st.maxMana, F.mana + reg * dt)
  end
  F.lastRead = now
  local pm, pmx = num(UnitPower, 'pet', 0), num(UnitPowerMax, 'pet', 0)
  F.petMana, F.petManaPct = pm, (pm and pmx and pmx > 0) and 100 * pm / pmx or nil
  F.shards = num(C_Item and C_Item.GetItemCount, SOUL_SHARD) or huge
  for i = 1, #C.items do
    local it = C.items[i]
    local n = num(C_Item and C_Item.GetItemCount, it.id)
    if n ~= nil then it.have = n > 0 end
    local st, d = call(C_Container and C_Container.GetItemCooldown, it.id)
    if type(st) == 'number' and type(d) == 'number' then F.cds['cd:' .. it.cdGroup] = (st > 0 and d > 1.5) and st + d - F.t0 or nil end
  end
  for i = 1, #C.trinkets do
    local x = C.trinkets[i]
    local inv = x.slot == 'trinket1' and 13 or 14
    local st, d = call(GetInventoryItemCooldown, 'player', inv)
    if type(st) == 'number' and type(d) == 'number' then F.cds['tr:' .. x.slot] = (st > 0 and d > 1.5) and st + d - F.t0 or nil end
  end
  H.readAuras(C, F, now)
  H.sample(F, now)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the fight: start, your casts, the plan
-- ---------------------------------------------------------------------------------------------------------------------
function H.startFight(now, t0)
  local C, err = H.context()
  H.ctx, H.err = C, err
  local dur = C and C.cfg.fight.duration or 180
  local F = { t0 = t0 or now, dots = {}, cds = {}, buffs = {}, samples = {}, tapMana = 0, lastSpend = -huge, gcdUntil = 0, brandCharges = 0, shards = huge,
              t = 0, now = 0, rNow = dur, hpNow = 100, slope = -100 / dur }
  F.t = now - F.t0
  F.mana = (C and num(UnitPower, 'player', 0)) or (C and C.stats.maxMana) or 0
  F.manaStart = C and C.stats.maxMana or 0
  if C and C.cfg.debuffs.coeOther and C.cfg.debuffs.coeOther.on then F.buffs.coe = huge end
  F.unit = H.bossUnit()
  H.F = F
  H.casts = {}
  return F
end
function H.endFight() H.F = nil end

function H.onCast(event, unit, castGUID, spellID)
  if unit ~= 'player' then return end
  local now = GetTime()
  -- The opener comes before the game says you are in combat: a spell of yours that lands on a raid boss starts the fight.
  if not H.F and event == 'UNIT_SPELLCAST_SUCCEEDED' and H.enabled() and H.ctx and H.keyOf(spellID) and H.bossUnit() then H.startFight(now) end
  local F, C = H.F, H.ctx
  if not F or not C then return end
  F.t = now - F.t0
  local k = H.keyOf(spellID)
  if event == 'UNIT_SPELLCAST_START' then
    if not k then return end
    local _, _, _, _, endMs = call(UnitCastingInfo, 'player')
    F.cast = { key = k, guid = castGUID, finish = type(endMs) == 'number' and endMs / 1000 or now + H.castTime(C, F, k) }
    F.gcdUntil = now + H.gcd(C, F)
  elseif event == 'UNIT_SPELLCAST_CHANNEL_START' then
    if not k then return end
    local _, _, _, _, endMs = call(UnitChannelInfo, 'player')
    local s = C.SPELLS[k]
    F.channel = { key = k, finish = type(endMs) == 'number' and endMs / 1000 or now + (s and s.duration or 0), idx = indexOf(C.rot, k) or (#C.rot + 1) }
  elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
    F.channel = nil
  elseif event == 'UNIT_SPELLCAST_STOP' or event == 'UNIT_SPELLCAST_FAILED' or event == 'UNIT_SPELLCAST_INTERRUPTED' then
    if F.cast and (castGUID == nil or F.cast.guid == nil or F.cast.guid == castGUID) then F.cast = nil end
  elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then
    if not k then return end
    local wasCast = F.cast ~= nil and F.cast.key == k
    if wasCast then F.cast = nil
    elseif C.SPELLS[k] then F.gcdUntil = now + H.gcd(C, F) end    -- an instant (or a channel) starts the GCD now
    H.effects(C, F, k, now - F.t0)
    H.casts[#H.casts + 1] = { t = now - F.t0, key = k }
  end
end

-- The plan at `now`: the next spell, the two after it, what to use with it, and the time to kill.
function H.plan(now)
  local C, F = H.ctx, H.F
  local v = { keys = {}, extras = {}, title = C.title }
  local tNow = now - F.t0
  H.readGame(C, F, now)
  local rNow, hpNow, slope, known = H.timeToKill(C, F, now)
  v.ttk, v.ttkKnown, v.hp = rNow, known, hpNow
  F.t, F.now, F.rNow, F.hpNow, F.slope = tNow, tNow, rNow, hpNow, slope
  local P = { t = tNow, now = tNow, rNow = rNow, hpNow = hpNow, slope = slope, mana = F.mana, tapMana = F.tapMana, manaStart = F.manaStart,
              dots = copyT(F.dots), cds = copyT(F.cds), buffs = copyT(F.buffs), brandCharges = F.brandCharges, shards = F.shards,
              lastSpend = F.lastSpend, actOpen = F.actOpen, doomSeen = F.doomSeen, isbSeen = F.isbSeen, petMana = F.petMana, petManaPct = F.petManaPct }
  local S = H.newS(C, P)
  local free = max(tNow, F.gcdUntil - F.t0)
  if F.cast and F.cast.finish > now then                        -- the spell you are casting: counted as done when it ends
    local fin = F.cast.finish - F.t0
    P.t = fin; H.effects(C, P, F.cast.key, fin)
    free = max(free, fin)
  end
  if F.channel and F.channel.finish > now then                  -- a channel is cut when something above it is ready
    P.t = free
    local k = H.decide(C, P, S, F.channel.idx)
    if k then v.clip = true else free = max(free, F.channel.finish - F.t0) end
  end
  P.t = free
  v.wait = max(0, free - tNow)
  for n = 1, 3 do
    local k = H.decide(C, P, S)
    if not k then break end
    v.keys[n] = k
    if n == 1 then v.extras = H.extras(C, P, S, k); F.actOpen = P.actOpen or F.actOpen end
    local s = C.SPELLS[k]
    local done = (k == 'lifeTap' or (s and s.kind == 'channel')) and P.t or P.t + H.castTime(C, P, k)
    local nextT = P.t + H.occupies(C, P, k) + C.lat
    H.effects(C, P, k, done)
    P.t = nextT
    if H.remaining(P, P.t) <= 0 then break end
  end
  return v
end

-- Before the pull: the precast spell (Fight tab), else the first spell of the fight.
function H.prePull(now)
  local C = H.ctx
  local v = { keys = {}, extras = {}, title = C.title, pre = true, ttk = C.cfg.fight.duration, ttkKnown = false, hp = 100 }
  if C.precast then v.keys[1] = C.precast; return v end
  local F = { t0 = now, dots = {}, cds = {}, buffs = {}, samples = {}, tapMana = 0, lastSpend = -huge, gcdUntil = 0, brandCharges = 0, shards = huge,
              mana = num(UnitPower, 'player', 0) or C.stats.maxMana, manaStart = C.stats.maxMana }
  if C.cfg.debuffs.coeOther and C.cfg.debuffs.coeOther.on then F.buffs.coe = huge end
  local P = { t = 0, now = 0, rNow = C.cfg.fight.duration, hpNow = 100, slope = -100 / C.cfg.fight.duration, mana = F.mana, tapMana = 0, manaStart = F.manaStart,
              dots = F.dots, cds = F.cds, buffs = F.buffs, brandCharges = 0, shards = huge, lastSpend = -huge }
  local k = H.decide(C, P, H.newS(C, P))
  v.keys[1] = k
  return v
end

-- ---------------------------------------------------------------------------------------------------------------------
-- watching: fights start and end, every tenth of a second a new plan
-- ---------------------------------------------------------------------------------------------------------------------
local function inCombat()
  local a = call(InCombatLockdown)
  if a then return true end
  return call(UnitAffectingCombat, 'player') == true
end

-- One look at the game: called ten times a second while the helper is on.
function H.tick(now)
  if not H.enabled() then H.F = nil; H.view = { keys = {}, extras = {} }; return H.view end
  local fighting = inCombat()
  local boss = H.encounter ~= nil or H.bossUnit() ~= nil
  if H.F and not fighting and not H.encounter then H.endFight() end
  if not H.F and fighting and boss then H.startFight(now, H.encounter and H.encounter.start or nil) end
  local v
  if H.F then
    if H.ctx then v = H.plan(now) else v = { keys = {}, extras = {}, msg = H.err } end
    v.active = true
  elseif boss and not fighting then
    if not H.ctx or not H.preAt or now - H.preAt > 2 then H.ctx, H.err = H.context(); H.preAt = now end
    v = H.ctx and H.prePull(now) or { keys = {}, extras = {}, msg = H.err }
    v.active = true
  else
    v = { keys = {}, extras = {} }
  end
  H.view = v
  return v
end

-- ---------------------------------------------------------------------------------------------------------------------
-- key bindings: which key casts a spell (from your action bars), read out of combat
-- ---------------------------------------------------------------------------------------------------------------------
local BARS = { { 1, 'ACTIONBUTTON' }, { 61, 'MULTIACTIONBAR1BUTTON' }, { 49, 'MULTIACTIONBAR2BUTTON' }, { 25, 'MULTIACTIONBAR3BUTTON' },
               { 37, 'MULTIACTIONBAR4BUTTON' }, { 145, 'MULTIACTIONBAR5BUTTON' }, { 157, 'MULTIACTIONBAR6BUTTON' }, { 169, 'MULTIACTIONBAR7BUTTON' } }
local function shortKey(k)
  return (k:gsub('SHIFT%-', 'S'):gsub('CTRL%-', 'C'):gsub('ALT%-', 'A'):gsub('NUMPAD', 'N'):gsub('BUTTON', 'M'):gsub('MOUSEWHEELUP', 'WU'):gsub('MOUSEWHEELDOWN', 'WD'))
end
function H.readBindings()
  local map = {}
  if type(GetActionInfo) ~= 'function' or type(GetBindingKey) ~= 'function' then H.keys = map; return end
  for b = 1, #BARS do
    for i = 1, 12 do
      local slot = BARS[b][1] + i - 1
      local kind, id = call(GetActionInfo, slot)
      local name
      if kind == 'spell' then name = spellName(id)
      elseif kind == 'macro' and type(GetMacroSpell) == 'function' then local sid = call(GetMacroSpell, id); name = sid and spellName(sid)
      elseif kind == 'item' then name = 'item:' .. tostring(id) end
      local key = name and call(GetBindingKey, BARS[b][2] .. i)
      if name and type(key) == 'string' and not map[name] then map[name] = shortKey(key) end
    end
  end
  H.keys = map
end
function H.keyText(e)
  local map = H.keys or {}
  if e.item then return map['item:' .. tostring(e.item)] or '' end
  local id = e.spell
  local n = id and spellName(id)
  return (n and map[n]) or ''
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the bar
-- ---------------------------------------------------------------------------------------------------------------------
local BAR
local function icon(e)
  if e.item then return call(C_Item and C_Item.GetItemIconByID, e.item) end
  return call(C_Spell and C_Spell.GetSpellTexture, e.spell)
end
local function entryOf(C, k)
  local s = C and C.SPELLS[k]
  return { spell = s and s.id, label = s and s.name or k }
end
local function makeIcon(parent, size)
  local f = CreateFrame('Frame', nil, parent)
  f:SetSize(size, size)
  f.tex = f:CreateTexture(nil, 'ARTWORK'); f.tex:SetAllPoints(f); f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.key = f:CreateFontString(nil, 'OVERLAY', size > 32 and 'NumberFontNormal' or 'NumberFontNormalSmall')
  f.key:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -1, -2); f.key:SetText('')
  return f
end
local function setIcon(f, e)
  if not e then f:Hide(); return end
  f.tex:SetTexture(icon(e) or 134400)
  f.key:SetText(H.keyText(e))
  f:Show()
end

function H.createBar()
  if BAR then return BAR end
  local f = CreateFrame('Frame', 'WarlockSimHelperBar', UIParent)
  f:SetSize(236, 70)
  f:SetFrameStrata('MEDIUM')
  local pos = WL.db and WL.db.options.helperPos
  if type(pos) == 'table' and type(pos[1]) == 'string' then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
  else f:SetPoint('CENTER', UIParent, 'CENTER', 0, -180) end
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', function(self) if H.unlocked then self:StartMoving() end end)
  f:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    if WL.db and type(p) == 'string' then WL.db.options.helperPos = { p, floor((x or 0) + 0.5), floor((y or 0) + 0.5) } end
  end)
  f:EnableMouse(false)
  f.bg = f:CreateTexture(nil, 'BACKGROUND'); f.bg:SetAllPoints(f); f.bg:SetColorTexture(0.05, 0.03, 0.08, 0.72)
  f.edge = f:CreateTexture(nil, 'BORDER'); f.edge:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0); f.edge:SetPoint('TOPRIGHT', f, 'TOPRIGHT', 0, 0); f.edge:SetHeight(2)
  f.edge:SetColorTexture(0.58, 0.51, 0.79, 0.9)
  f.main = makeIcon(f, 46); f.main:SetPoint('TOPLEFT', f, 'TOPLEFT', 6, -8)
  f.next1 = makeIcon(f, 28); f.next1:SetPoint('TOPLEFT', f, 'TOPLEFT', 58, -8)
  f.next2 = makeIcon(f, 28); f.next2:SetPoint('TOPLEFT', f, 'TOPLEFT', 90, -8)
  f.next1:SetAlpha(0.8); f.next2:SetAlpha(0.6)
  f.extra1 = makeIcon(f, 22); f.extra1:SetPoint('TOPLEFT', f, 'TOPLEFT', 126, -8)
  f.extra2 = makeIcon(f, 22); f.extra2:SetPoint('TOPLEFT', f, 'TOPLEFT', 150, -8)
  f.name = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  f.name:SetPoint('TOPLEFT', f, 'TOPLEFT', 58, -40); f.name:SetWidth(120); f.name:SetJustifyH('LEFT'); f.name:SetText('')
  f.ttk = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
  f.ttk:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -8, -8); f.ttk:SetJustifyH('RIGHT'); f.ttk:SetText('')
  f.ttkLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
  f.ttkLabel:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -8, -30); f.ttkLabel:SetJustifyH('RIGHT'); f.ttkLabel:SetText('')
  f.build = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
  f.build:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 6, 4); f.build:SetWidth(224); f.build:SetJustifyH('LEFT'); f.build:SetText('')
  f:Hide()
  BAR = f
  return f
end

function H.render(v)
  local f = H.createBar()
  if H.unlocked then
    f:EnableMouse(true)
    f.main:Hide(); f.next1:Hide(); f.next2:Hide(); f.extra1:Hide(); f.extra2:Hide()
    f.name:SetText('Drag me. /wsim helper move locks it.'); f.ttk:SetText('84 s'); f.ttkLabel:SetText('to kill'); f.build:SetText('Helper')
    f:Show(); return
  end
  f:EnableMouse(false)
  if not v.active then f:Hide(); return end
  local C = H.ctx
  if v.msg or not C then
    f.main:Hide(); f.next1:Hide(); f.next2:Hide(); f.extra1:Hide(); f.extra2:Hide()
    f.name:SetText(v.msg or ''); f.ttk:SetText(''); f.ttkLabel:SetText(''); f.build:SetText('Helper')
    f:Show(); return
  end
  setIcon(f.main, v.keys[1] and entryOf(C, v.keys[1]))
  f.main:SetAlpha(((v.wait or 0) > 0.2 and not v.clip) and 0.55 or 1)   -- dim while your cast or channel still runs
  setIcon(f.next1, v.keys[2] and entryOf(C, v.keys[2]))
  setIcon(f.next2, v.keys[3] and entryOf(C, v.keys[3]))
  setIcon(f.extra1, v.extras[1]); setIcon(f.extra2, v.extras[2])
  local first = v.keys[1] and entryOf(C, v.keys[1])
  local label = first and first.label or ''
  if v.pre then label = (C.precast and 'Precast: ' or 'Open with ') .. label
  elseif v.clip then label = 'Stop the channel: ' .. label end
  if #v.extras > 0 then label = label .. ' + ' .. v.extras[1].label end
  f.name:SetText(label)
  if v.pre then f.ttk:SetText(''); f.ttkLabel:SetText('ready')
  else
    f.ttk:SetText(string.format('%d s', floor((v.ttk or 0) + 0.5)))
    f.ttkLabel:SetText(v.ttkKnown and string.format('to kill (%d%%)', floor((v.hp or 0) + 0.5)) or 'to kill (fight length)')
    if f.ttk.SetTextColor then if v.ttkKnown then f.ttk:SetTextColor(1, 0.82, 0) else f.ttk:SetTextColor(0.6, 0.6, 0.6) end end
  end
  f.build:SetText(C.title)
  f:Show()
end

-- ---------------------------------------------------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------------------------------------------------
local CAST_EVENTS = { 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_FAILED', 'UNIT_SPELLCAST_INTERRUPTED', 'UNIT_SPELLCAST_SUCCEEDED',
                      'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP' }
local OTHER_EVENTS = { 'ENCOUNTER_START', 'ENCOUNTER_END', 'PLAYER_REGEN_ENABLED', 'ACTIONBAR_SLOT_CHANGED', 'UPDATE_BINDINGS', 'PLAYER_ENTERING_WORLD' }
local watcher = CreateFrame('Frame')
local registered, since, bindingsDirty = false, 0, true
watcher:SetScript('OnEvent', function(_, event, a, b, c, d)
  if sub(event, 1, 15) == 'UNIT_SPELLCAST_' then H.onCast(event, a, b, c); return end
  if event == 'ENCOUNTER_START' then
    if inRaid() then H.encounter = { id = a, name = b, start = GetTime() } end
  elseif event == 'ENCOUNTER_END' then
    H.encounter = nil; H.endFight()
  elseif event == 'PLAYER_REGEN_ENABLED' then
    if not H.encounter then H.endFight() end
    if bindingsDirty then H.readBindings(); bindingsDirty = false end
  else
    bindingsDirty = true
    if not inCombat() then H.readBindings(); bindingsDirty = false end
  end
end)
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.1 then return end
  since = 0
  local ok, v = pcall(H.tick, GetTime())
  if not ok then H.view = { keys = {}, extras = {}, active = false }; H.lastError = v end
  if BAR or (ok and v and v.active) or H.unlocked then H.render(ok and v or H.view) end
end)
-- The events are only listened to while the helper is on.
function H.update()
  local on = H.enabled()
  if on and not registered then
    for i = 1, #CAST_EVENTS do
      if watcher.RegisterUnitEvent then watcher:RegisterUnitEvent(CAST_EVENTS[i], 'player') else watcher:RegisterEvent(CAST_EVENTS[i]) end
    end
    for i = 1, #OTHER_EVENTS do watcher:RegisterEvent(OTHER_EVENTS[i]) end
    registered = true
    if not inCombat() then H.readBindings(); bindingsDirty = false end
  elseif not on and registered then
    if watcher.UnregisterAllEvents then watcher:UnregisterAllEvents() end
    registered = false
    H.F, H.encounter = nil, nil
  end
  if on then watcher:Show() else
    watcher:Hide(); H.unlocked = false
    if BAR then BAR:Hide() end
  end
end
function H.toggle(v)
  if v == nil then v = not H.enabled() end
  WL.db.options.helper = v and true or false
  H.update()
  return WL.db.options.helper
end
function H.toggleMove()
  if not H.enabled() then H.toggle(true) end
  H.unlocked = not H.unlocked
  H.render(H.view)
  return H.unlocked
end
watcher:Hide()
WL.loginHooks[#WL.loginHooks + 1] = H.update
