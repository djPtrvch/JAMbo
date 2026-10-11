// Эквалайзер канала: цепочка BiquadFilterNode между входом и выходом.
// Узлы создаются только для включённых полос; если таких нет или EQ выключен — вход идёт прямо
// на выход. Low cut и high cut с крутизной 24 и 48 дБ/окт — каскад из 2 и 4 биквадов.
// Полоса MID или SIDE стоит между кодированием L/R → M/S и обратно и фильтрует только свой канал.
// Динамическая полоса (bell, shelf): детектор (eqdyn-worklet.js) слушает источник в полосе и
// подаёт сдвиг усиления (dB) в gain биквада; копии EQ для посылов берут сдвиг у основного EQ.
// Значения меняются плавно (setTargetAtTime), смена набора полос — кроссфейдом, без щелчков. Кривая строится через
// getFrequencyResponse тех же типов фильтров.

import { EQ_BANDS, EQ_DYN_RANGE_DEF, EQ_DYN_THR_DEF, EQ_SLOPES, EQ_TYPES, eqDynOn, eqHasGain, eqIsCut } from '../params';
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

/** Фильтр детектора динамической полосы: bell — полосовой, low shelf — ФНЧ, high shelf — ФВЧ. */
function setDetFilter(f: BiquadFilterNode, b: EqBand, at: number, smooth: boolean) {
  f.type = b.type === 1 ? 'lowpass' : b.type === 2 ? 'highpass' : 'bandpass';
  const q = b.type === 0 ? b.q : Math.SQRT1_2;
  if (smooth) {
    f.frequency.setTargetAtTime(b.freq, at, SMOOTH);
    f.Q.setTargetAtTime(q, at, SMOOTH);
  } else {
    f.frequency.value = b.freq;
    f.Q.value = q;
  }
}

/** Время перехода между старой и новой цепочкой, с. */
const FADE = 0.04;

/** Модуль детектора загружен (до этого динамические полосы работают как обычные). */
let dynReady = false;
export const setEqDynReady = (v: boolean) => { dynReady = v; };

interface Det { filter: BiquadFilterNode; node: AudioWorkletNode; delay: DelayNode | null; src: AudioNode; msg: string }
interface BandNodes { k: number; f: BiquadFilterNode[]; last: string; det: Det | null; follow: AudioWorkletNode | null }
interface Path { id: number; gain: GainNode; nodes: BandNodes[]; extra: AudioNode[] }

/** Источник динамической полосы n (1…16 — дорожка n); SELF — вход самого EQ. */
export type DynSource = (n: number) => AudioNode | null;

let pathIds = 0;

export class EqChain {
  readonly input: GainNode;
  readonly output: GainNode;
  /** Текущий сдвиг усиления динамических полос, dB (для анимации). */
  readonly dyn = new Float32Array(EQ_BANDS);
  /** Последние сдвиги от детекторов (сообщения приходят ~30 раз в секунду). */
  private dynLast = new Float32Array(EQ_BANDS);
  private path: Path;
  private sig = '';

  /**
   * source — откуда берутся источники T1…T16 динамических полос; follow — основной EQ, у которого
   * копия (EQ посыла) берёт сдвиг динамических полос.
   */
  constructor(private c: BaseAudioContext, private source?: DynSource, private follow?: EqChain) {
    this.input = c.createGain();
    // Всё стерео: моно-вход (L = R) повышается до двух каналов — для M/S.
    this.input.channelCount = 2;
    this.input.channelCountMode = 'explicit';
    this.input.channelInterpretation = 'speakers';
    this.output = c.createGain();
    this.path = this.makePath([], 0);
  }

  /** Номер текущей цепочки (копия пересобирается вместе с основным EQ). */
  get pathId() { return this.path.id; }

  /** Узел детектора полосы k основного EQ. */
  detector(k: number): AudioWorkletNode | null {
    return this.path.nodes.find((n) => n.k === k)?.det?.node ?? null;
  }

  private dynKey(b: EqBand, k: number): string {
    if (!eqDynOn(b) || !dynReady) return '';
    return this.follow ? `f${this.follow.pathId}:${this.follow.detector(k) ? 1 : 0}` : `d${b.dyn}`;
  }

