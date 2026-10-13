// Офлайн-проверка Delay (public/delay-worklet.js) в Node: рендер и замеры.
// Запуск: node scripts/delay-check.mjs
// Проверяет: время повторов и их амплитуды (степени FEEDBACK); ping-pong при SPREAD 100 %; FILTER на каждом
// повторе; устойчивость при FEEDBACK 100 % (60 с шума); скачки при смене TIME на хвосте; нагрузку (1 и 8 инстансов).
// Для замера времени повторов модуляция «лента» выключается (её wow ±0,2 мс сдвигает повтор на ±10 сэмплов).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const src = fs.readFileSync(new URL('../public/delay-worklet.js', import.meta.url), 'utf8');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dly-'));

/** Загрузить класс узла (noMod — без wow и flutter). */
async function load(noMod) {
  const ctx = {};
  Object.assign(globalThis, {
    sampleRate: SR, currentFrame: 0,
    AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
    registerProcessor(name, cls) { ctx.Proc = cls; },
  });
  let code = src;
  if (noMod) code = code.replace('wowMs: 0.2', 'wowMs: 0').replace('flutterMs: 0.03', 'flutterMs: 0');
  const file = path.join(dir, `w${noMod ? 0 : 1}.mjs`);
  fs.writeFileSync(file, code);
  await import(pathToFileURL(file).href);
  return ctx.Proc;
}
const Plain = await load(true);
const Tape = await load(false);

const DEF = { time: 0.25, feedback: 0.5, filter: 0, spread: 0 };
function render(Proc, frames, input, params = () => DEF, node = new Proc({ processorOptions: { maxTime: 6 } })) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const iL = new Float32Array(BLOCK), iR = new Float32Array(BLOCK), oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  for (let b = 0; b * BLOCK < frames; b++) {
    for (let s = 0; s < BLOCK; s++) { const [l, r] = input(b * BLOCK + s); iL[s] = l; iR[s] = r; }
    const pp = Object.fromEntries(Object.entries({ ...DEF, ...params(b) }).map(([k, v]) => [k, new Float32Array([v])]));
    node.process([[iL, iR]], [[oL, oR]], pp);
    const n = Math.min(BLOCK, frames - b * BLOCK);
    L.set(oL.subarray(0, n), b * BLOCK); R.set(oR.subarray(0, n), b * BLOCK);
  }
  return [L, R];
}
const db = (x) => 20 * Math.log10(Math.max(1e-12, x));
const peakAt = (x, a, b) => { let m = 0, at = a; for (let i = a; i < b; i++) if (Math.abs(x[i]) > m) { m = Math.abs(x[i]); at = i; } return [at, m]; };
const energy = (x, a, b) => { let s = 0; for (let i = a; i < b; i++) s += x[i] * x[i]; return s; };
/** Биквад RBJ (Q 0.707): 'hp' | 'lp' на частоте f — для замеров. */
function filt(x, type, f) {
  const w = (2 * Math.PI * f) / SR, cw = Math.cos(w), al = Math.sin(w) / Math.SQRT2, a0 = 1 + al;
  const b0 = (type === 'hp' ? (1 + cw) / 2 : (1 - cw) / 2) / a0, b1 = (type === 'hp' ? -(1 + cw) : 1 - cw) / a0, a1 = (-2 * cw) / a0, a2 = (1 - al) / a0;
  const y = new Float32Array(x.length); let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) { const v = b0 * x[i] + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v; }
  return y;
}
const log = (s) => console.log(s);
const D = Math.round(0.25 * SR);
const impulse = (amp) => (i) => (i === 0 ? [amp, amp] : [0, 0]);

