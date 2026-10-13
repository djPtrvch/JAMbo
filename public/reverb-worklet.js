// Реверб (этап 7): гибрид пластины и зала. Стерео вход и выход.
// Цепь: вход (L, R) → LOW CUT (HPF 2-го порядка) → HIGH CUT (LPF 14 кГц) → пред-задержка →
// входная диффузия (4 all-pass на канал, схема Даттерро) → FDN из 8 линий (L — в линии 0, 2, 4, 6;
// R — в 1, 3, 5, 7; матрица Хаусхолдера; в каждой линии — усиление затухания и НЧ-демпфирование по Жо,
// длины качаются медленными LFO) → выход; ранние отражения — 12 отводов на канал после пред-задержки.
// TONE — время затухания высоких (на 8 кГц — DECAY × r) и полка 6 кГц ±4 дБ на выходе.
// Параметры — AudioParam (k-rate): size, decay, tone, lowcut, predelay; внутри сглаживаются (DECAY, TONE,
// LOW CUT — 50 мс; SIZE — длины линий скользят за 150 мс). Состояние — только в инстансе: узлов может быть
// сколько угодно (общий реверб на шине или на каждой дорожке).
// Раз в ~0,5 с узел присылает { cpu: доля времени, ушедшая на расчёт }.

// ---------- Константы (одно место; позже — на вторую страницу или SHIFT) ----------
const REVERB_CONST = {
  /** Диффузия 0..1: множитель коэффициентов входных all-pass (0.7 — коэффициенты Даттерро как есть). */
  diffusion: 0.7,
  /** Модуляция 0..1: глубина качания длин линий (30 % — 6 сэмплов при 48 кГц). */
  modulation: 0.3,
  /** Глубина модуляции при 100 %, сэмплов (48 кГц). */
  modDepthMax: 20,
  /** Частоты LFO линий, Гц (у каждой своя, фаза случайная). */
  modRates: [0.1, 0.21, 0.33, 0.44, 0.56, 0.67, 0.79, 0.9],
  /** Ранние отражения: доля в выходе. */
  early: 0.4,
  /** Ширина стерео 0..1 (1 — как есть). */
  width: 1,
  /** HIGH CUT на входе, Гц. */
  highCutHz: 14000,
  /** Уровень возврата, dB. */
  returnDb: 0,
  /** Длины линий FDN при 48 кГц (взаимно простые), умножаются на масштаб SIZE. */
  fdnLengths: [1123, 1361, 1597, 1823, 2063, 2297, 2539, 2803],
  /** Входная диффузия: длины all-pass при 48 кГц (L и R чуть разные) и коэффициенты Даттерро. */
  diffLensL: [229, 173, 611, 447],
  diffLensR: [241, 181, 593, 461],
  diffCoefs: [0.75, 0.75, 0.625, 0.625],
  /** Ранние отражения: времена отводов, мс (× масштаб SIZE), L и R. */
  erTimesL: [3.1, 5.3, 7.9, 10.7, 13.3, 16.9, 19.7, 23.3, 27.1, 31.3, 35.9, 41.0],
  erTimesR: [3.7, 4.9, 8.6, 11.3, 14.1, 15.8, 20.6, 24.2, 26.3, 32.8, 34.7, 43.1],
  /** Пред-задержка от SIZE: 4 + 0.22 × SIZE мс. */
  preBaseMs: 4,
  prePerSize: 0.22,
  /** Масштаб длин от SIZE: 0.35 + 1.65 × SIZE/100. */
  scaleMin: 0.35,
  scaleRange: 1.65,
  /** TONE → r (время затухания на 8 кГц = DECAY × r): −100 → 0.12, 0 → 0.5, +100 → 1. */
  toneR: [0.12, 0.5, 1],
  dampHz: 8000,
  /** Полка на выходе: 6 кГц, ±4 dB на краях TONE. */
  shelfHz: 6000,
  shelfDb: 4,
  /** Сглаживание DECAY, TONE, LOW CUT и пред-задержки (время установления), мс; SIZE — скольжение длин. */
  smoothMs: 50,
  sizeGlideMs: 150,
  /** Выходной уровень хвоста (подобран: шум на входе — хвост около −6 dB к входу при DECAY 2 с). */
  lateGain: 0.35,
  /** Защита от денормалей. */
  tiny: 1e-18,
  /** Наибольшая пред-задержка, мс (от SIZE до 26 + дополнительная до 200). */
  maxPreMs: 240,
};

