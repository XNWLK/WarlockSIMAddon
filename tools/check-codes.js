// Checks that settings codes and build codes go both ways between the sim's page (JavaScript) and the addon (Lua).
//   node tools/check-codes.js
const path = require('path'), assert = require('assert');
const ROOT = path.join(__dirname, '..');
const SIM = process.env.SIM_DIR || path.join(ROOT, '..', 'wow-forever-warlock-sim');
const WL = require(path.join(SIM, 'tools', 'load-wl.js')).load(SIM, ['engine/settings-code.js', 'tests/retired-builds.js']);
const { newLua } = require('./lua-host.js');
const host = newLua();
host.loadAddon(['Data.lua', 'Engine.lua', 'Sim.lua', 'Codes.lua']);
const b64 = s => Buffer.from(s, 'utf8').toString('base64'), unb64 = s => Buffer.from(s, 'base64').toString('utf8');
const q = s => JSON.stringify(s);
const norm = o => JSON.parse(JSON.stringify(o));
let n = 0;

// settings: page -> addon -> page
const variants = [c => {}, c => { Object.keys(c.buffs).forEach(k => { c.buffs[k].on = !c.buffs[k].on; }); c.gear.sp = 812.5; c.fight.precast = 'soulFire'; c.professions.engineering = true; },
  c => { Object.keys(c.buffs).forEach(k => { c.buffs[k].on = false; }); Object.keys(c.debuffs).forEach(k => { c.debuffs[k].on = false; }); Object.keys(c.consumables).forEach(k => { c.consumables[k].on = false; });
         c.options.activesPolicy = 'custom'; c.options.activesTimeline = { racial: [10, 'exec'], pi: ['doom'] }; c.combat.targetResist.fire = 15; c.combat.levelResist.on = false; c.petSpPct = 12.5; c.fight.seed = 4000000000; }];
variants.forEach((v, i) => {
  const cfg = norm(WL.DEFAULT_CONFIG); v(cfg);
  const snap = norm(WL.settingsSnapshot(cfg));
  const code = 'WFS1:' + b64(JSON.stringify(snap));
  const back = host.eval('local o, err = WLX.decodeSettings(' + q(code) + '); if not o then return "ERR " .. err end; local c = WLX.copy(WLX.DEFAULT_CONFIG); local u = WLX.applySettings(c, o); return WLX.encodeSettings(c) .. "|" .. #u');
  assert(back.indexOf('ERR') !== 0, back);
  const [code2, unknown] = back.split('|');
  assert.strictEqual(unknown, '0', 'unknown settings: ' + unknown);
  const snap2 = JSON.parse(unb64(code2.slice(5)));
  assert.deepStrictEqual(snap2, snap, 'settings variant ' + i);
  // and the page applies what the addon wrote
  const c3 = norm(WL.DEFAULT_CONFIG); assert.strictEqual(WL.applySettings(c3, snap2).length, 0);
  assert.deepStrictEqual(norm(WL.settingsSnapshot(c3)), snap);
  n++;
});

// builds: page -> addon -> page
const builds = WL.BUILDS.concat(WL.RETIRED_BUILDS || []);
builds.push(Object.assign(norm(WL.BUILDS[0]), { short: 'Tïmeline "test" \ build', timeline: [{ t: 0, k: 'curseOfElements' }, { t: 12.345, k: 'soulFire' }], rotation: ['shadowBoltR2LowMana', 'bane', 'isbUpkeepR2', 'shadowBoltR2'] }));
builds.forEach(b => {
  const o = { v: 1, short: b.short, talents: b.talents, pet: b.pet || null, sacrifice: b.sacrifice || null, oil: b.oil, rotation: b.rotation };
  if (b.timeline) o.tl = b.timeline.map(e => [Math.round(e.t * 100) / 100, e.k]);
  const p = WL.cleanParams(b.params, b.rotation); if (p) o.p = p;
  const code = 'WFB1:' + b64(JSON.stringify(o));
  const back = host.eval('local b, err = WLX.decodeBuild(' + q(code) + '); if not b then return "ERR " .. err end; return WLX.encodeBuild(b) .. "|" .. #WLX.validateBuild(b)');
  assert(back.indexOf('ERR') !== 0, back);
  const o2 = JSON.parse(unb64(back.split('|')[0].slice(5)));
  const rot = WL.migrateRotation(b.rotation);
  assert.deepStrictEqual(o2.talents, norm(WL.migrateTalents(b.talents).talents), b.key + ' talents');   // Malediction -> Grim Reach
  assert.deepStrictEqual(o2.rotation, norm(rot), b.key + ' rotation');
  assert.strictEqual(o2.pet || null, b.pet || null); assert.strictEqual(o2.sacrifice || null, b.sacrifice || null); assert.strictEqual(o2.oil, b.oil);
  assert.strictEqual(o2.short, String(b.short).slice(0, 40));
  assert.deepStrictEqual(o2.p || null, norm(WL.cleanParams(b.params, rot) || null), b.key + ' params');
  if (b.timeline) assert.deepStrictEqual(o2.tl, norm(o.tl), b.key + ' timeline');
  if (!b.timeline) assert.strictEqual(back.split('|')[1], String(WL.validateBuild(Object.assign(norm(b), { rotation: rot })).length), b.key + ': the addon and the page find the same number of problems');
  n++;
});
// codes made before the patch of 2026-10-16: the removed totems and the sword box load quietly, Malediction moves to Grim Reach
{
  const snap = norm(WL.settingsSnapshot(norm(WL.DEFAULT_CONFIG)));
  snap.buffs = snap.buffs.concat(['windfuryTotem', 'flametongueTotem', 'tranquilAir', 'graceOfAir', 'scrollOfAgility']); snap.gear.weaponIsSword = true; snap.gear.agi = 17;
  const r = host.eval('local o = WLX.decodeSettings(' + q('WFS1:' + b64(JSON.stringify(snap))) + '); local c = WLX.copy(WLX.DEFAULT_CONFIG); return #WLX.applySettings(c, o)');
  assert.strictEqual(r, 0, 'old settings code: names reported as unknown'); n++;
  const old = { v: 1, short: 'Old', talents: Object.assign(norm(WL.BUILDS[0].talents), { malediction: 5 }), pet: WL.BUILDS[0].pet, sacrifice: WL.BUILDS[0].sacrifice || null, oil: WL.BUILDS[0].oil, rotation: WL.BUILDS[0].rotation };
  const mt = WL.migrateTalents(old.talents);
  const back = host.eval('local b = WLX.decodeBuild(' + q('WFB1:' + b64(JSON.stringify(old))) + '); return WLX.encodeBuild(b) .. "|" .. table.concat(b.migrated or {}, "/")');
  assert.deepStrictEqual(JSON.parse(unb64(back.split('|')[0].slice(5))).talents, norm(mt.talents), 'old build code with Malediction');
  assert.strictEqual(back.split('|')[1], mt.notes.join('/'), 'migration note');
  n += 2;
}
// damaged codes give a message, not an error
['', 'hello', 'WFS1:!!!!', 'WFS1:' + b64('{"v":2}'), 'WFB1:' + b64('[1,2'), 'WFB1:' + b64('{"v":1}')].forEach(c => {
  const r = host.eval('local a, e1 = WLX.decodeSettings(' + q(c) + '); local b, e2 = WLX.decodeBuild(' + q(c) + '); return tostring(a == nil and b == nil) .. " " .. tostring(e1) .. " / " .. tostring(e2)');
  assert(r.indexOf('true ') === 0, c + ' -> ' + r); n++;
});
console.log('OK: ' + n + ' code checks (settings and builds, page -> addon -> page)');
