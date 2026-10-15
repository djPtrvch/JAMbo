// Эталоны движков Plaits для самотеста Swift-версии: public/plaits.wasm (то же, что играет веб), как AudioWorklet
// (plaits-worklet.js): init, set (нота со сдвигом на 48 кГц), trigger, render блоками по 24 кадра, release после
// каждого блока. На каждый случай — новый экземпляр (состояние генератора случайных чисел — как после init).
// Выход: Resources/golden/e<движок>_s<набор>_n<нота>.i16 (Int16, 1 с, 48 кГц, моно) и cases.json.
// Запуск: node ios/tools/plaits/golden.mjs [движки, например 0-7]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../../..');
const out = join(here, '../../JAMbo.swiftpm/Resources/golden');
mkdirSync(out, { recursive: true });
const bytes = readFileSync(join(root, 'public/plaits.wasm'));
const mod = new WebAssembly.Module(bytes);

const SR = 48000;
const FRAMES = SR;
const BLOCK = 24;
const SHIFT = 12 * Math.log2(47872.34 / SR);
const NOTES = [48, 64];
// Наборы harmonics, timbre, morph; у SPEECH harmonics — точки пунктов Formant, Phoneme, LPC.
const SETS = [[0.5, 0.5, 0.5], [0.25, 0.75, 0.2], [0.8, 0.15, 0.85]];
const SPEECH_H = [0, 1 / 6, 1 / 3];

const [a, b] = (process.argv[2] ?? '0-7').split('-').map(Number);
const cases = [];
for (let e = a; e <= (b ?? a); e++) {
  SETS.forEach((set, s) => {
    for (const note of NOTES) {
      const w = new WebAssembly.Instance(mod, {}).exports;
      if (w._initialize) w._initialize();
      w.init();
      const h = e === 7 ? SPEECH_H[s] : set[0];
      w.set(0, e, note + SHIFT, h, set[1], set[2], 0.8, 0);
      w.trigger(0);
      const pcm = new Int16Array(FRAMES);
      for (let pos = 0; pos < FRAMES; pos += BLOCK) {
        const n = Math.min(BLOCK, FRAMES - pos);
        const ptr = w.render(0, n);
        const buf = new Float32Array(w.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) pcm[pos + i] = Math.max(-32768, Math.min(32767, Math.round(buf[i] * 32767)));
        w.release(0);
      }
      const name = `e${e}_s${s}_n${note}.i16`;
      writeFileSync(join(out, name), Buffer.from(pcm.buffer));
      cases.push({ file: name, engine: e, set: s, note, harmonics: h, timbre: set[1], morph: set[2] });
    }
  });
}
// Добавить к уже записанным случаям других движков.
let all = [];
try { all = JSON.parse(readFileSync(join(out, 'cases.json'), 'utf8')).filter((c) => c.engine < a || c.engine > (b ?? a)); } catch { /* нет файла */ }
all = all.concat(cases).sort((x, y) => x.engine - y.engine || x.set - y.set || x.note - y.note);
writeFileSync(join(out, 'cases.json'), JSON.stringify({ frames: FRAMES, block: BLOCK, accent: 0.8, cases: all }, null, 1));
console.log(`${cases.length} cases → ${out}`);