const C = REVERB_CONST;
const N = 8;

/** Время установления T (до ~95 %) → коэффициент однополюсного сглаживания за n сэмплов. */
const glide = (ms, n, sr) => 1 - Math.exp((-3 * n) / ((ms / 1000) * sr));
const pow2 = (n) => { let p = 1; while (p < n) p <<= 1; return p; };

/** Коэффициенты биквада (RBJ): type 'hp' | 'lp' | 'hs' (high shelf, S = 1). Пишет в out [b0, b1, b2, a1, a2]. */
function biquad(out, type, f, sr, gainDb = 0) {
  const w = (2 * Math.PI * Math.min(f, sr * 0.45)) / sr;
  const cw = Math.cos(w);
  const sw = Math.sin(w);
  let b0, b1, b2, a0, a1, a2;
  if (type === 'hs') {
    const A = Math.pow(10, gainDb / 40);
    const al = (sw / 2) * Math.SQRT2;
    const s = 2 * Math.sqrt(A) * al;
    b0 = A * ((A + 1) + (A - 1) * cw + s);
    b1 = -2 * A * ((A - 1) + (A + 1) * cw);
    b2 = A * ((A + 1) + (A - 1) * cw - s);
    a0 = (A + 1) - (A - 1) * cw + s;
    a1 = 2 * ((A - 1) - (A + 1) * cw);
    a2 = (A + 1) - (A - 1) * cw - s;
  } else {
    const al = sw / (2 * Math.SQRT1_2);
    a0 = 1 + al;
    a1 = -2 * cw;
    a2 = 1 - al;
    if (type === 'hp') { b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2; }
    else { b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2; }
  }
  out[0] = b0 / a0; out[1] = b1 / a0; out[2] = b2 / a0; out[3] = a1 / a0; out[4] = a2 / a0;
}

/** Состояние биквада на 2 канала: [x1, x2, y1, y2] × 2. */
const bq = (k, z, o, x) => {
  const y = k[0] * x + k[1] * z[o] + k[2] * z[o + 1] - k[3] * z[o + 2] - k[4] * z[o + 3];
  z[o + 1] = z[o]; z[o] = x; z[o + 3] = z[o + 2]; z[o + 2] = y;
  return y;
};

