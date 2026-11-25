-- Sim an item: your character as it is against your character with one item changed.
--   * A small "Sim this item" button under the item link window (the one that opens when you click an item link in chat).
--   * Shift+right-click (the click can be chosen: options.itemClick) on an item in your bags, on your character sheet, at a vendor, in a loot or quest window: a small panel
--     opens at the mouse and the sim starts at once. An item you are wearing is simmed against an empty slot: what it is
--     worth to you.
--   * A small "Sim" button beside each loot roll popup (Need / Greed) of an item you can wear: the popup's item icon
--     takes left clicks only, so the chosen click never reaches the game's handler there.
-- The panel is the addon's own frame, parented to the screen. Nothing of the game's is changed; the Alt+click comes in
-- through a post-hook on the game's own handler for modified item clicks (hooksecurefunc: runs after it, cannot block it).
local ADDON, WL = ...
if WL.notWarlock then return end   -- not a Warlock: nothing of the addon loads (Class.lua)
local copy = WL.copy

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
-- every value the game returns is passed on (GetItemInfoInstant's weapon sub-class is its 7th: a fixed list of six lost it)
local function pass(ok, ...)
  if not ok or isSecret((...)) then return nil end
  return ...
end
local function try(f, ...)
  if type(f) ~= 'function' then return nil end
  return pass(pcall(f, ...))
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
  local _, _, _, equipLoc, icon, classID, subclassID = try(C_Item.GetItemInfoInstant, link)
  item.equipLoc, item.classID, item.subclassID, item.icon = equipLoc, classID, subclassID, icon
  -- item level, required level, icon and item set (GetItemInfo: 4th, 5th, 10th and 16th value); the level the item really has
  local info = { try(C_Item.GetItemInfo, link) }
  item.ilvl, item.req, item.setID = info[4], info[5], info[16]
  if info[10] ~= nil then item.icon = info[10] end
  local eff = try(C_Item.GetDetailedItemLevelInfo, link)
  if type(eff) == 'number' and eff > 0 then item.ilvl = eff end
  local api = try(C_Item.GetItemStats, link)
  local lines, enchants = {}, {}
  local data = C_TooltipInfo and try(C_TooltipInfo.GetHyperlink, link)
  local types = Enum and Enum.TooltipDataLineType
  local enchanted = gameString('ENCHANTED_TOOLTIP_LINE')
  enchanted = enchanted and enchanted:match('^(.-)%%s')
  if type(data) == 'table' and type(data.lines) == 'table' then
    for i = 1, #data.lines do
      local l = data.lines[i]
      local text = type(l) == 'table' and l.leftText
      if type(text) == 'string' and not isSecret(text) then
        local plain = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        local isEnchant = (types and l.type == types.ItemEnchantmentPermanent) or (enchanted and enchanted ~= '' and plain:sub(1, #enchanted) == enchanted)
        if isEnchant then
          -- kept apart: an item's own stats never include its enchant (the gear code sends the enchant on its own)
          if enchanted and enchanted ~= '' and plain:sub(1, #enchanted) == enchanted then plain = plain:sub(#enchanted + 1) end
          enchants[#enchants + 1] = (plain:gsub('^%s+', ''))
        elseif not (types and l.type == types.GemSocket) then lines[#lines + 1] = text end
      end
    end
  end
  item.enchantLines = enchants
  item.stats, item.unknown = WL.itemStats(type(api) == 'table' and api or nil, lines, gameString, toPct)
  local id = tonumber(link:match('item:(%d+)'))
  if id and WL.TRINKET_FX[id] then                              -- its use effect, proc or bonus is counted in the fight
    local fx = WL.TRINKET_FX[id]
    item.unknown, item.fx = {}, fx
    if fx.stats then                                            -- a zone trinket: its own stats, as the website counts them
      local s = {}
      for k, v in pairs(fx.stats) do s[(k == 'critPct' and 'crit') or (k == 'hitPct' and 'hit') or (k == 'hastePct' and 'haste') or k] = v end
      item.stats = s
    end
  elseif id and WL.ITEM_FX and WL.ITEM_FX[id] then               -- other gear whose effect the fight plays (Blade of Eternal Darkness)
    item.unknown, item.fx = {}, WL.ITEM_FX[id]
  end
  item.raw = { api = type(api) == 'table' and api or nil, lines = lines }
  return item
end
local function equipped(slot)
  local link = try(GetInventoryItemLink, 'player', slot)
  if type(link) ~= 'string' then return nil end
  return readItem(link)
end
local function itemID(link) return link and tonumber(link:match('item:(%d+)')) end

-- ---------------------------------------------------------------------------------------------------------------------
-- the gear code: what you wear, for the website's gear builder ("WFG1:", format agreed with the sim; see Codes.lua)
-- ---------------------------------------------------------------------------------------------------------------------
local GEAR_KEYS = { 'head', 'neck', 'shoulder', 'shirt', 'chest', 'waist', 'legs', 'feet', 'wrist', 'hands', 'finger1', 'finger2',
                    'trinket1', 'trinket2', 'back', 'mainHand', 'offHand', 'ranged', 'tabard' }   -- = the game's inventory slots 1 to 19
local ENCHANTABLE = { head = true, neck = true, shoulder = true, back = true, chest = true, wrist = true, hands = true, waist = true, legs = true, feet = true,
                      mainHand = true, offHand = true }   -- Forever: necklace enchants, belt augments, off-hand enchants
local ITEM_TYPE = { INVTYPE_HEAD = 'head', INVTYPE_NECK = 'neck', INVTYPE_SHOULDER = 'shoulder', INVTYPE_CLOAK = 'back', INVTYPE_CHEST = 'chest',
  INVTYPE_ROBE = 'chest', INVTYPE_BODY = 'shirt', INVTYPE_TABARD = 'tabard', INVTYPE_WRIST = 'wrist', INVTYPE_HAND = 'hands', INVTYPE_WAIST = 'waist',
  INVTYPE_LEGS = 'legs', INVTYPE_FEET = 'feet', INVTYPE_FINGER = 'finger', INVTYPE_TRINKET = 'trinket', INVTYPE_WEAPON = 'oneHand',
  INVTYPE_WEAPONMAINHAND = 'mainHand', INVTYPE_2HWEAPON = 'twoHand', INVTYPE_WEAPONOFFHAND = 'offHand', INVTYPE_HOLDABLE = 'offHand',
  INVTYPE_SHIELD = 'offHand', INVTYPE_RANGED = 'ranged', INVTYPE_RANGEDRIGHT = 'ranged', INVTYPE_THROWN = 'ranged', INVTYPE_RELIC = 'ranged' }
local WEAPON_TYPE = { [7] = 'sword', [8] = 'sword', [15] = 'dagger', [10] = 'staff', [4] = 'mace', [5] = 'mace' }   -- weapon sub-classes
local QUALITY = { [0] = 'poor', [1] = 'common', [2] = 'uncommon', [3] = 'rare', [4] = 'epic', [5] = 'legendary' }
-- the addon's item stats -> the sim's Sheet (gear) names (pierce = Spell Pierce, spellPen = Spell Penetration: the same keys)
local CODE_STAT = { hit = 'hitPct', crit = 'critPct', haste = 'hastePct' }
local function codeStats(s)
  local o = {}
  for k, v in pairs(s or {}) do if v ~= 0 then o[CODE_STAT[k] or k] = math.floor(v * 100 + 0.5) / 100 end end
  return o
end
-- the stats exactly as the game gives them: { ITEM_MOD_SPELL_POWER = 36, ... } (the game's keys without "_SHORT")
local function rawStats(api)
  if type(api) ~= 'table' then return nil end
  local o, any = {}, false
  for k, v in pairs(api) do
    if type(k) == 'string' and type(v) == 'number' and v ~= 0 then o[(k:gsub('_SHORT$', ''))] = v; any = true end
  end
  return any and o or nil
end
-- one item of the code: id, name, slot, quality, stats, and what the game says besides (level, icon, set, raw stats)
local function codeItem(item, link)
  local e = { id = itemID(link), name = item.name, slot = ITEM_TYPE[item.equipLoc or ''], stats = codeStats(item.stats) }
  e.quality = QUALITY[try(C_Item.GetItemQualityByID, link) or -1]
  if item.classID == 2 then e.weapon = WEAPON_TYPE[item.subclassID or -1] or 'other' end
  if type(item.ilvl) == 'number' and item.ilvl > 0 then e.ilvl = item.ilvl end
  if type(item.req) == 'number' and item.req > 0 then e.req = item.req end
  if type(item.icon) == 'number' then e.iconId = item.icon
  elseif type(item.icon) == 'string' and item.icon ~= '' then e.icon = (item.icon:match('([^\\/]+)$') or item.icon):gsub('%.%a+$', ''):lower() end
  if type(item.setID) == 'number' and item.setID > 0 then e.set = item.setID end
  e.raw = rawStats(item.raw and item.raw.api)
  return e
end
-- the bags the game counts (0 = the backpack); a bag slot without a bag has no slots
local function bagItems()
  local list = {}
  if not (C_Container and C_Container.GetContainerNumSlots) then return list end
  for bag = 0, 4 do                                       -- the backpack and the four bag slots
    local n = try(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (type(n) == 'number' and n or 0) do
      local link = try(C_Container.GetContainerItemLink, bag, slot)
      if type(link) == 'string' then
        local item = readItem(link)
        if ITEM_TYPE[item.equipLoc or ''] then list[#list + 1] = codeItem(item, link) end
      end
    end
  end
  return list
end
-- Returns the code, the number of items and enchants, notes (enchants not understood) and the number of items from the
-- bags (options.gearBags), or nil and a plain sentence.
function WL.gearCode()
  if InCombatLockdown and InCombatLockdown() then return nil, 'You are in combat. The game hides item details from addons then - make the code after the fight.' end
  local out, notes, items, enchants, seen = { v = 1, items = {}, enchants = {} }, {}, 0, 0, {}
  for inv = 1, #GEAR_KEYS do
    local key, link = GEAR_KEYS[inv], try(GetInventoryItemLink, 'player', inv)
    if type(link) == 'string' then
      local item = readItem(link)
      out.items[key] = codeItem(item, link)
      items = items + 1
      local ench = { link = link }
      if ENCHANTABLE[key] and #item.enchantLines > 0 then
        local text = table.concat(item.enchantLines, ' / ')
        local stats, understood = WL.enchantStats(text, gameString, toPct)
        out.enchants[key] = { id = tonumber(link:match('item:%d+:(%d+)')), name = text, stats = codeStats(stats) }
        enchants = enchants + 1
        if not understood then notes[#notes + 1] = 'Enchant not understood, counted as 0: ' .. text end
        ench.text, ench.stats, ench.understood = text, stats, understood
      end
      seen[key] = ench
    end
  end
  WL.db.lastGear = seen                                   -- for /wsim dump: the links and how each enchant was read
  local bags = 0
  if WL.db.options.gearBags then
    out.bag = bagItems()
    bags = #out.bag
    if bags == 0 then out.bag = nil end
  end
  return WL.encodeGear(out), items, enchants, notes, bags
end

-- An item you wear against an empty slot: what it is worth.
local function worth(item)
  local main = try(GetInventoryItemLink, 'player', 16)
  local slot, wornLink                                     -- the slot it is in (for trinket and weapon effects), the worn copy's link
  local list = WL.ITEM_SLOTS[item.equipLoc or ''] or {}
  for i = 1, #list do
    local l = try(GetInventoryItemLink, 'player', list[i])
    if not slot and type(l) == 'string' and itemID(l) == itemID(item.link) then slot, wornLink = list[i], l end
  end
  -- its enchant is read from the copy you wear (a link from chat may have none)
  return { { worth = true, label = item.name, olds = { item.stats }, items = {}, enchFrom = { wornLink and readItem(wornLink) or item }, slot = slot,
             mainHand = type(main) == 'string' and itemID(main) == itemID(item.link) } }
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
    list[1] = { label = #names > 0 and table.concat(names, ' and ') or 'empty hands', olds = olds, mainHand = true, slot = 16, items = { main, off } }
    return list
  end
  if slots[1] == 17 and mainIs2H then return nil, 'You hold a two-hand weapon: an off-hand item cannot be compared on its own.' end
  local same = 0
  for i = 1, #slots do
    local old = equipped(slots[i])
    if old and itemID(old.link) == itemID(item.link) then same = same + 1
    else
      list[#list + 1] = { label = old and old.name or 'the empty slot', olds = old and { old.stats } or {}, items = { old }, mainHand = slots[i] == 16, slot = slots[i] }
    end
  end
  if #list == 0 then return worth(item) end
  if same > 0 and #list == 1 then list[1].note = 'You wear one of these already; this is it in your other slot.' end
  return list
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the sim
-- ---------------------------------------------------------------------------------------------------------------------
local bases = {}                                          -- the runs "as you are", reused while nothing changed: bases[''] as you are,
                                                          -- bases[<enchants>] without the enchants named; bases.key = what they were played with
local results = {}                                        -- what was shown for an item: results[key], key = link (+ "|worn")

local function itemFights() return math.max(20, math.min(2000, math.floor(tonumber(WL.db.options.itemFights) or 150))) end
WL.readItemInfo, WL.itemFights = readItem, itemFights     -- also used by the numbers on the character sheet (SheetUI.lua)

-- Spell Penetration on what you wear, items and enchants: the character sheet has no number for it (its "Spell
-- Piercing" is Spell Pierce), so reading the character adds it up from the items (Reader.lua).
function WL.wornSpellPen()
  local sum = 0
  for inv = 1, 19 do
    local link = try(GetInventoryItemLink, 'player', inv)
    if type(link) == 'string' then
      local item = readItem(link)
      sum = sum + (item.stats.spellPen or 0)
      if #item.enchantLines > 0 then sum = sum + (WL.enchantStats(table.concat(item.enchantLines, ' / '), gameString, toPct).spellPen or 0) end
    end
  end
  return sum
end

-- The enchants on the items a swap takes off (an item you wear: on itself). Both sides of the comparison leave them
-- out, so the items are compared as they are without enchants (Xn: "make it ignore the enchant that is on my gear").
-- Returns nil when there is none, else { stats = { stats, ... }, names = { 'Revelation on Witchblade', ... },
-- fx = true when it is the main hand's enchant with an effect in the fight, unread = { texts not read: still counted } }.
local function enchantsOn(items, mainHand)
  local e = { stats = {}, names = {}, unread = {}, fx = false }
  for _, it in pairs(items or {}) do
    local eid = type(it.link) == 'string' and tonumber(it.link:match('item:%d+:(%d+)')) or nil
    local fx = eid and WL.ENCHANT_FX[eid] or nil
    local lines = it.enchantLines or {}
    if #lines > 0 or fx then
      local text = #lines > 0 and table.concat(lines, ' / ') or fx.name
      local stats, understood = WL.enchantStats(text, gameString, toPct)
      e.stats[#e.stats + 1] = stats
      e.names[#e.names + 1] = text .. ' on ' .. (it.name or 'your item')
      if fx and mainHand and WL.char and WL.char.worn and WL.char.worn.mainEnchant == eid then e.fx = true end
      if not understood and not fx then e.unread[#e.unread + 1] = text end
    end
  end
  if #e.names == 0 then return nil end
  return e
end

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
  local key = n .. race .. WL.encodeBuild(build) .. WL.jsonEncode(WL.settingsSnapshot(cfg)) .. WL.fxKey(cfg)
  if bases.key ~= key then bases = { key = key } end
  local B, plan, planned = bases, {}, {}                   -- plan: the runs as you are still to play
  for i = 1, #alts do
    local a = alts[i]
    -- the enchant on what comes off is left out on both sides: as you are without it, and with the new item without it
    a.ench = enchantsOn(a.enchFrom or a.items, a.mainHand)
    local start, w = cfg.gear, WL.char and WL.char.worn
    a.sub = ''
    if a.ench then
      start = WL.gearWithSwap(cfg.gear, {}, a.ench.stats, cfg)
      if a.ench.fx then w = copy(w); w.mainEnchant = nil end
      a.sub = table.concat(a.ench.names, '|') .. (a.ench.fx and '|fx' or '')
    end
    if not B[a.sub] and not planned[a.sub] then
      planned[a.sub] = true
      plan[#plan + 1] = { sub = a.sub, gear = start, gb = w and WL.wornGearBuilder(w) or nil }
    end
    a.gear, a.delta = WL.gearWithSwap(start, a.worth and {} or item.stats, a.olds, cfg)
    if WL.char and a.slot then
      local after = WL.wornSwap(w, a.slot, (not a.worth) and itemID(item.link) or nil)
      if item.equipLoc == 'INVTYPE_2HWEAPON' and not a.worth then after = WL.wornSwap(after, 17, nil) end   -- the off hand comes off too
      a.set = w and type(w.items) == 'table' and WL.setChange(w.items, after.items) or nil
      if a.set then                                            -- it completes or breaks a set bonus: the item alone (the sets as
        local alone = copy(after)                              -- they were), then with the set bonus's change as well
        alone.items = w.items
        a.fxSwap, a.gb = true, WL.wornGearBuilder(alone)
        a.setGear = WL.gearWithSwap(a.gear, a.set.gain, { a.set.lose }, cfg)
        a.setGb = WL.wornGearBuilder(after)
      elseif WL.FX_SLOTS[a.slot] then                         -- a trinket or weapon: its effect goes with it
        a.fxSwap, a.gb = true, WL.wornGearBuilder(after)
      end
    end
  end
  -- kept for /wsim dump: what the game returned for the items of the last comparison
  WL.db.lastItem = { link = link, name = item.name, equipLoc = item.equipLoc, stats = item.stats, unknown = item.unknown, raw = item.raw, worn = worn or nil, against = {} }
  for i = 1, #alts do
    for _, old in pairs(alts[i].items or {}) do
      WL.db.lastItem.against[#WL.db.lastItem.against + 1] = { link = old.link, name = old.name, stats = old.stats, unknown = old.unknown, raw = old.raw }
    end
    if alts[i].ench then WL.db.lastItem.ignored = alts[i].ench.names end
  end
  local sets = 0
  for i = 1, #alts do if alts[i].set then sets = sets + 1 end end
  return WL.startJob('Item', n * (#alts + #plan + sets), function(j)
    local function onFight() j.done = j.done + 1 end
    for i = 1, #plan do
      local p, c = plan[i], cfg
      if p.sub ~= '' then c = copy(cfg); c.gear = p.gear; c.gearBuilder = p.gb end
      B[p.sub] = WL.simulate(build, race, c, { iterations = n, onFight = onFight })
    end
    for i = 1, #alts do
      local c, base = copy(cfg), B[alts[i].sub]
      c.gear = alts[i].gear
      if alts[i].fxSwap then c.gearBuilder = alts[i].gb end
      local before = j.done
      -- same fights on both sides, so the difference is taken fight by fight: its margin is far smaller than that of
      -- either DPS, and this side can stop as soon as it is exact enough (the run as you are always plays all of them)
      local r = WL.simulate(build, race, c, { iterations = n, onFight = onFight, stop = WL.pairedStop(base.dpsList) })
      j.done = before + n
      alts[i].dps, alts[i].base = r.dps, base
      alts[i].diff, alts[i].err, alts[i].n = WL.pairedDiff(base.dpsList, r.dpsList)
      if alts[i].set then                                      -- the same with the set bonus's change: three numbers
        local c2 = copy(cfg)
        c2.gear, c2.gearBuilder = alts[i].setGear, alts[i].setGb
        before = j.done
        local r2 = WL.simulate(build, race, c2, { iterations = n, onFight = onFight, stop = WL.pairedStop(base.dpsList) })
        j.done = before + n
        -- all three over the same fights, so item + set bonus = total
        local m = math.min(#r.dpsList, #r2.dpsList)
        local function cut(l) local o = {}; for f = 1, m do o[f] = l[f] end; return o end
        local A, B1, C1 = cut(base.dpsList), cut(r.dpsList), cut(r2.dpsList)
        alts[i].itemDiff, alts[i].itemErr = WL.pairedDiff(A, B1)
        alts[i].setDiff, alts[i].setErr = WL.pairedDiff(B1, C1)
        alts[i].diff, alts[i].err, alts[i].n = WL.pairedDiff(A, C1)
        alts[i].dps = r2.dps
      end
    end
    j.result.kind, j.result.link, j.result.worn, j.result.item, j.result.alts, j.result.n = 'item', link, worn, item, alts, n
    -- the line "as you are": the plain run when a comparison used it, else the one without the enchant
    j.result.base, j.result.plain = alts[1].base, false
    for i = 1, #alts do if alts[i].sub == '' then j.result.base, j.result.plain = alts[i].base, true end end
  end)
end

-- "Item: +5.0 DPS  Set bonus: +7.3 DPS" (signed, coloured), and what the set bonus change is
local function signed(v, err)
  local col = math.abs(v) <= err and 'cccccc' or (v > 0 and '40ff40' or 'ff5050')
  return string.format('|cff%s%+.1f DPS|r |cff999999+-%.1f|r', col, v, err)
end
local function setLines(lines, a, sign)
  lines[#lines + 1] = 'Item: ' .. signed(sign * a.itemDiff, a.itemErr) .. '   Set bonus: ' .. signed(sign * a.setDiff, a.setErr)
  local d = sign > 0 and a.set.delta or {}
  if sign < 0 then for k, v in pairs(a.set.delta) do d[k] = -v end end
  local what = WL.describeStats(d, true)
  local any = false
  for _, v in pairs(d) do if v ~= 0 then any = true end end
  lines[#lines + 1] = '|cffaaaaaaSet: ' .. table.concat(a.set.names, ', ') .. ' (' .. (any and what or '') .. (a.set.fx and ((any and ', ' or '') .. 'its effect in the fight') or '') .. ')|r'
end
local function resultText(res)
  local lines = {}
  for i = 1, #res.alts do
    local a = res.alts[i]
    local baseDps = (a.base or res.base).dps
    local pct = baseDps > 0 and 100 * a.diff / baseDps or 0
    if a.worth then
      -- an item you wear, against an empty slot: the loss without it is what it is worth
      lines[#lines + 1] = string.format('You are wearing this. It is worth%s:\n|cff40ff40%.1f DPS|r (%.1f%% of your damage)  |cff999999+-%.1f|r', a.set and ' in total' or '', -a.diff, -pct, a.err)
      if a.set then setLines(lines, a, -1) end
      lines[#lines + 1] = '|cffaaaaaaIt gives: ' .. WL.describeStats(res.item.stats, false) .. '|r'
    else
      local verdict
      if math.abs(a.diff) <= a.err then verdict = string.format('|cffcccccc%+.1f DPS: about the same|r', a.diff)
      elseif a.diff > 0 then verdict = string.format('|cff40ff40%+.1f DPS|r (%+.1f%%)', a.diff, pct)
      else verdict = string.format('|cffff5050%+.1f DPS|r (%+.1f%%)', a.diff, pct) end
      lines[#lines + 1] = string.format('Instead of %s:\n%s%s  |cff999999+-%.1f|r', a.label, a.set and 'Total: ' or '', verdict, a.err)
      if a.set then setLines(lines, a, 1) end
      lines[#lines + 1] = '|cffaaaaaaChange: ' .. WL.describeStats(a.delta, true) .. '|r'
    end
    if a.note then lines[#lines + 1] = '|cffaaaaaa' .. a.note .. '|r' end
    if a.ench then
      lines[#lines + 1] = '|cffffb060Enchant ignored: ' .. table.concat(a.ench.names, ', ') .. '. Both sides are simmed without it.|r'
      if #a.ench.unread > 0 then lines[#lines + 1] = '|cffffb060Could not be read, so still counted: ' .. table.concat(a.ench.unread, ', ') .. '|r' end
    end
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
  lines[#lines + 1] = string.format('|cff777777%.1f DPS as you are%s. %s Enchants are not counted.%s|r', res.base.dps,
    res.plain == false and ' (without the enchant)' or '',
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

-- Loot roll icons take left clicks only. Add a Sim button beside a roll for an item with a supported equipment slot.
local rollButtons = {}
local function simRollLink(link)
  if type(link) ~= 'string' or isSecret(link) or not link:find('item:', 1, true) then return nil end
  local _, _, _, equipLoc = try(C_Item.GetItemInfoInstant, link)
  if not WL.ITEM_SLOTS[equipLoc or ''] then return nil end
  return link
end
local function rollLink(f)
  if not f or not f.IsShown or not f:IsShown() then return nil end
  local id = f.rollID
  if id == nil or isSecret(id) or not GetLootRollItemLink then return nil end
  return simRollLink(try(GetLootRollItemLink, id))
end
local function rollButton(parent, linkOnClick)
  local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
  b:SetSize(44, 22); b:SetText('Sim'); b:SetFrameStrata('DIALOG')
  b:SetScript('OnClick', function(self)
    local link = self.link
    if linkOnClick then link = linkOnClick(self) end
    if not link then return end
    show(link, false, false)
    start()
  end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText("Xn's Warlock Sim")
    GameTooltip:AddLine('Sims this item against the one you wear in its slot.', 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local addonRollButtons = {}
local function addonRollLink(id, link)
  if type(id) ~= 'number' or isSecret(id) then return end
  if isSecret(link) then return end
  if not link then link = try(GetLootRollItemLink, id) end
  return simRollLink(link), id
end
local function ellesmereRollLink(row)
  local data = row.data
  if type(data) ~= 'table' or data.closed or data.done then return end
  return addonRollLink(data.rollID, data.link)
end
local function elvRollLink(bar)
  return addonRollLink(bar.rollID, bar.button and bar.button.link)
end
local function elvRollEdges(bar)
  local icon = bar.button
  local questIcon = icon and icon.questIcon
  local left, right = questIcon and questIcon:IsShown() and questIcon or icon or bar, bar
  -- ElvUI can put the Need/Greed/Pass controls outside a narrow bar.
  local needLeft, passRight = bar.need and bar.need:GetLeft(), bar.pass and bar.pass:GetRight()
  local xLeft, xRight = left:GetLeft(), right:GetRight()
  if needLeft and xLeft and needLeft < xLeft then left = bar.need end
  if passRight and xRight and passRight > xRight then right = bar.pass end
  return left, right
end
local function positionAddonRollButton(b, row, edges)
  -- A fixed-height button could overlap the one on the next compact roll bar.
  local height = row:GetHeight()
  local scale = height > 0 and math.min(1, height / b:GetHeight()) or 1
  if b.rowScale ~= scale then b:SetScale(scale); b.rowScale = scale end

  local needed = (b:GetWidth() + 2) * scale
  local anchor, onRight = row, false
  if edges then
    -- ElvUI's clickable item icon is outside the bar on the left.
    local left, right = edges(row)
    local xRight, screenRight = right:GetRight(), UIParent:GetRight()
    onRight = not xRight or not screenRight
      or (xRight + needed) * row:GetEffectiveScale() <= screenRight * UIParent:GetEffectiveScale()
    anchor = onRight and right or left
  else
    local left = row:GetLeft()
    onRight = left ~= nil and left < needed
  end
  local y = 0
  if anchor ~= row then
    -- ElvUI can draw its roll controls above the bar. Keep Sim centered on the row.
    local _, rowY = row:GetCenter()
    local _, anchorY = anchor:GetCenter()
    if rowY and anchorY then
      y = (rowY * row:GetEffectiveScale() - anchorY * anchor:GetEffectiveScale()) / b:GetEffectiveScale()
    end
  end
  if b.rollAnchor == anchor and b.onRight == onRight and b.rollY == y then return end
  b:ClearAllPoints()
  if onRight then b:SetPoint('LEFT', anchor, 'RIGHT', 2, y)
  else b:SetPoint('RIGHT', anchor, 'LEFT', -2, y) end
  b.rollAnchor, b.onRight, b.rollY = anchor, onRight, y
end
local function updateAddonRollButton(row, linkFor, on, edges)
  local link, id
  if on and row:IsVisible() then link, id = linkFor(row) end
  local b = addonRollButtons[row]
  if link and not b then
    b = rollButton(row, function(self)
      if not enabled() or not self:IsVisible() then return end
      -- The row may have ended or been reused since the last update.
      local current, rollID = linkFor(row)
      if rollID == self.rollID and current == self.link then return current end
    end)
    addonRollButtons[row] = b
  end
  if b then
    b.link, b.rollID = link, id
    if link then positionAddonRollButton(b, row, edges) end
    b:SetShown(link ~= nil)
  end
end
local function updateAddonRollButtons(on)
  -- EllesmereUI QoL pools rows under an anchor. Its preview rows have no roll ID.
  local anchor = _G.EllesmereUILootRolls
  if anchor and anchor:IsVisible() then
    for _, row in ipairs({ anchor:GetChildren() }) do
      updateAddonRollButton(row, ellesmereRollLink, on)
    end
  end
  -- ElvUI creates its numbered bars in order up to the user's configured limit.
  local i, bar = 1, _G.ElvUI_LootRollFrame1
  while bar do
    updateAddonRollButton(bar, elvRollLink, on, elvRollEdges)
    i = i + 1
    bar = _G['ElvUI_LootRollFrame' .. i]
  end
end

local function updateRollButtons()
  local on = enabled()
  for i = 1, 8 do
    local f = _G['GroupLootFrame' .. i]
    if not f and not rollButtons[i] then break end
    local link = on and rollLink(f) or nil
    local b = rollButtons[i]
    if link and not b then b = rollButton(UIParent); rollButtons[i] = b end
    if b then
      if link then
        if b.owner ~= f then b:ClearAllPoints(); b:SetPoint('RIGHT', f, 'LEFT', -2, 0); b.owner = f end
        b.link = link
        if not b:IsShown() then b:Show() end
      elseif b:IsShown() then b.link = nil; b:Hide() end
    end
  end
  updateAddonRollButtons(on)
end

local watcher, since = CreateFrame('Frame'), 0
watcher:SetScript('OnUpdate', function(_, elapsed)
  since = since + (elapsed or 0)
  if since < 0.2 then return end
  since = 0
  updateRollButtons()
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

-- The last 10 item sims of this character, newest first (WarlockSimDB.chars[...].items): the window's Items page lists
-- them, a click sims the item again. { link, worn, text } - text is the short answer ("+14.2 DPS", one per ring / trinket).
local HISTORY = 10
function WL.itemHistory()
  local e = WL.charStore(false)
  return (e and type(e.items) == 'table') and e.items or {}
end
local function shortAnswer(res)
  local parts = {}
  for i = 1, #res.alts do
    local a = res.alts[i]
    local v = a.worth and -a.diff or a.diff
    local col = math.abs(a.diff) <= a.err and 'cccccc' or ((v > 0 or a.worth) and '40ff40' or 'ff5050')
    parts[#parts + 1] = string.format('|cff%s%s%.1f|r', col, (v >= 0 and not a.worth) and '+' or '', v)
  end
  return (res.alts[1] and res.alts[1].worth and 'worth ' or '') .. table.concat(parts, ' / ') .. ' DPS'
end
local function remember(res)
  local e = WL.charStore(true)
  if not e or not res.link or not res.alts or #res.alts == 0 then return end
  local list = type(e.items) == 'table' and e.items or {}
  for i = #list, 1, -1 do if list[i].link == res.link and (list[i].worn and true or false) == (res.worn and true or false) then table.remove(list, i) end end
  table.insert(list, 1, { link = res.link, worn = res.worn and true or nil, text = shortAnswer(res) })
  for i = #list, HISTORY + 1, -1 do list[i] = nil end
  e.items = list
end
-- a click on the Items page: the panel opens at the mouse and the item is simmed again
function WL.simItemAgain(i)
  local h = WL.itemHistory()[i]
  if not h then return end
  show(h.link, h.worn, false)
  start()
end

-- called by the window's code when a job ends
function WL.onItemResult(res, err)
  local key = (res and keyOf(res.link, res.worn)) or running
  running = nil
  if not key then return end
  results[key] = res and resultText(res) or ('|cffffb060' .. tostring(err) .. '|r')
  if res then remember(res) end
  if panel and shown and keyOf(shown.link, shown.worn) == key then layout(results[key]) end
end
