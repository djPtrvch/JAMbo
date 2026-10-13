// Компрессор мастер-шины «glue» (по мотивам Ableton Glue Compressor и FabFilter Pro-C 2).
// Стерео, нулевая задержка, без lookahead. Детектор: смесь пика и RMS (RMS приведён к пику синуса) по сигналу
// после SC HPF (high-pass 2-го порядка, по умолчанию 90 Hz; на 20 Hz — обход). Gain computer в dB: колено KNEE,
// наклон 1 − 1/RATIO (RATIO непрерывный 1…20), ограничение RANGE. GR сглаживается в dB: атака — ATTACK, после пика
// GR держится HOLD, затем релиз (RELEASE или AUTO — быстрый и медленный). LINK: у каждого канала свой детектор
// и gain computer, плюс общий по максимуму L и R (прежний); GR канала = own + LINK·(linked − own); при 100 % —
// прежний звук. Выход = вход·(1 − MIX) + вход·GR·Makeup·MIX. BYPASS — кроссфейд 10 ms. AUDIT — вместо выхода сигнал
// детектора (вход после SC HPF), кроссфейд 10 ms. Параметры сглаживаются за 20 ms.
// Телеметрия (пока включена сообщением { meter: true }): раз в 256 отсчётов
// [пик входа, уровень детектора (dB), наибольший GR в dB (по каналам), пик выхода].

// ---------- Константы (одно место) ----------
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
const AUDIT_MS = 10;
/** SC HPF: не выше — обход. */
const SC_HPF_OFF_HZ = 20;
/** RANGE: на максимуме — без ограничения. */
const RANGE_OFF_DB = 40;
/** Телеметрия: кадр раз в METER_FRAMES отсчётов. */
const METER_FRAMES = 256;
/** Не даём состояниям уходить в денормалы. */
const TINY = 1e-25;

const coef = (ms, sr) => (ms <= 0 ? 0 : Math.exp(-1 / ((ms / 1000) * sr)));

/** Детектор и gain computer: пик + RMS → уровень (dB) → цель GR → сглаживание (атака, HOLD, релиз). */
class Detector {
  constructor() {
    this.pk = 0;
    this.ms = 0;
    this.env = 0; // GR, dB (≥ 0)
    this.envSlow = 0;
    this.hold = 0; // осталось отсчётов удержания
    this.ldb = -240;
  }

  /** a — модуль сигнала детектора; c — общие коэффициенты процессора. Возвращает GR, dB. */
  step(a, c) {
    this.pk = a > this.pk ? a : this.pk * c.kPeak + TINY;
    this.ms = a * a + (this.ms - a * a) * c.kRms + TINY;
    const level = PEAK_WEIGHT * this.pk + RMS_WEIGHT * Math.sqrt(this.ms) * RMS_CAL;
    const ldb = 20 * Math.log10(level + 1e-12);
    this.ldb = ldb;
    // Gain computer: мягкое колено KNEE (0 — жёсткое), наклон, ограничение RANGE.
    const over = ldb - c.thr;
    const knee = c.knee;
    const half = knee / 2;
    let target = 0;
    if (over >= half) target = over * c.slope;
    else if (over > -half) target = (c.slope * (over + half) * (over + half)) / (2 * knee);
    if (target > c.range) target = c.range;
    // Сглаживание GR в dB: атака; после неё HOLD держит GR; затем релиз.
    if (target > this.env) {
      this.env = target + (this.env - target) * c.kAtt;
      this.hold = c.holdN;
    } else if (this.hold > 0) {
      this.hold--;
    } else if (c.auto) {
      // Быстрая часть: релиз 60 ms; медленная копится при долгом сжатии и отпускает за 1.2 s.
      this.env = target + (this.env - target) * c.kAutoFast;
    } else {
      this.env = target + (this.env - target) * c.kRel;
    }
    if (c.auto) this.envSlow = target + (this.envSlow - target) * c.kAutoSlow;
    else this.envSlow = 0;
    return Math.max(this.env, this.envSlow);
  }
}

class GlueProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    // Цели параметров (из сообщений) и их сглаженные значения.
    this.p = {
      thr: -10, att: 10, rel: 400, auto: false, makeup: 0, ratio: 2, bypass: false,
      knee: 6, range: RANGE_OFF_DB, hold: 0, mix: 100, link: 100, schpf: 90, audit: false, meter: false,
    };
    this.thr = -10;
    this.makeupDb = 0;
    this.slope = 0.5;
    this.knee = 6;
    this.range = RANGE_OFF_DB;
    this.mix = 1;
    this.link = 1;
    this.schpf = 90;
    this.hpfSig = NaN;
    this.wet = 1;
    this.aud = 0;
    this.kSmooth = coef(PARAM_SMOOTH_MS, sr);
    this.wetStep = 1 / ((BYPASS_MS / 1000) * sr);
    this.audStep = 1 / ((AUDIT_MS / 1000) * sr);
    // Общие коэффициенты для детекторов (обновляются по ходу).
    this.c = {
      kPeak: coef(PEAK_RELEASE_MS, sr), kRms: coef(RMS_MS, sr), kAutoFast: coef(AUTO_FAST_MS, sr), kAutoSlow: coef(AUTO_SLOW_MS, sr),
      kAtt: 0, kRel: 0, auto: false, thr: -10, slope: 0.5, knee: 6, range: RANGE_OFF_DB, holdN: 0,
    };
    this.updateTimes();
    this.updateHpf(90);
    this.hz = [0, 0, 0, 0, 0, 0, 0, 0]; // x1, x2, y1, y2 для L и R
    this.det = new Detector(); // общий — по максимуму L и R
    this.detL = new Detector();
    this.detR = new Detector();
    this.meterN = 0;
    this.mIn = 0;
    this.mGr = 0;
    this.mOut = 0;
    this.mDet = -240;
    this.port.onmessage = (e) => {
      Object.assign(this.p, e.data);
      this.updateTimes();
    };
  }

  updateTimes() {
    this.c.kAtt = coef(this.p.att, this.sr);
    this.c.kRel = coef(this.p.rel, this.sr);
    this.c.auto = !!this.p.auto;
    this.c.holdN = Math.round((Math.max(0, this.p.hold) / 1000) * this.sr);
  }

  /** SC HPF: биквад Баттерворта на частоте f (на детекторе каждого канала). */
  updateHpf(f) {
    if (f === this.hpfSig) return;
    this.hpfSig = f;
    const w = (2 * Math.PI * f) / this.sr;
    const cw = Math.cos(w);
    const al = Math.sin(w) / (2 * Math.SQRT1_2);
    const a0 = 1 + al;
    this.hb0 = (1 + cw) / 2 / a0;
    this.hb1 = -(1 + cw) / a0;
    this.hb2 = (1 + cw) / 2 / a0;
    this.ha1 = (-2 * cw) / a0;
    this.ha2 = (1 - al) / a0;
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
    const slopeT = 1 - 1 / Math.max(1, Math.min(20, p.ratio));
    const kneeT = Math.max(0, Math.min(24, p.knee));
    const rangeT = p.range >= RANGE_OFF_DB ? Infinity : Math.max(0, p.range);
    const mixT = Math.max(0, Math.min(1, p.mix / 100));
    const linkT = Math.max(0, Math.min(1, p.link / 100));
    const wetT = p.bypass ? 0 : 1;
    const audT = p.audit ? 1 : 0;
    // SC HPF — по блокам (сглаживание по логарифму частоты); на 20 Hz и ниже — обход.
    const hpT = Math.max(SC_HPF_OFF_HZ, Math.min(500, p.schpf));
    const kb = Math.pow(ks, n);
    this.schpf = Math.exp(Math.log(hpT) + (Math.log(this.schpf) - Math.log(hpT)) * kb);
    if (Math.abs(this.schpf - hpT) < 1e-3) this.schpf = hpT;
    const hpOn = this.schpf > SC_HPF_OFF_HZ + 1e-6;
    if (hpOn) this.updateHpf(this.schpf);
    const c = this.c;
    for (let i = 0; i < n; i++) {
      const xl = inL ? inL[i] : 0;
      const xr = inR ? inR[i] : 0;
      // Сглаживание параметров (20 ms) и кроссфейды BYPASS, AUDIT (10 ms, линейно).
      this.thr = thrT + (this.thr - thrT) * ks;
      this.makeupDb = mkT + (this.makeupDb - mkT) * ks;
      this.slope = slopeT + (this.slope - slopeT) * ks;
      this.knee = kneeT + (this.knee - kneeT) * ks;
      this.range = rangeT === Infinity ? Infinity : this.range === Infinity ? rangeT : rangeT + (this.range - rangeT) * ks;
      this.mix = mixT + (this.mix - mixT) * ks;
      this.link = linkT + (this.link - linkT) * ks;
      if (this.wet < wetT) this.wet = Math.min(wetT, this.wet + this.wetStep);
      else if (this.wet > wetT) this.wet = Math.max(wetT, this.wet - this.wetStep);
      if (this.aud < audT) this.aud = Math.min(audT, this.aud + this.audStep);
      else if (this.aud > audT) this.aud = Math.max(audT, this.aud - this.audStep);
      c.thr = this.thr; c.slope = this.slope; c.knee = this.knee; c.range = this.range;
      // Детектор: SC HPF, общий — максимум из L/R; свои — по каналу (LINK).
      const hl = hpOn ? this.hp(xl, 0) : xl;
      const hr = hpOn ? this.hp(xr, 4) : xr;
      const al = Math.abs(hl);
      const ar = Math.abs(hr);
      const grLink = this.det.step(Math.max(al, ar), c);
      const ownL = this.detL.step(al, c);
      const ownR = this.detR.step(ar, c);
      let grL = grLink;
      let grR = grLink;
      const lk = this.link;
      if (lk < 1) { grL = ownL + lk * (grLink - ownL); grR = ownR + lk * (grLink - ownR); }
      const mx = this.mix;
      let kl;
      let kr;
      if (grL === grR) {
        const g = Math.pow(10, (this.makeupDb - grL) / 20);
        kl = kr = 1 - mx + g * mx;
      } else {
        kl = 1 - mx + Math.pow(10, (this.makeupDb - grL) / 20) * mx;
        kr = 1 - mx + Math.pow(10, (this.makeupDb - grR) / 20) * mx;
      }
      const wt = this.wet;
      let yl = xl * (wt * kl + (1 - wt));
      let yr = xr * (wt * kr + (1 - wt));
      // Индикация OUT — реальный выход компрессора (до AUDIT).
      const ao = Math.max(Math.abs(yl), Math.abs(yr));
      if (ao > this.mOut) this.mOut = ao;
      // AUDIT: кроссфейд 10 ms по плавной кривой (без излома на краях).
      const a0 = this.aud;
      if (a0 > 0) { const au = a0 * a0 * (3 - 2 * a0); yl = yl * (1 - au) + hl * au; yr = yr * (1 - au) + hr * au; }
      outL[i] = yl;
      if (outR !== outL) outR[i] = yr;
      // Индикация.
      const ai = Math.max(Math.abs(xl), Math.abs(xr));
      if (ai > this.mIn) this.mIn = ai;
      const grShown = (grL > grR ? grL : grR) * wt;
      if (grShown > this.mGr) this.mGr = grShown;
      if (this.det.ldb > this.mDet) this.mDet = this.det.ldb;
    }
    this.meterN += n;
    if (this.meterN >= METER_FRAMES) {
      if (p.meter) this.port.postMessage([this.mIn, this.mDet, this.mGr, this.mOut]);
      this.meterN = 0;
      this.mIn = 0;
      this.mGr = 0;
      this.mOut = 0;
      this.mDet = -240;
    }
    return true;
  }
}

registerProcessor('glue', GlueProcessor);