class ReverbProcessor extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [
      { name: 'size', defaultValue: 50, minValue: 0, maxValue: 100, automationRate: 'k-rate' },
      { name: 'decay', defaultValue: 2, minValue: 0.1, maxValue: 20, automationRate: 'k-rate' },
      { name: 'tone', defaultValue: 0, minValue: -100, maxValue: 100, automationRate: 'k-rate' },
      { name: 'lowcut', defaultValue: 20, minValue: 20, maxValue: 2000, automationRate: 'k-rate' },
      { name: 'predelay', defaultValue: 0, minValue: 0, maxValue: 200, automationRate: 'k-rate' },
    ];
  }

  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.k = sr / 48000;
    // Сглаженные значения (первый блок берёт цели сразу).
    this.started = false;
    this.size = 50; this.decay = 2; this.tone = 0; this.lowcut = 20; this.pre = 0;
    this.scale = this.scaleOf(50);
    // Фильтры входа и выхода.
    this.kHp = new Float64Array(5); this.zHp = new Float64Array(8);
    this.kLp = new Float64Array(5); this.zLp = new Float64Array(8);
    this.kSh = new Float64Array(5); this.zSh = new Float64Array(8);
    biquad(this.kLp, 'lp', C.highCutHz, sr);
    this.coefSig = '';
    // Пред-задержка (L, R).
    this.preLen = pow2(Math.ceil((C.maxPreMs / 1000) * sr) + 8);
    this.preL = new Float32Array(this.preLen);
    this.preR = new Float32Array(this.preLen);
    this.preW = 0;
    // Ранние отражения читают из той же пред-задержки: буфер с запасом на отводы (до 43 мс × 2).
    this.erLen = pow2(Math.ceil(0.1 * sr) + 8);
    this.erL = new Float32Array(this.erLen);
    this.erR = new Float32Array(this.erLen);
    this.erW = 0;
    // Отводы: знаки чередуются, усиления спадают; сумма модулей — 1.
    const g = C.erTimesL.map((_, i) => Math.pow(0.85, i) * (i % 2 ? -1 : 1));
    const sum = g.reduce((a, b) => a + Math.abs(b), 0);
    this.erGain = new Float32Array(g.map((x) => x / sum));
    // Входная диффузия: all-pass на канал.
    this.apL = C.diffLensL.map((l) => this.allpass(Math.round(l * this.k)));
    this.apR = C.diffLensR.map((l) => this.allpass(Math.round(l * this.k)));
    this.apG = new Float32Array(C.diffCoefs.map((c) => Math.min(0.95, (c * C.diffusion) / 0.7)));
    // FDN: линии с запасом на SIZE 100 % и модуляцию.
    const maxLen = Math.max(...C.fdnLengths) * (C.scaleMin + C.scaleRange) * this.k + C.modDepthMax * this.k + 16;
    this.lineSize = pow2(Math.ceil(maxLen));
    this.mask = this.lineSize - 1;
    this.lines = Array.from({ length: N }, () => new Float32Array(this.lineSize));
    this.w = 0;
    this.base = new Float64Array(C.fdnLengths.map((l) => l * this.k));
    this.gain = new Float64Array(N);
    this.damp = new Float64Array(N);
    this.lp = new Float64Array(N);
    this.rd = new Float64Array(N);
    this.v = new Float64Array(N);
    // LFO линий: вращающийся вектор (sin, cos) — без тригонометрии на сэмпле.
    this.ms = new Float64Array(N);
    this.mc = new Float64Array(N);
    this.mr = new Float64Array(N); // cos шага
    this.mi = new Float64Array(N); // sin шага
    for (let i = 0; i < N; i++) {
      const ph = Math.random() * 2 * Math.PI;
      this.ms[i] = Math.sin(ph); this.mc[i] = Math.cos(ph);
      const w = (2 * Math.PI * C.modRates[i]) / sr;
      this.mr[i] = Math.cos(w); this.mi[i] = Math.sin(w);
    }
    this.modDepth = C.modulation * C.modDepthMax * this.k;
    this.ret = Math.pow(10, C.returnDb / 20);
    // Нагрузка.
    this.busy = 0;
    this.frames = 0;
  }

  allpass(len) {
    const size = pow2(len + 1);
    return { buf: new Float32Array(size), mask: size - 1, len, w: 0 };
  }

  scaleOf(size) { return C.scaleMin + C.scaleRange * (size / 100); }

  /** r по TONE: −100 → 0.12, 0 → 0.5, +100 → 1 (по логарифму). */
  toneR(t) {
    const [lo, mid, hi] = C.toneR;
    const u = Math.max(-1, Math.min(1, t / 100));
    return u < 0 ? Math.exp(Math.log(mid) + (Math.log(mid) - Math.log(lo)) * u) : Math.exp(Math.log(mid) + (Math.log(hi) - Math.log(mid)) * u);
  }

  /** Усиления затухания и демпфирование линий по нынешним DECAY, TONE и длинам (формула Жо). */
  updateLoop() {
    const sr = this.sr;
    const r = this.toneR(this.tone);
    const c = Math.cos((2 * Math.PI * C.dampHz) / sr);
    for (let i = 0; i < N; i++) {
      const L = this.base[i] * this.scale;
      const g = Math.pow(10, (-3 * L) / (sr * this.decay));
      const gHf = Math.pow(10, (-3 * L) / (sr * this.decay * r));
      this.gain[i] = Math.min(0.9995, g);
      // Однополюсный НЧ (DC — 1): |H(8 кГц)| = gHf / g.
      const k2 = Math.min(1, gHf / g) ** 2;
      if (k2 >= 0.999999) { this.damp[i] = 0; continue; }
      const p = 1 - k2 * c;
      const q = 1 - k2;
      this.damp[i] = Math.max(0, Math.min(0.999, (p - Math.sqrt(Math.max(0, p * p - q * q))) / q));
    }
  }

  /** Коэффициенты LOW CUT и полки TONE — при изменении. */
  updateFilters() {
    const sig = `${Math.round(this.lowcut * 10)}|${Math.round(this.tone * 10)}`;
    if (sig === this.coefSig) return;
    this.coefSig = sig;
    biquad(this.kHp, 'hp', this.lowcut, this.sr);
    biquad(this.kSh, 'hs', C.shelfHz, this.sr, (C.shelfDb * this.tone) / 100);
  }

  reset() {
    for (const a of [this.preL, this.preR, this.erL, this.erR, ...this.lines]) a.fill(0);
    for (const ap of [...this.apL, ...this.apR]) ap.buf.fill(0);
    for (const z of [this.zHp, this.zLp, this.zSh, this.lp]) z.fill(0);
  }

  process(inputs, outputs, params) {
    const out = outputs[0];
    const oL = out[0];
    const oR = out[1] ?? out[0];
    const n = oL.length;
    const inp = inputs[0];
    const iL = inp && inp[0];
    const iR = inp && (inp[1] ?? inp[0]);
    const t0 = Date.now();
    const sr = this.sr;

    // Цели и сглаживание (DECAY, TONE, LOW CUT, пред-задержка — 50 мс; SIZE — 150 мс, по сэмплам).
    const tSize = params.size[0], tDecay = params.decay[0], tTone = params.tone[0], tLow = params.lowcut[0], tPre = params.predelay[0];
    if (!this.started) {
      this.started = true;
      this.size = tSize; this.decay = tDecay; this.tone = tTone; this.lowcut = tLow; this.pre = tPre;
      this.scale = this.scaleOf(tSize);
    }
    const a = glide(C.smoothMs, n, sr);
    this.decay += (tDecay - this.decay) * a;
    this.tone += (tTone - this.tone) * a;
    // LOW CUT — по логарифму частоты.
    this.lowcut = Math.exp(Math.log(this.lowcut) + (Math.log(tLow) - Math.log(this.lowcut)) * a);
    const pre0 = this.preMs ?? C.preBaseMs + C.prePerSize * tSize + tPre;
    const pre1 = pre0 + (C.preBaseMs + C.prePerSize * tSize + tPre - pre0) * a;
    this.preMs = pre1;
    const scale0 = this.scale;
    const scale1 = scale0 + (this.scaleOf(tSize) - scale0) * glide(C.sizeGlideMs, n, sr);
    this.scale = scale1;
    this.updateFilters();
    this.updateLoop();

    const lines = this.lines, mask = this.mask, base = this.base, gain = this.gain, damp = this.damp, lp = this.lp, rd = this.rd, v = this.v;
    const ms = this.ms, mc = this.mc, mr = this.mr, mi = this.mi, depth = this.modDepth;
    const preMask = this.preLen - 1, erMask = this.erLen - 1;
    const kHp = this.kHp, zHp = this.zHp, kLp = this.kLp, zLp = this.zLp, kSh = this.kSh, zSh = this.zSh;
    const erG = this.erGain, erTL = C.erTimesL, erTR = C.erTimesR;
    const apL = this.apL, apR = this.apR, apG = this.apG;
    const lateGain = C.lateGain, early = C.early, width = C.width, ret = this.ret, tiny = C.tiny;
    let w = this.w, pw = this.preW, ew = this.erW;
    let bad = false;

    for (let s = 0; s < n; s++) {
      const f = (s + 1) / n;
      const scale = scale0 + (scale1 - scale0) * f;
      // Вход: LOW CUT → HIGH CUT.
      let xl = iL ? iL[s] : 0;
      let xr = iR ? iR[s] : 0;
      xl = bq(kLp, zLp, 0, bq(kHp, zHp, 0, xl));
      xr = bq(kLp, zLp, 4, bq(kHp, zHp, 4, xr));
      // Пред-задержка (дробное чтение, линейно).
      this.preL[pw] = xl; this.preR[pw] = xr;
      const pd = Math.max(1, (pre1 / 1000) * sr);
      const pp = pw - pd + this.preLen * 2;
      const pi = Math.floor(pp), pf = pp - pi;
      const dl = this.preL[pi & preMask] + (this.preL[(pi + 1) & preMask] - this.preL[pi & preMask]) * pf;
      const dr = this.preR[pi & preMask] + (this.preR[(pi + 1) & preMask] - this.preR[pi & preMask]) * pf;
      pw = (pw + 1) & preMask;
      // Ранние отражения: отводы после пред-задержки, времена × масштаб SIZE.
      this.erL[ew] = dl; this.erR[ew] = dr;
      let el = 0, er = 0;
      const ems = (sr / 1000) * scale;
      for (let t = 0; t < 12; t++) {
        const ql = ew - erTL[t] * ems + this.erLen * 2;
        const qi = Math.floor(ql), qf = ql - qi;
        const a0 = this.erL[qi & erMask];
        el += erG[t] * (a0 + (this.erL[(qi + 1) & erMask] - a0) * qf);
        const qr = ew - erTR[t] * ems + this.erLen * 2;
        const ri = Math.floor(qr), rf = qr - ri;
        const b0 = this.erR[ri & erMask];
        er += erG[t] * (b0 + (this.erR[(ri + 1) & erMask] - b0) * rf);
      }
      ew = (ew + 1) & erMask;
      // Входная диффузия: 4 all-pass на канал.
      let ul = dl, ur = dr;
      for (let k = 0; k < 4; k++) {
        const g = apG[k];
        let ap = apL[k];
        let o = ap.buf[(ap.w - ap.len) & ap.mask];
        let x = ul + g * o;
        ul = o - g * x;
        ap.buf[ap.w] = x; ap.w = (ap.w + 1) & ap.mask;
        ap = apR[k];
        o = ap.buf[(ap.w - ap.len) & ap.mask];
        x = ur + g * o;
        ur = o - g * x;
        ap.buf[ap.w] = x; ap.w = (ap.w + 1) & ap.mask;
      }
      // FDN: чтение с модуляцией (кубическая интерполяция), демпфирование, затухание.
      let sum = 0;
      for (let i = 0; i < N; i++) {
        // LFO: поворот вектора.
        const sn = ms[i] * mr[i] + mc[i] * mi[i];
        mc[i] = mc[i] * mr[i] - ms[i] * mi[i];
        ms[i] = sn;
        const d = base[i] * scale + depth * sn;
        const pos = w - d + lines[i].length * 2;
        const ip = Math.floor(pos), fr = pos - ip;
        const L = lines[i];
        const y0 = L[(ip - 1) & mask], y1 = L[ip & mask], y2 = L[(ip + 1) & mask], y3 = L[(ip + 2) & mask];
        // Кубический Эрмит.
        const c1 = 0.5 * (y2 - y0);
        const c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3;
        const c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
        const val = ((c3 * fr + c2) * fr + c1) * fr + y1;
        rd[i] = val;
        lp[i] = val + damp[i] * (lp[i] - val);
        v[i] = lp[i] * gain[i];
        sum += v[i];
      }
      // Хаусхолдер: y = x − (2/8)·Σx; вход: L — в чётные линии, R — в нечётные.
      const h = sum * 0.25;
      const inL = ul * 0.5, inR = ur * 0.5;
      for (let i = 0; i < N; i++) lines[i][w] = v[i] - h + (i & 1 ? inR : inL) + tiny;
      w = (w + 1) & mask;
      // Выход: хвост (чётные линии — L, нечётные — R, знаки чередуются) + ранние отражения.
      let yl = (rd[0] - rd[2] + rd[4] - rd[6]) * lateGain + el * early;
      let yr = (rd[1] - rd[3] + rd[5] - rd[7]) * lateGain + er * early;
      // Полка TONE (6 кГц), ширина, возврат.
      yl = bq(kSh, zSh, 0, yl);
      yr = bq(kSh, zSh, 4, yr);
      if (width !== 1) {
        const m = (yl + yr) * 0.5, sd = (yl - yr) * 0.5 * width;
        yl = m + sd; yr = m - sd;
      }
      oL[s] = yl * ret;
      if (oR !== oL) oR[s] = yr * ret;
      if (!(yl === yl && yr === yr) || Math.abs(yl) > 1e6) bad = true;
    }
    this.w = w; this.preW = pw; this.erW = ew;
    // NaN или разнос — сброс состояния (тишина вместо шума).
    if (bad) { this.reset(); oL.fill(0); if (oR !== oL) oR.fill(0); }

    this.busy += Date.now() - t0;
    this.frames += n;
    if (this.frames >= sr / 2) {
      this.port.postMessage({ cpu: this.busy / ((this.frames / sr) * 1000) });
      this.busy = 0;
      this.frames = 0;
    }
    return true;
  }
}

registerProcessor('reverb', ReverbProcessor);
