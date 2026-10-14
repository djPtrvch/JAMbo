// Drive (этап 7): искажение на шине посыла (вместо прежнего Overdrive — WaveShaperNode). Стерео, каналы независимо.
// Шина отдаёт только обработанный сигнал (сухого пути и Mix нет; количество — посыл дорожки).
// Цепь: вход → LOW CUT (HP 2-го порядка; ≤ 25 Гц — обход) → · g (g = 10^(DRIVE_dB/20), DRIVE_dB = 36·DRIVE/100)
// → 4× оверсэмплинг (общий модуль oversampler.js) → нелинейность TYPE (SOFT, HARD, TUBE, FUZZ — с антипроизводной
// первого порядка по таблицам; FOLD — без антипроизводной) → децимация → фильтр DC (HP 1-го порядка 5 Гц)
// ÷ компенсация громкости → TONE (LP 2-го порядка, 500 Гц · 24^(TONE/100)) → выход.
// CRUSH — без оверсэмплинга (алиасинг — часть эффекта): квантование до B = 12 − 9·D бит и повтор отсчёта
// N = 1 + round(15·D²) раз (D = DRIVE/100), g = 1, без компенсации.
// Параметры — AudioParam (k-rate): drive (0..100), type (0..5), tone (0..100), lowcut (Гц). DRIVE, TONE, LOW CUT
// сглаживаются за 20 мс; смена TYPE — кроссфейд 20 мс старой и новой цепи. Состояние — только в инстансе
// (общая шина или эффект на каждой дорожке). Раз в ~0,5 с узел присылает { cpu }.

// ---------- Константы (одно место) ----------
const DRIVE_CONST = {
  /** DRIVE 100 % — усиление перед нелинейностью, dB. */
  driveDb: 36,
  /** Смещение TUBE (асимметрия — чётные гармоники). */
  tubeBias: 0.35,
  /** Фильтр DC после нелинейности, Гц. */
  dcHz: 5,
  /** LOW CUT: диапазон, Гц; не выше lowCutOff — обход. */
  lowCutMin: 20,
  lowCutMax: 1000,
  lowCutOff: 25,
  /** TONE: частота ФНЧ = toneHz · toneRange^(TONE/100 − … ), как прежде: 500 Гц · 24^(TONE/100). */
  toneHz: 500,
  toneRange: 24,
  /** CRUSH: бит при DRIVE 0 и 100 %, наибольший повтор отсчёта. */
  crushBitsMax: 12,
  crushBitsMin: 3,
  crushHoldMax: 16,
  /** Пик синуса для компенсации громкости (−12 dBFS). */
  refPeak: 0.25,
  /** FOLD: RMS для компенсации — по сигналу с гармониками до foldHarm (на большом DRIVE фолд даёт гармоники выше полосы,
   *  их срезают децимация и TONE — без ограничения громкость занижалась бы до −3 dB). */
  foldHarm: 12,
  /** FOLD: поправка компенсации, dB (пик и RMS синуса −12 dBFS — оба в пределах ±2 dB по всему DRIVE). */
  foldTrimDb: 0.4,
  /** Шаг таблицы компенсации, dB. */
  compStepDb: 0.1,
  /** Сглаживание DRIVE, TONE, LOW CUT и кроссфейд TYPE, мс. */
  smoothMs: 20,
  typeFadeMs: 20,
  /** Таблицы антипроизводных (Эрмит): до tableMax, шаг tableStep; дальше — асимптотика. */
  tableMax: 12,
  tableStep: 1 / 32,
  tiny: 1e-18,
  /** Тишина на входе дольше idleMs — расчёт пропускается (состояния к этому времени затухли), выход — нули. */
  idleMs: 200,
  idleLevel: 1e-7,
};

const C = DRIVE_CONST;
const SOFT = 0, HARD = 1, TUBE = 2, FUZZ = 3, FOLD = 4, CRUSH = 5;
const ADAA_EPS = 1e-6;

