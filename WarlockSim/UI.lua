-- The window: five tabs on top (Character, Builds, Fight, Buffs, Codes), the result underneath.
-- It is the addon's own frame: nothing is registered in Blizzard's settings and no Blizzard frame is touched.
local ADDON, WL = ...

local W, H = 430, 658
local PAD = 12
local main, tabs, pages, result = nil, {}, {}, {}
local current                                             -- the result on screen
local floor = math.floor
local copy = WL.copy

local function fmt(x, d)
  if x == nil then return '?' end
  return string.format('%.' .. (d or 0) .. 'f', x)
end
local function pctText(x) return fmt(x, x == floor(x) and 0 or 1) .. '%' end

-- ---------------------------------------------------------------------------------------------------------------------
-- small widget helpers
-- ---------------------------------------------------------------------------------------------------------------------
local function Text(parent, font, text)
  local fs = parent:CreateFontString(nil, 'ARTWORK', font or 'GameFontHighlightSmall')
  fs:SetJustifyH('LEFT'); fs:SetJustifyV('TOP')
  if text then fs:SetText(text) end
  return fs
end
local function tip(frame, getText)
  frame:SetScript('OnEnter', function(self)
    local t = getText
    if type(t) == 'function' then t = t(self) end
    if not t or t == '' or not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:SetText(t, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end
local function Button(parent, text, width, onClick, tooltip)
  local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  b:SetSize(width, 22); b:SetText(text)
  b:SetScript('OnClick', onClick)
  if tooltip then tip(b, tooltip) end
  return b
end
local function Check(parent, label, get, set, tooltip)
  local cb = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
  cb:SetSize(22, 22)
  local own = cb.Text or cb.text
  if type(own) == 'table' and own.SetText then own:SetText('') end
  cb.label = Text(parent, 'GameFontHighlightSmall', label)
  cb.label:SetPoint('LEFT', cb, 'RIGHT', 2, 0)
  cb:SetScript('OnClick', function(self) set(self:GetChecked() and true or false); if WL.refresh then WL.refresh() end end)
  cb.sync = function() cb:SetChecked(get() and true or false) end
  if tooltip then tip(cb, tooltip) end
  return cb
end
local function Edit(parent, width, get, set, tooltip)
  local e = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
  e:SetSize(width, 20); e:SetAutoFocus(false)
  if e.SetMaxLetters then e:SetMaxLetters(8) end
  local function apply(self)
    local v = tonumber(((self:GetText() or ''):gsub(',', '.')))
    if v then set(v) end
    self:ClearFocus()
    if WL.refresh then WL.refresh() end
  end
  e:SetScript('OnEnterPressed', apply)
  e:SetScript('OnEscapePressed', function(self) self:ClearFocus(); if WL.refresh then WL.refresh() end end)
  e:SetScript('OnEditFocusLost', function(self)
    local v = tonumber(((self:GetText() or ''):gsub(',', '.')))
    if v then set(v) end
  end)
  e.sync = function() if not e:HasFocus() then e:SetText(tostring(get())) end end
  if tooltip then tip(e, tooltip) end
  return e
end

-- one shared pop-up list for all dropdowns
local menu, menuCatcher, menuButtons = nil, nil, {}
local function hideMenu() if menu then menu:Hide() end; if menuCatcher then menuCatcher:Hide() end end
local function showMenu(anchor, items, onPick)
  if not menu then
    menuCatcher = CreateFrame('Button', nil, UIParent)
    menuCatcher:SetAllPoints(UIParent); menuCatcher:SetFrameStrata('FULLSCREEN')
    menuCatcher:SetScript('OnClick', hideMenu)
    menu = CreateFrame('Frame', 'WarlockSimMenu', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
    menu:SetFrameStrata('FULLSCREEN_DIALOG')
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menu:SetBackdropColor(0.06, 0.05, 0.09, 0.98); menu:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
    end
  end
  local width = math.max(anchor:GetWidth(), 120)
  for i = 1, #items do
    local b = menuButtons[i]
    if not b then
      b = CreateFrame('Button', nil, menu)
      b:SetHeight(18)
      b.text = Text(b, 'GameFontHighlightSmall'); b.text:SetPoint('LEFT', 6, 0); b.text:SetJustifyV('MIDDLE')
      local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(0.58, 0.51, 0.79, 0.35)
      menuButtons[i] = b
    end
    b.text:SetText(items[i].label)
    local need = (b.text.GetStringWidth and b.text:GetStringWidth() or 100) + 16
    if need > width then width = need end
    b:SetScript('OnClick', function() hideMenu(); onPick(items[i].value) end)
    b:Show()
  end
  for i = #items + 1, #menuButtons do menuButtons[i]:Hide() end
  for i = 1, #items do
    menuButtons[i]:ClearAllPoints()
    menuButtons[i]:SetPoint('TOPLEFT', menu, 'TOPLEFT', 4, -4 - (i - 1) * 18)
    menuButtons[i]:SetWidth(width - 8)
  end
  menu:SetSize(width, #items * 18 + 8)
  menu:ClearAllPoints(); menu:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, 0)
  menuCatcher:Show(); menu:Show()
end
-- items() -> { { value, label }, ... }; get() -> value; set(value)
local function Dropdown(parent, width, items, get, set, tooltip)
  local d = CreateFrame('Button', nil, parent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
  d:SetSize(width, 20)
  if d.SetBackdrop then
    d:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    d:SetBackdropColor(0.1, 0.09, 0.14, 0.9); d:SetBackdropBorderColor(0.45, 0.42, 0.55, 1)
  end
  d.text = Text(d, 'GameFontHighlightSmall'); d.text:SetPoint('LEFT', 6, 0); d.text:SetPoint('RIGHT', -14, 0); d.text:SetJustifyV('MIDDLE')
  if d.text.SetWordWrap then d.text:SetWordWrap(false) end
  local arrow = Text(d, 'GameFontHighlightSmall', 'v'); arrow:SetPoint('RIGHT', -5, 0)
  d:SetScript('OnClick', function(self)
    if menu and menu:IsShown() then hideMenu(); return end
    showMenu(self, items(), function(v) set(v); if WL.refresh then WL.refresh() end end)
  end)
  d.sync = function()
    local list, v, label = items(), get(), nil
    for i = 1, #list do if list[i].value == v then label = list[i].label end end
    d.text:SetText(label or (list[1] and list[1].label) or '')
  end
  if tooltip then tip(d, tooltip) end
  return d
end

local syncers = {}
local function keep(w) syncers[#syncers + 1] = w; return w end

-- ---------------------------------------------------------------------------------------------------------------------
-- result area
-- ---------------------------------------------------------------------------------------------------------------------
local ROWS = 10
local PET_ROW = { melee = 'melee', brand = 'Demonic Brand' }
local function rowInfo(key, build)
  local target, bk = key:match('^x(%d):(.+)$')
  bk = bk or key
  local name, icon
  if bk:sub(1, 4) == 'pet:' then
    local p = bk:sub(5)
    local pet = build and build.pet and WL.DEFAULT_CONFIG.pets[build.pet]
    if p == 'melee' then name = (pet and pet.name or 'Demon') .. ' melee'
    elseif PET_ROW[p] then name = PET_ROW[p]
    else
      for _, pc in pairs(WL.DEFAULT_CONFIG.pets) do if pc.spell and pc.spell.key == p then name = pc.spell.name .. ' (' .. pc.name .. ')'; icon = pc.spell.id end end
    end
  elseif bk:sub(1, 5) == 'item:' then
    local c = WL.DEFAULT_CONFIG.consumables[bk:sub(6)]
    name = c and c.name
  elseif bk == 'touchOfTheGrave' then name, icon = 'Touch of the Grave', 1260201
  elseif WL.SPELLS[bk] then name, icon = WL.SPELLS[bk].name, WL.SPELLS[bk].id end
  name = name or bk
  if target then name = name .. ' (target ' .. target .. ')' end
  return name, icon
end
local function spellIcon(id)
  if not id or not (C_Spell and C_Spell.GetSpellTexture) then return nil end
  local ok, tex = pcall(C_Spell.GetSpellTexture, id)
  return ok and tex or nil
end

local function setRows(rows)                             -- rows: { { label, value, share (0..1), right, icon, tip, onClick } }
  for i = 1, ROWS do
    local r, d = result.rows[i], rows[i]
    if d then
      r.label:SetText(d.label); r.right:SetText(d.right or '')
      r.bar:SetValue(math.max(0, math.min(1, d.share or 0)))
      local c = d.color
      r.bar:SetStatusBarColor(c and c[1] or 0.58, c and c[2] or 0.51, c and c[3] or 0.79, c and c[4] or 0.55)
      if d.icon then r.icon:SetTexture(d.icon); r.icon:Show() else r.icon:Hide() end
      r.tipText, r.onClick = d.tip, d.onClick
      r:Show()
    else r:Hide() end
  end
end

local function showSingle(res, build, raceKey, weights, notes, fromRank)
  local race = WL.RACES[raceKey] and WL.RACES[raceKey].name or raceKey
  result.head:SetText(string.format('%s DPS  |cffaaaaaa+- %s|r', fmt(res.dps, 1), fmt(res.dpsErr, 1)))
  result.sub:SetText(string.format('%s - %s - %d fights of about %d s%s', build.short or 'Build', race, res.iterations, floor(res.avgDuration + 0.5), fromRank and '   |cff9482c9(click here: back to the ranking)|r' or ''))
  local list, total = {}, 0
  for k, r in pairs(res.bySpell) do
    if r.dmg > 0 then list[#list + 1] = { key = k, r = r }; total = total + r.dmg end
  end
  table.sort(list, function(a, b) return a.r.dmg > b.r.dmg end)
  local rows, other = {}, 0
  local top = list[1] and list[1].r.dmg or 1
  for i = 1, #list do
    local k, r = list[i].key, list[i].r
    if i < ROWS or #list == ROWS then
      local name, icon = rowInfo(k, build)
      local hits = r.hits + r.ticks
      rows[#rows + 1] = { label = name, share = r.dmg / top, right = string.format('%s%%', fmt(100 * r.dmg / total, 1)), icon = spellIcon(icon),
        tip = string.format('%s\n%s DPS (%s%% of your damage)\n%s casts a fight%s\nCrits: %s%% of hits and ticks%s', name, fmt(r.dmg / res.avgDuration, 1), fmt(100 * r.dmg / total, 1), fmt(r.casts, 1),
          r.misses > 0 and string.format(', %s missed', fmt(r.misses, 1)) or '', fmt(hits > 0 and 100 * (r.crits + r.tickCrits) / hits or 0, 1),
          r.castTime > 0 and string.format('\nDamage per second of cast time: %s', fmt(r.dmg / r.castTime, 0)) or '') }
    else other = other + r.dmg end
  end
  if other > 0 then rows[#rows + 1] = { label = 'Everything else', share = other / top, right = string.format('%s%%', fmt(100 * other / total, 1)) } end
  setRows(rows)
  local lines = {}
  if weights and weights.sp and weights.sp > 0 then
    local function eq(k, per) return fmt(weights[k] * per / weights.sp, 1) end
    lines[#lines + 1] = string.format('|cffffd100Worth in spell power:|r 1%% hit = %s   1%% crit = %s   1%% haste = %s', eq('hitPct', 1), eq('critPct', 1), eq('hastePct', 1))
    lines[#lines + 1] = string.format('10 Intellect = %s   10 Spell Pierce = %s   |cffaaaaaa(1 spell power = %s DPS)|r', eq('int', 10), eq('pierce', 10), fmt(weights.sp, 2))
  elseif weights then
    lines[#lines + 1] = 'Stat weights: spell power gave no gain in this run (try more fights).'
  elseif current and current.weightsPending then
    lines[#lines + 1] = '|cffaaaaaaStat weights: still simming...|r'
  end
  lines[#lines + 1] = string.format('|cffaaaaaaLife Taps a fight: %s   lowest mana: %s   threat: %s a second%s|r', fmt(res.lifeTaps, 1), fmt(res.minMana, 0), fmt(res.tps, 0),
    res.mana.oomAvg > 0 and '   |cffff6060out of mana at times|r' or '')
  for i = 1, #(notes or {}) do lines[#lines + 1] = '|cffffb060' .. notes[i] .. '|r' end
  if WL.char and (WL.char.level or 60) < 60 then lines[#lines + 1] = string.format('|cffffb060A level 60 number: you are level %d (see the Character tab).|r', WL.char.level) end
  result.info:SetText(table.concat(lines, '\n'))
end

local function showRank(r)
  local best = r.rows[1]
  result.head:SetText(string.format('Best with your gear: %s', best.build.short or best.build.key))
  local race = WL.RACES[r.race] and WL.RACES[r.race].name or r.race
  result.sub:SetText(string.format('%d builds with your gear - %s - %d fights each. Click a build for its spells.', #r.rows, race, best.res.iterations))
  local rows = {}
  for i = 1, math.min(#r.rows, ROWS) do
    local row = r.rows[i]
    local mine = row.build.key == 'character'              -- your own character among the sim's builds: gold, so it stands out
    rows[i] = { label = (mine and '|cffffd100' or '') .. i .. '  ' .. (row.build.short or row.build.key) .. (mine and '  (you)|r' or ''), share = row.res.dps / best.res.dps,
      right = (mine and '|cffffd100' or '') .. fmt(row.res.dps, 1) .. (mine and '|r' or ''), color = mine and { 1, 0.82, 0, 0.6 } or nil,
      tip = string.format('%s\n%s DPS (+- %s)\n%s%% behind the best\n%s', row.build.name or row.build.short or '', fmt(row.res.dps, 1), fmt(row.res.dpsErr, 1), fmt(100 * (1 - row.res.dps / best.res.dps), 1), row.build.notes or ''),
      onClick = function() current = { kind = 'single', res = row.res, build = row.build, race = r.race, back = r }; WL.showResult(current) end }
  end
  setRows(rows)
  result.info:SetText((r.pending and ('|cffaaaaaa' .. r.pending .. ' more to come...|r\n') or '') .. '|cffaaaaaaDifferences smaller than the +- of two builds are noise. Run more fights (Fight tab) to tell close builds apart.|r')
end

local function signed(x, d) return (x >= 0 and '+' or '') .. fmt(x, d) end
-- "What if": the change in DPS, and which spells it came from
local function showWhatIf(r)
  result.head:SetText(string.format('%s%s DPS|r  |cffaaaaaa+- %s|r', r.diff >= 0 and '|cff40ff40' or '|cffff6060', signed(r.diff, 1), fmt(r.err, 1)))
  result.sub:SetText(string.format('What if %s:  %s -> %s DPS', WL.describeStats(r.delta, true), fmt(r.base.dps, 1), fmt(r.res.dps, 1)))
  local list, seen, dur = {}, {}, r.base.avgDuration > 0 and r.base.avgDuration or 1
  for _, by in ipairs({ r.base.bySpell, r.res.bySpell }) do
    for k in pairs(by) do
      if not seen[k] then
        seen[k] = true
        local d = ((r.res.bySpell[k] and r.res.bySpell[k].dmg or 0) - (r.base.bySpell[k] and r.base.bySpell[k].dmg or 0)) / dur
        if math.abs(d) >= 0.05 then list[#list + 1] = { key = k, d = d } end
      end
    end
  end
  table.sort(list, function(a, b) return math.abs(a.d) > math.abs(b.d) end)
  local rows, top = {}, list[1] and math.abs(list[1].d) or 1
  for i = 1, math.min(#list, ROWS) do
    local name, icon = rowInfo(list[i].key, r.build)
    local d = list[i].d
    rows[i] = { label = name, share = math.abs(d) / top, right = signed(d, 1), icon = spellIcon(icon), color = d >= 0 and { 0.25, 0.75, 0.3, 0.6 } or { 0.85, 0.3, 0.3, 0.6 },
      tip = string.format('%s\n%s DPS from this spell with the change', name, signed(d, 1)) }
  end
  setRows(rows)
  local lines, only, amount = {}, nil, 0
  for k, v in pairs(r.delta) do if v ~= 0 then if only then only = false else only, amount = k, v end end end
  if only then lines[#lines + 1] = string.format('|cffffd100That is %s DPS for each %s.|r', signed(r.diff / amount, 2), WL.describeStats({ [only] = 1 })) end
  lines[#lines + 1] = string.format('|cffaaaaaaBoth sides play the same %d fights, so the change is measured to within the +-. More fights (Fight tab) make the +- smaller.|r', r.res.iterations)
  for i = 1, #(r.notes or {}) do lines[#lines + 1] = '|cffffb060' .. r.notes[i] .. '|r' end
  result.info:SetText(table.concat(lines, '\n'))
end

function WL.showResult(r)
  current = r
  if not r then
    result.head:SetText('No result yet')
    result.sub:SetText('Read your character, then press Sim!')
    setRows({}); result.info:SetText('')
  elseif r.kind == 'rank' then showRank(r)
  elseif r.kind == 'whatif' then showWhatIf(r)
  else showSingle(r.res, r.build, r.race, r.weights, r.notes, r.back ~= nil) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- tab pages
-- ---------------------------------------------------------------------------------------------------------------------
local PET_NAMES = { imp = 'Imp', succubus = 'Succubus', felhunter = 'Felhunter', voidwalker = 'Voidwalker' }
local function startSim(fn)
  if WL.jobRunning() then return end
  hideMenu()
  local ok, err = fn()
  if ok == false and err then result.status:SetText('|cffff6060' .. err .. '|r') end
  WL.refresh()
end

local function buildCharacterPage(p)
  p.who = Text(p, 'GameFontNormal'); p.who:SetPoint('TOPLEFT', 0, 0); p.who:SetWidth(W - 2 * PAD)
  p.stats = Text(p, 'GameFontHighlightSmall'); p.stats:SetPoint('TOPLEFT', 0, -18); p.stats:SetWidth(W - 2 * PAD)
  if p.stats.SetSpacing then p.stats:SetSpacing(3) end
  local y = -74
  local function row(label, widget)
    local t = Text(p, 'GameFontNormalSmall', label); t:SetPoint('TOPLEFT', 0, y - 4)
    widget:SetPoint('TOPLEFT', 86, y)
    y = y - 23
    return widget
  end
  row('Play it like', keep(Dropdown(p, 300, function()
    local items, list = {}, WL.templates()
    for i = 1, #list do items[i] = { value = list[i].key, label = (list[i].short or list[i].key) .. (list[i].imported and ' (imported)' or '') } end
    return items
  end, function()
    if WL.findTemplate(WL.db.options.template) then return WL.db.options.template end
    return WL.char and WL.bestTemplate(WL.char.talents, WL.templates(), WL.char.pet) or WL.BUILDS[1].key
  end, function(v) WL.db.options.template = v end,
    'Your talents and demon come from your character. The order in which spells are cast (the priority list) is taken from this build. The closest ready build is picked for you; a build code from the website can be loaded on the Codes tab.')))
  local function demonItems(auto, extra)
    local items = { { value = 'auto', label = auto } }
    local keys = { 'imp', 'succubus', 'felhunter', 'voidwalker' }
    for i = 1, 4 do items[#items + 1] = { value = keys[i], label = PET_NAMES[keys[i]] } end
    items[#items + 1] = { value = 'none', label = extra }
    return items
  end
  row('Demon out', keep(Dropdown(p, 180, function()
    return demonItems('As read: ' .. ((WL.char and WL.char.pet and PET_NAMES[WL.char.pet]) or 'none'), 'None')
  end, function() return WL.db.options.pet end, function(v) WL.db.options.pet = v end, 'The demon that fights with you in the sim.')))
  row('Sacrificed', keep(Dropdown(p, 180, function()
    return demonItems('As read: ' .. ((WL.char and WL.char.sacrifice and PET_NAMES[WL.char.sacrifice]) or 'none'), 'None')
  end, function() return WL.db.options.sacrifice end, function(v) WL.db.options.sacrifice = v end,
    'The demon given up with Demonic Sacrifice before the fight. Read from the buff on you; pick it here if the addon did not find it.')))
  row('Weapon stone', keep(Dropdown(p, 240, function()
    return { { value = 'sheet', label = 'Already in my numbers (or none)' }, { value = 'spellstone', label = 'Add a Major Spellstone' }, { value = 'firestone', label = 'Add a Major Firestone' } }
  end, function() return WL.db.options.stone end, function(v) WL.db.options.stone = v end,
    'If a Spellstone or Firestone was active while your character was read, its bonus is inside your numbers already: leave this on the first choice. Pick a stone here only if you read your character without one.')))
  p.notes = Text(p, 'GameFontDisableSmall'); p.notes:SetPoint('TOPLEFT', 0, y - 4); p.notes:SetWidth(W - 2 * PAD); p.notes:SetHeight(58)
  if p.notes.SetWordWrap then p.notes:SetWordWrap(true) end
  p.read = Button(p, 'Read my character', 150, function()
    local ch, err = WL.doReadCharacter()
    result.status:SetText(ch and '|cff80ff80Character read.|r' or ('|cffff6060' .. tostring(err) .. '|r'))
    WL.refresh()
  end, 'Takes your talents, race, demon and the spell numbers from your character sheet as they are right now. Raid buffs the addon recognises on you are taken off again, so that the Buffs tab decides which buffs the sim uses. Not possible in combat.')
  p.read:SetPoint('BOTTOMLEFT', 0, 0)
  local sheet = keep(Check(p, 'Sheet numbers', function() return WL.db.options.sheetNumbers ~= false end, function(v) WL.db.options.sheetNumbers = v end,
    'Shows numbers on your character sheet: over every item you wear, the DPS that item is worth to you (your character as it is against the same character with that slot empty), and over your character the DPS it sims at.\n\nThey are worked out in the background when you open the character sheet, one item after the other, and again when your items, talents or the sim\'s settings change. A sim you start yourself always goes first.'))
  sheet:SetPoint('BOTTOMLEFT', 158, 0)
  local helper = keep(Check(p, 'Helper', function() return WL.db.options.helper == true end, function(v) WL.helper.toggle(v) end,
    "A small bar on raid bosses: the spell the sim would cast next with your character, the two after it, cooldowns and mana items to use with it, and the seconds until the boss dies. The sim's own priority list decides, with the time left worked out from how fast the boss loses health.\n\nOnly if your talents fit one of the sim's builds (the one under \"Play it like\"), and only on raid bosses. /wsim helper move places the bar.\n\nIt reads the boss's health, your mana, your buffs and the boss's debuffs from the game. Should the game ever hide one of them from addons, the helper follows your own casts instead; without the boss's health the time to kill is the fight length on the Fight tab, shown in grey."))
  helper:SetPoint('BOTTOMLEFT', 252, 0)
  p.sim = Button(p, 'Sim!', 72, function() startSim(WL.simCharacter) end, 'Plays the fights with your character and shows your DPS, the share of each spell and (if switched on) what each stat is worth.')
  p.sim:SetPoint('BOTTOMRIGHT', 0, 0)

  p.sync = function()
    local ch = WL.char
    if not ch then
      p.who:SetText('No character read yet')
      p.stats:SetText('Press "Read my character" (out of combat). The sim then uses your talents, your race,\nyour demon and the numbers on your character sheet.')
      p.notes:SetText('')
      if p.sim.SetEnabled then p.sim:SetEnabled(false) end
      return
    end
    if p.sim.SetEnabled then p.sim:SetEnabled(not WL.jobRunning()) end
    local split, points = WL.talentSplit(ch.talents)
    local race = WL.RACES[ch.raceKey] and WL.RACES[ch.raceKey].name or '?'
    p.who:SetText(string.format('%s - %s - level %s - %s', tostring(ch.name), race, tostring(ch.level or '?'), split))
    local s, g = ch.sheet, ch.gear
    local school = ''
    if (g.shadowSp or 0) > 0 then school = school .. ' +' .. fmt(g.shadowSp) .. ' Shadow' end
    if (g.fireSp or 0) > 0 then school = school .. ' +' .. fmt(g.fireSp) .. ' Fire' end
    p.stats:SetText(string.format(
      '|cffffd100On your sheet:|r  Spell power %s%s   Hit %s   Crit %s   Haste %s\nInt %s   Spirit %s   Stamina %s   Mana per 5 s %s   Spell Pierce %s\n|cffffd100Counted as gear:|r  SP %s   hit %s   crit %s   Int %s   Spi %s   Sta %s',
      fmt(s.sp), school, pctText(floor((s.hit or 0) * 10 + 0.5) / 10), pctText(floor((s.crit or 0) * 10 + 0.5) / 10), pctText(floor((s.haste or 0) * 10 + 0.5) / 10),
      fmt(s.int), fmt(s.spi), fmt(s.sta), fmt(s.mp5), fmt(s.pierce),
      fmt(g.sp), pctText(floor(g.hitPct * 10 + 0.5) / 10), pctText(floor(g.critPct * 10 + 0.5) / 10), fmt(g.int), fmt(g.spi), fmt(g.sta)))
    local notes = {}
    if ch.restored then notes[#notes + 1] = '|cffaaaaaaAs read ' .. ((ch.readAt or 0) > 0 and ('on ' .. date('%d %b, %H:%M', ch.readAt)) or 'before') .. ' (kept over the reload). Read again if your items or talents changed since.|r' end
    if ch.level and ch.level < 60 then notes[#notes + 1] = string.format('|cffffb060Level %d: the sim plays your numbers as a level 60 Warlock (level 60 spells, a level 63 boss), so the DPS is what that would do, not what you do now. Item and stat comparisons still give a rough idea; hit counts for more here than against enemies of your own level.|r', ch.level) end
    if points ~= 51 and (ch.level or 60) >= 60 then notes[#notes + 1] = string.format('|cffffb060%d talent points found (51 expected).|r', points) end
    for i = 1, #ch.notes do notes[#notes + 1] = '|cffffb060' .. ch.notes[i] .. '|r' end
    local on = {}
    for k in pairs(ch.buffsOnYou or {}) do on[#on + 1] = WL.DEFAULT_CONFIG.buffs[k].name end
    table.sort(on)
    if #on > 0 then notes[#notes + 1] = 'Taken off your numbers (the Buffs tab decides): ' .. table.concat(on, ', ') .. '.' end
    if #(ch.otherAuras or {}) > 0 then notes[#notes + 1] = 'Also on you; if they give stats, they count as gear: ' .. table.concat(ch.otherAuras, ', ') .. '.' end
    if ch.weaponEffect then notes[#notes + 1] = 'Your weapon has a temporary effect (stone or oil): its bonus is in your numbers.' end
    local fx = WL.wornEffectNames(ch.worn)
    if #fx > 0 then notes[#notes + 1] = 'What these do counts in the fight: ' .. table.concat(fx, ', ') .. ' (trinkets: see "Trinkets" on the Fight tab).' end
    p.notes:SetText(table.concat(notes, ' '))
  end
end

-- "What if": your character with a few stats more (or less), against your character as it is
local WHATIF_BOXES = { { 'sp', 'Spell power' }, { 'hit', 'Hit %' }, { 'crit', 'Crit %' }, { 'haste', 'Haste %' }, { 'int', 'Intellect' }, { 'spi', 'Spirit' },
                       { 'sta', 'Stamina' }, { 'pierce', 'Spell Pierce' }, { 'mp5', 'Mana per 5' } }
local WHATIF_QUICK = { { '+10 SP', 'sp', 10 }, { '+1% hit', 'hit', 1 }, { '+1% crit', 'crit', 1 }, { '+1% haste', 'haste', 1 }, { '+20 Int', 'int', 20 } }
local function buildWhatIfPage(p)
  local change = {}
  local t = Text(p, 'GameFontHighlightSmall', 'What if your character had a little more (or less) of a stat? Both sides play the same fights, so even a small change shows.')
  t:SetPoint('TOPLEFT', 0, 0); t:SetWidth(W - 2 * PAD)
  local boxes = {}
  local function simChange()
    for i = 1, #boxes do                                  -- what is typed counts, even if the box still has the cursor
      local v = tonumber(((boxes[i]:GetText() or ''):gsub(',', '.')))
      change[WHATIF_BOXES[i][1]] = v or 0
    end
    startSim(function() return WL.simWhatIf(copy(change)) end)
  end
  local bw = (W - 2 * PAD - 4 * 6) / #WHATIF_QUICK
  for i = 1, #WHATIF_QUICK do
    local q = WHATIF_QUICK[i]
    local b = Button(p, q[1], bw, function()
      for k in pairs(change) do change[k] = 0 end
      change[q[2]] = q[3]
      for j = 1, #boxes do boxes[j]:ClearFocus(); boxes[j].sync() end
      simChange()
    end, 'Sims your character as it is and with ' .. WL.describeStats({ [q[2]] = q[3] }, true) .. ', and shows the difference.')
    b:SetPoint('TOPLEFT', (i - 1) * (bw + 6), -34)
  end
  local h = Text(p, 'GameFontNormalSmall', 'Or your own change (a minus for less):'); h:SetPoint('TOPLEFT', 0, -66)
  for i = 1, #WHATIF_BOXES do
    local key, x, y = WHATIF_BOXES[i][1], ((i - 1) % 3) * 136, -84 - math.floor((i - 1) / 3) * 24
    local l = Text(p, 'GameFontNormalSmall', WHATIF_BOXES[i][2]); l:SetPoint('TOPLEFT', x, y - 4)
    local e = Edit(p, 46, function() return change[key] or 0 end, function(v) change[key] = v end)
    e:SetPoint('TOPLEFT', x + 76, y)
    boxes[i] = keep(e)
  end
  local n = Text(p, 'GameFontDisableSmall', 'Hit, crit and haste are in percent. Intellect also adds crit, by the sim\'s rule. The number of fights is the one on the Fight tab.')
  n:SetPoint('TOPLEFT', 0, -162); n:SetWidth(W - 2 * PAD)
  p.go = Button(p, 'Sim this change', 130, simChange, 'Sims your character as it is and with the change above, and shows the difference in DPS and where it comes from.')
  p.go:SetPoint('BOTTOMRIGHT', 0, 0)
  local clear = Button(p, 'Clear', 80, function()
    for k in pairs(change) do change[k] = 0 end
    for j = 1, #boxes do boxes[j]:ClearFocus(); boxes[j].sync() end
  end, 'Sets every box back to 0.')
  clear:SetPoint('BOTTOMLEFT', 0, 0)
  p.sync = function() if p.go.SetEnabled then p.go:SetEnabled(WL.char ~= nil and not WL.jobRunning()) end end
end

local function buildBuildsPage(p)
  local t = Text(p, 'GameFontHighlightSmall', 'Plays every build of the sim (and builds you loaded on the Codes tab) with the gear numbers of your character and puts them in order, so you see which build is best for your gear. Your own character, with the talents you have now, is in the list in gold.')
  t:SetPoint('TOPLEFT', 0, 0); t:SetWidth(W - 2 * PAD)
  local lab = Text(p, 'GameFontNormalSmall', 'Race'); lab:SetPoint('TOPLEFT', 0, -62)
  p.race = keep(Dropdown(p, 180, function()
    local items = {}
    if WL.char then return { { value = WL.char.raceKey, label = (WL.RACES[WL.char.raceKey] and WL.RACES[WL.char.raceKey].name or '?') .. ' (your character)' } } end
    for i = 1, #WL.RACE_KEYS do items[i] = { value = WL.RACE_KEYS[i], label = WL.RACES[WL.RACE_KEYS[i]].name } end
    return items
  end, function() return WL.raceKey() end, function(v) if not WL.char then WL.db.options.race = v end end, 'Without a character read, the builds are played as this race, with the gear numbers of the sim\'s settings (or of a settings code you loaded).'))
  p.race:SetPoint('TOPLEFT', 86, -58)
  p.gear = Text(p, 'GameFontDisableSmall'); p.gear:SetPoint('TOPLEFT', 0, -88); p.gear:SetWidth(W - 2 * PAD)
  p.rank = Button(p, 'Sim builds with your gear', 200, function() startSim(WL.simRanking) end, 'Reads your character again (out of combat), then plays every build of the sim with your gear numbers: one sim per build, and one for your own character, in a row. Fewer fights (Fight tab) make it quicker and less exact.')
  p.rank:SetPoint('BOTTOMLEFT', 0, 0)
  p.sync = function()
    local g = WL.characterConfig().gear
    p.gear:SetText(string.format('Gear numbers used: %s spell power, %s hit, %s crit, %s haste, Int %s, Spirit %s, Stamina %s%s', fmt(g.sp), pctText(floor(g.hitPct * 10 + 0.5) / 10),
      pctText(floor(g.critPct * 10 + 0.5) / 10), pctText(floor(g.hastePct * 10 + 0.5) / 10), fmt(g.int), fmt(g.spi), fmt(g.sta), WL.char and ' (from your character).' or ' (the sim\'s settings - read your character to use your own).'))
    if p.rank.SetEnabled then p.rank:SetEnabled(not WL.jobRunning()) end
  end
end

local function buildFightPage(p)
  local y = 0
  local function label(text, x) local t = Text(p, 'GameFontNormalSmall', text); t:SetPoint('TOPLEFT', x, y - 4); return t end
  local function place(w, x) w:SetPoint('TOPLEFT', x, y); return w end
  local f, o = function() return WL.cfg.fight end, function() return WL.db.options end
  label('Fights', 0)
  place(keep(Edit(p, 50, function() return o().fights end, function(v) o().fights = math.max(10, math.min(20000, floor(v))) end,
    'How many fights are played and averaged - with "Stop early" on, the most that are played. More fights = a steadier number and a longer wait. 300 is good for a quick look, 1000 and more to compare close builds.')), 92)
  label('Fight length (s)', 190)
  place(keep(Edit(p, 50, function() return f().duration end, function(v) f().duration = math.max(10, math.min(1800, v)) end, 'Each fight lasts this long, give or take 10%.')), 300)
  y = y - 26
  label('Targets', 0)
  place(keep(Dropdown(p, 60, function() return { { value = 1, label = '1' }, { value = 2, label = '2' }, { value = 3, label = '3' } } end,
    function() return f().targets end, function(v) f().targets = v end, 'With 2 or 3 targets, Bane of Havoc (if talented) copies damage to the second one.')), 92)
  place(keep(Check(p, 'Keep DoTs on all targets', function() return f().multiDot end, function(v) f().multiDot = v end, 'With 2 or 3 targets: your DoTs and curse are kept up on the extra targets too.')), 186)
  y = y - 26
  label('Pop cooldowns', 0)
  place(keep(Dropdown(p, 200, function()
    return { { value = 'pull', label = 'At the pull' }, { value = 'doom', label = 'When Bane of Doom explodes' }, { value = 'execute', label = 'In the execute phase' } }
  end, function()
    local v = WL.cfg.options.activesPolicy
    return (v == 'pull' or v == 'doom' or v == 'execute') and v or 'doom'
  end, function(v) WL.cfg.options.activesPolicy = v end, 'When the racial cooldown, the Spellblasting potion and Power Infusion are used for the first time. Afterwards each is used again whenever it is ready.')), 92)
  y = y - 26
  label('Precast', 0)
  place(keep(Dropdown(p, 120, function()
    local items = { { value = '', label = 'Nothing' } }
    for i = 1, #WL.PRECAST_SPELLS do items[#items + 1] = { value = WL.PRECAST_SPELLS[i], label = WL.SPELLS[WL.PRECAST_SPELLS[i]].name } end
    return items
  end, function() return f().precast or '' end, function(v) f().precast = v end, 'A spell you start before the pull so that it finishes as the fight starts.')), 92)
  label('Trinkets', 222)
  place(keep(Dropdown(p, 130, function()
    return { { value = 'cds', label = 'With cooldowns' }, { value = 'ready', label = 'When ready' }, { value = 'execute', label = 'Execute phase' }, { value = 'never', label = 'Never' } }
  end, function()
    local tu = WL.cfg.options.trinketUse or {}
    return tu.trinket1 or 'cds'
  end, function(v) WL.cfg.options.trinketUse = { trinket1 = v, trinket2 = v } end,
    'When the trinkets you wear are used, if the sim knows what they do (Talisman of Ephemeral Power, Zandalarian Hero Charm, The Black Book and more). "With cooldowns": together with your racial and Power Infusion ("Pop cooldowns"). "When ready": from the pull on, again whenever ready. "Execute phase": only once the boss is low. "Never": not at all.\n\nA mana trinket is used when its mana is missing. A trinket\'s plain stats always count, and so does what your main-hand enchant does (Revelation, Grand Sorcerer, Grand Arcanist, Insight).')), 276)
  y = y - 26
  place(keep(Check(p, 'Keep Curse of the Elements up', function() return WL.cfg.options.useCurseOfElements end, function(v) WL.cfg.options.useCurseOfElements = v end)), -2)
  place(keep(Check(p, 'Stat weights', function() return o().weights end, function(v) o().weights = v end,
    'Also works out what hit, crit, haste, Intellect and Spell Pierce are worth in spell power for this build. Needs six more runs on the same fights; each stops as soon as its weight is exact enough.')), 216)
  place(keep(Check(p, 'Stop early', function() return o().stopEarly ~= false end, function(v) o().stopEarly = v end,
    'Stops a sim as soon as its result is exact enough, instead of always playing every fight: the number of fights set becomes the most that are played (never fewer than 40).\n\nA DPS stops when its +- is 0.5% of it. A comparison (an item, What if, a stat weight, the numbers on the character sheet) plays the same fights on both sides and stops when the +- of the difference is 0.5 DPS or a tenth of the difference - often after a few dozen fights.\n\nOff: every sim plays exactly the number of fights set.')), 318)
  y = y - 26
  label('Move every', 0)
  place(keep(Edit(p, 36, function() return f().moveEvery end, function(v) f().moveEvery = math.max(0, v) end, 'Every this many seconds you have to move (0 = never). Only instants can be cast while moving.')), 92)
  label('s for', 136)
  place(keep(Edit(p, 36, function() return f().moveDuration end, function(v) f().moveDuration = math.max(0, v) end, 'How long each movement lasts, in seconds.')), 176)
  label('s      Hit taken every', 218)
  place(keep(Edit(p, 36, function() return f().hitEvery end, function(v) f().hitEvery = math.max(0, v) end, 'You take a hit every this many seconds (0 = never): casts are pushed back.')), 346)
  y = y - 26
  label('Latency (ms)', 0)
  place(keep(Edit(p, 50, function() return f().latencyMs end, function(v) f().latencyMs = math.max(0, math.min(2000, v)) end, 'Your reaction delay after each cast.')), 92)
  label('While simming', 190)
  place(keep(Dropdown(p, 110, function() return { { value = 'auto', label = 'Automatic' }, { value = 'smooth', label = 'Stay smooth' }, { value = 'fast', label = 'Sim faster' }, { value = 'fastest', label = 'Fastest' } } end,
    function() return o().speed end, function(v) o().speed = v end, 'The game gives addons one processor core, shared with the game itself. "Automatic" sims faster while you are out of combat and stays smooth while you fight. "Stay smooth" sims for 8 ms of every frame: the game runs nearly as usual. "Sim faster" takes 30 ms: about twice as quick, the game stutters a little. "Fastest" takes 100 ms: the sim gets nearly the whole core, the game drops to about 10 frames a second until it is done.')), 284)
  y = y - 26
  label('Item sims', 0)
  place(keep(Edit(p, 50, function() return o().itemFights end, function(v) o().itemFights = math.max(20, math.min(2000, floor(v))) end,
    'How many fights an item sim plays (the click on an item, and the numbers on your character sheet). More fights = smaller differences show reliably, and a longer wait. 150 is a quick look; 500 and more to tell close items apart.')), 92)
  label('fights', 148)
  place(keep(Check(p, 'Minimap button', function() return o().minimapButton ~= false end, function(v) o().minimapButton = v; WL.updateMinimapButton() end,
    'The round button at the edge of the minimap: click opens or closes this window, right-click sims your character, drag moves it. /wsim minimap does the same as this box.')), 214)
  p.reset = Button(p, 'Back to the sim\'s settings', 190, function()
    WL.cfg = WL.newConfig(); WL.saveSettings(); WL.refresh()
    result.status:SetText('Fight, buffs and consumables are back to the sim\'s defaults.')
  end, 'Puts everything on the Fight and Buffs tabs back to what the website starts with. Your character stays as read.')
  p.reset:SetPoint('BOTTOMLEFT', 0, 0)
  local il = Text(p, 'GameFontNormalSmall', 'Sim an item with'); il:SetPoint('BOTTOMLEFT', 198, 5)
  local ic = keep(Dropdown(p, 122, function() return WL.ITEM_CLICKS end, function() return o().itemClick end, function(v) o().itemClick = v end,
    'This click on an item - in your bags, on your character sheet, at a vendor, in a loot window - opens a small panel and sims your character with that item in place of the one you wear in its slot. An item you are wearing is simmed against an empty slot: what it is worth to you.\n\nPick another click if this one is taken by another addon or gets in your way; the game may also do what it usually does for that click. "Off" also hides the button under item links from chat.'))
  ic:SetPoint('BOTTOMLEFT', 284, 1)
end

local COUNT_WHO = { innervate = 'Druids', powerInfusion = 'Priests' }
local function buildBuffsPage(p)
  local scroll = CreateFrame('ScrollFrame', 'WarlockSimBuffScroll', p, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', 0, -26); scroll:SetPoint('BOTTOMRIGHT', -24, 0)
  local child = CreateFrame('Frame', nil, scroll)
  child:SetSize(W - 2 * PAD - 28, 10)
  scroll:SetScrollChild(child)
  local y, checks = 0, {}
  local function header(text)
    local t = Text(child, 'GameFontNormal', text); t:SetPoint('TOPLEFT', 0, y - 4)
    y = y - 22
  end
  local function item(tbl, key, others)
    local e = WL.DEFAULT_CONFIG[tbl][key]
    local cb = Check(child, e.name, function() return WL.cfg[tbl][key] and WL.cfg[tbl][key].on end, function(v)
      WL.cfg[tbl][key].on = v
      if v then others(key) end
    end, e.name .. '\n' .. (e.desc or ''))
    cb:SetPoint('TOPLEFT', 0, y)
    cb.label:SetWidth(W - 2 * PAD - (e.count ~= nil and 100 or 60))
    if cb.label.SetWordWrap then cb.label:SetWordWrap(false) end
    checks[#checks + 1] = cb
    if e.count ~= nil then                                     -- Innervate / Power Infusion: how many Druids / Priests
      local most = e.maxCount or 5
      local who = COUNT_WHO[key] or 'players'
      local n = Edit(child, 28, function() return WL.cfg[tbl][key].count or 1 end, function(v)
        WL.cfg[tbl][key].count = math.max(1, math.min(most, math.floor(v + 0.5)))
      end, 'How many ' .. who .. ' give you theirs (1 to ' .. most .. '). The next one comes when the last one is over.')
      n:SetPoint('TOPRIGHT', child, 'TOPRIGHT', -6, y - 1)
      local x = Text(child, 'GameFontHighlightSmall', 'how many')
      x:SetPoint('RIGHT', n, 'LEFT', -8, 0)
      checks[#checks + 1] = n
    end
    y = y - 20
  end
  header('Raid buffs')
  for i = 1, #WL.BUFF_ORDER do
    item('buffs', WL.BUFF_ORDER[i], function(key)
      for k, b in pairs(WL.cfg.buffs) do if k ~= key and b.on and WL.buffsClash(WL.cfg.buffs[key], b) then b.on = false end end
    end)
  end
  header('On the boss')
  for i = 1, #WL.DEBUFF_ORDER do
    item('debuffs', WL.DEBUFF_ORDER[i], function(key)
      local g = WL.cfg.debuffs[key].group
      if g then for k, d in pairs(WL.cfg.debuffs) do if k ~= key and d.group == g then d.on = false end end end
    end)
  end
  header('Consumables')
  for i = 1, #WL.CONSUMABLE_ORDER do
    item('consumables', WL.CONSUMABLE_ORDER[i], function(key)
      local c = WL.cfg.consumables[key]
      for k, x in pairs(WL.cfg.consumables) do if k ~= key and x.group == c.group then x.on = false end end
      if c.requires and WL.cfg.professions then WL.cfg.professions[c.requires] = true end
    end)
  end
  child:SetHeight(-y + 8)
  local none = Button(p, 'Nothing', 90, function()
    for _, b in pairs(WL.cfg.buffs) do b.on = false end
    for _, d in pairs(WL.cfg.debuffs) do d.on = false end
    for k, c in pairs(WL.cfg.consumables) do c.on = k == 'buildOil' end
    WL.refresh()
  end, 'Switches every buff, boss debuff and consumable off (the weapon stone setting stays).')
  none:SetPoint('TOPLEFT', 0, 0)
  local def = Button(p, 'The sim\'s defaults', 140, function()
    local d = WL.DEFAULT_CONFIG
    for k, b in pairs(WL.cfg.buffs) do b.on = d.buffs[k].on; b.count = d.buffs[k].count end
    for k, x in pairs(WL.cfg.debuffs) do x.on = d.debuffs[k].on end
    for k, c in pairs(WL.cfg.consumables) do c.on = d.consumables[k].on end
    WL.refresh()
  end, 'The raid buffs and boss debuffs the website starts with.')
  def:SetPoint('LEFT', none, 'RIGHT', 6, 0)
  p.sync = function() for i = 1, #checks do checks[i].sync() end end
end

local function buildCodesPage(p)
  local t = Text(p, 'GameFontHighlightSmall', 'Paste a settings or build code from the website here, or make one - or a gear code of what you wear - to take there. Ctrl+V pastes, Ctrl+C copies.')
  t:SetPoint('TOPLEFT', 0, 0); t:SetWidth(W - 2 * PAD)
  local scroll = CreateFrame('ScrollFrame', 'WarlockSimCodeScroll', p, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', 2, -34); scroll:SetPoint('BOTTOMRIGHT', -26, 54)
  local bg = scroll:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
  local box = CreateFrame('EditBox', nil, scroll)
  box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  box:SetWidth(W - 2 * PAD - 32)
  box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
  scroll:SetScrollChild(box)
  scroll:SetScript('OnMouseDown', function() box:SetFocus() end)
  p.box = box
  local function say(msg, bad) result.status:SetText((bad and '|cffff6060' or '|cff80ff80') .. msg .. '|r') end
  local function show(code) box:SetText(code); box:SetFocus(); box:HighlightText() end
  local load = Button(p, 'Load the code', 120, function()
    local code = (box:GetText() or ''):gsub('%s+', '')
    if code:sub(1, #WL.SETTINGS_CODE_PREFIX) == WL.SETTINGS_CODE_PREFIX then
      local o, err = WL.decodeSettings(code)
      if not o then say(err, true); return end
      local c = WL.newConfig()
      local unknown = WL.applySettings(c, o)
      WL.cfg = c; WL.saveSettings()
      say('Settings loaded' .. (#unknown > 0 and (' (not known here: ' .. table.concat(unknown, ', ') .. ')') or '') .. (WL.char and '. Your character\'s own gear numbers still win: the code\'s gear is used when no character is read.' or '.'))
    elseif code:sub(1, #WL.BUILD_CODE_PREFIX) == WL.BUILD_CODE_PREFIX then
      local b, err, known = WL.addImportedBuild(code)
      if not b then say(err, true); return end
      local errs = WL.validateBuild(b)
      WL.db.options.template = b.key
      say('Build "' .. b.short .. '" ' .. (known and 'was loaded before' or 'loaded') .. ': it is in the ranking and can be picked under "Play it like".' .. (b.migrated and (' ' .. table.concat(b.migrated, '. ') .. '.') or '') .. (#errs > 0 and (' Note: ' .. errs[1]) or ''), #errs > 0)
    elseif code:sub(1, #WL.GEAR_CODE_PREFIX) == WL.GEAR_CODE_PREFIX then say('That is a gear code: it is for the website\'s gear builder. The addon reads your gear from the game itself.', true)
    elseif code:find('share=', 1, true) then say('That is a share link. The addon reads settings codes and build codes: on the website use "Make settings code" or "Make build code".', true)
    else say('That is neither a settings code (WFS1:) nor a build code (WFB1:).', true) end
    WL.refresh()
  end, 'Reads the code in the box. A settings code replaces the Fight and Buffs settings (and the gear numbers used when no character is read). A build code adds a build with its priority list.')
  load:SetPoint('BOTTOMLEFT', 0, 26)
  local s = Button(p, 'My settings as a code', 150, function()
    show(WL.encodeSettings(WL.characterConfig()))
    say('Settings code made' .. (WL.char and ' (with your character\'s gear numbers)' or '') .. '. Copy it with Ctrl+C and paste it on the website under "Input / output".')
  end, 'Makes a settings code of everything set here, with your character\'s gear numbers if one is read. The website opens it under "Input / output".')
  s:SetPoint('LEFT', load, 'RIGHT', 6, 0)
  local g = Button(p, 'My gear as a code', 124, function()
    local code, items, enchants, notes, bags = WL.gearCode()
    if not code then say(items, true); return end
    show(code)
    say(string.format('Gear code made: %d items, %d enchants%s. Copy it with Ctrl+C and paste it on the website in the gear builder.%s', items, enchants,
      WL.db.options.gearBags and string.format(', %d from your bags', bags) or '', #notes > 0 and (' ' .. table.concat(notes, ' ')) or ''), #notes > 0)
  end, 'Makes a gear code of everything you wear: each item with its name, game id, item level, icon and stats, and the enchants (by their text). The website\'s gear builder loads it, so you can look at your own gear there, and it learns items it does not know yet.\n\n"Use:" and "Chance on hit:" effects are not in it; an enchant whose text the addon cannot read is counted as 0 and named.')
  g:SetPoint('LEFT', s, 'RIGHT', 6, 0)
  local b = Button(p, 'My character as a build code', 190, function()
    local build, notes = WL.characterBuildNow()
    if not build then say(notes[1], true); return end
    show(WL.encodeBuild(build))
    local _, points = WL.talentSplit(build.talents)
    say('Build code made. ' .. (points ~= 51 and 'The website only takes builds with exactly 51 talent points (yours has ' .. points .. ').' or 'Paste it on the website under "Input / output".'), points ~= 51)
  end, 'Your talents, demon and priority list as a build code for the website.')
  b:SetPoint('BOTTOMLEFT', 0, 0)
  local forget = Button(p, 'Forget loaded builds', 136, function()
    WL.db.builds = {}; WL.imported = {}
    if not WL.findTemplate(WL.db.options.template) then WL.db.options.template = nil end
    say('Loaded builds removed.'); WL.refresh()
  end, 'Removes every build that was loaded from a build code.')
  forget:SetPoint('LEFT', b, 'RIGHT', 6, 0)
  local bagsBox = keep(Check(p, 'Bags too', function() return WL.db.options.gearBags end, function(v) WL.db.options.gearBags = v end,
    '"My gear as a code" also lists the items in your bags that you can wear, so you can send the website everything you have.'))
  bagsBox:SetPoint('LEFT', forget, 'RIGHT', 4, 0)
  p.bagsBox = bagsBox
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------------------------------------------------
local TAB_NAMES = { 'Character', 'What if', 'Builds', 'Buffs', 'Fight', 'Codes' }
local BUILDERS = { buildCharacterPage, buildWhatIfPage, buildBuildsPage, buildBuffsPage, buildFightPage, buildCodesPage }
local PAGE_H = 248

local function selectTab(i)
  hideMenu()
  WL.db.options.tab = i
  for k = 1, #tabs do
    pages[k]:SetShown(k == i)
    tabs[k].bg:SetColorTexture(0.58, 0.51, 0.79, k == i and 0.55 or 0.15)
  end
end

local function create()
  main = CreateFrame('Frame', 'WarlockSimFrame', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
  main:SetSize(W, H); main:SetFrameStrata('MEDIUM'); main:SetToplevel(true)
  main:SetClampedToScreen(true); main:SetMovable(true); main:EnableMouse(true)
  local pos = WL.db.pos
  if type(pos) == 'table' and pos[1] then main:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0) else main:SetPoint('CENTER', 80, 0) end
  if main.SetBackdrop then
    main:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    main:SetBackdropColor(0.05, 0.04, 0.08, 0.95); main:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
  else
    local bg = main:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.04, 0.08, 0.95)
  end
  local drag = CreateFrame('Frame', nil, main)
  drag:SetPoint('TOPLEFT', 0, 0); drag:SetPoint('TOPRIGHT', -30, 0); drag:SetHeight(28)
  drag:EnableMouse(true); drag:RegisterForDrag('LeftButton')
  drag:SetScript('OnDragStart', function() main:StartMoving() end)
  drag:SetScript('OnDragStop', function()
    main:StopMovingOrSizing()
    local a, _, b, x, y = main:GetPoint(1)
    WL.db.pos = { a, b, x, y }
  end)
  local title = Text(main, 'GameFontNormalLarge', "Xn's Warlock Sim"); title:SetPoint('TOPLEFT', PAD, -9)
  local ver = Text(main, 'GameFontDisableSmall', 'v' .. WL.VERSION .. '  -  /wsim'); ver:SetPoint('LEFT', title, 'RIGHT', 8, -1)
  local close = CreateFrame('Button', nil, main, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', 0, 0)
  close:SetScript('OnClick', function() main:Hide() end)
  main:SetScript('OnHide', hideMenu)

  local tabW = (W - 2 * PAD - 4 * (#TAB_NAMES - 1)) / #TAB_NAMES
  for i = 1, #TAB_NAMES do
    local tb = CreateFrame('Button', nil, main)
    tb:SetSize(tabW, 22); tb:SetPoint('TOPLEFT', PAD + (i - 1) * (tabW + 4), -32)
    tb.bg = tb:CreateTexture(nil, 'BACKGROUND'); tb.bg:SetAllPoints()
    local hl = tb:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    local t = Text(tb, 'GameFontNormalSmall', TAB_NAMES[i]); t:SetPoint('CENTER'); t:SetJustifyH('CENTER')
    tb:SetScript('OnClick', function() selectTab(i) end)
    tabs[i] = tb
    local page = CreateFrame('Frame', nil, main)
    page:SetPoint('TOPLEFT', PAD, -62); page:SetSize(W - 2 * PAD, PAGE_H)
    pages[i] = page
    BUILDERS[i](page)
    if page.sync then keep(page) end
  end

  local line = main:CreateTexture(nil, 'ARTWORK'); line:SetColorTexture(0.58, 0.51, 0.79, 0.6)
  line:SetPoint('TOPLEFT', PAD, -62 - PAGE_H - 8); line:SetSize(W - 2 * PAD, 1)
  local top = -62 - PAGE_H - 16
  result.head = Text(main, 'GameFontNormalLarge'); result.head:SetPoint('TOPLEFT', PAD, top)
  result.subBtn = CreateFrame('Button', nil, main)
  result.subBtn:SetPoint('TOPLEFT', PAD, top - 20); result.subBtn:SetSize(W - 2 * PAD, 14)
  result.sub = Text(result.subBtn, 'GameFontHighlightSmall'); result.sub:SetAllPoints()
  result.subBtn:SetScript('OnClick', function() if current and current.back then WL.showResult(current.back) end end)
  result.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame('Button', nil, main)
    r:SetPoint('TOPLEFT', PAD, top - 38 - (i - 1) * 17); r:SetSize(W - 2 * PAD, 16)
    r.icon = r:CreateTexture(nil, 'ARTWORK'); r.icon:SetSize(14, 14); r.icon:SetPoint('LEFT', 0, 0)
    r.bar = CreateFrame('StatusBar', nil, r)
    r.bar:SetPoint('LEFT', 18, 0); r.bar:SetPoint('RIGHT', -52, 0); r.bar:SetHeight(14)
    r.bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.bar:SetStatusBarColor(0.58, 0.51, 0.79, 0.55)
    r.bar:SetMinMaxValues(0, 1)
    r.label = Text(r.bar, 'GameFontHighlightSmall'); r.label:SetPoint('LEFT', 4, 0); r.label:SetJustifyV('MIDDLE')
    r.right = Text(r, 'GameFontHighlightSmall'); r.right:SetPoint('RIGHT', 0, 0); r.right:SetJustifyH('RIGHT')
    tip(r, function(self) return self.tipText end)
    r:SetScript('OnClick', function(self) if self.onClick then self.onClick() end end)
    r:Hide()
    result.rows[i] = r
  end
  result.info = Text(main, 'GameFontHighlightSmall')
  result.info:SetPoint('TOPLEFT', PAD, top - 38 - ROWS * 17 - 4); result.info:SetWidth(W - 2 * PAD)
  result.info:SetHeight(74)
  if result.info.SetSpacing then result.info:SetSpacing(2) end

  result.progress = CreateFrame('StatusBar', nil, main)
  result.progress:SetPoint('BOTTOMLEFT', PAD, 28); result.progress:SetSize(W - 2 * PAD - 70, 16)
  result.progress:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); result.progress:SetStatusBarColor(0.3, 0.75, 0.35, 0.8)
  result.progress:SetMinMaxValues(0, 1)
  local pbg = result.progress:CreateTexture(nil, 'BACKGROUND'); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.5)
  result.progressText = Text(result.progress, 'GameFontHighlightSmall'); result.progressText:SetPoint('LEFT', 4, 0)
  result.stop = Button(main, 'Stop', 62, function() WL.cancelJob() end)
  result.stop:SetPoint('BOTTOMRIGHT', -PAD, 25)
  result.status = Text(main, 'GameFontHighlightSmall'); result.status:SetPoint('BOTTOMLEFT', PAD, 28); result.status:SetWidth(W - 2 * PAD)
  result.tip = Text(main, 'GameFontDisableSmall'); result.tip:SetPoint('BOTTOMLEFT', PAD, 9); result.tip:SetWidth(W - 2 * PAD)
  if result.tip.SetWordWrap then result.tip:SetWordWrap(false) end
  result.status:SetJustifyV('BOTTOM')

  main:SetScript('OnUpdate', function()
    local done, total, label, secs = WL.jobProgress()
    if not done then return end
    result.progress:SetValue(total > 0 and done / total or 0)
    local left = done > 0 and secs * (total - done) / done or nil
    result.progressText:SetText(string.format('%s: %d of %d fights%s', label, done, total, left and string.format(' - about %d s left', floor(left + 0.5)) or ''))
  end)
  selectTab(WL.db.options.tab or 1)
  WL.showResult(nil)
end

function WL.refresh()
  if not main then return end
  for i = 1, #syncers do if syncers[i].sync then syncers[i].sync() end end
  local running = WL.jobRunning()
  result.progress:SetShown(running); result.stop:SetShown(running); result.status:SetShown(not running)
  local click = WL.itemClickText()
  result.tip:SetText(click and ('|cff9482c9Tip:|r ' .. click .. ' any item to sim what it is worth.')
    or 'Item sims are switched off (Fight tab, "Sim an item with").')
  WL.saveSettings()
end
WL.onJobEnd = function(res, err)
  if res and res.kind == 'item' then
    if WL.onItemResult then WL.onItemResult(res) end
  elseif res then
    WL.lastResult = res
    if main then
      WL.showResult(res)
      if res.remembered then result.status:SetText('|cffaaaaaaNothing has changed since this was simmed: the result is the same.|r')
      else result.status:SetText(string.format('|cffaaaaaa%d fights in %s s (%s ms of sim time a fight).|r', res.fights, fmt(res.seconds, 1), fmt(res.fights > 0 and 1000 * res.cpuSeconds / res.fights or 0, 1))) end
    end
  else
    if WL.onItemResult then WL.onItemResult(nil, err) end
    if main then result.status:SetText('|cffff6060' .. tostring(err) .. '|r') end
  end
  WL.refresh()
end
-- a part of the result is ready (the DPS before the stat weights, the builds one by one): show it while the rest is simmed
WL.onJobPartial = function(res)
  WL.lastResult = res
  if main then WL.showResult(res) end
end
-- Opening the window reads your character (out of combat): one look at the game's numbers when it opens, nothing while
-- it stays open. In combat the character read last stays.
local function readOnOpen()
  if InCombatLockdown and InCombatLockdown() then return end
  WL.doReadCharacter()
end
function WL.toggleWindow()
  if not WL.db then return end
  if not main then create() elseif main:IsShown() then main:Hide(); return end
  readOnOpen()
  main:Show()
  WL.refresh()
end
-- Escape closes the window: its name goes on the game's list of windows that Escape closes (UISpecialFrames), the way
-- other addons' windows do it in this client (ItemRack's options window).
-- NOT RegisterGameMenuEscHandler (Blizzard's newer hand-in, tried in v0.6.1/0.6.2): it puts an entry made by the addon
-- into the game's own list of Escape handlers, which the game reads on every Escape - after that, the rest of the
-- game's Escape work counts as the addon's, and its protected steps (clearing your target) were blocked with
-- "WarlockSim has been blocked from an action only available to the Blizzard UI".
if type(UISpecialFrames) == 'table' then
  local listed = false
  for i = 1, #UISpecialFrames do if UISpecialFrames[i] == 'WarlockSimFrame' then listed = true end end
  if not listed then tinsert(UISpecialFrames, 'WarlockSimFrame') end
end

-- the key binding "Sim my character" and a right-click on the minimap button: the window opens and Sim! is pressed
-- (your character is read first if nothing was read yet and you are not fighting)
function WL.simFromKey()
  if not WL.db then return end
  if not main then create() end
  if not main:IsShown() then readOnOpen(); main:Show() end
  startSim(WL.simCharacter)
end
