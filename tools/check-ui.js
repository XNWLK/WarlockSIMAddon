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

step('start-up', 'MOCK.talents = ' + toLua(build.talents) + '; MOCK.fire("ADDON_LOADED", "SomethingElse"); MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db and WLX.cfg); MOCK.fire("PLAYER_LOGIN"); assert(#MOCK.chat == 1, "no hello line"); WLX.db.options.fights = 10');
step('open the window (in combat: nothing is read)', 'MOCK.combat = true; SlashCmdList.WARLOCKSIM(""); MOCK.combat = false; assert(WarlockSimFrame and WarlockSimFrame:IsShown()); assert(WLX.char == nil, "read in combat"); return MOCK.find("FontString", "No result yet") and "empty result shown"');
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
step('sim builds with your gear', 'WLX.db.options.weights = false; MOCK.click("Sim builds with your gear"); ' + pump + '; local r = WLX.lastResult; WLX.lastRank = r; assert(r.kind == "rank" and #r.rows == 8, "rows " .. tostring(r.rows and #r.rows)); return r.rows[1].build.short .. " first with " .. string.format("%.1f", r.rows[1].res.dps) .. ", my character at place " .. (function() for i = 1, #r.rows do if r.rows[i].build.key == "character" then return i end end end)()');
step('click a ranking row and go back', `local row; for _, f in ipairs(MOCK.frames) do if f.__kind == "Button" and f.onClick and f.shown then row = f; break end end
  assert(row, "no clickable row"); row.scripts.OnClick(row); assert(MOCK.findLike("FontString", "back to the ranking"), "no way back shown")
  local sub; for _, f in ipairs(MOCK.frames) do if f.__kind == "Button" and f.scripts.OnClick and f.width == 406 and f.height == 14 then sub = f end end
  assert(sub, "no back button"); sub.scripts.OnClick(sub); assert(MOCK.findLike("FontString", "^Best with your gear: "), "ranking not shown again")`);
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
const frames = 'for i = 1, 16 do MOCK.frame() end';
step('item link window: a ring against both rings', `MOCK.refItem = 1001; ItemRefTooltip.shown = true; ${frames}
  assert(WarlockSimItemPanel and WarlockSimItemPanel:IsShown(), "no panel under the item window"); MOCK.click("Sim this item"); assert(WLX.jobRunning(), "no item sim started"); ${pump}; ${frames}
  local t = WarlockSimItemPanel.text.text
  assert(t:find("Instead of Old Band", 1, true) and t:find("Instead of Plain Loop", 1, true), "both rings: " .. t)
  assert(t:find("Change: +8 spell power, +1% hit, +10 Intellect, -8 Stamina", 1, true), "difference to Old Band: " .. t)
  assert(t:find("Change: +20 spell power, +1% hit, +10 Intellect, -3 Spirit", 1, true), "difference to Plain Loop: " .. t)
  assert(WLX.db.lastItem.against[2].unknown[1]:find("Summons a cat") and t:find("Not counted on Plain Loop: Use: Summons a cat", 1, true), "the Use line is noted as not counted: " .. t)
  return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%c", " / "))`);
step('item link window: second click reuses the run as you are', `MOCK.refItem = 1003; ${frames}; MOCK.click("Sim this item"); local _, total = WLX.jobProgress(); assert(total == 150, "fights planned: " .. tostring(total)); ${pump}; ${frames}
  assert(WarlockSimItemPanel.text.text:find("Instead of Old Band", 1, true)); assert(WarlockSimItemPanel.text.text:find("You wear one of these already", 1, true))`);
