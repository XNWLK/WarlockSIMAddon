// Runs every check. All of them must say OK before the addon is installed or pushed.
//   node tools/check-all.js          quick: 1 fight per scene in the engine check
//   node tools/check-all.js full     4 fights per scene
//   node tools/check-all.js --one    one check after the other, as before (slower; for a computer with few cores)
// The checks do not depend on each other, so they run at the same time, each in its own process (one core each), and the
// engine check is split into pieces (CHECK_SHARD=i/n: every n-th scene). Each line gives how long its check took.
const cp = require('child_process'), path = require('path'), os = require('os');
const args = process.argv.slice(2);
const full = args.indexOf('full') >= 0, oneByOne = args.indexOf('--one') >= 0;
const cores = Math.max(1, (os.cpus() || []).length);
const workers = oneByOne ? 1 : Math.max(1, cores - 1);
const pieces = oneByOne ? 1 : Math.max(1, Math.min(16, workers - 6));   // the engine check's pieces, beside the 7 other checks
const fightsPerScene = full ? '4' : '1';

const runs = [['check-api.js'], ['check-limits.js'], ['check-codes.js'], ['check-character.js'], ['check-items.js'], ['check-ui.js'], ['check-helper.js']]
  .map(r => ({ name: r[0], file: r[0], args: r.slice(1), env: {} }));
for (let i = 0; i < pieces; i++) {
  runs.push({ name: 'check-engine.js', file: 'check-engine.js', args: [fightsPerScene], env: { CHECK_SHARD: i + '/' + pieces }, piece: i });
}
// the longest first, so the short ones fill the gaps (order of the runs only, not of the report)
const LONG = ['check-engine.js', 'check-ui.js', 'check-character.js', 'check-helper.js'];
const queue = runs.slice().sort((a, b) => (LONG.indexOf(a.name) < 0 ? 99 : LONG.indexOf(a.name)) - (LONG.indexOf(b.name) < 0 ? 99 : LONG.indexOf(b.name)));

const t0 = Date.now();
function runOne(r) {
  return new Promise(resolve => {
    const t = Date.now();
    const p = cp.spawn(process.execPath, [path.join(__dirname, r.file)].concat(r.args), { env: Object.assign({}, process.env, r.env) });
    let out = '', err = '';
    p.stdout.on('data', d => { out += d; });
    p.stderr.on('data', d => { err += d; });
    p.on('close', code => { r.code = code; r.out = out; r.err = err; r.secs = (Date.now() - t) / 1000; resolve(); });
  });
}
async function main() {
  let next = 0;
  async function lane() { while (next < queue.length) { const r = queue[next++]; await runOne(r); } }
  await Promise.all(Array.from({ length: Math.min(workers, queue.length) }, lane));

  let bad = 0;
  const plain = runs.filter(r => r.piece === undefined), eng = runs.filter(r => r.piece !== undefined);
  const lastLine = r => { const l = (r.out || '').trim().split('\n'); return (l[l.length - 1] || '(no output)').replace(/^OK: /, ''); };
  const secs = s => (s >= 60 ? Math.floor(s / 60) + ' min ' + Math.round(s % 60) + ' s' : s.toFixed(1) + ' s');
  plain.forEach(r => {
    if (r.code !== 0) { bad++; console.log('FAIL ' + r.name + ' (' + secs(r.secs) + ')\n' + r.out + r.err); }
    else console.log('ok   ' + r.name + ': ' + lastLine(r) + '  [' + secs(r.secs) + ']');
  });
  // the engine pieces as one line: their fights added up, the time of the slowest piece
  const failed = eng.filter(r => r.code !== 0);
  const fights = eng.reduce((n, r) => { const m = /agree in all (\d+) fights/.exec(r.out || ''); return n + (m ? +m[1] : 0); }, 0);
  const slowest = Math.max.apply(null, eng.map(r => r.secs)), cpu = eng.reduce((n, r) => n + r.secs, 0);
  if (failed.length) { bad++; failed.forEach(r => console.log('FAIL check-engine.js piece ' + r.env.CHECK_SHARD + ' (' + secs(r.secs) + ')\n' + r.out + r.err)); }
  else console.log('ok   check-engine.js: the addon\'s engine and the sim\'s engine agree in all ' + fights + ' fights  [' + secs(slowest) +
    (eng.length > 1 ? ' for the slowest of ' + eng.length + ' pieces, ' + secs(cpu) + ' in all' : '') + ']');
  console.log('\n' + (bad ? 'FAIL: ' + bad + ' checks failed' : 'OK: all checks pass') + ' in ' + secs((Date.now() - t0) / 1000) +
    (oneByOne ? ' (one after the other)' : ' (' + Math.min(workers, queue.length) + ' at a time on ' + cores + ' cores)'));
  process.exit(bad ? 1 : 0);
}
main();
