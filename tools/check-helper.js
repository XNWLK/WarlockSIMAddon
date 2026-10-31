// The helper bar (WarlockSim/Helper.lua) against the practice boss (tools/arena.lua): for every ready build, one fight
// played by what the helper shows - once with everything readable, once with the boss's health, buffs, debuffs and
// mana hidden as the game may hide them in combat. Fails on any error of the helper, on a fight where it fell silent,
// and when its time to kill is far off. With "compare" it also puts its casts next to the sim's own fights.
//   node tools/check-helper.js            quick
//   node tools/check-helper.js compare    + casts per spell: helper / sim (slower)
const { reset, step, lua } = require('./arena-server.js');
const compare = process.argv[2] === 'compare';
const builds = JSON.parse((reset({}), lua('local o = {}; for i, b in ipairs(WLX.BUILDS) do o[i] = b.key end; return WLX.jsonEncode(WLX.jsonArray(o))')));
let bad = 0;
const fail = msg => { bad++; console.log('FAIL ' + msg); };
for (const build of builds) {
  for (const hide of [false, true]) {
    const set = { auto: true, length: compare ? 150 : 60, raidDps: 3500, hideHealth: hide, hideAuras: hide, hideMana: hide };
    let s = JSON.parse(reset({ build, race: 'orc', set }));
    s = JSON.parse(step({ dt: 0.2 }));                            // the addon looks ten times a second
    if (!s.helper.active || !s.helper.keys.length) fail(build + ': nothing shown before the pull');
    s = JSON.parse(step({ dt: 0.1, pull: true }));
    let silent = 0, n = 0;
    const seen = new Set(), refused = [];
    for (let i = 0; i < 1500 && !(s.result && !s.combat); i++) {
      s = JSON.parse(step({ dt: 0.5 }));
      if (s.helper.error) { fail(build + ': ' + s.helper.error); break; }
      if (s.combat) { n++; if (!s.helper.active || !s.helper.keys.length) silent++; }
      s.log.forEach(l => { if (/^ {6,}/.test(l) && !seen.has(l)) { seen.add(l); refused.push(l.trim()); } });
    }
    const r = s.result;
    if (!r) { fail(build + ': the fight never ended'); continue; }
    if (refused.length) fail(`${build}${hide ? ' (hidden)' : ''}: the game refused what the helper showed: ${refused.slice(0, 3).join('; ')}`);
    if (silent > 2) fail(`${build}: no spell shown ${silent} of ${n} times`);
    if (!hide && r.ttkError > 6) fail(`${build}: time to kill off by ${r.ttkError.toFixed(1)} s on average`);
    const line = `${build}${hide ? ' (hidden)' : ''}: ${r.length.toFixed(0)} s, ${r.presses} casts, ${r.dps.toFixed(0)} DPS, time to kill off by ${r.ttkError != null ? r.ttkError.toFixed(1) : '-'} s`;
    console.log('ok   ' + line);
    if (compare && !hide) {
      const sim = JSON.parse(lua(`local C = WLX.helper.context(); local out, n = {}, 40
        for i = 0, n - 1 do local fc = WLX.copy(C.cfg); fc.fight.seed = 1000 + i; local res = WLX.simulateOnce(C.build, C.race, fc, { duration = ${r.length.toFixed(1)} })
          for k, v in pairs(res.bySpell) do if v.casts > 0 then out[k] = (out[k] or 0) + v.casts / n end end end
        return WLX.jsonEncode(out)`));
      const keys = [...new Set([...Object.keys(r.casts), ...Object.keys(sim)])].filter(k => !k.startsWith('pet:') && k !== 'touchOfTheGrave');
      console.log('     casts helper / sim: ' + keys.map(k => `${k} ${r.casts[k] || 0}/${(sim[k] || 0).toFixed(1)}`).join('  '));
    }
  }
}
console.log(bad ? 'FAIL: ' + bad + ' problems' : 'OK: the helper played ' + builds.length * 2 + ' fights without a problem');
process.exit(bad ? 1 : 0);
