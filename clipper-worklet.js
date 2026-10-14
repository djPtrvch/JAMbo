// Клиппер мастер-шины: между компрессором и лимитером. Стерео, каналы независимо.
// Вход · DRIVE → кроссовер Linkwitz-Riley 4-го порядка на частоте BASS (OFF — без деления) →
// ВЧ-полоса: 4× оверсэмплинг (полифазный FIR, общий модуль oversampler.js) → нелинейность с мягким коленом (SOFTNESS) по CEILING
// (с антипроизводной — меньше алиасинга) → обратно; НЧ-полоса — без обработки, с той же задержкой →
// сумма → MIX (сухой — исходный вход с той же задержкой) → UNITY (−DRIVE dB). BYPASS — кроссфейд 10 ms
// с задержанным входом (задержка не меняется). AUDIT — на выходе срезанное: вход после DRIVE (задержан) − выход.
// Телеметрия (пока { meter: true }): раз в 256 отсчётов [пик после DRIVE, срез пика (dB; последнее окно 10 ms),
// пик выхода]; пока { wave: true } — раз в ~33 ms снимок формы: 1024 отсчёта входа после DRIVE и выхода
// (выровнены по задержке) вокруг наибольшего пика последних 2048 отсчётов, канал с большим пиком.

// ---------- Константы (одно место) ----------
const BASS_OFF_HZ = 0; // BASS = OFF приходит как 0
const PARAM_SMOOTH_MS = 20;
const BYPASS_MS = 10;
const GR_WINDOW_MS = 10;
const METER_FRAMES = 256;
const AUDIT_MS = 10;
/** Снимки формы: кольцо, окно поиска пика, длина снимка, период. */
const WAVE_RING = 4096;
const WAVE_SEARCH = 2048;
const WAVE_LEN = 1024;
const WAVE_HZ = 30;
const TINY = 1e-25;

/** Оверсэмплер — общий модуль (oversampler.js, загружается раньше). */
const { OVERSAMPLE, FIR_LEN, PHASE_LEN, PHASES, PH0_DELAY, PH0_GAIN, DEC_C, DEC_HALF, DEC_MID } = globalThis.JamboOversampler;

const coef = (ms, sr) => (ms <= 0 ? 0 : Math.exp(-1 / ((ms / 1000) * sr)));

/**
 * Задержка ВЧ-пути в исходных отсчётах: интерполятор (c) + коррекция (1) + антипроизводная (½) +
 * децимация (c), всё в отсчётах 4× частоты.
 */
const HF_DELAY = ((FIR_LEN - 1) / 2 + 1 + 0.5 + (FIR_LEN - 1) / 2) / OVERSAMPLE;
const LF_DELAY = Math.round(HF_DELAY);

/** Биквад Баттерворта (TDF-II): коэффициенты для ФНЧ или ФВЧ на частоте f. */
function butter(f, sr, high) {
  const w = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w);
  const al = Math.sin(w) * Math.SQRT1_2; // Q = 1/√2
  const a0 = 1 + al;
  const b0 = (high ? (1 + cw) / 2 : (1 - cw) / 2) / a0;
  const b1 = (high ? -(1 + cw) : 1 - cw) / a0;
  return [b0, b1, b0, (-2 * cw) / a0, (1 - al) / a0];
}

/** Нелинейность и её антипроизводная (u в долях CEILING, колено k). */
function shape(u, k) {
  const a = Math.abs(u);
  if (a <= k) return u;
  const s = 1 - k;
  const y = s > 1e-9 ? k + s * Math.tanh((a - k) / s) : 1;
  return u < 0 ? -y : y;
}
function lnCosh(x) {
  const a = Math.abs(x);
  // При a > 9 поправка меньше 1e-8 — без логарифма и экспоненты.
  return a > 9 ? a - Math.LN2 : a + Math.log1p(Math.exp(-2 * a)) - Math.LN2;
}
function antideriv(u, k) {
  const a = Math.abs(u);
  if (a <= k) return 0.5 * u * u;
  const s = 1 - k;
  const base = 0.5 * k * k + k * (a - k);
  return s > 1e-9 ? base + s * s * lnCosh((a - k) / s) : base + (a - k) * (1 - k); // s→0: y=1
}

