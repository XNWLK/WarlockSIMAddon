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
// When the racial is suggested ("Pop cooldowns": "When Bane of Doom explodes", the default). The helper's own plan
// (decide, extras, effects) from the very start of a fight, with full mana and the boss on its Fight-tab length, until
// the racial shows among the extras. A build that never casts Bane of Doom: Blood Fury not with the opening DoTs and
// curse, only with the first filler (Wrack); Berserking from the first spell. A Doom build: as before, when Doom explodes.
function racialPlan(build, race, spellId) {
  reset({ build, race });
  return JSON.parse(lua(`local H = WLX.helper
    local C, err = H.context(); assert(C, err)
    local d = C.cfg.fight.duration
    local P = { t = 0, now = 0, rNow = d, hpNow = 100, slope = -100 / d, mana = C.stats.maxMana, tapMana = 0, manaStart = C.stats.maxMana,
                dots = {}, cds = {}, buffs = {}, brandCharges = 0, shards = math.huge, lastSpend = -math.huge }
    if C.cfg.debuffs.coeOther and C.cfg.debuffs.coeOther.on then P.buffs.coe = math.huge end
    local S = H.newS(C, P)
    local steps = {}
    for n = 1, 80 do
      local k, ki = H.decide(C, P, S)
      if not k then break end
      local a = ki and C.acts[ki]
      local x, racial = H.extras(C, P, S, k, ki), false
      for i = 1, #x do if x[i].spell == ${spellId} then racial = true end end
      steps[n] = { t = P.t, key = k, fill = (a and (a.filler or a.preFiller)) and true or false, racial = racial, doomEnd = P.dots.baneOfDoom }
      if racial then break end
      local s = C.SPELLS[k]
      local done = (k == 'lifeTap' or (s and s.kind == 'channel')) and P.t or P.t + H.castTime(C, P, k)
      local nextT = P.t + H.occupies(C, P, k) + C.lat
      H.effects(C, P, k, done)
      P.t = nextT
    end
    return WLX.jsonEncode({ policy = tostring(C.cfg.options.activesPolicy), castsDoom = C.castsDoom == true, steps = WLX.jsonArray(steps) })`));
}
{
  const BLOOD_FURY = 20572, BERSERKING = 20554;
  const seq = p => p.steps.map(x => x.key + (x.racial ? '+racial' : '')).join(' ');
  const before = bad;
  // 1. Wrack DS, Orc: Blood Fury waits for the first Wrack.
  const w = racialPlan('wrack_ds', 'orc', BLOOD_FURY);
  if (w.policy !== 'doom' || w.castsDoom) fail(`racial timing: wrack_ds should be a no-Doom build on the "doom" policy (policy ${w.policy}, castsDoom ${w.castsDoom})`);
  const wi = w.steps.findIndex(x => x.fill);
  if (wi < 1) fail(`racial timing: wrack_ds should open with DoTs before its first filler: ${seq(w)}`);
  else {
    const early = w.steps.slice(0, wi).filter(x => x.racial);
    if (early.length) fail(`racial timing: wrack_ds (Orc) shows Blood Fury with an opening spell (${early.map(x => x.key).join(', ')}): ${seq(w)}`);
    if (!w.steps.slice(0, wi).some(x => x.key === 'curseOfElements' || /bane/i.test(x.key))) fail(`racial timing: wrack_ds opener has no curse: ${seq(w)}`);
    if (w.steps[wi].key !== 'wrack' || !w.steps[wi].racial) fail(`racial timing: wrack_ds (Orc) does not show Blood Fury with the first Wrack: ${seq(w)}`);
  }
  // 2. Wrack DS, Troll: Berserking from the first spell.
  const b = racialPlan('wrack_ds', 'troll', BERSERKING);
  if (!b.steps.length || !b.steps[0].racial || b.steps[0].fill) fail(`racial timing: wrack_ds (Troll) does not show Berserking with the first spell: ${seq(b)}`);
  // 3. A Doom build, Orc: the old rule - not with the opening Bane of Doom, then when Doom explodes.
  const m = racialPlan('demo_pact_succ_sb', 'orc', BLOOD_FURY);
  const last = m.steps[m.steps.length - 1] || {};
  const doomEnd = m.steps.map(x => x.doomEnd).find(x => x != null);
  if (!m.castsDoom || !m.steps.length || m.steps[0].key !== 'baneOfDoom') fail(`racial timing: demo_pact_succ_sb should open with Bane of Doom: ${seq(m)}`);
  else if (m.steps[0].racial) fail('racial timing: demo_pact_succ_sb (Orc) shows Blood Fury with the opening Bane of Doom');
  else if (!last.racial || doomEnd == null || last.t < doomEnd - 4 || last.t > doomEnd + 4) fail(`racial timing: demo_pact_succ_sb (Orc) Blood Fury at ${last.t != null ? last.t.toFixed(1) : '-'} s (racial ${!!last.racial}), Bane of Doom explodes at ${doomEnd != null ? doomEnd.toFixed(1) : '-'} s`);
  if (bad === before) console.log(`ok   racial timing: Wrack DS Blood Fury with Wrack at ${w.steps[wi].t.toFixed(1)} s after ${w.steps.slice(0, wi).map(x => x.key).join(', ')}; Berserking with ${b.steps[0].key} at 0 s; Shadow Demo Blood Fury at ${last.t.toFixed(1)} s (Doom explodes at ${doomEnd.toFixed(1)} s)`);
}
console.log(bad ? 'FAIL: ' + bad + ' problems' : 'OK: the helper played ' + builds.length * 2 + ' fights without a problem');
process.exit(bad ? 1 : 0);
