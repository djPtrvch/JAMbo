// Сатуратор мастер-шины: после EQ мастера, до компрессора. Стерео, каналы независимо.
// Вход · DRIVE → 4× оверсэмплинг (общий модуль oversampler.js) → нелинейность TAPE / TUBE / EDGE
// (с антипроизводной — меньше алиасинга) ÷ компенсация громкости → обратно → фильтр DC (TUBE) →
// TONE (low shelf + high shelf на 1 kHz) → смесь с сухим сигналом (MIX · smoothstep(DRIVE, 0…1 dB)).
// Сухой сигнал задержан на задержку оверсэмплера (целое число отсчётов) — фазы совпадают при MIX.
// Индикации нет.

// ---------- Константы (одно место) ----------
const TUBE_BIAS = 0.35;
/** Пик синуса, у которого громкость не меняется при любом DRIVE (−12 dBFS). */
const REF_PEAK = 0.25;
const MAX_DRIVE_DB = 24;
/** Шаг таблицы компенсации, dB. */
const COMP_STEP_DB = 0.1;
/** DRIVE, с которого обработка включается полностью (ниже — плавно, при 0 — сухой сигнал). */
const FADE_IN_DB = 1;
const TONE_HZ = 1000;
const TONE_Q = 0.5;
const TONE_MAX_DB = 6;
const DC_HZ = 5;
/** Таблицы антипроизводных (Эрмит): до TABLE_MAX, шаг TABLE_STEP; дальше — асимптотика. */
const TABLE_MAX = 12;
const TABLE_STEP = 1 / 32;
const ADAA_EPS = 1e-6;
const PARAM_SMOOTH_MS = 20;
const TYPE_FADE_MS = 20;
const TINY = 1e-25;
/** Выход из покоя (DRIVE или MIX был 0): буферы оверсэмплера заполняются, потом обработка входит за WARM_RAMP_MS. */
const WARM_SAMPLES = 40;
const WARM_RAMP_MS = 5;

/** Оверсэмплер — общий модуль (oversampler.js, загружается раньше). */
const { OVERSAMPLE, FIR_LEN, PHASE_LEN, PHASES, PH0_DELAY, PH0_GAIN, DEC_C, DEC_HALF, DEC_MID } = globalThis.JamboOversampler;

const coef = (ms, sr) => (ms <= 0 ? 0 : Math.exp(-1 / ((ms / 1000) * sr)));

// ---------- Кривые и их антипроизводные ----------
const TB = Math.tanh(TUBE_BIAS);
const TD = 1 - TB * TB;
let LC_B = 0;

const edgeY = (u) => u / Math.sqrt(Math.sqrt(1 + u * u * u * u));

/**
 * Антипроизводные — по таблицам (кубический Эрмит по значениям F и F' = кривой, шаг TABLE_STEP)
 * на [0, TABLE_MAX], дальше — асимптотика; так без логарифмов и экспонент на каждом отсчёте.
 * Кривые нечётные — F чётная, таблица по |u|.
 */
function makeTable(y) {
  const n = Math.round(TABLE_MAX / TABLE_STEP);
  const F = new Float64Array(n + 2);
  const D = new Float64Array(n + 2);
  for (let i = 0; i <= n; i++) {
    D[i] = y(i * TABLE_STEP);
    if (i === 0) continue;
    // Интеграл по ячейке — Симпсоном (16 частей).
    const a = (i - 1) * TABLE_STEP;
    const m = 16;
    const hh = TABLE_STEP / m;
    let s = y(a) + y(a + TABLE_STEP);
    for (let k = 1; k < m; k++) s += (k % 2 ? 4 : 2) * y(a + k * hh);
    F[i] = F[i - 1] + (s * hh) / 3;
  }
  F[n + 1] = F[n];
  D[n + 1] = D[n];
  return { F, D, fmax: F[n] };
}
const TANH_T = makeTable(Math.tanh);
const EDGE_T = makeTable(edgeY);
const INV_STEP = 1 / TABLE_STEP;

