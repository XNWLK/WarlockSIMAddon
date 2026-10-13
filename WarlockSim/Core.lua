-- What ties the parts together inside the game: saved settings, the jobs that run fights a little every frame so the
-- game never freezes, the slash commands, the self-test and the diagnostic dump.
local ADDON, WL = ...

WL.VERSION = '0.5.0'
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
local DEFAULT_OPTIONS = { fights = 300, weights = true, speed = 'smooth', template = nil, stone = 'sheet', race = nil, pet = 'auto', sacrifice = 'auto', minimapHint = true,
                          itemClick = 'shift-right', itemClickDefault = 2, itemFights = 150, sheetNumbers = true }
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
function WL.doReadCharacter()
  local ch, err = WL.readCharacter()
  if not ch then return nil, err end
  ch.gear = WL.gearFromSheet(ch.sheet, ch.state)
  WL.char = ch
  return ch
end

-- ---------------------------------------------------------------------------------------------------------------------
-- jobs: fights are played inside a coroutine that hands the game back every few milliseconds
-- ---------------------------------------------------------------------------------------------------------------------
local BUDGET = { smooth = 8, fast = 30, fastest = 100 }     -- milliseconds of simulating per frame
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
  deadline = now() + (j.background and BUDGET.smooth or BUDGET[WL.db.options.speed] or BUDGET.smooth)
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

-- One build with stat weights (optional): result = { kind = 'single', res, weights, notes, build }.
function WL.simBuild(build, raceKey, cfg, label, notes)
  local n, weights = fights(), WL.db.options.weights
  local keys = WL.STAT_WEIGHT_KEYS
  return startJob(label, n * (weights and (1 + #keys) or 1), function(j)
    local function onFight() j.done = j.done + 1 end
    local res = WL.simulate(build, raceKey, cfg, { iterations = n, onFight = onFight })
    j.result.kind, j.result.res, j.result.build, j.result.notes, j.result.race = 'single', res, build, notes, raceKey
    if weights then
      local by = {}
      for i = 1, #keys do
        j.label = label .. ' - stat weights'
        by[keys[i]] = WL.statWeightRun(build, raceKey, cfg, n, keys[i], onFight)
      end
      j.result.weights = WL.combineWeights(cfg, res.dps, by)
    end
  end)
end
function WL.simCharacter()
  local build, notes = WL.characterBuildNow()
  if not build then return false, notes[1] end
  local errs = WL.validateBuild(build, true)
  if #errs > 0 then return false, errs[1] end
  return WL.simBuild(build, WL.raceKey(), WL.characterConfig(), 'My character', notes)
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
  return startJob(#list .. ' builds', n * #list, function(j)
    local rows = {}
    for i = 1, #list do
      j.label = 'Builds: ' .. (list[i].short or list[i].key)
      local res = WL.simulate(list[i], race, cfg, { iterations = n, onFight = function() j.done = j.done + 1 end })
      rows[#rows + 1] = { build = list[i], res = res }
    end
    table.sort(rows, function(a, b) return a.res.dps > b.res.dps end)
    j.result.kind, j.result.rows, j.result.race = 'rank', rows, race
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
  WL.db.dump = d
  return d
end

-- ---------------------------------------------------------------------------------------------------------------------
-- start-up and slash commands
-- ---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame('Frame')
events:RegisterEvent('ADDON_LOADED')
events:RegisterEvent('PLAYER_LOGOUT')
events:RegisterEvent('PLAYER_LOGIN')
events:SetScript('OnEvent', function(_, event, name)
  if event == 'ADDON_LOADED' and name == ADDON then
    initDB()
    if #WL.ACTIONS_MISSING > 0 then WL.print('This copy does not know these priority actions of the sim yet: ' .. table.concat(WL.ACTIONS_MISSING, ', ')) end
  elseif event == 'PLAYER_LOGIN' then
    if WL.db and WL.db.options.minimapHint then WL.print('v' .. WL.VERSION .. ' loaded. Type /wsim to open it.' .. (WL.itemClickText() and (' ' .. WL.itemClickText() .. ' an item to sim what it is worth to you.') or '')) end
  elseif event == 'PLAYER_LOGOUT' then
    if WL.db then WL.saveSettings() end
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
  elseif msg == 'help' or msg == '?' then
    WL.print('/wsim - open or close the window  |  /wsim read - read your character  |  /wsim test - check the maths against the DPS sim  |  /wsim dump - save what the game returned (for bug reports)  |  /wsim stop - stop a running sim')
  else
    if WL.toggleWindow then WL.toggleWindow() end
  end
end
