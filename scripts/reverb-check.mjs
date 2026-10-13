// Офлайн-проверка реверба (public/reverb-worklet.js) в Node: рендер и замеры.
// Запуск: node scripts/reverb-check.mjs
// Проверяет: время затухания (T60 по Шрёдеру) против DECAY; затухание высоких по TONE; устойчивость
// при DECAY 20 с и SIZE 100 % (нет разноса и NaN); скачки при резкой смене SIZE и DECAY на хвосте;
// LOW CUT (НЧ хвоста падают, середина почти не меняется); уровень хвоста; нагрузку (1 и 8 инстансов).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const ctx = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage(m) { ctx.last = m; }, onmessage: null }; } },
  registerProcessor(name, cls) { ctx.Proc = cls; },
});
const src = fs.readFileSync(new URL('../public/reverb-worklet.js', import.meta.url), 'utf8');
const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'rv-')), 'worklet.mjs');
fs.writeFileSync(tmp, src);
await import(pathToFileURL(tmp).href);

const DEF = { size: 50, decay: 2, tone: 0, lowcut: 20, predelay: 0 };

/** Рендер: input(i) → [l, r]; params(block) → объект параметров. Возвращает [L, R]. */
function render(frames, input, params = () => DEF, node = new ctx.Proc()) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const iL = new Float32Array(BLOCK), iR = new Float32Array(BLOCK);
  const oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  for (let b = 0; b * BLOCK < frames; b++) {
    for (let s = 0; s < BLOCK; s++) { const [l, r] = input(b * BLOCK + s); iL[s] = l; iR[s] = r; }
    const p = params(b);
    const pp = Object.fromEntries(Object.entries({ ...DEF, ...p }).map(([k, v]) => [k, new Float32Array([v])]));
    node.process([[iL, iR]], [[oL, oR]], pp);
    const n = Math.min(BLOCK, frames - b * BLOCK);
    L.set(oL.subarray(0, n), b * BLOCK); R.set(oR.subarray(0, n), b * BLOCK);
  }
  return [L, R];
}

const impulse = (i) => (i === 0 ? [1, 1] : [0, 0]);
let seed = 1;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff * 2 - 1; };
const noise = (until) => (i) => (i < until ? [rnd() * 0.5, rnd() * 0.5] : [0, 0]);
const db = (x) => 20 * Math.log10(Math.max(1e-12, x));
const rms = (a, from = 0, to = a.length) => { let s = 0; for (let i = from; i < to; i++) s += a[i] * a[i]; return Math.sqrt(s / Math.max(1, to - from)); };

/** T60 по обратному интегралу Шрёдера: наклон от −5 до −25 dB, ×3. */
function t60(x) {
  const e = new Float64Array(x.length);
  let acc = 0;
  for (let i = x.length - 1; i >= 0; i--) { acc += x[i] * x[i]; e[i] = acc; }
  const at = (dB) => { const lim = e[0] * Math.pow(10, dB / 10); for (let i = 0; i < e.length; i++) if (e[i] <= lim) return i; return e.length; };
  return ((at(-25) - at(-5)) / SR) * 3;
}
/** Простой полосовой: разность первого порядка (ВЧ) или однополюсный НЧ. */
const hi = (x) => { const y = new Float32Array(x.length); let p = 0, q = 0; for (let i = 0; i < x.length; i++) { const d = x[i] - p; p = x[i]; y[i] = d - q; q = d; } return y; };
const lo = (x, hz) => { const a = Math.exp((-2 * Math.PI * hz) / SR); const y = new Float32Array(x.length); let z = 0; for (let i = 0; i < x.length; i++) { z = x[i] + a * (z - x[i]); y[i] = z; } return y; };

const out = [];
const log = (s) => { out.push(s); console.log(s); };

