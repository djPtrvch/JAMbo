// Детектор динамической полосы EQ: на вход — источник, уже отфильтрованный в полосе (стерео),
// на выход — сдвиг усиления полосы в dB (моно, подаётся в gain биквада). Уровень — пик
// (STEREO — max |L|, |R|; MID — |L+R|/2; SIDE — |L−R|/2) с атакой ATTACK_MS и спадом RELEASE_MS;
// сдвиг = RANGE · min(1, (уровень − THRESHOLD) / SPAN_DB), ниже порога — 0.
// ~30 раз в секунду сдвиг уходит сообщением (анимация точки и кривой).

// ---------- Константы (одно место) ----------
const ATTACK_MS = 5;
const RELEASE_MS = 100;
/** Над порогом на столько dB сдвиг доходит до RANGE. */
const SPAN_DB = 12;
const REPORT_HZ = 30;
const TINY = 1e-25;

const coef = (ms, sr) => Math.exp(-1 / ((ms / 1000) * sr));

class EqDynProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.p = { thr: -24, range: -6, ms: 0 };
    this.env = 0;
    this.kAtt = coef(ATTACK_MS, sampleRate);
    this.kRel = coef(RELEASE_MS, sampleRate);
    this.every = Math.round(sampleRate / REPORT_HZ);
    this.n = 0;
    this.port.onmessage = (e) => Object.assign(this.p, e.data);
  }

  process(inputs, outputs) {
    const inp = inputs[0];
    const out = outputs[0][0];
    const n = out.length;
    const L = inp[0];
    const R = inp[1] || L;
    const { thr, range, ms } = this.p;
    let env = this.env;
    let off = 0;
    for (let i = 0; i < n; i++) {
      const l = L ? L[i] : 0;
      const r = R ? R[i] : 0;
      const a = ms === 1 ? Math.abs(l + r) * 0.5 : ms === 2 ? Math.abs(l - r) * 0.5 : Math.max(Math.abs(l), Math.abs(r));
      env = a + (env - a) * (a > env ? this.kAtt : this.kRel) + TINY;
      const over = 20 * Math.log10(env + 1e-12) - thr;
      off = over > 0 ? range * Math.min(1, over / SPAN_DB) : 0;
      out[i] = off;
    }
    this.env = env;
    this.n += n;
    if (this.n >= this.every) {
      this.n = 0;
      this.port.postMessage(off);
    }
    return true;
  }
}

registerProcessor('eqdyn', EqDynProcessor);
