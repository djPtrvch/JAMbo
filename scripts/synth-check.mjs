// Офлайн-проверка своих движков (jambo-synth-worklet.js) в Node: рендер голоса и спектр (FFT).
// Запуск: node scripts/synth-check.mjs
// Проверяет: алиасинг (синус C7 у FM — ratio 1, index 0; пила C6 у ANALOG — не гармоники ниже
// −60 dBc в слышимой области), пики (≤ 0 dBFS при любых ручках), отсутствие NaN, скачки уровня
// у DRUM (TONE) и ANALOG (WAVE), нагрузку (время расчёта 8 голосов).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
// Заглушки AudioWorklet как настоящие глобальные (без vm: в песочнице vm обращения к Math медленнее
// и замер нагрузки неверен); worklet загружается копией-модулем.
const ctx = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
  registerProcessor(name, cls) { ctx.Proc = cls; },
});
const src = fs.readFileSync(new URL('../public/jambo-synth-worklet.js', import.meta.url), 'utf8');
const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'jb-')), 'worklet.mjs');
fs.writeFileSync(tmp, src);
await import(pathToFileURL(tmp).href);
// Таблицы WTABLE — из src/audio/wavetable.ts (типы снимает Node, хранилище не нужно — встроенные таблицы).
{
  const { stripTypeScriptTypes } = await import('node:module');
  const ts = fs.readFileSync(new URL('../src/audio/wavetable.ts', import.meta.url), 'utf8')
    .replace(/^import .*storage.*$/m, 'const getSample = async () => undefined;');
  const wt = path.join(path.dirname(tmp), 'wavetable.mjs');
  fs.writeFileSync(wt, stripTypeScriptTypes(ts));
  ctx.wt = await import(pathToFileURL(wt).href);
  const tb = await ctx.wt.getTable('');
  ctx.testTable = { type: 'table', frames: tb.frames, levels: tb.levels };
}
Object.defineProperty(ctx, 'currentFrame', { get: () => globalThis.currentFrame, set: (v) => { globalThis.currentFrame = v; } });

/** Узел с одним голосом: нота с параметрами, рендер n кадров (блоками по 128, как в браузере). */
function render({ engine, note, p1 = 0.5, p2 = 0.5, p3 = 0.5, decay = 500, frames = 16384, table = null, slots = 1 }) {
  const node = new ctx.Proc({ processorOptions: { slots } });
  if (table) node.port.onmessage({ data: table });
  const evs = [];
  for (let s = 0; s < slots; s++) evs.push({ type: 'note', slot: s, frame: 0, end: 1e12, engine, note, p1, p2, p3, decay, accent: 0.8 });
  node.port.onmessage({ data: evs });
  const out = new Float32Array(frames);
  const bufs = Array.from({ length: slots }, () => [new Float32Array(128)]);
  ctx.currentFrame = 0;
  for (let f = 0; f < frames; f += 128) {
    node.process([], bufs);
    out.set(bufs[0][0].subarray(0, Math.min(128, frames - f)), f);
    ctx.currentFrame += 128;
  }
  return { out, node };
}

// ---------- FFT ----------
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const a = -2 * Math.PI / len;
    for (let i = 0; i < n; i += len) {
      for (let k = 0; k < len / 2; k++) {
        const wr = Math.cos(a * k), wi = Math.sin(a * k);
        const xr = re[i + k + len / 2] * wr - im[i + k + len / 2] * wi;
        const xi = re[i + k + len / 2] * wi + im[i + k + len / 2] * wr;
        re[i + k + len / 2] = re[i + k] - xr; im[i + k + len / 2] = im[i + k] - xi;
        re[i + k] += xr; im[i + k] += xi;
      }
    }
  }
}

/** Спектр (дБ) окна из N отсчётов с конца сигнала (Блэкман–Харрис). */
function spectrum(x, N = 16384) {
  const re = new Float64Array(N), im = new Float64Array(N);
  const off = x.length - N;
  for (let i = 0; i < N; i++) {
    const t = i / (N - 1);
    const w = 0.35875 - 0.48829 * Math.cos(2 * Math.PI * t) + 0.14128 * Math.cos(4 * Math.PI * t) - 0.01168 * Math.cos(6 * Math.PI * t);
    re[i] = x[off + i] * w;
  }
  fft(re, im);
  const db = new Float64Array(N / 2);
  for (let k = 0; k < N / 2; k++) db[k] = 10 * Math.log10(re[k] * re[k] + im[k] * im[k] + 1e-30);
  return db;
}

/**
 * Наибольшая составляющая не на гармониках основного тона (dBc) в полосе 20 Гц … 20 кГц.
 * Основной тон — по пику спектра; у гармоник окно ±(4 + n·0.002·n) бинов (дрейф ANALOG).
 */
function worstAlias(x, N = 16384) {
  const db = spectrum(x, N);
  const binHz = SR / N;
  let k0 = 1;
  for (let k = 2; k < N / 2; k++) if (db[k] > db[k0]) k0 = k;
  const f0 = k0 * binHz, ref = db[k0];
  let worst = -Infinity, at = 0;
  for (let k = Math.ceil(20 / binHz); k < Math.min(N / 2, 20000 / binHz); k++) {
    const h = Math.round(k * binHz / f0);
    const dk = Math.abs(k - h * f0 / binHz);
    if (h >= 1 && dk <= 5 + h * 0.15) continue;
    if (db[k] - ref > worst) { worst = db[k] - ref; at = k * binHz; }
  }
  return { f0: Math.round(f0), worst: +worst.toFixed(1), at: Math.round(at) };
}

