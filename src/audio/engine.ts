// Звуковой движок (Web Audio). Читает состояние из state.ts и ничего в нём не меняет,
// кроме загрузки сэмплов из файлов.
//
// Голос (на каждую ноту трига):
//   сэмпл → огибающая Attack/Decay → Level → фильтр LP/HP → Pan → вход дорожки
//                                                               ↘ посылы Reverb / Delay / Drive
// Дорожка: вход → sidechain (приглушение) → громкость микшера → мастер.
// Мастер: компрессор (Threshold, Attack, Release, Ratio, Makeup) → лимитер (Input, Ceiling,
// Lookahead, Release) → выход.
//
// Параметры голоса берутся на шаге с учётом p-lock и модуляции; если на ручку назначен LFO
// или ENV, значения голоса обновляются каждый кадр, пока он звучит.

import { PARAM_BY_ID, RATIOS, SAMPLE_ROOT, TRACK_COUNT, filterFreq, fromNorm } from '../params';
import { doc, modulatedNorm, setTrackSample, ui } from '../state';
import { buildKit } from './kit';

let ctx: AudioContext | null = null;
const buffers = new Map<string, AudioBuffer>();
const peaks = new Map<string, Float32Array>();
let fileCount = 0;

interface TrackChain { input: GainNode; duck: GainNode; vol: GainNode; sends: GainNode[] }
interface Voice {
  track: number;
  locks: Record<string, number>;
  note: number;
  src: AudioBufferSourceNode;
  level: GainNode;
  filter: BiquadFilterNode;
  pan: StereoPannerNode;
  sends: GainNode[];
  ended: boolean;
}

let tracks: TrackChain[] = [];
let busInputs: GainNode[] = [];
const voices: Voice[] = [];
const MAX_VOICES = 48;

// Узлы эффектов и мастера.
let rev: { hpf: BiquadFilterNode; pre: DelayNode; conv: ConvolverNode };
let dly: { hpf: BiquadFilterNode; l: DelayNode; r: DelayNode; fbL: GainNode; fbR: GainNode };
let drv: { shaper: WaveShaperNode; tone: BiquadFilterNode };
let mst: { comp: DynamicsCompressorNode; makeup: GainNode; limIn: GainNode; lim: DynamicsCompressorNode };

const SENDS = ['reverb', 'delay', 'drive'] as const;

// ---------- Запуск ----------

/** Создать контекст (можно до касания — он будет на паузе). */
function ensureCtx(): AudioContext {
  if (ctx) return ctx;
  // iOS 17+: играть даже при выключенном звонке (переключатель Mute).
  const session = (navigator as Navigator & { audioSession?: { type: string } }).audioSession;
  if (session) session.type = 'playback';
  ctx = new AudioContext({ latencyHint: 'interactive' });
  for (const [k, b] of buildKit(ctx)) buffers.set(k, b);
  buildGraph(ctx);
  return ctx;
}

/** В iOS Safari звук можно включить только из касания пользователя. */
export function unlockAudio() {
  const c = ensureCtx();
  if (c.state !== 'running') void c.resume();
}

export function initAudio() {
  ensureCtx();
}

function buildGraph(c: AudioContext) {
  // Мастер.
  const masterIn = c.createGain();
  const comp = c.createDynamicsCompressor();
  comp.knee.value = 6;
  const makeup = c.createGain();
  const limIn = c.createGain();
  const lim = c.createDynamicsCompressor();
  lim.knee.value = 0;
  lim.ratio.value = 20;
  masterIn.connect(comp).connect(makeup).connect(limIn).connect(lim).connect(c.destination);
  mst = { comp, makeup, limIn, lim };

  // Reverb: HPF → предзадержка → свёртка.
  const revIn = c.createGain();
  const rhpf = c.createBiquadFilter();
  rhpf.type = 'highpass';
  const pre = c.createDelay(1);
  const conv = c.createConvolver();
  revIn.connect(rhpf).connect(pre).connect(conv).connect(masterIn);
  rev = { hpf: rhpf, pre, conv };

  // Delay: HPF → две линии (L/R) с обратной связью, Stereo разносит время правой линии.
  const dlyIn = c.createGain();
  const dhpf = c.createBiquadFilter();
  dhpf.type = 'highpass';
  const l = c.createDelay(4);
  const r = c.createDelay(4);
  const fbL = c.createGain();
  const fbR = c.createGain();
  const merger = c.createChannelMerger(2);
  dlyIn.connect(dhpf);
  dhpf.connect(l);
  dhpf.connect(r);
  l.connect(fbL).connect(l);
  r.connect(fbR).connect(r);
  l.connect(merger, 0, 0);
  r.connect(merger, 0, 1);
  merger.connect(masterIn);
  dly = { hpf: dhpf, l, r, fbL, fbR };

  // Overdrive: шейпер → тон.
  const drvIn = c.createGain();
  const shaper = c.createWaveShaper();
  shaper.oversample = '2x';
  const tone = c.createBiquadFilter();
  tone.type = 'lowpass';
  const drvOut = c.createGain();
  drvOut.gain.value = 0.5;
  drvIn.connect(shaper).connect(tone).connect(drvOut).connect(masterIn);
  drv = { shaper, tone };

  busInputs = [revIn, dlyIn, drvIn];

  // Дорожки.
  tracks = Array.from({ length: TRACK_COUNT }, () => {
    const input = c.createGain();
    const duck = c.createGain();
    const vol = c.createGain();
    input.connect(duck).connect(vol).connect(masterIn);
    const sends = busInputs.map((bus) => {
      const g = c.createGain();
      g.connect(bus);
      return g;
    });
    return { input, duck, vol, sends };
  });
}

