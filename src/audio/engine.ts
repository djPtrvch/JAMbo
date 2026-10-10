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
// Измерители уровня стоят на выходе каждой дорожки и в мастере (вход компрессора, вход и выход
// лимитера): пиковый уровень по каналам и громкость в LUFS (K-взвешивание, окно ~400 мс).

import { OVER_PEAK, PARAM_BY_ID, RATIOS, VOL_DEF_DB, volGain, SAMPLE_ROOT, TRACK_COUNT, filterFreq, fromNorm } from '../params';
import { doc, modulatedNorm, setTrackSample, ui } from '../state';
import { detectRoot } from './pitch';

let ctx: AudioContext | null = null;
const buffers = new Map<string, AudioBuffer>();
const peaks = new Map<string, Float32Array[]>();
let fileCount = 0;

interface TrackChain { input: GainNode; duck: GainNode; vol: GainNode; sends: GainNode[]; meter: Meter }
interface Voice {
  track: number;
  root: number;
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
let mst: {
  comp: DynamicsCompressorNode; makeup: GainNode; limIn: GainNode; lim: DynamicsCompressorNode;
  compMeter: Meter; compOutMeter: Meter; limMeter: Meter; outMeter: Meter;
};

const SENDS = ['reverb', 'delay', 'drive'] as const;

// ---------- Запуск ----------

/** Создать контекст (на паузе, пока его не включит касание). */
function ensureCtx(): AudioContext {
  if (ctx) return ctx;
  ctx = new AudioContext({ latencyHint: 'interactive' });
  buildGraph(ctx);
  return ctx;
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
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) htmlAudio?.pause();
    });
  }
  if (htmlAudio.paused && !document.hidden) void htmlAudio.play().catch(() => { /* повторим на следующем касании */ });
}

/** Состояние звука для подсказки на экране: running, suspended, interrupted или none. */
export const audioState = (): string => (ctx ? ctx.state : 'none');

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
  mst = {
    comp, makeup, limIn, lim,
    compMeter: new Meter(c, masterIn, false), compOutMeter: new Meter(c, makeup, false), limMeter: new Meter(c, limIn, false), outMeter: new Meter(c, lim, true),
  };

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
    return { input, duck, vol, sends, meter: new Meter(c, vol, true) };
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
/** Скорость воспроизведения: нота относительно определённой высоты сэмпла (root) + Pitch. */
const rateFor = (note: number, root: number, pitch: number) => Math.pow(2, (note - root + pitch) / 12);

/** Запустить ноты дорожки в момент time (performance.now). */
export function triggerTrack(track: number, time: number, notes: number[], locks: Record<string, number>) {
  // Контекст может ещё просыпаться после первого касания — ноты всё равно ставим в план.
  if (!ctx || ctx.state === 'closed') return;
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
    const voice: Voice = { track, root, locks, note, src, level, filter, pan, sends, ended: false };
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
    if (assigns.pitch) vo.src.playbackRate.setTargetAtTime(rateFor(vo.note, vo.root, v('pitch')), now, 0.01);
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

  const fsig = JSON.stringify([fx, doc.mixer, doc.master, doc.ratio, doc.limBypass]);
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
    const vol = volGain(doc.mixer[`mix.vol${i + 1}`] ?? VOL_DEF_DB);
    set(ch.vol.gain, vol);
    ch.sends.forEach((s) => set(s.gain, vol));
  });

  const m = doc.master;
  set(mst.comp.threshold, m['cmp.threshold']);
  set(mst.comp.attack, m['cmp.attack'] / 1000);
  set(mst.comp.release, m['cmp.release'] / 1000);
  set(mst.comp.ratio, RATIOS[doc.ratio]);
  set(mst.makeup.gain, Math.pow(10, m['cmp.makeup'] / 20));
  // BYPASS лимитера: без Input, порог 0 dB и Ratio 1:1 — сигнал проходит как есть,
  // и метры мастера показывают текущий выходной уровень без ограничения.
  const lb = doc.limBypass;
  set(mst.limIn.gain, lb ? 1 : Math.pow(10, m['lim.input'] / 20));
  set(mst.lim.ratio, lb ? 1 : 20);
  set(mst.lim.threshold, lb ? 0 : m['lim.ceiling']);
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

// Файлы, выбранные в окне выбора (можно сразу несколько — это «папка»), привязаны к дорожке,
// на которую их загрузили: стрелки под окном сэмпла перелистывают их по кругу.
const fileLists = new Map<number, { files: File[]; index: number }>();
const fileKeys = new Map<File, string>();

