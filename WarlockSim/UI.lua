-- The window: a side menu with seven pages (My DPS, What if, Items, Builds, Raid setup, Codes, Options), each page with
-- its own result, a bar at the bottom for messages, the progress of a sim and its Stop button. It can be dragged by its
-- title and made bigger or smaller at its bottom right corner (Xn, 2026-11-19: layout B, "resizable").
-- It is the addon's own frame: nothing is registered in Blizzard's settings and no Blizzard frame is touched.
local ADDON, WL = ...
if WL.notWarlock then return end   -- not a Warlock: nothing of the addon loads (Class.lua)

local W0, H0 = 660, 520                                   -- the size it opens with the first time
local MIN_W, MIN_H, MAX_W, MAX_H = 600, 470, 1200, 1000
local PAD, NAV, TOP, FOOT = 12, 118, 34, 50               -- outer gap, side menu width, title bar, bottom bar
local main
local pages, navButtons, views, foot = {}, {}, {}, {}
local floor = math.floor
local copy = WL.copy

local function fmt(x, d)
  if x == nil then return '?' end
  return string.format('%.' .. (d or 0) .. 'f', x)
end
local function pctText(x) return fmt(x, x == floor(x) and 0 or 1) .. '%' end
local function pct1(x) return pctText(floor((x or 0) * 10 + 0.5) / 10) end

-- ---------------------------------------------------------------------------------------------------------------------
-- small widget helpers
-- ---------------------------------------------------------------------------------------------------------------------
local function Text(parent, font, text)
  local fs = parent:CreateFontString(nil, 'ARTWORK', font or 'GameFontHighlightSmall')
  fs:SetJustifyH('LEFT'); fs:SetJustifyV('TOP')
  if text then fs:SetText(text) end
  return fs
