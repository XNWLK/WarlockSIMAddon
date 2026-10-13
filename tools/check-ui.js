// Runs the whole addon against a stand-in for the game (tools/wow-mock.lua): start-up, reading a character, a sim with
// stat weights, the ranking, every tab, the codes, the self-test and the dump. It proves that no line of the addon's own
// code fails on the way - not that the window looks right; that is seen in the game only.
//   node tools/check-ui.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const ROOT = path.join(__dirname, '..');
const SIM = process.env.SIM_DIR || path.join(ROOT, '..', 'wow-forever-warlock-sim');
const WL = require(path.join(SIM, 'tools', 'load-wl.js')).load(SIM, ['engine/settings-code.js']);
const { newLua } = require('./lua-host.js');
const { toLua } = require('./lua-ser.js');
const host = newLua();
host.run(fs.readFileSync(path.join(__dirname, 'wow-mock.lua'), 'utf8'), '@wow-mock.lua');

const toc = fs.readFileSync(path.join(ROOT, 'WarlockSim', 'WarlockSim.toc'), 'utf8').split(/\r?\n/).map(l => l.trim()).filter(l => l && l[0] !== '#');
toc.forEach(f => assert(fs.existsSync(path.join(ROOT, 'WarlockSim', f)), 'the .toc lists a file that does not exist: ' + f));
fs.readdirSync(path.join(ROOT, 'WarlockSim')).filter(f => f.endsWith('.lua')).forEach(f => assert(toc.includes(f), f + ' is not in the .toc'));
host.loadAddon(toc);

const lua = code => host.eval(code);
const step = (name, code) => { const r = lua('local ok, e = xpcall(function() ' + code + ' end, debug.traceback); if not ok then return "ERR " .. tostring(e) end; return e'); if (typeof r === 'string' && r.indexOf('ERR ') === 0) { console.log('FAIL at "' + name + '":\n' + r.slice(4)); process.exit(1); } console.log('ok   ' + name + (r !== null && r !== undefined && r !== true ? ': ' + r : '')); return r; };
const pump = 'local n = 0; while WLX.jobRunning() do MOCK.frame(); n = n + 1; if n > 2000000 then error("the job never ends") end end';
const build = WL.BUILDS[2];                                  // Demo Pact Fire Imp

step('start-up', 'MOCK.talents = ' + toLua(build.talents) + '; MOCK.fire("ADDON_LOADED", "SomethingElse"); MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db and WLX.cfg); WLX.db.options.fights = 10');
step('open the window', 'SlashCmdList.WARLOCKSIM(""); assert(WarlockSimFrame and WarlockSimFrame:IsShown()); return MOCK.find("FontString", "No result yet") and "empty result shown"');
step('sim without a character says so', 'MOCK.click("Sim!"); assert(not WLX.jobRunning())');
step('read in combat is refused', 'MOCK.combat = true; MOCK.click("Read my character"); MOCK.combat = false; assert(WLX.char == nil)');
step('not a Warlock is refused', 'MOCK.class = "MAGE"; MOCK.click("Read my character"); MOCK.class = nil; assert(WLX.char == nil)');
step('read the character', `MOCK.click("Read my character"); local c = WLX.char; assert(c, "no character")
  assert(c.raceKey == "orc" and c.pet == "imp" and c.sacrifice == "succubus", "race / pet / sacrifice: " .. tostring(c.raceKey) .. " " .. tostring(c.pet) .. " " .. tostring(c.sacrifice))
  local n = 0; for k, v in pairs(c.talents) do n = n + v end; assert(n == 51, "talent points " .. n)
  assert(c.buffsOnYou.arcaneIntellect and c.buffsOnYou.blessingOfKings, "buffs on you")
  assert(#c.otherAuras == 1 and c.otherAuras[1] == "Demon Armor", "other auras")
  assert(c.sheet.sp == 712 and c.sheet.spShadow == 733 and c.sheet.crit == 18.4 and c.sheet.hit == 9 and c.sheet.mp5 == 40)
  return string.format("gear: SP %s, Int %s, Sta %s, crit %s, hit %s, shadow +%s; template %s", c.gear.sp, c.gear.int, c.gear.sta, c.gear.critPct, c.gear.hitPct, c.gear.shadowSp, WLX.bestTemplate(c.talents, WLX.templates(), c.pet))`);
step('the sim\'s totals equal the sheet', `local b = WLX.characterBuildNow(); local cfg = WLX.copy(WLX.DEFAULT_CONFIG)
  for k, x in pairs(cfg.buffs) do x.on = WLX.char.buffsOnYou[k] and true or false end; for _, x in pairs(cfg.consumables) do x.on = false end
  cfg.gear = WLX.copy(WLX.char.gear); local s = WLX.computeStats(b, "orc", cfg)
  assert(math.abs(s.int - 420) < 0.01 and math.abs(s.sta - 430) < 0.01 and math.abs(s.spi - 260) < 0.01 and math.abs(s.sp - 712) < 0.01 and math.abs(s.critPct - 18.4) < 0.01, "totals " .. s.int .. " " .. s.sta .. " " .. s.spi .. " " .. s.sp .. " " .. s.critPct)`);
