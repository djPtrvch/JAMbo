// Офлайн-проверка сатуратора мастера (public/saturator-worklet.js) в Node: совпадение с прежним (BIAS 0,
// FOCUS 20, OUTPUT 0, AUTO ON), прозрачность при DRIVE 0, DC при BIAS, FOCUS, AUTO OFF, BYPASS (MIX 0), телеметрия.
// Запуск: node scripts/sat-check.mjs [прежний-saturator-worklet.js]

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sat-'));
let k = 0;
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
const NEW = await load(new URL('../public/saturator-worklet.js', import.meta.url));
const OLD = process.argv[2] ? await load(process.argv[2]) : null;

function render(ctx, frames, input, p, onBlock) {
  ctx.msgs = [];
  const node = new ctx.Proc();
  node.port.onmessage({ data: { drive: 0, type: 0, tone: 0, mix: 100, ...p } });
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const iL = new Float32Array(BLOCK), iR = new Float32Array(BLOCK), oL = new Float32Array(BLOCK), oR = new Float32Array(BLOCK);
  for (let b = 0; b * BLOCK < frames; b++) {
    if (onBlock) { const d = onBlock(b); if (d) node.port.onmessage({ data: d }); }
    for (let s = 0; s < BLOCK; s++) { const [l, r] = input(b * BLOCK + s); iL[s] = l; iR[s] = r; }
    node.process([[iL, iR]], [[oL, oR]]);
    L.set(oL, b * BLOCK); R.set(oR, b * BLOCK);
  }
  return [L, R, ctx.msgs];
}
const db = (x) => 20 * Math.log10(Math.max(1e-12, x));
let seed = 1;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff) * 2 - 1; };
const noise = (a = 0.3) => { seed = 7; return () => [rnd() * a, rnd() * a]; };
const sine = (hz, a) => (i) => { const v = a * Math.sin((2 * Math.PI * hz * i) / SR); return [v, v]; };
const maxDiff = (a, b, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };
const peak = (a, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i])); return m; };
const rms = (a, from = 0) => { let s = 0; for (let i = from; i < a.length; i++) s += a[i] * a[i]; return Math.sqrt(s / (a.length - from)); };
const log = (s) => console.log(s);
const N = SR;
const D = 33;

