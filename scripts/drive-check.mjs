// Офлайн-проверка Drive (public/drive-worklet.js) в Node: рендер и спектры.
// Запуск: node scripts/drive-check.mjs
// Проверяет: линейность при DRIVE 0; гармоники по типам; громкость (пик и RMS) по DRIVE; LOW CUT; алиасинг;
// уровни и повтор CRUSH; скачки при смене TYPE и DRIVE; нагрузку (1 и 8 инстансов).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const ctx = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
  registerProcessor(name, cls) { ctx.Proc = cls; },
});
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'drv-'));
const put = (name, code) => { const f = path.join(dir, name); fs.writeFileSync(f, code); return pathToFileURL(f).href; };
await import(put('os.mjs', fs.readFileSync(new URL('../public/oversampler.js', import.meta.url), 'utf8')));
// Для замера уровней CRUSH — выход до фильтра DC и TONE (globalThis.RAW).
let code = fs.readFileSync(new URL('../public/drive-worklet.js', import.meta.url), 'utf8');
code = code.replace('        // Фильтр DC (HP 1-го порядка 5 Гц), TONE.', '        const rawY = y;\n        // Фильтр DC (HP 1-го порядка 5 Гц), TONE.').replace('o[i] = y;', 'o[i] = globalThis.RAW ? rawY : y;');
await import(put('drive.mjs', code));

const DEF = { drive: 26, type: 0, tone: 100, lowcut: 20 };
function render(frames, input, params = () => ({}), node = new ctx.Proc()) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const iL = new Float32Array(BLOCK), iR = new Float32Array(BLOCK), oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  for (let b = 0; b * BLOCK < frames; b++) {
    for (let s = 0; s < BLOCK; s++) { const v = input(b * BLOCK + s); iL[s] = v; iR[s] = v; }
    const pp = Object.fromEntries(Object.entries({ ...DEF, ...params(b) }).map(([k, v]) => [k, new Float32Array([v])]));
    node.process([[iL, iR]], [[oL, oR]], pp);
    const n = Math.min(BLOCK, frames - b * BLOCK);
    L.set(oL.subarray(0, n), b * BLOCK); R.set(oR.subarray(0, n), b * BLOCK);
  }
  return L;
}
const db = (x) => 20 * Math.log10(Math.max(1e-12, x));
const sine = (hz, amp = 0.25) => (i) => amp * Math.sin((2 * Math.PI * hz * i) / SR);

/** Спектр (БПФ 2^16, окно Блэкмана–Харриса) отрезка x с from. Амплитуды (линейно) по бинам. */
const N = 65536;
function spectrum(x, from = SR) {
  const re = new Float64Array(N), im = new Float64Array(N);
  let wsum = 0;
  for (let i = 0; i < N; i++) {
    const t = (2 * Math.PI * i) / (N - 1);
    const w = 0.35875 - 0.48829 * Math.cos(t) + 0.14128 * Math.cos(2 * t) - 0.01168 * Math.cos(3 * t);
    re[i] = x[from + i] * w; wsum += w;
  }
  for (let i = 1, j = 0; i < N; i++) { let bit = N >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; } }
  for (let len = 2; len <= N; len <<= 1) {
    const a = (-2 * Math.PI) / len, wr = Math.cos(a), wi = Math.sin(a);
    for (let i = 0; i < N; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k], vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci, vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi; re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
  const mag = new Float64Array(N / 2);
  for (let i = 0; i < N / 2; i++) mag[i] = (2 * Math.hypot(re[i], im[i])) / wsum;
  return mag;
}
const binOf = (hz) => Math.round((hz * N) / SR);
/** Пик спектра около частоты hz (±4 бина). */
const at = (m, hz) => { const b = binOf(hz); let v = 0; for (let k = b - 4; k <= b + 4; k++) if (k > 0 && k < m.length) v = Math.max(v, m[k]); return v; };
const NAMES = ['SOFT', 'HARD', 'TUBE', 'FUZZ', 'FOLD', 'CRUSH'];
const log = (s) => console.log(s);
const len = SR + N + 1000;