step('item link window: two-hand weapon, off-hand, worn item, not wearable, switched off', `MOCK.refItem = 1004; ${frames}; MOCK.click("Sim this item"); ${pump}; ${frames}
  assert(WarlockSimItemPanel.text.text:find("Instead of Short Blade and Orb", 1, true), WarlockSimItemPanel.text.text)
  assert(WarlockSimItemPanel.text.text:find("+15 spell power, +1% crit", 1, true), WarlockSimItemPanel.text.text)
  MOCK.equipped[16] = 1004; MOCK.equipped[17] = nil; MOCK.refItem = 1006; ${frames}; MOCK.click("Sim this item"); assert(not WLX.jobRunning()); assert(WarlockSimItemPanel.text.text:find("two-hand weapon", 1, true))
  MOCK.refItem = 1004; ${frames}; MOCK.click("Sim this item"); assert(WLX.jobRunning(), "a worn item is simmed against an empty slot"); ${pump}; ${frames}
  assert(WarlockSimItemPanel.text.text:find("You are wearing this. It is worth", 1, true) and WarlockSimItemPanel.text.text:find("It gives: 60 spell power, 1% crit", 1, true), WarlockSimItemPanel.text.text)
  MOCK.refItem = 1007; ${frames}; assert(not WarlockSimItemPanel:IsShown(), "bread gets no button")
  MOCK.refItem = 1001; ${frames}; assert(WarlockSimItemPanel:IsShown()); WLX.db.options.itemClick = "off"; ${frames}; assert(not WarlockSimItemPanel:IsShown()); WLX.db.options.itemClick = "shift-right"
  ItemRefTooltip.shown = false; MOCK.refItem = nil; ${frames}; assert(not WarlockSimItemPanel:IsShown()); MOCK.equipped[16] = 1005; MOCK.equipped[17] = 1006`);
step('Shift+right-click an item in a bag: the panel opens at the mouse and the sim starts', `MOCK.keys = { shift = true }; MOCK.button = "RightButton"; HandleModifiedItemClick(MOCK.link(1001), MOCK.bagLocation()); MOCK.keys = {}
  assert(WarlockSimItemPanel:IsShown() and WLX.jobRunning(), "no panel or no sim after the click"); assert(WarlockSimItemPanel.title.text == "Ring of Tests" and WarlockSimItemPanel.title:IsShown(), "title")
  ${pump}; ${frames}; assert(WarlockSimItemPanel.text.text:find("Instead of Old Band", 1, true) and WarlockSimItemPanel.text.text:find("Instead of Plain Loop", 1, true), WarlockSimItemPanel.text.text)
  WarlockSimItemPanel.close.scripts.OnClick(WarlockSimItemPanel.close); assert(not WarlockSimItemPanel:IsShown(), "the close button hides it")`);
step('Shift+right-click a slot of the character sheet: what the worn item is worth', `MOCK.keys = { shift = true }; MOCK.button = "RightButton"; PaperDollItemSlotButton_OnModifiedClick(MOCK.slot(11), "RightButton"); MOCK.keys = {}
  assert(WLX.jobRunning(), "no sim: the game ends this click before its general item handler, the slot hook must catch it"); ${pump}; ${frames}
  assert(WarlockSimItemPanel.text.text:find("You are wearing this. It is worth", 1, true) and WarlockSimItemPanel.text.text:find("It gives: 12 spell power, 8 Stamina", 1, true), WarlockSimItemPanel.text.text)
  local worth = tonumber((WarlockSimItemPanel.text.text:gsub("|c%x%x%x%x%x%x%x%x", ""):match("worth:%c([%d%.]+) DPS"))); assert(worth and worth > 0, "worth is a positive number: " .. WarlockSimItemPanel.text.text); return worth .. " DPS"`);
step('other clicks are left alone', `WarlockSimItemPanel:Hide(); MOCK.button = "RightButton"; local bag = MOCK.bagLocation()
  MOCK.keys = { alt = true, shift = true }; HandleModifiedItemClick(MOCK.link(1001), bag); assert(not WarlockSimItemPanel:IsShown() and not WLX.jobRunning(), "Shift+Alt+right")
  MOCK.keys = { alt = true }; HandleModifiedItemClick(MOCK.link(1001), bag); assert(not WarlockSimItemPanel:IsShown(), "Alt+right is no longer the click")
  MOCK.keys = { shift = true }; MOCK.button = "LeftButton"; HandleModifiedItemClick(MOCK.link(1001), bag); assert(not WarlockSimItemPanel:IsShown(), "Shift+left (the chat link click)")
  MOCK.button = "RightButton"; HandleModifiedItemClick(MOCK.link(1007), bag); assert(not WarlockSimItemPanel:IsShown(), "bread")
  HandleModifiedItemClick(nil, nil); PaperDollItemSlotButton_OnModifiedClick(MOCK.slot(5), "RightButton"); assert(not WarlockSimItemPanel:IsShown(), "an empty slot")
  WLX.db.options.itemClick = "off"; HandleModifiedItemClick(MOCK.link(1001), bag); PaperDollItemSlotButton_OnModifiedClick(MOCK.slot(11), "RightButton"); assert(not WarlockSimItemPanel:IsShown(), "switched off")
  WLX.db.options.itemClick = "shift-right"; MOCK.keys = {}`);
