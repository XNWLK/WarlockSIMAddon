// Runs every check in turn. All of them must say OK before the addon is installed or pushed.
//   node tools/check-all.js          quick: 1 fight per scene in the engine check
//   node tools/check-all.js full     4 fights per scene (several minutes)
const cp = require('child_process'), path = require('path');
const full = process.argv[2] === 'full';
const runs = [['check-api.js'], ['check-limits.js'], ['check-codes.js'], ['check-character.js'], ['check-ui.js'], ['check-engine.js', full ? '4' : '1']];
let bad = 0;
runs.forEach(r => {
  const out = cp.spawnSync(process.execPath, [path.join(__dirname, r[0])].concat(r.slice(1)), { encoding: 'utf8' });
  const lines = (out.stdout || '').trim().split('\n');
  const last = lines[lines.length - 1] || '(no output)';
  if (out.status !== 0) { bad++; console.log('FAIL ' + r[0] + '\n' + (out.stdout || '') + (out.stderr || '')); }
  else console.log('ok   ' + r[0] + ': ' + last.replace(/^OK: /, ''));
});
console.log(bad ? '\nFAIL: ' + bad + ' checks failed' : '\nOK: all checks pass');
process.exit(bad ? 1 : 0);
