// Checks how the addon reads an item: from the game's stat list, from tooltip lines in the Forever client's own wording
// (private/ref/GlobalStrings_enUS.lua, if present), from the classic wording, and the gear after a swap.
//   node tools/check-items.js
const fs = require('fs'), path = require('path');
const { newLua } = require('./lua-host.js');
const { toLua } = require('./lua-ser.js');
const host = newLua();
host.loadAddon(['Data.lua', 'Engine.lua', 'Sim.lua', 'Codes.lua', 'Character.lua', 'Items.lua']);
const ref = path.join(__dirname, '..', 'private', 'ref', 'GlobalStrings_enUS.lua');
const strings = {};
if (fs.existsSync(ref)) {
  fs.readFileSync(ref, 'utf8').split('\n').forEach(l => { const m = l.match(/^(ITEM_MOD_[A-Z0-9_]+|ITEM_SPELL_TRIGGER_[A-Z]+) = "(.*)";\s*$/); if (m && !/_SHORT$/.test(m[1])) strings[m[1]] = m[2].replace(/\\"/g, '"'); });
} else console.log('NOTE: private/ref/GlobalStrings_enUS.lua is missing - only the classic wording is checked');
const haveRef = Object.keys(strings).length > 0;
host.run('STRINGS = ' + toLua(strings));
const out = host.eval(`
local WL, bad, n = WLX, {}, 0
local function S(name) return STRINGS[name] end
local function pct(stat, v) return v / 14 end
local function check(name, got, want)
  n = n + 1
  local keys = {}
  for k in pairs(got) do keys[k] = true end
  for k in pairs(want) do keys[k] = true end
  for k in pairs(keys) do
    if math.abs((got[k] or 0) - (want[k] or 0)) > 1e-9 then bad[#bad + 1] = name .. ': ' .. k .. ' = ' .. tostring(got[k]) .. ', expected ' .. tostring(want[k]) end
  end
end
-- the game's stat list alone
check('stat list', (WL.itemStats({ ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 9, ITEM_MOD_SPELL_POWER_SHORT = 30, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 5, ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 21,
  ITEM_MOD_HIT_SPELL_RATING_SHORT = 14, ITEM_MOD_CRIT_RATING_SHORT = 28, ITEM_MOD_SPELL_PENETRATION_SHORT = 10, ITEM_MOD_POWER_REGEN0_SHORT = 4, ITEM_MOD_STRENGTH_SHORT = 50 }, {}, S, pct)),
  { int = 12, sta = 9, sp = 35, shadowSp = 21, hit = 1, crit = 2, pierce = 10, mp5 = 4 })
-- the classic wording
local st, unknown = WL.itemStats(nil, { 'Robe of Tests', 'Cloth', '+20 Stamina', '|cff00ff00Equip: Increases damage and healing done by magical spells and effects by up to 40.|r',
  'Equip: Improves your chance to hit with spells by 1%.', 'Equip: Improves your chance to get a critical strike with spells by 2%.', 'Equip: Restores 6 mana per 5 sec.',
  'Equip: Increases damage done by Shadow spells and effects by up to 19.', 'Equip: Decreases the magical resistances of your spell targets by 10.',
  'Use: Does something odd. (2 Min Cooldown)', 'Equip: Increases your pet\\'s happiness.', '"A flavour text."' }, S, pct)
if ${haveRef ? 'true' : 'false'} then check('classic wording', st, { sta = 20, sp = 40, hit = 1, crit = 2, mp5 = 6, shadowSp = 19, pierce = 10 })
else check('classic wording', st, { sp = 40, hit = 1, crit = 2, mp5 = 6, shadowSp = 19, pierce = 10 }) end
n = n + 1; if #unknown ~= 2 then bad[#bad + 1] = 'lines not understood: ' .. #unknown .. ' (' .. table.concat(unknown, ' | ') .. ')' end
if ${haveRef ? 'true' : 'false'} then
  -- the Forever client's own wording, a percentage in the text is taken as it stands, a bare number as a rating
  check('Forever wording', (WL.itemStats(nil, { '+12 Intellect', '+7 Spirit', '-3 Agility', 'Equip: Increases spell power by 30.', 'Equip: Improves spell hit by 1.5%.',
    'Equip: Improves spell critical strike by 28.', 'Equip: Increases your haste by 2%.', 'Equip: Increases shadow damage done by up to 21.', 'Equip: Increases fire damage done by up to 9.',
    'Equip: Increases spell piercing by 10.', 'Equip: Restores 5 mana per 5 sec.', 'Equip: Increases damage done by magical spells and effects by up to 1,200.' }, S, pct)),
    { int = 12, spi = 7, sp = 1230, hit = 1.5, crit = 2, haste = 2, shadowSp = 21, fireSp = 9, pierce = 10, mp5 = 5 })
  -- both sources say the same thing: counted once; the tooltip's percentage wins over the list's bare number
  check('list and tooltip together', (WL.itemStats({ ITEM_MOD_INTELLECT_SHORT = 12, ITEM_MOD_SPELL_POWER_SHORT = 30, ITEM_MOD_HIT_SPELL_RATING_SHORT = 1 },
    { '+12 Intellect', 'Equip: Increases spell power by 30.', 'Equip: Improves spell hit by 1%.' }, S, pct)), { int = 12, sp = 30, hit = 1 })
end
-- a swap: gear + new - old, Intellect also moves the sheet's crit
local cfg = WL.copy(WL.DEFAULT_CONFIG)
local g, d = WL.gearWithSwap({ sp = 500, shadowSp = 0, fireSp = 0, hitPct = 5, critPct = 10, hastePct = 0, pierce = 0, int = 148, spi = 54, sta = 160, mp5 = 0 },
  { sp = 30, int = 12, hit = 1 }, { { sp = 10, sta = 8 }, { crit = 1, int = 6 } }, cfg)
check('gear after a swap', g, { sp = 520, shadowSp = 0, fireSp = 0, hitPct = 6, critPct = 10 - 1 + 6 / 60, hastePct = 0, pierce = 0, int = 154, spi = 54, sta = 152, mp5 = 0 })
n = n + 1; local text = WL.describeStats(d, true)
if text ~= '+20 spell power, +1% hit, -1% crit, +6 Intellect, -8 Stamina' then bad[#bad + 1] = 'difference text: ' .. text end
n = n + 1; if WL.describeStats({}, true) ~= 'nothing the sim counts' then bad[#bad + 1] = 'empty difference text' end
-- enchant texts (the gear code): the game's own item wording, then words; hit / crit / haste with a % as they stand
local function ench(name, text, want, wantOk)
  local s, ok = WL.enchantStats(text, S, pct)
  check('enchant ' .. name, s, want)
  n = n + 1; if ok ~= wantOk then bad[#bad + 1] = 'enchant ' .. name .. ': understood = ' .. tostring(ok) end
end
ench('Intellect', '+8 Intellect', { int = 8 }, true)
ench('spell damage', '+30 Spell Damage and Healing', { sp = 30 }, true)
ench('spell power after', 'Spell Power +18', { sp = 18 }, true)
ench('two parts', '+18 Spell Damage and Healing / +1% Spell Hit', { sp = 18, hit = 1 }, true)
ench('mana regen', 'Mana Regen 4 per 5 sec.', { mp5 = 4 }, true)
ench('all stats', '+4 All Stats', { int = 4, spi = 4, sta = 4 }, true)
ench('agility: read, counts as nothing', '+7 Agility', {}, true)
ench('shadow', '+20 Shadow Spell Damage', { shadowSp = 20 }, true)
ench('crit rating', '+14 Spell Critical Strike Rating', { crit = 1 }, true)
ench('healing only', '+24 Healing Spells', {}, false)
ench('nothing to read', 'Minor Speed Increase', {}, false)
ench('one of two not read', '+10 Stamina, Minor Speed Increase', { sta = 10 }, false)
ench('colour codes', '|cff00ff00+15 Spirit|r', { spi = 15 }, true)
-- every equip location maps to slots that exist
for loc, slots in pairs(WL.ITEM_SLOTS) do n = n + 1; for _, s in ipairs(slots) do if s < 1 or s > 18 then bad[#bad + 1] = loc .. ' slot ' .. s end end end
return n .. '|' .. table.concat(bad, '\\n')
`);
const [n, bad] = out.split('|');
if (bad) { console.log('FAIL\n' + bad); process.exit(1); }
console.log('OK: ' + n + ' item checks (stat list, classic and Forever wording, swaps)');
