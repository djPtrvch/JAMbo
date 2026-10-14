// Проверка высоты Plaits (офлайн в Node, plaits.wasm напрямую): node scripts/plaits-pitch-check.mjs
// Plaits настроен на 47872,34 Гц (kCorrectedSampleRate), worklet сдвигает ноту на 12·log2(47872,34 / sampleRate).
// A4 (нота 69) — синус движка FM (Plaits 2, mod index 0) — должна звучать 440 Гц ±1 цент при 44100 и 48000.
import { readFileSync } from 'node:fs';

const PLAITS_SR = 47872.34; // как в public/plaits-worklet.js
const BLOCK = 24;
const shift = (sr) => 12 * Math.log2(PLAITS_SR / sr);

const inst = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(new URL('../public/plaits.wasm', import.meta.url))), {});
const w = inst.exports;
if (w._initialize) w._initialize();
w.init();

/** Частота (циклов на отсчёт) по переходам через ноль вверх с линейной интерполяцией. */
function cyclesPerSample(x) {
  const ups = [];
  for (let i = 1; i < x.length; i++) if (x[i - 1] < 0 && x[i] >= 0) ups.push(i - 1 + x[i - 1] / (x[i - 1] - x[i]));
  return (ups.length - 1) / (ups[ups.length - 1] - ups[0]);
}

let ok = true;
for (const sr of [44100, 48000]) {
  const s = shift(sr);
  // FM (2): harmonics — ratio, timbre — mod index 0 → чистый синус.
  w.set(0, 2, 69 + s, 0.5, 0, 0, 0.8, 0);
  w.trigger(0);
  const n = 48000 * 2;
  const out = new Float32Array(n);
  for (let pos = 0; pos < n; pos += BLOCK) {
    const ptr = w.render(0, BLOCK);
    out.set(new Float32Array(w.memory.buffer, ptr, BLOCK), pos);
  }
  const f = cyclesPerSample(out.subarray(4800)) * sr; // отсчёты звучат с частотой контекста sr
  const cents = 1200 * Math.log2(f / 440);
  const old = 12 * Math.log2(48000 / sr);
  console.log(`sampleRate ${sr}: сдвиг ${s.toFixed(4)} полутона (прежний ${old.toFixed(4)}), A4 = ${f.toFixed(3)} Гц, ${cents >= 0 ? '+' : ''}${cents.toFixed(2)} цента`);
  if (Math.abs(cents) > 1) ok = false;
}
console.log(ok ? 'OK' : 'FAIL');
process.exit(ok ? 0 : 1);
