// Звуковой движок (Web Audio). Читает состояние из state.ts и ничего в нём не меняет,
// кроме загрузки сэмплов из файлов.
//
// Голос (на каждую ноту трига):
//   сэмпл или голос синта → огибающая Attack/Decay → Level → фильтр LP/HP → Pan → вход дорожки
//                                                                          ↘ посылы Reverb / Delay / Drive
// Синт — движки Mutable Instruments Plaits (plaits.wasm в AudioWorklet, узел на дорожку с
// SYNTH_SLOTS голосами); цепочка каждого голоса синта постоянная, огибающая ставится на триге.
// Дорожка: EQ → вход → sidechain (приглушение) → громкость микшера → mute/solo → мастер. EQ стоит до эффектов:
// у каждого посыла голоса своя копия EQ дорожки с теми же полосами.
// Мастер: EQ → компрессор (Threshold, Attack, Release, Ratio, Makeup) → лимитер (Input, Ceiling,
// Lookahead, Release) → выход.
//
// Параметры голоса берутся на шаге с учётом p-lock и модуляции; если на ручку назначен LFO
// или ENV, значения голоса обновляются каждый кадр, пока он звучит.
// Измерители уровня стоят на выходе каждой дорожки и в мастере (вход компрессора, вход и выход
// лимитера): пиковый уровень по каналам и громкость в LUFS (K-взвешивание, окно ~400 мс).

import { DELAY_DIVS, isAuto, OVER_PEAK, DRUM_ENGINE, SYNTH_ENGINES, synthEngine, PARAM_BY_ID, RATIOS, VOL_DEF_DB, volGain, SAMPLE_ROOT, MAX_TRACKS, filterFreq, fromNorm } from '../params';
import { audible, addSamplesQuiet, addSamplesToFolder, doc, setStepSound, triggerEnv, liveFx, liveMaster, liveMixer, modulatedNorm, ui } from '../state';
import { detectRoot } from './pitch';
import { encodeWav } from './wav';
import { settings } from '../settings';
import { getSample, putSample, sampleKey, type SampleRecord } from '../storage';
import { EqChain, setEqDynReady, type DynSource } from './eq';

let ctx: AudioContext | null = null;
const buffers = new Map<string, AudioBuffer>();
const peaks = new Map<string, Float32Array[]>();

interface TrackChain {
  /** EQ сухого сигнала и копии EQ для посылов Reverb / Delay / Drive. */
  eq: EqChain; sendEqs: EqChain[];
  input: GainNode; duck: GainNode; vol: GainNode;
  /** Mute / solo: глушит выход дорожки (сухой и посылы); метр стоит до него — уровень виден и у заглушённой. */
  gate: GainNode; sends: GainNode[]; meter: Meter;
}
interface Voice {
  track: number;
  root: number;
  locks: Record<string, number>;
  note: number;
  /** Время начала ноты (контекст): до него модуляция голос не трогает. */
  at: number;
  /** Сэмпл; у голоса синта — null (звучит слот synth). */
  src: AudioBufferSourceNode | null;
  synth: { slot: number; engine: number; end: number } | null;
  level: GainNode;
  filter: BiquadFilterNode;
  pan: StereoPannerNode;
  sends: GainNode[];
  ended: boolean;
}

let tracks: TrackChain[] = [];
let busInputs: GainNode[] = [];
const voices: Voice[] = [];

// ---------- Синт (Plaits) ----------

const SYNTH_SLOTS = 6;
interface SynthSlot { amp: GainNode; level: GainNode; filter: BiquadFilterNode; pan: StereoPannerNode; sends: GainNode[] }
interface Synth { node: AudioWorkletNode; slots: SynthSlot[]; next: number; busyUntil: number[] }
const synths: (Synth | null)[] = Array(MAX_TRACKS).fill(null);
let wasmBytes: ArrayBuffer | null = null;

/** Загрузить AudioWorklet и plaits.wasm (один раз, после создания контекста). */
function loadSynth(c: AudioContext) {
  const url = (f: string) => new URL(f, document.baseURI).href;
  void Promise.all([
    c.audioWorklet.addModule(url('plaits-worklet.js')),
    fetch(url('plaits.wasm')).then((r) => r.arrayBuffer()),
  ]).then(([, bytes]) => { wasmBytes = bytes; }).catch((e) => console.error('synth', e));
}

/** Узел синта дорожки и постоянные цепочки его голосов (создаются, когда синт выбран). */
function ensureSynth(track: number): Synth | null {
  if (synths[track]) return synths[track];
  if (!ctx || !wasmBytes) return null;
  const c = ctx;
  const node = new AudioWorkletNode(c, 'plaits', {
    numberOfInputs: 0,
    numberOfOutputs: SYNTH_SLOTS,
    outputChannelCount: Array(SYNTH_SLOTS).fill(1),
    processorOptions: { bytes: wasmBytes, slots: SYNTH_SLOTS },
  });
  node.port.onmessage = (e) => { if (typeof e.data?.cpu === 'number') synthCpu[track] = e.data.cpu; };
  const ch = tracks[track];
  const slots = Array.from({ length: SYNTH_SLOTS }, (_, k) => {
    const amp = c.createGain();
    amp.gain.value = 0;
    const level = c.createGain();
    const filter = c.createBiquadFilter();
    const pan = c.createStereoPanner();
    node.connect(amp, k).connect(level).connect(filter).connect(pan).connect(ch.eq.input);
    const sends = SENDS.map((_, i) => {
      const g = c.createGain();
      g.gain.value = 0;
      pan.connect(g).connect(ch.sendEqs[i].input);
      return g;
    });
    return { amp, level, filter, pan, sends };
  });
  return (synths[track] = { node, slots, next: 0, busyUntil: Array(SYNTH_SLOTS).fill(0) });
}

/** Ручка Decay (мс) → затухание движка Plaits 0..1. */
const decayNorm = (ms: number) => Math.sqrt(Math.min(1, Math.max(0, ms / 4000)));

/**
 * Параметры движка 0..1 для голоса синта (с p-lock и модуляцией). У движков, где Morph в Plaits —
 * затухание, затухание берётся с ручки Decay, а Morph смешивает выходы OUT и AUX.
 */
function synthParams(engine: number, v: (id: string) => number) {
  const harmonics = v('harm') / 100;
  const timbre = v('timbre') / 100;
  // DRUM: Sweep, Tone, Drive — как есть, затухание — постоянная времени из Decay (мс).
  if (engine === DRUM_ENGINE) return { harmonics, timbre, morph: v('morph') / 100, aux: 0, decay: v('decay') };
  if (SYNTH_ENGINES[engine].decay) return { harmonics, timbre, morph: decayNorm(v('decay')), aux: v('morph') / 100 };
  return { harmonics, timbre, morph: v('morph') / 100, aux: 0 };
}

