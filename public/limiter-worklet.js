// Лимитер мастер-шины (по мотивам Ableton Limiter и FabFilter Pro-L 2). Стерео, после компрессора.
// Вход · GAIN → детектор true peak (4× оверсэмплинг, полифазный FIR, stereo-linked) → целевое
// усиление g = min(1, Ceiling/Peak) → скользящий минимум за окно lookahead → релиз → скользящее
// среднее того же окна (рампа: усиление достигает цели ровно к приходу пика) → задержанный
// lookahead сигнал · g → жёсткий клип на CEILING (страховка). BYPASS — кроссфейд 10 ms с тем же
// задержанным сигналом (задержка мастера не меняется). Смена LOOKAHEAD — кроссфейд задержек.
// LINK (0–100 %): у каждого канала свой gain computer (свой true peak); GR канала в dB =
// own_c + LINK·(linked − own_c), linked — общий computer по максимуму L и R (при LINK 100 % — ровно прежний звук).
// UNITY: на выходе −GAIN dB (после лимитирования и страховочного клипа). AUDIT: вместо сигнала — разность задержанного
// входа (после GAIN) и выхода лимитера (то, что срезано); включение — кроссфейд 10 ms. UNITY и AUDIT — только из окна.
// Телеметрия (пока включена сообщением { meter: true }): раз в 256 отсчётов [true peak после GAIN, наибольший GR в dB
// (по каналам), true peak выхода].

// ---------- Константы (одно место) ----------
const OVERSAMPLE = 4;
const TAPS_PER_PHASE = 12;
const MAX_LOOKAHEAD_MS = 6;
const AUTO_FAST_MS = 30;
const AUTO_SLOW_MS = 400;
const PARAM_SMOOTH_MS = 20;
const BYPASS_MS = 10;
const LOOKAHEAD_XFADE_MS = 20;
/** Усиление держится ровным ещё HOLD отсчётов вокруг пика (меньше межсэмпловых пиков от модуляции). */
const HOLD = 8;
/** Телеметрия: кадр раз в METER_FRAMES отсчётов. */
const METER_FRAMES = 256;
const AUDIT_MS = 10;
const TINY = 1e-25;

const coef = (ms, sr) => (ms <= 0 ? 0 : Math.exp(-1 / ((ms / 1000) * sr)));

/**
 * Полифазный FIR для 4× оверсэмплинга: окно Блэкмана × sinc, каждая фаза нормирована к 1.
 * Центр ядра — целое число входных отсчётов, поэтому фазы попадают ровно в точки 0, ¼, ½, ¾
 * между отсчётами (пик синуса fs/4 с фазой 45° — ровно посередине — ловится без недобора).
 */
function makeFir() {
  const n = OVERSAMPLE * TAPS_PER_PHASE;
  const c = OVERSAMPLE * Math.floor(TAPS_PER_PHASE / 2);
  const h = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    const d = k - c;
    const x = d / OVERSAMPLE;
    const sinc = x === 0 ? 1 : Math.sin(Math.PI * x) / (Math.PI * x);
    const r = (Math.PI * d) / (c + 1);
    const w = 0.42 + 0.5 * Math.cos(r) + 0.08 * Math.cos(2 * r);
    h[k] = sinc * w;
  }
  const phases = [];
  for (let p = 0; p < OVERSAMPLE; p++) {
    const f = new Float32Array(TAPS_PER_PHASE);
    let sum = 0;
    for (let j = 0; j < TAPS_PER_PHASE; j++) { f[j] = h[j * OVERSAMPLE + p]; sum += f[j]; }
    for (let j = 0; j < TAPS_PER_PHASE; j++) f[j] /= sum;
    phases.push(f);
  }
  // Задержка фильтра во входных отсчётах (центр ядра).
  return { phases, delay: c / OVERSAMPLE };
}
const FIR = makeFir();