const peak = (x) => x.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
const hasNaN = (x) => x.some((v) => !Number.isFinite(v));
const rms = (x, a, b) => { let s = 0; for (let i = a; i < b; i++) s += x[i] * x[i]; return Math.sqrt(s / (b - a)); };
const dbfs = (v) => (20 * Math.log10(v)).toFixed(1);
const C = (oct) => 12 * (oct + 1); // MIDI: C4 = 60

let fail = 0;
const check = (ok, msg) => { console.log(`${ok ? 'OK  ' : 'FAIL'} ${msg}`); if (!ok) fail++; };

// Алиасинг.
{
  const fmSine = worstAlias(render({ engine: 18, note: C(7), p1: 1 / 4, p2: 0, p3: 0, frames: 32768 }).out);
  check(fmSine.worst < -60, `FM sine C7 (ratio 1, index 0): f0 ${fmSine.f0} Hz, worst non-harmonic ${fmSine.worst} dBc at ${fmSine.at} Hz`);
  const saw = worstAlias(render({ engine: 17, note: C(6), p1: 2 / 3, p2: 0, p3: 0, frames: 32768 }).out);
  check(saw.worst < -60, `ANALOG saw C6: f0 ${saw.f0} Hz, worst non-harmonic ${saw.worst} dBc at ${saw.at} Hz`);
}

// WTABLE: встроенные таблицы звучат, алиасинг пилы (BASIC, позиция 50 %) на C6.
{
  for (const name of ctx.wt.BUILTIN_TABLES) {
    const tb = await ctx.wt.getTable(ctx.wt.builtinKey(name));
    const t = { type: 'table', frames: tb.frames, levels: tb.levels };
    const pk = [0, 0.5, 1].map((p1) => peak(render({ engine: 19, note: C(3), p1, p2: 0, p3: 0, frames: 4800, table: t }).out));
    check(Math.min(...pk) > 0.05 && Math.max(...pk) <= 1, `WTABLE ${name}: peak ${pk.map(dbfs).join(' / ')} dBFS (position 0 / 50 / 100 %)`);
  }
  const saw = worstAlias(render({ engine: 19, note: C(6), p1: 0.5, p2: 0, p3: 0, frames: 32768, table: ctx.testTable }).out);
  check(saw.worst < -60, `WTABLE BASIC saw C6: worst non-harmonic ${saw.worst} dBc at ${saw.at} Hz`);
}

// Пики и NaN по сетке ручек.
for (const [engine, name] of [[16, 'DRUM'], [17, 'ANALOG'], [18, 'FM'], [19, 'WTABLE']]) {
  let worst = 0, nan = false;
  for (const note of [C(1), C(3), C(5), C(7)]) for (const p1 of [0, 0.5, 1]) for (const p2 of [0, 0.5, 1]) for (const p3 of [0, 0.5, 1]) {
    const { out } = render({ engine, note, p1, p2, p3, frames: 4800, table: engine === 19 ? ctx.testTable : null });
    if (peak(out) > worst) { worst = peak(out); ctx.worstAt = { note, p1, p2, p3 }; }
    nan ||= hasNaN(out);
  }
  if (engine === 19 && !ctx.testTable) { console.log('skip WTABLE peaks (no table)'); continue; }
  check(!nan && worst <= 1, `${name}: peak ${dbfs(worst)} dBFS over the knob grid (worst at ${JSON.stringify(ctx.worstAt)}), NaN: ${nan}`);
}

// Уровень по ручке: DRUM TONE и ANALOG WAVE (RMS первых 100 мс / установившийся).
{
  const lv = [0, 0.25, 0.5, 0.75, 1].map((t) => rms(render({ engine: 16, note: C(2), p1: 0.5, p2: t, p3: 0, frames: 4800 }).out, 0, 4800));
  const span = 20 * Math.log10(Math.max(...lv) / Math.min(...lv));
  check(span < 2, `DRUM TONE 0→100 %: RMS ${lv.map(dbfs).join(' / ')} dBFS (spread ${span.toFixed(1)} dB)`);
  const pk = [];
  for (let w = 0; w <= 1.0001; w += 0.05) pk.push(peak(render({ engine: 17, note: C(3), p1: w, p2: 0, p3: 0, frames: 9600 }).out.subarray(4800)));
  const pspan = 20 * Math.log10(Math.max(...pk) / Math.min(...pk));
  check(pspan < 2, `ANALOG WAVE 0→100 % (step 5 %): peak ${dbfs(Math.min(...pk))} … ${dbfs(Math.max(...pk))} dBFS (spread ${pspan.toFixed(1)} dB)`);
}

// Нагрузка: 8 голосов (по движку) на 1 с звука.
for (const [engine, name] of [[16, 'DRUM'], [17, 'ANALOG'], [18, 'FM'], [19, 'WTABLE']]) {
  if (engine === 19 && !ctx.testTable) continue;
  const t0 = performance.now();
  render({ engine, note: C(3), p1: 0.7, p2: 0.7, p3: 0.7, decay: 4000, frames: SR, slots: 8, table: engine === 19 ? ctx.testTable : null });
  const ms = performance.now() - t0;
  console.log(`CPU  ${name}: 8 voices × 1 s rendered in ${ms.toFixed(0)} ms (${(ms / 10).toFixed(1)} % of one core here)`);
}

export { render, worstAlias, peak };
if (fail) { console.log(`${fail} check(s) failed`); process.exitCode = 1; }
