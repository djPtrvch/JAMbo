// Эталоны своих движков JAMbo (DRUM, ANALOG, FM) для Swift-версии: рендер public/jambo-synth-worklet.js в Node
// так же, как браузер (блоки process() по 128 кадров, внутри — куски по 24; 48 кГц; дрейф ANALOG — свой генератор
// узла с начального состояния). Голос слота 0, нота в кадре 0 (у случая с retrig — второй удар в кадре retrig).
// Выход: ios/JAMbo.swiftpm/Resources/golden/j<движок>_s<набор>_n<нота>.i16 (1 с, Int16 = round(x·32767))
// и jambo_cases.json. Запуск: node ios/tools/jambo/golden.mjs
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
fs.rmSync(path.dirname(tmp), { recursive: true });

function render(engine, note, p1, p2, p3, decay, retrig) {
  const node = new ctx.Proc({ processorOptions: { slots: 1 } });
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
};
const NOTES = [48, 64];
const cases = [];
for (const [e, sets] of Object.entries(SETS)) {
  sets.forEach(([p1, p2, p3, decay, retrig], k) => {
    for (const note of NOTES) {
      const file = `j${e}_s${k}_n${note}.i16`;
      fs.writeFileSync(path.join(outDir, file), Buffer.from(render(Number(e), note, p1, p2, p3, decay, retrig).buffer));
      cases.push({ file, engine: Number(e), set: k, note, p1, p2, p3, decay, retrig });
    }
  });
}
fs.writeFileSync(path.join(outDir, 'jambo_cases.json'), JSON.stringify({ frames: FRAMES, block: 128, chunk: 24, cases }, null, 1));
console.log(`jambo golden: ${cases.length} cases → ${outDir}`);
