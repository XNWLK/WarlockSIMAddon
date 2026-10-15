-- Sim an item: your character as it is against your character with one item changed.
--   * A small "Sim this item" button under the item link window (the one that opens when you click an item link in chat).
--   * Shift+right-click (the click can be chosen: options.itemClick) on an item in your bags, on your character sheet, at a vendor, in a loot or quest window: a small panel
--     opens at the mouse and the sim starts at once. An item you are wearing is simmed against an empty slot: what it is
--     worth to you.
-- The panel is the addon's own frame, parented to the screen. Nothing of the game's is changed; the Alt+click comes in
-- through a post-hook on the game's own handler for modified item clicks (hooksecurefunc: runs after it, cannot block it).
local ADDON, WL = ...
local copy = WL.copy

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function try(f, ...)
  if type(f) ~= 'function' then return nil end
  local ok, a, b, c, d, e, g = pcall(f, ...)
  if not ok or isSecret(a) then return nil end
  return a, b, c, d, e, g
end

local CR = { hit = 8, crit = 11, haste = 20 }               -- the game's numbers for spell hit, spell crit and spell haste rating
local function toPct(stat, rating)
  local id = (stat == 'hit' and CR_HIT_SPELL) or (stat == 'crit' and CR_CRIT_SPELL) or (stat == 'haste' and CR_HASTE_SPELL) or CR[stat]
  local v = try(GetCombatRatingBonusForCombatRatingValue, id, rating)
  if type(v) == 'number' and v > 0 then return v end
  return rating
end
local function gameString(name) local v = _G[name]; return type(v) == 'string' and v or nil end