step('the click can be chosen; the tip names it', `local bag = MOCK.bagLocation()
  assert(MOCK.findLike("FontString", "Shift %+ right%-click any item"), "the tip line names Shift + right-click")
  WLX.db.options.itemClick = "alt-right"; WLX.refresh(); assert(MOCK.findLike("FontString", "Alt %+ right%-click any item"), "the tip follows the choice")
  MOCK.keys = { shift = true }; MOCK.button = "RightButton"; HandleModifiedItemClick(MOCK.link(1001), bag); assert(not WarlockSimItemPanel:IsShown(), "Shift+right no longer")
  MOCK.keys = { alt = true }; PaperDollItemSlotButton_OnModifiedClick(MOCK.slot(12), "RightButton"); assert(WarlockSimItemPanel:IsShown() and WLX.jobRunning(), "Alt+right on a slot once chosen")
  local _, total = WLX.jobProgress(); assert(total == 150, "one sim, not two (both hooks saw the click): " .. tostring(total)); WLX.cancelJob(); WarlockSimItemPanel:Hide()
  WLX.db.options.itemClick = "alt-left"; MOCK.button = "LeftButton"; HandleModifiedItemClick(MOCK.link(1001), bag); assert(WarlockSimItemPanel:IsShown(), "Alt+left once chosen"); WLX.cancelJob(); WarlockSimItemPanel:Hide()
  WLX.db.options.itemClick = "off"; WLX.refresh(); assert(MOCK.findLike("FontString", "Item sims are switched off"), "the tip says when it is off")
  WLX.db.options.itemClick = "shift-right"; MOCK.keys = {}; MOCK.button = nil; WLX.refresh(); WLX.cancelJob()`);
step('a saved Alt + right-click from the version before moves to the new default once', `local o = WarlockSimDB.options
  o.itemClick = "alt-right"; o.itemClickDefault = nil; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db.options.itemClick == "shift-right", "moved over")
  WLX.db.options.itemClick = "alt-right"; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db.options.itemClick == "alt-right", "a choice made afterwards stays"); WLX.db.options.itemClick = "shift-right"`);
step('my character stands out in the list of builds', `WLX.showResult(WLX.lastRank); local row = MOCK.findLike("FontString", "%(you%)"); assert(row and row.text:find("|cffffd100", 1, true), "no gold row for the character")`);
const bg = 'local n = 0; repeat MOCK.frame(); n = n + 1 until (n > 40 and not WLX.backgroundRunning() and not WLX.jobRunning()) or n > 3000000; for i = 1, 25 do MOCK.frame() end';
step('character sheet: a number over every worn item, the total over the character', `WLX.db.options.itemFights = 40; PaperDollFrame.shown = true; ${bg}
  local ring, loop, blade, orb = tonumber(MOCK.sheetText(11)), tonumber(MOCK.sheetText(12)), tonumber(MOCK.sheetText(16)), tonumber(MOCK.sheetText(17))
  assert(ring and loop and blade and orb, "a number on each worn item: " .. tostring(MOCK.sheetText(11)) .. " / " .. tostring(MOCK.sheetText(12)) .. " / " .. tostring(MOCK.sheetText(16)) .. " / " .. tostring(MOCK.sheetText(17)))
  assert(blade > orb and orb > 0, "30 spell power is worth more than 15: " .. blade .. " against " .. orb)
  assert(MOCK.sheetText(1) == "", "an empty slot has no number")
  local t = MOCK.findLike("FontString", "%d DPS|r$"); assert(t, "no total over the character"); local s = WLX.sheetState(); assert(s.base > 500 and s.n == 40)
  return "ring " .. ring .. ", loop " .. loop .. ", main hand " .. blade .. ", off-hand " .. orb .. " of " .. string.format("%.0f", s.base) .. " DPS"`);