/** F(|u|) по таблице; за TABLE_MAX: tanh — F ≈ a + const (e^-2a ничтожно), EDGE — a − 1/(12a³) + const. */
function tableF(T, edge, u) {
  const a = u < 0 ? -u : u;
  if (a >= TABLE_MAX) {
    const tail = edge ? (1 / (TABLE_MAX * TABLE_MAX * TABLE_MAX) - 1 / (a * a * a)) / 12 : 0;
    return T.fmax + (a - TABLE_MAX) - tail;
  }
  const x = a * INV_STEP;
  const i = x | 0;
  const t = x - i;
  const t2 = t * t;
  const t3 = t2 * t;
  const F = T.F;
  const D = T.D;
  return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + t) * TABLE_STEP * D[i]
    + (-2 * t3 + 3 * t2) * F[i + 1] + (t3 - t2) * TABLE_STEP * D[i + 1];
}

const tapeF = (u) => tableF(TANH_T, false, u);
LC_B = tableF(TANH_T, false, TUBE_BIAS);
const tubeF = (u) => (tableF(TANH_T, false, u + TUBE_BIAS) - LC_B - u * TB) / TD;
const edgeF = (u) => tableF(EDGE_T, true, u);

/** 0 TAPE, 1 TUBE, 2 EDGE: кривая и антипроизводная. */
const SHAPE = [
  (u) => Math.tanh(u),
  (u) => (Math.tanh(u + TUBE_BIAS) - TB) / TD,
  edgeY,
];
const ANTI = [tapeF, tubeF, edgeF];

/**
 * Компенсация громкости по типу и DRIVE (шаг COMP_STEP_DB): c = пик выхода кривой на синусе
 * REF_PEAK · g, делённый на REF_PEAK. У TUBE пик — после удаления постоянной составляющей (фильтр DC).
 */
const COMP_N = Math.round(MAX_DRIVE_DB / COMP_STEP_DB);
const COMP = SHAPE.map((f) => {
  const t = new Float64Array(COMP_N + 2);
  const P = 512;
  for (let i = 0; i <= COMP_N; i++) {
    const g = Math.pow(10, (i * COMP_STEP_DB) / 20);
    const v = new Float64Array(P);
    let mean = 0;
    for (let k = 0; k < P; k++) { v[k] = f(REF_PEAK * g * Math.sin((2 * Math.PI * k) / P)); mean += v[k]; }
    mean /= P;
    let pk = 0;
    for (let k = 0; k < P; k++) pk = Math.max(pk, Math.abs(v[k] - mean));
    t[i] = pk / REF_PEAK;
  }
  t[COMP_N + 1] = t[COMP_N];
  return t;
});

/**
 * Коррекция среднего по двум отсчётам у антипроизводной: вместе с ним даёт максимально плоский
 * симметричный фильтр 1 − sin⁸(ω/2) (9 отводов, ноль на Найквисте 4× частоты). Задержка всей цепи
 * (интерполятор c + ½ + 3½ + децимация c, в отсчётах 4× частоты) — целое число исходных отсчётов,
 * поэтому сухая ветка — просто задержка.
 */
const CORR = [-1, 9, -37, 93, 93, -37, 9, -1].map((v) => v / 128);
const CORR_LEN = CORR.length;
const [K0, K1, K2, K3] = CORR;
const DRY_DELAY = ((FIR_LEN - 1) / 2 + 0.5 + (CORR_LEN - 1) / 2 + (FIR_LEN - 1) / 2) / OVERSAMPLE;

