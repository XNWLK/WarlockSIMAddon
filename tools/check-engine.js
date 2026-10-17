// Plays the same fights in the DPS sim's own engine (JavaScript) and in the addon's engine (Lua, run by fengari) and
// compares them: total damage, damage / casts / misses / crits per spell, mana, health, threat, Life Taps.
//   node tools/check-engine.js            every scene, 4 fights each
//   node tools/check-engine.js 12         12 fights per scene
//   node tools/check-engine.js 4 pushback only scenes whose name contains "pushback"
// Must say OK after every change of WarlockSim/Engine.lua or Sim.lua and after every tools/gen-data.js.
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const SIM = process.env.SIM_DIR || path.join(ROOT, '..', 'wow-forever-warlock-sim');
const { toLua } = require('./lua-ser.js');
const { newLua } = require('./lua-host.js');

const FIGHTS = parseInt(process.argv[2], 10) || 4, ONLY = process.argv[3] || '';
const WL = require(path.join(SIM, 'tools', 'load-wl.js')).load(SIM, fs.existsSync(path.join(SIM, 'tests', 'retired-builds.js')) ? ['tests/retired-builds.js'] : []);
const host = newLua();
host.loadAddon(['Data.lua', 'Engine.lua', 'Sim.lua', 'Codes.lua'].filter(f => fs.existsSync(path.join(ROOT, 'WarlockSim', f))));
host.run(fs.readFileSync(path.join(__dirname, 'check-engine.lua'), 'utf8'), '@check-engine.lua');

const missing = host.eval('return table.concat(WLX.ACTIONS_MISSING, ",")');
if (missing) { console.log('FAIL: priority actions of the sim that Engine.lua does not know: ' + missing); process.exit(1); }

// ---- scenes: a name and a list of [path, value] changes to the default settings ----
const S = (name, patch, opt) => Object.assign({ name, patch: patch || [] }, opt || {});
const scenes = [
  S('defaults'),
  S('no buffs', [['buffs.*.on', false], ['debuffs.*.on', false]]),
  S('max buffs', [['buffs.*.on', true], ['debuffs.*.on', true], ['consumables.flaskSupremePower.on', true], ['consumables.greaterArcaneElixir.on', true],
    ['consumables.shadowPower.on', true], ['consumables.elixirOwl.on', true], ['consumables.elixirSages.on', true], ['consumables.brilliantWizardOil.on', true],
    ['consumables.majorSpellblasting.on', true], ['consumables.demonicRune.on', true], ['consumables.nightfinSoup.on', true]]),
  S('hit-capped gear', [['gear.sp', 1000], ['gear.hitPct', 17], ['gear.critPct', 20], ['gear.int', 250], ['gear.spi', 100], ['gear.sta', 300], ['gear.hastePct', 6], ['gear.pierce', 40]]),
  S('poor gear, long fight', [['gear.sp', 150], ['gear.hitPct', 0], ['gear.critPct', 5], ['gear.int', 60], ['gear.spi', 20], ['gear.mp5', 12], ['fight.duration', 300]]),
  S('short fight', [['fight.duration', 35]]),
  S('2 targets', [['fight.targets', 2]]),
  S('3 targets multi-DoT', [['fight.targets', 3], ['fight.multiDot', true]]),
  S('movement + latency + travel', [['fight.moveEvery', 20], ['fight.moveDuration', 5], ['fight.latencyMs', 150], ['fight.travelMs', 400], ['fight.lifeTapWhileMoving', true]]),
  S('pushback', [['fight.hitEvery', 2], ['buffs.concentrationAura.on', true]]),
  S('precast soul fire, pull', [['fight.precast', 'soulFire'], ['options.activesPolicy', 'pull']]),
  S('precast shadow bolt, execute', [['fight.precast', 'shadowBolt'], ['options.activesPolicy', 'execute']]),
  S('salvation, high crit', [['buffs.blessingOfSalvation.on', true], ['gear.critPct', 25]], { builds: ['demo_pact_succ_sb', 'wrack_succubus', 'destro_incin_imp'] }),
  S('every race, pushback', [['fight.hitEvery', 1.5]], { builds: ['demo_pact_fire', 'wrack_succubus', 'destro_incin_imp'] }),
  S('mana buffs + potions', [['buffs.manaTide.on', true], ['buffs.innervate.on', true], ['buffs.powerInfusion.on', true], ['buffs.manaSpring.on', true], ['buffs.restorativeTotems.on', true],
    ['consumables.majorManaPotion.on', true], ['gear.int', 20], ['gear.spi', 0], ['fight.duration', 240]]),
  S('engineering', [['professions.engineering', true], ['consumables.goblinSapper.on', true], ['consumables.denseDynamite.on', true]]),
  S('book ranks, old dot rule, no curse', [['options.bookRanks', true], ['options.dotEndCheck', false], ['options.useCurseOfElements', false], ['debuffs.coeOther.on', true]]),
  S('spell pierce + resist', [['gear.pierce', 60], ['combat.targetResist.shadow', 30], ['combat.targetResist.fire', 70]]),
  S('no level resist, no 5s rule, no heal', [['combat.levelResist.on', false], ['combat.fsrSeconds', 0], ['fight.healAmount', 0]]),
  S('crit includes all, no pets', [['gear.critIncludesAll', true], ['options.includePetDamage', false]]),
  S('custom cooldown timeline', [['options.activesPolicy', 'custom'], ['options.activesTimeline', { racial: [10, 'exec'], pi: ['doom'], majorSpellblasting: [0, 130], demonicRune: [40] }],
    ['buffs.powerInfusion.on', true], ['consumables.majorSpellblasting.on', true], ['consumables.demonicRune.on', true], ['fight.duration', 200]]),
  S('hellfire filler 3 targets', [['fight.targets', 3]], { builds: ['destro_incin_imp'], rotation: r => r.slice(0, -1).concat(['hellfire']) }),
  S('rain of fire filler 2 targets', [['fight.targets', 2]], { builds: ['destro_incin_imp'], rotation: r => r.slice(0, -1).concat(['rainOfFire']) }),
  S('drain life filler', [], { builds: ['sm_ruin_classic', 'wrack_succubus'], rotation: r => r.slice(0, -1).concat(['drainLife']) }),
  S('pet swap at execute', [], { builds: ['demo_pact_succ_sb'], rotation: r => ['swapToImp'].concat(r) }),
  S('timeline', [], { builds: ['demo_pact_fire', 'sm_ruin_classic'], timeline: [{ t: 0, k: 'curseOfElements' }, { t: 1.5, k: 'corruption' }, { t: 3.5, k: 'immolate' }, { t: 30, k: 'lifeTap' }, { t: 45, k: 'soulFire' }, { t: 60, k: 'drainLife' }] }),
];