end
-- a text that runs from x to the right edge of its parent (it follows the window's width)
local function Line(parent, font, x, y, right, text)
  local fs = Text(parent, font, text)
  fs:SetPoint('TOPLEFT', x, y); fs:SetPoint('TOPRIGHT', -(right or 0), y)
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
-- a button that shows and hides part of a page: [+] / [-] and its label
local function Fold(parent, label, isOpen, onToggle, tooltip)
  local b = CreateFrame('Button', nil, parent)
  b:SetHeight(18)
  b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetSize(14, 14); b.icon:SetPoint('LEFT', 0, 0)
  b.text = Text(b, 'GameFontNormal', label); b.text:SetPoint('LEFT', 18, 0); b.text:SetJustifyV('MIDDLE')
  local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
  b:SetScript('OnClick', function() onToggle(); if WL.refresh then WL.refresh() end end)
  b.sync = function()
    b.icon:SetTexture(isOpen() and 'Interface\\Buttons\\UI-MinusButton-Up' or 'Interface\\Buttons\\UI-PlusButton-Up')
  end
  if tooltip then tip(b, tooltip) end
  return b
end

local syncers = {}
local function keep(w) syncers[#syncers + 1] = w; return w end
local function say(msg, bad) if foot.status then foot.status:SetText((bad and '|cffff6060' or '|cff80ff80') .. msg .. '|r') end end

-- ---------------------------------------------------------------------------------------------------------------------
-- results: each of My DPS, What if and Builds has its own (a heading, a line under it, bars, notes)
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
  elseif bk:sub(1, 11) == 'trinket:set' then
    local sf = WL.SET_FX and WL.SET_FX[tonumber(bk:sub(12))]
    name = sf and (sf.name .. ' (set bonus)')
  elseif bk:sub(1, 8) == 'trinket:' then
    local tf = WL.TRINKET_FX and WL.TRINKET_FX[tonumber(bk:sub(9))]
    name = tf and tf.name
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

local function newView(parent, empty)
  local v = { rows = {}, fit = ROWS, empty = empty }
  local f = CreateFrame('Frame', nil, parent)
  v.frame = f
  v.head = Line(f, 'GameFontNormalLarge', 0, 0, 130)
  if v.head.SetWordWrap then v.head:SetWordWrap(false) end
  v.subBtn = CreateFrame('Button', nil, f)
  v.subBtn:SetPoint('TOPLEFT', 0, -20); v.subBtn:SetPoint('TOPRIGHT', 0, -20); v.subBtn:SetHeight(14)
  v.sub = Text(v.subBtn, 'GameFontHighlightSmall'); v.sub:SetAllPoints()
  if v.sub.SetWordWrap then v.sub:SetWordWrap(false) end
  v.subBtn:SetScript('OnClick', function() if v.current and v.current.back then WL.showResult(v.current.back) end end)
  for i = 1, ROWS do
    local r = CreateFrame('Button', nil, f)
    r:SetPoint('TOPLEFT', 0, -38 - (i - 1) * 17); r:SetPoint('TOPRIGHT', 0, -38 - (i - 1) * 17); r:SetHeight(16)
    r.icon = r:CreateTexture(nil, 'ARTWORK'); r.icon:SetSize(14, 14); r.icon:SetPoint('LEFT', 0, 0)
    r.bar = CreateFrame('StatusBar', nil, r)
    r.bar:SetPoint('LEFT', 18, 0); r.bar:SetPoint('RIGHT', -56, 0); r.bar:SetHeight(14)
    r.bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); r.bar:SetStatusBarColor(0.58, 0.51, 0.79, 0.55)
    r.bar:SetMinMaxValues(0, 1)
    r.label = Text(r.bar, 'GameFontHighlightSmall'); r.label:SetPoint('LEFT', 4, 0); r.label:SetJustifyV('MIDDLE')
    r.right = Text(r, 'GameFontHighlightSmall'); r.right:SetPoint('RIGHT', 0, 0); r.right:SetJustifyH('RIGHT')
    tip(r, function(self) return self.tipText end)
    r:SetScript('OnClick', function(self) if self.onClick then self.onClick() end end)
    r:Hide()
    v.rows[i] = r
  end
  v.info = Text(f, 'GameFontHighlightSmall')
  if v.info.SetSpacing then v.info:SetSpacing(2) end
  return v
end

local function setRows(v, rows)                          -- rows: { { label, share (0..1), right, icon, tip, onClick, color } }
  for i = 1, ROWS do
    local r, d = v.rows[i], i <= v.fit and rows[i] or nil
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

local function showSingle(v, res, build, raceKey, weights, notes, fromRank)
  local race = WL.RACES[raceKey] and WL.RACES[raceKey].name or raceKey
  v.head:SetText(string.format('%s DPS  |cffaaaaaa+- %s|r', fmt(res.dps, 1), fmt(res.dpsErr, 1)))
  v.sub:SetText(string.format('%s - %s - %d fights of about %d s%s', build.short or 'Build', race, res.iterations, floor(res.avgDuration + 0.5), fromRank and '   |cff9482c9(click here: back to the ranking)|r' or ''))
  local list, total = {}, 0
  for k, r in pairs(res.bySpell) do
    if r.dmg > 0 then list[#list + 1] = { key = k, r = r }; total = total + r.dmg end
  end
  table.sort(list, function(a, b) return a.r.dmg > b.r.dmg end)
  local rows, other = {}, 0
  local top = list[1] and list[1].r.dmg or 1
  for i = 1, #list do
    local k, r = list[i].key, list[i].r
    if i < v.fit or #list == v.fit then
      local name, icon = rowInfo(k, build)
      local hits = r.hits + r.ticks
      rows[#rows + 1] = { label = name, share = r.dmg / top, right = string.format('%s%%', fmt(100 * r.dmg / total, 1)), icon = spellIcon(icon),
        tip = string.format('%s\n%s DPS (%s%% of your damage)\n%s casts a fight%s\nCrits: %s%% of hits and ticks%s', name, fmt(r.dmg / res.avgDuration, 1), fmt(100 * r.dmg / total, 1), fmt(r.casts, 1),
          r.misses > 0 and string.format(', %s missed', fmt(r.misses, 1)) or '', fmt(hits > 0 and 100 * (r.crits + r.tickCrits) / hits or 0, 1),
          r.castTime > 0 and string.format('\nDamage per second of cast time: %s', fmt(r.dmg / r.castTime, 0)) or '') }
    else other = other + r.dmg end
  end
  if other > 0 then rows[#rows + 1] = { label = 'Everything else', share = other / top, right = string.format('%s%%', fmt(100 * other / total, 1)) } end
  setRows(v, rows)
  local lines = {}
  if weights and weights.sp and weights.sp > 0 then
    local function eq(k, per) return fmt(weights[k] * per / weights.sp, 1) end
    lines[#lines + 1] = string.format('|cffffd100Worth in spell power:|r 1%% hit = %s   1%% crit = %s   1%% haste = %s', eq('hitPct', 1), eq('critPct', 1), eq('hastePct', 1))
    lines[#lines + 1] = string.format('10 Intellect = %s   10 Spell Pierce = %s   |cffaaaaaa(1 spell power = %s DPS)|r', eq('int', 10), eq('pierce', 10), fmt(weights.sp, 2))
  elseif weights then
    lines[#lines + 1] = 'Stat weights: spell power gave no gain in this run (try more fights).'
  elseif v.current and v.current.weightsPending then
    lines[#lines + 1] = '|cffaaaaaaStat weights: still simming...|r'
  end
  lines[#lines + 1] = string.format('|cffaaaaaaLife Taps a fight: %s   lowest mana: %s   threat: %s a second%s|r', fmt(res.lifeTaps, 1), fmt(res.minMana, 0), fmt(res.tps, 0),
    res.mana.oomAvg > 0 and '   |cffff6060out of mana at times|r' or '')
  for i = 1, #(notes or {}) do lines[#lines + 1] = '|cffffb060' .. notes[i] .. '|r' end
  if WL.char and (WL.char.level or 60) < 60 then lines[#lines + 1] = string.format('|cffffb060A level 60 number: you are level %d.|r', WL.char.level) end
  v.info:SetText(table.concat(lines, '\n'))
end

local function showRank(v, r)
  local best = r.rows[1]
  v.head:SetText(string.format('Best with your gear: %s', best.build.short or best.build.key))
  local race = WL.RACES[r.race] and WL.RACES[r.race].name or r.race
  v.sub:SetText(string.format('%d builds with your gear - %s - %d fights each. Click a build for its spells.', #r.rows, race, best.res.iterations))
  local rows = {}
  for i = 1, math.min(#r.rows, ROWS) do
    local row = r.rows[i]
    local mine = row.build.key == 'character'              -- your own character among the sim's builds: gold, so it stands out
    rows[i] = { label = (mine and '|cffffd100' or '') .. i .. '  ' .. (row.build.short or row.build.key) .. (mine and '  (you)|r' or ''), share = row.res.dps / best.res.dps,
      right = (mine and '|cffffd100' or '') .. fmt(row.res.dps, 1) .. (mine and '|r' or ''), color = mine and { 1, 0.82, 0, 0.6 } or nil,
      tip = string.format('%s\n%s DPS (+- %s)\n%s%% behind the best\n%s', row.build.name or row.build.short or '', fmt(row.res.dps, 1), fmt(row.res.dpsErr, 1), fmt(100 * (1 - row.res.dps / best.res.dps), 1), row.build.notes or ''),
      onClick = function() WL.showResult({ kind = 'single', res = row.res, build = row.build, race = r.race, back = r }) end }
  end
  setRows(v, rows)
  v.info:SetText((r.pending and ('|cffaaaaaa' .. r.pending .. ' more to come...|r\n') or '') .. '|cffaaaaaaDifferences smaller than the +- of two builds are noise. More fights (Options) tell close builds apart.|r')
end

local function signed(x, d) return (x >= 0 and '+' or '') .. fmt(x, d) end
-- "What if": the change in DPS, and which spells it came from
local function showWhatIf(v, r)
  v.head:SetText(string.format('%s%s DPS|r  |cffaaaaaa+- %s|r', r.diff >= 0 and '|cff40ff40' or '|cffff6060', signed(r.diff, 1), fmt(r.err, 1)))
  v.sub:SetText(string.format('What if %s:  %s -> %s DPS', WL.describeStats(r.delta, true), fmt(r.base.dps, 1), fmt(r.res.dps, 1)))
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
  setRows(v, rows)
  local lines, only, amount = {}, nil, 0
  for k, x in pairs(r.delta) do if x ~= 0 then if only then only = false else only, amount = k, x end end end
  if only then lines[#lines + 1] = string.format('|cffffd100That is %s DPS for each %s.|r', signed(r.diff / amount, 2), WL.describeStats({ [only] = 1 })) end
  lines[#lines + 1] = string.format('|cffaaaaaaBoth sides play the same %d fights, so the change is measured to within the +-.|r', r.res.iterations)
  for i = 1, #(r.notes or {}) do lines[#lines + 1] = '|cffffb060' .. r.notes[i] .. '|r' end
  v.info:SetText(table.concat(lines, '\n'))
end

local function render(v)
  local r = v.current
  if not r then
    v.head:SetText(v.empty[1]); v.sub:SetText(v.empty[2])
    setRows(v, {}); v.info:SetText('')
  elseif r.kind == 'rank' then showRank(v, r)
  elseif r.kind == 'whatif' then showWhatIf(v, r)
  else showSingle(v, r.res, r.build, r.race, r.weights, r.notes, r.back ~= nil) end
  if v.onRender then v.onRender(r) end
end
-- puts a page's result at `top` (pixels from the page's top) with `height` left for it: as many bars as fit
local function placeView(v, top, height)
  v.frame:ClearAllPoints()
  v.frame:SetPoint('TOPLEFT', 0, -top); v.frame:SetPoint('TOPRIGHT', 0, -top)
  v.frame:SetHeight(math.max(60, height))
  v.fit = math.max(3, math.min(ROWS, floor((height - 38 - 70) / 17)))
  v.info:ClearAllPoints()
  v.info:SetPoint('TOPLEFT', 0, -38 - v.fit * 17 - 4); v.info:SetPoint('TOPRIGHT', 0, -38 - v.fit * 17 - 4)
  render(v)
end

-- Which page shows a result: a ranking and a build picked from it on Builds, a What if on What if, the rest on My DPS.
function WL.showResult(r)
  if not main then return end
  local k = 'dps'
  if r and (r.kind == 'rank' or (r.kind == 'single' and r.back)) then k = 'builds' elseif r and r.kind == 'whatif' then k = 'whatif' end
  views[k].current = r
  render(views[k])
end

-- ---------------------------------------------------------------------------------------------------------------------
-- pages
-- ---------------------------------------------------------------------------------------------------------------------
local PET_NAMES = { imp = 'Imp', succubus = 'Succubus', felhunter = 'Felhunter', voidwalker = 'Voidwalker' }
local function startSim(fn)
  if WL.jobRunning() then return end
  hideMenu()
  local ok, err = fn()
  if ok == false and err then say(err, true) end
  WL.refresh()
end
-- Sim and What if read your character first (out of combat), so what is simmed is what you wear right now.
local function readNow()
  if InCombatLockdown and InCombatLockdown() then return end
  local ch, err = WL.doReadCharacter()
  if not ch and not WL.char then return err end
end
local function simMine()
  startSim(function()
    local err = readNow()
    if err then return false, err end
    return WL.simCharacter()
  end)
end
local function opts() return WL.db.options end

-- My DPS: who you are, the rotation and demon, your result
local function characterTip()
  local ch = WL.char
  if not ch then return 'Your character is read when the window opens and when you press Sim (not in combat): your talents, race, demon and the numbers on your character sheet.' end
  local s, g = ch.sheet, ch.gear
  local school = ''
  if (g.shadowSp or 0) > 0 then school = school .. ' +' .. fmt(g.shadowSp) .. ' Shadow' end
  if (g.fireSp or 0) > 0 then school = school .. ' +' .. fmt(g.fireSp) .. ' Fire' end
  local lines = {
    '|cffffd100On your character sheet|r',
    string.format('Spell power %s%s   Hit %s   Crit %s   Haste %s', fmt(s.sp), school, pct1(s.hit), pct1(s.crit), pct1(s.haste)),
    string.format('Intellect %s   Spirit %s   Stamina %s   Mana per 5 s %s   Spell Pierce %s', fmt(s.int), fmt(s.spi), fmt(s.sta), fmt(s.mp5), fmt(s.pierce)),
    '|cffffd100What the sim counts as your gear|r (the sheet without your base stats and the buffs it takes off)',
    string.format('Spell power %s   hit %s   crit %s   Intellect %s   Spirit %s   Stamina %s', fmt(g.sp), pct1(g.hitPct), pct1(g.critPct), fmt(g.int), fmt(g.spi), fmt(g.sta)),
  }
  local on = {}
  for k in pairs(ch.buffsOnYou or {}) do on[#on + 1] = WL.DEFAULT_CONFIG.buffs[k].name end
  table.sort(on)
  if #on > 0 then lines[#lines + 1] = '\nTaken off your numbers (Raid setup decides): ' .. table.concat(on, ', ') .. '.' end
  if #(ch.otherAuras or {}) > 0 then lines[#lines + 1] = 'Also on you; if they give stats, they count as gear: ' .. table.concat(ch.otherAuras, ', ') .. '.' end
  if ch.weaponEffect then lines[#lines + 1] = 'Your weapon has a temporary effect (stone or oil): its bonus is in your numbers.' end
  local fx = WL.wornEffectNames(ch.worn)
  if #fx > 0 then lines[#lines + 1] = 'What these do counts in the fight: ' .. table.concat(fx, ', ') .. ' (when trinkets are used: Raid setup).' end
  return table.concat(lines, '\n')
end
local function characterWarnings(ch)
  local w = {}
  local _, points = WL.talentSplit(ch.talents)
  if ch.level and ch.level < 60 then w[#w + 1] = string.format('Level %d: the sim plays your numbers as a level 60 Warlock (level 60 spells, a level 63 boss), so the DPS is what that would do. Item and stat comparisons still give a rough idea.', ch.level) end
  if points ~= 51 and (ch.level or 60) >= 60 then w[#w + 1] = string.format('%d talent points found (51 expected).', points) end
  for i = 1, #ch.notes do w[#w + 1] = ch.notes[i] end
  return w
end
local function buildDpsPage(p)
  p.who = Line(p, 'GameFontNormal', 0, 0, 100)
  p.sim = Button(p, 'Sim', 90, simMine, 'Reads your character (out of combat) and plays the fights: your DPS, the share of each spell and (if switched on in Options) what each stat is worth.')
  p.sim:SetPoint('TOPRIGHT', 0, 3)
  p.infoBtn = CreateFrame('Button', nil, p)
  p.infoBtn:SetPoint('TOPLEFT', 0, -18); p.infoBtn:SetPoint('TOPRIGHT', -100, -18); p.infoBtn:SetHeight(14)
  p.info = Text(p.infoBtn, 'GameFontDisableSmall'); p.info:SetAllPoints()
  if p.info.SetWordWrap then p.info:SetWordWrap(false) end
  tip(p.infoBtn, function()
    local t = characterTip()
    local w = WL.char and characterWarnings(WL.char) or {}
    if #w > 0 then t = t .. '\n\n|cffffb060' .. table.concat(w, '\n') .. '|r' end
    return t
  end)
  local l1 = Text(p, 'GameFontNormalSmall', 'Rotation'); l1:SetPoint('TOPLEFT', 0, -44)
  p.rotation = keep(Dropdown(p, 200, function()
    local items, list = {}, WL.templates()
    for i = 1, #list do items[i] = { value = list[i].key, label = (list[i].short or list[i].key) .. (list[i].imported and ' (loaded)' or '') } end
    return items
  end, function()
    if WL.findTemplate(opts().template) then return opts().template end
    return WL.char and WL.bestTemplate(WL.char.talents, WL.templates(), WL.char.pet) or WL.BUILDS[1].key
  end, function(v) opts().template = v end,
    'Your talents and demon come from your character. The order in which spells are cast (the priority list) is taken from this build. The closest ready build is picked for you; a build code from the website (Codes) adds its own.'))
  p.rotation:SetPoint('TOPLEFT', 56, -40)
  local function demonItems(auto, extra)
    local items = { { value = 'auto', label = auto } }
    local keys = { 'imp', 'succubus', 'felhunter', 'voidwalker' }
    for i = 1, 4 do items[#items + 1] = { value = keys[i], label = PET_NAMES[keys[i]] } end
    items[#items + 1] = { value = 'none', label = extra }
    return items
  end
  local l2 = Text(p, 'GameFontNormalSmall', 'Demon'); l2:SetPoint('TOPLEFT', 266, -44)
  local demon = keep(Dropdown(p, 130, function()
    return demonItems('As read: ' .. ((WL.char and WL.char.pet and PET_NAMES[WL.char.pet]) or 'none'), 'None')
  end, function() return opts().pet end, function(v) opts().pet = v end, 'The demon that fights with you in the sim.'))
  demon:SetPoint('TOPLEFT', 310, -40)
  p.more = keep(Fold(p, 'More choices', function() return opts().dpsMore end, function() opts().dpsMore = not opts().dpsMore; p.layout() end,
    'The demon given up with Demonic Sacrifice, and a weapon stone.'))
  p.more:SetPoint('TOPLEFT', 0, -66); p.more:SetWidth(140)
  p.moreRow = CreateFrame('Frame', nil, p)
  p.moreRow:SetPoint('TOPLEFT', 0, -88); p.moreRow:SetPoint('TOPRIGHT', 0, -88); p.moreRow:SetHeight(22)
  local l3 = Text(p.moreRow, 'GameFontNormalSmall', 'Sacrificed'); l3:SetPoint('TOPLEFT', 0, -4)
  keep(Dropdown(p.moreRow, 130, function()
    return demonItems('As read: ' .. ((WL.char and WL.char.sacrifice and PET_NAMES[WL.char.sacrifice]) or 'none'), 'None')
  end, function() return opts().sacrifice end, function(v) opts().sacrifice = v end,
    'The demon given up with Demonic Sacrifice before the fight. Read from the buff on you; pick it here if the addon did not find it.')):SetPoint('TOPLEFT', 62, 0)
  local l4 = Text(p.moreRow, 'GameFontNormalSmall', 'Weapon stone'); l4:SetPoint('TOPLEFT', 204, -4)
  keep(Dropdown(p.moreRow, 160, function()
    return { { value = 'sheet', label = 'Already in my numbers (or none)' }, { value = 'spellstone', label = 'Add a Major Spellstone' }, { value = 'firestone', label = 'Add a Major Firestone' } }
  end, function() return opts().stone end, function(v) opts().stone = v end,
    'If a Spellstone or Firestone was active while your character was read, its bonus is inside your numbers already: leave this on the first choice. Pick a stone here only if you read your character without one.')):SetPoint('TOPLEFT', 286, 0)
  p.view = newView(p, { 'No result yet', 'Press Sim: your character is read and played.' })
  views.dps = p.view
  p.layout = function()
    local open = opts().dpsMore and true or false
    p.moreRow:SetShown(open)
    local top = open and 116 or 92
    placeView(p.view, top, (p.ph or 380) - top)
  end
  p.sync = function()
    local ch = WL.char
    if p.sim.SetEnabled then p.sim:SetEnabled(not WL.jobRunning()) end
    if not ch then
      p.who:SetText('No character read yet')
      p.info:SetText('Your character is read when you press Sim (not in combat).')
      return
    end
    local split = WL.talentSplit(ch.talents)
    local race = WL.RACES[ch.raceKey] and WL.RACES[ch.raceKey].name or '?'
    p.who:SetText(string.format('%s - %s - level %s - %s', tostring(ch.name), race, tostring(ch.level or '?'), split))
    local when = (ch.readAt or 0) > 0 and ('Read ' .. date('%d %b, %H:%M', ch.readAt)) or 'Read before'
    local w = #characterWarnings(ch)
    p.info:SetText(when .. (ch.restored and ' (kept over the reload: Sim reads it again)' or '') .. '   |cff9482c9your numbers and notes: hover here|r' .. (w > 0 and string.format('   |cffffb060%d note%s|r', w, w > 1 and 's' or '') or ''))
  end
end

-- What if: your character with a little more (or less) of a stat
local WHATIF_BOXES = { { 'sp', 'Spell power' }, { 'shadowSp', 'Shadow power' }, { 'fireSp', 'Fire power' }, { 'hit', 'Hit %' }, { 'crit', 'Crit %' },
                       { 'haste', 'Haste %' }, { 'int', 'Intellect' }, { 'spi', 'Spirit' }, { 'sta', 'Stamina' }, { 'pierce', 'Spell Pierce' }, { 'mp5', 'Mana per 5' } }
local WHATIF_QUICK = { { '+10 SP', 'sp', 10 }, { '+1% hit', 'hit', 1 }, { '+1% crit', 'crit', 1 }, { '+1% haste', 'haste', 1 }, { '+20 Int', 'int', 20 } }
local function buildWhatIfPage(p)
  local change, boxes = {}, {}
  local function simChange()
    for i = 1, #boxes do                                  -- what is typed counts, even if the box still has the cursor
      local v = tonumber(((boxes[i]:GetText() or ''):gsub(',', '.')))
      change[WHATIF_BOXES[i][1]] = v or 0
    end
    startSim(function()
      local err = readNow()
      if err then return false, err end
      return WL.simWhatIf(copy(change))
    end)
  end
  for i = 1, #WHATIF_QUICK do
    local q = WHATIF_QUICK[i]
    local b = Button(p, q[1], 78, function()
      for k in pairs(change) do change[k] = 0 end
      change[q[2]] = q[3]
      for j = 1, #boxes do boxes[j]:ClearFocus(); boxes[j].sync() end
      simChange()
    end, 'Sims your character as it is and with ' .. WL.describeStats({ [q[2]] = q[3] }, true) .. ', and shows the difference. Both sides play the same fights, so even a small change shows.')
    b:SetPoint('TOPLEFT', (i - 1) * 84, 0)
  end
  p.own = keep(Fold(p, 'Your own change', function() return opts().whatifOwn end, function() opts().whatifOwn = not opts().whatifOwn; p.layout() end,
    'Type any change (a minus for less). Shadow / Fire power: spell damage for that school only. Hit, crit and haste are in percent; Intellect also adds crit.'))
  p.own:SetPoint('TOPLEFT', 0, -30); p.own:SetWidth(160)
  p.ownBox = CreateFrame('Frame', nil, p)
  p.ownBox:SetPoint('TOPLEFT', 0, -52); p.ownBox:SetPoint('TOPRIGHT', 0, -52); p.ownBox:SetHeight(124)
  for i = 1, #WHATIF_BOXES do
    local key, x, y = WHATIF_BOXES[i][1], ((i - 1) % 3) * 146, -floor((i - 1) / 3) * 24
    local l = Text(p.ownBox, 'GameFontNormalSmall', WHATIF_BOXES[i][2]); l:SetPoint('TOPLEFT', x, y - 4)
    local e = Edit(p.ownBox, 46, function() return change[key] or 0 end, function(v) change[key] = v end)
    e:SetPoint('TOPLEFT', x + 80, y)
    boxes[i] = keep(e)
  end
  p.go = Button(p.ownBox, 'Sim this change', 130, simChange, 'Sims your character as it is and with the change above, and shows the difference in DPS and where it comes from.')
  p.go:SetPoint('TOPLEFT', 0, -98)
  local clear = Button(p.ownBox, 'Clear', 80, function()
    for k in pairs(change) do change[k] = 0 end
    for j = 1, #boxes do boxes[j]:ClearFocus(); boxes[j].sync() end
  end, 'Sets every box back to 0.')
  clear:SetPoint('TOPLEFT', 136, -98)
  p.view = newView(p, { 'No change simmed yet', 'Press one of the buttons above, or open "Your own change".' })
  views.whatif = p.view
  p.layout = function()
    local open = opts().whatifOwn and true or false
    p.ownBox:SetShown(open)
    local top = open and 184 or 58
    placeView(p.view, top, (p.ph or 380) - top)
  end
  p.sync = function() if p.go.SetEnabled then p.go:SetEnabled(not WL.jobRunning()) end end
end

-- Items: the last 10 item sims, and how items are simmed
local ITEM_ROWS = 10
local function buildItemsPage(p)
  Line(p, 'GameFontHighlightSmall', 0, 0, 0, 'Items you simmed, newest first. Click one to sim it again.')
  p.empty = Line(p, 'GameFontDisableSmall', 0, -20, 0)
  p.rows = {}
  for i = 1, ITEM_ROWS do
    local r = CreateFrame('Button', nil, p)
    r:SetPoint('TOPLEFT', 0, -18 - (i - 1) * 18); r:SetPoint('TOPRIGHT', 0, -18 - (i - 1) * 18); r:SetHeight(17)
    local hl = r:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    r.name = Text(r, 'GameFontHighlightSmall'); r.name:SetPoint('LEFT', 2, 0); r.name:SetPoint('RIGHT', -150, 0); r.name:SetJustifyV('MIDDLE')
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.right = Text(r, 'GameFontHighlightSmall'); r.right:SetPoint('RIGHT', -2, 0); r.right:SetJustifyH('RIGHT'); r.right:SetJustifyV('MIDDLE')
    r:SetScript('OnClick', function(self) if not WL.jobRunning() then WL.simItemAgain(self.index) end end)
    r:SetScript('OnEnter', function(self)
      if not (GameTooltip and self.link) then return end
      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then GameTooltip:SetText(self.link) end
      GameTooltip:Show()
    end)
    r:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    r:Hide()
    p.rows[i] = r
  end
  local y = -18 - ITEM_ROWS * 18 - 12
  local h1 = Text(p, 'GameFontNormal', 'On your character sheet'); h1:SetPoint('TOPLEFT', 0, y)
  keep(Check(p, 'A number over each item you wear: the DPS it is worth to you', function() return opts().sheetNumbers ~= false end, function(v) opts().sheetNumbers = v end,
    'Over every item you wear, the DPS that item is worth to you (your character as it is against the same character with that slot empty), and over your character the DPS it sims at.\n\nThey are worked out in the background when you open the character sheet, one item after the other, and again when your items, talents or the sim\'s settings change. A sim you start yourself always goes first.')):SetPoint('TOPLEFT', -2, y - 18)
  y = y - 48
  local h2 = Text(p, 'GameFontNormal', 'Simming an item'); h2:SetPoint('TOPLEFT', 0, y)
  local l1 = Text(p, 'GameFontNormalSmall', 'Sim an item with'); l1:SetPoint('TOPLEFT', 0, y - 24)
  keep(Dropdown(p, 160, function() return WL.ITEM_CLICKS end, function() return opts().itemClick end, function(v) opts().itemClick = v end,
    'This click on an item - in your bags, on your character sheet, at a vendor, in a loot window - opens a small panel and sims your character with that item in place of the one you wear in its slot. A loot roll popup (Need / Greed) gets a small Sim button beside it instead (its item icon takes left clicks only). An item you are wearing is simmed against an empty slot: what it is worth to you.\n\nPick another click if this one is taken by another addon or gets in your way; the game may also do what it usually does for that click. "Off" also hides the button under item links from chat.')):SetPoint('TOPLEFT', 110, y - 20)
  local l2 = Text(p, 'GameFontNormalSmall', 'Fights per item sim'); l2:SetPoint('TOPLEFT', 0, y - 48)
  keep(Edit(p, 50, function() return opts().itemFights end, function(v) opts().itemFights = math.max(20, math.min(2000, floor(v))) end,
    'How many fights an item sim plays (the click on an item, and the numbers on your character sheet). More fights = smaller differences show reliably, and a longer wait. 150 is a quick look; 500 and more to tell close items apart.')):SetPoint('TOPLEFT', 116, y - 44)
  p.sync = function()
    local list = WL.itemHistory()
    for i = 1, ITEM_ROWS do
      local r, h = p.rows[i], list[i]
      if h then
        r.index, r.link = i, h.link
        r.name:SetText(h.link .. (h.worn and '  |cffaaaaaa(you wear it)|r' or ''))
        r.right:SetText(h.text or '')
        r:Show()
      else r:Hide() end
    end
    local click = WL.itemClickText()
    p.empty:SetText(#list == 0 and ('None yet. ' .. (click and (click .. ' an item in your bags, on your character sheet or at a vendor to sim it.') or 'Choose a click below to sim items.')) or '')
  end
end

-- Builds: every ready build with your gear, in order
local function buildBuildsPage(p)
  local lab = Text(p, 'GameFontNormalSmall', 'Race'); lab:SetPoint('TOPLEFT', 0, -4)
  p.race = keep(Dropdown(p, 170, function()
    local items = {}
    if WL.char then return { { value = WL.char.raceKey, label = (WL.RACES[WL.char.raceKey] and WL.RACES[WL.char.raceKey].name or '?') .. ' (your character)' } } end
    for i = 1, #WL.RACE_KEYS do items[i] = { value = WL.RACE_KEYS[i], label = WL.RACES[WL.RACE_KEYS[i]].name } end
    return items
  end, function() return WL.raceKey() end, function(v) if not WL.char then opts().race = v end end, 'Without a character read, the builds are played as this race, with the gear numbers of the sim\'s settings (or of a settings code you loaded).'))
  p.race:SetPoint('TOPLEFT', 36, 0)
  p.rank = Button(p, 'Rank builds', 120, function() startSim(WL.simRanking) end,
    'Reads your character again (out of combat), then plays every build of the sim (and builds you loaded under Codes) with your gear numbers and puts them in order: which build is best for your gear. Your own character, with the talents you have now, is in the list in gold.\n\nOne sim per build, in a row. Fewer fights (Options) make it quicker and less exact.')
  p.rank:SetPoint('TOPRIGHT', 0, 3)
  p.gearBtn = CreateFrame('Button', nil, p)
  p.gearBtn:SetPoint('TOPLEFT', 0, -26); p.gearBtn:SetPoint('TOPRIGHT', 0, -26); p.gearBtn:SetHeight(14)
  p.gear = Text(p.gearBtn, 'GameFontDisableSmall'); p.gear:SetAllPoints()
  tip(p.gearBtn, function()
    local g = WL.characterConfig().gear
    return string.format('Gear numbers used: %s spell power, %s hit, %s crit, %s haste, Intellect %s, Spirit %s, Stamina %s%s', fmt(g.sp), pct1(g.hitPct), pct1(g.critPct), pct1(g.hastePct),
      fmt(g.int), fmt(g.spi), fmt(g.sta), WL.char and ' (from your character).' or ' (the sim\'s settings - your character is read when you rank the builds).')
  end)
  p.view = newView(p, { 'No ranking yet', 'Press Rank builds: every build is played with your gear.' })
  views.builds = p.view
  p.use = Button(p.view.frame, 'Use this rotation', 128, function()
    local r = p.view.current
    if not (r and r.build and WL.findTemplate(r.build.key)) then return end
    opts().template = r.build.key
    say('Your rotation is now ' .. (r.build.short or r.build.key) .. ' (My DPS).')
    WL.refresh()
  end, 'Plays your character with the priority list of this build from now on (My DPS, "Rotation"). Your talents stay your own.')
  p.use:SetPoint('TOPRIGHT', 0, 2)
  p.view.onRender = function(r) p.use:SetShown(r ~= nil and r.kind == 'single' and r.back ~= nil and r.build ~= nil and WL.findTemplate(r.build.key) ~= nil) end
  p.layout = function() placeView(p.view, 46, (p.ph or 380) - 46) end
  p.sync = function()
    p.gear:SetText(WL.char and 'Played with the gear numbers of your character (hover to see them).' or 'No character read yet: played with the sim\'s gear numbers (hover to see them).')
    if p.rank.SetEnabled then p.rank:SetEnabled(not WL.jobRunning()) end
  end
end

-- Raid setup: the website's presets, raid buffs, boss debuffs, consumables, the fight
local COUNT_WHO = { innervate = 'Druids', powerInfusion = 'Priests' }
local function buildRaidPage(p)
  local scroll = CreateFrame('ScrollFrame', 'WarlockSimBuffScroll', p, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', 0, 0); scroll:SetPoint('BOTTOMRIGHT', -24, 0)
  local child = CreateFrame('Frame', nil, scroll)
  child:SetSize(400, 10)
  scroll:SetScrollChild(child)
  local stack, checks = {}, {}
  local function folded(key) return opts().fold[key] end
  local function row(h, section)
    local r = CreateFrame('Frame', nil, child)
    r:SetHeight(h)
    stack[#stack + 1] = { f = r, h = h, section = section }
    return r
  end
  local function relayout()
    local y = 0
    for _, e in ipairs(stack) do
      local hidden = e.section and folded(e.section)
      e.f:SetShown(not hidden)
      if not hidden then
        e.f:ClearAllPoints()
        e.f:SetPoint('TOPLEFT', child, 'TOPLEFT', 0, -y); e.f:SetPoint('TOPRIGHT', child, 'TOPRIGHT', 0, -y)
        y = y + e.h
      end
    end
    child:SetHeight(y + 8)
  end
  local function header(key, label, tooltip)
    local r = row(24)
    local f = keep(Fold(r, label, function() return not folded(key) end, function() opts().fold[key] = not folded(key); relayout() end, tooltip))
    f:SetPoint('TOPLEFT', 0, -4); f:SetPoint('TOPRIGHT', 0, -4)
    return f
  end
  -- the presets
  local pr = row(30)
  local x = 0
  for _, pre in ipairs(WL.BUFF_PRESETS or {}) do
    local b = Button(pr, pre.name, 96, function() WL.applyPreset(pre.key); say(pre.name .. ': buffs, boss debuffs and consumables as the website has them.'); WL.refresh() end,
      pre.tip .. '\n\nChanges only which buffs, boss debuffs and consumables are ticked; your gear and the fight stay.')
    b:SetPoint('TOPLEFT', x, -2); x = x + 102
  end
  p.now = Text(pr, 'GameFontDisableSmall'); p.now:SetPoint('TOPLEFT', x + 4, -7)
  -- buffs, debuffs, consumables
  local heads = {}
  local function item(tbl, key, section, others)
    local e = WL.DEFAULT_CONFIG[tbl][key]
    local r = row(20, section)
    local cb = Check(r, e.name, function() return WL.cfg[tbl][key] and WL.cfg[tbl][key].on end, function(v)
      WL.cfg[tbl][key].on = v
      if v then others(key) end
    end, e.name .. '\n' .. (e.desc or ''))
    cb:SetPoint('TOPLEFT', 8, 0)
    cb.label:SetPoint('RIGHT', r, 'RIGHT', e.count ~= nil and -100 or -4, 0)
    if cb.label.SetWordWrap then cb.label:SetWordWrap(false) end
    checks[#checks + 1] = cb
    if e.count ~= nil then                                     -- Innervate / Power Infusion: how many Druids / Priests
      local most = e.maxCount or 5
      local who = COUNT_WHO[key] or 'players'
      local n = Edit(r, 28, function() return WL.cfg[tbl][key].count or 1 end, function(v)
        WL.cfg[tbl][key].count = math.max(1, math.min(most, math.floor(v + 0.5)))
      end, 'How many ' .. who .. ' give you theirs (1 to ' .. most .. '). The next one comes when the last one is over.')
      n:SetPoint('TOPRIGHT', r, 'TOPRIGHT', -6, -1)
      local t = Text(r, 'GameFontHighlightSmall', 'how many'); t:SetPoint('RIGHT', n, 'LEFT', -8, 0)
      checks[#checks + 1] = n
    end
  end
  local function group(tbl, order, key, label, others)
    heads[#heads + 1] = { f = header(key, label, 'Click to show or hide the list.'), tbl = tbl, label = label }
    for i = 1, #order do item(tbl, order[i], key, others) end
  end
  group('buffs', WL.BUFF_ORDER, 'buffs', 'Raid buffs', function(key)
    for k, b in pairs(WL.cfg.buffs) do if k ~= key and b.on and WL.buffsClash(WL.cfg.buffs[key], b) then b.on = false end end
  end)
  group('debuffs', WL.DEBUFF_ORDER, 'debuffs', 'On the boss', function(key)
    local g = WL.cfg.debuffs[key].group
    if g then for k, d in pairs(WL.cfg.debuffs) do if k ~= key and d.group == g then d.on = false end end end
  end)
  group('consumables', WL.CONSUMABLE_ORDER, 'consumables', 'Consumables', function(key)
    local c = WL.cfg.consumables[key]
    for k, x2 in pairs(WL.cfg.consumables) do if k ~= key and x2.group == c.group then x2.on = false end end
    if c.requires and WL.cfg.professions then WL.cfg.professions[c.requires] = true end
  end)
  -- the fight
  local f = function() return WL.cfg.fight end
  local function label(r, text, lx) local t = Text(r, 'GameFontNormalSmall', text); t:SetPoint('TOPLEFT', lx, -4); return t end
  local function place(r, w, wx) w:SetPoint('TOPLEFT', wx, 0); return w end
  header('fight', 'Fight')
  local r = row(24, 'fight')
  label(r, 'Length (s)', 8)
  place(r, keep(Edit(r, 50, function() return f().duration end, function(v) f().duration = math.max(10, math.min(1800, v)) end, 'Each fight lasts this long, give or take 10%.')), 100)
  label(r, 'Targets', 170)
  place(r, keep(Dropdown(r, 50, function() return { { value = 1, label = '1' }, { value = 2, label = '2' }, { value = 3, label = '3' } } end,
    function() return f().targets end, function(v) f().targets = v end, 'With 2 or 3 targets, Bane of Havoc (if talented) copies damage to the second one.')), 222)
  place(r, keep(Check(r, 'DoTs on all targets', function() return f().multiDot end, function(v) f().multiDot = v end, 'With 2 or 3 targets: your DoTs and curse are kept up on the extra targets too.')), 280)
  r = row(24, 'fight')
  label(r, 'Pop cooldowns', 8)
  place(r, keep(Dropdown(r, 190, function()
    return { { value = 'pull', label = 'At the pull' }, { value = 'doom', label = 'When Bane of Doom explodes' }, { value = 'execute', label = 'In the execute phase' } }
  end, function()
    local v = WL.cfg.options.activesPolicy
    return (v == 'pull' or v == 'doom' or v == 'execute') and v or 'doom'
  end, function(v) WL.cfg.options.activesPolicy = v end, 'When the racial cooldown, the Spellblasting potion and Power Infusion are used for the first time. Afterwards each is used again whenever it is ready.')), 100)
  r = row(24, 'fight')
  label(r, 'Trinkets', 8)
  place(r, keep(Dropdown(r, 190, function()
    return { { value = 'cds', label = 'With cooldowns' }, { value = 'ready', label = 'When ready' }, { value = 'execute', label = 'Execute phase' }, { value = 'never', label = 'Never' } }
  end, function()
    local tu = WL.cfg.options.trinketUse or {}
    return tu.trinket1 or 'cds'
  end, function(v) WL.cfg.options.trinketUse = { trinket1 = v, trinket2 = v } end,
    'When the trinkets you wear are used, if the sim knows what they do (Talisman of Ephemeral Power, Zandalarian Hero Charm, The Black Book and more). "With cooldowns": together with your racial and Power Infusion ("Pop cooldowns"). "When ready": from the pull on, again whenever ready. "Execute phase": only once the boss is low. "Never": not at all.\n\nA build with "Activate trinket" in its priority (most ready builds) uses them at that step instead, whenever they are ready and its condition holds; "Never" still keeps them unused.\n\nA mana trinket is used when its mana is missing. A trinket\'s plain stats always count, and so does what your main-hand enchant does (Revelation, Grand Sorcerer, Grand Arcanist, Insight).')), 100)
  local function typeList(list) return function() local items = {}; for i = 1, #list do items[i] = { value = list[i].key, label = list[i].name } end; return items end end
  r = row(24, 'fight')
  label(r, 'Boss type', 8)
  place(r, keep(Dropdown(r, 120, typeList(WL.BOSS_TYPES), function() return f().bossType or '' end, function(v) f().bossType = v end,
    'What the boss is. Only some trinkets care: Mark of the Champion (Demons and Undead), Rune of the Dawn, Royal Seal of Eldre\'Thalas, Draconic Infused Emblem (Dragonkin), Cannonball Runner and more. A kind of enemy counts as its creature type too: a Satyr is a Demon, a Murloc or a Troll a Humanoid, a Dinosaur a Beast.\n\n"Not set": none of those bonuses count.')), 100)
  label(r, 'Zone', 232)
  place(r, keep(Dropdown(r, 130, typeList(WL.ZONE_TYPES), function() return f().zone or '' end, function(v) f().zone = v end,
    'Where the fight is. Only some trinkets and set bonuses care ("This effect is doubled in ... areas"): Briarwood Reed (Marsh / Swamp), Golden Banana, Rune of Perfection, Enriched Seal (Forest / Grassland), Second Wind (Mountainous), Rotmender\'s Raiment (Haunted / Wasteland), Violet Sorcerer\'s Vestments (Stronghold / City) and more.\n\n"Not set": none of those bonuses count.')), 268)
  r = row(24, 'fight')
  place(r, keep(Check(r, 'Keep Curse of the Elements up', function() return WL.cfg.options.useCurseOfElements end, function(v) WL.cfg.options.useCurseOfElements = v end)), 6)
  header('fightMore', 'More fight settings', 'Precast, movement, hits taken, latency.')
  r = row(24, 'fightMore')
  label(r, 'Precast', 8)
  place(r, keep(Dropdown(r, 140, function()
    local items = { { value = '', label = 'Nothing' } }
    for i = 1, #WL.PRECAST_SPELLS do items[#items + 1] = { value = WL.PRECAST_SPELLS[i], label = WL.SPELLS[WL.PRECAST_SPELLS[i]].name } end
    return items
  end, function() return f().precast or '' end, function(v) f().precast = v end, 'A spell you start before the pull so that it finishes as the fight starts.')), 100)
  r = row(24, 'fightMore')
  label(r, 'Move every', 8)
  place(r, keep(Edit(r, 36, function() return f().moveEvery end, function(v) f().moveEvery = math.max(0, v) end, 'Every this many seconds you have to move (0 = never). Only instants can be cast while moving.')), 100)
  label(r, 's for', 144)
  place(r, keep(Edit(r, 36, function() return f().moveDuration end, function(v) f().moveDuration = math.max(0, v) end, 'How long each movement lasts, in seconds.')), 178)
  label(r, 's', 220)
  r = row(24, 'fightMore')
  label(r, 'Hit taken every', 8)
  place(r, keep(Edit(r, 36, function() return f().hitEvery end, function(v) f().hitEvery = math.max(0, v) end, 'You take a hit every this many seconds (0 = never): casts are pushed back.')), 100)
  label(r, 's      Latency (ms)', 144)
  place(r, keep(Edit(r, 50, function() return f().latencyMs end, function(v) f().latencyMs = math.max(0, math.min(2000, v)) end, 'Your reaction delay after each cast.')), 256)
  r = row(34)
  p.reset = Button(r, 'Back to the sim\'s settings', 190, function()
    WL.cfg = WL.newConfig(); WL.saveSettings(); WL.refresh()
    say('Buffs, boss debuffs, consumables and the fight are back to the sim\'s defaults.')
  end, 'Puts everything on this page back to what the sim starts with. Your character stays as read.')
  p.reset:SetPoint('TOPLEFT', 0, -8)
  relayout()
  p.layout = function() child:SetWidth(math.max(300, (p.pw or 460) - 28)) end
  p.sync = function()
    for i = 1, #checks do checks[i].sync() end
    for _, h in ipairs(heads) do
      local n, on = 0, 0
      for _, x2 in pairs(WL.cfg[h.tbl]) do n = n + 1; if x2.on then on = on + 1 end end
      h.f.text:SetText(string.format('%s  |cffaaaaaa(%d of %d)|r', h.label, on, n))
    end
    local pre = WL.presetNow()
    p.now:SetText(pre and ('Now: ' .. pre.name) or 'Now: your own choice')
  end
end

-- Codes: settings and build codes from the website in and out, a gear code of what you wear, the loaded builds
local LOADED_ROWS = 6
local function buildCodesPage(p)
  Line(p, 'GameFontHighlightSmall', 0, 0, 0, 'Paste a code from the website (Ctrl+V), or make one to take there (Ctrl+C copies).')
  local scroll = CreateFrame('ScrollFrame', 'WarlockSimCodeScroll', p, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', 2, -20); scroll:SetPoint('TOPRIGHT', -26, -20); scroll:SetHeight(84)
  local bg = scroll:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
  local box = CreateFrame('EditBox', nil, scroll)
  box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  box:SetWidth(400)
  box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
  scroll:SetScrollChild(box)
  scroll:SetScript('OnMouseDown', function() box:SetFocus() end)
  p.box = box
  local function show(code) box:SetText(code); box:SetFocus(); box:HighlightText() end
  local load = Button(p, 'Load the code', 120, function()
    local code = (box:GetText() or ''):gsub('%s+', '')
    if code:sub(1, #WL.SETTINGS_CODE_PREFIX) == WL.SETTINGS_CODE_PREFIX then
      local o, err = WL.decodeSettings(code)
      if not o then say(err, true); return end
      local c = WL.newConfig()
      local unknown, preBis = WL.applySettings(c, o)
      WL.cfg = c; WL.saveSettings()
      if preBis then say('Settings loaded' .. (#unknown > 0 and (' (not known here: ' .. table.concat(unknown, ', ') .. ')') or '') .. '. The code uses the website\'s Pre-BiS gear (each build its own items); the addon does not have those lists, so it keeps ' .. (WL.char and 'your character\'s gear numbers.' or 'the gear numbers it had. On the website, switch the gear to Custom to put gear numbers in a code.')); WL.refresh(); return end
      say('Settings loaded' .. (#unknown > 0 and (' (not known here: ' .. table.concat(unknown, ', ') .. ')') or '') .. (WL.char and '. Your character\'s own gear numbers still win: the code\'s gear is used when no character is read.' or '.'))
    elseif code:sub(1, #WL.BUILD_CODE_PREFIX) == WL.BUILD_CODE_PREFIX then
      local b, err, known = WL.addImportedBuild(code)
      if not b then say(err, true); return end
      local errs = WL.validateBuild(b)
      opts().template = b.key
      say('Build "' .. b.short .. '" ' .. (known and 'was loaded before' or 'loaded') .. ': it is your rotation now (My DPS) and in the ranking (Builds).' .. (b.migrated and (' ' .. table.concat(b.migrated, '. ') .. '.') or '') .. (#errs > 0 and (' Note: ' .. errs[1]) or ''), #errs > 0)
    elseif code:sub(1, #WL.GEAR_CODE_PREFIX) == WL.GEAR_CODE_PREFIX then say('That is a gear code: it is for the website\'s gear builder. The addon reads your gear from the game itself.', true)
    elseif code:find('share=', 1, true) then say('That is a share link. The addon reads settings codes and build codes: on the website use "Make settings code" or "Make build code".', true)
    else say('That is neither a settings code (WFS1:) nor a build code (WFB1:).', true) end
    WL.refresh()
  end, 'Reads the code in the box. A settings code replaces Raid setup (and the gear numbers used when no character is read). A build code adds a build with its priority list.')
  load:SetPoint('TOPLEFT', 0, -110)
  local mk = Text(p, 'GameFontNormal', 'Make a code'); mk:SetPoint('TOPLEFT', 0, -144)
  local s = Button(p, 'My settings', 100, function()
    show(WL.encodeSettings(WL.characterConfig()))
    say('Settings code made' .. (WL.char and ' (with your character\'s gear numbers)' or '') .. '. Copy it with Ctrl+C and paste it on the website under "Input / output".')
  end, 'Makes a settings code of everything set here, with your character\'s gear numbers if one is read. The website opens it under "Input / output".')
  s:SetPoint('TOPLEFT', 0, -162)
  local b = Button(p, 'My build', 100, function()
    local build, notes = WL.characterBuildNow()
    if not build then say(notes[1], true); return end
    show(WL.encodeBuild(build))
    local _, points = WL.talentSplit(build.talents)
    say('Build code made. ' .. (points ~= 51 and 'The website only takes builds with exactly 51 talent points (yours has ' .. points .. ').' or 'Paste it on the website under "Input / output".'), points ~= 51)
  end, 'Your talents, demon and priority list as a build code for the website.')
  b:SetPoint('TOPLEFT', 106, -162)
  local g = Button(p, 'My gear', 100, function()
    local code, items, enchants, notes, bags = WL.gearCode()
    if not code then say(items, true); return end
    show(code)
    say(string.format('Gear code made: %d items, %d enchants%s. Copy it with Ctrl+C and paste it on the website in the gear builder.%s', items, enchants,
      opts().gearBags and string.format(', %d from your bags', bags) or '', #notes > 0 and (' ' .. table.concat(notes, ' ')) or ''), #notes > 0)
  end, 'Makes a gear code of everything you wear: each item with its name, game id, item level, icon and stats, and the enchants (by their text). The website\'s gear builder loads it, so you can look at your own gear there, and it learns items it does not know yet.\n\n"Use:" and "Chance on hit:" effects are not in it; an enchant whose text the addon cannot read is counted as 0 and named.')
  g:SetPoint('TOPLEFT', 212, -162)
  keep(Check(p, 'Bags too', function() return opts().gearBags end, function(v) opts().gearBags = v end,
    '"My gear" also lists the items in your bags that you can wear, so you can send the website everything you have.')):SetPoint('TOPLEFT', 318, -162)
  local lb = Text(p, 'GameFontNormal', 'Loaded builds'); lb:SetPoint('TOPLEFT', 0, -196)
  p.none = Line(p, 'GameFontDisableSmall', 0, -214, 0, 'None. A build code from the website adds one here; it can then be your rotation (My DPS).')
  p.loaded = {}
  for i = 1, LOADED_ROWS do
    local r = CreateFrame('Frame', nil, p)
    r:SetPoint('TOPLEFT', 0, -212 - (i - 1) * 22); r:SetPoint('TOPRIGHT', 0, -212 - (i - 1) * 22); r:SetHeight(22)
    r.name = Text(r, 'GameFontHighlightSmall'); r.name:SetPoint('LEFT', 4, 0); r.name:SetPoint('RIGHT', -84, 0); r.name:SetJustifyV('MIDDLE')
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.remove = Button(r, 'Remove', 76, function(self)
      local bb = self.build
      if bb and WL.removeImportedBuild(bb.slot) then say('Removed "' .. (bb.short or '?') .. '".'); WL.refresh() end
    end, 'Removes this loaded build. If it was your rotation, the closest ready build is used again.')
    r.remove:SetPoint('RIGHT', 0, 0)
    r:Hide()
    p.loaded[i] = r
  end
  p.layout = function() box:SetWidth(math.max(200, (p.pw or 460) - 34)) end
  p.sync = function()
    local list = WL.imported or {}
    for i = 1, LOADED_ROWS do
      local r, bb = p.loaded[i], list[i]
      if bb then
        r.remove.build = bb
        r.name:SetText((bb.short or '?') .. (opts().template == bb.key and '  |cffffd100(your rotation)|r' or ''))
        r:Show()
      else r:Hide() end
    end
    p.none:SetShown(#list == 0)
  end
end

-- Options: accuracy and speed, the helper bar, the minimap button
local function buildOptionsPage(p)
  local y = 0
  local function head(text) local t = Text(p, 'GameFontNormal', text); t:SetPoint('TOPLEFT', 0, y); y = y - 20 end
  local function label(text, x) local t = Text(p, 'GameFontNormalSmall', text); t:SetPoint('TOPLEFT', x, y - 4); return t end
  head('Accuracy and speed')
  label('Fights per sim', 0)
  keep(Edit(p, 56, function() return opts().fights end, function(v) opts().fights = math.max(10, math.min(20000, floor(v))) end,
    'How many fights are played and averaged - with "Stop early" on, the most that are played. More fights = a steadier number and a longer wait. 300 is good for a quick look, 1000 and more to compare close builds.')):SetPoint('TOPLEFT', 110, y)
  label('While simming', 190)
  keep(Dropdown(p, 120, function() return { { value = 'auto', label = 'Automatic' }, { value = 'smooth', label = 'Stay smooth' }, { value = 'fast', label = 'Sim faster' }, { value = 'fastest', label = 'Fastest' } } end,
    function() return opts().speed end, function(v) opts().speed = v end, 'The game gives addons one processor core, shared with the game itself. "Automatic" sims faster while you are out of combat and stays smooth while you fight. "Stay smooth" sims for 8 ms of every frame: the game runs nearly as usual. "Sim faster" takes 30 ms: about twice as quick, the game stutters a little. "Fastest" takes 100 ms: the sim gets nearly the whole core, the game drops to about 10 frames a second until it is done.')):SetPoint('TOPLEFT', 280, y)
  y = y - 26
  keep(Check(p, 'Stop early when the result is exact enough', function() return opts().stopEarly ~= false end, function(v) opts().stopEarly = v end,
    'Stops a sim as soon as its result is exact enough, instead of always playing every fight: the number of fights set becomes the most that are played (never fewer than 40).\n\nA DPS stops when its +- is 0.5% of it. A comparison (an item, What if, a stat weight, the numbers on the character sheet) plays the same fights on both sides and stops when the +- of the difference is 0.5 DPS or a tenth of the difference - often after a few dozen fights.\n\nOff: every sim plays exactly the number of fights set.')):SetPoint('TOPLEFT', -2, y)
  y = y - 24
  keep(Check(p, 'Stat weights: what hit, crit, haste, Intellect and Spell Pierce are worth', function() return opts().weights end, function(v) opts().weights = v end,
    'Also works out what hit, crit, haste, Intellect and Spell Pierce are worth in spell power for your build (My DPS). Needs six more runs on the same fights; each stops as soon as its weight is exact enough.')):SetPoint('TOPLEFT', -2, y)
  y = y - 36
  head('The helper bar on raid bosses')
  keep(Check(p, 'Show it', function() return opts().helper == true end, function(v) WL.helper.toggle(v) end,
    "A small bar on raid bosses: the spell the sim would cast next with your character, the two after it, cooldowns and mana items to use with it, and the seconds until the boss dies. The sim's own priority list decides, with the time left worked out from how fast the boss loses health.\n\nOnly if your talents fit one of the sim's builds (your rotation on My DPS), and only on raid bosses.\n\nIt reads the boss's health, your mana, your buffs and the boss's debuffs from the game. Should the game ever hide one of them from addons, the helper follows your own casts instead; without the boss's health the time to kill is the fight length (Raid setup), shown in grey.")):SetPoint('TOPLEFT', -2, y)
  p.move = Button(p, 'Move the bar', 120, function()
    local moving = WL.helper.toggleMove()
    say(moving and 'Drag the helper bar where you want it, then press "Done moving".' or 'Helper bar placed.')
    p.move:SetText(moving and 'Done moving' or 'Move the bar')
  end, 'Shows the bar so you can drag it where you want it. Press again when it is in place (/wsim helper move does the same).')
  p.move:SetPoint('TOPLEFT', 110, y)
  y = y - 36
  head('The addon')
  keep(Check(p, 'Minimap button', function() return opts().minimapButton ~= false end, function(v) opts().minimapButton = v; WL.updateMinimapButton() end,
    'The round button at the edge of the minimap: click opens or closes this window, right-click sims your character, drag moves it. /wsim minimap does the same as this box.')):SetPoint('TOPLEFT', -2, y)
  y = y - 30
  Line(p, 'GameFontDisableSmall', 0, y, 0, '/wsim help lists the chat commands. The window can be made bigger or smaller at its bottom right corner.')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------------------------------------------------
local PAGES = {
  { key = 'dps', name = 'My DPS', icon = 'Interface\\Icons\\Spell_Shadow_ShadowBolt', build = buildDpsPage },
  { key = 'whatif', name = 'What if', icon = 'Interface\\Icons\\INV_Misc_QuestionMark', build = buildWhatIfPage },
  { key = 'items', name = 'Items', icon = 'Interface\\Icons\\INV_Chest_Cloth_08', build = buildItemsPage },
  { key = 'builds', name = 'Builds', icon = 'Interface\\Icons\\INV_Misc_Book_11', build = buildBuildsPage },
  { key = 'raid', name = 'Raid setup', icon = 'Interface\\Icons\\INV_Potion_25', build = buildRaidPage },
  { key = 'codes', name = 'Codes', icon = 'Interface\\Icons\\INV_Misc_Note_01', build = buildCodesPage },
  { key = 'options', name = 'Options', icon = 'Interface\\Icons\\Trade_Engineering', build = buildOptionsPage },
}
local function selectPage(key)
  hideMenu()
  if not pages[key] then key = 'dps' end
  opts().page = key
  for i = 1, #PAGES do
    local k = PAGES[i].key
    pages[k]:SetShown(k == key)
    navButtons[i].bg:SetColorTexture(0.58, 0.51, 0.79, k == key and 0.5 or 0)
  end
  if WL.refresh then WL.refresh() end
end
WL.selectPage = selectPage

-- everything that follows the window's size: the pages' width and height, how many result bars fit
local function relayout(w, h)
  local pw, ph = w - NAV - 3 * PAD, h - TOP - FOOT - 8
  for i = 1, #PAGES do
    local p = pages[PAGES[i].key]
    p.pw, p.ph = pw, ph
    if p.layout then p.layout() end
  end
end
local function savePlace()
  local a, _, b, x, y = main:GetPoint(1)
  WL.db.pos = { a, b, x, y }
  local w, h = main:GetWidth(), main:GetHeight()
  if type(w) == 'number' and type(h) == 'number' then WL.db.size = { floor(w + 0.5), floor(h + 0.5) } end
end

local function createFrame()
  main = CreateFrame('Frame', 'WarlockSimFrame', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
  local size = type(WL.db.size) == 'table' and WL.db.size or {}
  local w = math.max(MIN_W, math.min(MAX_W, tonumber(size[1]) or W0))
  local h = math.max(MIN_H, math.min(MAX_H, tonumber(size[2]) or H0))
  main:SetSize(w, h); main:SetFrameStrata('MEDIUM'); main:SetToplevel(true)
  main:SetClampedToScreen(true); main:SetMovable(true); main:EnableMouse(true)
  main:SetResizable(true)
  if main.SetResizeBounds then main:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
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
  drag:SetScript('OnDragStop', function() main:StopMovingOrSizing(); savePlace() end)
  local title = Text(main, 'GameFontNormalLarge', "Xn's Warlock Sim"); title:SetPoint('TOPLEFT', PAD, -9)
  local ver = Text(main, 'GameFontDisableSmall', 'v' .. WL.VERSION .. '  -  /wsim'); ver:SetPoint('LEFT', title, 'RIGHT', 8, -1)
  local close = CreateFrame('Button', nil, main, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', 0, 0)
  close:SetScript('OnClick', function() main:Hide() end)
  main:SetScript('OnHide', hideMenu)
  local line = main:CreateTexture(nil, 'ARTWORK'); line:SetColorTexture(0.58, 0.51, 0.79, 0.6)
  line:SetPoint('TOPLEFT', PAD, -TOP + 4); line:SetPoint('TOPRIGHT', -PAD, -TOP + 4); line:SetHeight(1)
  -- the corner that makes the window bigger or smaller
  local grip = CreateFrame('Button', nil, main)
  grip:SetSize(16, 16); grip:SetPoint('BOTTOMRIGHT', -3, 3)
  grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
  grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
  grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
  grip:SetScript('OnMouseDown', function() hideMenu(); main:StartSizing('BOTTOMRIGHT') end)
  grip:SetScript('OnMouseUp', function() main:StopMovingOrSizing(); savePlace(); relayout(main:GetWidth(), main:GetHeight()) end)
  tip(grip, 'Drag to make the window bigger or smaller.')
  main:SetScript('OnSizeChanged', function(_, nw, nh) if type(nw) == 'number' and type(nh) == 'number' then relayout(nw, nh) end end)
  return w, h
end

local function createNav()
  local split = main:CreateTexture(nil, 'ARTWORK'); split:SetColorTexture(0.58, 0.51, 0.79, 0.35)
  split:SetPoint('TOPLEFT', PAD + NAV + 4, -TOP - 2); split:SetPoint('BOTTOMLEFT', PAD + NAV + 4, FOOT + 2); split:SetWidth(1)
  for i = 1, #PAGES do
    local d = PAGES[i]
    local b = CreateFrame('Button', nil, main)
    b:SetSize(NAV - 4, 24)
    b:SetPoint('TOPLEFT', PAD, -TOP - 4 - (i - 1) * 27 - (d.key == 'options' and 12 or 0))
    b.bg = b:CreateTexture(nil, 'BACKGROUND'); b.bg:SetAllPoints()
    local hl = b:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    local ic = b:CreateTexture(nil, 'ARTWORK'); ic:SetSize(18, 18); ic:SetPoint('LEFT', 4, 0); ic:SetTexture(d.icon)
    local t = Text(b, 'GameFontNormalSmall', d.name); t:SetPoint('LEFT', 28, 0); t:SetJustifyV('MIDDLE')
    b:SetScript('OnClick', function() selectPage(d.key) end)
    navButtons[i] = b
    local page = CreateFrame('Frame', nil, main)
    page:SetPoint('TOPLEFT', PAD + NAV + 2 * PAD - 4, -TOP - 4); page:SetPoint('BOTTOMRIGHT', -PAD, FOOT + 4)
    pages[d.key] = page
    d.build(page)
    if page.sync then keep(page) end
  end
end

local function createFoot()
  local line = main:CreateTexture(nil, 'ARTWORK'); line:SetColorTexture(0.58, 0.51, 0.79, 0.6)
  line:SetPoint('BOTTOMLEFT', PAD, FOOT); line:SetPoint('BOTTOMRIGHT', -PAD, FOOT); line:SetHeight(1)
  foot.progress = CreateFrame('StatusBar', nil, main)
  foot.progress:SetPoint('BOTTOMLEFT', PAD, 28); foot.progress:SetPoint('BOTTOMRIGHT', -PAD - 70, 28); foot.progress:SetHeight(16)
  foot.progress:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8'); foot.progress:SetStatusBarColor(0.3, 0.75, 0.35, 0.8)
  foot.progress:SetMinMaxValues(0, 1)
  local pbg = foot.progress:CreateTexture(nil, 'BACKGROUND'); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.5)
  foot.progressText = Text(foot.progress, 'GameFontHighlightSmall'); foot.progressText:SetPoint('LEFT', 4, 0)
  foot.stop = Button(main, 'Stop', 62, function() WL.cancelJob() end)
  foot.stop:SetPoint('BOTTOMRIGHT', -PAD, 25)
  foot.status = Text(main, 'GameFontHighlightSmall')
  foot.status:SetPoint('BOTTOMLEFT', PAD, 28); foot.status:SetPoint('BOTTOMRIGHT', -PAD, 28)
  foot.status:SetJustifyV('BOTTOM')
  if foot.status.SetWordWrap then foot.status:SetWordWrap(false) end
  foot.tip = Text(main, 'GameFontDisableSmall'); foot.tip:SetPoint('BOTTOMLEFT', PAD, 9); foot.tip:SetPoint('BOTTOMRIGHT', -PAD - 150, 9)
  if foot.tip.SetWordWrap then foot.tip:SetWordWrap(false) end
  foot.fights = Text(main, 'GameFontDisableSmall'); foot.fights:SetPoint('BOTTOMRIGHT', -PAD - 14, 9); foot.fights:SetJustifyH('RIGHT')
  main:SetScript('OnUpdate', function()
    local done, total, label, secs = WL.jobProgress()
    if not done then return end
    foot.progress:SetValue(total > 0 and done / total or 0)
    local left = done > 0 and secs * (total - done) / done or nil
    foot.progressText:SetText(string.format('%s: %d of %d fights%s', label, done, total, left and string.format(' - about %d s left', floor(left + 0.5)) or ''))
  end)
end

local function create()
  opts().tab = nil                                        -- the tab of the window before v0.18.0
  if type(opts().fold) ~= 'table' then opts().fold = { buffs = true, debuffs = true, consumables = true, fightMore = true } end
  local w, h = createFrame()
  createNav()
  createFoot()
  relayout(w, h)
  for k, v in pairs(views) do render(v) end
  selectPage(opts().page)
end

function WL.refresh()
  if not main then return end
  for i = 1, #syncers do if syncers[i].sync then syncers[i].sync() end end
  local running = WL.jobRunning()
  foot.progress:SetShown(running); foot.stop:SetShown(running); foot.status:SetShown(not running)
  local click = WL.itemClickText()
  foot.tip:SetText(click and ('|cff9482c9Tip:|r ' .. click .. ' any item to sim what it is worth.')
    or 'Item sims are switched off (Items, "Sim an item with").')
  foot.fights:SetText(string.format('%d fights, %d s each', opts().fights or 0, floor((WL.cfg.fight.duration or 0) + 0.5)))
  WL.saveSettings()
end
WL.onJobEnd = function(res, err)
  if res and res.kind == 'item' then
    if WL.onItemResult then WL.onItemResult(res) end
  elseif res then
    WL.lastResult = res
    if main then
      WL.showResult(res)
      if res.remembered then say('|cffaaaaaaNothing has changed since this was simmed: the result is the same.|r')
      else say(string.format('|cffaaaaaa%d fights in %s s (%s ms of sim time a fight).|r', res.fights, fmt(res.seconds, 1), fmt(res.fights > 0 and 1000 * res.cpuSeconds / res.fights or 0, 1))) end
    end
  else
    if WL.onItemResult then WL.onItemResult(nil, err) end
    if main then say(tostring(err), true) end
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

-- the key binding "Sim my character" and a right-click on the minimap button: the window opens on My DPS and Sim is
-- pressed (your character is read first, if you are not fighting)
function WL.simFromKey()
  if not WL.db then return end
  if not main then create() end
  if not main:IsShown() then main:Show() end
  selectPage('dps')
  simMine()
end