/** RBJ shelf (TDF-II): high — high shelf, иначе low shelf; усиление gDb на частоте TONE_HZ. */
function shelf(gDb, sr, high) {
  const A = Math.pow(10, gDb / 40);
  const w = (2 * Math.PI * TONE_HZ) / sr;
  const cw = Math.cos(w);
  const al = Math.sin(w) / (2 * TONE_Q);
  const sa = 2 * Math.sqrt(A) * al;
  const s = high ? 1 : -1;
  const a0 = A + 1 - s * (A - 1) * cw + sa;
  const b0 = (A * (A + 1 + s * (A - 1) * cw + sa)) / a0;
  const b1 = (-2 * s * A * (A - 1 + s * (A + 1) * cw)) / a0;
  const b2 = (A * (A + 1 + s * (A - 1) * cw - sa)) / a0;
  const a1 = (2 * s * (A - 1 - s * (A + 1) * cw)) / a0;
  const a2 = (A + 1 - s * (A - 1) * cw - sa) / a0;
  return [b0, b1, b2, a1, a2];
}

function biquad(st, c, x) {
  const y = c[0] * x + st[0];
  st[0] = c[1] * x - c[3] * y + st[1];
  st[1] = c[2] * x - c[4] * y;
  return y;
}

/**
 * Нелинейность type с антипроизводной первого порядка по 4 отсчётам u (предыдущий — c.prevU):
 * y[p] (+)= k · (F(u) − F(u0)) / (u − u0). Ветки по типам — без вызовов через таблицу.
 */
function shapeAdaa(c, type, u, y, k, add) {
  const pf = c.prevF;
  let u0 = c.prevU;
  let F0 = pf[type];
  for (let p = 0; p < OVERSAMPLE; p++) {
    const v = u[p];
    let F;
    if (type === 0) F = tableF(TANH_T, false, v);
    else if (type === 1) F = (tableF(TANH_T, false, v + TUBE_BIAS) - LC_B - v * TB) / TD;
    else F = tableF(EDGE_T, true, v);
    const du = v - u0;
    const r = Math.abs(du) < ADAA_EPS ? SHAPE[type](0.5 * (v + u0)) : (F - F0) / du;
    y[p] = add ? y[p] + k * r : k * r;
    u0 = v;
    F0 = F;
  }
  pf[type] = F0;
}

class Channel {
  constructor() {
    this.hist = new Float64Array(PHASE_LEN * 2); // вход · g (исходная частота), двойной буфер
    this.hpos = 0;
    this.dry = new Float64Array(DRY_DELAY); // вход без g — сухая ветка (задержка)
    this.dpos = 0;
    this.u = new Float64Array(OVERSAMPLE);
    this.y = new Float64Array(OVERSAMPLE);
    this.corr = new Float64Array(CORR_LEN * 2); // вход коррекции, двойной буфер
    this.cpos = 0;
    this.os = new Float64Array(FIR_LEN * 2); // выход нелинейности (4× частота), двойной буфер
    this.opos = 0;
    this.prevU = 0;
    this.prevF = new Float64Array(3);
    this.dcX = 0;
    this.dcY = 0;
    this.lo = new Float64Array(2);
    this.hi = new Float64Array(2);
  }
}

class SaturatorProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.p = { drive: 0, type: 0, tone: 0, mix: 100 };
    this.driveDb = 0;
    this.mix = 1;
    this.toneDb = 0;
    this.kSmooth = coef(PARAM_SMOOTH_MS, sr);
    this.kBlock = Math.pow(this.kSmooth, 128);
    this.cur = 0; // тип сейчас
    this.prev = 0; // тип до смены (кроссфейд)
    this.fade = 1; // доля нового типа
    this.fadeStep = 1 / ((TYPE_FADE_MS / 1000) * sr);
    this.kDc = Math.exp((-2 * Math.PI * DC_HZ) / sr);
    this.ch = [new Channel(), new Channel()];
    this.cLo = shelf(0, sr, false);
    this.cHi = shelf(0, sr, true);
    this.idle = true;
    this.warmN = 0;
    this.ramp = 1;
    this.rampStep = 1 / ((WARM_RAMP_MS / 1000) * sr);
    this.port.onmessage = (e) => Object.assign(this.p, e.data);
  }

  /** Отсчёт (уже · g) → 4 отсчёта нелинейности (смесь кривых a — старая, b — новая) → децимация. */
  wet(c, x, ta, tb, wa, wb, ca, cb) {
    const hp = c.hpos;
    const hist = c.hist;
    hist[hp] = hist[hp + PHASE_LEN] = x;
    c.hpos = hp + 1 === PHASE_LEN ? 0 : hp + 1;
    const base = hp + PHASE_LEN;
    const u = c.u;
    u[0] = PH0_GAIN * hist[base - PH0_DELAY];
    for (let p = 1; p < OVERSAMPLE; p++) {
      const f = PHASES[p];
      let s = 0;
      for (let j = 0; j < PHASE_LEN; j++) s += f[j] * hist[base - j];
      u[p] = s;
    }
    const y = c.y;
    if (wa > 0) {
      shapeAdaa(c, ta, u, y, wa / ca, false);
      shapeAdaa(c, tb, u, y, wb / cb, true);
    } else shapeAdaa(c, tb, u, y, 1 / cb, false);
    c.prevU = u[OVERSAMPLE - 1];
    const os = c.os;
    const cb2 = c.corr;
    for (let p = 0; p < OVERSAMPLE; p++) {
      const cp = c.cpos;
      cb2[cp] = cb2[cp + CORR_LEN] = y[p];
      c.cpos = cp + 1 === CORR_LEN ? 0 : cp + 1;
      // Симметричный фильтр коррекции — парами отводов.
      const e = cp + CORR_LEN;
      const yc = K0 * (cb2[e] + cb2[e - 7]) + K1 * (cb2[e - 1] + cb2[e - 6]) + K2 * (cb2[e - 2] + cb2[e - 5]) + K3 * (cb2[e - 3] + cb2[e - 4]);
      const op = c.opos;
      os[op] = os[op + FIR_LEN] = yc;
      c.opos = op + 1 === FIR_LEN ? 0 : op + 1;
    }
    const ob = c.opos + FIR_LEN - 1;
    let out = DEC_MID * os[ob - DEC_C];
    const last = ob - (FIR_LEN - 1);
    for (let j = 0; j < DEC_C; j++) out += DEC_HALF[j] * (os[ob - j] + os[last + j]);
    return out + TINY;
  }

  process(inputs, outputs) {
    const inp = inputs[0];
    const out = outputs[0];
    const n = out[0].length;
    const p = this.p;
    const ks = this.kSmooth;
    const driveT = Math.max(0, Math.min(MAX_DRIVE_DB, p.drive));
    const mixT = Math.max(0, Math.min(1, p.mix / 100));
    const type = Math.max(0, Math.min(2, Math.round(p.type)));
    if (type !== this.cur) {
      // Смена TYPE: кроссфейд 20 ms; новая кривая начинает антипроизводную с текущего отсчёта.
      this.prev = this.fade >= 0.5 ? this.cur : this.prev;
      this.cur = type;
      this.fade = 0;
      for (const c of this.ch) c.prevF[type] = ANTI[type](c.prevU);
    }
    // TONE: наклон сглаживается по блокам, коэффициенты shelf — на блок.
    const toneT = (Math.max(-100, Math.min(100, p.tone)) / 100) * TONE_MAX_DB;
    if (this.toneDb !== toneT) {
      this.toneDb = Math.abs(toneT - this.toneDb) < 1e-4 ? toneT : toneT + (this.toneDb - toneT) * this.kBlock;
      this.cLo = shelf(-this.toneDb, this.sr, false);
      this.cHi = shelf(this.toneDb, this.sr, true);
    }
    const cLo = this.cLo;
    const cHi = this.cHi;
    const kDc = this.kDc;
    const D = DRY_DELAY;
    // DRIVE 0 или MIX 0 — выход = сухой сигнал: обработку не считаем (история входа идёт дальше).
    if ((driveT === 0 && this.driveDb < 1e-4) || (mixT === 0 && this.mix < 1e-5)) {
      this.driveDb = driveT;
      this.mix = mixT;
      this.fade = 1;
      this.idle = true;
      for (let k = 0; k < 2; k++) {
        const c = this.ch[k];
        const src = inp[k] || inp[0];
        const o = out[k] || out[0];
        const g = Math.exp(driveT * 0.11512925464970229);
        for (let i = 0; i < n; i++) {
          const x = src ? src[i] : 0;
          const hp = c.hpos;
          c.hist[hp] = c.hist[hp + PHASE_LEN] = x * g;
          c.hpos = hp + 1 === PHASE_LEN ? 0 : hp + 1;
          const dp = c.dpos;
          o[i] = c.dry[dp];
          c.dry[dp] = x;
          c.dpos = dp + 1 === D ? 0 : dp + 1;
        }
        if (!out[1]) break;
      }
      return true;
    }
    if (this.idle) {
      // Из покоя: буферы обработки заполняются заново, обработанная ветка входит после них плавно.
      this.idle = false;
      for (const c of this.ch) {
        c.os.fill(0);
        c.corr.fill(0);
        c.prevU = 0;
        c.prevF.fill(0);
        c.dcX = 0;
        c.dcY = 0;
      }
      this.warmN = WARM_SAMPLES;
      this.ramp = 0;
    }
    for (let i = 0; i < n; i++) {
      this.driveDb = driveT + (this.driveDb - driveT) * ks;
      this.mix = mixT + (this.mix - mixT) * ks;
      if (this.fade < 1) this.fade = Math.min(1, this.fade + this.fadeStep);
      const dB = this.driveDb;
      const g = Math.exp(dB * 0.11512925464970229); // 10^(dB/20)
      const t = Math.min(1, dB / FADE_IN_DB);
      if (this.warmN > 0) this.warmN--;
      else if (this.ramp < 1) this.ramp = Math.min(1, this.ramp + this.rampStep);
      const w = this.mix * t * t * (3 - 2 * t) * this.ramp;
      // Компенсация громкости по таблице.
      const ci = dB / COMP_STEP_DB;
      const i0 = Math.floor(ci);
      const fr = ci - i0;
      const ta = this.prev;
      const tb = this.cur;
      const wb = this.fade;
      const wa = ta === tb ? 0 : 1 - wb;
      const ca = COMP[ta][i0] + (COMP[ta][i0 + 1] - COMP[ta][i0]) * fr;
      const cb = COMP[tb][i0] + (COMP[tb][i0 + 1] - COMP[tb][i0]) * fr;
      // Доля TUBE — после неё фильтр DC.
      const tube = (tb === 1 ? wb : 0) + (ta === 1 ? wa : 0);
      for (let k = 0; k < 2; k++) {
        const c = this.ch[k];
        const src = inp[k] || inp[0];
        const x = src ? src[i] : 0;
        // Сухая ветка — задержка, равная задержке оверсэмплера.
        const dp = c.dpos;
        const dry = c.dry[dp];
        c.dry[dp] = x;
        c.dpos = dp + 1 === D ? 0 : dp + 1;
        let y = this.wet(c, x * g, ta, tb, wa, wb, ca, cb);
        // Фильтр DC (high-pass 1-го порядка) — для TUBE.
        const hpY = kDc * (c.dcY + y - c.dcX) + TINY;
        c.dcX = y;
        c.dcY = hpY;
        y += tube * (hpY - y);
        y = biquad(c.hi, cHi, biquad(c.lo, cLo, y));
        const o = out[k] || out[0];
        o[i] = dry + w * (y - dry);
        if (!out[1]) break;
      }
    }
    return true;
  }
}

registerProcessor('saturator', SaturatorProcessor);
