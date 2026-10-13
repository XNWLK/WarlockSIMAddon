// Makes a release on GitHub for a version of the addon: a tag, the notes, and WarlockSim-<version>.zip (the addon's
// folder, ready to unzip into the game's AddOns folder). Needs git and the GitHub command line tool (gh), signed in.
//   node tools/release.js <notes file>                      the version in WarlockSim.toc, at the pushed HEAD
//   node tools/release.js <notes file> <version> <commit>   an older version (not marked as the latest)
// Push first: the release is made from what is on GitHub.
const fs = require('fs'), path = require('path'), os = require('os'), cp = require('child_process');
const ROOT = path.join(__dirname, '..');
const run = (cmd, args) => cp.execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8' }).trim();
const notes = process.argv[2];
if (!notes || !fs.existsSync(notes)) { console.log('Give the file with the release notes.'); process.exit(1); }
const toc = fs.readFileSync(path.join(ROOT, 'WarlockSim', 'WarlockSim.toc'), 'utf8');
const older = !!process.argv[3];
const version = process.argv[3] || (toc.match(/^## Version:\s*(\S+)/m) || [])[1];
const commit = process.argv[4] || run('git', ['rev-parse', 'HEAD']);
if (!version) { console.log('No version found.'); process.exit(1); }
if (!older) {
  if (run('git', ['status', '--short'])) { console.log('There are uncommitted changes: commit and push first.'); process.exit(1); }
  if (run('git', ['rev-parse', 'HEAD']) !== run('git', ['rev-parse', 'origin/main'])) { console.log('HEAD is not what is on GitHub: push first.'); process.exit(1); }
}
const tagged = (cp.execFileSync('git', ['show', commit + ':WarlockSim/WarlockSim.toc'], { cwd: ROOT, encoding: 'utf8' }).match(/^## Version:\s*(\S+)/m) || [])[1];
if (tagged !== version) { console.log('The addon at ' + commit.slice(0, 7) + ' says version ' + tagged + ', not ' + version + '.'); process.exit(1); }
const zip = path.join(os.tmpdir(), 'WarlockSim-' + version + '.zip');
run('git', ['archive', '--format=zip', '--prefix=WarlockSim/', '-o', zip, commit + ':WarlockSim']);
const args = ['release', 'create', 'v' + version, zip, '--repo', 'XNWLK/WarlockSIMAddon', '--target', commit, '--title', "Xn's Warlock Sim " + version, '--notes-file', notes];
if (older) args.push('--latest=false');
console.log(run('gh', args));
console.log('Release v' + version + ' made from ' + commit.slice(0, 7) + ' with ' + path.basename(zip) + ' (' + fs.statSync(zip).size + ' bytes)');
