// Эталон превью-иконок движков для Swift-версии: функции draw из docs/icons/prototype/engine-previews-prototype.html
// (секция «final mix», module.exports) на записывающем canvas — каждая заливка с цветом (p — c.icon, s — c.gray),
// прозрачностью, прямоугольниками и контуром.
// Запуск (Node 22): node ios/tools/icons/golden.mjs
// Выход: ios/tools/icons/engine_previews_golden.json — [{engine, v: {h, t, m, q, d}, hx, ops: [{ink, a, r, poly, text}]}].
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const html = fs.readFileSync(path.join(root, 'docs/icons/prototype/engine-previews-prototype.html'), 'utf8');
const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const sandbox = { module: { exports: {} }, Math, Float32Array, Array, Object, String, parseInt, parseFloat };
vm.runInNewContext(script, sandbox);
const { ENGINES } = sandbox.module.exports;

const ID = { KICK: 16, ANALOG: 17, FM: 18, WTABLE: 19, SNARE: 20, HAT: 21, CLAP: 22, PERC: 23, SUB: 24 };
const r4 = (x) => Math.round(x * 1e4) / 1e4;

/** Canvas 2D, который только записывает заливки. */
function recorder() {
  const ops = [];
  let rects = [], poly = [];
  const g = {
    globalAlpha: 1, fillStyle: 'I', strokeStyle: 'I', lineWidth: 1, font: '', textAlign: '', lineCap: '', lineJoin: '',
    beginPath() { rects = []; poly = []; },
    rect(x, y, w, h) { rects.push([x, y, w, h].map(r4)); },
    moveTo(x, y) { poly.push([r4(x), r4(y)]); },
    lineTo(x, y) { poly.push([r4(x), r4(y)]); },
    closePath() {},
    fill() { ops.push({ ink: g.fillStyle === 'G' ? 's' : 'p', a: r4(g.globalAlpha), r: rects, poly }); },
    fillRect(x, y, w, h) { ops.push({ ink: g.fillStyle === 'G' ? 's' : 'p', a: r4(g.globalAlpha), r: [[x, y, w, h].map(r4)], poly: [] }); },
    fillText(t, x, y) { ops.push({ ink: 'p', a: r4(g.globalAlpha), r: [], poly: [], text: [t, x, y] }); },
    stroke() { throw new Error('stroke в превью не ожидается'); },
    setLineDash() {},
  };
  return { g, ops };
}

// HAT в Swift — сплошные линии (решение пользователя: без градиента к верху): полоски прототипа по 2 склеиваются
// в отрезки (mergeRuns), все линии — одна заливка без прозрачности.
export function mergeRuns(rects) {
  const out = [];
  for (const r of rects) {
    const p = out[out.length - 1];
    if (p && Math.abs(p[0] - r[0]) < 1e-3 && r[1] <= p[1] + p[3] + 1e-3) p[3] = r4(Math.max(p[1] + p[3], r[1] + r[3]) - p[1]);
    else out.push(r.slice());
  }
  return out;
}
const hatSolid = (ops) => [ops[0], { ink: 'p', a: 1, r: mergeRuns(ops.slice(1).flatMap((o) => o.r)), poly: [] }];

// Наборы ручек: по умолчанию, края, середина и смешанные; у ступенчатых — точные пункты (как в прототипе).
const SETS = [
  null,
  [0, 0, 0, 0, 0],
  [1, 1, 1, 1, 1],
  [0.5, 0.5, 0.5, 0.5, 0.5],
  [0.25, 0.75, 0.2, 0.6, 0.3],
  [0.8, 0.15, 0.85, 0.1, 0.9],
  [1 / 3, 2 / 3, 0.4, 0.95, 0.05],
  [0.62, 0.38, 0.7, 0.33, 0.66],
];
const cases = [];
for (const e of ENGINES) {
  const id = ID[e.name];
  if (id === undefined) continue;
  for (const [k, set] of SETS.entries()) {
    const s = set ? set.slice(0, 4) : e.knobs.map((x) => x.def);
    const D = set ? set[4] : e.decay ? e.decay.def : 0.5;
    for (const hx of e.kind === 'drum' && k < 3 ? [null, 22] : [null]) {
      const { g, ops } = recorder();
      e.draw(g, s, D, { T: 1.3, hx, reduced: true, icon: 'I', gray: 'G', bg: 'B', tA: 0, tB: 0, tm: 1 });
      let res = ops.filter((o) => o.r.length || o.poly.length || o.text);
      if (id === 21) res = hatSolid(res);
      cases.push({ engine: id, v: { h: s[0], t: s[1], m: s[2], q: s[3], d: D }, hx, ops: res });
    }
  }
}
fs.writeFileSync(path.join(here, 'engine_previews_golden.json'), JSON.stringify(cases));
console.log(cases.length + ' cases');