step('Sim! with stat weights', 'MOCK.click("Sim!"); assert(WLX.jobRunning(), "no job started"); ' + pump + '; local r = WLX.lastResult; assert(r and r.kind == "single" and r.res.dps > 200, "no result"); assert(r.weights and r.weights.sp ~= nil); return string.format("%.1f DPS, 1 SP = %.2f DPS, %d fights", r.res.dps, r.weights.sp, r.fights)');
step('every tab, every tooltip', `for _, name in ipairs({ "Builds", "Fight", "Buffs", "Codes", "Character" }) do
    for _, f in ipairs(MOCK.frames) do if f.__kind == "Button" and f.scripts.OnClick and not f.template then local kids = 0 end end
  end
  local tips = 0
  for _, f in ipairs(MOCK.frames) do if f.scripts.OnEnter then f.scripts.OnEnter(f); tips = tips + 1; if f.scripts.OnLeave then f.scripts.OnLeave(f) end end end
  return tips .. " tooltips"`);
step('rank the builds', 'WLX.db.options.weights = false; MOCK.click("Rank the builds"); ' + pump + '; local r = WLX.lastResult; assert(r.kind == "rank" and #r.rows == 8, "rows " .. tostring(r.rows and #r.rows)); return r.rows[1].build.short .. " first with " .. string.format("%.1f", r.rows[1].res.dps) .. ", my character at place " .. (function() for i = 1, #r.rows do if r.rows[i].build.key == "character" then return i end end end)()');
step('click a ranking row and go back', `local row; for _, f in ipairs(MOCK.frames) do if f.__kind == "Button" and f.onClick and f.shown then row = f; break end end
  assert(row, "no clickable row"); row.scripts.OnClick(row); assert(MOCK.findLike("FontString", "back to the ranking"), "no way back shown")
  local sub; for _, f in ipairs(MOCK.frames) do if f.__kind == "Button" and f.scripts.OnClick and f.width == 406 and f.height == 14 then sub = f end end
  assert(sub, "no back button"); sub.scripts.OnClick(sub); assert(MOCK.findLike("FontString", "^Best: "), "ranking not shown again")`);
const settingsCode = 'WFS1:' + Buffer.from(JSON.stringify(JSON.parse(JSON.stringify(WL.settingsSnapshot(Object.assign(JSON.parse(JSON.stringify(WL.DEFAULT_CONFIG)), {})))))).toString('base64');
const b2 = JSON.parse(JSON.stringify(WL.BUILDS[5]));
const buildCode = 'WFB1:' + Buffer.from(JSON.stringify({ v: 1, short: 'My web build', talents: b2.talents, pet: b2.pet, sacrifice: b2.sacrifice || null, oil: b2.oil, rotation: b2.rotation, p: b2.params })).toString('base64');
step('codes: load settings, load a build, make both codes', `local box; for _, f in ipairs(MOCK.frames) do if f.__kind == "EditBox" and not f.template then box = f end end; assert(box, "no code box")
  box:SetText(${JSON.stringify(settingsCode)}); MOCK.click("Load the code")
  box:SetText(${JSON.stringify(buildCode)}); MOCK.click("Load the code"); assert(#WLX.imported == 1 and WLX.db.options.template == "import1", "build not imported")
  box:SetText("nonsense"); MOCK.click("Load the code")
  MOCK.click("My settings as a code"); assert(box:GetText():sub(1, 5) == "WFS1:"); local o = WLX.decodeSettings(box:GetText()); assert(o.gear.sp == WLX.char.gear.sp, "the code carries the character's gear")
  MOCK.click("My character as a build code"); assert(box:GetText():sub(1, 5) == "WFB1:"); local b = WLX.decodeBuild(box:GetText()); assert(b.pet == "imp")
  return "imported: " .. WLX.imported[1].short`);
step('settings widgets write through', `MOCK.click("Nothing"); for k, b in pairs(WLX.cfg.buffs) do assert(not b.on, k) end
  MOCK.click("The sim's defaults"); assert(WLX.cfg.buffs.arcaneIntellect.on)
  MOCK.click("Back to the sim's settings"); MOCK.click("Forget loaded builds"); assert(#WLX.imported == 0)`);
step('stop a running sim', 'WLX.db.options.fights = 5000; MOCK.click("Sim!"); MOCK.frame(); assert(WLX.jobRunning()); MOCK.click("Stop"); assert(not WLX.jobRunning()); WLX.db.options.fights = 10');
step('/wsim test', 'SlashCmdList.WARLOCKSIM("test"); local t = WLX.db.selfTest; assert(t and t.ok, "self-test failed: " .. table.concat(t and t.lines or {}, " | ")); return t.fights .. " fights match"');
step('/wsim dump, read, help, close', 'SlashCmdList.WARLOCKSIM("dump"); assert(WLX.db.dump.character.raw.nodeCount == #WLX.TALENTS); SlashCmdList.WARLOCKSIM("read"); SlashCmdList.WARLOCKSIM("help"); SlashCmdList.WARLOCKSIM(""); assert(not WarlockSimFrame:IsShown()); MOCK.fire("PLAYER_LOGOUT"); assert(WLX.db.settings.v == 1)');
step('a second session starts from the saved settings', 'local saved = WarlockSimDB; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db == saved and WLX.cfg.fight.duration == 120)');
console.log('\n' + host.limits());
console.log('Chat lines the addon printed: ' + lua('return #MOCK.chat'));
console.log('OK: the addon runs start to finish against the stand-in game');
