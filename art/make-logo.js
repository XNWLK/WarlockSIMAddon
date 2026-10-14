// Builds art/logo.svg: rising bars + a Shadow Bolt comet modelled on the spell's icon (a sparkly head of lime green
// and magenta blobs in a purple haze, tapering into a green tail). Seeded, so the same picture every run.
const fs = require('fs');
let seed = Number(process.argv[2] || 7) >>> 0;
const rnd = () => { seed = (seed + 0x6D2B79F5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = a => a[Math.floor(rnd() * a.length)];
const H = [292, 112], T = [84, 296];
const L = Math.hypot(T[0] - H[0], T[1] - H[1]);
const d = [(T[0] - H[0]) / L, (T[1] - H[1]) / L], p = [-d[1], d[0]];
const W = t => t < 0.12 ? 56 : 56 * Math.pow(1 - (t - 0.12) / 0.88, 1.7) + 3;
const at = (t, side, along) => [H[0] + d[0] * (L * t + along) + p[0] * side, H[1] + d[1] * (L * t + along) + p[1] * side];
const f = n => n.toFixed(1);
function blobs(n, tPow, spread, rMin, rMax, colors, opacity) {
  let s = '';
  for (let i = 0; i < n; i++) {
    const t = Math.pow(rnd(), tPow), w = W(t);
    const side = (rnd() * 2 - 1) * w * spread;
    const along = t < 0.2 ? (rnd() * 2 - 1) * w * 0.55 : (rnd() * 2 - 1) * 8;
    const [x, y] = at(t, side, along);
    const r = rMin + (rMax - rMin) * rnd() * (0.45 + 0.55 * w / 54);
    s += `<circle cx="${f(x)}" cy="${f(y)}" r="${f(r)}" fill="${pick(colors)}" opacity="${opacity}"/>`;
  }
  return s;
}
const haze = blobs(34, 1.6, 0.7, 30, 56, ['#5B1A8C', '#7A22B0', '#4A1677'], 0.45);
function mass(k, tMax, color, opacity) { let s = ''; for (let t = 0; t <= tMax; t += 0.01) { const [x, y] = at(t, 0, 0); s += `<circle cx="${f(x)}" cy="${f(y)}" r="${f(W(t) * k)}" fill="${color}" opacity="${opacity}"/>`; } return s; }
const massM = mass(0.95, 1, '#9A28D2', 0.06), massG = mass(0.5, 1, '#7ED445', 0.05), massC = mass(0.36, 0.2, '#F0E4FF', 0.28);
const magenta = blobs(170, 1.6, 1.0, 3, 11, ['#B02EE0', '#D04CF2', '#9A2AD0', '#E070FF'], 0.85);
const green = blobs(45, 1.5, 0.45, 2, 7, ['#8EE04A', '#B4EE58', '#A8F070'], 0.7);
const light = blobs(45, 3, 0.45, 2, 6, ['#F4E6FF', '#FFFFFF', '#EEF8D0'], 0.95);
const sparks = blobs(46, 1.5, 1.35, 1.2, 3.4, ['#FFB4F4', '#FFFFFF', '#F59BFF', '#FFD6FA'], 0.9);

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">
  <defs>
    <linearGradient id="bar3" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#A47BEA"/>
      <stop offset="1" stop-color="#6A3FB5"/>
    </linearGradient>
    <filter id="haze" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>
    <filter id="fuzz" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.8"/></filter>
    <filter id="mass" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>
    <filter id="spark" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="0.6"/></filter>
  </defs>

  <rect width="400" height="400" fill="#15121D"/>

  <!-- bars -->
  <rect x="60" y="270" width="66" height="74" rx="8" fill="#3A3150"/>
  <rect x="150" y="225" width="66" height="119" rx="8" fill="#5A3D96"/>
  <rect x="240" y="175" width="66" height="169" rx="8" fill="url(#bar3)"/>
  <rect x="44" y="340" width="312" height="8" rx="4" fill="#2A2438"/>

  <!-- shadow bolt: purple haze, magenta and lime blobs, bright heart, sparkles -->
  <g filter="url(#haze)">${haze}</g>
  <g filter="url(#mass)">${massM}${massG}${massC}</g>
  <g filter="url(#fuzz)">${magenta}</g>
  <g filter="url(#fuzz)">${green}</g>
  <g filter="url(#fuzz)">${light}</g>
  <g filter="url(#spark)">${sparks}</g>
</svg>
`;
fs.writeFileSync(process.argv[3] || 'C:/Claude/warlock-sim-addon/art/logo.svg', svg);
console.log('seed', process.argv[2] || 7, svg.length, 'bytes');
