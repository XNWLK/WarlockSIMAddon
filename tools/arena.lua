-- A practice boss for the helper bar (tools/arena-server.js): a stand-in game world around the addon's real code.
-- Loaded after tools/wow-mock.lua and before the addon. It plays the game's part only: the boss loses health to the
-- raid and to your spells, your casts take their time and cost mana, DoTs tick, Nightfall can give Shadow Trance, and
-- the game's events reach the addon as they would in the game. The numbers of your spells come from the addon itself
-- (the same character the helper reads), with a hit and a crit roll per spell.
ARENA = { now = 1000, SECRET = setmetatable({}, { __tostring = function() return '(hidden)' end }), log = {}, seq = 0 }
local A = ARENA
local floor, max, min = math.floor, math.max, math.min
A.set = { raidDps = 3500, length = 150, hideHealth = false, hideAuras = true, hideMana = false, auto = false }
A.RACES = { human = { 'Human', 'Human' }, gnome = { 'Gnome', 'Gnome' }, orc = { 'Orc', 'Orc' }, undead = { 'Undead', 'Scourge' }, troll = { 'Troll', 'Troll' } }
A.race = 'orc'
A.PET_NPC = { imp = '416', succubus = '1863', felhunter = '417', voidwalker = '1860' }
A.SAC_AURA = { imp = { 18789, 'Burning Wish' }, voidwalker = { 18790, 'Fel Stamina' }, succubus = { 18791, 'Touch of Shadow' }, felhunter = { 18792, 'Fel Energy' } }
local PRESSABLE = { 'shadowBolt', 'searingPain', 'incinerate', 'immolate', 'corruption', 'baneOfAgony', 'baneOfDoom', 'siphonLife', 'curseOfElements',
                    'conflagrate', 'shadowburn', 'soulFire', 'wrack', 'deathCoil', 'lifeTap' }
local KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'Q', 'E', 'R', 'F', 'T', 'G' }

