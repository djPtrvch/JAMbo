// Эталоны мастера для Swift-версии (S5a): рендер worklet'ов веба (public/saturator-, glue-, clipper-, limiter-worklet.js,
// oversampler.js) в Node так же, как браузер — блоки process() по 128 кадров, 48 кГц; параметры — сообщения port
// (как sendDynamics в engine.ts), события — в начале блока. Параметры, убранные в Swift (BIAS, OUTPUT, AUTO сатуратора,
// RANGE, HOLD, LINK компрессора, MIX клиппера, LINK лимитера, UNITY, AUDIT), — по умолчанию: при них звук прежний.
// Случай chain — все четыре модуля по цепочке (SAT → COMP → CLIP → LIM) в каждом блоке.
// Выход: ios/JAMbo.swiftpm/Resources/golden/mst_<имя>.i16 (стерео L,R по очереди, Int16 = round(x·32767)) и mst_cases.json.
// Запуск: node ios/tools/master/golden.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const outDir = path.join(root, 'ios/JAMbo.swiftpm/Resources/golden');
const SR = 48000;
const BLOCK = 128;

/** mulberry32 — как FxRandom в Swift. */
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
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mst-'));
for (const f of ['oversampler.js', 'saturator-worklet.js', 'glue-worklet.js', 'clipper-worklet.js', 'limiter-worklet.js']) {
  const tmp = path.join(tmpDir, f.replace('.js', '.mjs'));
  fs.writeFileSync(tmp, fs.readFileSync(path.join(root, 'public', f), 'utf8'));
  await import(pathToFileURL(tmp).href);
}
fs.rmSync(tmpDir, { recursive: true });

/** Вход случая (Float32). sine — синус 440 Гц −12 dBFS первые 0,5 с, затем тишина; stereo — L шум-удар,
 *  R синус 660 Гц (30 мс); drums — 4 удара в секунду: «бочка» (синус 55 Гц с падением высоты, амплитуда 0.9,
 *  спад 120 мс) и между ними «хэт» (шум 0.4, спад 15 мс, seed 5), плюс синус 220 Гц 0.2 только в R;
 *  loud — синус 1 кГц 0 dBFS первые 0,5 с, затем синус 5 кГц −3 dBFS. */
function input(kind, frames) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  if (kind === 'sine') {
    for (let i = 0; i < 24000 && i < frames; i++) { const v = 0.25 * Math.sin((2 * Math.PI * 440 * i) / SR); L[i] = v; R[i] = v; }
  } else if (kind === 'stereo') {
    const rnd = mulberry32(11);
    for (let i = 0; i < 1440; i++) { L[i] = (rnd() * 2 - 1) * 0.5; R[i] = 0.3 * Math.sin((2 * Math.PI * 660 * i) / SR); }
  } else if (kind === 'drums') {
    const rnd = mulberry32(5);
    for (let i = 0; i < frames; i++) {
      const t = (i % 12000) / SR;
      const th = ((i + 6000) % 12000) / SR;
      const kick = 0.9 * Math.exp(-t / 0.12) * Math.sin(2 * Math.PI * (55 * t + 40 * 0.03 * (1 - Math.exp(-t / 0.03))));
      const hat = 0.4 * Math.exp(-th / 0.015) * (rnd() * 2 - 1);
      L[i] = kick + hat;
      R[i] = kick + hat + 0.2 * Math.sin((2 * Math.PI * 220 * i) / SR);
    }
  } else if (kind === 'loud') {
    for (let i = 0; i < frames; i++) {
      const v = i < 24000 ? Math.sin((2 * Math.PI * 1000 * i) / SR) : 0.708 * Math.sin((2 * Math.PI * 5000 * i) / SR);
      L[i] = v; R[i] = 0.9 * v;
    }
  }
  return [L, R];
}

/** Рендер: proc — 'saturator' | 'glue' | 'clipper' | 'limiter' | 'chain'; msg — параметры (у chain — { sat, glue, clip, lim });
 *  events — [{ frame (кратно 128), msg }]. */