const builds = WL.BUILDS.slice();
(WL.RETIRED_BUILDS || []).forEach(b => builds.push(b));
const RACES = WL.RACE_KEYS.concat(['none']);

function setPath(obj, p, v) {
  const parts = p.split('.');
  (function walk(o, i) {
    if (i === parts.length - 1) { if (parts[i] === '*') Object.keys(o).forEach(k => { o[k] = v; }); else o[parts[i]] = v; return; }
    if (parts[i] === '*') Object.keys(o).forEach(k => walk(o[k], i + 1)); else walk(o[parts[i]], i + 1);
  })(obj, 0);
}
function near(a, b) { return a === b || Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b)); }

let fights = 0, bad = 0, firstBad = null, t0 = Date.now(), luaMs = 0, jsMs = 0;
scenes.filter(s => !ONLY || s.name.indexOf(ONLY) >= 0).forEach(sc => {
  const cfg = JSON.parse(JSON.stringify(WL.DEFAULT_CONFIG));
  sc.patch.forEach(p => setPath(cfg, p[0], p[1]));
  host.run('CHK.setScene(' + toLua(sc.patch) + ')');
  let sceneFights = 0, sceneBad = 0;
  builds.filter(b => !sc.builds || sc.builds.indexOf(b.key) >= 0).forEach((b0, bi) => {
    const b = JSON.parse(JSON.stringify(b0));
    if (sc.rotation) b.rotation = sc.rotation(b.rotation);
    if (sc.timeline) b.timeline = sc.timeline;
    host.run('CHK.setBuild(' + toLua(b) + ')');
    const races = sc.builds ? RACES : [RACES[(bi + scenes.indexOf(sc)) % RACES.length], RACES[(bi + scenes.indexOf(sc) + 3) % RACES.length]];
    races.forEach(race => {
      const stats = WL.computeStats(b, race, cfg), table = WL.buildSpellTable(b, stats, cfg);
      for (let i = 0; i < FIGHTS; i++) {
        const fp = WL.fightParams(cfg, i);
        let t = Date.now();
        const r = WL.simulateOnce(b, race, cfg, { stats, table, seed: fp.seed, duration: fp.duration, log: false });
        jsMs += Date.now() - t; t = Date.now();
        const out = host.eval('return CHK.fight("' + race + '", ' + i + ')');
        luaMs += Date.now() - t;
        const o = JSON.parse(out);
        const diffs = [];
        const cmp = (name, a, bb) => { if (!near(a, bb)) diffs.push(name + ': sim ' + a + ' addon ' + bb); };
        cmp('seed', fp.seed, o.seed); cmp('duration', fp.duration, o.duration);
        cmp('total', r.total, o.total); cmp('endMana', r.endMana, o.endMana); cmp('minMana', r.minMana, o.minMana);
        cmp('health.min', r.health.min, o.healthMin); cmp('health.end', r.health.end, o.healthEnd);
        cmp('lifeTaps', r.lifeTaps, o.lifeTaps); cmp('threat', r.threat, o.threat); cmp('idle', r.idle, o.idle); cmp('clipped', r.clipped, o.clipped);
        cmp('exDmg', r.exDmg, o.exDmg); cmp('pushbacks', r.pushbacks, o.pushbacks);
        const keys = Object.keys(r.bySpell).filter(k => { const x = r.bySpell[k]; return x.casts || x.dmg || x.misses; });
        const okeys = Object.keys(o.rows).filter(k => { const x = o.rows[k]; return x[0] || x[1] || x[2]; });
        if (keys.slice().sort().join() !== okeys.slice().sort().join()) diffs.push('rows: sim [' + keys.sort().join() + '] addon [' + okeys.sort().join() + ']');
        else keys.forEach(k => { const x = r.bySpell[k], y = o.rows[k]; cmp(k + '.casts', x.casts, y[0]); cmp(k + '.dmg', x.dmg, y[1]); cmp(k + '.misses', x.misses, y[2]); cmp(k + '.crits', x.crits + x.tickCrits, y[3]); cmp(k + '.castTime', x.castTime, y[4]); });
        fights++; sceneFights++;
        if (diffs.length) { bad++; sceneBad++; if (!firstBad) firstBad = sc.name + ' / ' + b.key + ' / ' + race + ' / fight ' + i + '\n    ' + diffs.slice(0, 12).join('\n    '); }
      }
    });
  });
  console.log((sceneBad ? 'FAIL ' : 'ok   ') + sc.name + ': ' + sceneFights + ' fights' + (sceneBad ? ', ' + sceneBad + ' differ' : ''));
});

