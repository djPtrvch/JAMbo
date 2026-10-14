// Офлайн-проверка клиппера мастера (public/clipper-worklet.js) в Node: совпадение с прежним (MIX 100),
// статическая характеристика против формулы окна (TRANSFER), MIX, UNITY, AUDIT, BASS, снимки WAVE, телеметрия.
// Запуск: node scripts/clipper-check.mjs [прежний-clipper-worklet.js] (прежний — git show <коммит>:public/clipper-worklet.js).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clip-'));
let k = 0;
// Общий оверсэмплер (в приложении грузится раньше и кладёт себя в globalThis).
globalThis.sampleRate = SR;
await import(pathToFileURL(path.resolve('public/oversampler.js')).href);
async function load(file) {
  const ctx = {};
  Object.assign(globalThis, {
    sampleRate: SR, currentFrame: 0,
    AudioWorkletProcessor: class { constructor() { this.port = { postMessage(m) { ctx.msgs?.push(m); }, onmessage: null }; } },
    registerProcessor(name, cls) { ctx.Proc = cls; },
  });
  const f = path.join(dir, `w${k++}.mjs`);
  fs.writeFileSync(f, fs.readFileSync(file, 'utf8'));
  await import(pathToFileURL(f).href);
  return ctx;
}
const NEW = await load(new URL('../public/clipper-worklet.js', import.meta.url));
const OLD = process.argv[2] ? await load(process.argv[2]) : null;

function render(ctx, frames, input, p) {
  ctx.msgs = [];
  const node = new ctx.Proc();
  node.port.onmessage({ data: { drive: 0, ceiling: -1, softness: 30, bass: 0, bypass: false, ...p } });
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const iL = new Float32Array(BLOCK), iR = new Float32Array(BLOCK), oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  for (let b = 0; b * BLOCK < frames; b++) {
    for (let s = 0; s < BLOCK; s++) { const [l, r] = input(b * BLOCK + s); iL[s] = l; iR[s] = r; }
    node.process([[iL, iR]], [[oL, oR]]);
    L.set(oL, b * BLOCK); R.set(oR, b * BLOCK);
  }
  return [L, R, ctx.msgs];
}
const db = (x) => 20 * Math.log10(Math.max(1e-12, x));
const amp = (d) => Math.pow(10, d / 20);
let seed = 1;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff) * 2 - 1; };
const noise = (a = 0.5) => { seed = 7; return () => [rnd() * a, rnd() * a]; };
const sine = (hz, a, aR = a) => (i) => [a * Math.sin((2 * Math.PI * hz * i) / SR), aR * Math.sin((2 * Math.PI * hz * i) / SR)];
const maxDiff = (a, b, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };
const peak = (a, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i])); return m; };
const log = (s) => console.log(s);
const N = SR;
const D = 32; // задержка клиппера

/** Формула окна (TRANSFER): выход в dB при уровне источника x dB. */
function curve(x, input, ceiling, soft) {
  const kk = 1 - 0.6 * soft / 100;
  const u = amp(x + input - ceiling);
  let y;
  if (u <= kk) y = u; else { const s = 1 - kk; y = s > 1e-9 ? kk + s * Math.tanh((u - kk) / s) : 1; }
  return ceiling + db(y);
}

