// Звуковой движок (Web Audio). Читает состояние из state.ts и ничего в нём не меняет,
// кроме загрузки сэмплов из файлов.
//
// Голос (на каждую ноту трига):
//   сэмпл или голос синта → огибающая Attack/Decay → Level → фильтр LP/HP → Pan → вход дорожки
//                                                                          ↘ посылы Reverb / Delay / Drive
// Синт — движки Mutable Instruments Plaits (plaits.wasm в AudioWorklet) и свои движки JAMbo
// (jambo-synth-worklet.js): на дорожку по узлу каждого нужного семейства, у узла SYNTH_SLOTS голосов;
// оба узла идут в одни и те же постоянные цепочки голосов (огибающая ставится на триге), поэтому
// смена семейства (в том числе звуком шага) не пересоздаёт цепочки и не щёлкает: голос другого
// семейства в занятом слоте глушится сообщением stop в кадре новой ноты.
// Дорожка: EQ → вход → sidechain (приглушение) → громкость микшера → mute/solo → мастер. EQ стоит до эффектов:
// у каждого посыла голоса своя копия EQ дорожки с теми же полосами.
// Мастер: EQ → компрессор (Threshold, Attack, Release, Ratio, Makeup) → лимитер (Input, Ceiling,
// Lookahead, Release) → выход.
//
// Параметры голоса берутся на шаге с учётом p-lock и модуляции; если на ручку назначен LFO
// или ENV, значения голоса обновляются каждый кадр, пока он звучит.
// Измерители уровня стоят на выходе каждой дорожки и в мастере (вход компрессора, вход и выход
// лимитера): пиковый уровень по каналам и громкость в LUFS (K-взвешивание, окно ~400 мс).

import { BPM_MIN, stepIndex, DELAY_DIVS, isAuto, OVER_PEAK, DRUM_ENGINE, isJambo, SYNTH_ENGINES, synthEngine, PARAM_BY_ID, VOL_DEF_DB, volGain, SAMPLE_ROOT, MAX_TRACKS, filterFreq, fromNorm } from '../params';
import { tempo } from '../tempo';
import { audible, addSamplesQuiet, addSamplesToFolder, doc, setStepSound, triggerEnv, liveFx, liveMaster, liveMixer, modulatedNorm, ui, baseValue, autoLive, sliceMarks, sliceOf } from '../state';
import { detectRoot } from './pitch';
import { encodeWav } from './wav';
import { settings } from '../settings';
import { getSample, putSample, sampleKey, type SampleRecord } from '../storage';
import { EqChain, setEqDynReady, type DynSource } from './eq';
import { getTable } from './wavetable';

let ctx: AudioContext | null = null;
const buffers = new Map<string, AudioBuffer>();
const peaks = new Map<string, Float32Array[]>();

interface TrackChain {
  /** EQ сухого сигнала и копии EQ для посылов Reverb / Delay / Drive. */
  eq: EqChain; sendEqs: EqChain[];
  input: GainNode; duck: GainNode; vol: GainNode;
  /** Глубина sidechain: огибающая duck-worklet · (−amount) → duck.gain (значение 1). */
  duckDepth: GainNode;
  /** Sidechain посылов: g посыла → sendDuck[k] (значение 1) → шина; глубина → sendFlag[k] (1 / 0 — переключатель SETTINGS) → sendDuck[k].gain. */
  sendDuck: GainNode[];
  sendFlag: GainNode[];
  /** Mute / solo: глушит выход дорожки (сухой и посылы); метр стоит до него — уровень виден и у заглушённой. */
  gate: GainNode; sends: GainNode[]; meter: Meter;
}
interface Voice {
  track: number;
  root: number;
  locks: Record<string, number>;
  note: number;
  /** Нота высоты: у нарезки (маркеры сэмпла) — исходная высота (root), иначе — note. */
  rateNote?: number;
  /** Голос сэмпла: что играет (для полосы воспроизведения) — ключ, начало и конец (доли), скорость. */
  play?: { key: string; a: number; b: number; dur: number; rate: number };
  /** Время начала ноты (контекст): до него модуляция голос не трогает. */
  at: number;
  /** Сэмпл; у голоса синта — null (звучит слот synth). */
  src: AudioBufferSourceNode | null;
  synth: { slot: number; engine: number; end: number; id: number } | null;
  /** Конец удержания (контекст; Infinity — живая нота): до него нота держит уровень. */
  hold: number;
  /** Свой звук шага (или предпрослушка) — смена звука дорожки его не трогает. */
  own: boolean;
  /** Последние отправленные значения ручек: голос подхватывает поворот ручки, а не только следующую ноту. */
  sig?: string;
  vals?: number[];
  /** Значения идут по расписанию наперёд (автоматизация): при выходе из него — сбросить расписание. */
  sched?: boolean;
  /** Конец расписания (время контекста). */
  schedEnd?: number;
  level: GainNode;
  filter: BiquadFilterNode;
  pan: StereoPannerNode;
  sends: GainNode[];
  ended: boolean;
  /** Живая нота держится, пока держат клавишу: отпускание — releaseLive (дальше Decay как Release). */
  held?: { amp: AudioParam; decay: number; id: number };
}

/** Номер ноты синта: сообщение 'end' меняет конец именно этой ноты (слот мог занять другой голос). */
let noteId = 0;

let tracks: TrackChain[] = [];
let busInputs: GainNode[] = [];
const voices: Voice[] = [];

// ---------- Синт (Plaits и свои движки JAMbo) ----------

const SYNTH_SLOTS = 6;
type Family = 'plaits' | 'jambo';
interface SynthSlot { amp: GainNode; level: GainNode; filter: BiquadFilterNode; pan: StereoPannerNode; sends: GainNode[] }
interface Synth {
  nodes: Partial<Record<Family, AudioWorkletNode>>; slots: SynthSlot[]; next: number; busyUntil: number[];
  /** Семейство голоса, который последним занимал слот. */
  slotFamily: (Family | null)[];
  cpu: Record<Family, number>;
  /** Таблица WTABLE, отправленная в узел JAMbo (ключ). */
  table: string | null;
}
const synths: (Synth | null)[] = Array(MAX_TRACKS).fill(null);
let wasmBytes: ArrayBuffer | null = null;
let jamboReady = false;

/** Загрузить AudioWorklet'ы (plaits.wasm и свои движки) — один раз, после создания контекста. */
function loadSynth(c: AudioContext) {
  const url = (f: string) => new URL(f, document.baseURI).href;
  void Promise.all([
    c.audioWorklet.addModule(url('plaits-worklet.js')),
    fetch(url('plaits.wasm')).then((r) => r.arrayBuffer()),
  ]).then(([, bytes]) => { if (ctx === c) wasmBytes = bytes; }).catch((e) => console.error('synth', e));
  void c.audioWorklet.addModule(url('jambo-synth-worklet.js'))
    .then(() => { if (ctx === c) jamboReady = true; }).catch((e) => console.error('jambo synth', e));
}

const familyOf = (engine: number): Family => SYNTH_ENGINES[engine].family;

/**
 * Узел синта дорожки нужного семейства и постоянные цепочки голосов (создаются, когда синт выбран).
 * Цепочки общие для обоих семейств; узел семейства добавляется при первой ноте или выборе движка.
 */
function ensureSynth(track: number, family: Family): Synth | null {
  if (!ctx) return null;
  const sy = synths[track] ?? createSynthChains(track);
  if (sy.nodes[family]) return sy;
  if (family === 'plaits' ? !wasmBytes : !jamboReady) return null;
  const node = new AudioWorkletNode(ctx, family === 'plaits' ? 'plaits' : 'jambo-synth', {
    numberOfInputs: 0,
    numberOfOutputs: SYNTH_SLOTS,
    outputChannelCount: Array(SYNTH_SLOTS).fill(1),
    processorOptions: family === 'plaits' ? { bytes: wasmBytes, slots: SYNTH_SLOTS } : { slots: SYNTH_SLOTS },
  });
  node.port.onmessage = (e) => {
    if (typeof e.data?.cpu !== 'number') return;
    sy.cpu[family] = e.data.cpu;
    synthCpu[track] = sy.cpu.plaits + sy.cpu.jambo;
  };
  sy.slots.forEach((sl, k) => node.connect(sl.amp, k));
  sy.nodes[family] = node;
  if (family === 'jambo') sy.table = null;
  return sy;
}

/** Таблица WTABLE дорожки — в её узел JAMbo (когда сменилась или узел новый). Мипмапы — в основном потоке. */
function sendTable(track: number, key: string) {
  const sy = synths[track];
  const node = sy?.nodes.jambo;
  if (!sy || !node || sy.table === key) return;
  sy.table = key;
  void getTable(key).then((tb) => {
    if (tb && sy.nodes.jambo === node && sy.table === key) node.port.postMessage({ type: 'table', frames: tb.frames, levels: tb.levels });
  });
}