/** Время performance.now() → время контекста. */
function toCtx(perf: number): number {
  const c = ctx!;
  return Math.max(c.currentTime, c.currentTime + (perf - performance.now()) / 1000);
}

// ---------- Голоса ----------

/** Значение параметра голоса с p-lock и текущей модуляцией. */
function value(track: number, id: string, locks: Record<string, number>): number {
  const p = PARAM_BY_ID[id];
  const base = locks[id] ?? doc.tracks[track].params[id];
  return fromNorm(p, modulatedNorm(track, p, base));
}

function applyFilter(f: BiquadFilterNode, v: number, reso: number, at: number, smooth: boolean) {
  const ff = filterFreq(v);
  const type: BiquadFilterType = ff.type === 'hp' ? 'highpass' : 'lowpass';
  if (f.type !== type) f.type = type;
  const hz = ff.type === 'off' ? 20000 : ff.hz;
  const q = 0.7 + (reso / 100) * 18;
  if (smooth) {
    f.frequency.setTargetAtTime(hz, at, 0.015);
    f.Q.setTargetAtTime(q, at, 0.015);
  } else {
    f.frequency.setValueAtTime(hz, at);
    f.Q.setValueAtTime(q, at);
  }
}

const levelGain = (v: number) => Math.pow(v / 127, 1.5);
const rateFor = (note: number, pitch: number) => Math.pow(2, (note - SAMPLE_ROOT + pitch) / 12);

/** Запустить ноты дорожки в момент time (performance.now). */
export function triggerTrack(track: number, time: number, notes: number[], locks: Record<string, number>) {
  if (!ctx || ctx.state !== 'running') return;
  const t = doc.tracks[track];
  const buf = buffers.get(t.sample);
  if (!buf) return;
  const at = toCtx(time);
  const v = (id: string) => value(track, id, locks);

  const startSec = (buf.duration * v('start')) / 100;
  const endSec = (buf.duration * v('end')) / 100;
  if (endSec - startSec < 0.003) return;
  const attack = v('attack') / 1000;
  const decay = v('decay') / 1000;

  for (const note of notes) {
    const rate = rateFor(note, v('pitch'));
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = rate;
    const amp = ctx.createGain();
    const level = ctx.createGain();
    const filter = ctx.createBiquadFilter();
    const pan = ctx.createStereoPanner();
    const ch = tracks[track];

    // Огибающая Attack/Decay.
    amp.gain.setValueAtTime(0, at);
    amp.gain.linearRampToValueAtTime(1, at + Math.max(0.001, attack));
    amp.gain.setTargetAtTime(0, at + Math.max(0.001, attack), Math.max(0.005, decay / 4));
    level.gain.value = levelGain(v('level'));
    applyFilter(filter, v('filter'), v('reso'), at, false);
    pan.pan.value = Math.max(-1, Math.min(1, v('pan') / 64));

    src.connect(amp).connect(level).connect(filter).connect(pan).connect(ch.input);
    const sends = SENDS.map((id, k) => {
      const g = ctx!.createGain();
      g.gain.value = v(id) / 100;
      pan.connect(g).connect(ch.sends[k]);
      return g;
    });

    const playDur = (endSec - startSec) / rate;
    const stopAt = at + Math.min(playDur, attack + decay + 0.1);
    src.start(at, startSec, Math.max(0.003, (endSec - startSec)));
    src.stop(stopAt);
    const voice: Voice = { track, locks, note, src, level, filter, pan, sends, ended: false };
    src.onended = () => {
      voice.ended = true;
      for (const n of [src, amp, level, filter, pan, ...sends]) n.disconnect();
    };
    voices.push(voice);
    if (voices.length > MAX_VOICES) {
      const old = voices.shift()!;
      try { old.src.stop(); } catch { /* уже остановлен */ }
    }
  }
  sidechain(track, at);
}

