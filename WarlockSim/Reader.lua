-- Reads your character from the game: race, level, talents, demon, the character sheet's spell numbers and the buffs
-- on you. Everything is read with care: the Forever client hides numbers from addons in combat ("secret values"), so
-- nothing is read then, and every call is wrapped so that a missing function or a hidden value becomes a note, not an error.
local ADDON, WL = ...

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
-- f(...) -> its results, or nil when the function is missing, fails, or its first result is hidden
-- every value the game returns is passed on (GetItemInfoInstant's weapon sub-class is its 7th: a fixed list of six lost it)
local function pass(ok, ...)
  if not ok or isSecret((...)) then return nil end
  return ...
end
local function try(f, ...)
  if type(f) ~= 'function' then return nil end
  return pass(pcall(f, ...))
end
local function num(v) return (type(v) == 'number' and not isSecret(v)) and v or nil end

local RACE_BY_FILE = { Human = 'human', Gnome = 'gnome', Orc = 'orc', Scourge = 'undead', Undead = 'undead', Troll = 'troll' }
local PET_BY_NPC = { ['416'] = 'imp', ['1863'] = 'succubus', ['417'] = 'felhunter', ['1860'] = 'voidwalker' }
-- Demonic Sacrifice's buff per demon (names and spell ids of the classic game; checked by both).
local SACRIFICE_AURAS = {
  { 'imp', 18789, 'Burning Wish' }, { 'voidwalker', 18790, 'Fel Stamina' }, { 'succubus', 18791, 'Touch of Shadow' }, { 'felhunter', 18792, 'Fel Energy' },
}
-- Raid buffs of the sim that can sit on you as a buff, with the names they go by.
local BUFF_NAMES = {
  arcaneIntellect = { 'Arcane Intellect', 'Arcane Brilliance' },
  markOfTheWild = { 'Mark of the Wild', 'Gift of the Wild' },
  fortitude = { 'Power Word: Fortitude', 'Prayer of Fortitude' },
  divineSpirit = { 'Divine Spirit', 'Prayer of Spirit' },
  blessingOfKings = { 'Blessing of Kings', 'Greater Blessing of Kings' },
  blessingOfWisdom = { 'Blessing of Wisdom', 'Greater Blessing of Wisdom' },
  blessingOfSalvation = { 'Blessing of Salvation', 'Greater Blessing of Salvation' },
  concentrationAura = { 'Concentration Aura' },
  manaSpring = { 'Mana Spring', 'Mana Spring Totem' },
  graceOfAir = { 'Grace of Air', 'Grace of Air Totem' },
  tranquilAir = { 'Tranquil Air', 'Tranquil Air Totem' },
  moonkinAura = { 'Moonkin Aura', 'Moonkin Form' },
  scrollOfAgility = { 'Agility' },
}

local function spellName(id)
  if not id then return nil end
  local n = C_Spell and try(C_Spell.GetSpellName, id)
  return type(n) == 'string' and n or nil
end

-- The buffs on you: a list of { name, id }.
local function readAuras()
  local list = {}
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list, false end
  for i = 1, 80 do
    local a = try(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HELPFUL')
    if type(a) ~= 'table' then break end
    local name, id = a.name, a.spellId
    if type(name) == 'string' and not isSecret(name) then list[#list + 1] = { name = name, id = num(id) } end
  end
  return list, true
end

-- Talent points per sim talent: { key = points }, how they were found, and what the game returned (for /wsim dump).
local function readTalents(raw)
  local talents, found = {}, 0
  local configID
  if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetActiveSpecGroup then
    local group = try(C_SpecializationInfo.GetActiveSpecGroup)
    if group then configID = num((try(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group))) end
    raw.specGroup = group
  end
  if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then configID = num((try(C_ClassTalents.GetActiveConfigID))) end
  raw.configID = configID
  if not configID or not C_Traits then return talents, 'The game did not give out your talents (no talent set found).' end

  -- every node of your talent tree: rank by node id, by definition id, by spell id and by name
  local byNode, byDef, bySpell, byName, nodes = {}, {}, {}, {}, 0
  local info = try(C_Traits.GetConfigInfo, configID)
  local treeIDs = type(info) == 'table' and info.treeIDs or {}
  raw.treeIDs = treeIDs
  raw.nodes = {}
  for _, treeID in ipairs(treeIDs) do
    local ids = try(C_Traits.GetTreeNodes, treeID)
    for _, nodeID in ipairs(type(ids) == 'table' and ids or {}) do
      local node = try(C_Traits.GetNodeInfo, configID, nodeID)
      if type(node) == 'table' then
        local rank = num(node.activeRank) or num(node.currentRank) or num(node.ranksPurchased) or 0
        byNode[nodeID] = rank
        nodes = nodes + 1
        local entryID = (type(node.activeEntry) == 'table' and node.activeEntry.entryID) or (type(node.entryIDs) == 'table' and node.entryIDs[1])
        local entry = entryID and try(C_Traits.GetEntryInfo, configID, entryID)
        local defID = type(entry) == 'table' and entry.definitionID
        local def = defID and try(C_Traits.GetDefinitionInfo, defID)
        local sid = type(def) == 'table' and (def.spellID or def.overriddenSpellID)
        local name = (type(def) == 'table' and type(def.overrideName) == 'string' and def.overrideName ~= '' and def.overrideName) or spellName(sid)
        if defID then byDef[defID] = rank end
        if sid then bySpell[sid] = rank end
        if name then byName[name] = rank end
        if rank > 0 or nodes <= 6 then raw.nodes[#raw.nodes + 1] = { node = nodeID, rank = rank, max = num(node.maxRanks), def = defID, spell = sid, name = name } end
      end
    end
  end
  raw.nodeCount = nodes
  local how = {}
  for i = 1, #WL.TALENTS do
    local t = WL.TALENTS[i]
    local rank, via = byNode[t.wid], 'node'
    if rank == nil and t.def then rank, via = byDef[t.def], 'definition' end
    if rank == nil and t.spell then rank, via = bySpell[t.spell], 'spell' end
    if rank == nil then rank, via = byName[t.name], 'name' end
    if rank == nil and t.wid then                                         -- a node the tree walk did not list: ask for it directly
      local node = try(C_Traits.GetNodeInfo, configID, t.wid)
      if type(node) == 'table' and num(node.ID) and node.ID ~= 0 then rank, via = num(node.activeRank) or num(node.ranksPurchased) or 0, 'node (direct)' end
    end
    if rank ~= nil then
      found = found + 1
      how[via] = (how[via] or 0) + 1
      if rank > 0 then talents[t.key] = math.min(rank, t.ranks) end
    end
  end
  raw.talentsFound, raw.talentsHow = found, how
  if found == 0 then return talents, 'The game gave out a talent tree, but none of its talents could be matched to the sim\'s (' .. nodes .. ' talents seen).' end
  if found < #WL.TALENTS then return talents, (#WL.TALENTS - found) .. ' of the sim\'s ' .. #WL.TALENTS .. ' talents were not found in your talent tree; they count as 0 points.' end
  return talents, nil
end

-- Returns the character (a table), or nil and a plain sentence why not.
function WL.readCharacter()
  if InCombatLockdown and InCombatLockdown() then return nil, 'You are in combat. The game hides your numbers from addons then - read again after the fight.' end
  local raw, notes = {}, {}
  local c = { raw = raw, notes = notes, readAt = time and time() or 0 }
  local _, class = try(UnitClass, 'player')
  c.class = class
  if class ~= 'WARLOCK' then return nil, 'This character is not a Warlock.' end
  c.name, c.realm, c.level = try(UnitName, 'player'), try(GetRealmName), num((try(UnitLevel, 'player')))
  local _, raceFile = try(UnitRace, 'player')
  raw.raceFile = raceFile
  c.raceKey = RACE_BY_FILE[raceFile or ''] or WL.BASELINE_RACE
  if not RACE_BY_FILE[raceFile or ''] then notes[#notes + 1] = 'Your race (' .. tostring(raceFile) .. ') is not one the sim knows: no racials are counted.' end

  -- the character sheet
  local sheet = {}
  local STAT = { agi = 2, sta = 3, int = 4, spi = 5 }
  for k, i in pairs(STAT) do
    local base, eff = try(UnitStat, 'player', i)
    sheet[k] = num(eff) or num(base)
    raw['stat' .. i] = { num(base), num(eff) }
  end
  local sps = {}
  for school = 2, 7 do sps[school] = num((try(GetSpellBonusDamage, school))) end
  raw.spellPower = sps
  local spMin
  for school = 2, 7 do if sps[school] and (not spMin or sps[school] < spMin) then spMin = sps[school] end end
  sheet.sp, sheet.spShadow, sheet.spFire = spMin, sps[6], sps[3]
  local crits, critMin = {}, num((try(GetSpellCritChance)))
  crits[1] = critMin
  for school = 2, 7 do
    crits[school] = num((try(GetSpellCritChance, school)))
    if crits[school] and (not critMin or crits[school] < critMin) then critMin = crits[school] end
  end
  raw.crit = crits
  sheet.crit = critMin
  local hitRating, hitMod = num((try(GetCombatRatingBonus, CR_HIT_SPELL or 8))), num((try(GetSpellHitModifier)))
  raw.hit = { hitRating, hitMod }
  sheet.hit = (hitRating or hitMod) and ((hitRating or 0) + (hitMod or 0)) or nil
  sheet.haste = num((try(UnitSpellHaste, 'player')))
  local regenBase, regenCasting = try(GetManaRegen)
  raw.manaRegen = { num(regenBase), num(regenCasting) }
  sheet.mp5 = num(regenCasting) and regenCasting * 5 or nil
  sheet.pierce = num((try(GetSpellPenetration)))
  sheet.maxHealth, sheet.maxMana = num((try(UnitHealthMax, 'player'))), num((try(UnitPowerMax, 'player', 0)))
  c.sheet = sheet
  local missing = {}
  local NEED = { { 'int', 'Intellect' }, { 'spi', 'Spirit' }, { 'sta', 'Stamina' }, { 'sp', 'spell power' }, { 'crit', 'spell crit' }, { 'hit', 'spell hit' }, { 'haste', 'haste' } }
  for i = 1, #NEED do if sheet[NEED[i][1]] == nil then missing[#missing + 1] = NEED[i][2] end end
  if #missing > 0 then notes[#notes + 1] = 'The game did not give out: ' .. table.concat(missing, ', ') .. '. They count as 0 - set them by hand with a settings code.' end

  -- talents
  local talents, talentNote = readTalents(raw)
  c.talents = talents
  if talentNote then notes[#notes + 1] = talentNote end

  -- demon
  if try(UnitExists, 'pet') then
    local guid = try(UnitGUID, 'pet')
    raw.petGUID = guid
    if type(guid) == 'string' then
      local _, _, _, _, _, npc = strsplit('-', guid)
      c.pet = PET_BY_NPC[npc or '']
      if not c.pet then notes[#notes + 1] = 'Your pet is not a demon the sim knows; it is left out.' end
    end
  end

  -- buffs on you
  local auras, aurasOk = readAuras()
  raw.auras = auras
  if not aurasOk then notes[#notes + 1] = 'The buffs on you could not be read: buffs that give stats count as part of your gear.' end
  local buffs, used = {}, {}
  for key, names in pairs(BUFF_NAMES) do
    local b = WL.DEFAULT_CONFIG.buffs[key]
    local own = b and spellName(b.id)
    for i = 1, #auras do
      local a = auras[i]
      local hit = (b and a.id == b.id) or (own and a.name == own)
      if not hit then for j = 1, #names do if a.name == names[j] then hit = true end end end
      if hit and b then buffs[key] = true; used[i] = true end
    end
  end
  for s = 1, #SACRIFICE_AURAS do
    local sa = SACRIFICE_AURAS[s]
    local own = spellName(sa[2])
    for i = 1, #auras do
      if auras[i].id == sa[2] or auras[i].name == sa[3] or (own and auras[i].name == own) then c.sacrifice = sa[1]; used[i] = true end
    end
  end
  c.buffsOnYou = buffs
  local others = {}
  for i = 1, #auras do if not used[i] then others[#others + 1] = auras[i].name end end
  c.otherAuras = others

  -- weapon: a sword (Human racial) and a temporary effect on it (stone, oil)
  local itemID = num((try(GetInventoryItemID, 'player', 16)))
  if itemID and C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, _, _, classID, subclassID = try(C_Item.GetItemInfoInstant, itemID)
    raw.weapon = { itemID, classID, subclassID }
    c.isSword = classID == 2 and (subclassID == 7 or subclassID == 8)
  end
  if C_Item and C_Item.GetWeaponEnchantInfo then
    local hasMain = try(C_Item.GetWeaponEnchantInfo)
    c.weaponEffect = hasMain and true or false
  end

  c.state = { raceKey = c.raceKey, talents = c.talents, pet = c.pet, sacrifice = c.sacrifice, buffs = buffs, isSword = c.isSword, hitHasSuppression = false }
  return c
end