/** Загрузить файл (один раз) и поставить его на дорожку; высота определяется для индикации. */
async function loadFile(track: number, file: File): Promise<void> {
  const c = ensureCtx();
  let key = fileKeys.get(file);
  if (!key) {
    const buf = await c.decodeAudioData(await file.arrayBuffer());
    key = `file:${++fileCount}`;
    buffers.set(key, buf);
    fileKeys.set(file, key);
    setTrackSample(track, key, file.name, detectRoot(buf));
  } else {
    setTrackSample(track, key, file.name);
  }
}

/** Выбор файлов: они становятся списком выбранной дорожки, первый ставится на неё. */
export async function loadSampleFiles(files: File[]): Promise<void> {
  if (files.length === 0) return;
  const track = ui.selectedTrack;
  fileLists.set(track, { files, index: 0 });
  await loadFile(track, files[0]);
}

/** Стрелки под окном сэмпла: соседний файл из списка выбранной дорожки. */
export async function stepSample(dir: 1 | -1): Promise<void> {
  const track = ui.selectedTrack;
  const list = fileLists.get(track);
  if (!list || list.files.length === 0) return;
  list.index = (list.index + dir + list.files.length) % list.files.length;
  await loadFile(track, list.files[list.index]);
}

/** Позиция в списке файлов выбранной дорожки: [номер, всего]. */
export function sampleListPos(): [number, number] {
  const list = fileLists.get(ui.selectedTrack);
  return list ? [list.index + 1, list.files.length] : [0, 0];
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

/** Сэмпл стерео (для индикации в окне сэмпла). */
export const sampleIsStereo = (key: string) => (buffers.get(key)?.numberOfChannels ?? 1) > 1;


// ---------- Измерители уровня ----------

export interface Level {
  /** Пиковый уровень по каналам (0..1+, с плавным спадом). */
  l: number;
  r: number;
  /** Громкость LUFS (momentary, ~400 мс), -Infinity — тишина. */
  lufs: number;
  /** Была перегрузка (≥ 0 dBFS) за последние 2 с — метка клиппинга. */
  clip: boolean;
  /** Пик-холд по каналам: держится ~1,5 с, потом плавно спадает. */
  holdL: number;
  holdR: number;
  /** Максимальный пик с последнего сброса (число над метром, тап — сброс). */
  max: number;
}

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
    }
    return {
      l: this.disp[0], r: this.disp[1], lufs: this.lufsCache, clip: now < this.clipUntil,
      holdL: this.hold[0], holdR: this.hold[1], max: this.max,
    };
  }
}

const SILENT: Level = { l: 0, r: 0, lufs: -Infinity, clip: false, holdL: 0, holdR: 0, max: 0 };

/** Снижение громкости дорожки от sidechain, дБ (≤ 0). */
export function trackDuckDb(i: number): number {
  const g = tracks[i]?.duck.gain.value ?? 1;
  return g < 0.999 ? 20 * Math.log10(Math.max(1e-4, g)) : 0;
}

/** Lookahead лимитера — показывается числом. */
export const limiterLookahead = () => doc.master['lim.lookahead'];

/** Уровень дорожки (после громкости микшера). */
export const trackLevel = (i: number, now: number): Level => (tracks[i] ? tracks[i].meter.read(now) : SILENT);

/** Мастер: вход и выход компрессора (после Makeup), вход лимитера, выход. */
export function masterLevels(now: number): { comp: Level; compOut: Level; lim: Level; out: Level } {
  if (!mst) return { comp: SILENT, compOut: SILENT, lim: SILENT, out: SILENT };
  return {
    comp: mst.compMeter.read(now), compOut: mst.compOutMeter.read(now),
    lim: mst.limMeter.read(now), out: mst.outMeter.read(now),
  };
}

/** Снижение усиления лимитера (дБ, ≤ 0). */
export const limiterReduction = () => (mst ? mst.lim.reduction : 0);

/** Дорожка звучит в стерео: стереофайл или панорама не по центру. */
export function trackIsStereo(i: number): boolean {
  const t = doc.tracks[i];
  const buf = buffers.get(t.sample);
  return (buf?.numberOfChannels ?? 1) > 1 || Math.abs(t.params.pan) >= 1;
}

/** Определённая высота сэмпла (MIDI) или null. */
export const sampleRoot = (key: string): number | null => doc.roots[key] ?? null;