// 1. Как прежний (BIAS 0, FOCUS 20, OUTPUT 0, AUTO ON).
if (OLD) {
  for (const p of [{ drive: 12 }, { drive: 18, type: 1, tone: 50 }, { drive: 6, type: 2, mix: 60 }]) {
    const [a, b] = render(NEW, N, noise(), { ...p, focus: 20, bias: 0, out: 0, auto: true });
    const [c, d] = render(OLD, N, noise(), p);
    log(`Против прежнего (${JSON.stringify(p)}): наибольшая разница ${db(Math.max(maxDiff(a, c), maxDiff(b, d))).toFixed(1)} dB`);
  }
}
// 2. DRIVE 0 — выход = вход (с задержкой 33) при любых BIAS, FOCUS, OUTPUT.
{
  const row = [{ bias: 0.5 }, { bias: -1, focus: 500 }, { focus: 2000, out: 12 }, { bias: 0.3, focus: 120, out: -12, auto: false }].map((p) => {
    const [y] = render(NEW, N, noise(), { drive: 0, ...p });
    seed = 7; const xs = []; for (let i = 0; i < N; i++) { xs.push(rnd() * 0.3); rnd(); }
    let m = 0; for (let i = D; i < N; i++) m = Math.max(m, Math.abs(y[i] - xs[i - D]));
    return `${JSON.stringify(p)} ${db(m).toFixed(0)} dB`;
  });
  log(`DRIVE 0 против входа: ${row.join('; ')}`);
}
// 3. BIAS ≠ 0 — постоянной составляющей на выходе нет (синус 1 kHz −12 dBFS, DRIVE +12, последние 0,5 с).
{
  const row = [0, 1, 2].map((type) => [-0.8, 0.5, 1].map((bias) => {
    const [y] = render(NEW, SR * 2, sine(1000, 0.25), { drive: 12, type, bias });
    let m = 0; for (let i = SR * 1.5; i < SR * 2; i++) m += y[i]; m /= SR / 2;
    return `${db(Math.abs(m)).toFixed(0)}`;
  }).join('/'));
  log(`BIAS −0.8 / 0.5 / 1 — DC на выходе (dBFS) TAPE ${row[0]}, TUBE ${row[1]}, EDGE ${row[2]}`);
  // Чётные гармоники появляются у TAPE с BIAS.
  const dft = (y, f) => { let re = 0, im = 0; for (let i = SR; i < 2 * SR; i++) { re += y[i] * Math.cos((2 * Math.PI * f * i) / SR); im += y[i] * Math.sin((2 * Math.PI * f * i) / SR); } return Math.hypot(re, im); };
  const [a] = render(NEW, SR * 2, sine(1000, 0.25), { drive: 12, type: 0 });
  const [b] = render(NEW, SR * 2, sine(1000, 0.25), { drive: 12, type: 0, bias: 0.5 });
  log(`TAPE, DRIVE +12: 2-я гармоника ${db(dft(a, 2000) / dft(a, 1000)).toFixed(0)} dB без BIAS, ${db(dft(b, 2000) / dft(b, 1000)).toFixed(1)} dB с BIAS 0.5`);
}
// 4. FOCUS 200 Hz: синус 60 Hz проходит почти чисто, 2 kHz насыщается.
{
  const dft = (y, f) => { let re = 0, im = 0; for (let i = SR; i < 2 * SR; i++) { re += y[i] * Math.cos((2 * Math.PI * f * i) / SR); im += y[i] * Math.sin((2 * Math.PI * f * i) / SR); } return Math.hypot(re, im); };
  const h3 = (f, focus) => { const [y] = render(NEW, SR * 2, sine(f, 0.5), { drive: 18, focus }); return db(dft(y, 3 * f) / dft(y, f)).toFixed(1); };
  log(`FOCUS: 3-я гармоника синуса 60 Hz −6 dBFS, DRIVE +18 — ${h3(60, 20)} dB (OFF) / ${h3(60, 500)} dB (500 Hz); 2 kHz — ${h3(2000, 20)} / ${h3(2000, 500)} dB`);
  // Разбиение не меняет фазу: почти линейная кривая (DRIVE +1, −40 dBFS) — FOCUS 300 Hz против OFF на 300 Hz.
  const [a1] = render(NEW, SR * 2, sine(300, 0.01), { drive: 1, focus: 300 });
  const [a0] = render(NEW, SR * 2, sine(300, 0.01), { drive: 1 });
  log(`FOCUS 300 Hz против OFF (синус 300 Hz −40 dBFS, DRIVE +1): разница ${db(maxDiff(a1, a0, SR) / 0.01).toFixed(1)} dB к сигналу`);
}
// 5. AUTO OFF — громкость растёт с DRIVE; ON — постоянна.
{
  const lv = (drive, auto) => { const [y] = render(NEW, N, sine(1000, 0.25), { drive, auto }); return db(rms(y, N / 2)).toFixed(1); };
  log(`RMS синуса −12 dBFS, DRIVE 0/6/12/24: AUTO ON ${[0, 6, 12, 24].map((d) => lv(d, true)).join(' / ')}; OFF ${[0, 6, 12, 24].map((d) => lv(d, false)).join(' / ')} dBFS`);
  const o = (out) => { const [y] = render(NEW, N, sine(1000, 0.25), { drive: 12, out }); return db(rms(y, N / 2)); };
  log(`OUTPUT +6 / −6 при DRIVE +12: ${(o(6) - o(0)).toFixed(2)} / ${(o(-6) - o(0)).toFixed(2)} dB`);
}
// 6. BYPASS (MIX 0 за 20 ms): скачков нет, задержка та же.
{
  const d2 = (y, a, b) => { let m = 0; for (let i = a + 2; i < b; i++) m = Math.max(m, Math.abs(y[i] - 2 * y[i - 1] + y[i - 2])); return m; };
  const at = 188 * BLOCK; // граница блока около 0,5 с
  const [y] = render(NEW, SR, sine(200, 0.5), { drive: 18, type: 2 }, (b) => (b * BLOCK === at ? { drive: 18, type: 2, mix: 0 } : null));
  const ref = Math.max(d2(y, SR / 4, at), d2(y, at + SR / 4, SR));
  let m = 0; for (let i = at + SR / 4; i < SR; i++) m = Math.max(m, Math.abs(y[i] - 0.5 * Math.sin((2 * Math.PI * 200 * (i - D)) / SR)));
  log(`BYPASS: вторая разность в переходе / в установившемся ×${(d2(y, at, at + SR / 20) / ref).toFixed(2)}; после — выход = вход с задержкой ${D} (${db(m).toFixed(0)} dB)`);
  // Смены BIAS, FOCUS, OUTPUT, AUTO на звучащем синусе.
  const row = [{ bias: 0.8 }, { focus: 1000 }, { out: 12 }, { auto: false }].map((c) => {
    const base = { drive: 12, type: 0 };
    const [z] = render(NEW, SR, sine(200, 0.25), base, (b) => (b * BLOCK === at ? { ...base, ...c } : null));
    const r = Math.max(d2(z, SR / 4, at), d2(z, at + SR / 4, SR));
    return `${Object.keys(c)[0]} ×${(d2(z, at, at + SR / 20) / r).toFixed(2)}`;
  });
  log(`Смены (вторая разность в переходе / в установившемся): ${row.join(', ')}`);
}
// 7. Телеметрия и нагрузка.
{
  const [, , on] = render(NEW, SR, noise(), { drive: 6, meter: true });
  const [, , off] = render(NEW, SR, noise(), { drive: 6 });
  log(`Телеметрия: за 1 с ${on.length} кадров по ${on[0]?.length} значений, без meter — ${off.length}`);
  let t0 = performance.now(); render(NEW, SR * 10, noise(), { drive: 12, bias: 0.3, focus: 200, meter: true }); const a = performance.now() - t0;
  t0 = performance.now(); render(NEW, SR * 10, noise(), { drive: 12 }); const b = performance.now() - t0;
  let old = '';
  if (OLD) { t0 = performance.now(); render(OLD, SR * 10, noise(), { drive: 12 }); old = `, прежний ${((performance.now() - t0) / 100).toFixed(1)} %`; }
  log(`Нагрузка: ${(b / 100).toFixed(1)} % ядра (DRIVE +12), ${(a / 100).toFixed(1)} % (BIAS, FOCUS, телеметрия)${old}`);
}