// 1. MIX 100 — как прежний.
if (OLD) {
  for (const p of [{ drive: 6 }, { drive: 12, softness: 0, bass: 120 }, { drive: 3, ceiling: -6, softness: 100 }]) {
    const [a, b] = render(NEW, N, noise(), p);
    const [c, d] = render(OLD, N, noise(), p);
    log(`MIX 100 % против прежнего (${JSON.stringify(p)}): наибольшая разница ${db(Math.max(maxDiff(a, c), maxDiff(b, d))).toFixed(1)} dB`);
  }
}
// 2. Статическая характеристика (синус 200 Hz, BASS OFF) против формулы окна.
{
  const pts = [[0, 0, -6], [6, 0, -6], [12, 30, -16], [6, 100, -12], [0, 30, -4]];
  const row = pts.map(([input, soft, x]) => {
    const [y] = render(NEW, N, sine(200, amp(x)), { drive: input, ceiling: -3, softness: soft });
    const meas = db(peak(y, N / 2));
    const want = curve(x, input, -3, soft);
    return `INPUT ${input} SOFT ${soft} x ${x}: ${meas.toFixed(2)} / формула ${want.toFixed(2)} (Δ ${(meas - want).toFixed(2)})`;
  });
  log(`Характеристика (CEILING −3): ${row.join('; ')}`);
}
// 3. Синус 1 kHz −3 dBFS, INPUT +6, CEILING −3, SOFTNESS 0.
{
  const [y] = render(NEW, N, sine(1000, amp(-3)), { drive: 6, ceiling: -3, softness: 0 });
  log(`Синус 1 kHz −3 dBFS, INPUT +6, CEILING −3, SOFTNESS 0: пик выхода ${db(peak(y, N / 2)).toFixed(2)} dBFS`);
}
// 4. MIX 0 / 50 %.
{
  const [y0] = render(NEW, N, noise(), { drive: 12, mix: 0 });
  let d = 0; seed = 7; const xs = []; for (let i = 0; i < N; i++) { xs.push(rnd() * 0.5); rnd(); }
  for (let i = SR / 2; i < N; i++) d = Math.max(d, Math.abs(y0[i] - xs[i - D]));
  const [y50] = render(NEW, N, sine(1000, 0.5), { drive: 12, ceiling: -6, softness: 0, mix: 50 });
  const [y100] = render(NEW, N, sine(1000, 0.5), { drive: 12, ceiling: -6, softness: 0 });
  // Посередине: y50 = (вход задержанный + y100) / 2.
  let m = 0; for (let i = N / 2; i < N; i++) m = Math.max(m, Math.abs(y50[i] - (0.5 * Math.sin((2 * Math.PI * 1000 * (i - D)) / SR) + y100[i]) / 2));
  log(`MIX 0 %: выход против входа с задержкой ${D} — ${db(d).toFixed(1)} dB; MIX 50 %: против (вход + клип)/2 — ${db(m).toFixed(1)} dB`);
}
// 5. UNITY при INPUT +12: уровень на 12 dB ниже, GR тот же.
{
  const [a, , ma] = render(NEW, N, noise(0.3), { drive: 12, unity: true, meter: true });
  const [b, , mb] = render(NEW, N, noise(0.3), { drive: 12, meter: true });
  const rm = (x) => { let s = 0; for (let i = N / 2; i < N; i++) s += x[i] * x[i]; return Math.sqrt(s / (N / 2)); };
  const gr = (m) => Math.max(...m.filter(Array.isArray).map((f) => f[1]));
  log(`UNITY, INPUT +12: выход ${(db(rm(a)) - db(rm(b))).toFixed(2)} dB к обычному; GR ${gr(ma).toFixed(2)} / ${gr(mb).toFixed(2)} dB`);
}
// 6. AUDIT: выход клиппера + AUDIT = вход после INPUT с задержкой.
{
  const [a] = render(NEW, N, noise(), { drive: 6, audit: true });
  const [b] = render(NEW, N, noise(), { drive: 6 });
  let m = 0; seed = 7; const xs = []; for (let i = 0; i < N; i++) { xs.push(rnd() * 0.5); rnd(); }
  for (let i = SR / 2; i < N; i++) m = Math.max(m, Math.abs(a[i] + b[i] - xs[i - D] * amp(6)));
  log(`AUDIT: выход + AUDIT против входа после INPUT с задержкой — ${db(m).toFixed(1)} dB`);
}
// 7. BASS 120 Hz: синус 50 Hz не срезается.
{
  const [y] = render(NEW, SR * 2, sine(50, 0.9), { drive: 6, ceiling: -1, softness: 0, bass: 120 });
  // Гармоники: DFT на 100, 150, 200 Hz к 50 Hz по последней секунде.
  const dft = (f) => { let re = 0, im = 0; for (let i = SR; i < 2 * SR; i++) { re += y[i] * Math.cos((2 * Math.PI * f * i) / SR); im += y[i] * Math.sin((2 * Math.PI * f * i) / SR); } return Math.hypot(re, im); };
  const f0 = dft(50);
  log(`BASS 120 Hz, синус 50 Hz, INPUT +6: гармоники 2–4 — ${[100, 150, 200].map((f) => db(dft(f) / f0).toFixed(1)).join(' / ')} dB`);
}
// 8. Снимки WAVE: выравнивание входа и выхода (MIX 0 — выход = вход), центр на пике, поток.
{
  const burst = (i) => { const a = (i % 9600) < 400 ? 0.9 : 0.1; const v = a * Math.sin((2 * Math.PI * 300 * i) / SR); return [v, 0.5 * v]; };
  const [, , m] = render(NEW, SR, burst, { drive: 0, mix: 0, wave: true });
  const w = m.filter((x) => x && x.wave);
  // Сдвиг по кросс-корреляции входа и выхода в последнем снимке (MIX 0 — должен быть 0).
  const s = w[w.length - 1];
  let best = 0, bestLag = 0;
  for (let lag = -8; lag <= 8; lag++) { let c = 0; for (let j = 16; j < 1008; j++) c += s.inp[j] * s.out[j + lag]; if (c > best) { best = c; bestLag = lag; } }
  let pk = 0, at = 0; for (let j = 0; j < 1024; j++) if (Math.abs(s.inp[j]) > pk) { pk = Math.abs(s.inp[j]); at = j; }
  const kb = (w.length * (1024 * 4 * 2)) / 1024;
  log(`WAVE: ${w.length} снимков за 1 с (${kb.toFixed(0)} КБ/с), канал ${s.ch ? 'R' : 'L'}, сдвиг вход/выход ${bestLag} отсчётов, пик на ${at} из 1024`);
}
// 9. Телеметрия и нагрузка.
{
  const [, , on] = render(NEW, SR, noise(), { meter: true });
  const [, , off] = render(NEW, SR, noise(), {});
  log(`Телеметрия: за 1 с ${on.filter(Array.isArray).length} кадров, без meter — ${off.length}`);
  let t0 = performance.now(); render(NEW, SR * 10, noise(), { drive: 6, mix: 60, wave: true, meter: true }); const a = performance.now() - t0;
  let old = '';
  if (OLD) { t0 = performance.now(); render(OLD, SR * 10, noise(), { drive: 6 }); old = `, прежний ${((performance.now() - t0) / 100).toFixed(1)} %`; }
  log(`Нагрузка: ${(a / 100).toFixed(1)} % одного ядра (MIX 60 %, WAVE и телеметрия)${old}`);
}
