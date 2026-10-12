// AudioWorklet: свои синт-движки JAMbo (чистый JS, без WASM) — DRUM, ANALOG, FM, WTABLE.
// Протокол как у plaits-worklet.js: один узел = одна дорожка, у узла SLOTS моно-выходов —
// по одному на голос; дальше каждый голос идёт через свою цепочку Web Audio (огибающая Attack/Decay,
// Level, фильтр, Pan, посылы — engine.ts).
//
// Сообщения из основного потока (массив событий):
//   { type: 'note', slot, frame, end, engine, note, p1, p2, p3, decay, accent }
//     — в кадре frame голос запускается, после кадра end молчит и не считается;
//     p1, p2, p3 — ручки 1.1–1.3 (0..1), decay — ручка Decay (мс);
//   { type: 'mod', slot, note, p1, p2, p3, decay } — модуляция звучащего голоса (сразу, со сглаживанием);
//   { type: 'stop', slot, frame } — с кадра frame голос слота молчит (слот занял голос Plaits);
//   { type: 'table', frames, levels: [{ size, data }] } — таблица WTABLE дорожки: frames кадров,
//     мипмапы по октавам (уровень L — гармоники до 1024 >> L, data — frames × size отсчётов).
// Голос, который затих сам (DRUM), перестаёт считаться раньше end.
// Высота — MIDI-нота (как у Plaits: 69 = A4 = 440 Гц), частота дискретизации — sampleRate узла.
// Раз в ~0,5 с узел присылает { cpu: доля времени, ушедшая на расчёт голосов }.
// В process() нет выделений памяти: все буферы — Float32Array, созданные заранее.

const BLOCK = 24;
/** Тишина дольше этого (кадров) после атаки — голос больше не считается (как у Plaits). */
const SILENCE = 4800;
const QUIET = 1e-5;
/** Сглаживание ручек при смене на лету, с. */
const SMOOTH = 0.005;
const TAU = Math.PI * 2;

const DRUM = 16;
const ANALOG = 17;
const FM = 18;
const WTABLE = 19;

// ---------- DRUM ----------
/** Обертон мембраны (отношение частот) и Q полосового фильтра шума. */
const DRUM_RATIO = 1.6;
const DRUM_Q = 1.2;
/** Длительность клика, с. */
const DRUM_CLICK = 0.002;
/** Уровень синуса (пик) и шума (RMS) до клиппера: запас под клик и насыщение. */
const DRUM_SINE = 0.7;
const DRUM_NOISE_RMS = 0.45;
/** Общий множитель после клиппера: пик не выше 0 dBFS. */
const DRUM_OUT = 0.85;

// ---------- ANALOG ----------
/** Расстройка OSC1/OSC2 в сумме (центы) при ручке DETUNE 100 % (кривая x²). */
const ANALOG_DETUNE = 60;
/** Дрейф высоты голоса: ± центов; новая случайная цель — в среднем раз в 1/ANALOG_DRIFT_RATE с, плавно за 0,7 с. */
const ANALOG_DRIFT = 3;
const ANALOG_DRIFT_RATE = 2;
const ANALOG_OUT = 0.62;

// ---------- FM ----------
const FM_SNAP = [0.5, 1, 1.5, 2, 3, 4, 5, 6, 7, 8];
const FM_INDEX = 10;
/** Обратная связь модулятора (в долях периода) при нормированном индексе 1. */
const FM_FEEDBACK = 0.35;
const FM_OUT = 0.7;
/** Полуполосный фильтр децимации ×2 (окно Блэкмана–Харриса), нечётная длина. */
const HB_LEN = 63;

// ---------- WTABLE ----------
const WT_UNISON = 40;
const WT_SIDE = 0.708;
const WT_OUT = 0.5;