/** Постоянные цепочки голосов синта дорожки (огибающая, Level, фильтр, Pan, посылы). */
function createSynthChains(track: number): Synth {
  const c = ctx!;
  const ch = tracks[track];
  const slots = Array.from({ length: SYNTH_SLOTS }, () => {
    const amp = c.createGain();
    amp.gain.value = 0;
    const level = c.createGain();
    const filter = c.createBiquadFilter();
    const pan = c.createStereoPanner();
    amp.connect(level).connect(filter).connect(pan).connect(ch.eq.input);
    const sends = SENDS.map((_, i) => {
      const g = c.createGain();
      g.gain.value = 0;
      pan.connect(g).connect(ch.sendEqs[i].input);
      return g;
    });
    return { amp, level, filter, pan, sends };
  });
  return (synths[track] = {
    nodes: {}, slots, next: 0, busyUntil: Array(SYNTH_SLOTS).fill(0), slotFamily: Array(SYNTH_SLOTS).fill(null),
    cpu: { plaits: 0, jambo: 0 }, table: null,
  });
}

/** Ручка Decay (мс) → затухание движка Plaits 0..1. */
const decayNorm = (ms: number) => Math.sqrt(Math.min(1, Math.max(0, ms / 4000)));

/**
 * Параметры движка 0..1 для голоса синта (с p-lock и модуляцией). У движков, где Morph в Plaits —
 * затухание, затухание берётся с ручки Decay, а Morph смешивает выходы OUT и AUX.
 */
function synthParams(engine: number, v: (id: string) => number) {
  // Свои движки: ручки 1.1–1.3 — p1, p2, p3 (0..1), Decay — в мс (без пересчёта для Plaits).
  if (isJambo(engine)) return { p1: v('harm') / 100, p2: v('timbre') / 100, p3: v('morph') / 100, decay: v('decay') };
  // Ступенчатая 1.1 с привязкой (SPEECH): harmonics — точка пункта, а не положение ручки.
  const pts = SYNTH_ENGINES[engine].harmPoints;
  const harmonics = pts ? pts[stepIndex(v('harm') / 100, pts.length)] : v('harm') / 100;
  const timbre = v('timbre') / 100;
  if (SYNTH_ENGINES[engine].decay) return { harmonics, timbre, morph: decayNorm(v('decay')), aux: v('morph') / 100 };
  return { harmonics, timbre, morph: v('morph') / 100, aux: 0 };
}

// Нагрузка расчёта синтов: доля реального времени по каждой дорожке (присылает AudioWorklet).
const synthCpu: number[] = Array(MAX_TRACKS).fill(0);
/** Нагрузка эффектов в AudioWorklet (группа FX: реверб; по инстансу). */
const fxCpu = new Map<object, number>();
/** Суммарная нагрузка расчёта синтов и эффектов FX в AudioWorklet (доля 0..1). */
export const synthLoad = () => synthCpu.reduce((a, b) => a + b, 0) + [...fxCpu.values()].reduce((a, b) => a + b, 0);

// ---------- Реверб (AudioWorklet) ----------

/**
 * Инстанс реверба: вход → узел → выход. Состояние — в своём узле, без общих переменных, поэтому
 * инстансов может быть сколько угодно (общий на шине или на каждой дорожке — сравнение на этапе 7).
 * Параметры — AudioParam size, decay, tone, lowcut, predelay (внутри узла сглаживаются).
 */
interface Reverb { node: AudioWorkletNode | null; set: (fx: Record<string, number>, ct: number) => void }

/** Выходное усиление шины Drive (как у прежнего Overdrive). */
const DRIVE_OUT = 0.5;
/** Эффект на AudioWorklet (шина посыла): узел появляется, когда модуль загружен. */
interface FxNode { node: AudioWorkletNode | null }
const fxModules = new Map<string, Promise<void>>();
/** Загрузить worklet-эффект (file, name) между input и output; состояние — в инстансе, их может быть сколько угодно. */
function createFx(c: AudioContext, file: string, name: string, input: AudioNode, output: AudioNode, options: Record<string, unknown> = {}, after: Promise<unknown> = Promise.resolve()): FxNode {
  const fx: FxNode = { node: null };
  let mod = fxModules.get(file);
  if (!mod) { mod = after.then(() => c.audioWorklet.addModule(new URL(file, document.baseURI).href)); fxModules.set(file, mod); }
  void mod.then(() => {
    if (c !== ctx) return;
    const node = new AudioWorkletNode(c, name, {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2], channelCount: 2, channelCountMode: 'explicit', processorOptions: options,
    });
    node.port.onmessage = (e) => { if (typeof e.data?.cpu === 'number') fxCpu.set(fx, e.data.cpu); };
    input.connect(node).connect(output);
    fx.node = node;
    // Текущие значения сразу (иначе первый блок — значения по умолчанию).
    fxSig = '';
  }).catch((e) => console.error(name, e));
  return fx;
}

let reverbModule: Promise<void> | null = null;
function createReverb(c: AudioContext, input: AudioNode, output: AudioNode): Reverb {
  const r: Reverb = {
    node: null,
    set(fx, ct) {
      const n = r.node;
      if (!n) return;
      const p = (name: string, v: number) => n.parameters.get(name)?.setTargetAtTime(v, ct, 0.01);
      p('size', fx['rev.size']);
      p('decay', fx['rev.decay']);
      p('tone', fx['rev.tone'] ?? 0);
      p('lowcut', fx['rev.hpf']);
      p('predelay', fx['rev.predelay'] ?? 0);
    },
  };
  reverbModule ??= c.audioWorklet.addModule(new URL('reverb-worklet.js', document.baseURI).href);
  void reverbModule.then(() => {
    if (c !== ctx) return;
    const node = new AudioWorkletNode(c, 'reverb', {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2], channelCount: 2, channelCountMode: 'explicit',
    });
    node.port.onmessage = (e) => { if (typeof e.data?.cpu === 'number') fxCpu.set(r, e.data.cpu); };
    input.connect(node).connect(output);
    r.node = node;
    // Текущие значения сразу (иначе первый блок — значения по умолчанию).
    fxSig = '';
  }).catch((e) => console.error('reverb', e));
  return r;
}
const MAX_VOICES = 48;

// Узлы эффектов и мастера.
/** Реверб (reverb-worklet.js): узел появляется, когда модуль загружен (до этого хвоста нет). */
let rev: Reverb;
/** Delay (delay-worklet.js): узел появляется, когда модуль загружен (до этого эха нет). */
let dly: FxNode;
/** Drive (drive-worklet.js): узел появляется, когда модуль загружен. */
let drv: FxNode;
let mst: {
  eq: EqChain; satIn: GainNode; sat: AudioWorkletNode | null; glueIn: GainNode; glue: AudioWorkletNode | null; clipIn: GainNode; clip: AudioWorkletNode | null;
  limIn: GainNode; lim: AudioWorkletNode | null; outVol: GainNode;
  outMeter: Meter;
};

const SENDS = ['reverb', 'delay', 'drive'] as const;
/** Наибольшее время Delay, с (1 такт при 40 BPM — 6 с, со Stereo — до 9 с). */
/** Наибольшее время Delay, с: 1 такт (4 доли) при наименьшем темпе. */
const MAX_DELAY = (4 * 60) / BPM_MIN;

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
 * Телеметрия лимитера: кадр раз в 256 отсчётов (вход после GAIN и выход — true peak, линейно; GR — dB ≥ 0),
 * кольцевой буфер LIM_TELE кадров (окно лимитера рисует из него). Блок LIM — максимум последних кадров
 * (≈ кадр экрана). Включена, пока виден блок LIM (MST) или окно лимитера.
 */
export const LIM_TELE = 2048;
/** Кольцевой буфер телеметрии: in, out — пик (линейно), gr — dB ≥ 0, det — уровень детектора (dB, у компрессора). */
export interface Tele { in: Float32Array; out: Float32Array; gr: Float32Array; det: Float32Array; n: number; at: number }
const makeTele = (): Tele => ({ in: new Float32Array(LIM_TELE), out: new Float32Array(LIM_TELE), gr: new Float32Array(LIM_TELE), det: new Float32Array(LIM_TELE), n: 0, at: 0 });
export const limTele = makeTele();
/**
 * Телеметрия компрессора: [пик входа, уровень детектора (dB), GR (dB), пик выхода] раз в 256 отсчётов —
 * окно компрессора; включена, пока виден блок COMP (MST) или окно.
 */