  /** Детектор динамической полосы k: источник → (задержка) → фильтр полосы → worklet. */
  private makeDet(b: EqBand, k: number): Det | null {
    const n = b.dyn ?? -1;
    const src = n === 0 ? this.input : this.source?.(n) ?? null;
    if (!src) return null;
    const filter = this.c.createBiquadFilter();
    setDetFilter(filter, b, 0, false);
    // Дорожка как источник: задержка разрывает возможный цикл (дорожки могут слушать друг друга).
    const delay = n > 0 ? this.c.createDelay(0.01) : null;
    const node = new AudioWorkletNode(this.c, 'eqdyn', {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1], channelCount: 2, channelCountMode: 'explicit',
    });
    if (delay) src.connect(delay).connect(filter);
    else src.connect(filter);
    filter.connect(node);
    node.port.onmessage = (e) => { this.dynLast[k] = e.data as number; };
    const det: Det = { filter, node, delay, src, msg: '' };
    this.sendDet(det, b);
    return det;
  }

  private sendDet(det: Det, b: EqBand) {
    const msg = { thr: b.thr ?? EQ_DYN_THR_DEF, range: b.range ?? EQ_DYN_RANGE_DEF, ms: b.ms ?? 0 };
    const s = `${msg.thr}|${msg.range}|${msg.ms}`;
    if (s === det.msg) return;
    det.msg = s;
    det.node.port.postMessage(msg);
  }

  /** Цепочка вход → усиление пути → полосы (MID/SIDE — между M/S-кодированием) → выход. */
  private makePath(active: [EqBand, number][], at: number): Path {
    const c = this.c;
    const gain = c.createGain();
    const extra: AudioNode[] = [];
    this.input.connect(gain);
    let cur: AudioNode = gain;
    const nodes = active.map(([b, k]): BandNodes => {
      const f = Array.from({ length: stages(b) }, () => {
        const n = c.createBiquadFilter();
        n.type = EQ_TYPES[b.type].node;
        setNode(n, b, at, false);
        return n;
      });
      for (let i = 1; i < f.length; i++) f[i - 1].connect(f[i]);
      const ms = b.ms ?? 0;
      if (!ms) {
        cur.connect(f[0]);
        cur = f[f.length - 1];
      } else {
        // L/R → M/S: M = (L+R)/2, S = (L−R)/2; фильтруется только свой канал; обратно L = M+S, R = M−S.
        const half = c.createGain();
        half.gain.value = 0.5;
        half.channelCount = 2;
        half.channelCountMode = 'explicit';
        const sp = c.createChannelSplitter(2);
        const enc = c.createChannelMerger(2);
        const negE = c.createGain();
        negE.gain.value = -1;
        cur.connect(half).connect(sp);
        sp.connect(enc, 0, 0);
        sp.connect(enc, 1, 0);
        sp.connect(enc, 0, 1);
        sp.connect(negE, 1).connect(enc, 0, 1);
        const sp2 = c.createChannelSplitter(2);
        const mid = c.createChannelMerger(2);
        enc.connect(sp2);
        const ch = ms === 1 ? 0 : 1;
        sp2.connect(f[0], ch);
        f[f.length - 1].connect(mid, 0, ch);
        sp2.connect(mid, 1 - ch, 1 - ch);
        const sp3 = c.createChannelSplitter(2);
        const dec = c.createChannelMerger(2);
        const negD = c.createGain();
        negD.gain.value = -1;
        mid.connect(sp3);
        sp3.connect(dec, 0, 0);
        sp3.connect(dec, 1, 0);
        sp3.connect(dec, 0, 1);
        sp3.connect(negD, 1).connect(dec, 0, 1);
        extra.push(half, sp, enc, negE, sp2, mid, sp3, dec, negD);
        cur = dec;
      }
      let det: Det | null = null;
      let fnode: AudioWorkletNode | null = null;
      if (eqDynOn(b) && dynReady) {
        if (this.follow) {
          fnode = this.follow.detector(k);
          if (fnode) for (const n of f) fnode.connect(n.gain);
        } else {
          det = this.makeDet(b, k);
          if (det) for (const n of f) det.node.connect(n.gain);
        }
      }
      return { k, last: `${b.freq}:${b.gain}:${b.q}`, f, det, follow: fnode };
    });
    cur.connect(this.output);
    return { id: ++pathIds, gain, nodes, extra };
  }

  private dispose(old: Path) {
    this.input.disconnect(old.gain);
    old.gain.disconnect();
    for (const n of old.nodes) {
      for (const f of n.f) f.disconnect();
      const d = n.det;
      if (d) {
        d.node.port.onmessage = null;
        if (d.delay) { d.src.disconnect(d.delay); d.delay.disconnect(); } else d.src.disconnect(d.filter);
        d.filter.disconnect();
        d.node.disconnect();
      }
    }
    for (const x of old.extra) x.disconnect();
    // Копия EQ: детектор основного EQ отдаёт сдвиг и в эти биквады — отключаем только их.
    for (const n of old.nodes) {
      if (n.follow) for (const f of n.f) { try { n.follow.disconnect(f.gain); } catch { /* уже отключено */ } }
    }
  }

  /**
   * Каждый кадр: если изменился набор полос (включение, тип, крутизна, M/S, источник DYN, bypass) —
   * новая цепочка плавно сменяет старую (кроссфейд FADE, без щелчка); иначе значения меняются плавно.
   */
  update(eq: Eq) {
    const active = eq.on ? eq.bands.map((b, k) => [b, k] as const).filter(([b]) => b && b.on) as [EqBand, number][] : [];
    const sig = active.map(([b, k]) => `${k}:${b.type}:${stages(b)}:${b.ms ?? 0}:${this.dynKey(b, k)}`).join(',');
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
      setTimeout(() => this.dispose(old), FADE * 1000 + 150);
      return;
    }
    this.dyn.fill(0);
    for (const n of this.path.nodes) {
      const b = eq.bands[n.k]!;
      if (n.det) {
        this.dyn[n.k] = this.dynLast[n.k];
        this.sendDet(n.det, b);
      }
      const v = `${b.freq}:${b.gain}:${b.q}`;
      if (v === n.last) continue;
      n.last = v;
      for (const f of n.f) setNode(f, b, at, true);
      if (n.det) setDetFilter(n.det.filter, b, at, true);
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
