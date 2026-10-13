// Компрессор мастер-шины «glue» (по мотивам Ableton Glue Compressor и FabFilter Pro-C 2).
// Стерео, нулевая задержка, без lookahead. Детектор stereo-linked: смесь пика и RMS (RMS приведён
// к пику синуса) по сигналу после high-pass 90 Hz; мягкое колено 6 dB; GR сглаживается в dB
// (Attack/Release с ручек, AUTO — два релиза: быстрый и медленный). Выход = вход · GR · Makeup.
// Параметры приходят сообщениями и сглаживаются за 20 ms; BYPASS — кроссфейд 10 ms.
// Для индикации ~60 раз в секунду уходит [пик входа, наибольший GR в dB, пик выхода].

// ---------- Константы (одно место) ----------
const KNEE_DB = 6;
const DETECT_HPF_HZ = 90;
const PEAK_WEIGHT = 0.6;
const RMS_WEIGHT = 0.4;
const RMS_MS = 10;
/** RMS синуса ниже его пика на 3 dB — приводим RMS к пику синуса. */
const RMS_CAL = Math.SQRT2;
/** Спад пикового детектора (держит пик между полупериодами). */
const PEAK_RELEASE_MS = 10;
const AUTO_FAST_MS = 60;
const AUTO_SLOW_MS = 1200;
const PARAM_SMOOTH_MS = 20;
const BYPASS_MS = 10;
const METER_HZ = 60;
/** Не даём состояниям уходить в денормалы. */
const TINY = 1e-25;

const coef = (ms, sr) => (ms <= 0 ? 0 : Math.exp(-1 / ((ms / 1000) * sr)));

class GlueProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    // Цели параметров (из сообщений) и их сглаженные значения.
    this.p = { thr: -10, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false };
    this.thr = -10;
    this.makeupDb = 0;
    this.slope = 0.5;
    this.wet = 1;
    this.kSmooth = coef(PARAM_SMOOTH_MS, sr);
    this.wetStep = 1 / ((BYPASS_MS / 1000) * sr);
    this.updateTimes();
    this.kPeak = coef(PEAK_RELEASE_MS, sr);
    this.kRms = coef(RMS_MS, sr);
    this.kAutoFast = coef(AUTO_FAST_MS, sr);
    this.kAutoSlow = coef(AUTO_SLOW_MS, sr);
    // High-pass 90 Hz (биквад Баттерворта) на каждом канале детектора.
    const w = (2 * Math.PI * DETECT_HPF_HZ) / sr;
    const cw = Math.cos(w);
    const al = Math.sin(w) / (2 * Math.SQRT1_2);
    const a0 = 1 + al;
    this.hb0 = (1 + cw) / 2 / a0;
    this.hb1 = -(1 + cw) / a0;
    this.hb2 = (1 + cw) / 2 / a0;
    this.ha1 = (-2 * cw) / a0;
    this.ha2 = (1 - al) / a0;
    this.hz = [0, 0, 0, 0, 0, 0, 0, 0]; // x1, x2, y1, y2 для L и R
    this.pk = 0;
    this.ms = 0;
    this.env = 0; // GR, dB (≥ 0)
    this.envSlow = 0;
    // Индикация.
    this.meterEvery = Math.max(128, Math.round(sr / METER_HZ));
    this.meterN = 0;
    this.mIn = 0;
    this.mGr = 0;
    this.mOut = 0;
    this.port.onmessage = (e) => {
      Object.assign(this.p, e.data);
      this.updateTimes();
    };
  }

  updateTimes() {
    this.kAtt = coef(this.p.att, this.sr);
    this.kRel = coef(this.p.rel, this.sr);
  }

  hp(x, o) {
    const z = this.hz;
    const y = this.hb0 * x + this.hb1 * z[o] + this.hb2 * z[o + 1] - this.ha1 * z[o + 2] - this.ha2 * z[o + 3] + TINY;
    z[o + 1] = z[o];
    z[o] = x;
    z[o + 3] = z[o + 2];
    z[o + 2] = y;
    return y;
  }

  process(inputs, outputs) {
    const inp = inputs[0];
    const out = outputs[0];
    const n = out[0].length;
    const inL = inp[0] || null;
    const inR = inp[1] || inL;
    const outL = out[0];
    const outR = out[1] || out[0];
    const p = this.p;
    const ks = this.kSmooth;
    const thrT = p.thr;
    const mkT = p.makeup;
    const slopeT = 1 - 1 / p.ratio;
    const wetT = p.bypass ? 0 : 1;
    const half = KNEE_DB / 2;
    for (let i = 0; i < n; i++) {
      const xl = inL ? inL[i] : 0;
      const xr = inR ? inR[i] : 0;
      // Сглаживание параметров (20 ms) и кроссфейд BYPASS (10 ms, линейно).
      this.thr = thrT + (this.thr - thrT) * ks;
      this.makeupDb = mkT + (this.makeupDb - mkT) * ks;
      this.slope = slopeT + (this.slope - slopeT) * ks;
      if (this.wet < wetT) this.wet = Math.min(wetT, this.wet + this.wetStep);
      else if (this.wet > wetT) this.wet = Math.max(wetT, this.wet - this.wetStep);
      // Детектор: high-pass, максимум из L/R, пик + RMS.
      const hl = this.hp(xl, 0);
      const hr = this.hp(xr, 4);
      const a = Math.max(Math.abs(hl), Math.abs(hr));
      this.pk = a > this.pk ? a : this.pk * this.kPeak + TINY;
      this.ms = a * a + (this.ms - a * a) * this.kRms + TINY;
      const level = PEAK_WEIGHT * this.pk + RMS_WEIGHT * Math.sqrt(this.ms) * RMS_CAL;
      const ldb = 20 * Math.log10(level + 1e-12);
      // Gain computer: мягкое колено 6 dB.
      const over = ldb - this.thr;
      let target = 0;
      if (over >= half) target = over * this.slope;
      else if (over > -half) target = (this.slope * (over + half) * (over + half)) / (2 * KNEE_DB);
      // Сглаживание GR в dB.
      if (p.auto) {
        // Быстрая часть: атака с ручки, релиз 60 ms; медленная копится при долгом сжатии и отпускает за 1.2 s.
        this.env = target > this.env ? target + (this.env - target) * this.kAtt : target + (this.env - target) * this.kAutoFast;
        this.envSlow = target + (this.envSlow - target) * this.kAutoSlow;
      } else {
        this.env = target + (this.env - target) * (target > this.env ? this.kAtt : this.kRel);
        this.envSlow = 0;
      }
      const gr = Math.max(this.env, this.envSlow);
      const g = Math.pow(10, (this.makeupDb - gr) / 20);
      const k = this.wet * g + (1 - this.wet);
      const yl = xl * k;
      const yr = xr * k;
      outL[i] = yl;
      if (outR !== outL) outR[i] = yr;
      // Индикация.
      const ai = Math.max(Math.abs(xl), Math.abs(xr));
      if (ai > this.mIn) this.mIn = ai;
      const ao = Math.max(Math.abs(yl), Math.abs(yr));
      if (ao > this.mOut) this.mOut = ao;
      const grShown = gr * this.wet;
      if (grShown > this.mGr) this.mGr = grShown;
    }
    this.meterN += n;
    if (this.meterN >= this.meterEvery) {
      this.port.postMessage([this.mIn, this.mGr, this.mOut]);
      this.meterN = 0;
      this.mIn = 0;
      this.mGr = 0;
      this.mOut = 0;
    }
    return true;
  }
}

registerProcessor('glue', GlueProcessor);
