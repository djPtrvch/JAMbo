// Delay (этап 7): ленточный стерео-дилей. Стерео вход, стерео выход; шина отдаёт только эхо (wet).
// Две кольцевые линии L и R (чтение — кубический Эрмит). Время L = TIME, R = TIME · (1 + o); время каждой
// линии скользит к цели (однополюсно, 80 мс) — смена TIME и темпа даёт ленточный питч-нырок без щелчков.
// SPREAD: до 50 % разносит время правой линии (o), дальше — перекрёстная связь c до классического ping-pong.
// Выход каждой линии: HP 60 Гц (всегда) → FILTER (LP и HP 2-го порядка последовательно, фильтры с переменной
// состоянием TPT — устойчивы к быстрой смене частоты: влево от центра LP опускается от 20 кГц, вправо HP
// поднимается от 20 Гц; около центра (|f| < 0.02) фильтр плавно подмешивается к прямому сигналу — в центре
// прозрачен, без переключений и щелчков при переходе через центр) → в выход; в обратную связь —
// ещё мягкая сатурация tanh(k·x)/k. Фильтр стоит на каждом повторе, включая первый, и накапливается.
// Модуляция «лента»: wow (случайное блуждание 0,5 Гц) и flutter (7 Гц), у каждой линии свои фазы.
// Параметры — AudioParam (k-rate): time (с), feedback (0..1), filter (−1..1), spread (0..1);
// FEEDBACK, FILTER, SPREAD сглаживаются за 20 мс. Состояние — только в инстансе (узлов может быть сколько
// угодно: общий дилей на шине или на каждой дорожке). Раз в ~0,5 с узел присылает { cpu }.

// ---------- Константы (одно место) ----------
const DELAY_CONST = {
  /** High-pass в петле (всегда), Гц. */
  loopHpHz: 60,
  /** Сатурация в обратной связи: tanh(k·x)/k. */
  satK: 1.2,
  /** Wow: случайное блуждание с частотой смены цели, Гц, и глубиной, мс. */
  wowHz: 0.5,
  wowMs: 0.2,
  /** Flutter: синус, Гц, и глубина, мс. */
  flutterHz: 7,
  flutterMs: 0.03,
  /** Скольжение времени линий (постоянная однополюсного сглаживания), мс. */
  glideMs: 80,
  /** Наибольшая скорость скольжения, сэмплов задержки на сэмпл: скорость чтения 0.25…1.75 (≈ −2 и +1 октавы
   *  на пике нырка) — большие смены (1/32 → 1 bar) скользят дольше 80 мс, без скачков. */
  glideMax: 0.75,
  /** Сглаживание FEEDBACK, FILTER, SPREAD (время установления), мс. */
  smoothMs: 20,
  /** FILTER: LP от 20 кГц (центр) до 500 Гц (−100 %), HP от 20 Гц (центр) до 1500 Гц (+100 %). */
  lpMaxHz: 20000,
  lpMinHz: 500,
  hpMinHz: 20,
  hpMaxHz: 1500,
  /** |FILTER| меньше — фильтр подмешивается к прямому сигналу (в центре — обход). */
  filterOff: 0.02,
  /** Запас длины правой линии (до +50 %). */
  spreadMax: 0.5,
  /** Наибольшее время по умолчанию, с (если узел не получил maxTime): 1 такт при 40 BPM. */
  maxTime: 6,
  /** Защита от денормалей. */
  tiny: 1e-18,
};

const C = DELAY_CONST;
const pow2 = (n) => { let p = 1; while (p < n) p <<= 1; return p; };
/** Время установления T (до ~95 %) → коэффициент однополюсного сглаживания за n сэмплов. */
const glide = (ms, n, sr) => 1 - Math.exp((-3 * n) / ((ms / 1000) * sr));

/** Коэффициенты биквада (RBJ, Q = 1/√2): 'hp' | 'lp'. Пишет в out [b0, b1, b2, a1, a2]. */
function biquad(out, type, f, sr) {
  const w = (2 * Math.PI * Math.min(f, sr * 0.45)) / sr;
  const cw = Math.cos(w);
  const al = Math.sin(w) / (2 * Math.SQRT1_2);
  const a0 = 1 + al;
  let b0, b1;
  if (type === 'hp') { b0 = (1 + cw) / 2; b1 = -(1 + cw); }
  else { b0 = (1 - cw) / 2; b1 = 1 - cw; }
  out[0] = b0 / a0; out[1] = b1 / a0; out[2] = b0 / a0; out[3] = (-2 * cw) / a0; out[4] = (1 - al) / a0;
}

