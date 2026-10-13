-- Numbers on the character sheet: over every item you wear, what that item is worth in DPS (your character as it is
-- against your character with that slot empty), and over your character the DPS it sims at.
-- They are worked out in the background the first time the sheet is opened with a given set of items, talents and sim
-- settings, one item after the other, and kept until one of those changes.
-- The texts live on a frame of the addon's own that is a child of the character sheet (so it shows and hides with it)
-- and are only anchored to the game's item slots. Nothing of the game's is changed or hooked.
local ADDON, WL = ...
local copy = WL.copy

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function try(f, ...)
  if type(f) ~= 'function' then return nil end
  local ok, a, b = pcall(f, ...)
  if not ok or isSecret(a) then return nil end
  return a, b
end

-- the character sheet's slots that can hold something the sim counts (shirt, tabard and ammunition are left out)
local SLOT_NAMES = { 'Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Finger0', 'Finger1',
                     'Trinket0', 'Trinket1', 'MainHand', 'SecondaryHand', 'Ranged' }
local overlay, total, sub
local labels = {}                                         -- inventory slot number -> its text
local slots = {}                                          -- list of { id, button }
local state = { key = nil, base = nil, worth = {} }       -- worth[slot] = { link, dps, err } for the items of `key`
local failedKey                                           -- a set of items that could not be simmed (no retry until something changes)