// 1. DRIVE 0, SOFT: синус 1 кГц −12 dBFS — сумма гармоник 2–10 к основному.
{
  const m = spectrum(render(len, sine(1000), () => ({ drive: 0 })));
  let h = 0; for (let k = 2; k <= 10; k++) h += at(m, 1000 * k) ** 2;
  log(`DRIVE 0 %, SOFT: гармоники 2–10 — ${db(Math.sqrt(h) / at(m, 1000)).toFixed(1)} dB к основному`);
}
// 2. Гармоники по типам (DRIVE 50 %, синус 1 кГц −12 dBFS): 2-я, 3-я, сумма 4–15.
for (const type of [0, 1, 2, 3, 4]) {
  const row = [];
  for (const drive of [26, 70]) {
    const m = spectrum(render(len, sine(1000), () => ({ drive, type })));
    const f = at(m, 1000);
    let rest = 0; for (let k = 4; k <= 15; k++) rest += at(m, 1000 * k) ** 2;
    row.push(`DRIVE ${drive}: 2-я ${db(at(m, 2000) / f).toFixed(1)}, 3-я ${db(at(m, 3000) / f).toFixed(1)}, 4–15-я ${db(Math.sqrt(rest) / f).toFixed(1)} dB`);
  }
  log(`${NAMES[type]}: ${row.join('; ')}`);
}
{
  const x = render(len, sine(1000), () => ({ drive: 100, type: 5 }));
  const m = spectrum(x);
  let noise = 0; const f = at(m, 1000);
  for (let k = binOf(100); k < binOf(20000); k++) { const hz = (k * SR) / N; if (Math.abs(hz - 1000) > 30) noise += m[k] ** 2; }
  log(`CRUSH, DRIVE 100 %: всё кроме основного — ${db(Math.sqrt(noise) / f).toFixed(1)} dB к основному`);
}
// 3. Громкость: синус 1 кГц −12 dBFS, пик и RMS выхода к входу (с учётом выходного 0.5 шины не считаем — здесь worklet).
for (const type of [0, 1, 2, 3, 4]) {
  let pkMin = 99, pkMax = -99, rmMin = 99, rmMax = -99;
  for (let drive = 0; drive <= 100; drive += 5) {
    const x = render(SR, sine(1000), () => ({ drive, type }));
    let pk = 0, ss = 0; for (let i = SR / 2; i < SR; i++) { pk = Math.max(pk, Math.abs(x[i])); ss += x[i] * x[i]; }
    const p = db(pk / 0.25), r = db(Math.sqrt(ss / (SR / 2)) / (0.25 / Math.SQRT2));
    pkMin = Math.min(pkMin, p); pkMax = Math.max(pkMax, p); rmMin = Math.min(rmMin, r); rmMax = Math.max(rmMax, r);
  }
  log(`Громкость ${NAMES[type]} (DRIVE 0–100 %): пик ${pkMin.toFixed(1)}…${pkMax.toFixed(1)} dB, RMS ${rmMin.toFixed(1)}…${rmMax.toFixed(1)} dB`);
}
// 4. LOW CUT 500 Гц: синус 100 Гц, DRIVE 70 %, SOFT — основной и продукты искажения к LOW CUT OFF.
{
  const m0 = spectrum(render(len, sine(100), () => ({ drive: 70 })));
  const m1 = spectrum(render(len, sine(100), () => ({ drive: 70, lowcut: 500 })));
  const harm = (m) => { let s = 0; for (let k = 2; k <= 30; k++) s += at(m, 100 * k) ** 2; return Math.sqrt(s); };
  log(`LOW CUT 500 Гц (синус 100 Гц, DRIVE 70 %): основной ${db(at(m1, 100) / at(m0, 100)).toFixed(1)} dB, продукты искажения ${db(harm(m1) / harm(m0)).toFixed(1)} dB к OFF`);
}
// 5. Алиасинг: синус 10 кГц −12 dBFS, DRIVE 70 % — наибольшая составляющая не на гармониках 10 кГц (до 20 кГц).
for (const type of [0, 1, 2, 3, 4]) {
  const m = spectrum(render(len, sine(10000), () => ({ drive: 70, type })));
  const f = at(m, 10000);
  let worst = 0;
  for (let k = binOf(50); k < binOf(21000); k++) {
    const hz = (k * SR) / N;
    if (Math.abs(hz - 10000) < 40 || Math.abs(hz - 20000) < 40) continue;
    worst = Math.max(worst, m[k]);
  }
  log(`Алиасинг ${NAMES[type]} (10 кГц, DRIVE 70 %): ${db(worst / f).toFixed(1)} dB к основному`);
}
// 6. CRUSH, DRIVE 100 %: уровни квантования и повтор отсчётов (выход до фильтра DC и TONE).
{
  globalThis.RAW = true;
  const x = render(SR, sine(50, 0.99), () => ({ drive: 100, type: 5 }));
  globalThis.RAW = false;
  const levels = new Set(); let runs = [], run = 1;
  let first = true;
  for (let i = SR / 2; i < SR; i++) { levels.add(x[i].toFixed(6)); if (x[i] === x[i - 1]) run++; else { if (!first) runs.push(run); first = false; run = 1; } }
  const counts = {}; for (const r of runs) counts[r] = (counts[r] || 0) + 1;
  const minRun = Math.min(...runs);
  const lens = Object.keys(counts).map(Number).sort((a, b) => a - b);
  log(`CRUSH, DRIVE 100 % (синус 50 Гц почти 0 dBFS): уровней ${levels.size} (${[...levels].map(Number).sort((a, b) => a - b).join(', ')}); длины ступенек ${lens.slice(0, 4).join(', ')}… (кратны ${lens.reduce((g, v) => { const gcd = (a, b) => (b ? gcd(b, a % b) : a); return gcd(g, v); })})`);
}
// 7. Скачки при смене TYPE и DRIVE на звучащем синусе 220 Гц: вторая разность.
{
  const hi2 = (x) => { let m = 0; for (let i = SR / 4 + 2; i < x.length; i++) m = Math.max(m, Math.abs(x[i] - 2 * x[i - 1] + x[i - 2])); return m; };
  // Без смены — наибольшая 2-я разность самих кривых (острые углы HARD, ступеньки CRUSH): порог для смен.
  const fixed = (types, drives) => Math.max(...types.flatMap((type) => drives.map((drive) => hi2(render(SR, sine(220), () => ({ drive, type }))))));
  const types = hi2(render(SR * 3, sine(220), (b) => ({ drive: 50, type: Math.floor(b / 60) % 5 })));
  const drives = hi2(render(SR * 3, sine(220), (b) => ({ drive: (Math.floor(b / 40) * 37) % 100, type: 1 })));
  const crush = hi2(render(SR * 3, sine(220), (b) => ({ drive: 50, type: Math.floor(b / 60) % 2 ? 5 : 0 })));
  log(`Смена TYPE 0–4 (DRIVE 50 %): наибольшая 2-я разность ${types.toFixed(4)}, без смены (те же типы) до ${fixed([0, 1, 2, 3, 4], [50]).toFixed(4)}`);
  log(`Смена DRIVE (HARD, скачки 0…100 %): ${drives.toFixed(4)}, без смены (HARD, DRIVE 0…100 %) до ${fixed([1], [0, 25, 50, 75, 100]).toFixed(4)}`);
  log(`SOFT ↔ CRUSH: ${crush.toFixed(4)}, без смены (SOFT и CRUSH, DRIVE 50 %) до ${fixed([0, 5], [50]).toFixed(4)}`);
}
// 8. Нагрузка: 10 с шума, 1 и 8 инстансов (SOFT, DRIVE 50 %).
for (const count of [1, 8]) {
  const nodes = Array.from({ length: count }, () => new ctx.Proc());
  const sec = 10;
  const t0 = performance.now();
  for (const nd of nodes) render(SR * sec, () => Math.random() - 0.5, () => ({ drive: 50, lowcut: 80, tone: 50 }), nd);
  log(`Нагрузка: ${count} инстанс(ов) — ${(((performance.now() - t0) / (sec * 1000)) * 100).toFixed(1)} % одного ядра`);
}