-- What the game says about an item: name, where it goes, its stats, and what was read (kept for /wsim dump).
local function readItem(link)
  local item = { link = link }
  item.name = try(C_Item.GetItemNameByID, link) or link:match('%[(.-)%]') or 'this item'
  local _, _, _, equipLoc, _, classID, subclassID = try(C_Item.GetItemInfoInstant, link)
  item.equipLoc, item.classID, item.subclassID = equipLoc, classID, subclassID
  item.isSword = classID == 2 and (subclassID == 7 or subclassID == 8)
  local api = try(C_Item.GetItemStats, link)
  local lines = {}
  local data = C_TooltipInfo and try(C_TooltipInfo.GetHyperlink, link)
  local types = Enum and Enum.TooltipDataLineType
  local enchanted = gameString('ENCHANTED_TOOLTIP_LINE')
  enchanted = enchanted and enchanted:match('^(.-)%%s')
  if type(data) == 'table' and type(data.lines) == 'table' then
    for i = 1, #data.lines do
      local l = data.lines[i]
      local text = type(l) == 'table' and l.leftText
      if type(text) == 'string' and not isSecret(text) then
        local skip = types and (l.type == types.ItemEnchantmentPermanent or l.type == types.GemSocket)
        if not skip and enchanted and enchanted ~= '' and text:gsub('|c%x%x%x%x%x%x%x%x', ''):sub(1, #enchanted) == enchanted then skip = true end
        if not skip then lines[#lines + 1] = text end
      end
    end
  end
  item.stats, item.unknown = WL.itemStats(type(api) == 'table' and api or nil, lines, gameString, toPct)
  item.raw = { api = type(api) == 'table' and api or nil, lines = lines }
  return item
end
local function equipped(slot)
  local link = try(GetInventoryItemLink, 'player', slot)
  if type(link) ~= 'string' then return nil end
  return readItem(link)
end
local function itemID(link) return link and tonumber(link:match('item:(%d+)')) end

-- An item you wear against an empty slot: what it is worth.
local function worth(item)
  local main = try(GetInventoryItemLink, 'player', 16)
  return { { worth = true, label = item.name, olds = { item.stats }, items = {}, mainHand = type(main) == 'string' and itemID(main) == itemID(item.link) } }
end
-- The swaps an item stands for: one per slot it could go into. `worn` = the item was clicked on the character sheet.
-- Returns a list of { label, olds = { stats, ... }, ... } or nil and a plain sentence.
local function alternatives(item, worn)
  local slots = WL.ITEM_SLOTS[item.equipLoc or '']
  if not slots then return nil, 'This is not something you can wear.' end
  if worn then return worth(item) end
  local list = {}
  local main = equipped(16)
  local mainIs2H = main and main.equipLoc == 'INVTYPE_2HWEAPON'
  if item.equipLoc == 'INVTYPE_2HWEAPON' then
    local off = equipped(17)
    local olds, names = {}, {}
    if main then olds[#olds + 1] = main.stats; names[#names + 1] = main.name end
    if off then olds[#olds + 1] = off.stats; names[#names + 1] = off.name end
    if main and itemID(main.link) == itemID(item.link) then return worth(item) end
    list[1] = { label = #names > 0 and table.concat(names, ' and ') or 'empty hands', olds = olds, mainHand = true, items = { main, off } }
    return list
  end
  if slots[1] == 17 and mainIs2H then return nil, 'You hold a two-hand weapon: an off-hand item cannot be compared on its own.' end
  local same = 0
  for i = 1, #slots do
    local old = equipped(slots[i])
    if old and itemID(old.link) == itemID(item.link) then same = same + 1
    else
      list[#list + 1] = { label = old and old.name or 'the empty slot', olds = old and { old.stats } or {}, items = { old }, mainHand = slots[i] == 16 }
    end
  end
  if #list == 0 then return worth(item) end
  if same > 0 and #list == 1 then list[1].note = 'You wear one of these already; this is it in your other slot.' end
  return list
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the sim
-- ---------------------------------------------------------------------------------------------------------------------
local baseCache                                           -- the last "as you are" run, reused while nothing changed
local results = {}                                        -- what was shown for an item: results[key], key = link (+ "|worn")

local function itemFights() return math.max(20, math.min(2000, math.floor(tonumber(WL.db.options.itemFights) or 150))) end
WL.readItemInfo, WL.itemFights = readItem, itemFights     -- also used by the numbers on the character sheet (SheetUI.lua)

-- worn = the item was clicked on the character sheet (sim it against an empty slot).
-- Returns true when a sim was started, or false and a plain sentence.
function WL.simItem(link, worn)
  if WL.jobRunning() then return false, 'A sim is running. Wait for it, or type /wsim stop.' end
  if not (InCombatLockdown and InCombatLockdown()) then
    local ch, err = WL.doReadCharacter()
    if not ch and not WL.char then return false, err end
  elseif not WL.char then
    return false, 'You are in combat and your character has not been read yet. Try again after the fight.'
  end
  local item = readItem(link)
  local alts, why = alternatives(item, worn)
  if not alts then return false, why end
  local build, notes = WL.characterBuildNow()
  if not build then return false, notes[1] end
  local errs = WL.validateBuild(build, true)
  if #errs > 0 then return false, errs[1] end
  local cfg, race, n = WL.characterConfig(), WL.raceKey(), itemFights()
  local key = n .. race .. WL.encodeBuild(build) .. WL.jsonEncode(WL.settingsSnapshot(cfg))
  local cached = baseCache and baseCache.key == key and baseCache.res or nil
  for i = 1, #alts do
    local a = alts[i]
    a.gear, a.delta = WL.gearWithSwap(cfg.gear, a.worth and {} or item.stats, a.olds, cfg)
    if a.mainHand then a.gear.weaponIsSword = (not a.worth and item.isSword) and true or false end
  end
  -- kept for /wsim dump: what the game returned for the items of the last comparison
  WL.db.lastItem = { link = link, name = item.name, equipLoc = item.equipLoc, stats = item.stats, unknown = item.unknown, raw = item.raw, worn = worn or nil, against = {} }
  for i = 1, #alts do
    for _, old in pairs(alts[i].items or {}) do
      WL.db.lastItem.against[#WL.db.lastItem.against + 1] = { link = old.link, name = old.name, stats = old.stats, unknown = old.unknown, raw = old.raw }
    end
  end
  return WL.startJob('Item', n * (#alts + (cached and 0 or 1)), function(j)
    local function onFight() j.done = j.done + 1 end
    local base = cached or WL.simulate(build, race, cfg, { iterations = n, onFight = onFight })
    baseCache = { key = key, res = base }
    for i = 1, #alts do
      local c = copy(cfg)
      c.gear = alts[i].gear
      local before = j.done
      -- same fights on both sides, so the difference is taken fight by fight: its margin is far smaller than that of
      -- either DPS, and this side can stop as soon as it is exact enough (the run as you are always plays all of them)
      local r = WL.simulate(build, race, c, { iterations = n, onFight = onFight, stop = WL.pairedStop(base.dpsList) })
      j.done = before + n
      alts[i].dps = r.dps
      alts[i].diff, alts[i].err, alts[i].n = WL.pairedDiff(base.dpsList, r.dpsList)
    end
    j.result.kind, j.result.link, j.result.worn, j.result.item, j.result.alts, j.result.base, j.result.n = 'item', link, worn, item, alts, base, n
  end)
end

local function resultText(res)
  local lines = {}
  for i = 1, #res.alts do
    local a = res.alts[i]
    local pct = res.base.dps > 0 and 100 * a.diff / res.base.dps or 0
    if a.worth then
      -- an item you wear, against an empty slot: the loss without it is what it is worth
      lines[#lines + 1] = string.format('You are wearing this. It is worth:\n|cff40ff40%.1f DPS|r (%.1f%% of your damage)  |cff999999+-%.1f|r', -a.diff, -pct, a.err)
      lines[#lines + 1] = '|cffaaaaaaIt gives: ' .. WL.describeStats(res.item.stats, false) .. '|r'
    else
      local verdict
      if math.abs(a.diff) <= a.err then verdict = string.format('|cffcccccc%+.1f DPS: about the same|r', a.diff)
      elseif a.diff > 0 then verdict = string.format('|cff40ff40%+.1f DPS|r (%+.1f%%)', a.diff, pct)
      else verdict = string.format('|cffff5050%+.1f DPS|r (%+.1f%%)', a.diff, pct) end
      lines[#lines + 1] = string.format('Instead of %s:\n%s  |cff999999+-%.1f|r', a.label, verdict, a.err)
      lines[#lines + 1] = '|cffaaaaaaChange: ' .. WL.describeStats(a.delta, true) .. '|r'
    end
    if a.note then lines[#lines + 1] = '|cffaaaaaa' .. a.note .. '|r' end
  end
  -- effects the sim does not know (use effects, procs, odd equip lines): on the new item and on what it would replace
  local function notCounted(name, unknown)
    if not unknown or #unknown == 0 then return end
    local first = unknown[1]
    if #first > 60 then first = first:sub(1, 57) .. '...' end
    lines[#lines + 1] = '|cffffb060Not counted on ' .. name .. ': ' .. first .. (#unknown > 1 and (' (and ' .. (#unknown - 1) .. ' more)') or '') .. '|r'
  end
  notCounted(res.item.name, res.item.unknown)
  local seen = {}
  for i = 1, #res.alts do
    for _, old in pairs(res.alts[i].items or {}) do
      if not seen[old.link] then seen[old.link] = true; notCounted(old.name, old.unknown) end
    end
  end
  local fewest = res.n
  for i = 1, #res.alts do if res.alts[i].n and res.alts[i].n < fewest then fewest = res.alts[i].n end end
  lines[#lines + 1] = string.format('|cff777777%.1f DPS as you are. %s Enchants and set bonuses are not counted.%s|r', res.base.dps,
    fewest < res.n and string.format('Exact enough after %d of %d fights.', fewest, res.n) or string.format('%d fights.', res.n),
    (WL.char and (WL.char.level or 60) < 60) and ' Played at level 60.' or '')
  return table.concat(lines, '\n')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the panel: under the item link window, or pinned at the mouse after an Alt+click
-- ---------------------------------------------------------------------------------------------------------------------
local panel
local shown                                               -- what the panel is showing: { link, worn, pinned, name }
local running                                             -- the key of the item whose sim is running
local lastRefLink                                         -- the item the item link window showed last time we looked
local WAIT = '|cffaaaaaaPlaying the fights...|r'
local function keyOf(link, worn) return link .. (worn and '|worn' or '') end

local function layout(text)
  local head = (shown and shown.pinned) and 18 or 0
  panel.title:SetShown(head > 0); panel.close:SetShown(head > 0)
  panel.button:ClearAllPoints(); panel.button:SetPoint('TOPLEFT', 6, -5 - head)
  panel.text:ClearAllPoints(); panel.text:SetPoint('TOPLEFT', 8, -28 - head)
  panel.text:SetText(text or '')
  local h = (text and text ~= '') and ((panel.text.GetStringHeight and panel.text:GetStringHeight() or 40) + 8) or 0
  panel:SetHeight(30 + head + h)
end
local function start()
  if not shown then return end
  local ok, err = WL.simItem(shown.link, shown.worn)
  if ok then running = keyOf(shown.link, shown.worn); layout(WAIT)
  else layout('|cffffb060' .. tostring(err) .. '|r') end
  if WL.refresh then WL.refresh() end
end
local function create()
  panel = CreateFrame('Frame', 'WarlockSimItemPanel', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
  panel:SetFrameStrata('TOOLTIP')
  panel:SetSize(260, 30)
  panel:SetClampedToScreen(true); panel:EnableMouse(true)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.05, 0.04, 0.08, 0.95); panel:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
  end
  panel.title = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
  panel.title:SetPoint('TOPLEFT', 8, -7); panel.title:SetWidth(220); panel.title:SetJustifyH('LEFT')
  if panel.title.SetWordWrap then panel.title:SetWordWrap(false) end
  panel.close = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
  panel.close:SetSize(22, 22); panel.close:SetPoint('TOPRIGHT', 1, 1)
  panel.close:SetScript('OnClick', function()
    shown = nil; panel:Hide()
    lastRefLink = nil                                     -- if the item link window is still open, its own panel comes back
  end)
  panel.button = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
  panel.button:SetSize(120, 20)
  panel.button:SetText('Sim this item')
  panel.button:SetScript('OnClick', start)
  panel.progress = panel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  panel.progress:SetPoint('LEFT', panel.button, 'RIGHT', 8, 0)
  panel.text = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  panel.text:SetWidth(244)
  panel.text:SetJustifyH('LEFT'); panel.text:SetJustifyV('TOP')
  if panel.text.SetSpacing then panel.text:SetSpacing(2) end
  panel:Hide()
end
-- Shows the panel for an item. anchor = nil: at the mouse (pinned, with the item's name and a close button).
local function show(link, worn, underRef)
  if not panel then create() end
  local name = link:match('%[(.-)%]') or 'Item'
  shown = { link = link, worn = worn, pinned = not underRef, name = name }
  panel.title:SetText(name)
  panel.button:SetText(worn and 'Sim its worth' or 'Sim this item')
  panel:ClearAllPoints()
  if underRef then
    panel:SetPoint('TOPLEFT', ItemRefTooltip, 'BOTTOMLEFT', 0, 2)
  else
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if type(scale) ~= 'number' or scale <= 0 then scale = 1 end
    panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', (x or 0) / scale + 18, (y or 0) / scale - 6)
  end
  local key = keyOf(link, worn)
  layout(results[key] or (running == key and WAIT) or '')
  panel:Show()
end

-- The item shown in the item link window right now, if it is one you can wear.
local function refLink()
  local tt = ItemRefTooltip
  if not tt or not tt.IsShown or not tt:IsShown() then return nil end
  local link
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    local _, l = try(TooltipUtil.GetDisplayedItem, tt)
    link = l
  end
  if not link and tt.GetItem then
    local _, l = try(tt.GetItem, tt)
    link = l
  end
  if type(link) ~= 'string' or isSecret(link) or not link:find('item:', 1, true) then return nil end
  local _, _, _, equipLoc = try(C_Item.GetItemInfoInstant, link)
  if not WL.ITEM_SLOTS[equipLoc or ''] then return nil end
  return link
end
local function enabled() return WL.db ~= nil and WL.db.options.itemClick ~= 'off' end
-- Is the click that is happening right now the one chosen for item sims ("shift-right", "alt-right", ...)?
-- The mouse button and each of Shift, Ctrl and Alt must be exactly as the choice names them.
local function clickMatches()
  local bind = WL.db.options.itemClick or 'shift-right'
  local button = GetMouseButtonClicked and GetMouseButtonClicked()
  if type(button) == 'string' and (button == 'RightButton') ~= (bind:find('right', 1, true) ~= nil) then return false end
  local alt = IsAltKeyDown and IsAltKeyDown() and true or false
  local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
  local ctrl = IsControlKeyDown and IsControlKeyDown() and true or false
  return alt == (bind:find('alt', 1, true) ~= nil) and shift == (bind:find('shift', 1, true) ~= nil) and ctrl == (bind:find('ctrl', 1, true) ~= nil)
end

local watcher, since = CreateFrame('Frame'), 0
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.2 then return end
  since = 0
  if not enabled() then
    if panel and panel:IsShown() then panel:Hide() end
    shown = nil
    return
  end
  -- the item link window: its panel follows it; a newly opened link takes the panel over from a pinned item
  local link = refLink()
  if link ~= lastRefLink then
    lastRefLink = link
    if link then show(link, nil, true)
    elseif shown and not shown.pinned then shown = nil; panel:Hide() end
  end
  if not shown or not panel then return end
  local done, total = WL.jobProgress()
  panel.progress:SetText((done and running == keyOf(shown.link, shown.worn)) and string.format('%d%%', math.floor(total > 0 and 100 * done / total or 0)) or '')
  if panel.button.SetEnabled then panel.button:SetEnabled(not WL.jobRunning()) end
end)

-- The chosen click on an item (bags, character sheet, vendor, loot, quest reward: everything the game sends through its
-- handler for modified item clicks). Any other click keeps its usual meaning only.
local function onModifiedItemClick(link, itemLocation)
  if not enabled() or type(link) ~= 'string' or isSecret(link) then return end
  if not clickMatches() then return end
  if not link:find('item:', 1, true) then return end
  local _, _, _, equipLoc = try(C_Item.GetItemInfoInstant, link)
  if not WL.ITEM_SLOTS[equipLoc or ''] then return end
  -- items on the character sheet are handled by the other hook below (the game does not send every click on them here)
  if type(itemLocation) == 'table' and itemLocation.IsEquipmentSlot and try(itemLocation.IsEquipmentSlot, itemLocation) then return end
  show(link, false, false)
  start()
end
-- The chosen click on a slot of the character sheet: the item you wear there, against an empty slot. Its own hook,
-- because the game ends some clicks on a slot (Shift + right-click, its "socket this item" click) before they reach the
-- general handler above.
local function onCharacterSlotClick(slot)
  if not enabled() or not clickMatches() then return end
  local id = type(slot) == 'table' and slot.GetID and try(slot.GetID, slot)
  if type(id) ~= 'number' then return end
  local link = try(GetInventoryItemLink, 'player', id)
  if type(link) ~= 'string' or not link:find('item:', 1, true) then return end
  local _, _, _, equipLoc = try(C_Item.GetItemInfoInstant, link)
  if not WL.ITEM_SLOTS[equipLoc or ''] then return end
  show(link, true, false)
  start()
end
-- Post-hooks (hooksecurefunc): they run after the game's own function and cannot change or block what it does.
local hooked = {}
local function hookClicks()
  if not hooksecurefunc then return end
  if not hooked.items and HandleModifiedItemClick then
    hooked.items = true
    hooksecurefunc('HandleModifiedItemClick', function(link, itemLocation) pcall(onModifiedItemClick, link, itemLocation) end)
  end
  if not hooked.slots and PaperDollItemSlotButton_OnModifiedClick then
    hooked.slots = true
    hooksecurefunc('PaperDollItemSlotButton_OnModifiedClick', function(slot) pcall(onCharacterSlotClick, slot) end)
  end
end
hookClicks()
local late = CreateFrame('Frame')                           -- once more at login, in case the game made its functions after this file was read
late:RegisterEvent('PLAYER_LOGIN')
late:SetScript('OnEvent', hookClicks)

-- called by the window's code when a job ends
function WL.onItemResult(res, err)
  local key = (res and keyOf(res.link, res.worn)) or running
  running = nil
  if not key then return end
  results[key] = res and resultText(res) or ('|cffffb060' .. tostring(err) .. '|r')
  if panel and shown and keyOf(shown.link, shown.worn) == key then layout(results[key]) end
end