/** Оверсэмплер — общий модуль (oversampler.js, загружается раньше). */
const { OVERSAMPLE, FIR_LEN, PHASE_LEN, PHASES, PH0_DELAY, PH0_GAIN, DEC_C, DEC_HALF, DEC_MID } = globalThis.JamboOversampler;

// ---------- Кривые и антипроизводные ----------
const TB = Math.tanh(C.tubeBias);
const TD = 1 - TB * TB;
const fuzzY = (u) => (u < 0 ? -(1 - Math.exp(u)) : 1 - Math.exp(-u));

/** Таблица антипроизводной нечётной кривой y на [0, tableMax] (Симпсон по ячейке) и её значений (для Эрмита). */
function makeTable(y) {
  const n = Math.round(C.tableMax / C.tableStep);
  const F = new Float64Array(n + 2);
  const D = new Float64Array(n + 2);
  for (let i = 0; i <= n; i++) {
    D[i] = y(i * C.tableStep);
    if (i === 0) continue;
    const a = (i - 1) * C.tableStep;
    const m = 16;
    const hh = C.tableStep / m;
    let s = y(a) + y(a + C.tableStep);
    for (let k = 1; k < m; k++) s += (k % 2 ? 4 : 2) * y(a + k * hh);
    F[i] = F[i - 1] + (s * hh) / 3;
  }
  F[n + 1] = F[n];
  D[n + 1] = D[n];
  return { F, D, fmax: F[n] };
}
const TANH_T = makeTable(Math.tanh);
const FUZZ_T = makeTable(fuzzY);
const INV_STEP = 1 / C.tableStep;

/** F(|u|) по таблице (кубический Эрмит); за tableMax кривая ≈ 1 — F растёт линейно. */
function tableF(T, u) {
  const a = u < 0 ? -u : u;
  if (a >= C.tableMax) return T.fmax + (a - C.tableMax);
  const x = a * INV_STEP;
  const i = x | 0;
  const t = x - i, t2 = t * t, t3 = t2 * t;
  const F = T.F, D = T.D, h = C.tableStep;
  return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + t) * h * D[i] + (-2 * t3 + 3 * t2) * F[i + 1] + (t3 - t2) * h * D[i + 1];
}
const LC_B = tableF(TANH_T, C.tubeBias);

/** Кривые 0–4 (для компенсации и малого du). */
const SHAPE = [
  (u) => Math.tanh(u),
  (u) => (u > 1 ? 1 : u < -1 ? -1 : u),
  (u) => (Math.tanh(u + C.tubeBias) - TB) / TD,
  fuzzY,
  (u) => Math.sin(u),
];
/** Антипроизводные 0–3 (у FOLD нет). */
const ANTI = [
  (u) => tableF(TANH_T, u),
  (u) => { const a = u < 0 ? -u : u; return a <= 1 ? 0.5 * u * u : a - 0.5; },
  (u) => (tableF(TANH_T, u + C.tubeBias) - LC_B - u * TB) / TD,
  (u) => tableF(FUZZ_T, u),
];

/**
 * Компенсация громкости по типу и DRIVE (шаг compStepDb): синус refPeak · g через кривую, постоянная составляющая
 * убрана (как после фильтра DC); c = √(пик-отношение · RMS-отношение) — и пик, и RMS остаются в пределах ±2 dB.
 */
