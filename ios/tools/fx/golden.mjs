// Эталоны FX для Swift-версии (S4): рендер worklet'ов веба (public/*-worklet.js) в Node так же, как браузер —
// блоки process() по 128 кадров, k-rate параметры берутся в начале блока, 48 кГц. Math.random заменён на mulberry32
// с seed случая (Swift повторяет тот же генератор — FxRandom), поэтому модуляция (wow, flutter, LFO линий)
// сравнивается по отсчётам. Вход — детерминированный (как FxGolden.input в Swift).
// Выход: ios/JAMbo.swiftpm/Resources/golden/fx_<имя>.i16 (стерео L,R по очереди, Int16 = round(x·32767)) и fx_cases.json.
// Запуск: node ios/tools/fx/golden.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const outDir = path.join(root, 'ios/JAMbo.swiftpm/Resources/golden');
const SR = 48000;
const BLOCK = 128;

/** mulberry32 — как IconRandom / FxRandom в Swift. */
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const procs = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
  registerProcessor(name, cls) { procs[name] = cls; },
});
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fx-'));
for (const f of ['delay-worklet.js', 'reverb-worklet.js']) {
  const tmp = path.join(tmpDir, f.replace('.js', '.mjs'));
  fs.writeFileSync(tmp, fs.readFileSync(path.join(root, 'public', f), 'utf8'));
  await import(pathToFileURL(tmp).href);
}
fs.rmSync(tmpDir, { recursive: true });

/** Вход случая (Float32, как буферы Web Audio). burst — шум 50 мс (амплитуда 0.5, генератор seed 7) в кадре 0
 *  и тише (0.25) в кадре 36000; sine — синус 440 Гц −12 dBFS первые 0.5 с, затем тишина; stereo — L шум-удар,
 *  R синус 660 Гц (короткие, 30 мс). */
function input(kind, frames) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  if (kind === 'burst') {
    const rnd = mulberry32(7);
    for (let i = 0; i < 2400; i++) { L[i] = (rnd() * 2 - 1) * 0.5; R[i] = (rnd() * 2 - 1) * 0.5; }
    for (let i = 0; i < 2400 && 36000 + i < frames; i++) { L[36000 + i] = (rnd() * 2 - 1) * 0.25; R[36000 + i] = (rnd() * 2 - 1) * 0.25; }
  } else if (kind === 'sine') {
    for (let i = 0; i < 24000 && i < frames; i++) { const v = 0.25 * Math.sin((2 * Math.PI * 440 * i) / SR); L[i] = v; R[i] = v; }
  } else if (kind === 'stereo') {
    const rnd = mulberry32(11);
    for (let i = 0; i < 1440; i++) { L[i] = (rnd() * 2 - 1) * 0.5; R[i] = 0.3 * Math.sin((2 * Math.PI * 660 * i) / SR); }
  }
  return [L, R];
}

/** Рендер: params — начальные значения AudioParam; events — [{ frame (кратно 128), params }]. */
function render(c) {
  Math.random = mulberry32(c.seed);
  const Proc = procs[c.proc];
  const node = new Proc({ processorOptions: c.options ?? {} });
  const vals = {};
  for (const d of Proc.parameterDescriptors) vals[d.name] = d.defaultValue;
  Object.assign(vals, c.params);
  const [iL, iR] = input(c.input, c.frames);
  const res = new Int16Array(c.frames * 2);
  const oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  const bL = new Float32Array(BLOCK), bR = new Float32Array(BLOCK);
  for (let f = 0; f < c.frames; f += BLOCK) {
    for (const e of c.events ?? []) if (e.frame === f) Object.assign(vals, e.params);
    const params = {};
    for (const k of Object.keys(vals)) params[k] = new Float32Array([vals[k]]);
    bL.set(iL.subarray(f, f + BLOCK)); bR.set(iR.subarray(f, f + BLOCK));
    node.process([[bL, bR]], [[oL, oR]], params);
    for (let i = 0; i < BLOCK && f + i < c.frames; i++) {
      res[2 * (f + i)] = Math.max(-32767, Math.min(32767, Math.round(oL[i] * 32767)));
      res[2 * (f + i) + 1] = Math.max(-32767, Math.min(32767, Math.round(oR[i] * 32767)));
    }
    globalThis.currentFrame += BLOCK;
  }
  return res;
}

const DLY = { proc: 'delay', options: { maxTime: 6 }, frames: 72000 };
const REV = { proc: 'reverb', frames: 72000 };
const CASES = [
  { name: 'dly_basic', ...DLY, seed: 1, input: 'burst', params: { time: 0.25, feedback: 0.5, filter: 0, spread: 0 } },
  { name: 'dly_lp', ...DLY, seed: 2, input: 'burst', params: { time: 0.1875, feedback: 0.7, filter: -0.6, spread: 0.3 } },
  { name: 'dly_hp_pingpong', ...DLY, seed: 3, input: 'stereo', params: { time: 0.125, feedback: 0.6, filter: 0.5, spread: 1 } },
  { name: 'dly_moves', ...DLY, seed: 4, input: 'sine', params: { time: 0.25, feedback: 0.8, filter: 0, spread: 0 },
    events: [{ frame: 12032, params: { time: 0.125 } }, { frame: 24064, params: { filter: -1 } },
      { frame: 36096, params: { filter: 1, spread: 0.8 } }, { frame: 48000, params: { time: 1, feedback: 1 } },
      { frame: 60032, params: { filter: 0.01, spread: 0.4 } }] },
  { name: 'rev_basic', ...REV, seed: 5, input: 'burst', params: { size: 50, decay: 2, tone: 0, lowcut: 120, predelay: 0 } },
  { name: 'rev_large', ...REV, seed: 6, input: 'burst', params: { size: 100, decay: 6, tone: 100, lowcut: 20, predelay: 30 } },
  { name: 'rev_small_dark', ...REV, seed: 7, input: 'stereo', params: { size: 0, decay: 0.5, tone: -100, lowcut: 300, predelay: 0 } },
  { name: 'rev_moves', ...REV, seed: 8, input: 'sine', params: { size: 0, decay: 2, tone: -100, lowcut: 20, predelay: 0 },
    events: [{ frame: 12032, params: { size: 100 } }, { frame: 24064, params: { decay: 8, predelay: 120 } },
      { frame: 36096, params: { tone: 100 } }, { frame: 48000, params: { lowcut: 300, size: 30 } },
      { frame: 60032, params: { decay: 0.5, tone: 0 } }] },
];

const cases = [];
for (const c of CASES) {
  const file = `fx_${c.name}.i16`;
  fs.writeFileSync(path.join(outDir, file), Buffer.from(render(c).buffer));
  const { name, ...rest } = c;
  cases.push({ file, ...rest, events: c.events ?? [] });
}
fs.writeFileSync(path.join(outDir, 'fx_cases.json'), JSON.stringify({ block: BLOCK, cases }, null, 1));
console.log(`fx golden: ${cases.length} cases → ${outDir}`);
