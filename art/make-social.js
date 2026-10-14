// 1280x640 social preview: the logo on the left, the name and one line on the right.
const fs = require('fs');
const svg = fs.readFileSync('C:/Claude/warlock-sim-addon/art/logo.svg', 'utf8').replace('width="400" height="400"', 'width="440" height="440"');
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1280px;height:640px;overflow:hidden;background:#15121D;font-family:'Segoe UI',sans-serif}
.wrap{display:flex;align-items:center;height:640px;padding:0 90px;gap:70px;box-sizing:border-box}
svg{display:block;border-radius:28px;flex:none}
h1{margin:0;color:#ECE8F5;font-size:78px;font-weight:600;letter-spacing:-1px;line-height:1.05}
p{margin:22px 0 0;color:#B393F0;font-size:34px;line-height:1.3}
small{display:block;margin-top:28px;color:#A39CB8;font-size:24px}
</style></head><body><div class="wrap">${svg}<div><h1>Xn's Warlock Sim</h1>
<p>A Warlock DPS simulator<br>inside the game</p><small>WoW: Forever addon · sims your own character</small></div></div></body></html>`;
fs.writeFileSync(process.argv[2], html);
