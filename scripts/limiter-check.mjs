// Офлайн-проверка лимитера (public/limiter-worklet.js) в Node: LINK, UNITY, AUDIT, совпадение с прежним (LINK 100 %).
// Запуск: node scripts/limiter-check.mjs [прежний-limiter-worklet.js]
// Без второго файла сравнение с прежним пропускается (прежний — git show <коммит>:public/limiter-worklet.js).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lim-'));
let k = 0;
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
const NEW = await load(new URL('../public/limiter-worklet.js', import.meta.url));
const OLD = process.argv[2] ? await load(process.argv[2]) : null;

/** Рендер: input(i) → [l, r]; p — параметры (сообщение). Возвращает [L, R, msgs]. */
function render(ctx, frames, input, p) {
  ctx.msgs = [];
  const node = new ctx.Proc();
  node.port.onmessage({ data: { gain: 0, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false, ...p } });
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
let seed = 1;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff) * 2 - 1; };
const noise = () => { seed = 7; return (i) => [rnd() * 0.5, rnd() * 0.5]; };
const maxDiff = (a, b) => { let m = 0; for (let i = 0; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };
const peak = (a, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i])); return m; };
const rms = (a, from = 0) => { let s = 0; for (let i = from; i < a.length; i++) s += a[i] * a[i]; return Math.sqrt(s / (a.length - from)); };
const log = (s) => console.log(s);
const N = SR * 2;

// 1. LINK 100 % — как прежний лимитер.
if (OLD) {
  for (const p of [{ gain: 12 }, { gain: 6, auto: true }, { gain: 18, lookahead: 1 }]) {
    const [a, b] = render(NEW, N, noise(), p);
    const [c, d] = render(OLD, N, noise(), p);
    log(`LINK 100 % против прежнего (${JSON.stringify(p)}): наибольшая разница ${db(Math.max(maxDiff(a, c), maxDiff(b, d))).toFixed(1)} dB`);
  }
}
// 2. LINK 0 / 50 %: пики только в L (синус 1 кГц, 0 dBFS, GAIN +6), R — тихий синус −20 dBFS.
for (const link of [100, 50, 0]) {
  const sine = (i) => [Math.sin((2 * Math.PI * 1000 * i) / SR), 0.1 * Math.sin((2 * Math.PI * 300 * i) / SR)];
  const [L, R] = render(NEW, N, sine, { gain: 6, link });
  const grL = db(peak(L, SR) / (2)), grR = db(rms(R, SR) / (0.1 * 2 / Math.SQRT2));
  log(`LINK ${link} %: GR_L ${(-grL).toFixed(2)} dB, GR_R ${(-grR).toFixed(2)} dB`);
}
// 3. UNITY при GAIN +12: выход на 12 dB ниже, GR прежнее.
{
  const [a, , ma] = render(NEW, N, noise(), { gain: 12, meter: true });
  const [b, , mb] = render(NEW, N, noise(), { gain: 12, unity: true, meter: true });
  const gr = (m) => Math.max(...m.slice(20).map((x) => x[1]));
  log(`UNITY, GAIN +12: выход ${(db(rms(b, SR)) - db(rms(a, SR))).toFixed(2)} dB к обычному; GR ${gr(ma).toFixed(2)} / ${gr(mb).toFixed(2)} dB`);
}
// 4. AUDIT: выход + AUDIT = задержанный вход после GAIN.
{
  const [a] = render(NEW, N, noise(), { gain: 12 });
  const [u] = render(NEW, N, noise(), { gain: 12, audit: true });
  // Задержанный вход: тот же рендер с CEILING 0 и без лимитирования не годится — восстановим через сумму.
  const [dry] = render(NEW, N, noise(), { gain: 12, ceiling: 40 }); // потолок выше пика — лимитер не работает, выход = задержанный вход
  const s = new Float32Array(N); for (let i = 0; i < N; i++) s[i] = a[i] + u[i];
  log(`AUDIT: выход + AUDIT против задержанного входа — наибольшая разница ${db(maxDiff(s.subarray(SR), dry.subarray(SR))).toFixed(1)} dB (вход ${db(peak(dry, SR)).toFixed(1)} dBFS)`);
}
// 5. Телеметрия: кадр раз в 256 отсчётов, только при meter.
{
  const [, , on] = render(NEW, SR, noise(), { gain: 12, meter: true });
  const [, , off] = render(NEW, SR, noise(), { gain: 12 });
  log(`Телеметрия: за 1 с ${on.length} кадров (ожидается ${Math.floor(SR / 256)}), без meter — ${off.length}`);
}
// 6. Нагрузка.
{
  const t0 = performance.now(); render(NEW, SR * 10, noise(), { gain: 12, link: 50 }); const ms = performance.now() - t0;
  let old = '';
  if (OLD) { const t1 = performance.now(); render(OLD, SR * 10, noise(), { gain: 12 }); old = `, прежний ${((performance.now() - t1) / 100).toFixed(1)} %`; }
  log(`Нагрузка: ${(ms / 100).toFixed(1)} % одного ядра${old}`);
}
