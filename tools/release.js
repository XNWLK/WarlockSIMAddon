// Makes the GitHub release for the newest version in PATCHNOTES.md: the tag vX.Y.Z on the pushed commit, that
// version's patch notes as its text, and WarlockSim-X.Y.Z.zip (the addon's folder, ready to unzip into the game's AddOns
// folder). Needs git and the GitHub command line tool (gh), signed in.
//   node tools/release.js --dry   shows the tag, the commit and the notes; changes nothing
//   node tools/release.js         makes the release
// Run it AFTER `git push`: it refuses unless GitHub's main is the local HEAD, the addon's .toc carries that version, and
// the tag is still free (a push without a new "## vX.Y.Z" entry in PATCHNOTES.md gets no release).
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
const ROOT = path.join(__dirname, '..'), REPO = 'XNWLK/WarlockSIMAddon';
const dry = process.argv.includes('--dry');
const sh = (cmd, args) => execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8' }).trim();

const notes = fs.readFileSync(path.join(ROOT, 'PATCHNOTES.md'), 'utf8').replace(/\r\n/g, '\n');
const m = /^## (v\d+\.\d+\.\d+)\n([\s\S]*?)(?=^## v\d+\.\d+\.\d+\n|(?![\s\S]))/m.exec(notes);
if (!m) throw new Error('No "## vX.Y.Z" entry found in PATCHNOTES.md');
const tag = m[1], version = tag.slice(1);
// GitHub shows every line break of a release text, so wrapped lines are joined to their bullet.
const body = m[2].trim().split('\n').reduce((out, line) => {
  if (/^\s+\S/.test(line) && out.length && !/^\s*[-*] /.test(line)) out[out.length - 1] += ' ' + line.trim(); else out.push(line);
  return out;
}, []).join('\n') +
  '\n\n**Install:** unzip `WarlockSim-' + version + '.zip` into `World of Warcraft\\_classic_beta_\\Interface\\AddOns` (over the old folder, if there is one), restart the game, type `/wsim`.' +
  ' · [All patch notes](https://github.com/' + REPO + '/blob/main/PATCHNOTES.md)\n';

const head = sh('git', ['rev-parse', 'HEAD']);
const remote = sh('git', ['ls-remote', 'origin', 'refs/heads/main']).split(/\s+/)[0];
if (head !== remote) throw new Error('GitHub main (' + remote.slice(0, 7) + ') is not the local HEAD (' + head.slice(0, 7) + '): push first.');
const toc = (sh('git', ['show', head + ':WarlockSim/WarlockSim.toc']).match(/^## Version:\s*(\S+)/m) || [])[1];
if (toc !== version) throw new Error('PATCHNOTES.md says ' + version + ', the addon\'s .toc says ' + toc + '.');
if (sh('git', ['ls-remote', '--tags', 'origin', 'refs/tags/' + tag])) throw new Error('Tag ' + tag + ' exists on GitHub already: nothing to do (a new release needs a new "## vX.Y.Z" entry in PATCHNOTES.md).');

console.log('tag     ' + tag + '\ncommit  ' + head.slice(0, 7) + '\n--- notes ---\n' + body + '-------------');
if (dry) { console.log('dry run: nothing created'); process.exit(0); }
const zip = path.join(os.tmpdir(), 'WarlockSim-' + version + '.zip'), file = path.join(os.tmpdir(), 'warlocksim-addon-release-notes.md');
sh('git', ['archive', '--format=zip', '--prefix=WarlockSim/', '-o', zip, head + ':WarlockSim']);
fs.writeFileSync(file, body);
console.log(sh('gh', ['release', 'create', tag, zip, '-R', REPO, '--target', head, '--title', "Xn's Warlock Sim " + version, '--notes-file', file]));
console.log('with ' + path.basename(zip) + ' (' + fs.statSync(zip).size + ' bytes)');
fs.unlinkSync(file); fs.unlinkSync(zip);
sh('git', ['fetch', '--tags', 'origin']);
console.log('local tag: ' + sh('git', ['tag', '--list', tag]));
