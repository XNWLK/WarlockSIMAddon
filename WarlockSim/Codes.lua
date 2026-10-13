-- The website's codes: a settings code ("WFS1:...") and a build code ("WFB1:..."), read and written the way the sim's
-- engine/settings-code.js and engine/custom-builds.js do, so codes go both ways between the page and the game.
-- A code is its prefix + base64 of JSON text. JSON and base64 are written out here (no game API in this file).
-- Not read here: the page's share links ("#share=..."), which are compressed.
local ADDON, WL = ...

local floor, huge = math.floor, math.huge
local byte, char, sub, format, concat = string.byte, string.char, string.sub, string.format, table.concat
local indexOf, copy = WL.indexOf, WL.copy

-- ---------------------------------------------------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------------------------------------------------
local ARRAY = {}                                            -- metatable that marks a table as a JSON list (also when empty)
function WL.jsonArray(t) return setmetatable(t or {}, ARRAY) end
WL.JSON_NULL = setmetatable({}, { __tostring = function() return 'null' end })
local NULL = WL.JSON_NULL

local function isArray(t)
  if getmetatable(t) == ARRAY then return true end
  local n = #t
  if n == 0 then return false end
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c == n
end
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function encStr(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or format('\\u%04x', byte(c)) end) .. '"'
end
local function encNum(x)
  if x ~= x or x == huge or x == -huge then return 'null' end
  if x == floor(x) and x > -1e15 and x < 1e15 then return format('%.0f', x) end
  for p = 14, 17 do
    local s = format('%.' .. p .. 'g', x)
    if tonumber(s) == x then return s end
  end
  return format('%.17g', x)