/** Оставить в периоде v (P отсчётов) только гармоники 1..H (ряд Фурье; синус — нечётные и чётные). */
function bandLimit(v, H) {
  const P = v.length;
  const cs = new Float64Array(P), sn = new Float64Array(P);
  for (let k = 0; k < P; k++) { cs[k] = Math.cos((2 * Math.PI * k) / P); sn[k] = Math.sin((2 * Math.PI * k) / P); }
  const a = new Float64Array(H + 1), b = new Float64Array(H + 1);
  for (let h = 1; h <= H; h++) {
    let sa = 0, sb = 0;
    for (let k = 0, j = 0; k < P; k++, j = (j + h) % P) { sa += v[k] * cs[j]; sb += v[k] * sn[j]; }
    a[h] = (2 * sa) / P; b[h] = (2 * sb) / P;
  }
  for (let k = 0; k < P; k++) {
    let s = 0;
    for (let h = 1, j = k; h <= H; h++, j = (j + k) % P) s += a[h] * cs[j] + b[h] * sn[j];
    v[k] = s;
  }
}
const COMP_N = Math.round(C.driveDb / C.compStepDb);
const COMP = SHAPE.map((f, type) => {
  const t = new Float64Array(COMP_N + 2);
  const P = 1024;
  const rIn = C.refPeak / Math.SQRT2;
  for (let i = 0; i <= COMP_N; i++) {
    const g = Math.pow(10, (i * C.compStepDb) / 20);
    const v = new Float64Array(P);
    let mean = 0;
    for (let k = 0; k < P; k++) { v[k] = f(C.refPeak * g * Math.sin((2 * Math.PI * k) / P)); mean += v[k]; }
    mean /= P;
    let pk = 0, ss = 0;
    for (let k = 0; k < P; k++) { const d = v[k] - mean; pk = Math.max(pk, Math.abs(d)); ss += d * d; }
    // FOLD: RMS — по сигналу с гармониками до foldHarm (пик — по полной кривой).
    if (type === FOLD) { bandLimit(v, C.foldHarm); ss = 0; for (let k = 0; k < P; k++) ss += v[k] * v[k]; }
    t[i] = Math.sqrt((pk / C.refPeak) * (Math.sqrt(ss / P) / rIn)) * (type === FOLD ? Math.pow(10, C.foldTrimDb / 20) : 1);
  }
  t[COMP_N + 1] = t[COMP_N];
  return t;
});

/**
 * Коррекция среднего по двум отсчётам у антипроизводной (максимально плоский 1 − sin⁸(ω/2), как у сатуратора).
 * Задержка цепи оверсэмплинга — целое число исходных отсчётов (OS_DELAY): CRUSH задержан на столько же,
 * чтобы кроссфейд с ним при смене TYPE не давал гребёнки.
 */
const CORR = [-1, 9, -37, 93, 93, -37, 9, -1].map((v) => v / 128);
const CORR_LEN = CORR.length;
const [K0, K1, K2, K3] = CORR;
const OS_DELAY = ((FIR_LEN - 1) / 2 + 0.5 + (CORR_LEN - 1) / 2 + (FIR_LEN - 1) / 2) / OVERSAMPLE;

/** RBJ (Q = 1/√2) 'hp' | 'lp' → [b0, b1, b2, a1, a2]. */
function rbj(out, type, f, sr) {
  const w = (2 * Math.PI * Math.min(f, sr * 0.45)) / sr;
  const cw = Math.cos(w), al = Math.sin(w) / Math.SQRT2, a0 = 1 + al;
  const b0 = (type === 'hp' ? (1 + cw) / 2 : (1 - cw) / 2) / a0;
  out[0] = b0; out[1] = (type === 'hp' ? -(1 + cw) : 1 - cw) / a0; out[2] = b0; out[3] = (-2 * cw) / a0; out[4] = (1 - al) / a0;
}
/** Биквад TDF-II; st — [s1, s2]. */
function bq(st, c, x) {
  const y = c[0] * x + st[0];
  st[0] = c[1] * x - c[3] * y + st[1];
  st[1] = c[2] * x - c[4] * y;
  return y;
}

class Channel {
  constructor() {
    this.hist = new Float64Array(PHASE_LEN * 2);
    this.hpos = 0;
    this.u = new Float64Array(OVERSAMPLE);
    this.y = new Float64Array(OVERSAMPLE);
    this.corr = new Float64Array(CORR_LEN * 2);
    this.cpos = 0;
    this.os = new Float64Array(FIR_LEN * 2);
    this.opos = 0;
    this.prevU = 0;
    this.prevF = new Float64Array(4);
    this.prevS = 0; // sin предыдущего отсчёта (FOLD)
    this.cd = new Float64Array(OS_DELAY); // задержка входа CRUSH (выравнивание с оверсэмплингом)
    this.cdp = 0;
    this.hold = 0; // CRUSH: удерживаемый отсчёт и счётчик
    this.holdN = 0;
    this.dcX = 0; this.dcY = 0;
    this.lc = new Float64Array(2);
    this.tone = new Float64Array(2);
  }
}