// Таблица синуса (FM): 4096 точек + 1 для линейной интерполяции.
const SIN_N = 4096;
const SIN = new Float32Array(SIN_N + 1);
for (let i = 0; i <= SIN_N; i++) SIN[i] = Math.sin(TAU * i / SIN_N);
/** Синус по фазе в долях периода (любое число), таблица с линейной интерполяцией. */
function sinT(ph) {
  let x = ph - Math.floor(ph);
  x *= SIN_N;
  const i = x | 0;
  return SIN[i] + (SIN[i + 1] - SIN[i]) * (x - i);
}

// Коэффициенты полуполосного фильтра: только центр и нечётные отводы (чётные — нули).
const HB_C = (HB_LEN - 1) / 2;
const HB_TAPS = [];
{
  let sum = 0;
  const all = new Float64Array(HB_LEN);
  for (let n = 0; n < HB_LEN; n++) {
    const k = n - HB_C;
    const sinc = k === 0 ? 0.5 : Math.sin(Math.PI * k / 2) / (Math.PI * k);
    const x = n / (HB_LEN - 1);
    const w = 0.35875 - 0.48829 * Math.cos(TAU * x) + 0.14128 * Math.cos(2 * TAU * x) - 0.01168 * Math.cos(3 * TAU * x);
    all[n] = sinc * w;
    sum += all[n];
  }
  for (let n = 0; n < HB_LEN; n++) if ((n - HB_C) % 2 !== 0) HB_TAPS.push(n, all[n] / sum);
  HB_TAPS.push(HB_C, all[HB_C] / sum);
}
const HB_IDX = new Int32Array(HB_TAPS.filter((_, i) => i % 2 === 0));
const HB_K = new Float32Array(HB_TAPS.filter((_, i) => i % 2 === 1));
const HB_N = HB_IDX.length;

function fmRatio(n) {
  const r = 0.5 * Math.pow(16, Math.min(1, Math.max(0, n)));
  for (let i = 0; i < FM_SNAP.length; i++) if (Math.abs(r / FM_SNAP[i] - 1) <= 0.02) return FM_SNAP[i];
  return r;
}

/** PolyBLEP: поправка у разрыва (t — фаза 0..1, dt — шаг фазы). */
function blep(t, dt) {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}

// ANALOG: формы совмещены по фазе (все положительны на первой половине периода): синус, треугольник
// с пиком на четверти периода, нисходящая пила, квадрат. Пик смеси соседних форм (кроссфейд равной
// мощности, нормированный по сумме амплитуд) заранее посчитан по сетке — делением на него пик не прыгает.
const WAVE_STEPS = 64;
const WAVE_GAIN = new Float32Array(3 * (WAVE_STEPS + 1));
{
  const shape = (k, ph) => (k === 0 ? Math.sin(TAU * ph) : k === 1 ? 1 - 4 * Math.abs(ph < 0.75 ? ph - 0.25 : ph - 1.25)
    : k === 2 ? 1 - 2 * ph : ph < 0.5 ? 1 : -1);
  for (let seg = 0; seg < 3; seg++) {
    for (let st = 0; st <= WAVE_STEPS; st++) {
      const wf = st / WAVE_STEPS;
      const ca = Math.cos(wf * Math.PI / 2), cb = Math.sin(wf * Math.PI / 2);
      let pk = 0;
      for (let i = 0; i < 2048; i++) {
        const ph = i / 2048;
        pk = Math.max(pk, Math.abs((ca * shape(seg, ph) + cb * shape(seg + 1, ph)) / (ca + cb)));
      }
      WAVE_GAIN[seg * (WAVE_STEPS + 1) + st] = 1 / pk;
    }
  }
}

const flush = (x) => (x > 1e-20 || x < -1e-20 ? x : 0);

