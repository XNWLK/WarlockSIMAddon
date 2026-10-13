// Runs the addon's Lua files outside the game, in fengari (a Lua VM written in JavaScript; test tool only).
// The game runs Lua 5.1, fengari Lua 5.3: the addon's files must keep to what both understand. What the game has and
// fengari lacks (the `bit` library) is supplied here. Two limits of the game's Lua 5.1 that fengari does not enforce are
// counted while the code runs and reported by limits(): 60 upvalues per function and (enforced by both) 200 locals.
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const ADDON_DIR = path.join(__dirname, '..', 'WarlockSim');

const PRELUDE = `
unpack = unpack or table.unpack
WLX = {}
HOST = { maxUp = 0, maxUpWhere = '' }
debug.sethook(function()
  local i = debug.getinfo(2, 'uS')
  if i and i.what == 'Lua' and i.nups > HOST.maxUp then HOST.maxUp = i.nups; HOST.maxUpWhere = i.short_src .. ':' .. i.linedefined end
end, 'c')
function HOST.load(src, name) local f = assert(load(src, name)); return f('WarlockSim', WLX) end
`;

function newLua() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  function run(code, name) {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || '=chunk')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
      const msg = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1);
      throw new Error('Lua: ' + msg);
    }
    const t = lua.lua_type(L, -1);
    let v = null;
    if (t === lua.LUA_TSTRING) v = to_jsstring(lua.lua_tostring(L, -1));
    else if (t === lua.LUA_TNUMBER) v = lua.lua_tonumber(L, -1);
    else if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1);
    lua.lua_pop(L, 1);
    return v;
  }
  // fengari's whole numbers are 32 bits wide and wrap around; the game's Lua 5.1 has only 64-bit floats. So the bit
  // library and math.floor / math.ceil are given here as JavaScript functions that return floats.
  const reg = (tbl, name, fn) => {
    lua.lua_getglobal(L, to_luastring(tbl));
    if (lua.lua_isnil(L, -1)) { lua.lua_pop(L, 1); lua.lua_newtable(L); lua.lua_pushvalue(L, -1); lua.lua_setglobal(L, to_luastring(tbl)); }
    lua.lua_pushjsfunction(L, LL => { const n = lua.lua_gettop(LL), a = []; for (let i = 1; i <= n; i++) a.push(lua.lua_tonumber(LL, i)); lua.lua_pushnumber(LL, fn.apply(null, a)); return 1; });
    lua.lua_setfield(L, -2, to_luastring(name)); lua.lua_pop(L, 1);
  };
  reg('bit', 'bxor', (a, b) => (a ^ b) >>> 0);
  reg('bit', 'bor', (a, b) => (a | b) >>> 0);
  reg('bit', 'band', (a, b) => (a & b) >>> 0);
  reg('bit', 'rshift', (a, n) => a >>> n);
  reg('bit', 'lshift', (a, n) => (a << n) >>> 0);
  reg('math', 'floor', Math.floor);
  reg('math', 'ceil', Math.ceil);
  run(PRELUDE, '=prelude');
  return {
    run, eval: run,
    // The addon's files in the order given, each called with the addon's name and its shared table like the game does.
    loadAddon(files) {
      files.forEach(f => {
        const src = fs.readFileSync(path.join(ADDON_DIR, f), 'utf8');
        lua.lua_pushstring(L, to_luastring(src)); lua.lua_setglobal(L, to_luastring('__src'));
        run('return HOST.load(__src, "@' + f + '")', '=load ' + f);
      });
    },
    limits() {
      const n = run('return HOST.maxUp'), where = run('return HOST.maxUpWhere');
      // fengari counts the globals table (_ENV) as one upvalue of a function that uses globals; the game's Lua does not.
      return 'Most upvalues in one function: ' + n + ' (limit in the game: 60) at ' + where + (n > 58 ? '  <-- TOO CLOSE' : '');
    },
  };
}
module.exports = { newLua };