step('character sheet: nothing is simmed again while nothing changes', `local before = WLX.sheetState().base; for i = 1, 60 do MOCK.frame() end; assert(not WLX.backgroundRunning() and WLX.sheetState().base == before)`);
step('character sheet: a new item starts the work again; a sim of yours goes first', `MOCK.equipped[11] = 1001; for i = 1, 25 do MOCK.frame() end
  assert(WLX.backgroundRunning(), "the background work did not start for the new item"); assert(not WLX.jobRunning(), "background work does not count as a sim of yours")
  MOCK.click("Sim!"); assert(WLX.jobRunning() and not WLX.backgroundRunning(), "your own sim takes over")
  ${pump}; ${bg}
  local ring = tonumber(MOCK.sheetText(11)); assert(ring and ring > 0, "the new ring has its number after the work was taken up again: " .. tostring(MOCK.sheetText(11)))
  assert(WLX.sheetState().worth[11].link == MOCK.link(1001)); MOCK.equipped[11] = 1002`);
step('character sheet: switched off and on; not while fighting', `WLX.db.options.sheetNumbers = false; for i = 1, 25 do MOCK.frame() end; assert(not WLX.backgroundRunning(), "off: no work")
  WLX.db.options.sheetNumbers = true; MOCK.combat = true; for i = 1, 25 do MOCK.frame() end; assert(not WLX.backgroundRunning(), "no work is started in combat")
  MOCK.combat = false; ${bg}; assert(tonumber(MOCK.sheetText(11)), "numbers are back after the fight")
  PaperDollFrame.shown = false; WLX.db.options.itemFights = 150`);
step('character sheet: the numbers are kept over a reload, nothing is simmed again', `PaperDollFrame.shown = true; ${bg}; local before = WLX.sheetState().base
  MOCK.fire("PLAYER_LOGOUT"); local e = WarlockSimDB.chars["Tester-Mock"]; assert(e and e.sheet and e.sheet.base == before, "not saved at logout")
  e.sheet.base = 1234.4; MOCK.fire("PLAYER_LOGIN"); assert(WLX.sheetState().base == 1234.4, "not put back at login")
  for i = 1, 25 do MOCK.frame() end; assert(not WLX.backgroundRunning(), "simmed again although nothing changed"); assert(MOCK.findLike("FontString", "1234 DPS"), "the kept total is shown")
  MOCK.equipped[11] = 1001; ${bg}; assert(WLX.sheetState().base ~= 1234.4, "a changed item works it out again"); MOCK.equipped[11] = 1002; ${bg}; PaperDollFrame.shown = false`);
step('the character is kept over a reload', `local e = WarlockSimDB.chars["Tester-Mock"]; assert(e and e.char and e.char.raw == nil, "the character is saved without the raw game data")
  local gear = WLX.char.gear.sp; WLX.char = nil; MOCK.fire("PLAYER_LOGIN"); assert(WLX.char and WLX.char.restored, "not put back"); assert(WLX.char.gear.sp == gear, "other gear numbers")
  WLX.refresh(); assert(MOCK.findLike("FontString", "kept over the reload"), "the Character tab does not say so")
  WarlockSimDB.chars["Tester-Mock"].char.talents = "broken"; WLX.char = nil; MOCK.fire("PLAYER_LOGIN"); assert(WLX.char == nil and WarlockSimDB.chars["Tester-Mock"].char == nil, "a broken saved character is dropped")
  MOCK.click("Read my character"); assert(WLX.char and not WLX.char.restored and WarlockSimDB.chars["Tester-Mock"].char)`);
