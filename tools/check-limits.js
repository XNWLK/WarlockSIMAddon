// How many more local variables fit into WL.simulateOnce (Sim.lua) before Lua's limit of 200 per function is reached.
// The game's Lua 5.1 and the test runner share this limit. Run after adding to the fight function.
const fs = require('fs'), path = require('path');
const { newLua } = require('./lua-host.js');
const src = fs.readFileSync(path.join(__dirname, '..', 'WarlockSim', 'Sim.lua'), 'utf8');
const MARK = '  local petDmg = 0\n';
if (src.split(MARK).length !== 2) throw new Error('marker line not found in Sim.lua');
const h = newLua();
function fits(k) {
  let extra = ''; for (let i = 0; i < k; i++) extra += '  local zz' + i + ' = 0\n';
  h.run('__t = ' + JSON.stringify(src.replace(MARK, () => extra + MARK)));
  return h.eval('return load(__t, "@Sim.lua") ~= nil');
}
let k = 0; while (k < 200 && fits(k + 1)) k++;
console.log('Room for ' + k + ' more local variables in the fight function (limit 200, used ' + (200 - k) + ')' + (k < 10 ? '  <-- TOO CLOSE: group some into a table' : ''));
process.exit(k < 10 ? 1 : 0);