// Нагрузка расчёта синтов: доля реального времени по каждой дорожке (присылает AudioWorklet).
const synthCpu: number[] = Array(MAX_TRACKS).fill(0);
/** Суммарная нагрузка расчёта синтов (доля 0..1). */
export const synthLoad = () => synthCpu.reduce((a, b) => a + b, 0);
const MAX_VOICES = 48;

// Узлы эффектов и мастера.
let rev: { hpf: BiquadFilterNode; pre: DelayNode; conv: ConvolverNode };
let dly: { hpf: BiquadFilterNode; l: DelayNode; r: DelayNode; fbL: GainNode; fbR: GainNode };
let drv: { shaper: WaveShaperNode; tone: BiquadFilterNode };
let mst: {
  eq: EqChain; satIn: GainNode; sat: AudioWorkletNode | null; glueIn: GainNode; glue: AudioWorkletNode | null; clipIn: GainNode; clip: AudioWorkletNode | null;
  limIn: GainNode; lim: AudioWorkletNode | null; outVol: GainNode;
  outMeter: Meter;
};

const SENDS = ['reverb', 'delay', 'drive'] as const;
/** Наибольшее время Delay, с (1 такт при 40 BPM — 6 с, со Stereo — до 9 с). */
const MAX_DELAY = 9;

// ---------- Сатуратор, компрессор (glue), клиппер и лимитер мастера — AudioWorklet ----------

/** Индикация устройства мастера: пик входа, наибольший GR (dB, ≥ 0), пик выхода, время прихода. */
export interface DynLevels { in: number; gr: number; out: number; at: number }
const glueLevels: DynLevels = { in: 0, gr: 0, out: 0, at: 0 };
const clipLevels: DynLevels = { in: 0, gr: 0, out: 0, at: 0 };
const limLevels: DynLevels = { in: 0, gr: 0, out: 0, at: 0 };
/** У сатуратора индикации нет. */
const satLevels: DynLevels = { in: 0, gr: 0, out: 0, at: 0 };
export const glueMeter = () => glueLevels;
export const clipperMeter = () => clipLevels;
export const limiterMeter = () => limLevels;

/**
 * Загрузить модуль worklet и вставить устройство между узлами from и to (до этого сигнал идёт
 * мимо — без обработки). Индикация приходит сообщениями в levels.
 */
function loadDevice(c: AudioContext, file: string, name: string, from: GainNode, to: AudioNode, levels: DynLevels, ready: (n: AudioWorkletNode) => void, after: Promise<unknown> = Promise.resolve()) {
  void after.then(() => c.audioWorklet.addModule(new URL(file, document.baseURI).href)).then(() => {
    if (c !== ctx || !mst) return;
    const node = new AudioWorkletNode(c, name, {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2], channelCount: 2, channelCountMode: 'explicit',
    });
    node.port.onmessage = (e) => {
      const [i, g, o] = e.data as number[];
      levels.in = i; levels.gr = g; levels.out = o; levels.at = performance.now();
    };
    // Снимаем только обход (from → to): от from могут идти и другие связи (скоп мастера).
    from.disconnect(to);
    from.connect(node).connect(to);
    ready(node);
    sendDynamics();
  }).catch((e) => console.error(name, e));
}

let satSig = '';
let glueSig = '';
let clipSig = '';
let limSig = '';
/** Параметры сатуратора, компрессора, клиппера и лимитера — в worklet (только при изменении). */
function sendDynamics() {
  if (!mst) return;
  const m = liveMaster();
  const auto = (v: number) => (isAuto(v) ? { rel: 400, auto: true } : { rel: v, auto: false });
  if (mst.sat) {
    const msg = { drive: m['sat.drive'], type: Math.round(m['sat.type']), tone: m['sat.tone'], mix: m['sat.mix'] };
    const sig = JSON.stringify(msg);
    if (sig !== satSig) { satSig = sig; mst.sat.port.postMessage(msg); }
  }
  if (mst.glue) {
    const msg = {
      thr: m['cmp.threshold'], att: m['cmp.attack'], ...auto(m['cmp.release']),
      makeup: m['cmp.makeup'], ratio: RATIOS[doc.ratio] ?? 2, bypass: doc.cmpBypass,
    };
    const sig = JSON.stringify(msg);
    if (sig !== glueSig) { glueSig = sig; mst.glue.port.postMessage(msg); }
  }
  if (mst.clip) {
    const msg = {
      drive: m['clip.drive'], ceiling: m['clip.ceiling'], softness: m['clip.softness'], bass: m['clip.bass'], bypass: doc.clipBypass,
    };
    const sig = JSON.stringify(msg);
    if (sig !== clipSig) { clipSig = sig; mst.clip.port.postMessage(msg); }
  }
  if (mst.lim) {
    const msg = {
      gain: m['lim.input'], ceiling: m['lim.ceiling'], lookahead: m['lim.lookahead'], ...auto(m['lim.release']), bypass: doc.limBypass,
    };
    const sig = JSON.stringify(msg);
    if (sig !== limSig) { limSig = sig; mst.lim.port.postMessage(msg); }
  }
}

// ---------- Запуск ----------

/** Создать контекст (на паузе, пока его не включит касание). */
function ensureCtx(): AudioContext {
  if (ctx) return ctx;
  // Настройки AUDIO ENGINE: частота дискретизации и буфер (как подсказка задержки).
  const opts: AudioContextOptions = { latencyHint: 'interactive' };
  if (settings.sampleRate) opts.sampleRate = settings.sampleRate;
  if (settings.bufferSize) opts.latencyHint = settings.bufferSize / (settings.sampleRate || 48000);
  try { ctx = new AudioContext(opts); } catch { ctx = new AudioContext({ latencyHint: 'interactive' }); }
  buildGraph(ctx);
  loadSynth(ctx);
  void applyOutput();
  return ctx;
}

/** Выход SETTINGS → OUTPUT (там, где браузер умеет выбирать выход: AudioContext.setSinkId). */
export const canChooseOutput = () => 'setSinkId' in AudioContext.prototype;
export async function applyOutput() {
  const c = ctx as (AudioContext & { setSinkId?: (id: string) => Promise<void> }) | null;
  if (!c?.setSinkId) return;
  try { await c.setSinkId(settings.outputId); } catch (e) { console.error('output', e); }
}

/**
 * Пересоздать аудиоконтекст с новыми настройками (частота, буфер): весь граф строится заново,
 * сэмплы остаются в памяти, синты загружаются в новый контекст. Вызывать из касания (iOS).
 */
export async function restartAudio() {
  const old = ctx;
  if (!old) return;
  ctx = null;
  voices.length = 0;
  synths.fill(null);
  synthCpu.fill(0);
  wasmBytes = null;
  scopePre = scopePost = null;
  scopeOn = null;
  fxSig = '';
  irSig = '';
  tailUntil = 0;
  gateOpen.length = 0;
  unlockAudio();
  await old.close().catch(() => {});
}