step('what if: +10 spell power gains, a typed change, nothing entered', `WLX.db.options.fights = 30; MOCK.click("+10 SP"); assert(WLX.jobRunning(), "no sim"); ${pump}
  local r = WLX.lastResult; assert(r.kind == "whatif" and r.diff > 0 and r.err >= 0, "kind / diff: " .. tostring(r.kind) .. " " .. tostring(r.diff))
  assert(MOCK.findLike("FontString", "What if %+10 spell power"), "what changed is shown"); assert(MOCK.findLike("FontString", "DPS for each 1 spell power"), "per point")
  for _, f in ipairs(MOCK.frames) do if f.__kind == "EditBox" and f.template == "InputBoxTemplate" and f.text == "10" then f:SetText("0") end end
  MOCK.click("Clear"); MOCK.click("Sim this change"); assert(not WLX.jobRunning(), "nothing entered: no sim"); assert(MOCK.findLike("FontString", "Enter a change first"), "says why")
  local n = 0; for _, f in ipairs(MOCK.frames) do if f.__kind == "EditBox" and f.template == "InputBoxTemplate" and f.text == "0" then n = n + 1; if n == 2 then f:SetText("-2") end end end
  MOCK.click("Sim this change"); ${pump}; local r2 = WLX.lastResult; assert(r2.kind == "whatif" and r2.delta.hit == -2 and r2.diff < 0, "-2% hit loses: " .. tostring(r2.delta.hit) .. " " .. tostring(r2.diff))
  WLX.db.options.fights = 10; return string.format("+10 SP: %+.1f DPS +- %.1f; -2%% hit: %+.1f DPS", r.diff, r.err, r2.diff)`);
step('item sim fights box; minimap button, its clicks, hiding it', `local box; for _, f in ipairs(MOCK.frames) do if f.__kind == "EditBox" and f.text == "150" then box = f end end; assert(box, "no item fights box")
  box:SetText("400"); box.scripts.OnEnterPressed(box); assert(WLX.db.options.itemFights == 400, "item fights: " .. tostring(WLX.db.options.itemFights)); box:SetText("5"); box.scripts.OnEnterPressed(box); assert(WLX.db.options.itemFights == 20, "at least 20"); WLX.db.options.itemFights = 150
  local b = WarlockSimMinimapButton; assert(b and b.shown, "no minimap button"); local was = WarlockSimFrame:IsShown()
  b.scripts.OnClick(b, "LeftButton"); assert(WarlockSimFrame:IsShown() ~= was, "a click opens / closes the window"); b.scripts.OnClick(b, "LeftButton")
  b.scripts.OnEnter(b); b.scripts.OnLeave(b); b.scripts.OnDragStart(b); b.scripts.OnUpdate(b, 0.016); b.scripts.OnDragStop(b); assert(WLX.db.options.minimapAngle ~= 200, "dragging moves it")
  WarlockSimFrame:Hide(); WLX.db.options.fights = 12; b.scripts.OnClick(b, "RightButton"); assert(WarlockSimFrame:IsShown() and WLX.jobRunning(), "right-click opens the window and sims"); WLX.cancelJob(); WLX.db.options.fights = 10
  WarlockSim_Toggle(); assert(not WarlockSimFrame:IsShown(), "the key binding closes it"); WarlockSim_Toggle()
  SlashCmdList.WARLOCKSIM("minimap"); assert(not b.shown and WLX.db.options.minimapButton == false, "/wsim minimap hides it"); SlashCmdList.WARLOCKSIM("minimap"); assert(b.shown, "and shows it again")`);
step('opening the window reads the character (out of combat), and only then', `WarlockSimFrame:Hide(); local before = WLX.char; WLX.char = nil
  WLX.toggleWindow(); assert(WarlockSimFrame:IsShown() and WLX.char and not WLX.char.restored, "not read on opening")
  local c = WLX.char; WLX.refresh(); assert(WLX.char == c, "read again while open"); WLX.toggleWindow(); assert(not WarlockSimFrame:IsShown() and WLX.char == c, "read on closing")
  MOCK.combat = true; WLX.toggleWindow(); MOCK.combat = false; assert(WLX.char == c, "read in combat"); WLX.toggleWindow(); WLX.toggleWindow()`);