/** Голос: состояние слота для всех движков (буферы — заранее). */
class Voice {
  constructor() {
    this.engine = DRUM;
    this.note = 48;
    // Цели ручек и сглаженные значения.
    this.t1 = 0.5; this.t2 = 0.5; this.t3 = 0.5; this.td = 500;
    this.s1 = 0.5; this.s2 = 0.5; this.s3 = 0.5; this.sd = 500;
    this.t = 0;
    this.rnd = 22222;
    // DRUM
    this.p1 = 0; this.p2 = 0; this.ic1 = 0; this.ic2 = 0;
    // ANALOG
    this.a1 = 0; this.a2 = 0; this.as = 0; this.tri1 = 0; this.tri2 = 0; this.drift = 0; this.driftTo = 0;
    // FM
    this.pc = 0; this.pm = 0; this.m1 = 0; this.m2 = 0;
    this.hb = new Float32Array(HB_LEN * 2);
    this.hbPos = 0;
    // WTABLE: центр и два боковых голоса
    this.w0 = 0; this.wl = 0; this.wr = 0;
  }

  rand() {
    let r = this.rnd;
    r ^= r << 13; r ^= r >>> 17; r ^= r << 5;
    this.rnd = r;
    return (r >>> 0) / 4294967296;
  }

  set(ev) {
    this.note = ev.note;
    this.t1 = ev.p1; this.t2 = ev.p2; this.t3 = ev.p3;
    if (ev.decay !== undefined) this.td = ev.decay;
  }

  trigger(ev) {
    this.engine = ev.engine;
    this.set(ev);
    // Новая нота — ручки сразу на своих местах (сглаживание — только для смены на лету).
    this.s1 = this.t1; this.s2 = this.t2; this.s3 = this.t3; this.sd = this.td;
    this.t = 0;
    this.p1 = 0; this.p2 = 0;
    this.pc = 0; this.pm = 0; this.m1 = 0; this.m2 = 0;
    this.hb.fill(0);
    // ANALOG: случайная начальная фаза (одна на оба осциллятора — в унисоне они не гасят друг друга).
    const ph = this.rand();
    this.a1 = ph; this.a2 = ph; this.as = ph * 0.5;
    this.tri1 = this.tri2 = 1 - 4 * Math.abs(ph < 0.75 ? ph - 0.25 : ph - 1.25);
    this.drift = (this.rand() * 2 - 1) * ANALOG_DRIFT;
    this.driftTo = this.drift;
    // WTABLE: центр с нуля, боковые — со случайной фазы (без скачка уровня при включении унисона).
    this.w0 = 0; this.wl = this.rand(); this.wr = this.rand();
  }

  /** Сглаживание ручек на блок из n кадров. */
  smooth(n) {
    const k = 1 - Math.exp(-n / (SMOOTH * sampleRate));
    this.s1 += (this.t1 - this.s1) * k;
    this.s2 += (this.t2 - this.s2) * k;
    this.s3 += (this.t3 - this.s3) * k;
    this.sd += (this.td - this.sd) * k;
  }

  render(out, pos, n, table) {
    this.smooth(n);
    if (this.engine === DRUM) this.drum(out, pos, n);
    else if (this.engine === ANALOG) this.analog(out, pos, n);
    else if (this.engine === FM) this.fm(out, pos, n);
    else if (this.engine === WTABLE) this.wtable(out, pos, n, table);
    else out.fill(0, pos, pos + n);
  }

