-- What ties the parts together inside the game: saved settings, the jobs that run fights a little every frame so the
-- game never freezes, the slash commands, the self-test and the diagnostic dump.
local ADDON, WL = ...

WL.VERSION = '0.8.0'
local copy = WL.copy
local function now() return debugprofilestop and debugprofilestop() or (GetTime() * 1000) end
function WL.print(msg)
  local text = "|cff9482c9Xn's Warlock Sim:|r " .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(text) else print(text) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------------------------------------------------
-- WL.db        saved between sessions (WarlockSimDB): settings snapshot, options, imported builds, the last character read
-- WL.cfg       the settings the sim runs with (the sim's defaults + what you changed)
-- WL.char      the character read from the game (nil until "Read my character")
local DEFAULT_OPTIONS = { fights = 300, weights = true, speed = 'auto', speedDefault = 2, template = nil, stone = 'sheet', race = nil, pet = 'auto', sacrifice = 'auto', minimapHint = true,
                          itemClick = 'shift-right', itemClickDefault = 2, itemFights = 150, sheetNumbers = true, minimapButton = true, minimapAngle = 200, stopEarly = true }
-- The click that sims an item (options.itemClick). 'off' also hides the button under the item link window.
WL.ITEM_CLICKS = {
  { value = 'shift-right', label = 'Shift + right-click' }, { value = 'alt-right', label = 'Alt + right-click' }, { value = 'alt-left', label = 'Alt + left-click' },
  { value = 'ctrl-alt-right', label = 'Ctrl + Alt + right-click' }, { value = 'shift-alt-right', label = 'Shift + Alt + right-click' },
  { value = 'off', label = 'Off' },
}
function WL.itemClickText()
  local v = WL.db and WL.db.options.itemClick
  for i = 1, #WL.ITEM_CLICKS do if WL.ITEM_CLICKS[i].value == v and v ~= 'off' then return WL.ITEM_CLICKS[i].label end end
  return nil
end

function WL.newConfig()
  local cfg = copy(WL.DEFAULT_CONFIG)
  cfg.options.showWithinPct = 0
  return cfg
end

local function initDB()
  WarlockSimDB = type(WarlockSimDB) == 'table' and WarlockSimDB or {}
  local db = WarlockSimDB
  db.options = type(db.options) == 'table' and db.options or {}
  if db.options.itemButton == false and db.options.itemClick == nil then db.options.itemClick = 'off' end   -- the check box of v0.2 / v0.3
  db.options.itemButton = nil
  -- v0.4.0's default click was Alt + right-click; the default is Shift + right-click now. Moved over once; a click picked by hand afterwards stays.
  if db.options.itemClick == 'alt-right' and db.options.itemClickDefault ~= 2 then db.options.itemClick = 'shift-right' end
  db.options.itemClickDefault = 2
  -- The speed's default was "stay smooth"; it is "automatic" now. Moved over once; a speed picked by hand afterwards stays.
  if db.options.speed == 'smooth' and db.options.speedDefault ~= 2 then db.options.speed = 'auto' end
  db.options.speedDefault = 2
  for k, v in pairs(DEFAULT_OPTIONS) do if db.options[k] == nil then db.options[k] = v end end
  db.builds = type(db.builds) == 'table' and db.builds or {}        -- imported build codes: { { code = 'WFB1:...' }, ... }
  db.chars = type(db.chars) == 'table' and db.chars or {}
  WL.db = db
  WL.cfg = WL.newConfig()
  if type(db.settings) == 'table' then pcall(WL.applySettings, WL.cfg, copy(db.settings)) end
  WL.imported = {}
  for i = 1, #db.builds do
    local b = type(db.builds[i]) == 'table' and WL.decodeBuild(db.builds[i].code)
    if b then b.key = 'import' .. i; b.imported = true; WL.imported[#WL.imported + 1] = b end
  end
end
function WL.saveSettings() if WL.db then WL.db.settings = copy(WL.settingsSnapshot(WL.cfg)) end end

-- Every build a priority list can be taken from: the sim's ready builds, then the imported ones.
function WL.templates()
  local list = {}
  for i = 1, #WL.BUILDS do list[#list + 1] = WL.BUILDS[i] end
  for i = 1, #(WL.imported or {}) do list[#list + 1] = WL.imported[i] end
  return list
end
function WL.findTemplate(key)
  local list = WL.templates()
  for i = 1, #list do if list[i].key == key then return list[i] end end
  return nil
end
function WL.addImportedBuild(code)
  local b, err = WL.decodeBuild(code)
  if not b then return nil, err end
  local clean = WL.encodeBuild(b)
  for i = 1, #WL.db.builds do if WL.db.builds[i].code == clean then return WL.imported[i], nil, true end end
  WL.db.builds[#WL.db.builds + 1] = { code = clean }
  b.key = 'import' .. #WL.db.builds; b.imported = true
  WL.imported[#WL.imported + 1] = b
  return b
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the character as the sim plays it
-- ---------------------------------------------------------------------------------------------------------------------
function WL.raceKey() return (WL.char and WL.char.raceKey) or WL.db.options.race or 'human' end

-- The settings for a sim with your character's numbers: your settings, with the gear found from the character sheet.
function WL.characterConfig()
  local cfg = copy(WL.cfg)
  if WL.char and WL.char.gear then
    cfg.gear = copy(WL.char.gear)
    if WL.db.options.stone == 'sheet' and cfg.consumables.buildOil then cfg.consumables.buildOil.on = false end   -- the stone is in your numbers already
  end
  return cfg
end
-- Your character as a build: talents and demon from the game, the priority list from the chosen ready build.
function WL.characterBuildNow()
  local ch, o = WL.char, WL.db.options
  if not ch then return nil, { 'Read your character first.' } end
  local templates = WL.templates()
  local tpl = WL.findTemplate(o.template) or WL.findTemplate(WL.bestTemplate(ch.talents, templates, ch.pet)) or templates[1]
  local pet, sac = ch.pet, ch.sacrifice
  if o.pet ~= 'auto' then pet = o.pet ~= 'none' and o.pet or nil end
  if o.sacrifice ~= 'auto' then sac = o.sacrifice ~= 'none' and o.sacrifice or nil end
  local stone = o.stone == 'sheet' and 'none' or o.stone
  local b, notes = WL.characterBuild({ talents = ch.talents, pet = pet, sacrifice = sac, oil = stone }, tpl)
  b.template = tpl.key
  return b, notes, tpl
end
-- What is kept per character between sessions (WarlockSimDB.chars["Name-Realm"]): the character as last read and the
-- numbers on the character sheet, so both are there at once after a /reload or a login.
function WL.charKey()
  local ok, name, realm = pcall(function() return UnitName('player'), GetRealmName() end)
  if not ok or type(name) ~= 'string' or (issecretvalue and issecretvalue(name)) then return nil end
  return name .. '-' .. tostring(realm)
end
function WL.charStore(create)
  local key = WL.db and WL.charKey()
  if not key then return nil end
  local e = WL.db.chars[key]
  if type(e) ~= 'table' then
    if not create then return nil end
    e = {}; WL.db.chars[key] = e
  end
  return e
end
local function saveCharacter(ch)
  local e = WL.charStore(true)
  if not e then return end
  local keep = {}
  for k, v in pairs(ch) do if k ~= 'raw' and k ~= 'restored' then keep[k] = v end end   -- `raw` (what the game returned) only goes into /wsim dump
  e.char = copy(keep)
end
-- The character as last read, put back after a /reload or a login. Its gear numbers are worked out again from the saved
-- sheet numbers (so a newer version of the addon uses its own rules); anything that does not fit any more is dropped.
local function restoreCharacter()
  local e = WL.charStore(false)
  if not (e and type(e.char) == 'table' and e.char.class == 'WARLOCK' and type(e.char.sheet) == 'table' and type(e.char.state) == 'table') then return end
  local ch = copy(e.char)
  ch.raw, ch.notes, ch.restored = {}, type(ch.notes) == 'table' and ch.notes or {}, true
  local ok = pcall(function()
    ch.gear = WL.gearFromSheet(ch.sheet, ch.state)
    WL.char = ch
    local b = WL.characterBuildNow()
    if not b then error('no build') end
  end)
  if not ok then WL.char = nil; e.char = nil end
end
function WL.doReadCharacter()
  local ch, err = WL.readCharacter()
  if not ch then return nil, err end
  ch.gear = WL.gearFromSheet(ch.sheet, ch.state)
  WL.char = ch
  saveCharacter(ch)
  return ch
end

-- ---------------------------------------------------------------------------------------------------------------------
-- jobs: fights are played inside a coroutine that hands the game back every few milliseconds
-- ---------------------------------------------------------------------------------------------------------------------
local BUDGET = { smooth = 8, fast = 30, fastest = 100 }     -- milliseconds of simulating per frame
-- 'auto': quick while you are out of combat (you are waiting for the result), gentle while you fight
local function budget()
  local s = WL.db.options.speed
  if s == 'auto' or not BUDGET[s] then return (InCombatLockdown and InCombatLockdown()) and BUDGET.smooth or BUDGET.fast end
  return BUDGET[s]
end
local job, deadline
local driver = CreateFrame('Frame')
driver:Hide()

WL.onTick = function()
  if job and now() > deadline then coroutine.yield() end
end
-- A job is either one you started (a sim from the window, an item sim) or background work (the numbers on the character
-- sheet). Background work never shows in the window, always runs at the gentle speed, and gives way at once when you
-- start something yourself.
function WL.jobRunning() return job ~= nil and not job.background end
function WL.backgroundRunning() return job ~= nil and job.background == true end
function WL.jobProgress()
  if not job or job.background then return nil end
  return job.done, job.total, job.label, (now() - job.started) / 1000
end
function WL.cancelJob()
  if not job or job.background then return end
  job = nil
  driver:Hide()
  if WL.onJobEnd then WL.onJobEnd(nil, 'Stopped.') end
end
function WL.cancelBackground()
  if not job or not job.background then return end
  job = nil
  driver:Hide()
end
driver:SetScript('OnUpdate', function()
  if not job then driver:Hide(); return end
  local j = job
  deadline = now() + (j.background and BUDGET.smooth or budget())
  local t0 = now()
  local ok, err = coroutine.resume(j.co)
  j.cpu = j.cpu + (now() - t0)
  if job ~= j then return end                               -- stopped from inside
  if not ok then
    job = nil; driver:Hide()
    WL.lastError = tostring(err)
    if j.background then
      if WL.onBackgroundEnd then WL.onBackgroundEnd(false, tostring(err)) end
    elseif WL.onJobEnd then WL.onJobEnd(nil, 'The sim stopped with an error: ' .. tostring(err)) end
  elseif coroutine.status(j.co) == 'dead' then
    job = nil; driver:Hide()
    if j.background then
      if WL.onBackgroundEnd then WL.onBackgroundEnd(true) end
      return
    end
    j.result.cpuSeconds = j.cpu / 1000
    j.result.seconds = (now() - j.started) / 1000
    j.result.fights = j.done
    WL.db.lastTiming = { fights = j.done, cpuSeconds = j.result.cpuSeconds, seconds = j.result.seconds, msPerFight = j.done > 0 and j.cpu / j.done or 0, speed = WL.db.options.speed }
    if WL.onJobEnd then WL.onJobEnd(j.result) end
  end
end)
-- fn(job) runs in the coroutine; it adds to job.done as fights finish and fills job.result.
-- background = true: see above. Returns false when another job is in the way.
local function startJob(label, total, fn, background)
  if job then
    if job.background and not background then job = nil     -- the background work gives way; it is taken up again later
    else return false end
  end
  local j = { label = label, total = total, done = 0, started = now(), cpu = 0, result = {}, background = background and true or false }
  j.co = coroutine.create(function() fn(j) end)
  job = j
  driver:Show()
  return true
end

WL.startJob = startJob

local function fights() return math.max(10, math.min(20000, math.floor(tonumber(WL.db.options.fights) or 300))) end

-- Stopping once the result is exact enough (options.stopEarly, on by default; the number of fights set is then the most
-- that are played, never fewer than MIN_FIGHTS). Two rules, each a function(fight number, that fight's DPS) -> stop?
--   one run on its own: stop when the +- of the DPS is at most 0.5% of it;
--   one side of a comparison (it plays the same fights as `baseList`): stop when the +- of the difference, taken fight
--   by fight, is at most `abs` DPS or `rel` of the difference - and at the end of the base run's fights at the latest.
local MIN_FIGHTS = 40
function WL.stopEarly() return WL.db ~= nil and WL.db.options.stopEarly ~= false end
local function margin(s, s2, i)
  local mean = s / i
  return mean, 1.96 * math.sqrt(math.max(0, (s2 - i * mean * mean) / (i - 1)) / i)
end
function WL.singleStop()
  if not WL.stopEarly() then return nil end
  local s, s2 = 0, 0
  return function(i, dps)
    s, s2 = s + dps, s2 + dps * dps
    if i < MIN_FIGHTS then return false end
    local mean, err = margin(s, s2, i)
    return err <= 0.005 * mean
  end
end
function WL.pairedStop(baseList, rel, abs)
  if not WL.stopEarly() then return nil end
  local s, s2 = 0, 0
  return function(i, dps)
    local d = dps - (baseList[i] or dps)
    s, s2 = s + d, s2 + d * d
    if i >= #baseList then return true end
    if i < MIN_FIGHTS then return false end
    local mean, err = margin(s, s2, i)
    return err <= math.max(abs or 0.5, (rel or 0.1) * math.abs(mean))
  end
end
-- Both sides of a comparison played fight by fight, side by side (fight i with the same seed and length on both), so
-- they stop together once the difference is exact enough. For "What if", which also shows the change per spell.
-- Returns two results with what the window shows: dps, dpsList, bySpell[k].dmg (an average fight), avgDuration, iterations.
function WL.pairedRun(build, race, cfgA, cfgB, n, onFight)
  local stA, stB = WL.computeStats(build, race, cfgA), WL.computeStats(build, race, cfgB)
  local tA, tB = WL.buildSpellTable(build, stA, cfgA), WL.buildSpellTable(build, stB, cfgB)
  local A, B = { dpsList = {}, bySpell = {}, dur = 0 }, { dpsList = {}, bySpell = {}, dur = 0 }
  local early, s, s2, played = WL.stopEarly(), 0, 0, 0
  for i = 0, n - 1 do
    local seed, dur = WL.fightParams(cfgA, i)
    local a = WL.simulateOnce(build, race, cfgA, { stats = stA, table = tA, seed = seed, duration = dur })
    local b = WL.simulateOnce(build, race, cfgB, { stats = stB, table = tB, seed = seed, duration = dur })
    for _, pair in ipairs({ { A, a }, { B, b } }) do
      local side, r = pair[1], pair[2]
      side.dpsList[i + 1] = r.dps; side.dur = side.dur + r.duration
      for k, row in pairs(r.bySpell) do side.bySpell[k] = side.bySpell[k] or { dmg = 0 }; side.bySpell[k].dmg = side.bySpell[k].dmg + row.dmg end
    end
    played = i + 1
    if onFight then onFight(); onFight() end
    local d = b.dps - a.dps
    s, s2 = s + d, s2 + d * d
    if early and played >= MIN_FIGHTS and played < n then          -- the same rule as WL.pairedStop
      local mean, err = margin(s, s2, played)
      if err <= math.max(0.5, 0.1 * math.abs(mean)) then break end
    end
  end
  for _, side in ipairs({ A, B }) do
    local s = 0
    for f = 1, played do s = s + side.dpsList[f] end
    side.dps, side.avgDuration, side.iterations = s / played, side.dur / played, played
    for _, row in pairs(side.bySpell) do row.dmg = row.dmg / played end
  end
  return A, B
end
-- The difference of a comparison, fight by fight over the fights both sides played: mean, its +-, number of fights.
function WL.pairedDiff(baseList, list)
  local n = math.min(#baseList, #list)
  local s, s2 = 0, 0
  for f = 1, n do local d = list[f] - baseList[f]; s = s + d; s2 = s2 + d * d end
  if n < 2 then return n == 1 and s or 0, 0, n end
  local mean, err = margin(s, s2, n)
  return mean, err, n
end

-- One build with stat weights (optional): result = { kind = 'single', res, weights, notes, build }.
-- Results of the last sims, by everything that decides them: asking for the same thing again costs nothing.
local remembered, REMEMBER = {}, 6
local function recall(key)
  for i = 1, #remembered do if remembered[i].key == key then return remembered[i].result end end
  return nil
end
local function remember(key, result)
  table.insert(remembered, 1, { key = key, result = result })
  remembered[REMEMBER + 1] = nil
end
local function answerFromMemory(result)
  if job and not job.background then return false end      -- a sim of yours is running; background work does not matter here
  local r = {}
  for k, v in pairs(result) do r[k] = v end
  r.remembered = true
  if WL.onJobEnd then WL.onJobEnd(r) end
  return true
end
function WL.simBuild(build, raceKey, cfg, label, notes)
  local n, weights = fights(), WL.db.options.weights
  local keys = WL.STAT_WEIGHT_KEYS
  local key = 'single|' .. n .. '|' .. tostring(WL.stopEarly()) .. '|' .. raceKey .. '|' .. tostring(weights) .. '|' .. WL.encodeBuild(build) .. WL.jsonEncode(WL.settingsSnapshot(cfg))
  local known = recall(key)
  if known then return answerFromMemory(known) end
  return startJob(label, n * (weights and (1 + #keys) or 1), function(j)
    local function onFight() j.done = j.done + 1 end
    local res = WL.simulate(build, raceKey, cfg, { iterations = n, onFight = onFight, stop = WL.singleStop() })
    j.result.kind, j.result.res, j.result.build, j.result.notes, j.result.race = 'single', res, build, notes, raceKey
    if weights then
      -- the DPS and the spells are on screen now; the stat weights follow
      j.result.weightsPending = true
      if WL.onJobPartial then WL.onJobPartial(j.result) end
      j.total = j.done + #res.dpsList * #keys             -- the weights play at most as many fights as the run above did
      local by = {}
      for i = 1, #keys do
        j.label = label .. ' - stat weights'
        -- the same fights with a little more of one stat; the difference is taken fight by fight, so each weight can stop
        -- on its own once exact enough (2% of the difference - the steps are big, +100 spell power, +2% hit... - or 0.25 DPS)
        local c = copy(cfg)
        c.extra = c.extra or {}
        c.extra[keys[i]] = (c.extra[keys[i]] or 0) + cfg.weightDeltas[keys[i]]
        local r = WL.simulate(build, raceKey, c, { iterations = #res.dpsList, onFight = onFight, stop = WL.pairedStop(res.dpsList, 0.02, 0.25) })
        by[keys[i]] = res.dps + WL.pairedDiff(res.dpsList, r.dpsList)
      end
      j.result.weights = WL.combineWeights(cfg, res.dps, by)
      j.result.weightsPending = nil
    end
    remember(key, j.result)
  end)
end
function WL.simCharacter()
  local build, notes = WL.characterBuildNow()
  if not build then return false, notes[1] end
  local errs = WL.validateBuild(build, true)
  if #errs > 0 then return false, errs[1] end
  return WL.simBuild(build, WL.raceKey(), WL.characterConfig(), 'My character', notes)
end
-- "What if": your character as it is against your character with some stats more or less (delta: the stats of
-- Items.lua, e.g. { sp = 10, hit = 1 }; hit / crit / haste in percent). Both sides play the same fights, so the
-- difference is measured, not two separate guesses. result = { kind = 'whatif', base, res, diff, err, delta, build, race }.
function WL.simWhatIf(delta)
  local build, notes = WL.characterBuildNow()
  if not build then return false, notes[1] end
  local errs = WL.validateBuild(build, true)
  if #errs > 0 then return false, errs[1] end
  local any, parts = false, {}
  for i = 1, #WL.ITEM_STAT_ORDER do
    local v = tonumber(delta[WL.ITEM_STAT_ORDER[i]]) or 0
    if v ~= 0 then any = true end
    parts[#parts + 1] = tostring(v)
  end
  if not any then return false, 'Enter a change first (or press one of the + buttons).' end
  local cfg, race, n = WL.characterConfig(), WL.raceKey(), fights()
  local gear, d = WL.gearWithSwap(cfg.gear, delta, {}, cfg)
  local changed = copy(cfg)
  changed.gear = gear
  local key = 'whatif|' .. n .. '|' .. tostring(WL.stopEarly()) .. '|' .. race .. '|' .. table.concat(parts, ',') .. '|' .. WL.encodeBuild(build) .. WL.jsonEncode(WL.settingsSnapshot(cfg))
  local known = recall(key)
  if known then return answerFromMemory(known) end
  return startJob('What if', 2 * n, function(j)
    local function onFight() j.done = j.done + 1 end
    local base, res = WL.pairedRun(build, race, cfg, changed, n, onFight)
    local r = j.result
    r.kind, r.base, r.res, r.build, r.race, r.delta, r.notes = 'whatif', base, res, build, race, d, notes
    r.diff, r.err = WL.pairedDiff(base.dpsList, res.dpsList)
    remember(key, r)
  end)
end
-- Every ready build (and your character, if read) with your numbers: result = { kind = 'rank', rows = { { build, res }, ... } }.
function WL.simRanking()
  -- your gear as it is right now (not possible in combat, and not for another class: then what was read last, or the settings' numbers)
  if not (InCombatLockdown and InCombatLockdown()) then WL.doReadCharacter() end
  local n, race, cfg = fights(), WL.raceKey(), WL.characterConfig()
  local list = {}
  local mine = WL.char and WL.characterBuildNow()
  if mine and #WL.validateBuild(mine, true) == 0 then list[#list + 1] = mine end
  local tpls = WL.templates()
  for i = 1, #tpls do list[#list + 1] = tpls[i] end
  local key = 'rank|' .. n .. '|' .. tostring(WL.stopEarly()) .. '|' .. race .. '|' .. WL.jsonEncode(WL.settingsSnapshot(cfg))
  for i = 1, #list do key = key .. '|' .. WL.encodeBuild(list[i]) end
  local known = recall(key)
  if known then return answerFromMemory(known) end
  return startJob(#list .. ' builds', n * #list, function(j)
    local rows = {}
    j.result.kind, j.result.rows, j.result.race = 'rank', rows, race
    for i = 1, #list do
      j.label = 'Builds: ' .. (list[i].short or list[i].key)
      local res = WL.simulate(list[i], race, cfg, { iterations = n, onFight = function() j.done = j.done + 1 end, stop = WL.singleStop() })
      j.done = n * i                                       -- a build that stopped early moves the bar on to the next one
      rows[#rows + 1] = { build = list[i], res = res }
      table.sort(rows, function(a, b) return a.res.dps > b.res.dps end)
      -- the list grows on screen build by build
      if i < #list then j.result.pending = #list - i; if WL.onJobPartial then WL.onJobPartial(j.result) end end
    end
    j.result.pending = nil
    remember(key, j.result)
  end)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- self-test: a few fights whose exact damage is known from the DPS sim (Expected.lua, written by tools/gen-expected.js)
-- ---------------------------------------------------------------------------------------------------------------------
function WL.selfTest()
  local exp = WL.EXPECTED
  if not exp then return false, 'No expected values in this copy.' end
  if job and job.background then job = nil; driver:Hide() end   -- background work gives way
  if job then return false, 'A sim is running - wait for it or type /wsim stop first.' end
  local bad, lines, t0 = 0, {}, now()
  for i = 1, #exp.fights do
    local e = exp.fights[i]
    local build = WL.BUILD_BY_KEY[e.build]
    local seed, dur = WL.fightParams(WL.DEFAULT_CONFIG, e.i)
    local ok, r = pcall(WL.simulateOnce, build, e.race, WL.DEFAULT_CONFIG, { seed = seed, duration = dur })
    local total = ok and r.total or nil
    local good = total ~= nil and math.abs(total - e.total) <= 1e-6 * e.total
    if not good then bad = bad + 1 end
    lines[#lines + 1] = string.format('%s %s #%d: %s (expected %.3f, got %s)', e.build, e.race, e.i, good and 'ok' or 'DIFFERENT', e.total, ok and string.format('%.3f', total) or tostring(r))
  end
  local ms = now() - t0
  local res = { ok = bad == 0, bad = bad, fights = #exp.fights, ms = ms, msPerFight = ms / #exp.fights, lines = lines, simCommit = WL.SIM_COMMIT, version = WL.VERSION }
  if WL.db then WL.db.selfTest = res end
  return bad == 0, res
end

-- ---------------------------------------------------------------------------------------------------------------------
-- diagnostic dump: what the game returned when the character was read, saved with the settings file so it can be looked at
-- ---------------------------------------------------------------------------------------------------------------------
function WL.dump()
  local d = { at = date and date('%Y-%m-%d %H:%M:%S') or '', version = WL.VERSION, simCommit = WL.SIM_COMMIT }
  if GetBuildInfo then d.build = { GetBuildInfo() } end
  local ch = WL.char
  if ch then
    d.character = { name = ch.name, realm = ch.realm, level = ch.level, raceKey = ch.raceKey, pet = ch.pet, sacrifice = ch.sacrifice, sheet = ch.sheet, gear = ch.gear,
                    talents = ch.talents, buffsOnYou = ch.buffsOnYou, otherAuras = ch.otherAuras, notes = ch.notes, isSword = ch.isSword, weaponEffect = ch.weaponEffect, raw = ch.raw }
  end
  d.lastTiming, d.selfTest, d.lastError = WL.db.lastTiming, WL.db.selfTest, WL.lastError
  d.sheet = WL.sheetState and WL.sheetState() or nil      -- the numbers on the character sheet
  d.lastItem = WL.db.lastItem                              -- what the game returned for the items of the last item comparison
  d.lastGear = WL.db.lastGear                              -- the last gear code: each worn link, and how its enchant was read
  d.blocked = WL.db.blocked                                -- actions of this addon the game blocked (the watcher)
  WL.db.dump = d
  return d
end

-- ---------------------------------------------------------------------------------------------------------------------
-- start-up and slash commands
-- ---------------------------------------------------------------------------------------------------------------------
WL.loginHooks, WL.logoutHooks = {}, {}                    -- other files add what they do at login / logout

-- The watcher: when the game blocks an action and names this addon (it says so through these two events, in combat
-- too, where it otherwise stays silent), it is noted with the action and the time (WarlockSimDB.blocked, the last 20)
-- and said once per action in chat. It only listens.
local blockedSaid = {}
local function noteBlocked(event, addon, action)
  if addon ~= ADDON or not WL.db then return end
  local list = type(WL.db.blocked) == 'table' and WL.db.blocked or {}
  WL.db.blocked = list
  table.insert(list, 1, { at = date and date('%Y-%m-%d %H:%M:%S') or '', event = event, action = tostring(action), combat = (InCombatLockdown and InCombatLockdown()) and true or false, version = WL.VERSION })
  list[21] = nil
  if not blockedSaid[tostring(action)] then
    blockedSaid[tostring(action)] = true
    WL.print('|cffff6060The game blocked an action of this addon:|r ' .. tostring(action) .. '. It is noted for a bug report (/wsim blocked lists them).')
  end
end

local events = CreateFrame('Frame')
events:RegisterEvent('ADDON_LOADED')
events:RegisterEvent('PLAYER_LOGOUT')
events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('ADDON_ACTION_BLOCKED')
events:RegisterEvent('ADDON_ACTION_FORBIDDEN')
events:SetScript('OnEvent', function(_, event, name, extra)
  if event == 'ADDON_ACTION_BLOCKED' or event == 'ADDON_ACTION_FORBIDDEN' then noteBlocked(event, name, extra); return end
  if event == 'ADDON_LOADED' and name == ADDON then
    initDB()
    if #WL.ACTIONS_MISSING > 0 then WL.print('This copy does not know these priority actions of the sim yet: ' .. table.concat(WL.ACTIONS_MISSING, ', ')) end
  elseif event == 'PLAYER_LOGIN' then
    if WL.db and not WL.char then restoreCharacter() end
    for i = 1, #WL.loginHooks do WL.loginHooks[i]() end    -- the minimap button, the numbers on the character sheet
    if WL.db and WL.db.options.minimapHint then WL.print('v' .. WL.VERSION .. ' loaded. Type /wsim to open it.' .. (WL.itemClickText() and (' ' .. WL.itemClickText() .. ' an item to sim what it is worth to you.') or '')) end
  elseif event == 'PLAYER_LOGOUT' then
    if WL.db then WL.saveSettings() end
    for i = 1, #WL.logoutHooks do WL.logoutHooks[i]() end
  end
end)

SLASH_WARLOCKSIM1, SLASH_WARLOCKSIM2 = '/wsim', '/warlocksim'
SlashCmdList['WARLOCKSIM'] = function(msg)
  msg = string.lower(strtrim and strtrim(msg or '') or (msg or ''))
  if msg == 'test' then
    local ok, res = WL.selfTest()
    if type(res) ~= 'table' then WL.print(tostring(res)); return end
    WL.print(string.format('Self-test: %s - %d of %d fights match the DPS sim exactly; %.0f ms a fight.', ok and '|cff40ff40passed|r' or '|cffff4040FAILED|r', res.fights - res.bad, res.fights, res.msPerFight))
    if not ok then for i = 1, #res.lines do if res.lines[i]:find('DIFFERENT') then WL.print(res.lines[i]) end end end
  elseif msg == 'dump' then
    WL.dump()
    WL.print('Saved what the game returned. Type /reload (or log out) so it is written to the settings file.')
  elseif msg == 'read' then
    local ch, err = WL.doReadCharacter()
    WL.print(ch and ('Read ' .. tostring(ch.name) .. ': ' .. WL.talentSplit(ch.talents) .. ', ' .. tostring(ch.sheet.sp) .. ' spell power.') or err)
    if WL.refresh then WL.refresh() end
  elseif msg == 'stop' then
    WL.cancelJob()
  elseif msg == 'blocked' then
    local list = type(WL.db.blocked) == 'table' and WL.db.blocked or {}
    if #list == 0 then WL.print('The game has not blocked anything of this addon.') end
    for i = 1, #list do local b = list[i]; WL.print(string.format('%s  %s  %s%s (v%s)', b.at, b.event == 'ADDON_ACTION_FORBIDDEN' and 'forbidden' or 'blocked', b.action, b.combat and ', in combat' or '', tostring(b.version))) end
  elseif msg == 'minimap' then
    WL.db.options.minimapButton = not WL.db.options.minimapButton
    if WL.updateMinimapButton then WL.updateMinimapButton() end
    WL.print('Minimap button ' .. (WL.db.options.minimapButton and 'shown.' or 'hidden. /wsim minimap brings it back.'))
    if WL.refresh then WL.refresh() end
  elseif msg == 'help' or msg == '?' then
    WL.print('/wsim - open or close the window  |  /wsim read - read your character  |  /wsim minimap - show or hide the minimap button  |  /wsim test - check the maths against the DPS sim  |  /wsim dump - save what the game returned (for bug reports)  |  /wsim stop - stop a running sim  |  /wsim blocked - actions of this addon the game blocked')
  else
    if WL.toggleWindow then WL.toggleWindow() end
  end
end