// 1. T60 против DECAY.
for (const decay of [0.5, 2, 6]) {
  for (const size of [0, 50, 100]) {
    const [L] = render(Math.round(SR * Math.min(20, decay * 2.5 + 1)), impulse, () => ({ decay, size, tone: 100 }));
    log(`T60 DECAY ${decay} s, SIZE ${size}% (TONE +100): ${t60(L).toFixed(2)} s`);
  }
}
// 2. TONE: время затухания высоких (после двойной разности) к DECAY 2 с.
for (const tone of [-100, 0, 100]) {
  const [L] = render(SR * 6, impulse, () => ({ decay: 2, tone }));
  log(`TONE ${tone}: T60 ВЧ ${t60(hi(L)).toFixed(2)} s, общий ${t60(L).toFixed(2)} s`);
}
// 3. Устойчивость: DECAY 20, SIZE 100, шум 1 с, затем 40 с тишины.
{
  const [L, R] = render(SR * 41, noise(SR), () => ({ decay: 20, size: 100, tone: 100 }));
  let nan = false, peak = 0, peakLate = 0;
  for (let i = 0; i < L.length; i++) {
    if (!Number.isFinite(L[i]) || !Number.isFinite(R[i])) nan = true;
    const a = Math.max(Math.abs(L[i]), Math.abs(R[i]));
    if (a > peak) peak = a;
    if (i > SR * 30 && a > peakLate) peakLate = a;
  }
  const r1 = rms(L, SR * 2, SR * 3), r2 = rms(L, SR * 22, SR * 23);
  log(`DECAY 20 s, SIZE 100%: NaN ${nan}, пик ${db(peak).toFixed(1)} dBFS, через 20 с хвост ${(db(r2) - db(r1)).toFixed(1)} dB (ожидается около −60), пик после 30 с ${db(peakLate).toFixed(1)} dBFS`);
}
// 4. Скачки: шум без остановки, на 2-й секунде резко SIZE 0 → 100 или DECAY 0.5 → 8; пик ВЧ
// (двойная разность) к локальному RMS после смены и до неё.
{
  const at = Math.round((2 * SR) / BLOCK);
  const jump = (name, p) => {
    const [L] = render(SR * 3, noise(SR * 3), p);
    const d = hi(L);
    // Выброс: |ВЧ| к RMS ВЧ в окне ±5 мс вокруг (щелчок — одиночный выброс; посветление хвоста — нет).
    const spike = (a, b) => {
      let m = 0;
      for (let i = Math.round(a * SR); i < Math.round(b * SR); i += 8) m = Math.max(m, Math.abs(d[i]) / (rms(d, i - 240, i + 240) + 1e-12));
      return m;
    };
    log(`Смена ${name} на хвосте: выброс ВЧ / локальный RMS — после ${spike(2, 2.3).toFixed(1)}, до ${spike(1.6, 2).toFixed(1)} (щелчок — заметно больше)`);
  };
  jump('SIZE 0 → 100 %', (b) => ({ size: b < at ? 0 : 100 }));
  jump('SIZE 100 → 0 %', (b) => ({ size: b < at ? 100 : 0 }));
  jump('DECAY 0.5 → 8 с', (b) => ({ decay: b < at ? 0.5 : 8 }));
  jump('DECAY 8 → 0.5 с', (b) => ({ decay: b < at ? 8 : 0.5 }));
  jump('TONE −100 → +100', (b) => ({ tone: b < at ? -100 : 100 }));
}
// 5. LOW CUT: синус 60 Hz и 1 kHz на входе — уровень хвоста при LOW CUT 20 и 300 Hz.
{
  const sine = (hz) => (i) => { const v = 0.3 * Math.sin((2 * Math.PI * hz * i) / SR); return [v, v]; };
  const lvl = (hz, lowcut) => rms(render(SR * 2, sine(hz), () => ({ lowcut }))[0], SR, SR * 2);
  log(`LOW CUT 20 → 300 Hz: 60 Hz ${(db(lvl(60, 300)) - db(lvl(60, 20))).toFixed(1)} dB, 1 kHz ${(db(lvl(1000, 300)) - db(lvl(1000, 20))).toFixed(1)} dB; LOW CUT 120 Hz: 60 Hz ${(db(lvl(60, 120)) - db(lvl(60, 20))).toFixed(1)} dB`);
}
// 6. Уровень хвоста: шум на входе (RMS), выход при DECAY 2 с.
{
  const [L, R] = render(SR * 3, noise(SR * 3));
  log(`Уровень: вход ${db(0.5 / Math.sqrt(3)).toFixed(1)} dBFS RMS, выход L ${db(rms(L, SR, SR * 3)).toFixed(1)} / R ${db(rms(R, SR, SR * 3)).toFixed(1)} dBFS RMS; корреляция L/R ${(() => { let s = 0, a = 0, b = 0; for (let i = SR; i < SR * 3; i++) { s += L[i] * R[i]; a += L[i] * L[i]; b += R[i] * R[i]; } return (s / Math.sqrt(a * b)).toFixed(2); })()}`);
}
// 7. Нагрузка: 10 с шума, 1 и 8 инстансов.
for (const count of [1, 8]) {
  const nodes = Array.from({ length: count }, () => new ctx.Proc());
  const sec = 10;
  const t0 = performance.now();
  for (const nd of nodes) render(SR * sec, noise(SR * sec), () => DEF, nd);
  const ms = performance.now() - t0;
  log(`Нагрузка: ${count} инстанс(ов) — ${((ms / (sec * 1000)) * 100).toFixed(1)} % одного ядра`);
}