/** Канал: кроссовер, оверсэмплер, нелинейность. */
class Channel {
  constructor() {
    this.lp = [new Float64Array(2), new Float64Array(2)];
    this.hp = [new Float64Array(2), new Float64Array(2)];
    this.hist = new Float64Array(PHASE_LEN * 2); // история ВЧ (исходная частота), двойной буфер
    this.hpos = 0;
    this.os = new Float64Array(FIR_LEN * 2); // выход нелинейности (4× частота), двойной буфер
    this.opos = 0;
    this.prevU = 0; // для антипроизводной
    this.prevF = 0;
    this.c0 = 0; // коррекция (3 отсчёта)
    this.c1 = 0;
    this.lfDelay = new Float64Array(LF_DELAY + 1);
    this.dryDelay = new Float64Array(LF_DELAY + 1);
    this.hfDelay = new Float64Array(LF_DELAY + 1); // ВЧ без среза — опора для GR
    this.xDelay = new Float64Array(LF_DELAY + 1); // вход после DRIVE — для AUDIT и снимков
    this.wIn = new Float32Array(WAVE_RING); // снимки: вход после DRIVE (задержан) и выход
    this.wOut = new Float32Array(WAVE_RING);
    this.dpos = 0;
  }
}

function biquad(st, c, x) {
  const y = c[0] * x + st[0];
  st[0] = c[1] * x - c[3] * y + st[1];
  st[1] = c[2] * x - c[4] * y;
  return y;
}

class ClipperProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.p = { drive: 0, ceiling: -1, softness: 30, bass: 0, bypass: false, mix: 100, unity: false, audit: false, meter: false, wave: false };
    this.mix = 1;
    this.unity = 1;
    this.aud = 0;
    this.audStep = 1 / ((AUDIT_MS / 1000) * sr);
    this.wPos = 0;
    this.waveEvery = Math.round(sr / WAVE_HZ);
    this.waveN = 0;
    /** Срез последнего завершённого окна (кадр без своего окна показывает его). */
    this.lastGr = 0;
    this.frameGr = -1;
    this.driveLin = 1;
    this.ceil = Math.pow(10, -1 / 20);
    this.knee = 1 - 0.6 * 0.3;
    this.freq = 100;
    this.split = 1; // 1 — кроссовер, 0 — OFF (всё в ВЧ)
    this.kSmooth = coef(PARAM_SMOOTH_MS, sr);
    this.kBlock = Math.pow(this.kSmooth, 128);
    this.wet = 1;
    this.wetStep = 1 / ((BYPASS_MS / 1000) * sr);
    this.splitStep = 1 / ((PARAM_SMOOTH_MS / 1000) * sr);
    this.ch = [new Channel(), new Channel()];
    this.cLp = butter(100, sr, false);
    this.cHp = butter(100, sr, true);
    this.grWin = Math.round((GR_WINDOW_MS / 1000) * sr);
    this.grN = 0;
    /** В окне нелинейность срабатывала (иначе GR — только погрешность фильтров, показываем 0). */
    this.engaged = false;
    this.winIn = 0;
    this.winOut = 0;
    this.meterEvery = METER_FRAMES;
    this.meterN = 0;
    this.mIn = 0;
    this.mGr = 0;
    this.mOut = 0;
    this.port.onmessage = (e) => Object.assign(this.p, e.data);
  }

  /** Отсчёт ВЧ-полосы на исходной частоте → 4 отсчёта нелинейности → децимация → 1 отсчёт. */
  hf(c, x, ceil, k) {
    const hp = c.hpos;
    const hist = c.hist;
    hist[hp] = hist[hp + PHASE_LEN] = x;
    c.hpos = hp + 1 === PHASE_LEN ? 0 : hp + 1;
    const base = hp + PHASE_LEN;
    const inv = 1 / ceil;
    const os = c.os;
    for (let p = 0; p < OVERSAMPLE; p++) {
      let s;
      if (p === 0) s = PH0_GAIN * hist[base - PH0_DELAY];
      else {
        const f = PHASES[p];
        s = 0;
        for (let j = 0; j < PHASE_LEN; j++) s += f[j] * hist[base - j];
      }
      // Нелинейность с антипроизводной первого порядка (меньше алиасинга от среза);
      // ниже колена — просто среднее двух отсчётов (без логарифмов).
      const u = s * inv;
      const u0 = c.prevU;
      let y;
      if (Math.abs(u) <= k && Math.abs(u0) <= k) {
        y = 0.5 * (u + u0);
        c.prevF = 0.5 * u * u;
      } else {
        this.engaged = true;
        const F = antideriv(u, k);
        const du = u - u0;
        y = Math.abs(du) > 1e-6 ? (F - c.prevF) / du : shape(0.5 * (u + u0), k);
        c.prevF = F;
      }
      c.prevU = u;
      // Коррекция среднего по двум отсчётам у антипроизводной: [-1/8, 5/4, -1/8].
      const yc = 1.25 * c.c0 - 0.125 * (y + c.c1);
      c.c1 = c.c0;
      c.c0 = y;
      const op = c.opos;
      os[op] = os[op + FIR_LEN] = yc * ceil;
      c.opos = op + 1 === FIR_LEN ? 0 : op + 1;
    }
    // Децимация: ФНЧ по последним FIR_LEN отсчётам 4× частоты (симметричные пары отводов).
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
    const driveT = Math.pow(10, p.drive / 20);
    const ceilT = Math.pow(10, p.ceiling / 20);
    const kneeT = 1 - 0.6 * (p.softness / 100);
    const wetT = p.bypass ? 0 : 1;
    const mixT = Math.max(0, Math.min(1, (p.mix ?? 100) / 100));
    const unityT = p.unity ? 1 / driveT : 1;
    const audT = p.audit ? 1 : 0;
    const splitT = p.bass > BASS_OFF_HZ ? 1 : 0;
    // Частота кроссовера сглаживается по блокам; коэффициенты линейно интерполируются внутри блока.
    const fT = p.bass > BASS_OFF_HZ ? p.bass : this.freq;
    const f1 = fT + (this.freq - fT) * this.kBlock;
    const lp0 = this.cLp;
    const hp0 = this.cHp;
    const lp1 = butter(f1, this.sr, false);
    const hp1 = butter(f1, this.sr, true);
    this.freq = f1;
    const lpc = new Float64Array(5);
    const hpc = new Float64Array(5);
    const D = LF_DELAY + 1;
    const moving = Math.abs(f1 - fT) > 0.01 || lp0[0] !== lp1[0];
    if (!moving) { lpc.set(lp1); hpc.set(hp1); }
    for (let i = 0; i < n; i++) {
      if (moving) {
        const a = (i + 1) / n;
        for (let q = 0; q < 5; q++) { lpc[q] = lp0[q] + (lp1[q] - lp0[q]) * a; hpc[q] = hp0[q] + (hp1[q] - hp0[q]) * a; }
      }
      this.driveLin = driveT + (this.driveLin - driveT) * ks;
      this.ceil = ceilT + (this.ceil - ceilT) * ks;
      this.knee = kneeT + (this.knee - kneeT) * ks;
      this.mix = mixT + (this.mix - mixT) * ks;
      this.unity = unityT + (this.unity - unityT) * ks;
      if (this.aud < audT) this.aud = Math.min(audT, this.aud + this.audStep);
      else if (this.aud > audT) this.aud = Math.max(audT, this.aud - this.audStep);
      const a0 = this.aud;
      const au = a0 * a0 * (3 - 2 * a0);
      if (this.wet < wetT) this.wet = Math.min(wetT, this.wet + this.wetStep);
      else if (this.wet > wetT) this.wet = Math.max(wetT, this.wet - this.wetStep);
      if (this.split < splitT) this.split = Math.min(splitT, this.split + this.splitStep);
      else if (this.split > splitT) this.split = Math.max(splitT, this.split - this.splitStep);
      let inPk = 0;
      let dryPk = 0;
      let outPk = 0;
      for (let k = 0; k < 2; k++) {
        const c = this.ch[k];
        const src = inp[k] || inp[0];
        const raw = src ? src[i] : 0;
        const x = raw * this.driveLin;
        if (Math.abs(x) > inPk) inPk = Math.abs(x);
        // Кроссовер LR4 (OFF — всё в ВЧ, с плавным переходом).
        const lo = biquad(c.lp[1], lpc, biquad(c.lp[0], lpc, x));
        const hi = biquad(c.hp[1], hpc, biquad(c.hp[0], hpc, x));
        const sp = this.split;
        const hfIn = sp * hi + (1 - sp) * x;
        const lfIn = sp * lo;
        const yh = this.hf(c, hfIn, this.ceil, this.knee);
        // НЧ и сухой сигнал — с той же задержкой.
        const dp = c.dpos;
        const r = (dp + 1) % D;
        const lfOut = c.lfDelay[r];
        const dryOut = c.dryDelay[r];
        const lin = lfOut + c.hfDelay[r];
        const xOut = c.xDelay[r];
        c.lfDelay[dp] = lfIn;
        c.dryDelay[dp] = raw;
        c.hfDelay[dp] = hfIn;
        c.xDelay[dp] = x;
        c.dpos = r;
        const wet = lfOut + yh;
        // MIX — с исходным входом (до DRIVE) той же задержки; UNITY — −DRIVE dB после MIX.
        let y1 = (dryOut + (wet - dryOut) * this.mix) * this.unity;
        // AUDIT: срезанное — вход после DRIVE минус выход клиппера (до MIX).
        if (au > 0) y1 += (xOut - wet - y1) * au;
        // В bypass клиппер отключён целиком (и DRIVE тоже): сухой — исходный сигнал с той же задержкой.
        const y = this.wet * y1 + (1 - this.wet) * dryOut;
        const o = out[k] || out[0];
        o[i] = y;
        c.wIn[this.wPos] = xOut;
        c.wOut[this.wPos] = y;
        // Опора для GR — тот же сигнал без среза (НЧ + ВЧ, с той же задержкой и фазой кроссовера).
        if (Math.abs(lin) > dryPk) dryPk = Math.abs(lin);
        if (Math.abs(wet) > outPk) outPk = Math.abs(wet);
        if (Math.abs(y) > this.mOut) this.mOut = Math.abs(y);
        if (!out[1]) break;
      }
      this.wPos = (this.wPos + 1) & (WAVE_RING - 1);
      if (inPk > this.mIn) this.mIn = inPk;
      // Срез пика: самый большой пик выхода к самому большому пику того же сигнала без среза за 10 ms.
      if (dryPk > this.winIn) this.winIn = dryPk;
      if (outPk > this.winOut) this.winOut = outPk;
      if (++this.grN >= this.grWin) {
        let gr = this.winIn > 1e-6 && this.wet > 0.5 ? Math.max(0, -20 * Math.log10(Math.max(this.winOut, 1e-9) / this.winIn)) : 0;
        // Без срабатывания нелинейности или меньше 0.1 dB — погрешность фильтров оверсэмплинга, не срез.
        if (gr < 0.1 || !this.engaged) gr = 0;
        this.engaged = false;
        if (gr > this.mGr) this.mGr = gr;
        this.lastGr = gr;
        this.frameGr = Math.max(this.frameGr, gr);
        this.grN = 0;
        this.winIn = 0;
        this.winOut = 0;
      }
    }
    this.cLp = lp1;
    this.cHp = hp1;
    this.meterN += n;
    if (this.meterN >= this.meterEvery) {
      // GR кадра — наибольшее из окон 10 ms, закончившихся в кадре; если ни одно не закончилось — последнее.
      const gr = this.frameGr >= 0 ? this.frameGr : this.lastGr;
      if (p.meter) this.port.postMessage([this.mIn, gr, this.mOut]);
      this.meterN = 0;
      this.mIn = 0;
      this.mGr = 0;
      this.mOut = 0;
      this.frameGr = -1;
    }
    this.waveN += n;
    if (this.waveN >= this.waveEvery) {
      this.waveN = 0;
      if (p.wave) this.sendWave();
    }
    return true;
  }
}