  // Синус со свипом высоты + шум через полосовой фильтр + клик → мягкий клиппер.
  drum(out, pos, n) {
    const sr = sampleRate;
    const f0 = 440 * Math.pow(2, (this.note - 69) / 12);
    const decay = this.sd;
    const tau = Math.max(0.001, decay / 1000);
    // SWEEP: 0..+48 полутонов, время свипа = clamp(0.08 × decay, 6, 80 мс).
    const tauSweep = Math.min(0.08, Math.max(0.006, 0.08 * decay / 1000));
    const semis = 48 * this.s1;
    // TONE: синус ↔ шум равной мощности; до 50 % растёт доля обертона 1.6.
    const x = this.s2;
    const gs = Math.cos(x * Math.PI / 2), gn = Math.sin(x * Math.PI / 2);
    const h2 = Math.min(1, x * 2) * 0.5;
    const hNorm = 1 / Math.sqrt(1 + h2 * h2);
    // Полосовой фильтр шума (TPT SVF): центр нота × 4, Q 1.2; уровень шума — к RMS DRUM_NOISE_RMS
    // по эквивалентной полосе фильтра (белый шум ±1 — RMS 1/√3).
    const fc = Math.min(f0 * 4, sr * 0.45);
    const g = Math.tan(Math.PI * fc / sr), k = 1 / DRUM_Q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const enbw = Math.PI / 2 * fc / DRUM_Q;
    const nGain = DRUM_NOISE_RMS / ((1 / Math.sqrt(3)) * Math.sqrt(Math.min(1, enbw / (sr / 2))));
    // DRIVE: клик (до 1.0) и tanh (запас 1 → 12), компенсация — пик DRUM_SINE остаётся на месте.
    const dg = 1 + 11 * this.s3;
    const comp = DRUM_SINE / Math.tanh(dg * DRUM_SINE);
    const click = this.s3;
    const clickLen = DRUM_CLICK * sr;
    const dEnv = Math.exp(-1 / (tau * sr));
    const dSweep = Math.exp(-1 / (tauSweep * sr));
    let t = this.t;
    let env = Math.exp(-t / (tau * sr));
    let sw = Math.exp(-t / (tauSweep * sr));
    let p1 = this.p1, p2 = this.p2, ic1 = this.ic1, ic2 = this.ic2, rnd = this.rnd;
    for (let i = 0; i < n; i++) {
      const f = f0 * Math.pow(2, semis * sw / 12);
      p1 += f / sr; if (p1 >= 1) p1 -= 1;
      p2 += f * DRUM_RATIO / sr; if (p2 >= 1) p2 -= 1;
      const tonal = (Math.sin(TAU * p1) + h2 * Math.sin(TAU * p2)) * hNorm;
      rnd ^= rnd << 13; rnd ^= rnd >>> 17; rnd ^= rnd << 5;
      const wn = (rnd | 0) / 2147483648;
      const v3 = wn - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
      ic1 = 2 * v1 - ic1; ic2 = 2 * v2 - ic2;
      let y = env * (gs * DRUM_SINE * tonal + gn * k * v1 * nGain);
      if (t < clickLen) y += click * (1 - t / clickLen);
      out[pos + i] = DRUM_OUT * comp * Math.tanh(dg * y);
      env *= dEnv; sw *= dSweep; t++;
    }
    this.p1 = p1; this.p2 = p2; this.ic1 = flush(ic1); this.ic2 = flush(ic2); this.rnd = rnd; this.t = t;
  }

