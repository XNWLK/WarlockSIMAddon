// Checks the addon's "from the character sheet back to gear" step: for every ready build, race and a few buff sets the
// sim works out the character's totals from known gear; the addon must find that gear again from those totals alone.
// Also: a character with a ready build's talents gets that build back as its template, with the same priority list.
//   node tools/check-character.js
const path = require('path'), assert = require('assert');
const { newLua } = require('./lua-host.js');
const host = newLua();
host.loadAddon(['Data.lua', 'Engine.lua', 'Sim.lua', 'Codes.lua', 'Character.lua']);
const out = host.eval(`
local WL, n, bad = WLX, 0, {}
local buffSets = { {}, { arcaneIntellect = true, blessingOfKings = true, markOfTheWild = true, fortitude = true, divineSpirit = true, blessingOfWisdom = true, moonkinAura = true }, { blessingOfKings = true, blessingOfSalvation = true, manaSpring = true } }
local gears = { WL.DEFAULT_CONFIG.gear, { sp = 1000, shadowSp = 21, fireSp = 40, hitPct = 17, critPct = 20.5, hastePct = 6, pierce = 40, spellPen = 25, int = 250, spi = 100, sta = 300, mp5 = 14, weaponIsSword = false },
  { sp = 37, shadowSp = 0, fireSp = 0, hitPct = 0, critPct = 3.2, hastePct = 0, pierce = 0, spellPen = 0, int = -40, spi = -30, sta = -10, mp5 = 0 } }
local fields = { 'sp', 'shadowSp', 'fireSp', 'hitPct', 'critPct', 'hastePct', 'pierce', 'spellPen', 'int', 'spi', 'sta', 'mp5' }
for bi = 1, #WL.BUILDS do
  local b = WL.BUILDS[bi]
  for _, race in ipairs({ 'human', 'gnome', 'orc', 'undead', 'troll' }) do
    for si = 1, #buffSets do
      for gi = 1, #gears do
        for _, withSupp in ipairs({ false, true }) do
          local cfg = WL.copy(WL.DEFAULT_CONFIG)
          for k, x in pairs(cfg.buffs) do x.on = buffSets[si][k] and true or false end
          for _, x in pairs(cfg.consumables) do x.on = false end
          cfg.gear = WL.copy(gears[gi]); cfg.gear.critIncludesAll = false
          local build = WL.copy(b); build.oil = 'none'
          local s = WL.computeStats(build, race, cfg)
          local supp = WL.talentValue(build, 'suppression', 'hitPct')
          local sheet = { int = s.int, spi = s.spi, sta = s.sta, sp = s.sp, spShadow = s.sp + s.schoolSp.shadow, spFire = s.sp + s.schoolSp.fire,
            hit = s.hitPctUncapped - cfg.combat.baseHitPct - (withSupp and 0 or supp), crit = s.critPct, haste = s.hastePct, mp5 = s.mp5, pierce = s.pierce, spellPen = s.spellPen }
          local g = WL.gearFromSheet(sheet, { raceKey = race, talents = build.talents, pet = build.pet, sacrifice = build.sacrifice, buffs = buffSets[si], hitHasSuppression = withSupp })
          for _, f in ipairs(fields) do
            n = n + 1
            if math.abs(g[f] - gears[gi][f]) > 0.001 then bad[#bad + 1] = b.key .. ' ' .. race .. ' buffs ' .. si .. ' gear ' .. gi .. ' ' .. f .. ': ' .. tostring(g[f]) .. ' instead of ' .. tostring(gears[gi][f]) end
          end
        end
      end
    end
  end
  -- the template of a build's own talents is that build, and its priority list comes back unchanged
  local key = WL.bestTemplate(b.talents, WL.BUILDS, b.pet)
  n = n + 1
  if key ~= b.key then bad[#bad + 1] = 'template of ' .. b.key .. ' is ' .. tostring(key) end
  local cb, notes = WL.characterBuild({ talents = b.talents, pet = b.pet, sacrifice = b.sacrifice, oil = b.oil }, b)
  n = n + 1
  if table.concat(cb.rotation, ',') ~= table.concat(b.rotation, ',') or #notes > 0 or #WL.validateBuild(cb) > 0 then
    bad[#bad + 1] = 'character build of ' .. b.key .. ': ' .. table.concat(cb.rotation, ',') .. ' / ' .. table.concat(notes, ' ') .. ' / ' .. table.concat(WL.validateBuild(cb), ' ')
  end
end
-- a character without any talents can still be simulated with every template
for bi = 1, #WL.BUILDS do
  local cb, notes = WL.characterBuild({ talents = {}, pet = nil, sacrifice = 'imp', oil = 'none' }, WL.BUILDS[bi])
  local errs = WL.validateBuild(cb, true)
  n = n + 1
  if #errs > 0 or cb.sacrifice ~= nil then bad[#bad + 1] = 'no talents with ' .. WL.BUILDS[bi].key .. ': ' .. table.concat(errs, ' ') end
  local r = WL.simulate(cb, 'orc', WL.DEFAULT_CONFIG, { iterations = 2 })
  n = n + 1
  if not (r.dps > 50) then bad[#bad + 1] = 'no talents with ' .. WL.BUILDS[bi].key .. ': dps ' .. tostring(r.dps) end
end
return n .. '|' .. table.concat(bad, '\\n')
`);
const [n, bad] = out.split('|');
if (bad) { console.log('FAIL\n' + bad.split('\n').slice(0, 15).join('\n')); process.exit(1); }
console.log('OK: ' + n + ' character checks (gear found again from the sheet, templates, builds without talents)');
