// A practice page for the helper bar, in a browser on this computer: http://localhost:8642
// The addon's real Lua code runs here (in the Lua runner of the checks), against a stand-in game (wow-mock.lua) and a
// practice boss (arena.lua). The page sends your key presses and draws what the addon shows. Test tool only.
//   node tools/arena-server.js        (PORT=... for another port)
const http = require('http'), fs = require('fs'), path = require('path');
const { newLua } = require('./lua-host.js');
const ROOT = path.join(__dirname, '..');
const PORT = +process.env.PORT || 8642;
const toc = fs.readFileSync(path.join(ROOT, 'WarlockSim', 'WarlockSim.toc'), 'utf8').split(/\r?\n/).map(l => l.trim()).filter(l => l && l[0] !== '#');

let host = null;
const q = s => JSON.stringify(String(s));     // a JavaScript string as a Lua string (plain ASCII here)
function lua(code) {
  const r = host.run('local ok, r = xpcall(function() ' + code + ' end, debug.traceback); if not ok then return "ERR " .. tostring(r) end; return r');
  if (typeof r === 'string' && r.startsWith('ERR ')) throw new Error(r.slice(4));
  return r;
}
function state() { return lua('return WLX.jsonEncode(ARENA.state())'); }

// A fresh game: the addon loaded, a character with the talents, demon and race of a ready build read, the helper on.
function reset(opt) {
  host = newLua();
  host.run("debug.sethook()");          // the upvalue counter of the checks is not needed here, and slows every call
  host.run(fs.readFileSync(path.join(__dirname, 'wow-mock.lua'), 'utf8'), '@wow-mock.lua');
  host.run(fs.readFileSync(path.join(__dirname, 'arena.lua'), 'utf8'), '@arena.lua');
  host.loadAddon(toc);
  const set = opt.set || {};
  lua(`
    local b = WLX.BUILDS[1]
    for _, x in ipairs(WLX.BUILDS) do if x.key == ${q(opt.build || '')} then b = x end end
    ARENA.race = ARENA.RACES[${q(opt.race || 'orc')}] and ${q(opt.race || 'orc')} or 'orc'
    MOCK.talents = b.talents
    MOCK.pet = b.pet and ARENA.PET_NPC[b.pet] or nil
    MOCK.auras = { { name = 'Arcane Intellect', spellId = 10157 }, { name = 'Demon Armor', spellId = 11735 }, { name = 'Greater Blessing of Kings', spellId = 25898 } }
    if b.sacrifice then local s = ARENA.SAC_AURA[b.sacrifice]; MOCK.auras[#MOCK.auras + 1] = { name = s[2], spellId = s[1] } end
    MOCK.fire('ADDON_LOADED', 'WarlockSim'); MOCK.fire('PLAYER_LOGIN')
    WLX.db.options.template = b.key
    local ch, err = WLX.doReadCharacter(); assert(ch, err)
    ${Object.keys(set).map(k => `ARENA.set[${q(k)}] = ${typeof set[k] === 'boolean' ? set[k] : +set[k]}`).join('\n    ')}
    WLX.helper.toggle(true)
    ARENA.setup()`);
  return state();
}
function step(body) {
  const set = body.set || {};
  const lines = Object.keys(set).filter(k => k !== 'length').map(k => `ARENA.set[${q(k)}] = ${typeof set[k] === 'boolean' ? set[k] : +set[k]}`);
  const presses = (body.press || []).map(k => `do local why = ARENA.press(${q(k)}); if why then ARENA.log[#ARENA.log + 1] = '       ' .. why end end`);
  if (body.pull) presses.unshift('ARENA.pull()');
  lua(lines.join('\n') + '\n' + presses.join('\n') + `\nARENA.step(${Math.max(0, Math.min(2, +body.dt || 0))})`);
  return state();
}

function send(res, code, type, body) { res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' }); res.end(body); }
const server = http.createServer((req, res) => {
  let data = '';
  req.on('data', c => { data += c; if (data.length > 1e5) req.destroy(); });
  req.on('end', () => {
    try {
      const body = data ? JSON.parse(data) : {};
      if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) return send(res, 200, 'text/html; charset=utf-8', fs.readFileSync(path.join(__dirname, 'arena.html')));
      if (req.url === '/api/builds') {
        if (!host) reset({});
        return send(res, 200, 'application/json', lua('local o = {}; for i, b in ipairs(WLX.BUILDS) do o[i] = { key = b.key, short = b.short, pet = b.pet } end; return WLX.jsonEncode(WLX.jsonArray(o))'));
      }
      if (req.url === '/api/reset') return send(res, 200, 'application/json', reset(body));
      if (req.url === '/api/step') { if (!host) reset({}); return send(res, 200, 'application/json', step(body)); }
      send(res, 404, 'text/plain', 'not found');
    } catch (e) {
      console.error(e.message);
      send(res, 500, 'application/json', JSON.stringify({ error: e.message }));
    }
  });
});
module.exports = { reset, step, lua };
if (require.main === module) server.listen(PORT, '127.0.0.1', () => console.log('Helper practice page: http://localhost:' + PORT));