step('stop early: the rules', `local st = WLX.singleStop(); local i = 0; repeat i = i + 1 until st(i, 900) or i > 500; assert(i == 40, "a steady DPS stops at the 40th fight: " .. i)
  local base = {}; for f = 1, 200 do base[f] = 900 + (f % 7) * 30 end
  local ps = WLX.pairedStop(base); i = 0; repeat i = i + 1 until ps(i, base[i] + 5) or i > 500; assert(i == 40, "a steady difference stops at 40: " .. i)
  local noisy = WLX.pairedStop(base); i = 0; repeat i = i + 1 until noisy(i, base[i] + ((i % 2 == 0) and 40 or -40)) or i > 500; assert(i == 200, "a difference lost in noise plays every fight of the base run: " .. i)
  local m, e, n = WLX.pairedDiff(base, { base[1] + 2, base[2] + 2 }); assert(n == 2 and math.abs(m - 2) < 1e-9 and e == 0, "pairedDiff over the fights both played")
  WLX.db.options.stopEarly = false; assert(WLX.singleStop() == nil and WLX.pairedStop(base) == nil, "switched off"); WLX.db.options.stopEarly = true`);
step('stop early: What if and an item stop long before the fights set; switched off, they play every fight', `WLX.db.options.fights = 300; MOCK.click("+10 SP"); ${pump}
  local r = WLX.lastResult; assert(r.kind == "whatif" and r.res.iterations < 300 and r.res.iterations >= 40 and r.base.iterations == r.res.iterations, "fights: " .. r.res.iterations)
  local early = r.res.iterations
  WLX.db.options.stopEarly = false; WLX.db.options.fights = 60; MOCK.click("+10 SP"); ${pump}; assert(WLX.lastResult.res.iterations == 60, "off: every fight")
  WLX.db.options.stopEarly = true; WLX.db.options.fights = 10
  MOCK.keys = { shift = true }; MOCK.button = "RightButton"; HandleModifiedItemClick(MOCK.link(1003), MOCK.bagLocation()); MOCK.keys = {}; ${pump}; for i = 1, 16 do MOCK.frame() end
  local t = WarlockSimItemPanel.text.text; WarlockSimItemPanel:Hide()
  return "What if +10 SP: exact enough after " .. early .. " of 300 fights; item: " .. (t:match("Exact enough after %d+ of %d+ fights") or "all fights")`);