  // Два осциллятора PolyBLEP (одна форма) + суб (квадрат −1 октава) + дрейф высоты; считается
  // с передискретизацией ×2 и полуполосным фильтром (как FM) — алиасинг пилы и квадрата ниже −60 dBc.
  analog(out, pos, n) {
    const sr2 = sampleRate * 2;
    // Дрейф: медленное случайное блуждание ±ANALOG_DRIFT центов (на голос, общий для осцилляторов).
    if (this.rand() < ANALOG_DRIFT_RATE * n / sampleRate) this.driftTo = (this.rand() * 2 - 1) * ANALOG_DRIFT;
    this.drift += (this.driftTo - this.drift) * n / (0.7 * sampleRate);
    const f0 = 440 * Math.pow(2, (this.note - 69 + this.drift / 100) / 12);
    // DETUNE: OSC1 вверх, OSC2 вниз, в сумме 0..60 центов по кривой x².
    const det = ANALOG_DETUNE / 2 * this.s2 * this.s2;
    const dt1 = Math.min(0.45, f0 * Math.pow(2, det / 1200) / sr2);
    const dt2 = Math.min(0.45, f0 * Math.pow(2, -det / 1200) / sr2);
    const dts = f0 * 0.5 / sr2;
    // WAVE: синус (0) → треугольник (1/3) → пила (2/3) → квадрат (1).
    const seg = Math.min(2.9999, Math.max(0, this.s1 * 3));
    const wi = seg | 0, wf = seg - wi;
    const ca = Math.cos(wf * Math.PI / 2), cb = Math.sin(wf * Math.PI / 2);
    const gx = wf * WAVE_STEPS, gi = gx | 0, gr = gx - gi, gb = wi * (WAVE_STEPS + 1) + gi;
    const wg = WAVE_GAIN[gb] + (gi < WAVE_STEPS ? (WAVE_GAIN[gb + 1] - WAVE_GAIN[gb]) * gr : 0);
    const wA = ca / (ca + cb) * wg, wB = cb / (ca + cb) * wg;
    // SUB: 0..100 % по амплитуде, общий уровень компенсируется.
    const sub = this.s3;
    const gain = ANALOG_OUT / (1 + 0.5 * sub);
    const leak = 1 - 20 / sr2;
    let a1 = this.a1, a2 = this.a2, as = this.as, tri1 = this.tri1, tri2 = this.tri2, hp = this.hbPos;
    const hb = this.hb;
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < 2; j++) {
        // Треугольник — интеграл квадрата, сдвинутого на четверть периода (пик на φ = 0.25).
        const b1 = a1 < 0.75 ? a1 + 0.25 : a1 - 0.75, b2 = a2 < 0.75 ? a2 + 0.25 : a2 - 0.75;
        tri1 = tri1 * leak + 4 * dt1 * ((b1 < 0.5 ? 1 : -1) + blep(b1, dt1) - blep(b1 < 0.5 ? b1 + 0.5 : b1 - 0.5, dt1));
        tri2 = tri2 * leak + 4 * dt2 * ((b2 < 0.5 ? 1 : -1) + blep(b2, dt2) - blep(b2 < 0.5 ? b2 + 0.5 : b2 - 0.5, dt2));
        let x1A, x2A, x1B, x2B;
        if (wi === 0) {
          x1A = sinT(a1); x2A = sinT(a2); x1B = tri1; x2B = tri2;
        } else if (wi === 1) {
          x1A = tri1; x2A = tri2;
          x1B = 1 - 2 * a1 + blep(a1, dt1); x2B = 1 - 2 * a2 + blep(a2, dt2);
        } else {
          x1A = 1 - 2 * a1 + blep(a1, dt1); x2A = 1 - 2 * a2 + blep(a2, dt2);
          x1B = (a1 < 0.5 ? 1 : -1) + blep(a1, dt1) - blep(a1 < 0.5 ? a1 + 0.5 : a1 - 0.5, dt1);
          x2B = (a2 < 0.5 ? 1 : -1) + blep(a2, dt2) - blep(a2 < 0.5 ? a2 + 0.5 : a2 - 0.5, dt2);
        }
        const osc = 0.5 * (wA * (x1A + x2A) + wB * (x1B + x2B));
        const sb = (as < 0.5 ? 1 : -1) + blep(as, dts) - blep(as < 0.5 ? as + 0.5 : as - 0.5, dts);
        const y = gain * (osc + sub * sb);
        hb[hp] = y; hb[hp + HB_LEN] = y;
        hp = hp + 1 === HB_LEN ? 0 : hp + 1;
        a1 += dt1; if (a1 >= 1) a1 -= 1;
        a2 += dt2; if (a2 >= 1) a2 -= 1;
        as += dts; if (as >= 1) as -= 1;
      }
      let acc = 0;
      for (let q = 0; q < HB_N; q++) acc += HB_K[q] * hb[hp + HB_IDX[q]];
      out[pos + i] = acc;
    }
    this.a1 = a1; this.a2 = a2; this.as = as; this.tri1 = flush(tri1); this.tri2 = flush(tri2); this.hbPos = hp;
    this.t += n;
  }

  // Два оператора: несущая (ratio 1) и модулятор (RATIO) с обратной связью; ×2 передискретизация.
  fm(out, pos, n) {
    const sr = sampleRate;
    const f0 = 440 * Math.pow(2, (this.note - 69) / 12);
    const ratio = fmRatio(this.s1);
    const idxNorm = Math.pow(this.s2, 1.5);
    // Индекс в радианах → в долях периода (фазы считаются в периодах).
    const index = FM_INDEX * idxNorm / TAU;
    const fb = FM_FEEDBACK * idxNorm;
    // CONTOUR: индекс спадает с постоянной времени от Decay: 0 % — постоянный, 50 % — как амплитуда
    // (огибающая engine.ts: постоянная Decay / 4), 100 % — в 5 раз быстрее.
    const m = this.s3;
    const k = m < 0.5 ? 2 * m : 1 + 8 * (m - 0.5);
    const tauA = Math.max(0.001, this.sd / 4000);
    const rate = k / tauA;
    const dt = f0 / (2 * sr);
    let env = Math.exp(-this.t / sr * rate);
    const dEnv = Math.exp(-rate / sr);
    let pc = this.pc, pm = this.pm, m1 = this.m1, m2 = this.m2, hp = this.hbPos;
    const hb = this.hb;
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < 2; j++) {
        const mod = sinT(pm + fb * 0.5 * (m1 + m2));
        m2 = m1; m1 = mod;
        const y = sinT(pc + index * env * mod);
        pm += ratio * dt; if (pm >= 1) pm -= Math.floor(pm);
        pc += dt; if (pc >= 1) pc -= 1;
        hb[hp] = y; hb[hp + HB_LEN] = y;
        hp = hp + 1 === HB_LEN ? 0 : hp + 1;
      }
      // Децимация: свёртка с полуполосным фильтром (только ненулевые отводы).
      let acc = 0;
      for (let q = 0; q < HB_N; q++) acc += HB_K[q] * hb[hp + HB_IDX[q]];
      out[pos + i] = FM_OUT * acc;
      env *= dEnv;
    }
    this.pc = pc; this.pm = pm; this.m1 = m1; this.m2 = m2; this.hbPos = hp;
    this.t += n;
  }

  // Чтение кадров таблицы (по фазе и между кадрами), мипмап по октаве, WARP и UNISON.
  wtable(out, pos, n, table) {
    if (!table) { out.fill(0, pos, pos + n); return; }
    const sr = sampleRate;
    const f0 = 440 * Math.pow(2, (this.note - 69) / 12);
    const frames = table.frames;
    const fpos = this.s1 * (frames - 1);
    const fi = Math.min(frames - 2, Math.max(0, Math.floor(fpos)));
    const ff = frames > 1 ? fpos - fi : 0;
    // WARP: 0..50 % — изгиб фазы φ^(1+3w); 50..100 % — плюс синхронизация 1 → 4.
    const w = this.s2;
    const bend = 1 + 3 * Math.min(1, w * 2);
    const sync = w > 0.5 ? 1 + 3 * (w - 0.5) * 2 : 1;
    // UNISON: до 25 % — один голос; дальше три (боковые на −3 дБ), расстройка 0 → 40 центов.
    const u = this.s3;
    const side = u <= 0.25 ? 0 : WT_SIDE * Math.min(1, (u - 0.25) / 0.05);
    const cents = u <= 0.25 ? 0 : WT_UNISON * (u - 0.25) / 0.75;
    const norm = WT_OUT / Math.sqrt(1 + 2 * side * side);
    const dt0 = f0 / sr;
    const dtl = dt0 * Math.pow(2, -cents / 1200), dtr = dt0 * Math.pow(2, cents / 1200);
    // Мипмап: уровень, где гармоники (с учётом синхронизации и изгиба) не выше Найквиста.
    const fEff = f0 * Math.pow(2, cents / 1200) * sync * (1 + (bend - 1) * 0.5);
    const lv = Math.min(table.levels.length - 1, Math.max(0, Math.ceil(Math.log2(1024 * fEff / (0.5 * sr)))));
    const level = table.levels[lv];
    const size = level.size, data = level.data;
    const rowA = fi * size, rowB = (frames > 1 ? fi + 1 : fi) * size;
    let w0 = this.w0, wl = this.wl, wr = this.wr;
    const bent = bend !== 1;
    for (let i = 0; i < n; i++) {
      let y = 0;
      for (let v = 0; v < 3; v++) {
        if (v > 0 && side === 0) break;
        let ph = v === 0 ? w0 : v === 1 ? wl : wr;
        if (sync !== 1) { ph *= sync; ph -= Math.floor(ph); }
        if (bent) ph = Math.pow(ph, bend);
        const x = ph * size;
        const j = x | 0, fr = x - j;
        const j2 = j + 1 === size ? 0 : j + 1;
        const a = data[rowA + j] + (data[rowA + j2] - data[rowA + j]) * fr;
        const b = data[rowB + j] + (data[rowB + j2] - data[rowB + j]) * fr;
        y += (v === 0 ? 1 : side) * (a + (b - a) * ff);
      }
      out[pos + i] = norm * y;
      w0 += dt0; if (w0 >= 1) w0 -= 1;
      wl += dtl; if (wl >= 1) wl -= 1;
      wr += dtr; if (wr >= 1) wr -= 1;
    }
    this.w0 = w0; this.wl = wl; this.wr = wr;
    this.t += n;
  }
}

class JamboProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const { slots } = options.processorOptions;
    this.slots = slots;
    this.voices = Array.from({ length: slots }, () => new Voice());
    this.pending = Array.from({ length: slots }, () => []);
    this.end = new Float64Array(slots);
    this.start0 = new Float64Array(slots);
    this.quiet = new Float64Array(slots);
    this.table = null;
    this.busy = 0;
    this.frames = 0;
    this.port.onmessage = (e) => {
      const data = e.data;
      if (data && data.type === 'table') { this.table = data; return; }
      for (const ev of data) {
        if (ev.type === 'note' || ev.type === 'stop') {
          const q = this.pending[ev.slot];
          q.push(ev);
          q.sort((a, b) => a.frame - b.frame);
        } else if (ev.type === 'mod') {
          this.voices[ev.slot].set(ev);
        }
      }
    };
  }

  start(slot, ev) {
    if (ev.type === 'stop') { this.end[slot] = Math.min(this.end[slot], ev.frame); return; }
    this.end[slot] = ev.end;
    this.start0[slot] = ev.frame;
    this.quiet[slot] = 0;
    this.voices[slot].trigger(ev);
  }

  process(_inputs, outputs) {
    const t0 = Date.now();
    const frames = outputs[0][0].length;
    for (let s = 0; s < this.slots; s++) {
      const out = outputs[s][0];
      const q = this.pending[s];
      const vo = this.voices[s];
      let pos = 0;
      while (pos < frames) {
        const now = currentFrame + pos;
        // Запуск ноты ровно в её кадре (запоздавшая — сразу).
        while (q.length && q[0].frame <= now) this.start(s, q.shift());
        let n = Math.min(BLOCK, frames - pos);
        if (q.length) n = Math.min(n, q[0].frame - now);
        if (now >= this.end[s]) {
          out.fill(0, pos, pos + n);
        } else {
          vo.render(out, pos, n, this.table);
          let peak = 0;
          for (let i = pos; i < pos + n; i++) { const a = out[i] < 0 ? -out[i] : out[i]; if (a > peak) peak = a; }
          this.quiet[s] = peak < QUIET ? this.quiet[s] + n : 0;
          if (this.quiet[s] > SILENCE && now - this.start0[s] > SILENCE) this.end[s] = now;
        }
        pos += n;
      }
    }
    this.busy += Date.now() - t0;
    this.frames += frames;
    if (this.frames >= sampleRate / 2) {
      this.port.postMessage({ cpu: this.busy / (this.frames / sampleRate * 1000) });
      this.busy = 0;
      this.frames = 0;
    }
    return true;
  }
}

registerProcessor('jambo-synth', JamboProcessor);