/** Биквад (прямая форма I — устойчива к смене коэффициентов на ходу); z — [x1, x2, y1, y2] с отступа o. */
const bq = (k, z, o, x) => {
  const y = k[0] * x + k[1] * z[o] + k[2] * z[o + 1] - k[3] * z[o + 2] - k[4] * z[o + 3];
  z[o + 1] = z[o]; z[o] = x; z[o + 3] = z[o + 2]; z[o + 2] = y;
  return y;
};

/** SVF (TPT, Заваличин) на частоте f, Q = 1/√2: коэффициенты [a1, a2, a3] в c. */
function svf(c, f, sr) {
  const g = Math.tan((Math.PI * Math.min(f, sr * 0.49)) / sr);
  const k = Math.SQRT2;
  c[0] = 1 / (1 + g * (g + k)); c[1] = g * c[0]; c[2] = g * c[1];
}
/** Шаг SVF: s — [ic1, ic2] с отступа o; LP-выход. */
const svfLp = (c, s, o, x) => {
  const v3 = x - s[o + 1], v1 = c[0] * s[o] + c[1] * v3, v2 = s[o + 1] + c[1] * s[o] + c[2] * v3;
  s[o] = 2 * v1 - s[o]; s[o + 1] = 2 * v2 - s[o + 1];
  return v2;
};
/** Шаг SVF: HP-выход (x − k·band − low). */
const svfHp = (c, s, o, x) => {
  const v3 = x - s[o + 1], v1 = c[0] * s[o] + c[1] * v3, v2 = s[o + 1] + c[1] * s[o] + c[2] * v3;
  s[o] = 2 * v1 - s[o]; s[o + 1] = 2 * v2 - s[o + 1];
  return x - Math.SQRT2 * v1 - v2;
};