end
local function encode(v, out)
  local t = type(v)
  if v == nil or v == NULL then out[#out + 1] = 'null'
  elseif t == 'boolean' then out[#out + 1] = v and 'true' or 'false'
  elseif t == 'number' then out[#out + 1] = encNum(v)
  elseif t == 'string' then out[#out + 1] = encStr(v)
  elseif t == 'table' then
    if isArray(v) then
      out[#out + 1] = '['
      for i = 1, #v do
        if i > 1 then out[#out + 1] = ',' end
        encode(v[i], out)
      end
      out[#out + 1] = ']'
    else
      local keys = {}
      for k in pairs(v) do if type(k) == 'string' then keys[#keys + 1] = k end end
      table.sort(keys)
      out[#out + 1] = '{'
      for i = 1, #keys do
        if i > 1 then out[#out + 1] = ',' end
        out[#out + 1] = encStr(keys[i]); out[#out + 1] = ':'
        encode(v[keys[i]], out)
      end
      out[#out + 1] = '}'
    end
  else error('cannot write a ' .. t .. ' as JSON') end
end
function WL.jsonEncode(v)
  local out = {}
  encode(v, out)
  return concat(out)
end

local function utf8(cp)
  if cp < 0x80 then return char(cp) end
  if cp < 0x800 then return char(0xC0 + floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then return char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64) end
  return char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64, 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
end
local UNESC = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
-- Returns the value, or nil and a message. JSON null becomes nil (a missing field).
function WL.jsonDecode(s)
  local pos, len = 1, #s
  local value
  local function ws() local _, e = s:find('^[ \n\r\t]*', pos); pos = e + 1 end
  local function fail(m) error({ json = m .. ' at character ' .. pos }) end
  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local a = s:find('["\\]', pos)
      if not a then fail('text without an end') end
      out[#out + 1] = sub(s, pos, a - 1)
      if sub(s, a, a) == '"' then pos = a + 1; break end
      local c = sub(s, a + 1, a + 1)
      if c == 'u' then
        local cp = tonumber(sub(s, a + 2, a + 5), 16)
        if not cp then fail('bad \\u') end
        pos = a + 6
        if cp >= 0xD800 and cp < 0xDC00 and sub(s, pos, pos + 1) == '\\u' then    -- surrogate pair
          local lo = tonumber(sub(s, pos + 2, pos + 5), 16)
          if lo and lo >= 0xDC00 and lo < 0xE000 then cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00); pos = pos + 6 end
        end
        out[#out + 1] = utf8(cp)
      else
        if not UNESC[c] then fail('bad escape') end
        out[#out + 1] = UNESC[c]; pos = a + 2
      end
    end
    return concat(out)
  end
  value = function()
    ws()
    local c = sub(s, pos, pos)
    if c == '{' then
      local o = {}
      pos = pos + 1; ws()
      if sub(s, pos, pos) == '}' then pos = pos + 1; return o end
      while true do
        ws()
        if sub(s, pos, pos) ~= '"' then fail('a name was expected') end
        local k = str()
        ws()
        if sub(s, pos, pos) ~= ':' then fail('":" was expected') end
        pos = pos + 1
        o[k] = value()
        ws()
        local d = sub(s, pos, pos)
        pos = pos + 1
        if d == '}' then return o end
        if d ~= ',' then fail('"," was expected') end
      end
    elseif c == '[' then
      local a, n = WL.jsonArray(), 0
      pos = pos + 1; ws()
      if sub(s, pos, pos) == ']' then pos = pos + 1; return a end
      while true do
        local v = value()
        n = n + 1
        a[n] = v == nil and NULL or v
        ws()
        local d = sub(s, pos, pos)
        pos = pos + 1
        if d == ']' then return a end
        if d ~= ',' then fail('"," was expected') end
      end
    elseif c == '"' then return str()
    elseif sub(s, pos, pos + 3) == 'true' then pos = pos + 4; return true
    elseif sub(s, pos, pos + 4) == 'false' then pos = pos + 5; return false
    elseif sub(s, pos, pos + 3) == 'null' then pos = pos + 4; return nil
    else
      local a, e = s:find('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
      local n = a and tonumber(sub(s, a, e))
      if not n then fail('unexpected text') end
      pos = e + 1
      return n
    end
  end
  local ok, res = pcall(value)
  if not ok then return nil, type(res) == 'table' and res.json or tostring(res) end
  ws()
  if pos <= len then return nil, 'text after the end' end
  return res
end

-- ---------------------------------------------------------------------------------------------------------------------
-- base64
-- ---------------------------------------------------------------------------------------------------------------------
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64V = {}
for i = 1, 64 do B64V[byte(B64, i)] = i - 1 end
function WL.base64Encode(s)
  local out, n = {}, #s
  for i = 1, n, 3 do
    local a, b, c = byte(s, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = floor(v / 262144), floor(v / 4096) % 64, floor(v / 64) % 64, v % 64
    out[#out + 1] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1) .. (b and sub(B64, c3 + 1, c3 + 1) or '=') .. (c and sub(B64, c4 + 1, c4 + 1) or '=')
  end
  return concat(out)
end
function WL.base64Decode(s)
  s = s:gsub('=+$', '')
  local out, n = {}, #s
  for i = 1, n, 4 do
    local a, b, c, d = B64V[byte(s, i)], B64V[byte(s, i + 1) or 0], B64V[byte(s, i + 2) or 0], B64V[byte(s, i + 3) or 0]
    if not a or not b or (i + 2 <= n and not c) or (i + 3 <= n and not d) then return nil end
    local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    if i + 3 <= n then out[#out + 1] = char(floor(v / 65536), floor(v / 256) % 256, v % 256)
    elseif i + 2 <= n then out[#out + 1] = char(floor(v / 65536), floor(v / 256) % 256)
    else out[#out + 1] = char(floor(v / 65536)) end
  end
  return concat(out)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- settings code (settings-code.js)
-- ---------------------------------------------------------------------------------------------------------------------
WL.SETTINGS_CODE_PREFIX = 'WFS1:'
WL.BUILD_CODE_PREFIX = 'WFB1:'

local function onKeys(o, order)
  local a = WL.jsonArray()
  for i = 1, #order do if o and o[order[i]] and o[order[i]].on then a[#a + 1] = order[i] end end
  return a
end
function WL.settingsSnapshot(c)
  local options = copy(c.options)
  if options.alwaysShowBestTrees then WL.jsonArray(options.alwaysShowBestTrees) end
  return {
    v = 1, fight = c.fight, gear = c.gear, options = options,
    buffs = onKeys(c.buffs, WL.BUFF_ORDER), debuffs = onKeys(c.debuffs, WL.DEBUFF_ORDER), cons = onKeys(c.consumables, WL.CONSUMABLE_ORDER),
    prof = c.professions or {}, petSpPct = c.petSpPct,
    succ = { apPerSp = c.pets.succubus.melee.apPerSp, baseDps = c.pets.succubus.melee.baseDps },
    bossArmor = c.combat.bossArmor,
    resist = c.combat.targetResist, levelResist = (c.combat.levelResist and c.combat.levelResist.on) and true or false,
  }
end
function WL.encodeSettings(c)
  return WL.SETTINGS_CODE_PREFIX .. WL.base64Encode(WL.jsonEncode(WL.settingsSnapshot(c)))
end
local function decodeCode(code, prefix, what)
  local s = tostring(code or ''):gsub('%s+', '')
  if sub(s, 1, #prefix) ~= prefix then return nil, 'Not a ' .. what .. ' code (it must start with ' .. prefix .. ')' end
  local raw = WL.base64Decode(sub(s, #prefix + 1))
  local o = raw and WL.jsonDecode(raw)
  if type(o) ~= 'table' then return nil, 'The ' .. what .. ' code is damaged (could not be read)' end
  return o
end
function WL.decodeSettings(code)
  local o, err = decodeCode(code, WL.SETTINGS_CODE_PREFIX, 'settings')
  if not o then return nil, err end
  if o.v ~= 1 then return nil, 'Unknown settings-code version' end
  return o
end
local function isNum(x) return type(x) == 'number' and x == x and x ~= huge and x ~= -huge end
-- Applies a snapshot onto config `c` in place. Returns the list of names in the code that this version does not know.
function WL.applySettings(c, o)
  local unknown = {}
  local secs = { 'fight', 'gear', 'options' }
  for i = 1, 3 do
    local sec = secs[i]
    if type(o[sec]) == 'table' then
      for k, v in pairs(o[sec]) do
        if c[sec][k] ~= nil then c[sec][k] = v
        elseif not indexOf(WL.RETIRED_SETTINGS, sec .. '.' .. k) then unknown[#unknown + 1] = sec .. '.' .. k end
      end
    end
  end
  local pairsOf = { { 'buffs', 'buffs' }, { 'debuffs', 'debuffs' }, { 'cons', 'consumables' } }
  for i = 1, 3 do
    local list, tgt = type(o[pairsOf[i][1]]) == 'table' and o[pairsOf[i][1]] or {}, c[pairsOf[i][2]] or {}
    for k, e in pairs(tgt) do e.on = indexOf(list, k) ~= nil end
    for j = 1, #list do if not tgt[list[j]] then unknown[#unknown + 1] = pairsOf[i][1] .. '.' .. tostring(list[j]) end end
  end
  c.professions = c.professions or {}
  for k in pairs(c.professions) do c.professions[k] = (type(o.prof) == 'table' and o.prof[k]) and true or false end
  if isNum(o.petSpPct) then c.petSpPct = o.petSpPct end
  if type(o.succ) == 'table' then
    if isNum(o.succ.apPerSp) then c.pets.succubus.melee.apPerSp = o.succ.apPerSp end
    if isNum(o.succ.baseDps) then c.pets.succubus.melee.baseDps = o.succ.baseDps end
  end
  if isNum(o.bossArmor) then c.combat.bossArmor = o.bossArmor end
  if type(o.resist) == 'table' then
    if isNum(o.resist.shadow) then c.combat.targetResist.shadow = o.resist.shadow end
    if isNum(o.resist.fire) then c.combat.targetResist.fire = o.resist.fire end
  end
  if type(o.levelResist) == 'boolean' and c.combat.levelResist then c.combat.levelResist.on = o.levelResist end
  return unknown
end

-- ---------------------------------------------------------------------------------------------------------------------
-- build code (custom-builds.js)
-- ---------------------------------------------------------------------------------------------------------------------
function WL.encodeBuild(b)
  local o = { v = 1, short = b.short, talents = b.talents, pet = b.pet or NULL, sacrifice = b.sacrifice or NULL, oil = b.oil, rotation = WL.jsonArray(copy(b.rotation)) }
  if b.timeline and #b.timeline > 0 then
    o.tl = WL.jsonArray()
    for i = 1, #b.timeline do o.tl[i] = WL.jsonArray({ floor(b.timeline[i].t * 100 + 0.5) / 100, b.timeline[i].k }) end
  end
  local p = WL.cleanParams(b.params, b.rotation)
  if p then o.p = p end
  return WL.BUILD_CODE_PREFIX .. WL.base64Encode(WL.jsonEncode(o))
end
function WL.decodeBuild(code)
  local o, err = decodeCode(code, WL.BUILD_CODE_PREFIX, 'build')
  if not o then return nil, err end
  if o.v ~= 1 or type(o.talents) ~= 'table' then return nil, 'Unknown build-code version' end
  local b = { short = sub(tostring(o.short or 'Custom build'), 1, 40), talents = {}, pet = type(o.pet) == 'string' and o.pet or nil,
              sacrifice = type(o.sacrifice) == 'string' and o.sacrifice or nil, oil = type(o.oil) == 'string' and o.oil or 'none', rotation = {} }
  for k, v in pairs(o.talents) do if type(v) == 'number' then b.talents[k] = v end end
  if type(o.rotation) == 'table' then
    local rot = {}
    for i = 1, #o.rotation do rot[i] = tostring(o.rotation[i]) end
    b.rotation = WL.migrateRotation(rot)
  end
  b.params = type(o.p) == 'table' and WL.cleanParams(o.p) or nil
  if type(o.tl) == 'table' then
    b.timeline = {}
    for i = 1, #o.tl do
      local x = o.tl[i]
      if type(x) == 'table' and tostring(x[2]) ~= 'shadowBoltR2' then b.timeline[#b.timeline + 1] = { t = tonumber(x[1]) or 0, k = tostring(x[2]) } end
    end
  end
  return b
end
