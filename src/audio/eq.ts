// Эквалайзер канала: цепочка BiquadFilterNode между входом и выходом.
// Узлы создаются только для включённых полос; если таких нет или EQ выключен — вход идёт прямо
// на выход. Low cut и high cut с крутизной 24 и 48 дБ/окт — каскад из 2 и 4 биквадов.
// Значения меняются плавно (setTargetAtTime), без щелчков. Кривая строится через
// getFrequencyResponse тех же типов фильтров.

import { EQ_SLOPES, EQ_TYPES, eqHasGain, eqIsCut } from '../params';
import type { Eq, EqBand } from '../state';

const SMOOTH = 0.02;

/** Сколько биквадов в каскаде у полосы. */
const stages = (b: EqBand) => (eqIsCut(b.type) ? EQ_SLOPES[b.slope] / 12 : 1);

/** Q полосы для узла: у highpass/lowpass в Web Audio Q задаётся в дБ (резонанс). */
const nodeQ = (b: EqBand) => (eqIsCut(b.type) ? 20 * Math.log10(b.q) : b.q);

function setNode(f: BiquadFilterNode, b: EqBand, at: number, smooth: boolean) {
  const q = nodeQ(b);
  const gain = eqHasGain(b.type) ? b.gain : 0;
  if (smooth) {
    f.frequency.setTargetAtTime(b.freq, at, SMOOTH);
    f.Q.setTargetAtTime(q, at, SMOOTH);
    f.gain.setTargetAtTime(gain, at, SMOOTH);
  } else {
    f.frequency.value = b.freq;
    f.Q.value = q;
    f.gain.value = gain;
  }
}

export class EqChain {
  readonly input: GainNode;
  readonly output: GainNode;
  private nodes: { k: number; f: BiquadFilterNode[]; last: string }[] = [];
  private sig = '';
  /** Куда подключён вход (первый узел или выход) — к входу ещё может быть подключён анализатор. */
  private first: AudioNode;

  constructor(private c: BaseAudioContext) {
    this.input = c.createGain();
    this.output = c.createGain();
    this.input.connect(this.output);
    this.first = this.output;
  }

  /** Каждый кадр: пересобрать цепочку, если изменился набор полос, иначе плавно обновить значения. */
  update(eq: Eq) {
    const active = eq.on ? eq.bands.map((b, k) => [b, k] as const).filter(([b]) => b && b.on) as [EqBand, number][] : [];
    const sig = active.map(([b, k]) => `${k}:${b.type}:${stages(b)}`).join(',');
    const at = this.c.currentTime;
    if (sig !== this.sig) {
      this.sig = sig;
      this.input.disconnect(this.first);
      for (const n of this.nodes) for (const f of n.f) f.disconnect();
      this.nodes = active.map(([b, k]) => ({
        k,
        last: `${b.freq}:${b.gain}:${b.q}`,
        f: Array.from({ length: stages(b) }, () => {
          const f = this.c.createBiquadFilter();
          f.type = EQ_TYPES[b.type].node;
          setNode(f, b, at, false);
          return f;
        }),
      }));
      const chain: AudioNode[] = [...this.nodes.flatMap((n) => n.f), this.output];
      this.first = chain[0];
      this.input.connect(chain[0]);
      for (let i = 1; i < chain.length; i++) chain[i - 1].connect(chain[i]);
      return;
    }
    for (const n of this.nodes) {
      const b = eq.bands[n.k]!;
      const v = `${b.freq}:${b.gain}:${b.q}`;
      if (v === n.last) continue;
      n.last = v;
      for (const f of n.f) setNode(f, b, at, true);
    }
  }
}

// ---------- Кривая ----------

let curveCtx: BaseAudioContext | null = null;
let probe: BiquadFilterNode | null = null;

/**
 * АЧХ одной полосы в дБ на частотах freqs (out заполняется). Узел-зонд живёт в отдельном
 * контексте и никуда не подключён — только getFrequencyResponse.
 */
export function bandResponse(b: EqBand, freqs: Float32Array<ArrayBuffer>, out: Float32Array<ArrayBuffer>, sampleRate: number) {
  if (!curveCtx || curveCtx.sampleRate !== sampleRate) {
    curveCtx = new OfflineAudioContext(1, 1, sampleRate);
    probe = curveCtx.createBiquadFilter();
  }
  const f = probe!;
  f.type = EQ_TYPES[b.type].node;
  setNode(f, b, 0, false);
  const mag = new Float32Array(freqs.length);
  const phase = new Float32Array(freqs.length);
  f.getFrequencyResponse(freqs, mag, phase);
  const n = stages(b);
  for (let i = 0; i < freqs.length; i++) out[i] = n * 20 * Math.log10(Math.max(1e-6, mag[i]));
}