export const compTele = makeTele();
/** Телеметрия клиппера: [пик после INPUT, срез (dB), пик выхода] — окно клиппера (LEVEL) и блок CLIP. */
export const clipTele = makeTele();
/**
 * Телеметрия сатуратора (только при открытом окне): раз в 256 отсчётов мин./макс. входа и выхода (WAVE) и точка
 * TRANSFER (вход — отсчёт с наибольшим модулем, выход — кривая для него). Кольцо LIM_TELE кадров.
 */
export const satTele = {
  inLo: new Float32Array(LIM_TELE), inHi: new Float32Array(LIM_TELE), outLo: new Float32Array(LIM_TELE), outHi: new Float32Array(LIM_TELE),
  n: 0, at: 0, px: 0, py: 0,
};
/** Снимок формы клиппера (вид WAVE): 1024 отсчёта входа после INPUT и выхода, канал (0 — L, 1 — R), время прихода. */
export const clipWave = { inp: new Float32Array(1024), out: new Float32Array(1024), ch: 0, at: 0, n: 0 };
/** Кадров телеметрии на секунду. */
export const limTeleRate = () => (ctx ? ctx.sampleRate / 256 : 187.5);
function teleFrame(t: Tele, levels: DynLevels, i: number, g: number, o: number, d = -120) {
  const k = t.n % LIM_TELE;
  t.in[k] = i; t.gr[k] = g; t.out[k] = o; t.det[k] = d;
  t.n++;
  t.at = performance.now();
  // Блок LIM/COMP: наибольшее за последние 3 кадра (~16 ms — кадр экрана), чтобы пики между кадрами не терялись.
  let mi = 0, mg = 0, mo = 0;
  for (let j = 0; j < 3 && j < t.n; j++) {
    const q = (t.n - 1 - j) % LIM_TELE;
    mi = Math.max(mi, t.in[q]); mg = Math.max(mg, t.gr[q]); mo = Math.max(mo, t.out[q]);
  }
  levels.in = mi; levels.gr = mg; levels.out = mo; levels.at = t.at;
}

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
      if (name === 'glue') { const [i, d, g, o] = e.data as number[]; teleFrame(compTele, levels, i, g, o, d); return; }
      if (name === 'saturator') {
        const [a, b, c2, d, px, py] = e.data as number[];
        const t = satTele;
        const q = t.n % LIM_TELE;
        t.inLo[q] = a; t.inHi[q] = b; t.outLo[q] = c2; t.outHi[q] = d; t.px = px; t.py = py;
        t.n++;
        t.at = performance.now();
        return;
      }
      if (name === 'clipper' && e.data && (e.data as { wave?: boolean }).wave) {
        const w = e.data as { inp: Float32Array<ArrayBuffer>; out: Float32Array<ArrayBuffer>; ch: number };
        clipWave.inp = w.inp; clipWave.out = w.out; clipWave.ch = w.ch; clipWave.at = performance.now(); clipWave.n++;
        return;
      }
      const [i, g, o] = e.data as number[];
      if (name === 'limiter') { teleFrame(limTele, levels, i, g, o); return; }
      if (name === 'clipper') { teleFrame(clipTele, levels, i, g, o); return; }
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
    // BYPASS сатуратора — MIX 0: worklet за 20 мс уходит в сухой сигнал (с той же задержкой) — без щелчка.
    const msg = {
      drive: m['sat.drive'], type: Math.round(m['sat.type']), tone: m['sat.tone'], mix: doc.satBypass ? 0 : m['sat.mix'],
      bias: m['sat.bias'] ?? 0, focus: m['sat.focus'] ?? 20, out: m['sat.out'] ?? 0, auto: (m['sat.auto'] ?? 1) >= 0.5,
      // Телеметрия — только пока открыто окно сатуратора.
      meter: ui.satView,
    };
    const sig = JSON.stringify(msg);
    if (sig !== satSig) { satSig = sig; mst.sat.port.postMessage(msg); }
  }
  if (mst.glue) {
    const msg = {
      thr: m['cmp.threshold'], att: m['cmp.attack'], ...auto(m['cmp.release']),
      makeup: m['cmp.makeup'], ratio: m['cmp.ratio'] ?? 2, bypass: doc.cmpBypass,
      knee: m['cmp.knee'] ?? 6, range: m['cmp.range'] ?? 40, hold: m['cmp.hold'] ?? 0, mix: m['cmp.mix'] ?? 100,
      link: m['cmp.link'] ?? 100, schpf: m['cmp.schpf'] ?? 90,
      // AUDIT — только пока открыто окно компрессора; телеметрия — пока виден блок COMP (MST) или окно.
      audit: ui.compView && ui.compAudit, meter: ui.channel === 'master' || ui.compView,
    };
    const sig = JSON.stringify(msg);
    if (sig !== glueSig) { glueSig = sig; mst.glue.port.postMessage(msg); }
  }
  if (mst.clip) {
    const msg = {
      drive: m['clip.drive'], ceiling: m['clip.ceiling'], softness: m['clip.softness'], bass: m['clip.bass'], bypass: doc.clipBypass,
      mix: m['clip.mix'] ?? 100,
      // UNITY и AUDIT — только пока открыто окно клиппера; кадры — пока виден блок CLIP (MST) или окно; снимки — вид WAVE окна.
      unity: ui.clipView && ui.clipUnity, audit: ui.clipView && ui.clipAudit, meter: ui.channel === 'master' || ui.clipView,
      wave: ui.clipView && settings.clipDisplay === 'wave',
    };
    const sig = JSON.stringify(msg);
    if (sig !== clipSig) { clipSig = sig; mst.clip.port.postMessage(msg); }
  }
  if (mst.lim) {
    const msg = {
      gain: m['lim.input'], ceiling: m['lim.ceiling'], lookahead: m['lim.lookahead'], ...auto(m['lim.release']), bypass: doc.limBypass,
      link: m['lim.link'] ?? 100,
      // UNITY и AUDIT — только пока открыто окно лимитера; телеметрия — пока виден блок LIM (MST) или окно.
      unity: ui.limView && ui.limUnity, audit: ui.limView && ui.limAudit, meter: ui.channel === 'master' || ui.limView,
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
  preview = null;
  wasmBytes = null;
  jamboReady = false;
  scopePre = scopePost = null;
  outScope = null;
  satScope = null;
  scopeOn = null;
  fxSig = '';
  reverbModule = null;
  duckNode = null;
  duckE = 0;
  duckSig = '';
  fxCpu.clear();
  fxModules.clear();
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
  masterInput = masterIn;
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

  // Reverb: AudioWorklet (LOW CUT, пред-задержка, диффузия, FDN) — общий на шине посыла.
  const revIn = c.createGain();
  rev = createReverb(c, revIn, masterIn);

  // Delay: AudioWorklet (две линии, фильтр и сатурация в петле, spread / ping-pong); шина отдаёт только эхо.
  const dlyIn = c.createGain();
  dly = createFx(c, 'delay-worklet.js', 'delay', dlyIn, masterIn, { maxTime: MAX_DELAY });

  // Drive: AudioWorklet (LOW CUT → усиление → 4× нелинейность → DC → компенсация → TONE); шина отдаёт только
  // обработанный сигнал. Сигналы дорожек суммируются до нелинейности (как aux-send) — уровень посыла влияет на силу.
  const drvIn = c.createGain();
  const drvOut = c.createGain();
  drvOut.gain.value = DRIVE_OUT;
  drvOut.connect(masterIn);
  drv = createFx(c, 'drive-worklet.js', 'drive', drvIn, drvOut, {}, os);

  busInputs = [revIn, dlyIn, drvIn];

  // Дорожки.
  // Каналы на все 12 дорожек сразу: у несуществующих гейт закрыт.
  tracks = Array.from({ length: MAX_TRACKS }, () => {
    const input = c.createGain();
    const duck = c.createGain();
    const duckDepth = c.createGain();
    duckDepth.gain.value = 0;
    duckDepth.connect(duck.gain);
    const vol = c.createGain();
    const gate = c.createGain();
    const eq = new EqChain(c, dynSource);
    eq.output.connect(input);
    input.connect(duck).connect(vol).connect(gate).connect(masterIn);
    // Посылы: g → sendDuck → шина; sendDuck приглушается огибающей, если включён переключатель SETTINGS → SIDECHAIN.
    const sendDuck = busInputs.map((bus) => { const d = c.createGain(); d.connect(bus); return d; });
    const sendFlag = sendDuck.map((d, k) => {
      const f = c.createGain();
      f.gain.value = scSendOn(k) ? 1 : 0;
      duckDepth.connect(f).connect(d.gain);
      return f;
    });
    const sends = sendDuck.map((d) => {
      const g = c.createGain();
      g.connect(d);
      return g;
    });
    const sendEqs = sends.map((g) => {
      // Копия EQ для посыла: сдвиг динамических полос — от детекторов основного EQ дорожки.
      const e = new EqChain(c, undefined, eq);
      e.output.connect(g);
      return e;
    });
    return { eq, sendEqs, input, duck, duckDepth, sendDuck, sendFlag, vol, gate, sends, meter: new Meter(c, vol, true) };
  });
  // Sidechain: огибающая приглушения — один узел на проект (duck-worklet.js), её выход — в глубину каждой дорожки.
  void c.audioWorklet.addModule(new URL('duck-worklet.js', document.baseURI).href).then(() => {
    if (c !== ctx) return;
    const node = new AudioWorkletNode(c, 'duck', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [1] });
    node.port.onmessage = (e) => {
      if (typeof e.data?.e === 'number') duckE = e.data.e;
      if (typeof e.data?.cpu === 'number') fxCpu.set(node, e.data.cpu);
    };
    for (const ch of tracks) node.connect(ch.duckDepth);
    duckNode = node;
    duckSig = '';
  }).catch((e) => console.error('duck', e));
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
  // Ручка → автоматизация → p-lock шага; LFO/ENV — сверху.
  return fromNorm(p, modulatedNorm(track, p, baseValue(track, id, locks, at), at));
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

/**
 * Удержание ноты: Attack → уровень держится gate секунд от начала ноты → Decay работает как Release.
 * Нет gate (нота в 1 шаг, ratchet) — как раньше: Decay сразу после атаки. Infinity — живая нота,
 * держится до releaseLive. Движки, которые затухают сами (STRING, MODAL, ударные, DRUM), gate не слушают.
 */
const holdEnd = (at: number, attack: number, gate?: number) =>
  gate === undefined ? at + attack : gate === Infinity ? Infinity : at + Math.max(attack, gate);

/** Запустить ноты дорожки в момент time (performance.now); gate — удержание ноты, с. */
export function triggerTrack(track: number, time: number, notes: number[], locks: Record<string, number>, sound?: string, gate?: number, retrig = false) {
  // Контекст может ещё просыпаться после первого касания — ноты всё равно ставим в план.
  if (!ctx || ctx.state === 'closed') return;
  const t = doc.tracks[track];
  // У шага может быть свой звук (сэмпл или движок) вместо звука дорожки.
  const key = sound || t.sample;
  const engine = synthEngine(key);
  if (engine !== null) { triggerSynth(track, engine, time, notes, locks, gate, !!sound, retrig); return; }
  const buf = buffers.get(key);
  if (!buf) return;
  const at = toCtx(time);
  probe(at);
  // Начальные значения — с модуляцией на момент ноты (ENV запущен на это время).
  const v = (id: string) => value(track, id, locks, time);

  const startSec0 = (buf.duration * v('start')) / 100;
  const endSec0 = (buf.duration * v('end')) / 100;
  // Маркеры нарезки (редактор сэмпла): нота маркера играет от него до следующего (последний — до конца) в исходной
  // высоте; нота без маркера молчит. Без маркеров — как прежде (Start/End, нота меняет высоту).
  const marks = sliceMarks(t, key);
  if (!marks.length && endSec0 - startSec0 < 0.003) return;
  const attack = v('attack') / 1000;
  const decay = v('decay') / 1000;
  // Высота сэмпла определяется только для индикации: воспроизведение всегда от C3.
  const root = SAMPLE_ROOT;

  legatoCut(track, notes, at, attack);
  for (const note of notes) {
    let startSec = startSec0;
    let endSec = endSec0;
    let rate = rateFor(note, root, v('pitch'));
    if (marks.length) {
      const k = sliceOf(note, marks);
      if (k < 0) continue;
      startSec = marks[k].at * buf.duration;
      endSec = (k + 1 < marks.length ? marks[k + 1].at : 1) * buf.duration;
      if (endSec - startSec < 0.003) continue;
      rate = rateFor(root, root, v('pitch'));
    }
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = rate;
    const amp = ctx.createGain();
    // Край сэмпла (End или конец файла) — плавно за 4 мс: обрезанная волна не щёлкает.
    const edge = ctx.createGain();
    const level = ctx.createGain();
    const filter = ctx.createBiquadFilter();
    const pan = ctx.createStereoPanner();
    const ch = tracks[track];

    // Огибающая Attack/Decay; длинная нота держит уровень до конца (Decay — после неё).
    const hold = holdEnd(at, Math.max(0.001, attack), gate);
    amp.gain.setValueAtTime(0, at);
    amp.gain.linearRampToValueAtTime(1, at + Math.max(0.001, attack));
    if (hold !== Infinity) {
      if (hold > at + attack) amp.gain.setValueAtTime(1, hold);
      amp.gain.setTargetAtTime(0, hold, Math.max(0.005, decay / 4));
    }
    level.gain.value = levelGain(v('level'));
    applyFilter(filter, v('filter'), v('reso'), at, false);
    pan.pan.value = Math.max(-1, Math.min(1, v('pan') / 64));

    src.connect(edge).connect(amp).connect(level).connect(filter).connect(pan).connect(ch.eq.input);
    const sends = SENDS.map((id, k) => {
      const g = ctx!.createGain();
      g.gain.value = v(id) / 100;
      pan.connect(g).connect(ch.sendEqs[k].input);
      return g;
    });

    const playDur = (endSec - startSec) / rate;
    const fadeLen = Math.min(0.004, playDur / 4);
    edge.gain.setValueAtTime(1, at + playDur - fadeLen);
    edge.gain.linearRampToValueAtTime(0, at + playDur);
    src.start(at, startSec, Math.max(0.003, (endSec - startSec)));
    // Живая нота звучит до отпускания (или до конца сэмпла); остальные — пока Decay не затих
    // (8 постоянных времени, −70 dB: раньше обрыв на −40 dB при длинном Decay щёлкал).
    if (hold !== Infinity) src.stop(Math.min(at + playDur, hold + Math.max(0.02, decay) * 2 + 0.05));
    const voice: Voice = { track, root, locks, note, rateNote: marks.length ? root : undefined, play: { key, a: startSec / buf.duration, b: endSec / buf.duration, dur: buf.duration, rate }, at, src, synth: null, level, filter, pan, sends, ended: false, hold, own: !!sound };
    if (hold === Infinity) voice.held = { amp: amp.gain, decay, id: 0 };
    // Автоматизация: значения голоса наперёд — с самого начала ноты.
    if (autoLive(track)) scheduleVoice(voice, at);
    src.onended = () => {
      voice.ended = true;
      for (const n of [src, edge, amp, level, filter, pan, ...sends]) n.disconnect();
    };
    voices.push(voice);
    if (voices.length > MAX_VOICES) {
      // Лишний голос гаснет за ~5 мс, а не обрывается.
      const old = voices.shift()!;
      if (old.src) {
        old.level.gain.cancelScheduledValues(ctx.currentTime);
        old.level.gain.setTargetAtTime(0, ctx.currentTime, 0.0015);
        try { old.src.stop(ctx.currentTime + 0.02); } catch { /* уже остановлен */ }
      }
    }
  }
  if (!retrig) sidechain(track, at);
}

/** Ноты синта: голоса по кругу, огибающая и параметры — на постоянной цепочке голоса. */
function triggerSynth(track: number, engine: number, time: number, notes: number[], locks: Record<string, number>, gate?: number, own = false, retrig = false) {
  const family = familyOf(engine);
  const sy = ensureSynth(track, family);
  const node = sy?.nodes[family];
  if (!sy || !node) return;
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
  // Удержание длинной (и живой) ноты; у затухающих самих движков его нет — их физику не трогаем.
  const hold = selfDecay ? at + attack : holdEnd(at, attack, gate);
  const live = hold === Infinity;
  // Живая нота: конец голоса — когда отпустят (сообщение 'end'); пока — через минуту.
  const tail = Math.max(0.02, decay) * 2 + 0.05;
  // Голос молчит после затухания огибающей (дальше движок не считается — экономия процессора).
  const end = selfDecay ? at + attack + 15 : live ? at + 60 : hold + tail;
  const sr = ctx!.sampleRate;
  const mono = engine === DRUM_ENGINE;
  if (!mono) legatoCut(track, notes, at, attack);
  const events = (mono ? notes.slice(0, 1) : notes).map((note) => {
    // Свободный голос (затих к моменту ноты), иначе — самый старый по кругу. DRUM (бочка)
    // монофонична: всегда слот 0, новый удар обрывает прошлый (стык сглаживает AudioWorklet).
    let slot = mono ? 0 : -1;
    for (let k = 0; slot < 0 && k < SYNTH_SLOTS; k++) {
      const c = (sy.next + k) % SYNTH_SLOTS;
      if (sy.busyUntil[c] <= at) { slot = c; break; }
    }
    const steal = slot < 0;
    if (steal) slot = sy.next;
    if (!mono) sy.next = (slot + 1) % SYNTH_SLOTS;
    const sl = sy.slots[slot];
    const prevFamily = sy.slotFamily[slot];
    sy.slotFamily[slot] = family;
    // Голос, который ещё звучит в этом слоте, уступает место новой ноте: быстро гаснет (≈5 мс),
    // и новая нота начинается после этого — без щелчка.
    for (const vo of voices) if (vo.synth && vo.track === track && vo.synth.slot === slot) vo.ended = true;
    const start = steal ? at + 0.008 : at;
    const g = sl.amp.gain;
    // Затухающие сами движки (и DRUM) с короткой атакой: огибающая слота не обнуляется — хвост прошлой
    // ноты в слоте (резонатор ещё звучит) не обрывается скачком 1 → 0, новую ноту движок начинает сам.
    const keep = (mono || (selfDecay && !steal)) && attack <= 0.0025;
    if (mono) {
      // Огибающая не обнуляется (хвост прошлого удара гасит сам движок); атака длиннее 2,5 мс — с нуля.
      if (g.cancelAndHoldAtTime) g.cancelAndHoldAtTime(start); else g.cancelScheduledValues(start);
      g.setValueAtTime(attack > 0.0025 ? 0 : 1, start);
      if (attack > 0.0025) g.linearRampToValueAtTime(1, start + attack);
    } else if (keep) {
      g.cancelScheduledValues(at);
      g.setValueAtTime(1, start);
    } else {
      g.cancelScheduledValues(at);
      if (steal) g.setTargetAtTime(0, at, 0.0015);
      g.setValueAtTime(0, start);
      g.linearRampToValueAtTime(1, start + attack);
    }
    if (!selfDecay && !live) {
      const h = hold + (start - at);
      if (h > start + attack) g.setValueAtTime(1, h);
      g.setTargetAtTime(0, h, Math.max(0.005, decay / 4));
    }
    // На звучащем хвосте (keep) параметры слота меняются за ~1 мс, а не скачком.
    // Расписание автоматизации прошлого голоса слота (наперёд) с начала новой ноты не действует.
    for (const p of [sl.level.gain, sl.filter.frequency, sl.filter.Q, sl.pan.pan, ...sl.sends.map((x) => x.gain)]) p.cancelScheduledValues(start);
    const put = (p: AudioParam, x: number) => (keep ? p.setTargetAtTime(x, start, 0.001) : p.setValueAtTime(x, start));
    put(sl.level.gain, levelGain(v('level')));
    applyFilter(sl.filter, v('filter'), v('reso'), start, keep);
    put(sl.pan.pan, Math.max(-1, Math.min(1, v('pan') / 64)));
    SENDS.forEach((id, k) => put(sl.sends[k].gain, v(id) / 100));
    const stop = end + (start - at);
    sy.busyUntil[slot] = selfDecay ? start + attack + 0.3 + 4 * decay : live ? Infinity : stop;
    const id = ++noteId;
    const voice: Voice = {
      track, root: 0, locks, note, at: start, src: null, synth: { slot, engine, end: stop, id }, level: sl.level, filter: sl.filter, pan: sl.pan, sends: sl.sends, ended: false,
      hold: selfDecay ? start + attack : live ? Infinity : hold + (start - at), own,
      held: live ? { amp: g, decay, id } : undefined,
    };
    voices.push(voice);
    // Автоматизация: значения голоса наперёд — с самого начала ноты (mod — после самой ноты).
    if (autoLive(track)) queueMicrotask(() => { if (!voice.ended) scheduleVoice(voice, start); });
    // Слот занимал голос другого семейства — тот замолкает в кадре новой ноты (огибающая уже погашена).
    if (prevFamily && prevFamily !== family) sy.nodes[prevFamily]?.port.postMessage([{ type: 'stop', slot, frame: Math.round(start * sr) }]);
    return { type: 'note', id, slot, frame: Math.round(start * sr), end: Math.round(stop * sr), engine, note, ...synthParams(engine, v), accent: 0.8 };
  });
  node.port.postMessage(events);
  if (!retrig) sidechain(track, at);
}

/**
 * Полоса воспроизведения: где сейчас звучащие голоса сэмпла key дорожки (доли длины). Позиция — от начала ноты
 * по её скорости (модуляция Pitch не учитывается); голос, отпущенный и затихающий, ещё показывается, пока играет.
 */
export function samplePlayheads(track: number, key: string): number[] {
  if (!ctx || !key) return [];
  const now = ctx.currentTime - (ctx.outputLatency || 0);
  const out: number[] = [];
  for (const vo of voices) {
    const pl = vo.play;
    if (!pl || vo.ended || vo.track !== track || pl.key !== key || now < vo.at) continue;
    const f = pl.a + ((now - vo.at) * pl.rate) / pl.dur;
    if (f < pl.b) out.push(f);
  }
  return out;
}

/** Живой наигрыш с пианоролла: ноты выбранной дорожки сейчас. */
export function playNow(track: number, notes: number[], held = false, velocity = 1) {
  // Живая нота тоже запускает ENV: гейт — пока держат клавишу (held, отпускание — releaseEnv),
  // иначе (ноты с MIDI) — один шаг. VELOCITY: Level ноты = Level дорожки × сила нажатия.
  const now = performance.now();
  triggerEnv(track, now, held ? 1e9 : 60000 / tempo() / 4);
  triggerTrack(track, now, notes, velocity < 1 ? { level: doc.tracks[track].params.level * velocity } : {}, undefined, held ? Infinity : undefined);
}

/** Отпустили клавишу: живые ноты notes дорожки — Decay как Release с этого момента. */
export function releaseLive(track: number, notes: number[]) {
  if (!ctx) return;
  const ct = ctx.currentTime;
  const sr = ctx.sampleRate;
  const msgs = new Map<AudioWorkletNode, unknown[]>();
  for (const vo of voices) {
    const hd = vo.held;
    if (!hd || vo.track !== track || !notes.includes(vo.note)) continue;
    vo.held = undefined;
    vo.hold = Math.max(ct, vo.at);
    if (vo.ended) continue;
    const t = Math.max(ct, vo.at);
    const g = hd.amp;
    if (g.cancelAndHoldAtTime) g.cancelAndHoldAtTime(t); else { g.cancelScheduledValues(t); g.setValueAtTime(g.value, t); }
    g.setTargetAtTime(0, t, Math.max(0.005, hd.decay / 4));
    const stop = t + Math.max(0.02, hd.decay) * 2 + 0.05;
    if (vo.src) { try { vo.src.stop(stop); } catch { /* уже остановлен */ } continue; }
    if (!vo.synth) continue;
    vo.synth.end = stop;
    const sy = synths[track];
    if (!sy) continue;
    sy.busyUntil[vo.synth.slot] = stop;
    const node = sy.nodes[familyOf(vo.synth.engine)];
    if (!node) continue;
    if (!msgs.has(node)) msgs.set(node, []);
    msgs.get(node)!.push({ type: 'end', id: hd.id, slot: vo.synth.slot, end: Math.round(stop * sr) });
  }
  msgs.forEach((m, node) => node.port.postMessage(m));
}

/** Sidechain: огибающая (duck-worklet.js), её последнее значение (индикация) и глубины дорожек. */
let duckNode: AudioWorkletNode | null = null;
let duckE = 0;
let duckSig = '';
const duckAmount: number[] = [];

/**
 * Sidechain: триг дорожки-источника — сообщение в огибающую (в точном кадре; ATTACK, RELEASE, CURVE — на момент
 * трига). Только от источника и если хоть одна другая дорожка приглушается.
 */
function sidechain(source: number, at: number) {
  if (!duckNode || !ctx) return;
  const fx = liveFx();
  if (source !== fx['sc.source']) return;
  if (!doc.tracks.some((t, i) => i !== source && t.params.sidechain > 0)) return;
  duckNode.port.postMessage({
    type: 'trig', frame: Math.round(at * ctx.sampleRate),
    attack: fx['sc.attack'], release: fx['sc.release'], curve: fx['sc.curve'] ?? 50,
  });
}

/** Переключатель SETTINGS → SIDECHAIN для посыла k (0 Reverb, 1 Delay, 2 Drive). */
const scSendOn = (k: number) => [settings.scSends.rev, settings.scSends.dly, settings.scSends.drv][k] ?? false;
/** Переключатели посылов сменились — плавно (~10 мс). */
export function applySidechainSends() {
  if (!ctx) return;
  const ct = ctx.currentTime;
  for (const ch of tracks) ch.sendFlag.forEach((f, k) => f.gain.setTargetAtTime(scSendOn(k) ? 1 : 0, ct, 0.01 / 3));
}

/** Остановка: будущие триги sidechain отменяются (возврат досчитывается). */
export function flushSidechain() {
  duckNode?.port.postMessage({ type: 'flush' });
}

/** Глубины sidechain дорожек (−amount; у источника и несуществующих — 0): плавно, за ~10 мс, при изменении. */
function updateDuckDepths(ct: number, source: number) {
  const amounts = tracks.map((_, i) => (i === source || i >= doc.tracks.length ? 0 : Math.max(0, Math.min(1, doc.tracks[i].params.sidechain / 100))));
  const sig = amounts.join(',');
  if (sig === duckSig) return;
  duckSig = sig;
  amounts.forEach((a, i) => {
    duckAmount[i] = a;
    tracks[i].duckDepth.gain.setTargetAtTime(-a, ct, 0.01 / 3);
  });
}

/**
 * Дорожки i…last сменили номер (удаление — i и все правее, перестановка — участок): их голоса
 * звучат на цепочках прежних номеров — быстро гаснут (~5 мс) и больше не модулируются; новые ноты
 * пойдут по новым номерам.
 */
export function trackDeleted(i: number, last = MAX_TRACKS - 1) {
  if (!ctx) return;
  const ct = ctx.currentTime;
  for (const vo of voices) {
    if (vo.track < i || vo.track > last || vo.ended) continue;
    vo.ended = true;
    if (vo.src) {
      vo.level.gain.cancelScheduledValues(ct);
      vo.level.gain.setTargetAtTime(0, ct, 0.0015);
      try { vo.src.stop(ct + 0.03); } catch { /* уже остановлен */ }
    }
  }
  for (let ch = i; ch <= last; ch++) {
    const sy = synths[ch];
    if (!sy) continue;
    sy.slots.forEach((sl) => { sl.amp.gain.cancelScheduledValues(ct); sl.amp.gain.setTargetAtTime(0, ct, 0.0015); });
    sy.busyUntil.fill(0);
  }
}

/**
 * Быстро погасить голос с момента t (постоянная tau, с): сэмпл — уровнем и остановкой, синт — огибающей
 * слота и сообщением 'end' (только эта нота). Голос больше не модулируется.
 */
function fadeVoice(vo: Voice, t: number, tau: number) {
  vo.ended = true;
  vo.held = undefined;
  vo.hold = Math.min(vo.hold, t);
  const stop = t + tau * 8 + 0.005;
  if (vo.src) {
    vo.level.gain.cancelScheduledValues(t);
    vo.level.gain.setTargetAtTime(0, t, tau);
    try { vo.src.stop(stop); } catch { /* уже остановлен */ }
    return;
  }
  const sy = synths[vo.track];
  if (!vo.synth || !sy) return;
  const g = sy.slots[vo.synth.slot].amp.gain;
  if (g.cancelAndHoldAtTime) g.cancelAndHoldAtTime(t); else g.cancelScheduledValues(t);
  g.setTargetAtTime(0, t, tau);
  sy.busyUntil[vo.synth.slot] = Math.min(sy.busyUntil[vo.synth.slot], stop);
  sy.nodes[familyOf(vo.synth.engine)]?.port.postMessage([{ type: 'end', id: vo.synth.id, slot: vo.synth.slot, end: Math.round(stop * ctx!.sampleRate) }]);
}

/**
 * Нота той же высоты продолжает державшуюся (длинная нота до следующей, звук сменили): прежняя гаснет
 * вместе с атакой новой — без провала и без удвоения уровня на стыке. Отпущенные раньше хвосты не трогаем.
 */
function legatoCut(track: number, notes: number[], at: number, attack: number) {
  for (const vo of voices) {
    if (vo.track !== track || vo.ended || vo.hold === Infinity || !notes.includes(vo.note)) continue;
    if (vo.at < at && vo.hold >= at - 0.005) fadeVoice(vo, at, Math.max(0.0015, attack / 3));
  }
}

/** Звук дорожки на прошлом кадре: сменили (движок, сэмпл, пресет, UNDO) — держащиеся ноты переходят на новый. */
const lastSound: string[] = [];

/**
 * Смена звука дорожки: ноты, которые ещё держатся (живые и длинные ноты секвенсора), сразу звучат новым
 * звуком — прежний голос гаснет за ~5 мс, новый начинается с той же нотой на оставшееся удержание
 * (иначе новый движок слышен только со следующей ноты — у ноты на такт через 2 с). Свой звук шага не трогаем.
 */
function retrigger(track: number) {
  const c = ctx!;
  const now = c.currentTime;
  const redo = new Map<string, { at: number; gate: number; locks: Record<string, number>; notes: number[] }>();
  for (const vo of voices) {
    if (vo.track !== track || vo.ended || vo.own) continue;
    const t = Math.max(now, vo.at);
    if (vo.hold <= t + 0.01) continue;
    const gate = vo.hold === Infinity ? Infinity : vo.hold - t;
    // Кроссфейд: прежний голос гаснет, когда вступает новый (у синта — через 12 мс, запас до AudioWorklet).
    fadeVoice(vo, t + 0.012, 0.003);
    const key = `${t}|${gate}|${JSON.stringify(vo.locks)}`;
    const r = redo.get(key);
    if (r) r.notes.push(vo.note); else redo.set(key, { at: t, gate, locks: vo.locks, notes: [vo.note] });
  }
  // Новые ноты — сразу, без sidechain (это не новый триг).
  redo.forEach((r) => triggerTrack(track, performance.now() + (r.at - now) * 1000, r.notes, r.locks, undefined, r.gate, true));
}

/** Шаг расписания автоматизации, с, и сколько шагов наперёд (с запасом на опоздавший кадр). */
const SCHED_DT = 0.005;
const SCHED_N = 12;
/**
 * Расписание начинается не раньше чем через 8 мс: до этого времени звук, возможно, уже посчитан, и правка
 * «задним числом» дала бы скачок. Точки — на общей сетке времени (кратны SCHED_DT): новое расписание
 * подхватывает точку прошлого ровно в её момент — без скачка.
 */
const SCHED_LEAD = 0.008;
const schedVals: number[][] = Array.from({ length: SCHED_N + 1 }, () => []);

/** Живые параметры голоса: Pitch, Level, Filter, Resonance, Pan и посылы. */
function liveVals(vo: Voice, at: number, out: number[]) {
  const v = (id: string) => value(vo.track, id, vo.locks, at);
  out.length = 0;
  out.push(v('pitch'), v('level'), v('filter'), v('reso'), v('pan'), ...SENDS.map((id) => v(id)));
}

/**
 * Значение AudioParam — линейными отрезками по точкам расписания от anchor. Продолжение (cont) — точка
 * прошлого расписания в момент anchor остаётся (с неё идут отрезки), иначе значение ставится в anchor.
 */
function rampParam(p: AudioParam, anchor: number, cont: boolean, val: (k: number) => number) {
  p.cancelScheduledValues(anchor + 1e-4);
  if (!cont) p.setValueAtTime(val(0), anchor);
  for (let k = 1; k <= SCHED_N; k++) p.linearRampToValueAtTime(val(k), anchor + k * SCHED_DT);
}

/**
 * Голос дорожки с автоматизацией: значения (с p-lock и LFO/ENV) считаются наперёд на ~60 мс с шагом 5 мс
 * (200 раз в секунду) по часам секвенсора и уходят в AudioParam отрезками, а в AudioWorklet синта —
 * сообщениями mod с кадром; каждый кадр расписание обновляется (кадр опоздал — звук не замирает).
 */
function scheduleVoice(vo: Voice, start?: number) {
  const c = ctx!;
  const ct = c.currentTime;
  // Начало ноты: расписание — сразу от её начала (значения ноты совпадают с кривой, первый кадр продолжает).
  const anchor = start ?? Math.ceil((ct + SCHED_LEAD) / SCHED_DT) * SCHED_DT;
  // Прошлое расписание дотягивается до anchor — продолжаем с его точки; иначе (долгий кадр) — с нуля.
  const cont = start === undefined && !!vo.sched && (vo.schedEnd ?? 0) >= anchor - 1e-6;
  const perf = performance.now() + (anchor - ct) * 1000;
  for (let k = 0; k <= SCHED_N; k++) liveVals(vo, perf + k * SCHED_DT * 1000, schedVals[k]);
  if (vo.src) rampParam(vo.src.playbackRate, anchor, cont, (k) => rateFor(vo.rateNote ?? vo.note, vo.root, schedVals[k][0]));
  rampParam(vo.level.gain, anchor, cont, (k) => levelGain(schedVals[k][1]));
  // Фильтр: тип (LP/HP/выкл.) — по текущему значению, частота и резонанс — отрезками.
  const ff = filterFreq(schedVals[0][2]);
  const type: BiquadFilterType = ff.type === 'hp' ? 'highpass' : 'lowpass';
  if (vo.filter.type !== type) vo.filter.type = type;
  // Точка с другим типом (кривая прошла центр ручки) — край текущего типа: LP открыт (20 кГц), HP — 20 Гц.
  rampParam(vo.filter.frequency, anchor, cont, (k) => {
    const f = filterFreq(schedVals[k][2]);
    if (f.type === ff.type) return ff.type === 'off' ? 20000 : f.hz;
    return ff.type === 'hp' ? 20 : 20000;
  });
  rampParam(vo.filter.Q, anchor, cont, (k) => 0.7 + (schedVals[k][3] / 100) * 18);
  rampParam(vo.pan.pan, anchor, cont, (k) => Math.max(-1, Math.min(1, schedVals[k][4] / 64)));
  SENDS.forEach((_, i) => rampParam(vo.sends[i].gain, anchor, cont, (k) => schedVals[k][5 + i] / 100));
  if (vo.synth) {
    // Ручки 1.1–1.3 (и Decay) — сообщениями mod с кадром: AudioWorklet применяет их в своё время.
    const sr = c.sampleRate;
    const msgs: unknown[] = [];
    for (let k = 0; k <= SCHED_N; k++) {
      const at = perf + k * SCHED_DT * 1000;
      const p = synthParams(vo.synth.engine, (id) => value(vo.track, id, vo.locks, at));
      msgs.push({ type: 'mod', slot: vo.synth.slot, note: vo.note, id: vo.synth.id, frame: Math.round((anchor + k * SCHED_DT) * sr), ...p });
    }
    synths[vo.track]?.nodes[familyOf(vo.synth.engine)]?.port.postMessage(msgs);
  }
  vo.sched = true;
  vo.schedEnd = anchor + SCHED_N * SCHED_DT;
  vo.vals = schedVals[0].slice();
  vo.sig = undefined;
}

/** Автоматизация кончилась (стоп, паттерн без неё): расписание наперёд снимается, значения — сейчас. */
function unschedule(vo: Voice) {
  const c = ctx!;
  const anchor = Math.ceil((c.currentTime + SCHED_LEAD) / SCHED_DT) * SCHED_DT;
  vo.sched = false;
  const vals: number[] = [];
  liveVals(vo, performance.now() + (anchor - c.currentTime) * 1000, vals);
  const set = (p: AudioParam, x: number) => {
    p.cancelScheduledValues(anchor + 1e-4);
    p.setTargetAtTime(x, anchor, 0.005);
  };
  if (vo.src) set(vo.src.playbackRate, rateFor(vo.rateNote ?? vo.note, vo.root, vals[0]));
  set(vo.level.gain, levelGain(vals[1]));
  for (const p of [vo.filter.frequency, vo.filter.Q]) p.cancelScheduledValues(anchor + 1e-4);
  applyFilter(vo.filter, vals[2], vals[3], anchor, true);
  set(vo.pan.pan, Math.max(-1, Math.min(1, vals[4] / 64)));
  SENDS.forEach((_, i) => set(vo.sends[i].gain, vals[5 + i] / 100));
  vo.vals = vals;
  if (vo.synth) {
    // Сообщение без кадра снимает в AudioWorklet запланированные mod слота.
    const p = synthParams(vo.synth.engine, (id) => value(vo.track, id, vo.locks));
    synths[vo.track]?.nodes[familyOf(vo.synth.engine)]?.port.postMessage([{ type: 'mod', slot: vo.synth.slot, note: vo.note, id: vo.synth.id, ...p }]);
    vo.sig = Object.values(p).join(',');
  }
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
    // Дорожки больше нет (удалили, UNDO сменил число дорожек) — голос не трогаем.
    const tr = doc.tracks[vo.track];
    if (!tr) continue;
    // Модуляция (LFO/ENV) и повороты ручек меняют звучащие ноты сразу (p-lock шага держит своё значение):
    // значение уходит в голос, когда изменилось с прошлого кадра.
    // Автоматизация: значения наперёд по расписанию (чаще кадров — каждые 5 мс).
    if (autoLive(vo.track)) { scheduleVoice(vo); continue; }
    if (vo.sched) unschedule(vo);
    const v = (id: string) => value(vo.track, id, vo.locks);
    const now = c.currentTime;
    if (vo.synth) {
      const p = synthParams(vo.synth.engine, v);
      const sig = Object.values(p).join(',');
      if (vo.sig !== undefined && sig !== vo.sig) {
        synths[vo.track]?.nodes[familyOf(vo.synth.engine)]?.port.postMessage([{ type: 'mod', slot: vo.synth.slot, note: vo.note, ...p }]);
      }
      vo.sig = sig;
    }
    const vals = [v('pitch'), v('level'), v('filter'), v('reso'), v('pan'), ...SENDS.map((id) => v(id))];
    const was = vo.vals;
    vo.vals = vals;
    if (!was) continue;
    const ch = (k: number) => vals[k] !== was[k];
    if (ch(0) && vo.src) vo.src.playbackRate.setTargetAtTime(rateFor(vo.rateNote ?? vo.note, vo.root, vals[0]), now, 0.01);
    if (ch(1)) vo.level.gain.setTargetAtTime(levelGain(vals[1]), now, 0.01);
    if (ch(2) || ch(3)) applyFilter(vo.filter, vals[2], vals[3], now, true);
    if (ch(4)) vo.pan.pan.setTargetAtTime(Math.max(-1, Math.min(1, vals[4] / 64)), now, 0.01);
    SENDS.forEach((_, i) => { if (ch(5 + i)) vo.sends[i].gain.setTargetAtTime(vals[5 + i] / 100, now, 0.01); });
  }
}