/** Фактические параметры звука для SETTINGS. */
export function audioInfo() {
  const c = ctx;
  return { state: c?.state ?? 'none', sampleRate: c?.sampleRate ?? 0, baseLatency: c?.baseLatency ?? 0, outputLatency: (c as AudioContext & { outputLatency?: number })?.outputLatency ?? 0 };
}

/**
 * В iOS Safari звук можно включить только из действия пользователя (отпускание пальца):
 * при каждом таком касании, пока звук не включён, создаём/возобновляем контекст и проигрываем
 * беззвучный буфер — так iOS надёжно открывает вывод звука (в том числе после перерыва,
 * например после окна выбора файла, когда контекст становится «interrupted»).
 */
export function unlockAudio() {
  const c = ensureCtx();
  unmuteHtmlAudio();
  if (c.state === 'running') return;
  void c.resume().catch(() => { /* повторим на следующем касании */ });
  const src = c.createBufferSource();
  src.buffer = c.createBuffer(1, 1, c.sampleRate);
  src.connect(c.destination);
  src.start();
}

/**
 * Safari: Web Audio по умолчанию звучит как «системные звуки» и глушится переключателем
 * беззвучного режима и настройками сайта. Беззвучный зацикленный HTML-аудиоэлемент,
 * запущенный касанием, переводит страницу в режим воспроизведения медиа, и Web Audio звучит.
 */
let htmlAudio: HTMLAudioElement | null = null;

function silentWavUrl(): string {
  const n = 4000;
  const buf = new ArrayBuffer(44 + n);
  const v = new DataView(buf);
  const str = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  str(0, 'RIFF'); v.setUint32(4, 36 + n, true); str(8, 'WAVE');
  str(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, 8000, true); v.setUint32(28, 8000, true); v.setUint16(32, 1, true); v.setUint16(34, 8, true);
  str(36, 'data'); v.setUint32(40, n, true);
  for (let i = 0; i < n; i++) v.setUint8(44 + i, 128);
  return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }));
}

function unmuteHtmlAudio() {
  if (!htmlAudio) {
    htmlAudio = document.createElement('audio');
    htmlAudio.setAttribute('x-webkit-airplay', 'deny');
    htmlAudio.preload = 'auto';
    htmlAudio.loop = true;
    htmlAudio.src = silentWavUrl();
    // BACKGROUND: со включённой настройкой звук играет и в фоне (iOS не глушит страницу, пока
    // играет HTML-аудио); без неё при сворачивании звук останавливается.
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) { void ctx?.resume().catch(() => {}); return; }
      if (settings.background) return;
      htmlAudio?.pause();
      void ctx?.suspend().catch(() => {});
    });
    if ('mediaSession' in navigator) navigator.mediaSession.metadata = new MediaMetadata({ title: 'JAMbo', artist: 'Groovebox' });
  }
  if (htmlAudio.paused && (!document.hidden || settings.background)) void htmlAudio.play().catch(() => { /* повторим на следующем касании */ });
}

/** Состояние звука для подсказки на экране: running, suspended, interrupted или none. */
export const audioState = (): string => (ctx ? ctx.state : 'none');

function buildGraph(c: AudioContext) {
  // Мастер.
  const masterIn = c.createGain();
  // Сатуратор (saturator-worklet.js) встаёт между satIn и glueIn, компрессор «glue» (glue-worklet.js) —
  // между glueIn и clipIn, клиппер (clipper-worklet.js) —
  // между clipIn и limIn, лимитер (limiter-worklet.js) — между limIn и громкостью выхода, когда
  // модули загружены (до этого сигнал идёт мимо).
  const satIn = c.createGain();
  const glueIn = c.createGain();
  const clipIn = c.createGain();
  const limIn = c.createGain();
  // Источник T1…T16 динамических полос EQ — выход дорожки после громкости микшера (до mute).
  const dynSource: DynSource = (n) => tracks[n - 1]?.vol ?? null;
  setEqDynReady(false);
  void c.audioWorklet.addModule(new URL('eqdyn-worklet.js', document.baseURI).href)
    .then(() => { if (c === ctx) setEqDynReady(true); }).catch((e) => console.error('eqdyn', e));
  const eq = new EqChain(c, dynSource);
  masterIn.connect(eq.input);
  // Громкость выхода (регулятор на измерителе справа при MST) — после лимитера, перед выходом.
  const outVol = c.createGain();
  eq.output.connect(satIn).connect(glueIn).connect(clipIn).connect(limIn).connect(outVol).connect(c.destination);
  scopeTaps = [null, null, null, null];
  gSplit = gL = gR = null;
  mst = { eq, satIn, sat: null, glueIn, glue: null, clipIn, clip: null, limIn, lim: null, outVol, outMeter: new Meter(c, outVol, true) };
  satSig = '';
  glueSig = '';
  clipSig = '';
  limSig = '';
  // Общий 4× оверсэмплер (oversampler.js) — до сатуратора и клиппера.
  const os = c.audioWorklet.addModule(new URL('oversampler.js', document.baseURI).href);
  loadDevice(c, 'saturator-worklet.js', 'saturator', satIn, glueIn, satLevels, (n) => { mst!.sat = n; }, os);
  loadDevice(c, 'glue-worklet.js', 'glue', glueIn, clipIn, glueLevels, (n) => { mst!.glue = n; });
  loadDevice(c, 'clipper-worklet.js', 'clipper', clipIn, limIn, clipLevels, (n) => { mst!.clip = n; }, os);
  loadDevice(c, 'limiter-worklet.js', 'limiter', limIn, outVol, limLevels, (n) => { mst!.lim = n; });

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
  const l = c.createDelay(MAX_DELAY);
  const r = c.createDelay(MAX_DELAY);
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
  // Каналы на все 12 дорожек сразу: у несуществующих гейт закрыт.
  tracks = Array.from({ length: MAX_TRACKS }, () => {
    const input = c.createGain();
    const duck = c.createGain();
    const vol = c.createGain();
    const gate = c.createGain();
    const eq = new EqChain(c, dynSource);
    eq.output.connect(input);
    input.connect(duck).connect(vol).connect(gate).connect(masterIn);
    const sends = busInputs.map((bus) => {
      const g = c.createGain();
      g.connect(bus);
      return g;
    });
    const sendEqs = sends.map((g) => {
      // Копия EQ для посыла: сдвиг динамических полос — от детекторов основного EQ дорожки.
      const e = new EqChain(c, undefined, eq);
      e.output.connect(g);
      return e;
    });
    return { eq, sendEqs, input, duck, vol, gate, sends, meter: new Meter(c, vol, true) };
  });
}

