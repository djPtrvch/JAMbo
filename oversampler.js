// Общий 4× оверсэмплер мастера (клиппер, сатуратор): полифазный FIR с окном Кайзера.
// Загружается в AudioWorkletGlobalScope первым (addModule) и кладёт константы в globalThis.JamboOversampler.

// ---------- Константы (одно место) ----------
const OVERSAMPLE = 4;
/** Длина FIR оверсэмплинга (отсчёты 4× частоты), нечётная — целый центр. */
const FIR_LEN = 129;
const KAISER_BETA = 9;

function besselI0(x) {
  let s = 1;
  let t = 1;
  for (let k = 1; k < 30; k++) { t *= (x / (2 * k)) ** 2; s += t; }
  return s;
}

/** Ядро ФНЧ на частоте Найквиста исходной частоты (окно Кайзера), в отсчётах 4× частоты. */
function makeKernel() {
  const h = new Float64Array(FIR_LEN);
  const c = (FIR_LEN - 1) / 2;
  const fc = 0.5 / OVERSAMPLE;
  let sum = 0;
  for (let k = 0; k < FIR_LEN; k++) {
    const d = k - c;
    const sinc = d === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * d) / (Math.PI * d);
    const r = d / c;
    const w = besselI0(KAISER_BETA * Math.sqrt(Math.max(0, 1 - r * r))) / besselI0(KAISER_BETA);
    h[k] = sinc * w;
    sum += h[k];
  }
  for (let k = 0; k < FIR_LEN; k++) h[k] /= sum;
  return h;
}
const KERNEL = makeKernel();
/**
 * Фазы интерполятора (усиление OVERSAMPLE). У ядра с частотой среза на Найквисте каждый 4-й отсчёт от
 * центра — ноль, поэтому фаза 0 — просто задержка на PH0_DELAY исходных отсчётов.
 */
const PHASE_LEN = Math.ceil(FIR_LEN / OVERSAMPLE);
const PHASES = [];
for (let p = 0; p < OVERSAMPLE; p++) {
  const taps = new Float64Array(PHASE_LEN);
  for (let k = p, j = 0; k < FIR_LEN; k += OVERSAMPLE, j++) taps[j] = KERNEL[k] * OVERSAMPLE;
  PHASES.push(taps);
}
const PH0_DELAY = (FIR_LEN - 1) / 2 / OVERSAMPLE;
const PH0_GAIN = KERNEL[(FIR_LEN - 1) / 2] * OVERSAMPLE;
/** Децимация: ядро симметрично — пары отводов складываются. */
const DEC_C = (FIR_LEN - 1) / 2;
const DEC_HALF = KERNEL.slice(0, DEC_C);
const DEC_MID = KERNEL[DEC_C];

globalThis.JamboOversampler = { OVERSAMPLE, FIR_LEN, KERNEL, PHASE_LEN, PHASES, PH0_DELAY, PH0_GAIN, DEC_C, DEC_HALF, DEC_MID };