/** Детектор true peak одного стереосигнала: история и наибольший модуль из 4 фаз. */
class TruePeak {
  constructor() {
    this.hl = new Float32Array(TAPS_PER_PHASE * 2);
    this.hr = new Float32Array(TAPS_PER_PHASE * 2);
    this.pos = 0;
  }
  push(l, r) {
    // Двойной буфер: окно истории всегда непрерывно (без деления по модулю в цикле).
    const p = this.pos;
    this.hl[p] = this.hl[p + TAPS_PER_PHASE] = l;
    this.hr[p] = this.hr[p + TAPS_PER_PHASE] = r;
    this.pos = (p + 1) % TAPS_PER_PHASE;
    // Свежий отсчёт — по индексу p, старше — p-1, ...: читаем назад от p + TAPS_PER_PHASE.
    const base = p + TAPS_PER_PHASE;
    let m = 0;
    let ml = 0;
    let mr = 0;
    for (let ph = 0; ph < OVERSAMPLE; ph++) {
      const f = FIR.phases[ph];
      let sl = 0;
      let sr = 0;
      for (let j = 0; j < TAPS_PER_PHASE; j++) {
        const k = base - j;
        sl += f[j] * this.hl[k];
        sr += f[j] * this.hr[k];
      }
      const al = Math.abs(sl);
      const ar = Math.abs(sr);
      if (al > ml) ml = al;
      if (ar > mr) mr = ar;
      const a = Math.max(al, ar);
      if (a > m) m = a;
    }
    // Пики каналов — для gain computer каждого канала (LINK).
    this.pl = ml;
    this.pr = mr;
    return m;
  }
}

/**
 * Gain computer: цель g = min(1, Ceiling/Peak) → скользящий минимум за окно L + HOLD → релиз (вниз мгновенно,
 * вверх — экспонента с ручки или AUTO) → скользящее среднее за окно L (рампа к цели). Состояние — своё у каждого.
 */
class GainComputer {
  constructor(maxL, L) {
    this.maxL = maxL;
    this.tHist = new Float64Array(maxL).fill(1);
    this.eHist = new Float64Array(maxL).fill(1);
    this.hpos = 0;
    // Монотонная очередь скользящего минимума: индексы отсчётов и значения.
    this.qIdx = new Float64Array(maxL + 1);
    this.qVal = new Float64Array(maxL + 1);
    this.qHead = 0;
    this.qLen = 0;
    this.n = 0;
    this.sumAge = 0;
    this.envF = 1;
    this.envS = 1;
    this.L = L;
    this.sum = L;
  }

  /** Новое окно L: очередь минимума и сумма пересобираются из истории. */
  setWindow(L) {
    this.L = L;
    const M = this.maxL;
    this.qHead = 0;
    this.qLen = 0;
    this.sum = 0;
    for (let k = L + HOLD - 1; k >= 0; k--) {
      const idx = this.n - 1 - k;
      const pos = (this.hpos - 1 - k + 2 * M) % M;
      this.pushMin(idx, this.tHist[pos]);
      if (k < L) this.sum += this.eHist[pos];
    }
    this.sumAge = 0;
  }

  pushMin(idx, v) {
    const cap = this.maxL + 1;
    // Убираем с хвоста всё, что не меньше нового значения.
    while (this.qLen > 0) {
      const tail = (this.qHead + this.qLen - 1) % cap;
      if (this.qVal[tail] >= v) this.qLen--;
      else break;
    }
    const at = (this.qHead + this.qLen) % cap;
    this.qIdx[at] = idx;
    this.qVal[at] = v;
    this.qLen++;
    // Убираем с головы то, что вышло из окна.
    while (this.qIdx[this.qHead] <= idx - this.L - HOLD) {
      this.qHead = (this.qHead + 1) % cap;
      this.qLen--;
    }
    return this.qVal[this.qHead];
  }

  /** Отсчёт: пик pk, потолок ceil; auto, kRel, kFast, kSlow — релиз. Возвращает усиление g. */
  step(pk, ceil, auto, kRel, kFast, kSlow) {
    const M = this.maxL;
    const t = pk > ceil ? ceil / pk : 1;
    const hp = this.hpos;
    this.tHist[hp] = t;
    const h = this.pushMin(this.n, t);
    // Релиз: вниз мгновенно, вверх — экспонента с ручки (AUTO: быстрый и медленный этапы).
    let e;
    if (auto) {
      this.envF = h < this.envF ? h : h + (this.envF - h) * kFast;
      this.envS = h + (this.envS - h) * kSlow;
      e = Math.min(this.envF, this.envS);
    } else {
      this.envF = h < this.envF ? h : h + (this.envF - h) * kRel;
      this.envS = this.envF;
      e = this.envF;
    }
    // Скользящее среднее за окно L (рампа к цели).
    const old = this.eHist[(hp - this.L + 2 * M) % M];
    this.eHist[hp] = e;
    this.sum += e - old;
    if (++this.sumAge >= 4096) {
      // Пересчёт суммы — без накопления ошибки.
      let s = 0;
      for (let k = 0; k < this.L; k++) s += this.eHist[(hp - k + 2 * M) % M];
      this.sum = s;
      this.sumAge = 0;
    }
    this.hpos = (hp + 1) % M;
    this.n++;
    return Math.min(1, this.sum / this.L);
  }
}

class LimiterProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const sr = sampleRate;
    this.sr = sr;
    this.p = { gain: 0, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false, link: 100, unity: false, audit: false, meter: false };
    this.gainLin = 1;
    this.ceil = Math.pow(10, -1 / 20);
    this.kSmooth = coef(PARAM_SMOOTH_MS, sr);
    this.wet = 1;
    this.wetStep = 1 / ((BYPASS_MS / 1000) * sr);
    this.link = 1;
    this.unityG = 1;
    this.aud = 0;
    this.audStep = 1 / ((AUDIT_MS / 1000) * sr);
    this.kFast = coef(AUTO_FAST_MS, sr);
    this.kSlow = coef(AUTO_SLOW_MS, sr);
    this.kRel = coef(150, sr);
    this.maxL = Math.ceil((MAX_LOOKAHEAD_MS / 1000) * sr) + HOLD + 2;
    const size = this.maxL + FIR.delay + 8;
    this.size = size;
    // Задержанный сигнал (после GAIN и без него — для bypass).
    this.dl = new Float32Array(size);
    this.dr = new Float32Array(size);
    this.xl = new Float32Array(size);
    this.xr = new Float32Array(size);
    this.w = 0;
    this.pkPrev = 0;
    this.pkPrevL = 0;
    this.pkPrevR = 0;
    this.detIn = new TruePeak();
    this.detOut = new TruePeak();
    this.L = this.lookSamples(3);
    // Общий (по максимуму каналов — прежний) и по каналу (для LINK < 100 %).
    this.gcLink = new GainComputer(this.maxL, this.L);
    this.gcL = new GainComputer(this.maxL, this.L);
    this.gcR = new GainComputer(this.maxL, this.L);
    // Кроссфейд задержек при смене LOOKAHEAD.
    this.oldDelay = -1;
    this.xf = 1;
    this.xfStep = 1 / ((LOOKAHEAD_XFADE_MS / 1000) * sr);
    this.meterN = 0;
    this.mIn = 0;
    this.mGr = 1;
    this.mOut = 0;
    this.port.onmessage = (e) => {
      Object.assign(this.p, e.data);
      this.kRel = coef(this.p.rel, this.sr);
    };
  }

  lookSamples(ms) {
    return Math.max(1, Math.min(this.maxL - HOLD - 1, Math.round((ms / 1000) * this.sr)));
  }

  /** Задержка звука относительно детектора для окна L (рампа кончается ровно на пике). */
  delayFor(L) {
    return L + FIR.delay + HOLD / 2;
  }

  /** Новое окно L у всех gain computer; звук — кроссфейдом старой и новой задержки. */
  setWindow(L) {
    this.oldDelay = this.delayFor(this.L);
    this.xf = 0;
    this.L = L;
    this.gcLink.setWindow(L);
    this.gcL.setWindow(L);
    this.gcR.setWindow(L);
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
    const gainT = Math.pow(10, p.gain / 20);
    const ceilT = Math.pow(10, p.ceiling / 20);
    const wetT = p.bypass ? 0 : 1;
    const linkT = Math.max(0, Math.min(1, p.link / 100));
    const unityT = p.unity ? 1 / gainT : 1;
    const audT = p.audit ? 1 : 0;
    const S = this.size;
    const auto = p.auto, kRel = this.kRel, kFast = this.kFast, kSlow = this.kSlow;
    // Новое окно lookahead — только после окончания прошлого кроссфейда.
    const Lt = this.lookSamples(p.lookahead);
    if (Lt !== this.L && this.xf >= 1) this.setWindow(Lt);
    for (let i = 0; i < n; i++) {
      this.gainLin = gainT + (this.gainLin - gainT) * ks;
      this.ceil = ceilT + (this.ceil - ceilT) * ks;
      this.link = linkT + (this.link - linkT) * ks;
      this.unityG = unityT + (this.unityG - unityT) * ks;
      if (this.wet < wetT) this.wet = Math.min(wetT, this.wet + this.wetStep);
      else if (this.wet > wetT) this.wet = Math.max(wetT, this.wet - this.wetStep);
      if (this.aud < audT) this.aud = Math.min(audT, this.aud + this.audStep);
      else if (this.aud > audT) this.aud = Math.max(audT, this.aud - this.audStep);
      const rawL = inL ? inL[i] : 0;
      const rawR = inR ? inR[i] : 0;
      const gl = rawL * this.gainLin;
      const gr = rawR * this.gainLin;
      const w = this.w;
      this.dl[w] = gl;
      this.dr[w] = gr;
      this.xl[w] = rawL;
      this.xr[w] = rawR;
      this.w = (w + 1) % S;
      // Детектор: true peak, межсэмпловый пик — на оба соседних отсчёта.
      const det = this.detIn;
      const pk0 = det.push(gl, gr);
      const pk = Math.max(pk0, this.pkPrev);
      this.pkPrev = pk0;
      if (pk0 > this.mIn) this.mIn = pk0;
      const ceil = this.ceil;
      const gLink = this.gcLink.step(pk, ceil, auto, kRel, kFast, kSlow);
      // Свои каналы (LINK): считаются всегда — смена LINK без скачка.
      const pkL = Math.max(det.pl, this.pkPrevL);
      const pkR = Math.max(det.pr, this.pkPrevR);
      this.pkPrevL = det.pl;
      this.pkPrevR = det.pr;
      const gOwnL = this.gcL.step(pkL, ceil, auto, kRel, kFast, kSlow);
      const gOwnR = this.gcR.step(pkR, ceil, auto, kRel, kFast, kSlow);
      // GR канала в dB: own + LINK·(linked − own) → усиление: own^(1−LINK) · linked^LINK.
      const lk = this.link;
      let gL = gLink;
      let gR = gLink;
      if (lk < 1) {
        const lgl = Math.log(gLink);
        gL = Math.exp((1 - lk) * Math.log(gOwnL) + lk * lgl);
        gR = Math.exp((1 - lk) * Math.log(gOwnR) + lk * lgl);
      }
      const gMin = gL < gR ? gL : gR;
      if (gMin < this.mGr) this.mGr = gMin;
      // Задержанный звук (при смене LOOKAHEAD — кроссфейд старой и новой задержки).
      const d = this.delayFor(this.L);
      const r = (w - d + S) % S;
      let yl = this.dl[r];
      let yr = this.dr[r];
      let bl = this.xl[r];
      let br = this.xr[r];
      if (this.xf < 1) {
        const ro = (w - this.oldDelay + S) % S;
        const a = this.xf;
        yl = yl * a + this.dl[ro] * (1 - a);
        yr = yr * a + this.dr[ro] * (1 - a);
        bl = bl * a + this.xl[ro] * (1 - a);
        br = br * a + this.xr[ro] * (1 - a);
        this.xf = Math.min(1, this.xf + this.xfStep);
      }
      // Задержанный вход после GAIN — для AUDIT (вход минус выход).
      const preL = yl;
      const preR = yr;
      yl *= gL;
      yr *= gR;
      // Страховка: жёсткий клип на CEILING.
      const c = this.ceil;
      if (yl > c) yl = c; else if (yl < -c) yl = -c;
      if (yr > c) yr = c; else if (yr < -c) yr = -c;
      const wt = this.wet;
      let ol = yl * wt + bl * (1 - wt);
      let or = yr * wt + br * (1 - wt);
      // Индикация OUT — реальный выход лимитера (до UNITY и AUDIT).
      const po = this.detOut.push(ol, or);
      if (po > this.mOut) this.mOut = po;
      // UNITY: −GAIN на выходе (только на обработанной ветке).
      const u = this.unityG;
      if (u !== 1) { ol = yl * wt * u + bl * (1 - wt); or = yr * wt * u + br * (1 - wt); }
      // AUDIT: то, что срезано (задержанный вход − выход), кроссфейдом.
      const au = this.aud;
      if (au > 0) {
        ol = ol * (1 - au) + (preL - yl) * wt * au;
        or = or * (1 - au) + (preR - yr) * wt * au;
      }
      outL[i] = ol;
      if (outR !== outL) outR[i] = or;
    }
    this.meterN += n;
    if (this.meterN >= METER_FRAMES) {
      if (p.meter) {
        const grDb = this.wet > 0.5 ? -20 * Math.log10(Math.max(this.mGr, 1e-6)) : 0;
        this.port.postMessage([this.mIn, grDb, this.mOut]);
      }
      this.meterN = 0;
      this.mIn = 0;
      this.mGr = 1;
      this.mOut = 0;
    }
    return true;
  }
}

registerProcessor('limiter', LimiterProcessor);