/** Живой наигрыш с пианоролла: ноты выбранной дорожки сейчас. */
export function playNow(track: number, notes: number[]) {
  triggerTrack(track, performance.now(), notes, {});
}

/** Sidechain: триг дорожки-источника приглушает остальные на их Sidechain amount. */
function sidechain(source: number, at: number) {
  if (source !== doc.fx['sc.source']) return;
  const atk = doc.fx['sc.attack'] / 1000;
  const rel = doc.fx['sc.release'] / 1000;
  doc.tracks.forEach((t, i) => {
    if (i === source) return;
    const amount = t.params.sidechain / 100;
    if (amount <= 0) return;
    const g = tracks[i].duck.gain;
    g.cancelScheduledValues(at);
    g.setTargetAtTime(1 - amount, at, Math.max(0.0005, atk / 3));
    g.setTargetAtTime(1, at + atk, Math.max(0.005, rel / 3));
  });
}

/** Модуляция звучащих голосов (LFO/ENV) — каждый кадр. */
function updateVoices() {
  const c = ctx!;
  for (let k = voices.length - 1; k >= 0; k--) {
    const vo = voices[k];
    if (vo.ended) { voices.splice(k, 1); continue; }
    const assigns = doc.tracks[vo.track].assigns;
    if (Object.keys(assigns).length === 0) continue;
    const v = (id: string) => value(vo.track, id, vo.locks);
    const now = c.currentTime;
    if (assigns.pitch) vo.src.playbackRate.setTargetAtTime(rateFor(vo.note, v('pitch')), now, 0.01);
    if (assigns.level) vo.level.gain.setTargetAtTime(levelGain(v('level')), now, 0.01);
    if (assigns.filter || assigns.reso) applyFilter(vo.filter, v('filter'), v('reso'), now, true);
    if (assigns.pan) vo.pan.pan.setTargetAtTime(Math.max(-1, Math.min(1, v('pan') / 64)), now, 0.01);
    SENDS.forEach((id, i) => { if (assigns[id]) vo.sends[i].gain.setTargetAtTime(v(id) / 100, now, 0.01); });
  }
}

// ---------- Эффекты, микшер, мастер ----------

let fxSig = '';
let irSig = '';
let irTimer = 0;
const curves = new Map<number, Float32Array>();

/** Кривые overdrive: Soft, Hard, Tube, Fuzz. */
function driveCurve(type: number): Float32Array {
  let curve = curves.get(type);
  if (curve) return curve;
  const n = 2048;
  curve = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    curve[i] = type === 0 ? Math.tanh(3 * x)
      : type === 1 ? Math.max(-0.7, Math.min(0.7, 2.5 * x)) / 0.7
      : type === 2 ? (x < 0 ? Math.tanh(2 * x) : Math.tanh(5 * x) * 0.9)
      : Math.sign(x) * (1 - Math.exp(-10 * Math.abs(x)));
  }
  curves.set(type, curve);
  return curve;
}

/** Импульс реверба: стереошум с экспоненциальным затуханием; Size — плотность начала. */
function buildIR(c: AudioContext, decay: number, size: number): AudioBuffer {
  const sec = Math.min(8, Math.max(0.1, decay));
  const n = Math.round(c.sampleRate * sec);
  const ir = c.createBuffer(2, n, c.sampleRate);
  const fade = 0.002 + (size / 100) * 0.08;
  for (let ch = 0; ch < 2; ch++) {
    const d = ir.getChannelData(ch);
    for (let i = 0; i < n; i++) {
      const t = i / c.sampleRate;
      d[i] = (Math.random() * 2 - 1) * Math.exp((-6.9 * t) / sec) * Math.min(1, t / fade);
    }
  }
  return ir;
}