function render(c) {
  const names = c.proc === 'chain' ? ['saturator', 'glue', 'clipper', 'limiter'] : [c.proc];
  const keys = { saturator: 'sat', glue: 'glue', clipper: 'clip', limiter: 'lim' };
  const nodes = names.map((n) => new procs[n]({}));
  const send = (msg) => {
    if (!msg) return;
    names.forEach((n, k) => {
      const m = c.proc === 'chain' ? msg[keys[n]] : msg;
      if (m) nodes[k].port.onmessage({ data: m });
    });
  };
  send(c.msg);
  const [iL, iR] = input(c.input, c.frames);
  const res = new Int16Array(c.frames * 2);
  const bufs = names.map(() => [new Float32Array(BLOCK), new Float32Array(BLOCK)]);
  const bL = new Float32Array(BLOCK), bR = new Float32Array(BLOCK);
  for (let f = 0; f < c.frames; f += BLOCK) {
    for (const e of c.events ?? []) if (e.frame === f) send(e.msg);
    bL.set(iL.subarray(f, f + BLOCK)); bR.set(iR.subarray(f, f + BLOCK));
    let src = [bL, bR];
    nodes.forEach((node, k) => {
      node.process([src], [bufs[k]], {});
      src = bufs[k];
    });
    for (let i = 0; i < BLOCK && f + i < c.frames; i++) {
      res[2 * (f + i)] = Math.max(-32767, Math.min(32767, Math.round(src[0][i] * 32767)));
      res[2 * (f + i) + 1] = Math.max(-32767, Math.min(32767, Math.round(src[1][i] * 32767)));
    }
  }
  return res;
}