const gearCode = step('gear code: what you wear, for the website\'s gear builder', `MOCK.equipped[1] = 1009; MOCK.equipped[5] = 1008
  MOCK.combat = true; MOCK.click("My gear as a code"); MOCK.combat = false; assert(MOCK.findLike("FontString", "You are in combat"), "refused in combat")
  MOCK.click("My gear as a code"); local box; for _, f in ipairs(MOCK.frames) do if f.__kind == "EditBox" and not f.template then box = f end end
  assert(box:GetText():sub(1, 5) == "WFG1:", "no gear code in the box"); assert(MOCK.findLike("FontString", "Gear code made: 6 items, 2 enchants"), "the count")
  assert(MOCK.findLike("FontString", "Enchant not understood, counted as 0: %+18 Spell Damage and Healing / %+1%% Spell Hit / Minor Glow"), "the enchant part it cannot read is named")
  local code = box:GetText(); box:SetText(code); MOCK.click("Load the code"); assert(MOCK.findLike("FontString", "That is a gear code"), "loading a gear code says what it is for")
  assert(WLX.db.lastGear.chest.understood == true and WLX.db.lastGear.head.understood == false, "kept for the dump")
  MOCK.equipped[1] = nil; MOCK.equipped[5] = nil; return code`);
{
  // the website's own reader takes the code (app/gear-builder.js, run with the browser helpers it expects)
  const vm = require('vm');
  const WG = require(path.join(SIM, 'tools', 'load-wl.js')).load(SIM, ['engine/settings-code.js', 'data/items.js']);
  const ctx = { WL: WG, atob: s => Buffer.from(s, 'base64').toString('latin1'), btoa: s => Buffer.from(s, 'latin1').toString('base64'), escape, unescape };
  ctx.window = ctx; vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(SIM, 'app', 'gear-builder.js'), 'utf8'), ctx);
  const g = ctx.WL.decodeGear(gearCode);
  const head = g.slots.head.custom, chest = g.slots.chest.custom, main = g.slots.mainHand.custom;
  assert.strictEqual(Object.keys(g.slots).sort().join(','), 'chest,finger1,finger2,head,mainHand,offHand', 'the items');
  assert.strictEqual(head.name, 'Mish’undare, Circlet of the Mind Flayer', 'a name that is not plain ASCII');
  assert.strictEqual(head.id, 1009); assert.strictEqual(head.quality, '4' === '4' ? 'epic' : '', 'quality');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(chest)), { name: 'Robe of Tests', slot: 'chest', stats: { int: 20, hitPct: 1 }, id: 1008, quality: 'epic' }, 'a robe: chest, its own stats without the enchant');
  assert.strictEqual(main.weapon, 'sword'); assert.strictEqual(main.slot, 'mainHand');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(g.enchants.chest.custom)), { name: '+4 All Stats', stats: { int: 4, spi: 4, sta: 4, agi: 4 }, id: 1891 }, 'the robe\'s enchant');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(g.enchants.head.custom.stats)), { sp: 18, hitPct: 1 }, 'the head enchant: what could be read');
  assert(!g.enchants.finger1, 'a ring enchant is not sent (rings take none on the website)');
  assert.strictEqual(g.ignored.length, 0, 'the website ignores nothing: ' + g.ignored.join(', '));
  console.log('ok   gear code: the website\'s gear builder reads it: ' + Object.keys(g.slots).length + ' items, ' + Object.keys(g.enchants).length + ' enchants');
}
step('Escape closes the window (the list the game walks), and the game\'s own Escape handlers are left alone', `assert(#MOCK.escHandlers == 0, "an entry of the addon's in the game's Escape handlers taints every Escape")
  local n = 0; for _, name in ipairs(UISpecialFrames) do if name == "WarlockSimFrame" then n = n + 1 end end; assert(n == 1, "on the list of windows Escape closes: " .. n .. " times")
  if not WarlockSimFrame:IsShown() then WLX.toggleWindow() end; assert(MOCK.closeSpecialWindows() and not WarlockSimFrame:IsShown(), "Escape's list does not close it"); WLX.toggleWindow()`);
step('the watcher notes actions of this addon the game blocks, and only those', `local chat = #MOCK.chat
  MOCK.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "ClearTarget()"); assert(WLX.db.blocked == nil, "another addon's block was noted")
  MOCK.combat = true; MOCK.fire("ADDON_ACTION_BLOCKED", "WarlockSim", "ClearTarget()"); MOCK.fire("ADDON_ACTION_BLOCKED", "WarlockSim", "ClearTarget()"); MOCK.combat = false
  MOCK.fire("ADDON_ACTION_FORBIDDEN", "WarlockSim", "UNKNOWN()")
  local b = WLX.db.blocked; assert(b and #b == 3 and b[1].action == "UNKNOWN()" and b[1].event == "ADDON_ACTION_FORBIDDEN" and b[3].combat == true, "the list")
  assert(#MOCK.chat == chat + 2, "one chat line per action, not per block: " .. (#MOCK.chat - chat))
  for i = 1, 30 do MOCK.fire("ADDON_ACTION_BLOCKED", "WarlockSim", "X" .. i .. "()") end; assert(#WLX.db.blocked == 20, "the last 20 only")
  SlashCmdList.WARLOCKSIM("blocked"); assert(MOCK.chat[#MOCK.chat]:find("blocked", 1, true)); SlashCmdList.WARLOCKSIM("dump"); assert(WLX.db.dump.blocked == WLX.db.blocked)
  WLX.db.blocked = nil; SlashCmdList.WARLOCKSIM("blocked"); assert(MOCK.chat[#MOCK.chat]:find("has not blocked anything", 1, true))`);
