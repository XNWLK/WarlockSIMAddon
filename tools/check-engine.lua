-- Lua side of tools/check-engine.js: plays one fight with the addon's engine and returns it as JSON text.
local WL = WLX
CHK = {}
local cfg, build

local function setPath(obj, parts, i, v)
  local k = parts[i]
  if i == #parts then
    if k == '*' then for kk in pairs(obj) do obj[kk] = v end else obj[k] = v end
    return
  end
  if k == '*' then for _, o in pairs(obj) do setPath(o, parts, i + 1, v) end else setPath(obj[k], parts, i + 1, v) end
end
function CHK.setScene(patch)
  cfg = WL.copy(WL.DEFAULT_CONFIG)
  for _, p in ipairs(patch) do
    local parts = {}
    for s in string.gmatch(p[1], '[^.]+') do parts[#parts + 1] = s end
    setPath(cfg, parts, 1, p[2])
  end
end
function CHK.setBuild(b) build = b end

local function num(x)
  if x == nil then return 'null' end
  if x == math.huge then return '1e999' end
  if x == -math.huge then return '-1e999' end
  return string.format('%.17g', x)
end
function CHK.fight(race, i)
  local seed, dur = WL.fightParams(cfg, i)
  local r = WL.simulateOnce(build, race, cfg, { seed = seed, duration = dur })
  local rows = {}
  for k, x in pairs(r.bySpell) do
    rows[#rows + 1] = string.format('%q:[%s,%s,%s,%s,%s]', k, num(x.casts), num(x.dmg), num(x.misses), num(x.crits + x.tickCrits), num(x.castTime))
  end
  return '{"seed":' .. num(seed) .. ',"duration":' .. num(dur) .. ',"total":' .. num(r.total) .. ',"endMana":' .. num(r.endMana) .. ',"minMana":' .. num(r.minMana)
    .. ',"healthMin":' .. num(r.health.min) .. ',"healthEnd":' .. num(r.health.finish) .. ',"lifeTaps":' .. num(r.lifeTaps) .. ',"threat":' .. num(r.threat)
    .. ',"idle":' .. num(r.idle) .. ',"clipped":' .. num(r.clipped) .. ',"exDmg":' .. num(r.exDmg) .. ',"pushbacks":' .. num(r.pushbacks)
    .. ',"rows":{' .. table.concat(rows, ',') .. '}}'
end
function CHK.table(race)
  local stats = WL.computeStats(build, race, cfg)
  local tbl = WL.buildSpellTable(build, stats, cfg)
  local s, t = {}, {}
  for _, k in ipairs({ 'int', 'spi', 'sta', 'maxMana', 'maxHealth', 'sp', 'hitPct', 'critPct', 'hastePct', 'mp5', 'pierce' }) do
    s[#s + 1] = string.format('%q:%s', k, num(stats[k]))
  end
  for k, e in pairs(tbl) do
    local f = {}
    for _, n in ipairs({ 'cast', 'cd', 'range', 'cost', 'sp', 'critPct', 'critMult', 'directMult', 'periodicMult', 'ticks' }) do
      if e[n] ~= nil then f[#f + 1] = string.format('%q:%s', n, num(e[n])) end
    end
    t[#t + 1] = string.format('%q:{%s}', k, table.concat(f, ','))
  end
  return '{"stats":{' .. table.concat(s, ',') .. '},"table":{' .. table.concat(t, ',') .. '}}'
end
