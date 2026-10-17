// Эталоны движков Plaits для Swift-версии: рендер public/plaits.wasm так же, как играет веб
// (plaits-worklet.js на 48 кГц: нота сдвигается на 12·log2(47872,34/48000), accent 0,8, блоки по 24 отсчёта,
// триггер — один блок). Свежий экземпляр wasm на каждый случай (общий генератор шума — с начального состояния).
// Выход: Resources/golden/e<движок>_s<набор>_n<нота>.i16 (1 с, Int16 = round(x·32767)) и cases.json.
// У движков 11–15 (ручка 1.3 — OUT→AUX) — ещё выход AUX на наборе 0: e<движок>_s0_n<нота>_aux.i16 (aux_mix 1).
// Запуск: node ios/tools/plaits/golden.mjs [движки через запятую, по умолчанию 0–15]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const out = path.join(root, 'ios/JAMbo.swiftpm/Resources/golden');
const bytes = fs.readFileSync(path.join(root, 'public/plaits.wasm'));
const module = new WebAssembly.Module(bytes);

const FRAMES = 48000;
const BLOCK = 24;
const ACCENT = 0.8;
const SHIFT = 12 * Math.log2(47872.34 / 48000);
const SETS = [[0.5, 0.5, 0.5], [0.25, 0.75, 0.2], [0.8, 0.15, 0.85]];
// SPEECH: harmonics — точки пунктов Formant, Phoneme, LPC.
const SPEECH_H = [0, 1 / 6, 1 / 3];
const NOTES = [48, 64];
const engines = (process.argv[2] ?? '0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15').split(',').map(Number);

function render(engine, note, h, t, m, aux) {
  const w = new WebAssembly.Instance(module, {}).exports;
  if (w._initialize) w._initialize();
  w.init();
  w.set(0, engine, note + SHIFT, h, t, m, ACCENT, aux);
  w.trigger(0);
  const res = new Int16Array(FRAMES);
  for (let pos = 0; pos < FRAMES; pos += BLOCK) {
    const n = Math.min(BLOCK, FRAMES - pos);
    const ptr = w.render(0, n);
    w.release(0);
    const buf = new Float32Array(w.memory.buffer, ptr, n);
    for (let i = 0; i < n; i++) res[pos + i] = Math.max(-32767, Math.min(32767, Math.round(buf[i] * 32767)));
  }
  return res;
}

fs.mkdirSync(out, { recursive: true });
const cases = [];
for (const e of engines) {
  SETS.forEach((s, k) => {
    const [h, t, m] = e === 7 ? [SPEECH_H[k], s[1], s[2]] : s;
    for (const note of NOTES) {
      const file = `e${e}_s${k}_n${note}.i16`;
      fs.writeFileSync(path.join(out, file), Buffer.from(render(e, note, h, t, m, 0).buffer));
      cases.push({ file, engine: e, set: k, note, harmonics: h, timbre: t, morph: m });
      if (e >= 11 && k === 0) {
        const auxFile = `e${e}_s${k}_n${note}_aux.i16`;
        fs.writeFileSync(path.join(out, auxFile), Buffer.from(render(e, note, h, t, m, 1).buffer));
        cases.push({ file: auxFile, engine: e, set: k, note, harmonics: h, timbre: t, morph: m, aux: 1 });
      }
    }
  });
}
fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify({ frames: FRAMES, block: BLOCK, accent: ACCENT, cases }, null, 1));
console.log(`golden: ${cases.length} cases → ${out}`);