// 1. Повторы: 250 мс (1/8 при 120 BPM), FEEDBACK 50 %, малый импульс (сатурация линейна).
{
  const [L] = render(Plain, SR * 2, impulse(0.1));
  const reps = [1, 2, 3, 4].map((k) => peakAt(L, k * D - 200, k * D + 200));
  log(`Повторы (FB 50 %): позиции ${reps.map(([at], k) => at - (k + 1) * D).join(', ')} сэмплов от k·250 мс; амплитуды ${reps.map(([, a]) => a.toFixed(4)).join(', ')} (отношения ${reps.slice(1).map(([, a], k) => (a / reps[k][1]).toFixed(3)).join(', ')})`);
}
// 2. SPREAD 100 %: первый повтор слева, второй справа.
{
  const [L, R] = render(Plain, SR * 2, impulse(0.1), () => ({ spread: 1 }));
  const row = [1, 2, 3, 4].map((k) => { const [, l] = peakAt(L, k * D - 200, k * D + 200); const [, r] = peakAt(R, k * D - 200, k * D + 200); return `${k}: L ${db(l).toFixed(1)} / R ${db(r).toFixed(1)} dB`; });
  log(`SPREAD 100 %: ${row.join('; ')}`);
}
// 3. FILTER: энергия выше 2 кГц (LP) и ниже 200 Гц (HP) у 1-го и 2-го повтора.
for (const [f, type, hz] of [[-1, 'hp', 2000], [1, 'lp', 200]]) {
  const [L] = render(Plain, SR * 2, impulse(0.1), () => ({ filter: f }));
  const band = filt(L, type, hz);
  const e1 = energy(band, D - 100, D + 4000), e2 = energy(band, 2 * D - 100, 2 * D + 4000);
  log(`FILTER ${f > 0 ? '+' : '−'}100: энергия ${type === 'hp' ? 'выше 2 кГц' : 'ниже 200 Гц'} — 2-й повтор ниже 1-го на ${(10 * Math.log10(e1 / e2)).toFixed(1)} dB`);
}
// 4. FEEDBACK 100 %, 60 с шума: пик выхода против пика входа; нарастания нет.
{
  let seed = 1; const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff) * 2 - 1; };
  let inPeak = 0;
  const [L, R] = render(Tape, SR * 60, () => { const a = rnd() * 0.5, b = rnd() * 0.5; inPeak = Math.max(inPeak, Math.abs(a), Math.abs(b)); return [a, b]; }, () => ({ feedback: 1, time: 0.25 }));
  const pk = (a, b) => Math.max(peakAt(L, a, b)[1], peakAt(R, a, b)[1]);
  let nan = false; for (let i = 0; i < L.length; i++) if (!Number.isFinite(L[i]) || !Number.isFinite(R[i])) { nan = true; break; }
  const rms = (a, b) => Math.sqrt(energy(L, a, b) / (b - a));
  log(`FEEDBACK 100 %, 60 с шума (пик входа ${db(inPeak).toFixed(1)} dBFS): пик выхода ${db(pk(0, L.length)).toFixed(1)} dBFS; RMS 5–10 с ${db(rms(SR * 5, SR * 10)).toFixed(1)}, 50–60 с ${db(rms(SR * 50, SR * 60)).toFixed(1)} dBFS; NaN ${nan}`);
}
// 5. Смена TIME на звучащем хвосте (синус 300 Гц 0,5 с, потом хвост): наибольший скачок между соседними отсчётами.
{
  const sine = (i) => (i < SR / 2 ? [0.5 * Math.sin((2 * Math.PI * 300 * i) / SR), 0.5 * Math.sin((2 * Math.PI * 300 * i) / SR)] : [0, 0]);
  const at = Math.round((1.2 * SR) / BLOCK);
  const jump = (p) => { const [L] = render(Tape, SR * 2, sine, p); let m = 0; for (let i = SR; i < SR * 2 - 1; i++) m = Math.max(m, Math.abs(L[i + 1] - L[i])); return m; };
  const base = jump(() => ({ feedback: 0.7 }));
  const ch = jump((b) => ({ feedback: 0.7, time: b < at ? 0.25 : 0.125 }));
  const ch2 = jump((b) => ({ feedback: 0.7, time: b < at ? 0.25 : 0.5 }));
  log(`Смена TIME 1/8 → 1/16 и 1/8 → 1/4 на хвосте: наибольший скачок между отсчётами ${ch.toFixed(4)} и ${ch2.toFixed(4)} (без смены ${base.toFixed(4)}; скачок синуса 300 Гц амплитуды 0,5 — до ${(0.5 * 2 * Math.PI * 300 / SR).toFixed(4)})`);
}
// 6. Нагрузка: 10 с шума, 1 и 8 инстансов.
for (const count of [1, 8]) {
  const nodes = Array.from({ length: count }, () => new Tape({ processorOptions: { maxTime: 6 } }));
  const sec = 10;
  const t0 = performance.now();
  for (const nd of nodes) render(Tape, SR * sec, () => [Math.random() - 0.5, Math.random() - 0.5], () => ({ feedback: 0.6, filter: -0.3, spread: 0.7 }), nd);
  log(`Нагрузка: ${count} инстанс(ов) — ${(((performance.now() - t0) / (sec * 1000)) * 100).toFixed(1)} % одного ядра`);
}