/** Экран отладки: следующая нота сообщает, насколько позже текущего времени звука она стоит (с). */
let noteProbe: ((ahead: number) => void) | null = null;
export const probeNextNote = (f: (ahead: number) => void) => { noteProbe = f; };
function probe(at: number) {
  if (!noteProbe) return;
  noteProbe(at - ctx!.currentTime);
  noteProbe = null;
}

/** Время performance.now() → время контекста. */
function toCtx(perf: number): number {
  const c = ctx!;
  return Math.max(c.currentTime, c.currentTime + (perf - performance.now()) / 1000);
}

// ---------- Голоса ----------

/** Значение параметра голоса с p-lock и модуляцией; at — момент (performance.now) начала ноты. */
function value(track: number, id: string, locks: Record<string, number>, at?: number): number {
  const p = PARAM_BY_ID[id];
  const base = locks[id] ?? doc.tracks[track].params[id];
  return fromNorm(p, modulatedNorm(track, p, base, at));
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
/** Скорость воспроизведения: нота относительно определённой высоты сэмпла (root) + Pitch. */
const rateFor = (note: number, root: number, pitch: number) => Math.pow(2, (note - root + pitch) / 12);

/** Запустить ноты дорожки в момент time (performance.now). */
export function triggerTrack(track: number, time: number, notes: number[], locks: Record<string, number>, sound?: string) {
  // Контекст может ещё просыпаться после первого касания — ноты всё равно ставим в план.
  if (!ctx || ctx.state === 'closed') return;
  const t = doc.tracks[track];
  // У шага может быть свой звук (сэмпл или движок) вместо звука дорожки.
  const key = sound || t.sample;
  const engine = synthEngine(key);
  if (engine !== null) { triggerSynth(track, engine, time, notes, locks); return; }
  const buf = buffers.get(key);
  if (!buf) return;
  const at = toCtx(time);
  probe(at);
  // Начальные значения — с модуляцией на момент ноты (ENV запущен на это время).
  const v = (id: string) => value(track, id, locks, time);

  const startSec = (buf.duration * v('start')) / 100;
  const endSec = (buf.duration * v('end')) / 100;
  if (endSec - startSec < 0.003) return;
  const attack = v('attack') / 1000;
  const decay = v('decay') / 1000;
  // Высота сэмпла определяется только для индикации: воспроизведение всегда от C3.
  const root = SAMPLE_ROOT;

  for (const note of notes) {
    const rate = rateFor(note, root, v('pitch'));
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

    src.connect(amp).connect(level).connect(filter).connect(pan).connect(ch.eq.input);
    const sends = SENDS.map((id, k) => {
      const g = ctx!.createGain();
      g.gain.value = v(id) / 100;
      pan.connect(g).connect(ch.sendEqs[k].input);
      return g;
    });

    const playDur = (endSec - startSec) / rate;
    const stopAt = at + Math.min(playDur, attack + decay + 0.1);
    src.start(at, startSec, Math.max(0.003, (endSec - startSec)));
    src.stop(stopAt);
    const voice: Voice = { track, root, locks, note, at, src, synth: null, level, filter, pan, sends, ended: false };
    src.onended = () => {
      voice.ended = true;
      for (const n of [src, amp, level, filter, pan, ...sends]) n.disconnect();
    };
    voices.push(voice);
    if (voices.length > MAX_VOICES) {
      const old = voices.shift()!;
      try { old.src?.stop(); } catch { /* уже остановлен */ }
    }
  }
  sidechain(track, at);
}

/** Ноты синта: голоса по кругу, огибающая и параметры — на постоянной цепочке голоса. */
function triggerSynth(track: number, engine: number, time: number, notes: number[], locks: Record<string, number>) {
  const sy = ensureSynth(track);
  if (!sy) return;
  const at0 = toCtx(time);
  // Живой наигрыш: небольшой запас, чтобы нота успела дойти до AudioWorklet к началу огибающей
  // (иначе огибающая открывается раньше звука движка — щелчок).
  const at = Math.max(at0, ctx!.currentTime + 0.012);
  probe(at);
  const v = (id: string) => value(track, id, locks, time);
  const attack = Math.max(0.002, v('attack') / 1000);
  const decay = v('decay') / 1000;
  // Затухает сам движок (Decay управляет им): огибающая только с атакой, голос считается,
  // пока не затихнет (это отслеживает AudioWorklet).
  const selfDecay = SYNTH_ENGINES[engine].decay;
  // Голос молчит после затухания огибающей (дальше движок не считается — экономия процессора).
  const end = selfDecay ? at + attack + 15 : at + attack + Math.max(0.02, decay) * 2 + 0.05;
  const sr = ctx!.sampleRate;
  const events = notes.map((note) => {
    // Свободный голос (затих к моменту ноты), иначе — самый старый по кругу.
    let slot = -1;
    for (let k = 0; k < SYNTH_SLOTS; k++) {
      const c = (sy.next + k) % SYNTH_SLOTS;
      if (sy.busyUntil[c] <= at) { slot = c; break; }
    }
    const steal = slot < 0;
    if (steal) slot = sy.next;
    sy.next = (slot + 1) % SYNTH_SLOTS;
    const sl = sy.slots[slot];
    // Голос, который ещё звучит в этом слоте, уступает место новой ноте: быстро гаснет (≈5 мс),
    // и новая нота начинается после этого — без щелчка.
    for (const vo of voices) if (vo.synth && vo.track === track && vo.synth.slot === slot) vo.ended = true;
    const start = steal ? at + 0.008 : at;
    const g = sl.amp.gain;
    g.cancelScheduledValues(at);
    if (steal) g.setTargetAtTime(0, at, 0.0015);
    g.setValueAtTime(0, start);
    g.linearRampToValueAtTime(1, start + attack);
    if (!selfDecay) g.setTargetAtTime(0, start + attack, Math.max(0.005, decay / 4));
    sl.level.gain.setValueAtTime(levelGain(v('level')), start);
    applyFilter(sl.filter, v('filter'), v('reso'), start, false);
    sl.pan.pan.setValueAtTime(Math.max(-1, Math.min(1, v('pan') / 64)), start);
    SENDS.forEach((id, k) => sl.sends[k].gain.setValueAtTime(v(id) / 100, start));
    const stop = end + (start - at);
    sy.busyUntil[slot] = selfDecay ? start + attack + 0.3 + 4 * decay : stop;
    voices.push({ track, root: 0, locks, note, at: start, src: null, synth: { slot, engine, end: stop }, level: sl.level, filter: sl.filter, pan: sl.pan, sends: sl.sends, ended: false });
    return { type: 'note', slot, frame: Math.round(start * sr), end: Math.round(stop * sr), engine, note, ...synthParams(engine, v), accent: 0.8 };
  });
  sy.node.port.postMessage(events);
  sidechain(track, at);
}

/** Живой наигрыш с пианоролла: ноты выбранной дорожки сейчас. */
export function playNow(track: number, notes: number[], held = false) {
  // Живая нота тоже запускает ENV: гейт — пока держат клавишу (held, отпускание — releaseEnv),
  // иначе (ноты с MIDI) — один шаг.
  const now = performance.now();
  triggerEnv(track, now, held ? 1e9 : 60000 / doc.bpm / 4);
  triggerTrack(track, now, notes, {});
}

/** Sidechain: триг дорожки-источника приглушает остальные на их Sidechain amount. */
function sidechain(source: number, at: number) {
  const fx = liveFx();
  if (source !== fx['sc.source']) return;
  const atk = fx['sc.attack'] / 1000;
  const rel = fx['sc.release'] / 1000;
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
    if (vo.synth && c.currentTime > vo.synth.end) vo.ended = true;
    if (vo.ended) { voices.splice(k, 1); continue; }
    // Нота ещё не началась (запланирована наперёд) — её начальные значения уже выставлены.
    if (vo.at > c.currentTime) continue;
    const assigns = doc.tracks[vo.track].assigns;
    if (Object.keys(assigns).length === 0) continue;
    const v = (id: string) => value(vo.track, id, vo.locks);
    const now = c.currentTime;
    if (vo.synth && (assigns.harm || assigns.timbre || assigns.morph || (assigns.decay && SYNTH_ENGINES[vo.synth.engine].decay))) {
      synths[vo.track]?.node.port.postMessage([{ type: 'mod', slot: vo.synth.slot, note: vo.note, ...synthParams(vo.synth.engine, v) }]);
    }
    if (assigns.pitch && vo.src) vo.src.playbackRate.setTargetAtTime(rateFor(vo.note, vo.root, v('pitch')), now, 0.01);
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
  // Значения с p-lock играющих шагов (FX — любой дорожки, микшер — MIX, мастер — MST).
  const fx = liveFx(now);
  const mixer = liveMixer(now);
  const master = liveMaster(now);
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

  const fsig = JSON.stringify([fx, mixer, master, doc.ratio, doc.limBypass, doc.cmpBypass, doc.clipBypass, doc.bpm, doc.tracks.map((t) => +t.mute + 2 * +t.solo)]);
  if (fsig === fxSig) return;
  fxSig = fsig;
  set(rev.hpf.frequency, fx['rev.hpf']);
  set(rev.pre.delayTime, fx['rev.predelay'] / 1000);

  // Время Delay привязано к темпу: доля такта × длительность четверти.
  const time = Math.min(MAX_DELAY, DELAY_DIVS[Math.round(fx['dly.time'])].beats * 60 / doc.bpm);
  set(dly.l.delayTime, time);
  set(dly.r.delayTime, Math.min(MAX_DELAY, time * (1 + (fx['dly.stereo'] / 100) * 0.5)));
  // Пока идёт MUTE TAILS, обратная связь возвращается не раньше его конца.
  const fbAt = Math.max(ct, tailUntil);
  dly.fbL.gain.setTargetAtTime(fx['dly.feedback'] / 100 * 0.95, fbAt, 0.02);
  dly.fbR.gain.setTargetAtTime(fx['dly.feedback'] / 100 * 0.95, fbAt, 0.02);
  set(dly.hpf.frequency, fx['dly.hpf']);

  drv.shaper.curve = driveCurve(Math.round(fx['od.type'])) as Float32Array<ArrayBuffer>;
  set(drv.tone.frequency, 500 * Math.pow(24, fx['od.tone'] / 100));

  tracks.forEach((ch, i) => {
    const vol = volGain(mixer[`mix.vol${i + 1}`] ?? VOL_DEF_DB);
    set(ch.vol.gain, vol);
    gateTrack(i, vol, ct);
  });

  sendDynamics();
  set(mst.outVol.gain, volGain(doc.outVol));
}

/** Постоянная времени гейта mute/solo: закрывается и открывается за ~5 ms (3τ). */
const GATE_TAU = 0.0015;
/** MUTE TAILS: на столько секунд гасится обратная связь Delay, если заглушили его единственный источник. */
const TAIL_CUT = 0.1;
const gateOpen: boolean[] = [];
let tailUntil = 0;

/** Гейт дорожки i (mute/solo): выход и посылы; ноты заглушённой дорожки играют дальше (метр, sidechain, DYN EQ). */
function gateTrack(i: number, vol: number, ct: number) {
  const ch = tracks[i];
  const open = audible(i);
  ch.gate.gain.setTargetAtTime(open ? 1 : 0, ct, GATE_TAU);
  ch.sends.forEach((s) => s.gain.setTargetAtTime(open ? vol : 0, ct, GATE_TAU));
  if (gateOpen[i] === true && !open && settings.muteTails) cutDelayTail(i, ct);
  gateOpen[i] = open;
}

/** MUTE TAILS: заглушённая дорожка — единственный слышимый источник посыла Delay → гасим его повторы. */
function cutDelayTail(i: number, ct: number) {
  const sends = (k: number) => (doc.tracks[k]?.params.delay ?? 0) > 0;
  if (!sends(i) || doc.tracks.some((_, k) => k !== i && audible(k) && sends(k))) return;
  const fb = doc.fx['dly.feedback'] / 100 * 0.95;
  for (const g of [dly.fbL.gain, dly.fbR.gain]) {
    g.cancelScheduledValues(ct);
    g.setTargetAtTime(0, ct, GATE_TAU);
    g.setTargetAtTime(fb, ct + TAIL_CUT, 0.005);
  }
  tailUntil = ct + TAIL_CUT;
}

/**
 * Mute/solo сразу, из жеста (не дожидаясь кадра): гейты всех дорожек — solo одной меняет остальные.
 * Возвращает время вызова (performance.now) для экрана отладки.
 */
export function applyAllGates(): number {
  const t = performance.now();
  if (!ctx || !tracks.length) return t;
  const mixer = liveMixer(t);
  const ct = ctx.currentTime;
  tracks.forEach((_, i) => gateTrack(i, volGain(mixer[`mix.vol${i + 1}`] ?? VOL_DEF_DB), ct));
  return t;
}

/** Каждый кадр: эффекты, микшер, мастер и модуляция голосов. */
export function updateAudio(now: number) {
  if (!ctx) return;
  updateFx(now);
  updateEqs();
  // Узел синта создаётся заранее, когда синт выбран на дорожке (не на первой ноте).
  doc.tracks.forEach((t, i) => { if (synthEngine(t.sample) !== null) ensureSynth(i); });
  updateVoices();
}

// ---------- Эквалайзеры ----------

/** EQ канала без дорожки: выключен. */
const OFF_EQ = { on: false, bands: [] as never[] };

function updateEqs() {
  tracks.forEach((ch, i) => {
    const eq = doc.eqs[i] ?? OFF_EQ;
    ch.eq.update(eq);
    for (const e of ch.sendEqs) e.update(eq);
  });
  mst.eq.update(doc.masterEq);
}

// Спектр до и после EQ — только пока открыта панель EQ (анализаторы иначе отключены).
let scopePre: AnalyserNode | null = null;
let scopePost: AnalyserNode | null = null;
let scopeOn: EqChain | null = null;

/** Подключить анализаторы к EQ канала (дорожка или 'master'); null — отключить. */
export function setEqScope(channel: number | 'master' | null) {
  if (!ctx) return;
  const chain = channel === null ? null : channel === 'master' ? mst.eq : tracks[channel]?.eq ?? null;
  if (chain === scopeOn) return;
  if (!scopePre) {
    scopePre = ctx.createAnalyser();
    scopePost = ctx.createAnalyser();
    for (const a of [scopePre, scopePost!]) { a.fftSize = 4096; a.smoothingTimeConstant = 0.6; a.minDecibels = -100; a.maxDecibels = 0; }
  }
  if (scopeOn) {
    scopeOn.input.disconnect(scopePre);
    scopeOn.output.disconnect(scopePost!);
  }
  scopeOn = chain;
  if (chain) {
    chain.input.connect(scopePre);
    chain.output.connect(scopePost!);
  }
}

// ---------- Скоп мастера (гониометр и осциллоскоп при MST) ----------

/** Точки съёма осциллоскопа (0 сатуратор, 1 компрессор, 2 клиппер, 3 лимитер): узел и анализаторы L/R. */
interface ScopeTap { node: AudioNode; split: ChannelSplitterNode; l: AnalyserNode; r: AnalyserNode }
let scopeTaps: (ScopeTap | null)[] = [null, null, null, null];
/** Гониометр — всегда конечный сигнал мастера (после громкости выхода). */
let gSplit: ChannelSplitterNode | null = null;
let gL: AnalyserNode | null = null;
let gR: AnalyserNode | null = null;

function stereoAnalysers(c: AudioContext): [ChannelSplitterNode, AnalyserNode, AnalyserNode] {
  const split = c.createChannelSplitter(2);
  const l = c.createAnalyser();
  const r = c.createAnalyser();
  for (const a of [l, r]) { a.fftSize = 4096; a.smoothingTimeConstant = 0; }
  split.connect(l, 0);
  split.connect(r, 1);
  return [split, l, r];
}

/**
 * Включённые точки съёма осциллоскопа (их сигналы рисуются одновременно); null — скоп выключен.
 * Гониометр подключён к конечному выходу мастера, пока скоп включён.
 */
export function setMasterScope(on: boolean[] | null) {
  if (!ctx || !mst) return;
  if (on && !gSplit) {
    [gSplit, gL, gR] = stereoAnalysers(ctx);
    mst.outVol.connect(gSplit);
  } else if (!on && gSplit) {
    mst.outVol.disconnect(gSplit);
    gSplit = gL = gR = null;
  }
  // Пока устройство не загружено, его выход — следующий вход (сигнал идёт мимо).
  const nodes: AudioNode[] = [mst.glueIn, mst.clipIn, mst.limIn, mst.lim ?? mst.limIn];
  for (let k = 0; k < 4; k++) {
    const want = on?.[k] ? nodes[k] : null;
    const cur = scopeTaps[k];
    if ((cur?.node ?? null) === want) continue;
    if (cur) { try { cur.node.disconnect(cur.split); } catch { /* связь уже снята */ } }
    if (!want) { scopeTaps[k] = null; continue; }
    const [split, l, r] = cur ? [cur.split, cur.l, cur.r] : stereoAnalysers(ctx);
    want.connect(split);
    scopeTaps[k] = { node: want, split, l, r };
  }
}

/** Сигнал мастера в точке съёма k (L и R, по 4096 отсчётов); false — точка выключена. */
export function masterScope(k: number, L: Float32Array<ArrayBuffer>, R: Float32Array<ArrayBuffer>): boolean {
  const t = scopeTaps[k];
  if (!t) return false;
  t.l.getFloatTimeDomainData(L);
  t.r.getFloatTimeDomainData(R);
  return true;
}

/** Конечный сигнал мастера для гониометра (L и R); false — скоп выключен. */
export function masterGonio(L: Float32Array<ArrayBuffer>, R: Float32Array<ArrayBuffer>): boolean {
  if (!gL || !gR) return false;
  gL.getFloatTimeDomainData(L);
  gR.getFloatTimeDomainData(R);
  return true;
}

/** Текущий сдвиг динамических полос показанного EQ, dB (null — панель закрыта). */
export const eqDynDb = (): Float32Array | null => scopeOn?.dyn ?? null;

/** Спектр до и после EQ в dBFS (по бинам FFT); false — анализаторы не подключены. */
export function eqSpectrum(pre: Float32Array<ArrayBuffer>, post: Float32Array<ArrayBuffer>): boolean {
  if (!scopeOn || !scopePre || !scopePost) return false;
  scopePre.getFloatFrequencyData(pre);
  scopePost.getFloatFrequencyData(post);
  return true;
}

export const eqSampleRate = () => (ctx ? ctx.sampleRate : 48000);

/** Понижение усиления компрессора мастера (дБ, ≤ 0). */

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

// Файлы, выбранные в окне выбора (можно сразу несколько), декодируются и ложатся в папку
// дорожки (state: doc.folders) вместе с её пресетами; стрелки под окном сэмпла их перелистывают.
const fileKeys = new Map<File, string>();

/**
 * Декодировать файл (один раз): ключ сэмпла по содержимому; файл сохраняется в браузере
 * (IndexedDB) для проектов, имя и высота запоминаются в doc.
 */
async function decodeFile(file: File): Promise<string> {
  const c = ensureCtx();
  const known = fileKeys.get(file);
  if (known) return known;
  const bytes = await file.arrayBuffer();
  const key = await sampleKey(bytes);
  if (!buffers.has(key)) {
    // decodeAudioData может забрать буфер — декодируем копию.
    buffers.set(key, await c.decodeAudioData(bytes.slice(0)));
    void putSample({ key, name: file.name, bytes }).catch((e) => console.error('sample store', e));
  }
  fileKeys.set(file, key);
  doc.files[key] = file.name;
  const root = detectRoot(buffers.get(key)!);
  if (typeof root === 'number') doc.roots[key] = root;
  return key;
}

/** Сэмплы проекта из браузерного хранилища в память (перед открытием проекта). */
export async function ensureSamples(keys: string[]): Promise<void> {
  const c = ensureCtx();
  for (const key of keys) {
    if (buffers.has(key)) continue;
    const rec = await getSample(key);
    if (!rec) continue;
    try { buffers.set(key, await c.decodeAudioData(rec.bytes.slice(0))); } catch { /* испорченный файл */ }
  }
}

/** Байты сэмплов для экспорта проекта. */
export async function sampleRecords(keys: string[]): Promise<SampleRecord[]> {
  const out: SampleRecord[] = [];
  for (const key of keys) {
    const rec = await getSample(key);
    if (rec) out.push(rec);
  }
  return out;
}

/** Нераспознанные файлы пропускаются; если не открылся ни один — ошибка. */
async function decodeAll(files: File[]): Promise<string[]> {
  const keys: string[] = [];
  for (const f of files) {
    try { keys.push(await decodeFile(f)); } catch { /* не аудио */ }
  }
  if (files.length && !keys.length) throw new Error('no audio');
  return keys;
}

/** Файлы с iPad (IMPORT в браузере библиотеки): декодировать и сохранить; ключи и имена. */
export async function importAudioFiles(files: File[]): Promise<{ key: string; name: string }[]> {
  const out: { key: string; name: string }[] = [];
  for (const f of files) {
    try { out.push({ key: await decodeFile(f), name: f.name }); } catch { /* не аудио */ }
  }
  if (files.length && !out.length) throw new Error('no audio');
  return out;
}

/** Сэмпл из библиотеки: загрузить из хранилища, имя и высота — в проект. false — сэмпла нет. */
export async function useLibrarySample(key: string, name: string): Promise<boolean> {
  await ensureSamples([key]);
  const buf = buffers.get(key);
  if (!buf) return false;
  doc.files[key] = name;
  if (!(key in doc.roots)) {
    const root = detectRoot(buf);
    if (typeof root === 'number') doc.roots[key] = root;
  }
  return true;
}

/** Выбор файлов: все ложатся в папку выбранной дорожки, первый звучит на ней. */
export async function loadSampleFiles(files: File[]): Promise<void> {
  const track = ui.selectedTrack;
  addSamplesToFolder(track, await decodeAll(files));
}

/** Файлы для зажатых шагов: в папку дорожки, первый — звук этих шагов. */
export async function loadStepSample(files: File[], steps: number[]): Promise<void> {
  const track = ui.selectedTrack;
  const keys = await decodeAll(files);
  addSamplesQuiet(track, keys);
  setStepSound(track, steps, keys[0]);
}

/** Огибающая сэмпла для окна сэмпла: n пиков 0..1. */
export function samplePeaks(key: string, n = 160): Float32Array[] | null {
  const cached = peaks.get(key);
  if (cached) return cached;
  const buf = buffers.get(key);
  if (!buf) return null;
  // Стерео — две огибающие (L и R), моно — одна; общая нормировка.
  const chans = Math.min(2, buf.numberOfChannels);
  const out = Array.from({ length: chans }, () => new Float32Array(n));
  let max = 0;
  for (let ch = 0; ch < chans; ch++) {
    const d = buf.getChannelData(ch);
    const step = Math.max(1, Math.floor(d.length / n));
    for (let i = 0; i < n; i++) {
      let m = 0;
      for (let j = i * step; j < Math.min(d.length, (i + 1) * step); j++) m = Math.max(m, Math.abs(d[j]));
      out[ch][i] = m;
      max = Math.max(max, m);
    }
  }
  if (max > 0) for (const o of out) for (let i = 0; i < n; i++) o[i] /= max;
  peaks.set(key, out);
  return out;
}

// ---------- Редактор сэмпла ----------

/** Декодированный сэмпл (редактор сэмпла). */
export const sampleBuffer = (key: string): AudioBuffer | null => buffers.get(key) ?? null;

/**
 * Отредактированный сэмпл (TRIM, NORMALIZE, MONO): каналы data → новый сэмпл (WAV 24 бит, ключ по
 * содержимому, хранится в браузере), имя и высота — как у исходного from.
 */
export async function addEditedSample(from: string, data: Float32Array[], rate: number): Promise<string> {
  const c = ensureCtx();
  const buf = c.createBuffer(data.length, data[0].length, rate);
  data.forEach((d, ch) => buf.copyToChannel(d as Float32Array<ArrayBuffer>, ch));
  const bytes = encodeWav(buf);
  const key = await sampleKey(bytes);
  if (!buffers.has(key)) {
    buffers.set(key, buf);
    await putSample({ key, name: doc.files[from] ?? 'sample.wav', bytes });
  }
  doc.files[key] = doc.files[from] ?? 'sample.wav';
  if (typeof doc.roots[from] === 'number') doc.roots[key] = doc.roots[from];
  return key;
}

/** Сэмпл WAV-файлом (SAVE в редакторе): на iPad — в «Файлы». */
export function downloadSample(key: string) {
  const buf = buffers.get(key);
  if (!buf) return;
  const url = URL.createObjectURL(new Blob([encodeWav(buf)], { type: 'audio/wav' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `${(doc.files[key] ?? 'sample').replace(/\.[^.]+$/, '').replace(/[^\w\- ]+/g, '_') || 'sample'}.wav`;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

/** Сэмпл стерео (для индикации в окне сэмпла). */
export const sampleIsStereo = (key: string) => (buffers.get(key)?.numberOfChannels ?? 1) > 1;


// ---------- Измерители уровня ----------

export interface Level {
  /** Пиковый уровень по каналам (0..1+, с плавным спадом). */
  l: number;
  r: number;
  /** Громкость LUFS (momentary, ~400 мс), -Infinity — тишина. */
  lufs: number;
  /** Интегральная громкость LUFS с последнего сброса (BS.1770: пороги −70 LUFS и −10 LU). */
  lufsI: number;
  /** Была перегрузка (≥ 0 dBFS) за последние 2 с — метка клиппинга. */
  clip: boolean;
  /** Пик-холд по каналам: держится ~1,5 с, потом плавно спадает. */
  holdL: number;
  holdR: number;
  /** Максимальный пик с последнего сброса (число над метром, тап — сброс). */
  max: number;
}

/** Интегральная громкость: абсолютный порог и корзины по 0,1 LU от него до +10 LUFS. */
const INT_ABS_GATE = -70;
const INT_BINS = 800;

/** Измеритель: пики по каналам и (по желанию) K-взвешенная громкость. */
class Meter {
  private an: AnalyserNode[];
  private k: AnalyserNode[] = [];
  private buf = new Float32Array(1024);
  private kbuf: Float32Array<ArrayBuffer> | null = null;
  private disp = [0, 0];
  private hold = [0, 0];
  private holdAt = [0, 0];
  private max = 0;
  private clipUntil = 0;
  private lufsCache = -Infinity;
  private lufsAt = 0;
  /**
   * Интегральная громкость: блоки (~400 мс, каждые 100 мс — перекрытие 75%) выше −70 LUFS
   * копятся по корзинам 0,1 LU (число и энергия) — память не растёт со временем.
   */
  private binN = new Float64Array(INT_BINS);
  private binE = new Float64Array(INT_BINS);
  private lufsI = -Infinity;

  /** Сброс максимального пика (тап по dB, смена канала измерителя). */
  resetPeak() {
    this.max = 0;
  }

  /** Сброс интегральной громкости (тап по LUFS, смена канала измерителя). */
  resetIntegrated() {
    this.binN.fill(0);
    this.binE.fill(0);
    this.lufsI = -Infinity;
  }

  private integrate(energy: number) {
    const l = energy > 1e-10 ? -0.691 + 10 * Math.log10(energy) : -Infinity;
    if (l <= INT_ABS_GATE) return;
    const b = Math.min(INT_BINS - 1, Math.floor((l - INT_ABS_GATE) * 10));
    this.binN[b]++;
    this.binE[b] += energy;
    // Относительный порог: средняя громкость блоков выше −70 LUFS минус 10 LU.
    let n = 0;
    let e = 0;
    for (let i = 0; i < INT_BINS; i++) { n += this.binN[i]; e += this.binE[i]; }
    const rel = -0.691 + 10 * Math.log10(e / n) - 10;
    const from = Math.max(0, Math.ceil((rel - INT_ABS_GATE) * 10));
    n = 0;
    e = 0;
    for (let i = from; i < INT_BINS; i++) { n += this.binN[i]; e += this.binE[i]; }
    this.lufsI = n ? -0.691 + 10 * Math.log10(e / n) : -Infinity;
  }

  constructor(c: AudioContext, src: AudioNode, lufs: boolean) {
    const split = c.createChannelSplitter(2);
    src.connect(split);
    this.an = [0, 1].map((ch) => {
      const a = c.createAnalyser();
      a.fftSize = 1024;
      split.connect(a, ch);
      return a;
    });
    if (lufs) {
      this.kbuf = new Float32Array(16384);
      this.k = [0, 1].map((ch) => {
        // K-взвешивание (ITU-R BS.1770): полка +4 дБ выше 1.5 кГц и срез ниже 38 Гц.
        const shelf = c.createBiquadFilter();
        shelf.type = 'highshelf';
        shelf.frequency.value = 1682;
        shelf.gain.value = 4;
        const hp = c.createBiquadFilter();
        hp.type = 'highpass';
        hp.frequency.value = 38;
        hp.Q.value = 0.5;
        const a = c.createAnalyser();
        a.fftSize = 16384;
        split.connect(shelf, ch).connect(hp).connect(a);
        return a;
      });
    }
  }

  private last: Level | null = null;
  private lastAt = -1;

  /** Чтение раз в кадр: повторный вызов с тем же now возвращает то же значение. */
  read(now: number): Level {
    if (now === this.lastAt && this.last) return this.last;
    this.lastAt = now;
    this.last = this.measure(now);
    return this.last;
  }

  private measure(now: number): Level {
    const peak = this.an.map((a) => {
      a.getFloatTimeDomainData(this.buf);
      let m = 0;
      for (const v of this.buf) m = Math.max(m, Math.abs(v));
      return m;
    });
    peak.forEach((p, i) => {
      this.disp[i] = Math.max(p, this.disp[i] * 0.9);
      // Пик-холд: новый пик фиксируется на 1,5 с, затем линия плавно опускается.
      if (p >= this.hold[i]) { this.hold[i] = p; this.holdAt[i] = now; } else if (now - this.holdAt[i] > 1500) this.hold[i] *= 0.95;
      this.max = Math.max(this.max, p);
    });
    if (Math.max(...peak) >= OVER_PEAK) this.clipUntil = now + 2000;
    // LUFS считаем не чаще 10 раз в секунду: окно большое.
    if (this.kbuf && now - this.lufsAt > 100) {
      this.lufsAt = now;
      let sum = 0;
      for (const a of this.k) {
        a.getFloatTimeDomainData(this.kbuf);
        let ms = 0;
        for (const v of this.kbuf) ms += v * v;
        sum += ms / this.kbuf.length;
      }
      this.lufsCache = sum > 1e-10 ? -0.691 + 10 * Math.log10(sum) : -Infinity;
      this.integrate(sum);
    }
    return {
      l: this.disp[0], r: this.disp[1], lufs: this.lufsCache, lufsI: this.lufsI, clip: now < this.clipUntil,
      holdL: this.hold[0], holdR: this.hold[1], max: this.max,
    };
  }
}

const SILENT: Level = { l: 0, r: 0, lufs: -Infinity, lufsI: -Infinity, clip: false, holdL: 0, holdR: 0, max: 0 };

/** Снижение громкости дорожки от sidechain, дБ (≤ 0). */
export function trackDuckDb(i: number): number {
  const g = tracks[i]?.duck.gain.value ?? 1;
  return g < 0.999 ? 20 * Math.log10(Math.max(1e-4, g)) : 0;
}

/** Lookahead лимитера — показывается числом. */

/** Уровень дорожки (после громкости микшера). */
export const trackLevel = (i: number, now: number): Level => (tracks[i] ? tracks[i].meter.read(now) : SILENT);

/** Оконечный сигнал мастера после громкости выхода (компрессор и лимитер — glueMeter, limiterMeter). */
export function masterLevels(now: number): { out: Level } {
  return { out: mst ? mst.outMeter.read(now) : SILENT };
}

/** Сброс интегральной громкости измерителя справа: дорожка i или выход мастера ('master'). */
export function resetLoudness(ch: number | 'master') {
  if (ch === 'master') mst?.outMeter.resetIntegrated();
  else tracks[ch]?.meter.resetIntegrated();
}

/** Сброс максимального пика измерителя справа: дорожка i или выход мастера ('master'). */
export function resetPeak(ch: number | 'master') {
  if (ch === 'master') mst?.outMeter.resetPeak();
  else tracks[ch]?.meter.resetPeak();
}

/** Снижение усиления лимитера (дБ, ≤ 0). */

/** Дорожка звучит в стерео: стереофайл или панорама не по центру. */
export function trackIsStereo(i: number): boolean {
  const t = doc.tracks[i];
  if (!t) return false;
  const buf = buffers.get(t.sample);
  if ((buf?.numberOfChannels ?? 1) > 1 || Math.abs(t.params.pan) >= 1) return true;
  // Панораму двигают LFO/ENV или p-lock шагов — сигнал тоже стерео (L и R различаются).
  if (Math.abs(t.assigns.pan?.amount ?? 0) > 0) return true;
  return t.pages.some((pg) => pg.some((s) => s && Math.abs(s.locks.pan ?? 0) >= 1));
}

/** Определённая высота сэмпла (MIDI) или null. */
export const sampleRoot = (key: string): number | null => doc.roots[key] ?? null;
