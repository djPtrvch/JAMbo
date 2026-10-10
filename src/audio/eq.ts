// Эквалайзер канала: цепочка BiquadFilterNode между входом и выходом.
// Узлы создаются только для включённых полос; если таких нет или EQ выключен — вход идёт прямо
// на выход. Low cut и high cut с крутизной 24 и 48 дБ/окт — каскад из 2 и 4 биквадов.
// Значения меняются плавно (setTargetAtTime), смена набора полос — кроссфейдом, без щелчков. Кривая строится через
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

/** Время перехода между старой и новой цепочкой, с. */
const FADE = 0.04;

interface Path { gain: GainNode; nodes: { k: number; f: BiquadFilterNode[]; last: string }[] }

export class EqChain {
  readonly input: GainNode;
  readonly output: GainNode;
  private path: Path;
  private sig = '';

  constructor(private c: BaseAudioContext) {
    this.input = c.createGain();
    this.output = c.createGain();
    this.path = this.makePath([], 0);
  }

  /** Цепочка вход → усиление пути → биквады → выход. */
  private makePath(active: [EqBand, number][], at: number): Path {
    const gain = this.c.createGain();
    const nodes = active.map(([b, k]) => ({
      k,
      last: `${b.freq}:${b.gain}:${b.q}`,
      f: Array.from({ length: stages(b) }, () => {
        const f = this.c.createBiquadFilter();
        f.type = EQ_TYPES[b.type].node;
        setNode(f, b, at, false);
        return f;
      }),
    }));
    const chain: AudioNode[] = [gain, ...nodes.flatMap((n) => n.f), this.output];
    this.input.connect(gain);
    for (let i = 1; i < chain.length; i++) chain[i - 1].connect(chain[i]);
    return { gain, nodes };
  }

  /**
   * Каждый кадр: если изменился набор полос (включение, тип, крутизна, bypass) — новая цепочка
   * плавно сменяет старую (кроссфейд FADE, без щелчка); иначе значения меняются плавно.
   */
  update(eq: Eq) {
    const active = eq.on ? eq.bands.map((b, k) => [b, k] as const).filter(([b]) => b && b.on) as [EqBand, number][] : [];
    const sig = active.map(([b, k]) => `${k}:${b.type}:${stages(b)}`).join(',');
    const at = this.c.currentTime;
    if (sig !== this.sig) {
      this.sig = sig;
      const old = this.path;
      const next = this.makePath(active, at);
      next.gain.gain.setValueAtTime(0, at);
      next.gain.gain.linearRampToValueAtTime(1, at + FADE);
      old.gain.gain.cancelScheduledValues(at);
      old.gain.gain.setValueAtTime(old.gain.gain.value, at);
      old.gain.gain.linearRampToValueAtTime(0, at + FADE);
      this.path = next;
      setTimeout(() => {
        this.input.disconnect(old.gain);
        old.gain.disconnect();
        for (const n of old.nodes) for (const f of n.f) f.disconnect();
      }, FADE * 1000 + 150);
      return;
    }
    for (const n of this.path.nodes) {
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
