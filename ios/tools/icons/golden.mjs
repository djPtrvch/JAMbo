// Эталон иконок движков для Swift-версии: SVG элементы из src/engineIcons.ts (как рисует веб) на наборах значений.
// Импорт fmRatio (нужен только иконке 18) подменяется заглушкой; файл берётся во временную папку.
// Запуск (Node 22): node --experimental-strip-types --no-warnings ios/tools/icons/golden.mjs
// Выход: ios/tools/icons/engine_icons_golden.json — [{engine, v, els: [{d | c | tx, fill, op, dash}]}].
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const src = fs.readFileSync(path.join(root, 'src/engineIcons.ts'), 'utf8')
  .replace("import { fmRatio } from './params';", 'const fmRatio = (n) => n;');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'icons-'));
const file = path.join(tmp, 'engineIcons.ts');
fs.writeFileSync(file, src);
const { iconSvg } = await import(pathToFileURL(file).href);

const SETS = [[0, 0, 0], [1, 1, 1], [0.5, 0.5, 0.5], [0.25, 0.75, 0.2], [0.8, 0.15, 0.85]];
const attr = (s, name) => { const m = s.match(new RegExp(` ${name}="([^"]*)"`)); return m ? m[1] : null; };
const cases = [];
for (let engine = 0; engine < 8; engine++) {
  for (const [h, t, m] of SETS) {
    const v = { h, t, m, d: 0.5 };
    const svg = iconSvg(String(engine), v, 64);
    const els = [];
    for (const [, tag, body, text] of svg.matchAll(/<(path|circle|text)([^>]*?)(?:\/>|>([^<]*)<\/text>)/g)) {
      const op = attr(body, 'opacity');
      const el = { fill: attr(body, 'fill') !== 'none', op: op === null ? null : Number(op), dash: attr(body, 'stroke-dasharray') !== null };
      if (tag === 'path') el.d = attr(body, 'd');
      else if (tag === 'circle') el.c = ['cx', 'cy', 'r'].map((k) => Number(attr(body, k)));
      else el.tx = [text, ...['x', 'y', 'font-size'].map((k) => Number(attr(body, k)))];
      els.push(el);
    }
    cases.push({ engine, v, els });
  }
}
fs.rmSync(tmp, { recursive: true });
const out = path.join(here, 'engine_icons_golden.json');
fs.writeFileSync(out, JSON.stringify(cases));
console.log(`icons golden: ${cases.length} cases → ${out}`);