/** Снимок формы вокруг наибольшего пика последних WAVE_SEARCH отсчётов (канал с большим пиком). */
ClipperProcessor.prototype.sendWave = function () {
  const M = WAVE_RING - 1;
  const end = this.wPos;
  let best = -1, bestK = 0, bestAt = 0;
  for (let k = 0; k < 2; k++) {
    const w = this.ch[k].wIn;
    for (let j = 1; j <= WAVE_SEARCH; j++) {
      const q = (end - j) & M;
      const a = Math.abs(w[q]);
      if (a > best) { best = a; bestK = k; bestAt = j; }
    }
  }
  // Окно WAVE_LEN с пиком в центре; сдвигается, чтобы целиком лежать в кольце (последние WAVE_RING отсчётов).
  let back = bestAt + WAVE_LEN / 2; // начало окна — столько отсчётов назад
  back = Math.max(WAVE_LEN, Math.min(WAVE_RING, back));
  const c = this.ch[bestK];
  const inp = new Float32Array(WAVE_LEN);
  const outp = new Float32Array(WAVE_LEN);
  for (let j = 0; j < WAVE_LEN; j++) {
    const q = (end - back + j) & M;
    inp[j] = c.wIn[q];
    outp[j] = c.wOut[q];
  }
  this.port.postMessage({ wave: true, ch: bestK, inp, out: outp }, [inp.buffer, outp.buffer]);
};

registerProcessor('clipper', ClipperProcessor);