local function say(msg) A.log[#A.log + 1] = string.format('%5.1f  %s', A.t0 and (A.now - A.t0) or 0, msg); while #A.log > 60 do table.remove(A.log, 1) end end
local function fire(...) MOCK.fire(...) end
local function isBoss(u) return u == 'target' or u == 'boss1' end
local function hidden(flag) return (A.combat and A.set[flag]) and true or false end
local function tv(k, f) return WLX.talentValue(A.C.build, k, f) end

-- ---------------------------------------------------------------------------------------------------------------------
-- the game's functions, as the world is right now
-- ---------------------------------------------------------------------------------------------------------------------
function GetTime() return A.now end
function issecretvalue(v) return v == A.SECRET end
function InCombatLockdown() return A.combat == true end
function UnitAffectingCombat(u) return u == 'player' and A.combat == true end
function IsInInstance() return true, 'raid' end
function UnitRace() local r = A.RACES[A.race]; return r[1], r[2] end
local mockExists = UnitExists
function UnitExists(u)
  if u == 'target' then return A.boss ~= nil and A.boss.hp > 0 end
  if u == 'boss1' then return A.combat == true and A.boss.hp > 0 end
  return mockExists(u)
end
function UnitClassification(u) return isBoss(u) and 'worldboss' or 'normal' end
function UnitIsBossMob(u) return isBoss(u) end
function UnitIsDead(u) return isBoss(u) and A.boss ~= nil and A.boss.hp <= 0 end
function UnitHealth(u)
  if isBoss(u) then if hidden('hideHealth') then return A.SECRET end; return floor(A.boss.hp) end
  return 5000
end
local mockHealthMax = UnitHealthMax
function UnitHealthMax(u)
  if isBoss(u) then if hidden('hideHealth') then return A.SECRET end; return A.boss.max end
  return mockHealthMax(u)
end
function UnitPower(u)
  if u == 'player' and A.p then if hidden('hideMana') then return A.SECRET end; return floor(A.p.mana) end
  return A.SECRET                                              -- the demon's mana: not part of this world
end
local mockPowerMax = UnitPowerMax
function UnitPowerMax(u) if u == 'player' then return (A.p and A.p.maxMana) or mockPowerMax(u) end; return A.SECRET end
C_Secrets = { ShouldAurasBeSecret = function() return hidden('hideAuras') end, ShouldSpellAuraBeSecret = function() return hidden('hideAuras') end }

local byId
local function keyOfId(id)
  if not byId then
    byId = {}
    for k, s in pairs(WLX.SPELLS) do byId[s.id] = k end
  end
  return byId[id]
end
local function racial() local rc = WLX.RACES[A.race].racials; for i = 1, #rc do if rc[i].effect == 'cooldown' then return rc[i] end end end
local mockSpellName = C_Spell.GetSpellName
C_Spell.GetSpellName = function(id)
  local k = keyOfId(id)
  if k then return WLX.SPELLS[k].name end
  local r = racial()
  if r and r.id == id then return r.name end
  if id == 17941 then return 'Shadow Trance' end
  if id == 17800 then return 'Shadow Vulnerability' end
  return mockSpellName(id)
end
C_Spell.GetSpellTexture = function(id) return 'spell:' .. tostring(id) end
C_Spell.GetSpellInfo = function(id)
  local k = keyOfId(id)
  if not k then return nil end
  return { name = WLX.SPELLS[k].name, spellID = id, castTime = hidden('hideAuras') and A.SECRET or floor(A.castTime(k) * 1000 + 0.5) }
end
C_Item.GetItemIconByID = function(id) return 'item:' .. tostring(id) end
C_Item.GetItemCount = function(id) if id == 6265 then return 12 end; return 0 end
C_Item.GetItemSpell = function() return nil end
C_Container.GetItemCooldown = function() return 0, 0, 1 end
function GetInventoryItemCooldown() return 0, 0, 1 end
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
  if hidden('hideAuras') or not A.p then return nil end
  if id == 17941 and (A.p.buffs.shadowTrance or 0) > A.now then return { name = 'Shadow Trance', spellId = 17941, expirationTime = A.p.buffs.shadowTrance } end
  return nil
end
local mockAuraByIndex = C_UnitAuras.GetAuraDataByIndex
C_UnitAuras.GetAuraDataByIndex = function(u, i, filter)
  if isBoss(u) then
    if hidden('hideAuras') or not A.boss then return nil end
    local list = A.debuffList()
    local d = list[i]
    if not d then return nil end
    return { name = d.name, spellId = d.id, expirationTime = d.expires, sourceUnit = 'player', isFromPlayerOrPlayerPet = true }
  end
  return mockAuraByIndex(u, i, filter)
end
function UnitCastingInfo(u)
  local c = u == 'player' and A.p and A.p.cast
  if not c then return nil end
  local s = WLX.SPELLS[c.key]
  return s.name, s.name, 'spell:' .. s.id, floor(c.start * 1000), floor(c.finish * 1000), false, c.guid, false, s.id
end
function UnitChannelInfo(u)
  local c = u == 'player' and A.p and A.p.channel
  if not c then return nil end
  local s = WLX.SPELLS[c.key]
  return s.name, s.name, 'spell:' .. s.id, floor(c.start * 1000), floor(c.finish * 1000), false, false, s.id
end
-- the action bar: the spells you can press, keys 1 to 0, Q, E, R, F, T, G
function GetActionInfo(slot) local e = A.bar and A.bar[slot]; if e then return 'spell', e.id end; return nil end
function GetBindingKey(cmd) local i = tonumber(cmd:match('^ACTIONBUTTON(%d+)$') or ''); return i and A.bar and A.bar[i] and KEYS[i] or nil end

-- ---------------------------------------------------------------------------------------------------------------------
-- the world
-- ---------------------------------------------------------------------------------------------------------------------
function A.debuffList()
  local out = {}
  for k, d in pairs(A.boss.debuffs) do if d.expires > A.now then out[#out + 1] = { key = k, name = d.name, id = d.id, expires = d.expires } end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
function A.haste()
  local h = 1 + A.C.stats.hastePct / 100
  local r = racial()
  if r and r.hastePct and (A.p.buffs.berserking or 0) > A.now then h = h * (1 + r.hastePct / 100) end
  return h
end
function A.castTime(k)
  local e = A.C.tbl[k]
  if not e then return 0 end
  local c = e.cast
  if k == 'shadowBolt' and (A.p.buffs.shadowTrance or 0) > A.now then c = 0 end
  if k == 'soulFire' and (A.p.buffs.decimation or 0) > A.now then c = c * (1 - tv('decimation', 'sfCastRedPct') / 100) end
  return c / A.haste()
end
function A.gcd() local cb = A.C.cfg.combat; return max(cb.minGcd, cb.gcd / A.haste()) end

-- After the addon loaded and the character was read: the boss, you, your action bar.
function A.setup()
  A.C = assert(WLX.helper.context())
  local st = A.C.stats
  A.p = { mana = st.maxMana, maxMana = st.maxMana, buffs = {}, cds = {}, gcdEnd = 0, dmg = 0, lastSpend = -1e9, casts = {}, agree = 0, presses = 0 }
  A.boss = { name = 'Practice Boss', debuffs = {} }
  A.resetBoss()
  A.bar = {}
  for _, k in ipairs(PRESSABLE) do
    local e, s = A.C.tbl[k], WLX.SPELLS[k]
    local useful = k == 'lifeTap' or k == 'deathCoil' or k == 'curseOfElements'
    for i = 1, #A.C.rot do
      local r = A.C.rot[i]
      if r:find(k, 1, true) or (r == 'bane' and (k == 'baneOfAgony' or k == 'baneOfDoom')) then useful = true end
    end
    if k == 'shadowBolt' then useful = true end
    if e and useful and (not s.talent or tv(s.talent) ~= 0) then A.bar[#A.bar + 1] = { key = k, id = s.id, name = s.name } end
  end
  local r = racial()
  if r then A.bar[#A.bar + 1] = { key = 'racial', id = r.id, name = r.name } end
  fire('ACTIONBAR_SLOT_CHANGED', 0)
  A.combat, A.t0, A.result = false, nil, nil
  say('Ready: ' .. A.C.title .. '. Target the boss is done for you; press Pull or any spell.')
end
function A.resetBoss()
  local total = A.set.raidDps + 650                             -- the raid plus roughly you
  A.boss.max = floor(total * A.set.length)
  A.boss.hp = A.boss.max
  A.boss.debuffs = {}
end

function A.pull()
  if A.combat or A.boss.hp <= 0 then return end
  A.combat, A.t0 = true, A.now
  A.ttkLog, A.raidLeft = {}, 0
  say('Pull! ' .. A.boss.name .. ' has ' .. A.boss.max .. ' health.')
  fire('PLAYER_REGEN_DISABLED')
  fire('ENCOUNTER_START', 9999, A.boss.name, 9, 40)
end
local function finish()
  A.combat = false
  local len = A.now - A.t0
  A.result = { length = len, dps = A.p.dmg / max(1, len), presses = A.p.presses, agree = A.p.agree, casts = A.p.casts }
  -- how close the helper's time to kill was: at each second after the first 10, what it said against the real end
  local n, err = 0, 0
  for _, e in ipairs(A.ttkLog or {}) do if e.t >= 10 then n = n + 1; err = err + math.abs(e.t + e.ttk - len) end end
  A.result.ttkError = n > 0 and err / n or nil
  say(string.format('The boss is dead after %.1f s. Your DPS: %.0f.', len, A.result.dps))
  fire('ENCOUNTER_END', 9999, A.boss.name, 9, 40, 1)
  fire('PLAYER_REGEN_ENABLED')
end

local function hitRoll() return math.random() * 100 < min(99, A.C.stats.hitPct) end
local function deal(amt, what)
  A.boss.hp = max(0, A.boss.hp - amt)
  A.p.dmg = A.p.dmg + amt
end
local NIGHTFALL = { corruption = true, drainSoul = true, drainLife = true, wrack = true }
local function nightfall(k)
  if NIGHTFALL[k] and tv('nightfall') ~= 0 and A.C.tbl.shadowBolt and math.random() * 100 < tv('nightfall', 'procPct') then
    A.p.buffs.shadowTrance = A.now + 10
    say('Shadow Trance! (Nightfall)')
  end
end
-- A cast is done: the game says so, then the spell does what it does.
function A.complete(k, guid)
  local s, e = WLX.SPELLS[k], A.C.tbl[k]
  fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, s.id)
  if k == 'lifeTap' then
    local gain = A.C.tapGain
    A.p.mana = min(A.p.maxMana, A.p.mana + gain)
    return
  end
  if s.kind ~= 'channel' then A.p.mana = A.p.mana - e.cost end
  if e.cost > 0 then A.p.lastSpend = A.now end
  if e.cd ~= 0 then A.p.cds[k] = A.now + e.cd end
  if k == 'shadowBolt' and (A.p.buffs.shadowTrance or 0) > A.now and A.p.instantTrance then A.p.buffs.shadowTrance = nil end
  if k == 'soulFire' then A.p.buffs.decimation = nil end
  if not hitRoll() then say(s.name .. ' missed.'); return end
  if s.kind == 'utility' then
    if k == 'curseOfElements' then A.boss.debuffs.coe = { name = s.name, id = s.id, expires = A.now + s.duration } end
    return
  end
  if s.kind == 'dot' or s.kind == 'hybrid' then
    if s.bane then A.boss.debuffs.baneOfAgony = nil; A.boss.debuffs.baneOfDoom = nil end
    A.boss.debuffs[k] = { name = s.name, id = s.id, expires = A.now + s.duration, nextTick = A.now + s.tickEvery, i = 0, ticks = e.ticks, key = k }
  end
  if e.directDmg then
    local amt = e.directDmg
    if k == 'incinerate' and A.boss.debuffs.immolate and A.boss.debuffs.immolate.expires > A.now then amt = amt * (1 + s.immolateBonusPct / 100) end
    local crit = math.random() * 100 < e.critPct
    if crit then amt = amt * e.critMult end
    deal(amt)
    if k == 'shadowBolt' and crit and tv('improvedShadowBolt') ~= 0 then A.boss.debuffs.isb = { name = 'Shadow Vulnerability', id = 17800, expires = A.now + 12 } end
    if (k == 'shadowBolt' or k == 'searingPain') and tv('decimation') ~= 0 and 100 * A.boss.hp / A.boss.max < A.C.cfg.fight.executePct then A.p.buffs.decimation = A.now + 10 end
    if k == 'conflagrate' and not (tv('shadowAndFlame') ~= 0 and math.random() * 100 < tv('shadowAndFlame', 'procPct')) then A.boss.debuffs.immolate = nil end   -- Shadow and Flame may keep it
  end
end
function A.stopChannel()
  local c = A.p.channel
  if not c then return end
  A.p.channel = nil
  fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', c.guid, WLX.SPELLS[c.key].id)
end

-- You press a key. Returns a reason when the game would not cast it.
function A.press(k)
  if not A.boss or A.boss.hp <= 0 then return 'The boss is dead.' end
  local v = WLX.helper.view
  local said = v and v.keys and v.keys[1]
  if k == 'racial' then
    local r = racial()
    if not r then return 'No racial cooldown.' end
    if (A.p.cds.racial or 0) > A.now then return r.name .. ' is not ready.' end
    if not A.combat then A.pull() end
    A.p.cds.racial = A.now + r.cd
    if r.hastePct then A.p.buffs.berserking = A.now + r.duration end
    A.seq = A.seq + 1
    fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-' .. A.seq, r.id)
    say(r.name .. '.')
    return nil
  end
  local s, e = WLX.SPELLS[k], A.C.tbl[k]
  if not s or not e then return 'Not a spell of yours.' end
  if A.p.cast then return 'You are still casting.' end
  if A.now < A.p.gcdEnd - 1e-6 then return 'Global cooldown.' end
  if (A.p.cds[k] or 0) > A.now + 1e-6 then return s.name .. ' is not ready.' end
  if k ~= 'lifeTap' and A.p.mana < e.cost then return 'Not enough mana.' end
  if not A.combat then A.pull() end
  if A.p.channel then A.stopChannel() end
  A.p.presses = A.p.presses + 1
  if said == k then A.p.agree = A.p.agree + 1 end
  A.p.casts[k] = (A.p.casts[k] or 0) + 1
  A.seq = A.seq + 1
  local guid = 'Cast-' .. A.seq
  local ct = k == 'lifeTap' and 0 or A.castTime(k)
  A.p.gcdEnd = A.now + A.gcd()
  A.p.instantTrance = k == 'shadowBolt' and ct == 0
  say(s.name .. (said and said ~= k and ('   (the helper said ' .. (WLX.SPELLS[said] and WLX.SPELLS[said].name or said) .. ')') or ''))
  if s.kind == 'channel' then
    A.p.mana = A.p.mana - e.cost; A.p.lastSpend = A.now
    A.p.channel = { key = k, guid = guid, start = A.now, finish = A.now + s.duration, nextTick = A.now + s.tickEvery }
    fire('UNIT_SPELLCAST_CHANNEL_START', 'player', guid, s.id)
    A.complete(k, guid)
  elseif ct > 0 then
    A.p.cast = { key = k, guid = guid, start = A.now, finish = A.now + ct }
    fire('UNIT_SPELLCAST_START', 'player', guid, s.id)
  else
    A.complete(k, guid)
  end
  return nil
end

-- The world moves on by h seconds.
local function advance(h)
  A.now = A.now + h
  if not A.combat then return end
  local p, b = A.p, A.boss
  -- the raid (its damage wobbles a little from second to second)
  A.wobble = A.wobble or 1
  if math.random() < h then A.wobble = 0.8 + math.random() * 0.4 end
  b.hp = max(0, b.hp - A.set.raidDps * A.wobble * h)
  -- your cast and channel
  if p.cast and p.cast.finish <= A.now + 1e-9 then local c = p.cast; p.cast = nil; A.complete(c.key, c.guid) end
  local c = p.channel
  if c then
    local s, e = WLX.SPELLS[c.key], A.C.tbl[c.key]
    while c.nextTick <= A.now + 1e-9 and c.nextTick <= c.finish + 1e-9 do
      if e.tickDmg then deal(e.tickDmg) end
      nightfall(c.key)
      c.nextTick = c.nextTick + s.tickEvery
    end
    if A.now >= c.finish - 1e-9 then A.stopChannel() end
  end
  -- DoT ticks
  for k, d in pairs(b.debuffs) do
    if d.ticks then
      local s = WLX.SPELLS[k]
      while d.i < d.ticks and d.nextTick <= A.now + 1e-9 do
        d.i = d.i + 1
        deal(A.C.tbl[k].tickDmg * (s.ramp and s.ramp[d.i] or 1))
        nightfall(k)
        d.nextTick = d.nextTick + s.tickEvery
      end
    end
    if d.expires <= A.now then b.debuffs[k] = nil end
  end
  -- mana: mp5, and Spirit once 5 seconds have passed since you last spent mana
  local cb, st = A.C.cfg.combat, A.C.stats
  local reg = (st.mp5 or 0) / 5
  if A.now > p.lastSpend + (cb.fsrSeconds or 5) then reg = reg + (cb.spiritRegenBase + cb.spiritRegenPerSpi * st.spi) / 2 end
  p.mana = min(p.maxMana, p.mana + reg * h)
  if b.hp <= 0 then
    if p.cast then p.cast = nil end
    A.stopChannel()
    finish()
  end
end

-- The page's clock: dt seconds of the world, the addon's frames ten times a second, auto-play.
function A.step(dt)
  local n = max(1, math.ceil(dt / 0.05))
  local h = dt / n
  for _ = 1, n do
    advance(h)
    A.since = (A.since or 0) + h
    if A.since >= 0.1 - 1e-9 then
      A.since = 0
      for _, f in ipairs(MOCK.frames) do if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end
      local v = WLX.helper.view
      if A.combat and v and v.active and not v.pre and v.ttk then
        local t = A.now - A.t0
        local last = A.ttkLog[#A.ttkLog]
        if not last or t - last.t >= 1 then A.ttkLog[#A.ttkLog + 1] = { t = t, ttk = v.ttk, known = v.ttkKnown } end
      end
      if A.set.auto and v and v.active and v.keys[1] and A.boss.hp > 0 then
        for i = 1, #(v.extras or {}) do if v.extras[i].spell and racial() and v.extras[i].spell == racial().id then A.press('racial') end end
        if not A.p.cast and A.now >= A.p.gcdEnd - 1e-6 and ((v.wait or 0) <= 0.05 or v.clip) then A.press(v.keys[1]) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- what the page shows
-- ---------------------------------------------------------------------------------------------------------------------
local function trueTtk()
  if not A.combat then return nil end
  local rate = A.set.raidDps + A.p.dmg / max(1, A.now - A.t0)
  return A.boss.hp / max(1, rate)
end
function A.frameTree()
  local root = _G.WarlockSimHelperBar
  if not root then return WLX.jsonArray({}) end
  local id = {}
  for i, f in ipairs(MOCK.frames) do id[f] = i end
  local function under(f) local q = f.parent; while q do if q == root then return true end; q = q.parent end; return false end
  local out = {}
  for i, f in ipairs(MOCK.frames) do
    if f == root or under(f) then
      local pts = {}
      for j, q in ipairs(f.points or {}) do pts[j] = WLX.jsonArray({ q[1], q[2] and id[q[2]] or 0, q[3], q[4], q[5] }) end
      out[#out + 1] = { id = i, kind = f.__kind, parent = f.parent and id[f.parent] or 0, shown = f.shown, w = f.width, h = f.height, wSet = f.wSet or false, hSet = f.hSet or false,
        points = WLX.jsonArray(pts), text = f.text ~= '' and f.text or nil, font = f.font, tex = f.tex and tostring(f.tex) or nil, color = f.color and WLX.jsonArray(f.color) or nil,
        alpha = f.alpha, tcolor = f.tcolor and WLX.jsonArray(f.tcolor) or nil, justify = f.justifyH, layer = f.layer }
    end
  end
  return WLX.jsonArray(out)
end
function A.state()
  local p, b, v = A.p, A.boss, WLX.helper.view or {}
  local spells = {}
  for i, e in ipairs(A.bar) do
    local k = e.key
    local cd = k == 'racial' and (p.cds.racial or 0) or (p.cds[k] or 0)
    local cost = k ~= 'racial' and A.C.tbl[k] and A.C.tbl[k].cost or 0
    spells[i] = { key = k, name = e.name, id = e.id, hotkey = KEYS[i], cd = max(0, cd - A.now), cost = cost, school = WLX.SPELLS[k] and WLX.SPELLS[k].school or 'shadow',
                  cast = k ~= 'racial' and A.castTime(k) or 0 }
  end
  local debuffs = {}
  for i, d in ipairs(A.debuffList()) do debuffs[i] = { key = d.key, name = d.name, left = d.expires - A.now } end
  local buffs = {}
  for k, t in pairs(p.buffs) do if t > A.now then buffs[#buffs + 1] = { key = k, left = t - A.now } end end
  local cast = p.cast and { name = WLX.SPELLS[p.cast.key].name, left = p.cast.finish - A.now, full = p.cast.finish - p.cast.start }
            or p.channel and { name = WLX.SPELLS[p.channel.key].name, left = p.channel.finish - A.now, full = p.channel.finish - p.channel.start, channel = true } or nil
  local keys = {}
  for i, k in ipairs(v.keys or {}) do keys[i] = { key = k, name = WLX.SPELLS[k] and WLX.SPELLS[k].name or k } end
  local extras = {}
  for i, x in ipairs(v.extras or {}) do extras[i] = x.label end
  return {
    t = A.combat and (A.now - A.t0) or 0, combat = A.combat, title = A.C.title, race = A.race,
    boss = { name = b.name, hp = b.hp, max = b.max, pct = 100 * b.hp / b.max, debuffs = WLX.jsonArray(debuffs), trueTtk = trueTtk() },
    player = { mana = p.mana, maxMana = p.maxMana, gcd = max(0, p.gcdEnd - A.now), gcdFull = A.gcd(), cast = cast, buffs = WLX.jsonArray(buffs), dps = A.combat and p.dmg / max(1, A.now - A.t0) or 0 },
    spells = WLX.jsonArray(spells),
    helper = { active = v.active or false, wait = v.wait or 0, keys = WLX.jsonArray(keys), extras = WLX.jsonArray(extras), ttk = v.ttk, ttkKnown = v.ttkKnown or false, msg = v.msg, clip = v.clip or false,
               pre = v.pre or false, error = WLX.helper.lastError and tostring(WLX.helper.lastError) or nil },
    bar = A.frameTree(), log = WLX.jsonArray({ unpack(A.log, max(1, #A.log - 13), #A.log) }), result = A.result, set = A.set,
    ttkLog = A.ttkLog and WLX.jsonArray(A.ttkLog) or WLX.jsonArray({}),
  }
end
