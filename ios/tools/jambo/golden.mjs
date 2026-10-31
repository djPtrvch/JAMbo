// Эталоны своих движков JAMbo (DRUM, ANALOG, FM, WTABLE) для Swift-версии: рендер public/jambo-synth-worklet.js в Node
// так же, как браузер (блоки process() по 128 кадров, внутри — куски по 24; 48 кГц; дрейф ANALOG — свой генератор
// узла с начального состояния). Голос слота 0, нота в кадре 0 (у случая с retrig — второй удар в кадре retrig).
// Выход: ios/JAMbo.swiftpm/Resources/golden/j<движок>_s<набор>_n<нота>.i16 (1 с, Int16 = round(x·32767))
// и jambo_cases.json; таблицы WTABLE (src/audio/wavetable.ts) — контрольные отсчёты в jambo_tables.json.
// Запуск: node ios/tools/jambo/golden.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const outDir = path.join(root, 'ios/JAMbo.swiftpm/Resources/golden');
const SR = 48000;
const FRAMES = 48000;
const ctx = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
  registerProcessor(name, cls) { ctx.Proc = cls; },
});
const src = fs.readFileSync(path.join(root, 'public/jambo-synth-worklet.js'), 'utf8');
const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'jb-')), 'worklet.mjs');
fs.writeFileSync(tmp, src);
await import(pathToFileURL(tmp).href);
// Таблицы WTABLE — из src/audio/wavetable.ts (типы снимает Node, хранилище не нужно — встроенные таблицы).
{
  const { stripTypeScriptTypes } = await import('node:module');
  const ts = fs.readFileSync(path.join(root, 'src/audio/wavetable.ts'), 'utf8')
    .replace(/^import .*storage.*$/m, 'const getSample = async () => undefined;');
  const wt = path.join(path.dirname(tmp), 'wavetable.mjs');
  fs.writeFileSync(wt, stripTypeScriptTypes(ts));
  ctx.wt = await import(pathToFileURL(wt).href);
}
fs.rmSync(path.dirname(tmp), { recursive: true });
const TABLES = ['BASIC', 'PWM', 'ORGAN', 'FORMANT', 'DIGITAL', 'METAL'];
const tables = {};
for (const name of TABLES) tables[name] = await ctx.wt.getTable(ctx.wt.builtinKey(name));

function render(engine, note, p1, p2, p3, decay, retrig, table) {
  const node = new ctx.Proc({ processorOptions: { slots: 1 } });
  if (table) node.port.onmessage({ data: { type: 'table', frames: tables[table].frames, levels: tables[table].levels } });
  const ev = (frame) => ({ type: 'note', slot: 0, frame, end: 1e12, engine, note, p1, p2, p3, decay, accent: 0.8 });
  node.port.onmessage({ data: [ev(0)] });
  if (retrig) node.port.onmessage({ data: [ev(retrig)] });
  const res = new Int16Array(FRAMES);
  const bufs = [[new Float32Array(128)]];
  globalThis.currentFrame = 0;
  for (let f = 0; f < FRAMES; f += 128) {
    node.process([], bufs);
    const b = bufs[0][0];
    for (let i = 0; i < 128 && f + i < FRAMES; i++) res[f + i] = Math.max(-32767, Math.min(32767, Math.round(b[i] * 32767)));
    globalThis.currentFrame += 128;
  }
  return res;
}

// Наборы: [p1, p2, p3, decay (мс), retrig (кадр второго удара или 0)].
const SETS = {
  16: [[0.5, 0.5, 0.5, 500, 0], [0.2, 0.9, 0.1, 200, 0], [0.8, 0.1, 0.9, 900, 12000]],
  17: [[0.125, 0, 0, 500, 0], [0.375, 0.5, 0.5, 500, 0], [0.625, 0.8, 0.3, 500, 0], [0.875, 0.3, 1, 500, 0]],
  18: [[0.5, 0.5, 0.5, 500, 0], [0.3, 0.9, 0.2, 800, 0], [0.75, 0.3, 0.9, 300, 0]],
  // WTABLE: [POSITION, WARP, UNISON, decay, retrig, таблица].
  19: [[0.5, 0.5, 0.5, 500, 0, 'BASIC'], [0.2, 0.3, 0, 500, 0, 'ORGAN'], [0.8, 0.8, 0.9, 500, 0, 'METAL'],
    [0.6, 0.1, 0.3, 500, 0, 'DIGITAL']],
};
const NOTES = [48, 64];
const cases = [];
for (const [e, sets] of Object.entries(SETS)) {
  sets.forEach(([p1, p2, p3, decay, retrig, table], k) => {
    for (const note of NOTES) {
      const file = `j${e}_s${k}_n${note}.i16`;
      fs.writeFileSync(path.join(outDir, file), Buffer.from(render(Number(e), note, p1, p2, p3, decay, retrig, table).buffer));
      cases.push({ file, engine: Number(e), set: k, note, p1, p2, p3, decay, retrig, table: table ?? '' });
    }
  });
}
fs.writeFileSync(path.join(outDir, 'jambo_cases.json'), JSON.stringify({ frames: FRAMES, block: 128, chunk: 24, cases }, null, 1));
// Контрольные отсчёты таблиц: уровни 0, 3, 6, 10 — кадры 0, 31, 63, каждый 16-й отсчёт.
const checks = {};
for (const name of TABLES) {
  const tb = tables[name];
  checks[name] = { frames: tb.frames, levels: [0, 3, 6, 10].map((L) => {
    const lv = tb.levels[L];
    const vals = [];
    for (const f of [0, 31, 63]) for (let j = 0; j < lv.size; j += 16) vals.push(lv.data[f * lv.size + j]);
    return { level: L, size: lv.size, values: vals };
  }) };
}
fs.writeFileSync(path.join(outDir, 'jambo_tables.json'), JSON.stringify(checks));
console.log(`jambo golden: ${cases.length} cases → ${outDir}`);
