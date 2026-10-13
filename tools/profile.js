// Where the fight engine spends its calls: plays some fights and counts how often each Lua function is called.
// The test runner is far slower than the game, so times here mean little; call counts show what is worth trimming.
//   node tools/profile.js [build key] [fights]
// Also prints the time per fight in the test runner (compare before / after a change; the game is ~80x faster).
const { newLua } = require('./lua-host.js');
const key = process.argv[2] || 'demo_pact_succ_sb', n = parseInt(process.argv[3], 10) || 10;
const host = newLua();
host.loadAddon(['Data.lua', 'Engine.lua', 'Sim.lua']);
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'WarlockSim', 'Sim.lua'), 'utf8').split('\n');
const eng = fs.readFileSync(path.join(__dirname, '..', 'WarlockSim', 'Engine.lua'), 'utf8').split('\n');
// timing first (no hook)
const t0 = Date.now();
host.run(`local b = WLX.BUILD_BY_KEY["${key}"]; local cfg = WLX.DEFAULT_CONFIG; local st = WLX.computeStats(b, "human", cfg); local tb = WLX.buildSpellTable(b, st, cfg)
  for i = 0, ${n - 1} do local s, d = WLX.fightParams(cfg, i); WLX.simulateOnce(b, "human", cfg, { stats = st, table = tb, seed = s, duration = d }) end`);
const ms = (Date.now() - t0) / n;
const out = host.eval(`
local counts = {}
debug.sethook(function() local i = debug.getinfo(2, 'S'); if i.what == 'Lua' then local k = i.short_src .. ':' .. i.linedefined; counts[k] = (counts[k] or 0) + 1 end end, 'c')
local b = WLX.BUILD_BY_KEY["${key}"]; local cfg = WLX.DEFAULT_CONFIG; local st = WLX.computeStats(b, "human", cfg); local tb = WLX.buildSpellTable(b, st, cfg)
for i = 0, ${n - 1} do local s, d = WLX.fightParams(cfg, i); WLX.simulateOnce(b, "human", cfg, { stats = st, table = tb, seed = s, duration = d }) end
debug.sethook()
local list = {}
for k, v in pairs(counts) do list[#list + 1] = k .. '=' .. v end
return table.concat(list, ';')`);
const rows = out.split(';').map(x => { const [k, v] = x.split('='); return { k, v: +v }; }).sort((a, b) => b.v - a.v);
const total = rows.reduce((a, r) => a + r.v, 0);
console.log(key + ': ' + ms.toFixed(0) + ' ms a fight in the test runner; ' + Math.round(total / n) + ' Lua function calls a fight');
rows.slice(0, 28).forEach(r => {
  const [file, line] = r.k.split(':');
  const text = ((file === 'Sim.lua' ? src : eng)[+line - 1] || '').trim().slice(0, 70);
  console.log(String(Math.round(r.v / n)).padStart(7) + '  ' + r.k.padEnd(16) + text);
});