const F = 48000;
const CASES = [
  { name: 'sat_tape', proc: 'saturator', frames: F, input: 'drums', msg: { drive: 12, type: 0, tone: 0, mix: 100, focus: 20 } },
  { name: 'sat_tube_tone', proc: 'saturator', frames: F, input: 'sine', msg: { drive: 18, type: 1, tone: 60, mix: 100, focus: 20 } },
  { name: 'sat_edge_mix', proc: 'saturator', frames: F, input: 'loud', msg: { drive: 6, type: 2, tone: -40, mix: 60, focus: 20 } },
  { name: 'sat_focus', proc: 'saturator', frames: F, input: 'drums', msg: { drive: 18, type: 0, tone: 0, mix: 100, focus: 500 } },
  { name: 'sat_moves', proc: 'saturator', frames: F, input: 'drums', msg: { drive: 0, type: 0, tone: 0, mix: 100, focus: 20 },
    events: [{ frame: 4096, msg: { drive: 12 } }, { frame: 8192, msg: { type: 1 } }, { frame: 12032, msg: { type: 2, tone: 100 } },
      { frame: 16000, msg: { focus: 800 } }, { frame: 20096, msg: { mix: 0 } }, { frame: 26112, msg: { mix: 100, focus: 20, drive: 24 } },
      { frame: 32000, msg: { drive: 0 } }, { frame: 40064, msg: { drive: 6, type: 0 } }] },
  { name: 'cmp_default', proc: 'glue', frames: F, input: 'drums', msg: { thr: -10, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false, knee: 6, mix: 100, schpf: 90 } },
  { name: 'cmp_hard_auto', proc: 'glue', frames: F, input: 'drums', msg: { thr: -24, att: 0.5, rel: 400, auto: true, makeup: 6, ratio: 10, bypass: false, knee: 0, mix: 100, schpf: 20 } },
  { name: 'cmp_mix_knee', proc: 'glue', frames: F, input: 'loud', msg: { thr: -18, att: 30, rel: 80, auto: false, makeup: 3, ratio: 4, bypass: false, knee: 24, mix: 50, schpf: 300 } },
  { name: 'cmp_moves', proc: 'glue', frames: F, input: 'drums', msg: { thr: -10, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false, knee: 6, mix: 100, schpf: 90 },
    events: [{ frame: 6016, msg: { thr: -30, ratio: 20 } }, { frame: 12032, msg: { bypass: true } }, { frame: 18048, msg: { bypass: false, knee: 0, schpf: 20 } },
      { frame: 24064, msg: { rel: 400, auto: true, att: 100 } }, { frame: 30080, msg: { mix: 20, makeup: 12 } }, { frame: 36096, msg: { schpf: 500, ratio: 1 } }] },
  { name: 'clip_default', proc: 'clipper', frames: F, input: 'drums', msg: { drive: 6, ceiling: -1, softness: 30, bass: 0, bypass: false } },
  { name: 'clip_bass_hard', proc: 'clipper', frames: F, input: 'drums', msg: { drive: 12, ceiling: -1, softness: 0, bass: 120, bypass: false } },
  { name: 'clip_soft_low', proc: 'clipper', frames: F, input: 'loud', msg: { drive: 3, ceiling: -6, softness: 100, bass: 0, bypass: false } },
  { name: 'clip_moves', proc: 'clipper', frames: F, input: 'drums', msg: { drive: 6, ceiling: -1, softness: 30, bass: 0, bypass: false },
    events: [{ frame: 6016, msg: { bass: 200 } }, { frame: 12032, msg: { bass: 60, softness: 0 } }, { frame: 18048, msg: { bypass: true } },
      { frame: 24064, msg: { bypass: false, bass: 0, ceiling: -9 } }, { frame: 30080, msg: { drive: 12, softness: 100 } }] },
  { name: 'lim_gain', proc: 'limiter', frames: F, input: 'drums', msg: { gain: 12, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false } },
  { name: 'lim_auto', proc: 'limiter', frames: F, input: 'loud', msg: { gain: 6, ceiling: -1, lookahead: 3, rel: 150, auto: true, bypass: false } },
  { name: 'lim_short', proc: 'limiter', frames: F, input: 'drums', msg: { gain: 18, ceiling: -3, lookahead: 1, rel: 40, auto: false, bypass: false } },
  { name: 'lim_moves', proc: 'limiter', frames: F, input: 'drums', msg: { gain: 12, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false },
    events: [{ frame: 6016, msg: { lookahead: 6 } }, { frame: 12032, msg: { lookahead: 0.5, ceiling: -6 } }, { frame: 18048, msg: { bypass: true } },
      { frame: 24064, msg: { bypass: false, rel: 1000 } }, { frame: 30080, msg: { rel: 400, auto: true, gain: 24 } }] },
  { name: 'chain_default', proc: 'chain', frames: F, input: 'drums', msg: {
    sat: { drive: 0, type: 0, tone: 0, mix: 100, focus: 20 },
    glue: { thr: -10, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false, knee: 6, mix: 100, schpf: 90 },
    clip: { drive: 0, ceiling: -1, softness: 30, bass: 0, bypass: false },
    lim: { gain: 0, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false } } },
  { name: 'chain_hot', proc: 'chain', frames: F, input: 'drums', msg: {
    sat: { drive: 9, type: 1, tone: 20, mix: 80, focus: 120 },
    glue: { thr: -20, att: 3, rel: 400, auto: true, makeup: 6, ratio: 4, bypass: false, knee: 6, mix: 100, schpf: 90 },
    clip: { drive: 4, ceiling: -1.5, softness: 30, bass: 100, bypass: false },
    lim: { gain: 6, ceiling: -0.3, lookahead: 3, rel: 150, auto: true, bypass: false } },
    events: [{ frame: 24064, msg: { sat: { mix: 0 }, glue: { bypass: true }, clip: { bypass: true }, lim: { bypass: true } } }] },
];

const cases = [];
for (const c of CASES) {
  const file = `mst_${c.name}.i16`;
  fs.writeFileSync(path.join(outDir, file), Buffer.from(render(c).buffer));
  const { name, ...rest } = c;
  cases.push({ file, ...rest, events: c.events ?? [] });
}
fs.writeFileSync(path.join(outDir, 'mst_cases.json'), JSON.stringify({ block: BLOCK, cases }, null, 1));
console.log(`master golden: ${cases.length} cases → ${outDir}`);
