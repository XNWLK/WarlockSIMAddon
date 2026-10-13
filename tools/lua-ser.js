// A JavaScript value as Lua source text (key order kept). Used by the generators and the checks.
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;
const RESERVED = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);
function str(s) {
  return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '')
    .replace(/[\u0080-￿]/g, c => Array.from(Buffer.from(c, 'utf8')).map(b => '\\' + b).join('')) + '"';
}
function toLua(v, drop) {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'number') { if (!isFinite(v)) throw new Error('not a finite number: ' + v); return String(v); }
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return str(v);
  if (Array.isArray(v)) return '{ ' + v.map(x => toLua(x, drop)).join(', ') + (v.length ? ' ' : '') + '}';
  const keys = Object.keys(v).filter(k => v[k] !== null && v[k] !== undefined && typeof v[k] !== 'function' && !(drop && drop.has(k)));
  return '{ ' + keys.map(k => (IDENT.test(k) && !RESERVED.has(k) ? k : '[' + str(k) + ']') + ' = ' + toLua(v[k], drop)).join(', ') + (keys.length ? ' ' : '') + '}';
}
module.exports = { toLua, str };