// stats and spell tables for every build and race at the defaults
let tableBad = 0;
host.run('CHK.setScene({})');
// plus one character with both range talents (Destructive Reach: Destruction spells, Grim Reach: Affliction spells)
const reach = Object.assign({}, builds[0], { key: 'both_reach_talents', talents: Object.assign({}, builds[0].talents, { destructiveReach: 2, grimReach: 2 }) });
builds.concat([reach]).forEach(b => {
  host.run('CHK.setBuild(' + toLua(b) + ')');
  RACES.forEach(race => {
    const stats = WL.computeStats(b, race, WL.DEFAULT_CONFIG), table = WL.buildSpellTable(b, stats, WL.DEFAULT_CONFIG);
    const o = JSON.parse(host.eval('return CHK.table("' + race + '")'));
    ['int', 'spi', 'sta', 'maxMana', 'maxHealth', 'sp', 'hitPct', 'critPct', 'hastePct', 'mp5', 'pierce'].forEach(k => { if (!near(stats[k], o.stats[k])) { tableBad++; if (!firstBad) firstBad = 'stats ' + b.key + ' ' + race + ' ' + k + ': sim ' + stats[k] + ' addon ' + o.stats[k]; } });
    Object.keys(table).forEach(k => ['cast', 'cd', 'range', 'cost', 'sp', 'critPct', 'critMult', 'directMult', 'periodicMult', 'ticks'].forEach(f => {
      const a = table[k][f], bb = o.table[k] && o.table[k][f];
      if (a !== undefined && !near(a, bb)) { tableBad++; if (!firstBad) firstBad = 'spell table ' + b.key + ' ' + race + ' ' + k + '.' + f + ': sim ' + a + ' addon ' + bb; }
    }));
    if (Object.keys(table).length !== Object.keys(o.table).length) { tableBad++; if (!firstBad) firstBad = 'spell table ' + b.key + ': different spells'; }
  });
});
console.log((tableBad ? 'FAIL ' : 'ok   ') + 'stats and spell tables: ' + (builds.length + 1) * RACES.length + ' characters' + (tableBad ? ', ' + tableBad + ' values differ' : ''));

console.log('');
console.log(host.limits());
console.log(fights + ' fights compared in ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s (sim ' + (jsMs / fights).toFixed(2) + ' ms a fight, addon in the test runner ' + (luaMs / fights).toFixed(1) + ' ms)');
if (bad || tableBad) { console.log('FAIL: ' + bad + ' fights differ. First:\n  ' + firstBad); process.exit(1); }
console.log('OK: the addon\'s engine and the sim\'s engine agree in all ' + fights + ' fights');