local function enabled() return WL.db ~= nil and WL.db.options.sheetNumbers ~= false end
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function create()
  if overlay or not PaperDollFrame or inCombat() then return overlay ~= nil end
  overlay = CreateFrame('Frame', nil, PaperDollFrame)
  overlay:SetAllPoints(PaperDollFrame)
  local level = (PaperDollItemsFrame and PaperDollItemsFrame.GetFrameLevel and PaperDollItemsFrame:GetFrameLevel()) or (PaperDollFrame.GetFrameLevel and PaperDollFrame:GetFrameLevel()) or 0
  if type(level) ~= 'number' then level = 0 end
  overlay:SetFrameLevel(level + 50)                       -- above the item slots
  for i = 1, #SLOT_NAMES do
    local button = _G['Character' .. SLOT_NAMES[i] .. 'Slot']
    local id = button and button.GetID and try(button.GetID, button)
    if type(id) == 'number' and id > 0 then
      local fs = overlay:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
      fs:SetPoint('BOTTOM', button, 'BOTTOM', 0, 1)
      fs:SetJustifyH('CENTER')
      labels[id] = fs
      slots[#slots + 1] = { id = id, button = button }
    end
  end
  local anchor = CharacterModelScene or PaperDollFrame
  -- at the feet of your character (the top of the model belongs to the game's own turn / zoom buttons)
  sub = overlay:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
  sub:SetPoint('BOTTOM', anchor, 'BOTTOM', 0, 6)
  total = overlay:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
  total:SetPoint('BOTTOM', sub, 'TOP', 0, 1)
  return true
end

-- What decides the numbers: the items you wear, your talents / demon / priority list, and the sim's settings.
-- Not the numbers read off the character sheet themselves: they move with every buff, and the worth of an item hardly does.
local function currentKey()
  local parts = {}
  for i = 1, #slots do
    local link = try(GetInventoryItemLink, 'player', slots[i].id)
    parts[#parts + 1] = type(link) == 'string' and link or '-'
  end
  if WL.char then
    local build = WL.characterBuildNow()
    if build then parts[#parts + 1] = WL.encodeBuild(build) end
    local snap = copy(WL.settingsSnapshot(WL.cfg))
    snap.gear = nil
    parts[#parts + 1] = WL.jsonEncode(snap)
    parts[#parts + 1] = tostring(WL.db.options.stone) .. tostring(WL.itemFights())
  end
  return table.concat(parts, '\1')
end

local function short(v)
  if v < 0.05 and v > -0.05 then return '0' end
  if v >= 9.95 or v <= -9.95 then return string.format('%.0f', v) end
  return string.format('%.1f', v)
end
local function show(key)
  if not overlay then return end
  local fresh = state.key == key
  for i = 1, #slots do
    local id = slots[i].id
    local fs, w = labels[id], state.worth[id]
    local link = try(GetInventoryItemLink, 'player', id)
    if type(link) ~= 'string' then fs:SetText('')
    elseif fresh and w and w.link == link then
      -- green: worth something; grey: nothing the sim counts, or less than the margin of the run
      if math.abs(w.dps) <= math.max(w.err or 0, 0.05) then fs:SetText('|cff999999' .. short(math.max(0, w.dps)) .. '|r')
      else fs:SetText('|cff40ff40' .. short(w.dps) .. '|r') end
    elseif WL.backgroundRunning() or not fresh then fs:SetText('|cff999999..|r')
    else fs:SetText('') end
  end
  if fresh and state.base then
    total:SetText(string.format('|cffffd100%.0f DPS|r', state.base))
    sub:SetText('sim, ' .. (state.n or 0) .. ' fights')
  elseif WL.backgroundRunning() then total:SetText('|cff999999...|r'); sub:SetText('simming')
  else total:SetText(''); sub:SetText('') end
end

-- The background work: the DPS as you are, then every worn item against an empty slot. Each finished number is kept at
-- once, so work that has to give way to a sim you start loses only the item it was on.
local function start(key)
  if not inCombat() then WL.doReadCharacter() end          -- your numbers as they are now (not in combat: then the last read)
  if not WL.char then failedKey = key; return false end    -- not a Warlock, or nothing could be read: no retry until the items change
  key = currentKey()                                       -- the read may have been the first: the key now holds talents and settings
  local build = WL.characterBuildNow()
  if not build or #WL.validateBuild(build, true) > 0 then failedKey = key; return false end
  local cfg, race, n = WL.characterConfig(), WL.raceKey(), WL.itemFights()
  if state.key ~= key then state = { key = key, base = nil, baseRes = nil, worth = {}, n = n } end
  local todo = {}
  for i = 1, #slots do
    local id = slots[i].id
    local link = try(GetInventoryItemLink, 'player', id)
    if type(link) == 'string' and not (state.worth[id] and state.worth[id].link == link) then todo[#todo + 1] = { id = id, link = link } end
  end
  if state.base and #todo == 0 then return false end
  local st = state
  return WL.startJob('Character sheet', n * (#todo + 1), function()
    if not st.baseRes then
      st.baseRes = WL.simulate(build, race, cfg, { iterations = n })
      st.base = st.baseRes.dps
    end
    local base = st.baseRes
    for i = 1, #todo do
      local t = todo[i]
      local item = WL.readItemInfo(t.link)
      local gear, delta = WL.gearWithSwap(cfg.gear, {}, { item.stats }, cfg)
      local any = false
      for _, v in pairs(delta) do if v ~= 0 then any = true end end
      if not any then
        st.worth[t.id] = { link = t.link, dps = 0, err = 0 }   -- nothing on it that the sim counts: no need to play fights
      else
        if t.id == 16 then gear.weaponIsSword = false end
        local c = copy(cfg)
        c.gear = gear
        local r = WL.simulate(build, race, c, { iterations = n })
        local sum, sq = 0, 0
        for f = 1, n do local d = base.dpsList[f] - r.dpsList[f]; sum = sum + d; sq = sq + d * d end
        local mean = sum / n
        st.worth[t.id] = { link = t.link, dps = mean, err = 1.96 * math.sqrt(math.max(0, sq / n - mean * mean) / math.max(1, n - 1)) }
      end
    end
  end, true)
end
WL.onBackgroundEnd = function(ok, err)
  if not ok then failedKey = state.key; WL.lastError = 'character sheet numbers: ' .. tostring(err) end
  if overlay and overlay:IsShown() then show(currentKey()) end   -- the last number at once, not at the watcher's next look
end

local watcher, since = CreateFrame('Frame'), 0
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.3 then return end
  since = 0
  if not WL.db then return end
  if not enabled() then
    if overlay and overlay:IsShown() then overlay:Hide(); WL.cancelBackground() end
    return
  end
  if not PaperDollFrame or not PaperDollFrame.IsVisible or not PaperDollFrame:IsVisible() then return end
  if not create() then return end
  if not overlay:IsShown() then overlay:Show() end
  local key = currentKey()
  -- Something to work out (items, talents or settings changed; or the work gave way to a sim of yours and is not done)?
  -- Then start, unless you are fighting, a sim of yours is running, or this set of items could not be simmed.
  local pending = key ~= state.key or not state.base
  if not pending then
    for i = 1, #slots do
      local link = try(GetInventoryItemLink, 'player', slots[i].id)
      local w = state.worth[slots[i].id]
      if type(link) == 'string' and not (w and w.link == link) then pending = true; break end
    end
  end
  if pending and not WL.backgroundRunning() and not WL.jobRunning() and not inCombat() and key ~= failedKey then
    start(key)
    key = currentKey()
  end
  show(key)
end)

-- for /wsim dump
function WL.sheetState() return { base = state.base, worth = state.worth, n = state.n } end