function updateFx(now: number) {
  const c = ctx!;
  const fx = doc.fx;
  const ct = c.currentTime;
  const set = (p: AudioParam, v: number) => p.setTargetAtTime(v, ct, 0.02);

  // Реверб: импульс пересчитываем, когда Size/Decay перестали меняться.
  const sig = `${fx['rev.decay'].toFixed(2)}|${Math.round(fx['rev.size'])}`;
  if (sig !== irSig) {
    if (!irTimer) irTimer = now;
    if (now - irTimer > 150 || !rev.conv.buffer) {
      rev.conv.buffer = buildIR(c, fx['rev.decay'], fx['rev.size']);
      irSig = sig;
      irTimer = 0;
    }
  }

  const fsig = JSON.stringify([fx, doc.mixer, doc.master, doc.ratio]);
  if (fsig === fxSig) return;
  fxSig = fsig;
  set(rev.hpf.frequency, fx['rev.hpf']);
  set(rev.pre.delayTime, fx['rev.predelay'] / 1000);

  const time = fx['dly.time'] / 1000;
  set(dly.l.delayTime, time);
  set(dly.r.delayTime, Math.min(4, time * (1 + (fx['dly.stereo'] / 100) * 0.5)));
  set(dly.fbL.gain, fx['dly.feedback'] / 100 * 0.95);
  set(dly.fbR.gain, fx['dly.feedback'] / 100 * 0.95);
  set(dly.hpf.frequency, fx['dly.hpf']);

  drv.shaper.curve = driveCurve(Math.round(fx['od.type'])) as Float32Array<ArrayBuffer>;
  set(drv.tone.frequency, 500 * Math.pow(24, fx['od.tone'] / 100));

  tracks.forEach((ch, i) => {
    const vol = Math.pow((doc.mixer[`mix.vol${i + 1}`] ?? 80) / 100, 2);
    set(ch.vol.gain, vol);
    ch.sends.forEach((s) => set(s.gain, vol));
  });

  const m = doc.master;
  set(mst.comp.threshold, m['cmp.threshold']);
  set(mst.comp.attack, m['cmp.attack'] / 1000);
  set(mst.comp.release, m['cmp.release'] / 1000);
  set(mst.comp.ratio, RATIOS[doc.ratio]);
  set(mst.makeup.gain, Math.pow(10, m['cmp.makeup'] / 20));
  set(mst.limIn.gain, Math.pow(10, m['lim.input'] / 20));
  set(mst.lim.threshold, m['lim.ceiling']);
  // Lookahead в Web Audio недоступен — приближаем быстрой атакой лимитера.
  set(mst.lim.attack, Math.max(0.001, m['lim.lookahead'] / 1000));
  set(mst.lim.release, m['lim.release'] / 1000);
}

/** Каждый кадр: эффекты, микшер, мастер и модуляция голосов. */
export function updateAudio(now: number) {
  if (!ctx) return;
  updateFx(now);
  updateVoices();
}

/** Понижение усиления компрессора мастера (дБ, ≤ 0). */
export const masterReduction = () => (mst ? mst.comp.reduction : 0);

// ---------- Метроном ----------

/** Щелчок в момент time (по шкале performance.now), мимо мастера. */
export function clickAt(time: number, accent: boolean) {
  if (!ctx || ctx.state !== 'running') return;
  const when = toCtx(time);
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.frequency.value = accent ? 1600 : 1000;
  gain.gain.setValueAtTime(0.0001, when);
  gain.gain.exponentialRampToValueAtTime(accent ? 0.5 : 0.3, when + 0.002);
  gain.gain.exponentialRampToValueAtTime(0.0001, when + 0.05);
  osc.connect(gain).connect(ctx.destination);
  osc.start(when);
  osc.stop(when + 0.06);
}

// ---------- Сэмплы и файлы ----------

/** Загрузить аудиофайл с iPad и поставить его на выбранную дорожку. */
export async function loadSampleFile(file: File): Promise<void> {
  const c = ensureCtx();
  const data = await file.arrayBuffer();
  const buf = await c.decodeAudioData(data);
  const key = `file:${++fileCount}`;
  buffers.set(key, buf);
  setTrackSample(ui.selectedTrack, key, file.name);
}

/** Огибающая сэмпла для окна сэмпла: n пиков 0..1. */
export function samplePeaks(key: string, n = 160): Float32Array | null {
  const cached = peaks.get(key);
  if (cached) return cached;
  const buf = buffers.get(key);
  if (!buf) return null;
  const d = buf.getChannelData(0);
  const out = new Float32Array(n);
  const step = Math.max(1, Math.floor(d.length / n));
  let max = 0;
  for (let i = 0; i < n; i++) {
    let m = 0;
    for (let j = i * step; j < Math.min(d.length, (i + 1) * step); j++) m = Math.max(m, Math.abs(d[j]));
    out[i] = m;
    max = Math.max(max, m);
  }
  if (max > 0) for (let i = 0; i < n; i++) out[i] /= max;
  peaks.set(key, out);
  return out;
}

