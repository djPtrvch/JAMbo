// Офлайн-проверка компрессора мастера (public/glue-worklet.js) в Node.
// Запуск: node scripts/glue-check.mjs [прежний-glue-worklet.js]
// Проверяет: совпадение с прежним (настройки по умолчанию), RATIO и KNEE, RANGE, HOLD, MIX, LINK, SC HPF, AUDIT,
// телеметрию и нагрузку. Прежний — git show <коммит>:public/glue-worklet.js.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'glue-'));
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
const NEW = await load(new URL('../public/glue-worklet.js', import.meta.url));
const OLD = process.argv[2] ? await load(process.argv[2]) : null;

/** Рендер: input(i) → [l, r]; p — параметры; onBlock(b) — правки по блокам. */
function render(ctx, frames, input, p, onBlock) {
  ctx.msgs = [];
  const node = new ctx.Proc();
  node.port.onmessage({ data: { thr: -12, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false, ...p } });
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
const noise = (a = 0.5) => { seed = 7; return () => [rnd() * a, rnd() * a]; };
const sine = (hz, amp, ampR = amp) => (i) => [amp * Math.sin((2 * Math.PI * hz * i) / SR), ampR * Math.sin((2 * Math.PI * hz * i) / SR)];
const maxDiff = (a, b, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };
const peak = (a, from = 0) => { let m = 0; for (let i = from; i < a.length; i++) m = Math.max(m, Math.abs(a[i])); return m; };
/** GR по пику выхода синуса амплитуды amp (последняя половина), dB. */
const grOf = (y, amp) => -db(peak(y, y.length / 2) / amp);
const log = (s) => console.log(s);
const N = SR * 2;
const dbAmp = (d) => Math.pow(10, d / 20);

// 1. Совпадение с прежним (KNEE 6, RANGE OFF, HOLD 0, MIX 100, LINK 100, SC HPF 90).
if (OLD) {
  for (const p of [{}, { auto: true, makeup: 4 }, { thr: -20, ratio: 10, att: 1, rel: 50 }]) {
    const [a, b] = render(NEW, N, noise(), p);
    const [c, d] = render(OLD, N, noise(), p);
    log(`По умолчанию против прежнего (${JSON.stringify(p)}): наибольшая разница ${db(Math.max(maxDiff(a, c), maxDiff(b, d))).toFixed(1)} dB`);
  }
}
// 2. RATIO при KNEE 0: синус 1 kHz −4 dBFS, THRESHOLD −12.
{
  const row = [1, 2, 4, 10, 20].map((ratio) => { const [y] = render(NEW, N, sine(1000, dbAmp(-4)), { knee: 0, ratio }); return `${ratio}:1 — ${grOf(y, dbAmp(-4)).toFixed(2)} dB`; });
  log(`RATIO, KNEE 0 (синус −4 dBFS, THRESHOLD −12): ${row.join('; ')}`);
  const [y] = render(NEW, N, sine(1000, dbAmp(-12)), { knee: 24, ratio: 4 });
  log(`Синус на пороге (−12), RATIO 4:1, KNEE 24: GR ${grOf(y, dbAmp(-12)).toFixed(2)} dB`);
}
// 3. RANGE 3 dB при THRESHOLD −20.
{
  const [y] = render(NEW, N, sine(1000, dbAmp(-2)), { thr: -20, ratio: 10, range: 3 });
  log(`RANGE 3 dB (THRESHOLD −20, синус −2 dBFS, 10:1): GR ${grOf(y, dbAmp(-2)).toFixed(2)} dB`);
}
// 4. HOLD 200 ms: короткий пик (50 ms) — GR держится; телеметрия — GR по кадрам.
for (const hold of [0, 200]) {
  const burst = (i) => { const on = i >= SR / 2 && i < SR / 2 + SR / 20; const a = on ? 0.9 : 0.05; return [a * Math.sin((2 * Math.PI * 1000 * i) / SR), a * Math.sin((2 * Math.PI * 1000 * i) / SR)]; };
  const [, , m] = render(NEW, SR * 2, burst, { thr: -20, ratio: 4, rel: 100, hold, meter: true });
  const gr = m.map((x) => x[2]);
  const pk = Math.max(...gr);
  const at = gr.indexOf(pk);
  let held = 0; for (let j = at; j < gr.length && gr[j] >= 0.9 * pk; j++) held++;
  log(`HOLD ${hold} ms: пик GR ${pk.toFixed(2)} dB, не ниже 90 % пика ${((held * 256) / SR * 1000).toFixed(0)} ms`);
}
// 5. MIX 0 / 50 %.
{
  const [y0] = render(NEW, N, noise(), { ratio: 10, thr: -30, makeup: 6, mix: 0 });
  let d = 0; { seed = 7; for (let i = 0; i < N; i++) { const v = rnd() * 0.5; rnd(); if (i > SR / 2) d = Math.max(d, Math.abs(y0[i] - v)); } }
  const [y50] = render(NEW, N, sine(1000, 0.5), { ratio: 10, thr: -30, mix: 50 });
  const [y100] = render(NEW, N, sine(1000, 0.5), { ratio: 10, thr: -30, mix: 100 });
  log(`MIX 0 %: выход против входа — ${db(d).toFixed(1)} dB; MIX 50 %: пик ${peak(y50, N / 2).toFixed(3)} (вход 0.5, обработанный ${peak(y100, N / 2).toFixed(3)}; ожидается ${((0.5 + peak(y100, N / 2)) / 2).toFixed(3)})`);
}
// 6. LINK: «бочка» только в L.
for (const link of [100, 50, 0]) {
  const kick = (i) => { const t = i % (SR / 2); const a = Math.exp(-t / 2400) * Math.sin((2 * Math.PI * 60 * t) / SR) * 0.9; return [a + 0.02 * Math.sin((2 * Math.PI * 1000 * i) / SR), 0.02 * Math.sin((2 * Math.PI * 1000 * i) / SR)]; };
  const [L, R] = render(NEW, N, kick, { thr: -24, ratio: 4, link, schpf: 20 });
  const [L0, R0] = render(NEW, N, kick, { thr: -24, ratio: 4, link, schpf: 20, bypass: true });
  // GR как наибольшее снижение огибающей: отношение пиков по окнам 5 ms.
  const gr = (y, x) => { let m = 0; for (let i = SR; i < N; i += 240) { const a = peak(y.subarray(i, i + 240)), b = peak(x.subarray(i, i + 240)); if (b > 1e-4) m = Math.max(m, -db(a / b)); } return m; };
  log(`LINK ${link} %: GR_L ${gr(L, L0).toFixed(2)} dB, GR_R ${gr(R, R0).toFixed(2)} dB`);
}
// 7. SC HPF: синус 60 Hz −6 dBFS при THRESHOLD −12; синус 1 kHz.
{
  const g = (hz, schpf) => { const [y] = render(NEW, N, sine(hz, 0.5), { thr: -12, ratio: 4, schpf }); return grOf(y, 0.5); };
  log(`SC HPF: 60 Hz — GR ${g(60, 20).toFixed(2)} dB (OFF), ${g(60, 90).toFixed(2)} dB (90 Hz); 1 kHz — ${g(1000, 20).toFixed(2)} / ${g(1000, 90).toFixed(2)} dB`);
}
// 8. AUDIT: выход — вход после SC HPF.
{
  const [y] = render(NEW, N, noise(), { audit: true, schpf: 200 });
  // Тот же фильтр отдельно: биквад Баттерворта 200 Hz.
  const w = (2 * Math.PI * 200) / SR, cw = Math.cos(w), al = Math.sin(w) / (2 * Math.SQRT1_2), a0 = 1 + al;
  const b0 = (1 + cw) / 2 / a0, b1 = -(1 + cw) / a0, a1 = (-2 * cw) / a0, a2 = (1 - al) / a0;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0, d = 0; seed = 7;
  for (let i = 0; i < N; i++) { const x = rnd() * 0.5; rnd(); const v = b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = v; if (i > SR / 2) d = Math.max(d, Math.abs(y[i] - v)); }
  log(`AUDIT (SC HPF 200 Hz): выход против входа после SC HPF — ${db(d).toFixed(1)} dB`);
}
// 9. Телеметрия и нагрузка.
{
  const [, , on] = render(NEW, SR, noise(), { meter: true });
  const [, , off] = render(NEW, SR, noise(), {});
  log(`Телеметрия: за 1 с ${on.length} кадров по ${on[0]?.length} значения, без meter — ${off.length}`);
  let t0 = performance.now(); render(NEW, SR * 10, noise(), { link: 50, mix: 60 }); const ms = performance.now() - t0;
  t0 = performance.now(); render(NEW, SR * 10, noise(), {}); const ms100 = performance.now() - t0;
  let old = '';
  if (OLD) { t0 = performance.now(); render(OLD, SR * 10, noise(), {}); old = `, прежний ${((performance.now() - t0) / 100).toFixed(1)} %`; }
  log(`Нагрузка: LINK 50 % и MIX 60 % — ${(ms / 100).toFixed(1)} %, по умолчанию ${(ms100 / 100).toFixed(1)} % одного ядра${old}`);
}
// 10. Без щелчков: резкие смены RATIO, KNEE, RANGE, MIX, LINK, SC HPF, HOLD, AUDIT на звучащем синусе 200 Hz
// (сравнивается наибольшая вторая разность до и после смены).
{
  const d2 = (y, a, b) => { let m = 0; for (let i = a + 2; i < b; i++) m = Math.max(m, Math.abs(y[i] - 2 * y[i - 1] + y[i - 2])); return m; };
  const changes = [
    { ratio: 20 }, { knee: 0 }, { range: 1 }, { mix: 0 }, { link: 0 }, { schpf: 500 }, { hold: 500 }, { audit: true }, { bypass: true },
  ];
  const at = SR, len = SR * 2;
  const row = changes.map((c) => {
    const base = { thr: -30, ratio: 4, knee: 6, range: 40, mix: 100, link: 100, schpf: 90, hold: 0 };
    const [y] = render(NEW, len, sine(200, 0.5, 0.3), base, (b) => (b * BLOCK === at ? { ...base, ...c } : null));
    // Переход (50 ms после смены) против установившегося до и после (у синуса вторая разность ∝ амплитуде).
    const ref = Math.max(d2(y, SR / 2, at), d2(y, at + SR / 2, len));
    return `${Object.keys(c)[0]} ×${(d2(y, at, at + SR / 20) / ref).toFixed(2)}`;
  });
  log(`Смена параметров (вторая разность в переходе / в установившемся): ${row.join(', ')}`);
}
