// Проверка SPEECH без режима Words (офлайн в Node, plaits.wasm напрямую — как plaits-worklet.js).
//   node scripts/speech-check.mjs [прежний plaits.wasm]
// 1) Прогон ручки 1.1 SPEECH 0…100 % через 1 %: harmonics — точка пункта (как harmPoints в params.ts), без сбоев,
//    уровень каждого пункта не ниже −60 dBFS, harmonics не выше 1/3 (ветка слов group > 2 недостижима).
// 2) С прежним wasm: 15 других движков и три пункта SPEECH звучат бит-в-бит как раньше (одна нота каждого).
import { readFileSync } from 'node:fs';

const BLOCK = 24;
const SR = 48000;
// Как SYNTH_ENGINES[7].harmPoints и options в src/params.ts.
const HARM_POINTS = [0, 1 / 6, 1 / 3];
const NAMES = ['Formant', 'Phoneme', 'LPC'];
const stepIndex = (n, steps) => Math.min(steps - 1, Math.max(0, Math.floor(n * steps)));

function load(path) {
  const inst = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(path)), {});
  const w = inst.exports;
  if (w._initialize) w._initialize();
  w.init();
  return w;
}

/** Нота engine длиной sec: триггер в начале (гейт — один блок, как в worklet). */
function render(w, engine, { note = 60, h = 0.5, t = 0.5, m = 0.5, aux = 0, sec = 1, slot = 0 } = {}) {
  w.set(slot, engine, note, h, t, m, 0.8, aux);
  w.trigger(slot);
  const out = new Float32Array(Math.round(sec * SR));
  for (let pos = 0; pos < out.length; pos += BLOCK) {
    const n = Math.min(BLOCK, out.length - pos);
    const ptr = w.render(slot, n);
    out.set(new Float32Array(w.memory.buffer, ptr, n), pos);
    w.release(slot);
  }
  return out;
}

const peakDb = (x) => { let p = 0; for (const v of x) { if (!Number.isFinite(v)) return NaN; p = Math.max(p, Math.abs(v)); } return 20 * Math.log10(Math.max(p, 1e-12)); };
const maxDiff = (a, b) => { let d = 0; for (let i = 0; i < a.length; i++) d = Math.max(d, Math.abs(a[i] - b[i])); return d; };

const cur = load(new URL('../public/plaits.wasm', import.meta.url));
let ok = true;

// 1) Прогон ручки.
const perPoint = [Infinity, Infinity, Infinity];
let maxH = 0;
for (let pct = 0; pct <= 100; pct++) {
  const i = stepIndex(pct / 100, HARM_POINTS.length);
  const h = HARM_POINTS[i];
  maxH = Math.max(maxH, h);
  // Разные species / phoneme и ноты — чтобы пройти разные фонемы.
  const x = render(cur, 7, { note: 48 + (pct % 24), h, t: (pct % 10) / 9, m: ((pct * 7) % 100) / 100, sec: 0.5 });
  const db = peakDb(x);
  if (Number.isNaN(db)) { ok = false; console.log(`NaN при ${pct} %`); }
  perPoint[i] = Math.min(perPoint[i], db);
}
console.log(`прогон 0…100 %: наибольший harmonics ${maxH.toFixed(4)} (group ${(maxH * 6).toFixed(3)})`);
NAMES.forEach((n, i) => {
  console.log(`  ${n}: наименьший пик ${perPoint[i].toFixed(1)} dBFS`);
  if (!(perPoint[i] >= -60)) ok = false;
});
// Как в speech_engine.cc: group = harmonics · 6 во float32; ветка слов — group > 2.
if (Math.fround(Math.fround(maxH) * 6) > 2) ok = false;

// 2) Сравнение с прежним wasm.
const oldPath = process.argv[2];
if (oldPath) {
  // Свежие экземпляры на каждую ноту: у шумовых движков общий генератор случайных чисел stmlib.
  const curPath = new URL('../public/plaits.wasm', import.meta.url);
  for (let e = 0; e < 16; e++) {
    const aux = e >= 11 ? 0.5 : 0;
    const pts = e === 7 ? HARM_POINTS : [0.5];
    for (const h of pts) {
      const a = render(load(curPath), e, { h, aux });
      const b = render(load(oldPath), e, { h, aux });
      const d = maxDiff(a, b);
      const tag = e === 7 ? `SPEECH h=${h.toFixed(4)}` : `engine ${e}`;
      console.log(`  ${tag}: пик ${peakDb(a).toFixed(1)} dBFS, разница с прежним ${d === 0 ? '0 (бит-в-бит)' : d.toExponential(2)}`);
      if (d !== 0) ok = false;
    }
  }
}
console.log(ok ? 'OK' : 'FAIL');
process.exit(ok ? 0 : 1);