step('Sim!: the DPS is on screen before the stat weights are done', `WLX.db.options.weights = true; WLX.db.options.fights = 12; MOCK.click("Sim!"); assert(WLX.jobRunning(), "no sim started")
  local seen = false; local n = 0
  while WLX.jobRunning() do MOCK.frame(); n = n + 1; if not seen and MOCK.findLike("FontString", "Stat weights: still simming") then seen = true; assert(MOCK.findLike("FontString", "^%d+%.%d DPS"), "DPS shown with the note") end; if n > 3000000 then error("never ends") end end
  assert(seen, "the DPS was not shown before the stat weights"); assert(not MOCK.findLike("FontString", "Stat weights: still simming"), "the note is gone at the end")
  assert(MOCK.findLike("FontString", "Worth in spell power"), "stat weights shown at the end")`);
step('Sim! again with nothing changed: the result is there at once', `local before = WLX.lastResult.res.dps; MOCK.click("Sim!"); assert(not WLX.jobRunning(), "it simmed again")
  assert(WLX.lastResult.remembered and WLX.lastResult.res.dps == before, "not the remembered result"); assert(MOCK.findLike("FontString", "Nothing has changed since this was simmed"), "no word about it")
  WLX.db.options.fights = 13; MOCK.click("Sim!"); assert(WLX.jobRunning(), "another number of fights is another sim"); WLX.cancelJob(); WLX.db.options.fights = 10; WLX.db.options.weights = false`);
step('the builds appear one by one; asked again, they are there at once', `WLX.db.options.fights = 11; MOCK.click("Sim builds with your gear"); assert(WLX.jobRunning(), "another number of fights: a new sim"); local seen = false; local n = 0
  while WLX.jobRunning() do MOCK.frame(); n = n + 1; if not seen and MOCK.findLike("FontString", "more to come") then seen = true end; if n > 3000000 then error("never ends") end end
  assert(seen, "no list before the last build was done"); assert(not MOCK.findLike("FontString", "more to come"), "the note is gone at the end")
  MOCK.click("Sim builds with your gear"); assert(not WLX.jobRunning() and WLX.lastResult.remembered and WLX.lastResult.kind == "rank", "the list was not remembered"); WLX.db.options.fights = 10`);
step('the speed: automatic by default, a saved "stay smooth" of the version before moves over once', `assert(WLX.db.options.speed == "auto", "default speed: " .. tostring(WLX.db.options.speed))
  local o = WarlockSimDB.options; o.speed = "smooth"; o.speedDefault = nil; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db.options.speed == "auto", "moved over")
  WLX.db.options.speed = "smooth"; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db.options.speed == "smooth", "a choice made afterwards stays"); WLX.db.options.speed = "auto"`);
step('the tip fits on one line', `WLX.refresh(); local t = MOCK.findLike("FontString", "^|cff9482c9Tip:|r "); assert(t, "no tip"); local plain = t.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  assert(#plain <= 60, "the tip is " .. #plain .. " characters: " .. plain); return plain`);
step('/wsim test', 'SlashCmdList.WARLOCKSIM("test"); local t = WLX.db.selfTest; assert(t and t.ok, "self-test failed: " .. table.concat(t and t.lines or {}, " | ")); return t.fights .. " fights match"');
step('/wsim dump, read, help, close', 'SlashCmdList.WARLOCKSIM("dump"); assert(WLX.db.dump.character.raw.nodeCount == #WLX.TALENTS); SlashCmdList.WARLOCKSIM("read"); SlashCmdList.WARLOCKSIM("help"); SlashCmdList.WARLOCKSIM(""); assert(not WarlockSimFrame:IsShown()); MOCK.fire("PLAYER_LOGOUT"); assert(WLX.db.settings.v == 1)');
step('a second session starts from the saved settings', 'local saved = WarlockSimDB; MOCK.fire("ADDON_LOADED", "WarlockSim"); assert(WLX.db == saved and WLX.cfg.fight.duration == 120)');
console.log('\n' + host.limits());
console.log('Chat lines the addon printed: ' + lua('return #MOCK.chat'));
console.log('OK: the addon runs start to finish against the stand-in game');
