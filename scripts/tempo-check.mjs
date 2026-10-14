// Проверка источника такта (офлайн в Node, без звука): node --experimental-strip-types scripts/tempo-check.mjs
// beatAt и timeAt взаимно обратны; смена темпа не даёт скачка доли; шаг n на 120 BPM — n·0,125 с (±1 мкс);
// шаги по долям совпадают с прежним планировщиком (nextTime += длина шага) и при смене темпа на ходу.
import { InternalTempoSource, STEPS_PER_BEAT, isBarStart, nextBarAt } from '../src/tempoSource.ts';

let ok = true;
const check = (name, cond, info = '') => { console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}${info ? ` — ${info}` : ''}`); if (!cond) ok = false; };

let bpm = 120;
const src = new InternalTempoSource(() => bpm, (v) => { bpm = v; });
src.started(12.345);

// 1) Взаимно обратны.
let maxErr = 0;
for (let b = 0; b < 1000; b += 0.37) maxErr = Math.max(maxErr, Math.abs(src.beatAt(src.timeAt(b)) - b));
for (let t = 12.345; t < 600; t += 0.731) maxErr = Math.max(maxErr, Math.abs(src.timeAt(src.beatAt(t)) - t));
check('beatAt(timeAt(b)) = b и timeAt(beatAt(t)) = t', maxErr < 1e-9, `наибольшая ошибка ${maxErr.toExponential(1)}`);

// 2) Шаг n на 120 BPM — n·0,125 с.
let stepErr = 0;
for (let n = 0; n < 100000; n++) stepErr = Math.max(stepErr, Math.abs(src.timeAt(n / STEPS_PER_BEAT) - 12.345 - n * 0.125));
check('шаг n на 120 BPM — n·0,125 с', stepErr < 1e-6, `наибольшая ошибка ${(stepErr * 1e6).toFixed(4)} мкс на 100 000 шагах`);

// 3) Смена темпа: доля в момент смены не прыгает.
const tc = src.timeAt(37 / STEPS_PER_BEAT);
const before = src.beatAt(tc);
bpm = 97.3;
src.retempo(37 / STEPS_PER_BEAT);
const after = src.beatAt(tc);
check('смена темпа 120 → 97,3 без скачка доли', Math.abs(after - before) < 1e-9, `${before} → ${after}`);
check('после смены — новый темп', Math.abs(src.timeAt(38 / STEPS_PER_BEAT) - tc - 60 / 97.3 / 4) < 1e-9);

// 4) Как прежний планировщик: nextTime += 60000/bpm/4 после каждого шага, темп меняется на ходу.
bpm = 120;
const s2 = new InternalTempoSource(() => bpm, () => {});
s2.started(1);
let nextOld = 1000, worst = 0;
const tempos = (k) => (k < 50 ? 120 : k < 120 ? 133 : k < 300 ? 87.5 : 240);
for (let k = 0; k < 500; k++) {
  bpm = tempos(k);
  const nextNew = s2.timeAt(k / STEPS_PER_BEAT) * 1000;
  worst = Math.max(worst, Math.abs(nextNew - nextOld));
  // Прежний: после шага k — интервал по текущему темпу. Новый: retempo с доли шага k.
  nextOld += 60000 / bpm / 4;
  s2.retempo(k / STEPS_PER_BEAT);
}
check('шаги совпадают с прежним планировщиком (смены темпа на ходу)', worst < 1e-6, `наибольшее расхождение ${(worst * 1000).toFixed(4)} мкс`);

// 5) Граница такта (quantum 4 доли = 16 шагов).
check('граница такта — каждые 16 шагов', [0, 16, 32].every((k) => isBarStart(k / 4)) && ![4, 8, 15, 17].some((k) => isBarStart(k / 4)));
check('следующая граница такта', nextBarAt(0) === 0 && nextBarAt(0.25) === 4 && nextBarAt(4) === 4 && nextBarAt(7.9) === 8);

console.log(ok ? 'OK' : 'FAIL');
process.exit(ok ? 0 : 1);