class DriveProcessor extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [
      { name: 'drive', defaultValue: 26, minValue: 0, maxValue: 100, automationRate: 'k-rate' },
      { name: 'type', defaultValue: 0, minValue: 0, maxValue: 5, automationRate: 'k-rate' },
      { name: 'tone', defaultValue: 50, minValue: 0, maxValue: 100, automationRate: 'k-rate' },
      { name: 'lowcut', defaultValue: 20, minValue: 20, maxValue: 1000, automationRate: 'k-rate' },
    ];
  }

  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.started = false;
    this.drive = 26; this.tone = 50; this.lowcut = 20;
    this.kSmooth = Math.exp(-1 / ((C.smoothMs / 1000) * sr));
    this.cur = 0; this.prev = 0; this.fade = 1;
    this.fadeStep = 1 / ((C.typeFadeMs / 1000) * sr);
    this.kDc = Math.exp((-2 * Math.PI * C.dcHz) / sr);
    this.ch = [new Channel(), new Channel()];
    this.cLc = new Float64Array(5);
    this.cTone = new Float64Array(5);
    this.lcSig = NaN; this.toneSig = NaN;
    this.lcW = 0;
    this.silent = 0;
    this.busy = 0;
    this.frames = 0;
  }

  /** Отсчёт (уже · g) → 4 отсчёта нелинейности (смесь типов a и b, только 0–4) → децимация. */
  wet(c, x, ta, tb, wa, wb, ka, kb) {
    const hp = c.hpos, hist = c.hist;
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
    for (let p = 0; p < OVERSAMPLE; p++) y[p] = 0;
    if (wa > 0 && ta !== CRUSH) this.shape(c, ta, u, y, wa / ka);
    if (wb > 0 && tb !== CRUSH) this.shape(c, tb, u, y, wb / kb);
    // Состояния кривых, которые сейчас не считались, — на текущий отсчёт (вход в них без скачка).
    const last = u[OVERSAMPLE - 1];
    for (let t = 0; t < 4; t++) if (t !== ta && t !== tb) c.prevF[t] = ANTI[t](last);
    if (ta !== FOLD && tb !== FOLD) c.prevS = Math.sin(last);
    c.prevU = last;
    const os = c.os, cb = c.corr;
    for (let p = 0; p < OVERSAMPLE; p++) {
      const cp = c.cpos;
      cb[cp] = cb[cp + CORR_LEN] = y[p];
      c.cpos = cp + 1 === CORR_LEN ? 0 : cp + 1;
      const e = cp + CORR_LEN;
      const yc = K0 * (cb[e] + cb[e - 7]) + K1 * (cb[e - 1] + cb[e - 6]) + K2 * (cb[e - 2] + cb[e - 5]) + K3 * (cb[e - 3] + cb[e - 4]);
      const op = c.opos;
      os[op] = os[op + FIR_LEN] = yc;
      c.opos = op + 1 === FIR_LEN ? 0 : op + 1;
    }
    const ob = c.opos + FIR_LEN - 1;
    let out = DEC_MID * os[ob - DEC_C];
    const lst = ob - (FIR_LEN - 1);
    for (let j = 0; j < DEC_C; j++) out += DEC_HALF[j] * (os[ob - j] + os[lst + j]);
    return out;
  }

  /** Нелинейность type по 4 отсчётам u: y[p] += k · кривая. SOFT, HARD, TUBE, FUZZ — антипроизводная первого
   *  порядка (F(u) − F(u0)) / (u − u0); FOLD — среднее sin двух соседних отсчётов (та же задержка ½ отсчёта). */
  shape(c, type, u, y, k) {
    let u0 = c.prevU;
    if (type === FOLD) {
      let s0 = c.prevS;
      for (let p = 0; p < OVERSAMPLE; p++) { const s = Math.sin(u[p]); y[p] += k * 0.5 * (s + s0); s0 = s; }
      c.prevS = s0;
      return;
    }
    let F0 = c.prevF[type];
    for (let p = 0; p < OVERSAMPLE; p++) {
      const v = u[p];
      let F;
      if (type === SOFT) F = tableF(TANH_T, v);
      else if (type === HARD) { const a = v < 0 ? -v : v; F = a <= 1 ? 0.5 * v * v : a - 0.5; }
      else if (type === TUBE) F = (tableF(TANH_T, v + C.tubeBias) - LC_B - v * TB) / TD;
      else F = tableF(FUZZ_T, v);
      const du = v - u0;
      y[p] += k * (Math.abs(du) < ADAA_EPS ? SHAPE[type](0.5 * (v + u0)) : (F - F0) / du);
      u0 = v;
      F0 = F;
    }
    c.prevF[type] = F0;
  }

  process(inputs, outputs, params) {
    const inp = inputs[0];
    const out = outputs[0];
    const n = out[0].length;
    const t0 = Date.now();
    const sr = this.sr;
    const driveT = Math.max(0, Math.min(100, params.drive[0]));
    const toneT = Math.max(0, Math.min(100, params.tone[0]));
    const lcT = Math.max(C.lowCutMin, Math.min(C.lowCutMax, params.lowcut[0]));
    const type = Math.max(0, Math.min(5, Math.round(params.type[0])));
    if (!this.started) {
      this.started = true;
      this.drive = driveT; this.tone = toneT; this.lowcut = lcT; this.cur = this.prev = type;
      this.lcW = lcT > C.lowCutOff ? 1 : 0;
    }
    if (type !== this.cur) {
      // Смена TYPE: кроссфейд 20 мс; новая кривая начинает антипроизводную с текущего отсчёта.
      this.prev = this.fade >= 0.5 ? this.cur : this.prev;
      this.cur = type;
      this.fade = 0;
      for (const c of this.ch) {
        if (type < 4) c.prevF[type] = ANTI[type](c.prevU);
        if (type === FOLD) c.prevS = Math.sin(c.prevU);
      }
    }
    // TONE и LOW CUT — по блокам (сглаживание за 20 мс), коэффициенты — при изменении.
    const kb = Math.pow(this.kSmooth, n);
    this.tone = toneT + (this.tone - toneT) * kb;
    if (Math.abs(this.tone - toneT) < 1e-3) this.tone = toneT;
    this.lowcut = Math.exp(Math.log(lcT) + (Math.log(this.lowcut) - Math.log(lcT)) * kb);
    if (Math.abs(this.lowcut - lcT) < 1e-3) this.lowcut = lcT;
    if (this.tone !== this.toneSig) { this.toneSig = this.tone; rbj(this.cTone, 'lp', C.toneHz * Math.pow(C.toneRange, this.tone / 100), sr); }
    if (this.lowcut !== this.lcSig) { this.lcSig = this.lowcut; rbj(this.cLc, 'hp', Math.max(C.lowCutMin, this.lowcut), sr); }
    // LOW CUT ≤ 25 Гц — обход: доля фильтра плавно 0 ↔ 1 (за 20 мс).
    const lcW0 = this.lcW, lcW1 = this.lowcut > C.lowCutOff ? 1 : 0;
    this.lcW = lcW0 + (lcW1 - lcW0) * (1 - kb);
    if (Math.abs(this.lcW - lcW1) < 1e-4) this.lcW = lcW1;

    // Покой: на входе тишина дольше idleMs — выход нули (сглаживания доходят до целей сразу).
    let peak = 0;
    for (let k = 0; k < (inp ? inp.length : 0); k++) { const a = inp[k]; for (let i = 0; i < n; i++) { const v = a[i] < 0 ? -a[i] : a[i]; if (v > peak) peak = v; } }
    this.silent = peak < C.idleLevel ? this.silent + n : 0;
    if (this.silent > (C.idleMs / 1000) * sr) {
      for (const o of out) o.fill(0);
      this.drive = driveT;
      if (this.fade < 1) this.fade = 1;
      this.report(t0, n);
      return true;
    }
    const ks = this.kSmooth, kDc = this.kDc, cLc = this.cLc, cTone = this.cTone, tiny = C.tiny;
    let bad = false;
    for (let i = 0; i < n; i++) {
      this.drive = driveT + (this.drive - driveT) * ks;
      if (this.fade < 1) this.fade = Math.min(1, this.fade + this.fadeStep);
      const D = this.drive / 100;
      const dB = C.driveDb * D;
      const g = Math.exp(dB * 0.11512925464970229); // 10^(dB/20)
      const ci = dB / C.compStepDb, i0 = Math.floor(ci), fr = ci - i0;
      const ta = this.prev, tb = this.cur;
      const wb = this.fade, wa = ta === tb ? 0 : 1 - wb;
      const ka = ta === CRUSH ? 1 : COMP[ta][i0] + (COMP[ta][i0 + 1] - COMP[ta][i0]) * fr;
      const kB = tb === CRUSH ? 1 : COMP[tb][i0] + (COMP[tb][i0 + 1] - COMP[tb][i0]) * fr;
      const osNeeded = (wa > 0 && ta !== CRUSH) || (wb > 0 && tb !== CRUSH);
      const crW = (ta === CRUSH ? wa : 0) + (tb === CRUSH ? wb : 0);
      // CRUSH: шаг квантования 2^(1 − B), B = 12 − 9·D; повтор N = 1 + round(15·D²).
      const step = Math.pow(2, 1 - (C.crushBitsMax - (C.crushBitsMax - C.crushBitsMin) * D));
      const holdN = 1 + Math.round((C.crushHoldMax - 1) * D * D);
      const lcw = lcW0 + (this.lcW - lcW0) * ((i + 1) / n);
      for (let k = 0; k < 2; k++) {
        const c = this.ch[k];
        const src = inp && (inp[k] || inp[0]);
        let x = src ? src[i] : 0;
        // LOW CUT (до искажения).
        const xl = bq(c.lc, cLc, x);
        x += (xl - x) * lcw;
        let y = osNeeded ? this.wet(c, x * g, ta, tb, wa, wb, ka, kB) : 0;
        if (!osNeeded) { // история оверсэмплера идёт дальше — вход в него потом без скачка
          const hp = c.hpos; c.hist[hp] = c.hist[hp + PHASE_LEN] = x * g; c.hpos = hp + 1 === PHASE_LEN ? 0 : hp + 1;
        }
        // CRUSH — на входе, задержанном на задержку оверсэмплинга (выравнивание при кроссфейде TYPE).
        const dp = c.cdp;
        const xd = c.cd[dp];
        c.cd[dp] = x;
        c.cdp = dp + 1 === OS_DELAY ? 0 : dp + 1;
        if (crW > 0) {
          if (c.holdN <= 0) {
            let q = step * Math.round(xd / step);
            if (q > 1 - step) q = 1 - step; else if (q < -1) q = -1;
            c.hold = q;
            c.holdN = holdN;
          }
          c.holdN--;
          y += crW * c.hold;
        } else c.holdN = 0;
        // Фильтр DC (HP 1-го порядка 5 Гц), TONE.
        const hpY = kDc * (c.dcY + y - c.dcX) + tiny;
        c.dcX = y;
        c.dcY = hpY;
        y = bq(c.tone, cTone, hpY);
        const o = out[k] || out[0];
        o[i] = y;
        if (!(y === y) || Math.abs(y) > 1e6) bad = true;
        if (!out[1]) break;
      }
    }
    if (bad) {
      // NaN или разнос — тишина и сброс состояний.
      this.ch = [new Channel(), new Channel()];
      for (const o of out) o.fill(0);
    }
    this.report(t0, n);
    return true;
  }

  /** Нагрузка: раз в ~0,5 с доля времени, ушедшая на расчёт. */
  report(t0, n) {
    this.busy += Date.now() - t0;
    this.frames += n;
    if (this.frames >= this.sr / 2) {
      this.port.postMessage({ cpu: this.busy / ((this.frames / this.sr) * 1000) });
      this.busy = 0;
      this.frames = 0;
    }
  }
}

registerProcessor('drive', DriveProcessor);