// ---------- Эффекты, микшер, мастер ----------

let fxSig = '';
function updateFx(now: number) {
  const c = ctx!;
  // Значения с p-lock играющих шагов (FX — любой дорожки, микшер — MIX, мастер — MST).
  const fx = liveFx(now);
  const mixer = liveMixer(now);
  const master = liveMaster(now);
  const ct = c.currentTime;
  const set = (p: AudioParam, v: number) => p.setTargetAtTime(v, ct, 0.02);

  // Глубины sidechain — от ручек дорожек (не входят в подпись FX): проверяются каждый кадр.
  updateDuckDepths(ct, Math.round(fx['sc.source']));

  const fsig = JSON.stringify([fx, mixer, master, doc.limBypass, doc.cmpBypass, doc.clipBypass, doc.satBypass, tempo(), ui.limView, ui.limUnity, ui.limAudit, ui.compView, ui.compAudit, ui.clipView, ui.clipUnity, ui.clipAudit, ui.satView, settings.clipDisplay, ui.channel === 'master', doc.tracks.map((t) => +t.mute + 2 * +t.solo)]);
  if (fsig === fxSig) return;
  fxSig = fsig;
  rev.set(fx, ct);

  // Время Delay привязано к темпу: доля такта × длительность четверти.
  const dn = dly.node;
  if (dn) {
    const dp = (name: string) => dn.parameters.get(name)!;
    // Скольжение времени и сглаживание — в worklet; сюда — цели.
    dp('time').setValueAtTime(Math.min(MAX_DELAY, DELAY_DIVS[Math.round(fx['dly.time'])].beats * 60 / tempo()), ct);
    // Пока идёт MUTE TAILS, обратная связь возвращается не раньше его конца.
    dp('feedback').setValueAtTime(fx['dly.feedback'] / 100, Math.max(ct, tailUntil));
    dp('filter').setValueAtTime(fx['dly.filter'] / 100, ct);
    dp('spread').setValueAtTime(fx['dly.spread'] / 100, ct);
  }

  // Тип overdrive сменился — кроссфейд на вторую копию шейпера (кривую молчащего узла менять безопасно).
  const vn = drv.node;
  if (vn) {
    // Сглаживание и кроссфейд TYPE — в worklet; сюда — цели.
    const vp = (name: string) => vn.parameters.get(name)!;
    vp('drive').setValueAtTime(fx['od.drive'] ?? 26, ct);
    vp('type').setValueAtTime(Math.round(fx['od.type']), ct);
    vp('tone').setValueAtTime(fx['od.tone'], ct);
    vp('lowcut').setValueAtTime(fx['od.lowcut'] ?? 20, ct);
  }

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
  const fb = doc.fx['dly.feedback'] / 100;
  const fbp = dly.node?.parameters.get('feedback');
  for (const g of fbp ? [fbp] : []) {
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
  doc.tracks.forEach((t, i) => {
    const e = synthEngine(t.sample);
    if (e !== null) ensureSynth(i, familyOf(e));
    sendTable(i, t.table ?? '');
    if (lastSound[i] !== undefined && lastSound[i] !== t.sample) retrigger(i);
    lastSound[i] = t.sample;
  });
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
/** Спектр конечного сигнала мастера (после громкости выхода) — для EQ мастера, пока включён. */
let outScope: AnalyserNode | null = null;
export function setOutScope(on: boolean) {
  if (!ctx || !mst) return;
  if (on && !outScope) {
    outScope = ctx.createAnalyser();
    outScope.fftSize = 4096;
    outScope.smoothingTimeConstant = 0.6;
    outScope.minDecibels = -100;
    outScope.maxDecibels = 0;
    mst.outVol.connect(outScope);
  } else if (!on && outScope) {
    mst.outVol.disconnect(outScope);
    outScope = null;
  }
}
/** Спектр входа и выхода сатуратора (окно сатуратора): анализаторы — только пока окно открыто. */
let satScope: { pre: AnalyserNode; post: AnalyserNode } | null = null;
export function setSatScope(on: boolean) {
  if (!ctx || !mst) return;
  if (on && !satScope) {
    const mk = () => { const a = ctx!.createAnalyser(); a.fftSize = 4096; a.smoothingTimeConstant = 0.8; a.minDecibels = -120; a.maxDecibels = 0; return a; };
    satScope = { pre: mk(), post: mk() };
    // Вход — satIn, выход — glueIn (сатуратор стоит между ними).
    mst.satIn.connect(satScope.pre);
    mst.glueIn.connect(satScope.post);
  } else if (!on && satScope) {
    mst.satIn.disconnect(satScope.pre);
    mst.glueIn.disconnect(satScope.post);
    satScope = null;
  }
}
export function satSpectrum(pre: Float32Array<ArrayBuffer>, post: Float32Array<ArrayBuffer>): boolean {
  if (!satScope) return false;
  satScope.pre.getFloatFrequencyData(pre);
  satScope.post.getFloatFrequencyData(post);
  return true;
}

export function outSpectrum(out: Float32Array<ArrayBuffer>): boolean {
  if (!outScope) return false;
  outScope.getFloatFrequencyData(out);
  return true;
}

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
// ---------- Предпрослушка в браузере библиотеки ----------

/** Вход мастера (сюда идёт предпрослушка сэмпла). */
let masterInput: GainNode | null = null;
let preview: { src: AudioBufferSourceNode; gain: GainNode } | null = null;
/** Громкость предпрослушки сэмпла (−3 dB). */
const PREVIEW_GAIN = 0.7;

/** Остановить предпрослушку сэмпла (быстрое затухание, без щелчка). */
export function stopPreview() {
  if (!preview || !ctx) return;
  const { src, gain } = preview;
  preview = null;
  gain.gain.setTargetAtTime(0, ctx.currentTime, 0.005);
  try { src.stop(ctx.currentTime + 0.05); } catch { /* уже остановлен */ }
}

/**
 * Предпрослушка сэмпла: целиком, в исходной высоте, сразу в мастер (не зависит от ручек дорожки,
 * mute и solo). Новая предпрослушка обрывает прошлую.
 */
/** Идёт ли предпрослушка сэмпла (кнопка ▶ в редакторе сэмпла). */
export const previewing = () => preview !== null;

export async function previewSample(key: string, from = 0, to = 1) {
  const c = ensureCtx();
  unlockAudio();
  await ensureSamples([key]);
  const buf = buffers.get(key);
  if (!buf || !masterInput || ctx !== c) return;
  stopPreview();
  const src = c.createBufferSource();
  src.buffer = buf;
  const gain = c.createGain();
  gain.gain.value = PREVIEW_GAIN;
  src.connect(gain).connect(masterInput);
  src.onended = () => { src.disconnect(); gain.disconnect(); if (preview?.src === src) preview = null; };
  // Отрезок from..to (доли длины; редактор сэмпла — выделение маркерами).
  const a = Math.max(0, Math.min(1, from)) * buf.duration;
  const b = Math.max(0, Math.min(1, to)) * buf.duration;
  src.start(c.currentTime, a, Math.max(0.003, b - a));
  preview = { src, gain };
}

/**
 * Предпрослушка пресета синта: одна нота через выбранную дорожку с движком и параметрами пресета
 * (как звук шага; на дорожку пресет не ставится). Нота — выбранная в пианоролле, иначе C3.
 */
export function previewPreset(sound: string, params: Record<string, number>) {
  ensureCtx();
  unlockAudio();
  stopPreview();
  triggerTrack(ui.selectedTrack, performance.now(), [ui.selNotes[0] ?? SAMPLE_ROOT], { ...params }, sound);
}

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

/** Снижение громкости дорожки от sidechain, дБ (≤ 0): 1 − amount·e по последнему значению огибающей. */
export function trackDuckDb(i: number): number {
  const g = 1 - (duckAmount[i] ?? 0) * duckE;
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

// ---------- Запись стемов ----------

/** Идущие записи стемов: дорожка → узел-записчик и накопленные куски (L, R). */
const stems = new Map<number, { node: AudioWorkletNode | null; L: Float32Array[]; R: Float32Array[]; done: Promise<void>; stopAt: number | null }>();
let stemReady: Promise<void> | null = null;

export const isStemRecording = (track: number) => stems.has(track);
/** Номер «дорожки» записи мастера (кнопка ● MASTER в MIX). */
export const MASTER_STEM = -1;

/** Загрузить узел записи заранее (при нажатии ●), чтобы запись с PLAY не теряла начало. */
export function prepareStems() {
  const c = ensureCtx();
  stemReady ??= c.audioWorklet.addModule(new URL('stem-worklet.js', document.baseURI).href);
}

/**
 * Запись стема дорожки с момента at (performance.now): выход дорожки после EQ, громкости микшера и
 * mute/solo (то, что дорожка отдаёт в мастер, без посылов Reverb, Delay и Drive), стерео; у мастера
 * (MASTER_STEM) — выход мастера после громкости выхода (с эффектами).
 */
export async function startStem(track: number, at: number) {
  const c = ensureCtx();
  // Мастер (MASTER_STEM): конечный сигнал — после громкости выхода, то, что идёт на выход.
  const src = track === MASTER_STEM ? mst?.outVol : tracks[track]?.gate;
  if (!src || stems.has(track)) return;
  const startFrame = Math.round(toCtx(at) * c.sampleRate);
  stemReady ??= c.audioWorklet.addModule(new URL('stem-worklet.js', document.baseURI).href);
  const rec = { node: null as AudioWorkletNode | null, L: [] as Float32Array[], R: [] as Float32Array[], done: Promise.resolve(), stopAt: null as number | null };
  stems.set(track, rec);
  await stemReady;
  if (stems.get(track) !== rec && rec.stopAt === null) return;
  const node = new AudioWorkletNode(c, 'stem-rec', { numberOfInputs: 1, numberOfOutputs: 1, channelCount: 2, channelCountMode: 'explicit' });
  // Узел должен быть в графе до выхода, иначе браузер его не считает: выход — через нулевое усиление.
  const sink = c.createGain();
  sink.gain.value = 0;
  node.connect(sink).connect(c.destination);
  src.connect(node);
  rec.node = node;
  rec.done = new Promise((resolve) => {
    node.port.onmessage = (e) => {
      if (Array.isArray(e.data)) { rec.L.push(e.data[0]); rec.R.push(e.data[1]); return; }
      if (e.data?.done) {
        try { src.disconnect(node); } catch { /* уже отключён */ }
        node.disconnect();
        sink.disconnect();
        resolve();
      }
    };
  });
  node.port.postMessage({ start: startFrame });
  // Остановку могли запросить, пока узел создавался.
  if (rec.stopAt !== null) node.port.postMessage({ stop: rec.stopAt });
}

/**
 * Закончить запись стема в момент at (performance.now; по умолчанию — сейчас): WAV 24 бит в хранилище
 * сэмплов; результат — ключ сэмпла (null — пусто).
 */
export async function stopStem(track: number, name: string, at = performance.now()): Promise<string | null> {
  const rec = stems.get(track);
  if (!rec) return null;
  stems.delete(track);
  const c = ensureCtx();
  rec.stopAt = Math.round(toCtx(at) * c.sampleRate);
  // Узел ещё создаётся — дождаться его (он сам получит stop).
  while (!rec.node) {
    await new Promise((r) => setTimeout(r, 20));
    if (!stemReady) return null;
  }
  rec.node.port.postMessage({ stop: rec.stopAt });
  await rec.done;
  const n = rec.L.reduce((a, x) => a + x.length, 0);
  if (n === 0) return null;
  const buf = c.createBuffer(2, n, c.sampleRate);
  for (const [k, parts] of [rec.L, rec.R].entries()) {
    const d = buf.getChannelData(k);
    let o = 0;
    for (const p of parts) { d.set(p, o); o += p.length; }
  }
  const bytes = encodeWav(buf);
  const key = await sampleKey(bytes);
  buffers.set(key, buf);
  await putSample({ key, name: `${name}.wav`, bytes });
  return key;
}
