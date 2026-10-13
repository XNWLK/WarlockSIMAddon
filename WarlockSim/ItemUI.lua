-- A small "Sim this item" button under the item link window (the one that opens when you click an item link in chat).
-- It plays your character as it is, and again with that one item in place of the one you wear in its slot.
-- The panel is the addon's own frame, only anchored to the game's window: nothing of the game's is changed or hooked.
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

-- The swaps an item stands for: one per slot it could go into. Returns a list of { label, olds = { stats, ... }, isSword }
-- or nil and a plain sentence.
local function alternatives(item)
  local slots = WL.ITEM_SLOTS[item.equipLoc or '']
  if not slots then return nil, 'This is not something you can wear.' end
  local list = {}
  local main = equipped(16)
  local mainIs2H = main and main.equipLoc == 'INVTYPE_2HWEAPON'
  if item.equipLoc == 'INVTYPE_2HWEAPON' then
    local off = equipped(17)
    local olds, names = {}, {}
    if main then olds[#olds + 1] = main.stats; names[#names + 1] = main.name end
    if off then olds[#olds + 1] = off.stats; names[#names + 1] = off.name end
    if main and itemID(main.link) == itemID(item.link) then return nil, 'You are wearing this item.' end
    list[1] = { label = #names > 0 and table.concat(names, ' and ') or 'empty hands', olds = olds, isSword = item.isSword, items = { main, off } }
    return list
  end
  if slots[1] == 17 and mainIs2H then return nil, 'You hold a two-hand weapon: an off-hand item cannot be compared on its own.' end
  local same = 0
  for i = 1, #slots do
    local old = equipped(slots[i])
    if old and itemID(old.link) == itemID(item.link) then same = same + 1
    else
      list[#list + 1] = { label = old and old.name or 'the empty slot', olds = old and { old.stats } or {}, items = { old },
                          isSword = slots[i] == 16 and item.isSword or nil, mainHand = slots[i] == 16 }
    end
  end
  if #list == 0 then return nil, 'You are wearing this item.' end
  if same > 0 and #list == 1 then list[1].note = 'You wear one of these already; this is it in your other slot.' end
  return list
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the sim
-- ---------------------------------------------------------------------------------------------------------------------
local baseCache                                           -- the last "as you are" run, reused while nothing changed
local results = {}                                        -- item id -> the text shown for it

local function itemFights() return math.max(20, math.min(2000, math.floor(tonumber(WL.db.options.itemFights) or 150))) end

-- Returns true when a sim was started, or false and a plain sentence.
function WL.simItem(link)
  if WL.jobRunning() then return false, 'A sim is running. Wait for it, or type /wsim stop.' end
  if not (InCombatLockdown and InCombatLockdown()) then
    local ch, err = WL.doReadCharacter()
    if not ch and not WL.char then return false, err end
  elseif not WL.char then
    return false, 'You are in combat and your character has not been read yet. Try again after the fight.'
  end
  local item = readItem(link)
  local alts, why = alternatives(item)
  if not alts then return false, why end
  local build, notes = WL.characterBuildNow()
  if not build then return false, notes[1] end
  local errs = WL.validateBuild(build, true)
  if #errs > 0 then return false, errs[1] end
  local cfg, race, n = WL.characterConfig(), WL.raceKey(), itemFights()
  local key = n .. race .. WL.encodeBuild(build) .. WL.jsonEncode(WL.settingsSnapshot(cfg))
  local cached = baseCache and baseCache.key == key and baseCache.res or nil
  for i = 1, #alts do
    alts[i].gear, alts[i].delta = WL.gearWithSwap(cfg.gear, item.stats, alts[i].olds, cfg)
    if alts[i].mainHand or item.equipLoc == 'INVTYPE_2HWEAPON' then alts[i].gear.weaponIsSword = item.isSword and true or false end
  end
  -- kept for /wsim dump: what the game returned for the items of the last comparison
  WL.db.lastItem = { link = link, name = item.name, equipLoc = item.equipLoc, stats = item.stats, unknown = item.unknown, raw = item.raw, against = {} }
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
      local r = WL.simulate(build, race, c, { iterations = n, onFight = onFight })
      -- same fights on both sides, so the difference is taken fight by fight: its margin is far smaller than that of either DPS
      local sum, sq = 0, 0
      for f = 1, n do local d = r.dpsList[f] - base.dpsList[f]; sum = sum + d; sq = sq + d * d end
      local mean = sum / n
      alts[i].dps, alts[i].diff = r.dps, mean
      alts[i].err = 1.96 * math.sqrt(math.max(0, sq / n - mean * mean) / math.max(1, n - 1))
    end
    j.result.kind, j.result.link, j.result.item, j.result.alts, j.result.base, j.result.n = 'item', link, item, alts, base, n
  end)
end

local function resultText(res)
  local lines = {}
  for i = 1, #res.alts do
    local a = res.alts[i]
    local pct = res.base.dps > 0 and 100 * a.diff / res.base.dps or 0
    local verdict
    if math.abs(a.diff) <= a.err then verdict = string.format('|cffcccccc%+.1f DPS: about the same|r', a.diff)
    elseif a.diff > 0 then verdict = string.format('|cff40ff40%+.1f DPS|r (%+.1f%%)', a.diff, pct)
    else verdict = string.format('|cffff5050%+.1f DPS|r (%+.1f%%)', a.diff, pct) end
    lines[#lines + 1] = string.format('Instead of %s:\n%s  |cff999999+-%.1f|r', a.label, verdict, a.err)
    lines[#lines + 1] = '|cffaaaaaaChange: ' .. WL.describeStats(a.delta, true) .. '|r'
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
  lines[#lines + 1] = string.format('|cff777777%.1f DPS as you are. %d fights. Enchants and set bonuses are not counted.|r', res.base.dps, res.n)
  return table.concat(lines, '\n')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the panel under the item link window
-- ---------------------------------------------------------------------------------------------------------------------
local panel, shownLink, runningLink
local function setText(text)
  panel.text:SetText(text or '')
  local h = (text and text ~= '') and ((panel.text.GetStringHeight and panel.text:GetStringHeight() or 40) + 8) or 0
  panel:SetHeight(30 + h)
end
local function create()
  panel = CreateFrame('Frame', 'WarlockSimItemPanel', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
  panel:SetFrameStrata('TOOLTIP')
  panel:SetSize(260, 30)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.05, 0.04, 0.08, 0.95); panel:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
  end
  panel.button = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
  panel.button:SetSize(120, 20); panel.button:SetPoint('TOPLEFT', 6, -5)
  panel.button:SetText('Sim this item')
  panel.button:SetScript('OnClick', function()
    if not shownLink then return end
    local ok, err = WL.simItem(shownLink)
    if ok then runningLink = shownLink; setText('|cffaaaaaaPlaying the fights...|r')
    else setText('|cffffb060' .. tostring(err) .. '|r') end
    if WL.refresh then WL.refresh() end
  end)
  panel.progress = panel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  panel.progress:SetPoint('LEFT', panel.button, 'RIGHT', 8, 0)
  panel.text = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  panel.text:SetPoint('TOPLEFT', 8, -28); panel.text:SetWidth(244)
  panel.text:SetJustifyH('LEFT'); panel.text:SetJustifyV('TOP')
  if panel.text.SetSpacing then panel.text:SetSpacing(2) end
  panel:Hide()
end

-- The item shown in the item link window right now, if it is one you can wear.
local function currentLink()
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

local watcher, since = CreateFrame('Frame'), 0
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.2 then return end
  since = 0
  if not WL.db or WL.db.options.itemButton == false then
    if panel and panel:IsShown() then panel:Hide() end
    return
  end
  local link = currentLink()
  if not link then
    if panel and panel:IsShown() then panel:Hide() end
    shownLink = nil
    return
  end
  if not panel then create() end
  if link ~= shownLink then
    shownLink = link
    panel:ClearAllPoints()
    panel:SetPoint('TOPLEFT', ItemRefTooltip, 'BOTTOMLEFT', 0, 2)
    setText(results[link] or (runningLink == link and '|cffaaaaaaPlaying the fights...|r') or '')
    panel:Show()
  end
  local done, total = WL.jobProgress()
  panel.progress:SetText((done and runningLink == link) and string.format('%d%%', math.floor(total > 0 and 100 * done / total or 0)) or '')
  if panel.button.SetEnabled then panel.button:SetEnabled(not WL.jobRunning()) end
end)

-- called by the window's code when a job ends
function WL.onItemResult(res, err)
  local link = (res and res.link) or runningLink
  runningLink = nil
  if not link then return end
  results[link] = res and resultText(res) or ('|cffffb060' .. tostring(err) .. '|r')
  if panel and shownLink == link then setText(results[link]) end
end