class DelayProcessor extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [
      { name: 'time', defaultValue: 0.25, minValue: 0.001, maxValue: 60, automationRate: 'k-rate' },
      { name: 'feedback', defaultValue: 0.4, minValue: 0, maxValue: 1, automationRate: 'k-rate' },
      { name: 'filter', defaultValue: 0, minValue: -1, maxValue: 1, automationRate: 'k-rate' },
      { name: 'spread', defaultValue: 0, minValue: 0, maxValue: 1, automationRate: 'k-rate' },
    ];
  }

  constructor(options) {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.maxTime = options?.processorOptions?.maxTime ?? C.maxTime;
    // Линии: 1 такт при наименьшем темпе × (1 + запас SPREAD) + модуляция и интерполяция.
    const len = pow2(Math.ceil(this.maxTime * (1 + C.spreadMax) * sr + ((C.wowMs + C.flutterMs) / 1000) * sr + 8));
    this.len = len;
    this.mask = len - 1;
    this.lineL = new Float32Array(len);
    this.lineR = new Float32Array(len);
    this.w = 0;
    // Время линий в сэмплах (скользит к цели); первый блок берёт цель сразу.
    this.dL = 0; this.dR = 0;
    this.started = false;
    this.fb = 0.4; this.filter = 0; this.spread = 0;
    // Фильтры: HP 60 Гц в петле и FILTER, по каналу L (0) и R (4).
    this.kHp = new Float64Array(5);
    biquad(this.kHp, 'hp', C.loopHpHz, sr);
    this.zHp = new Float64Array(8);
    // FILTER: SVF (TPT) — коэффициенты LP и HP [a1, a2, a3], состояния [ic1, ic2] × канал (L 0, R 2).
    this.cLp = new Float64Array(3);
    this.cHp = new Float64Array(3);
    this.sLp = new Float64Array(4);
    this.sHp = new Float64Array(4);
    this.wLp = 0; this.wHp = 0;
    this.fSig = NaN;
    // Модуляция: wow — случайное блуждание (косинусная интерполяция между случайными целями), flutter — синус.
    this.wowPh = new Float64Array([Math.random(), Math.random()]);
    this.wowA = new Float64Array([Math.random() * 2 - 1, Math.random() * 2 - 1]);
    this.wowB = new Float64Array([Math.random() * 2 - 1, Math.random() * 2 - 1]);
    const fw = (2 * Math.PI * C.flutterHz) / sr;
    this.flR = Math.cos(fw); this.flI = Math.sin(fw);
    const p0 = Math.random() * 2 * Math.PI, p1 = Math.random() * 2 * Math.PI;
    this.flS = new Float64Array([Math.sin(p0), Math.sin(p1)]);
    this.flC = new Float64Array([Math.cos(p0), Math.cos(p1)]);
    // Нагрузка.
    this.busy = 0;
    this.frames = 0;
  }

  /** Коэффициенты FILTER по f ∈ −1..1: LP — от 20 кГц вниз при f < 0, HP — от 20 Гц вверх при f > 0. */
  updateFilter(f) {
    if (f === this.fSig) return;
    this.fSig = f;
    const lp = f < 0 ? C.lpMaxHz * Math.pow(C.lpMinHz / C.lpMaxHz, -f) : C.lpMaxHz;
    const hp = f > 0 ? C.hpMinHz * Math.pow(C.hpMaxHz / C.hpMinHz, f) : C.hpMinHz;
    svf(this.cLp, lp, this.sr);
    svf(this.cHp, hp, this.sr);
  }

  reset() {
    this.lineL.fill(0); this.lineR.fill(0);
    this.zHp.fill(0); this.sLp.fill(0); this.sHp.fill(0);
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

    // Цели: время (с, не больше наибольшего), FEEDBACK, FILTER, SPREAD.
    const tTime = Math.min(this.maxTime, Math.max(0.001, params.time[0]));
    const tFb = Math.min(1, Math.max(0, params.feedback[0]));
    const tFilter = Math.min(1, Math.max(-1, params.filter[0]));
    const tSpread = Math.min(1, Math.max(0, params.spread[0]));
    if (!this.started) {
      this.started = true;
      this.fb = tFb; this.filter = tFilter; this.spread = tSpread;
    }
    const a = glide(C.smoothMs, n, sr);
    const fb0 = this.fb, fb1 = fb0 + (tFb - fb0) * a;
    this.fb = fb1;
    this.filter += (tFilter - this.filter) * a;
    if (Math.abs(this.filter - tFilter) < 1e-4) this.filter = tFilter;
    const sp0 = this.spread, sp1 = sp0 + (tSpread - sp0) * a;
    this.spread = sp1;
    this.updateFilter(this.filter);
    // Доля фильтра: у центра подмешивается плавно (по сэмплам внутри блока).
    const wLp0 = this.wLp, wLp1 = Math.min(1, Math.max(0, -this.filter / C.filterOff));
    const wHp0 = this.wHp, wHp1 = Math.min(1, Math.max(0, this.filter / C.filterOff));
    this.wLp = wLp1; this.wHp = wHp1;

    // SPREAD x: до 0.5 — разнос времени o = x, без перекрёстной связи; дальше c 0 → 1, o = 0.5·(1 − c).
    const cOf = (x) => (x > 0.5 ? (x - 0.5) / 0.5 : 0);
    const oOf = (x) => (x > 0.5 ? 0.5 * (1 - cOf(x)) : x);
    const c0 = cOf(sp0), c1 = cOf(sp1);
    const targL = tTime * sr;
    const targR = tTime * (1 + oOf(sp1)) * sr;
    if (this.dL === 0) { this.dL = targL; this.dR = targR; }
    const g = 1 - Math.exp(-1 / ((C.glideMs / 1000) * sr));
    const gm = C.glideMax;

    const lineL = this.lineL, lineR = this.lineR, mask = this.mask, len = this.len;
    const kHp = this.kHp, zHp = this.zHp, cLp = this.cLp, cHp = this.cHp, sLp = this.sLp, sHp = this.sHp;
    const k = C.satK, tiny = C.tiny;
    const wowAmp = (C.wowMs / 1000) * sr, flAmp = (C.flutterMs / 1000) * sr;
    const wowStep = C.wowHz / sr;
    const wowPh = this.wowPh, wowA = this.wowA, wowB = this.wowB, flS = this.flS, flC = this.flC, flR = this.flR, flI = this.flI;
    const maxD = len - 4;
    let w = this.w, dL = this.dL, dR = this.dR;
    let bad = false;

    for (let s = 0; s < n; s++) {
      const f = (s + 1) / n;
      const fb = fb0 + (fb1 - fb0) * f;
      const c = c0 + (c1 - c0) * f;
      let st = (targL - dL) * g;
      dL += st > gm ? gm : st < -gm ? -gm : st;
      st = (targR - dR) * g;
      dR += st > gm ? gm : st < -gm ? -gm : st;
      // Модуляция линий: wow (случайное блуждание) + flutter (синус).
      let mod0, mod1;
      {
        for (let ch = 0; ch < 2; ch++) {
          let ph = wowPh[ch] + wowStep;
          if (ph >= 1) { ph -= 1; wowA[ch] = wowB[ch]; wowB[ch] = Math.random() * 2 - 1; }
          wowPh[ch] = ph;
          const sn = flS[ch] * flR + flC[ch] * flI;
          flC[ch] = flC[ch] * flR - flS[ch] * flI;
          flS[ch] = sn;
        }
        const u0 = 0.5 - 0.5 * Math.cos(Math.PI * wowPh[0]);
        const u1 = 0.5 - 0.5 * Math.cos(Math.PI * wowPh[1]);
        mod0 = (wowA[0] + (wowB[0] - wowA[0]) * u0) * wowAmp + flS[0] * flAmp;
        mod1 = (wowA[1] + (wowB[1] - wowA[1]) * u1) * wowAmp + flS[1] * flAmp;
      }
      // Чтение линий (кубический Эрмит).
      let yL, yR;
      {
        const d = Math.min(maxD, Math.max(1, dL + mod0));
        const pos = w - d + len;
        const ip = Math.floor(pos), fr = pos - ip;
        const y0 = lineL[(ip - 1) & mask], y1 = lineL[ip & mask], y2 = lineL[(ip + 1) & mask], y3 = lineL[(ip + 2) & mask];
        const c1h = 0.5 * (y2 - y0), c2h = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3, c3h = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
        yL = ((c3h * fr + c2h) * fr + c1h) * fr + y1;
      }
      {
        const d = Math.min(maxD, Math.max(1, dR + mod1));
        const pos = w - d + len;
        const ip = Math.floor(pos), fr = pos - ip;
        const y0 = lineR[(ip - 1) & mask], y1 = lineR[ip & mask], y2 = lineR[(ip + 1) & mask], y3 = lineR[(ip + 2) & mask];
        const c1h = 0.5 * (y2 - y0), c2h = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3, c3h = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
        yR = ((c3h * fr + c2h) * fr + c1h) * fr + y1;
      }
      // Выход линий: HP 60 Гц → FILTER.
      yL = bq(kHp, zHp, 0, yL);
      yR = bq(kHp, zHp, 4, yR);
      {
        const wl = wLp0 + (wLp1 - wLp0) * f, wh = wHp0 + (wHp1 - wHp0) * f;
        let v = svfLp(cLp, sLp, 0, yL); yL += (v - yL) * wl;
        v = svfHp(cHp, sHp, 0, yL); yL += (v - yL) * wh;
        v = svfLp(cLp, sLp, 2, yR); yR += (v - yR) * wl;
        v = svfHp(cHp, sHp, 2, yR); yR += (v - yR) * wh;
      }
      // Обратная связь: мягкая сатурация, перекрёстная связь c.
      const sL = Math.tanh(k * yL) / k, sR = Math.tanh(k * yR) / k;
      // Вход: при c → 1 эхо входит только в левую линию (моно-сумма), правая получает его через обратную связь.
      const xl = iL ? iL[s] : 0, xr = iR ? iR[s] : 0;
      const m = (xl + xr) * 0.5;
      lineL[w] = (1 - c) * xl + c * m + fb * ((1 - c) * sL + c * sR) + tiny;
      lineR[w] = (1 - c) * xr + fb * ((1 - c) * sR + c * sL) + tiny;
      w = (w + 1) & mask;
      oL[s] = yL;
      if (oR !== oL) oR[s] = yR;
      if (!(yL === yL && yR === yR) || Math.abs(yL) > 1e6 || Math.abs(yR) > 1e6) bad = true;
    }
    this.w = w; this.dL = dL; this.dR = dR;
    // Денормали в состояниях фильтров.
    for (const z of [zHp, sLp, sHp]) for (let i = 0; i < z.length; i++) if (Math.abs(z[i]) < 1e-20) z[i] = 0;
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

registerProcessor('delay', DelayProcessor);
