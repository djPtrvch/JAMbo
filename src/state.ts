// Единый модуль состояния приложения.
// doc — то, что сохраняется и отменяется через UNDO (позже сюда подключится звук).
// ui — текущие удержания кнопок/шагов и выбор. rt — данные реального времени (LFO, проигрывание).

import {
  FX_GRID, isAuto, MASTER_GRID, MAX_PAGES, MIX_GRID, MOD_GRID, PATTERN_SLOTS, RATIOS, STEPS_PER_PAGE, TRACK_COUNT, TRACK_GRID, OCTAVE_DEF, OCTAVE_MAX, OCTAVE_MIN,
  BPM_MAX, BPM_MIN, VOL_MIN_DB, PARAM_BY_ID, PRESET_PARAMS, SEQ_COUNT, SEQ_MIX, SEQ_MST, SYNTH_ENGINES, SYNTH_GRID, synthEngine, synthGrid, synthKey, EQ_BANDS, EQ_BELL, EQ_DYN_RANGE_MAX, EQ_DYN_THR_MIN, EQ_FREQ_MAX, EQ_FREQ_MIN, EQ_GAIN_MAX, EQ_Q_DEF, EQ_Q_MAX, EQ_Q_MIN, EQ_TYPES, NOTE_NAMES, PROGRESSIONS, SCALES, fromNorm, toNorm, type ParamDef, type Slot,
} from './params';

export interface Step {
  on: boolean;
  /** Длина ноты в шагах. */
  len: number;
  /** Ноты шага (MIDI). Несколько нот — POLY. */
  notes: number[];
  /** P-lock: id параметра → значение. Может быть и на шаге без ноты. */
  locks: Record<string, number>;
  /** Свой звук шага (сэмпл или движок синта) вместо звука дорожки — тоже p-lock. */
  sound?: string;
}

/** Источник модуляции: 1–3 = LFO1–LFO3, 4 = огибающая ENV. */
export type Mod = 1 | 2 | 3 | 4;
export const MOD_SOURCES: Mod[] = [1, 2, 3, 4];
export const modName = (m: Mod) => (m === 4 ? 'ENV' : `LFO${m}`);
const MOD_BUTTON: Record<Mod, HoldButton> = { 1: 'lfo1', 2: 'lfo2', 3: 'lfo3', 4: 'env' };

export interface LfoAssign {
  lfo: Mod;
  /** Степень воздействия −1..+1 (в долях хода ручки). */
  amount: number;
}

/** Паттерн ячейки сетки 8×8: звук дорожки (параметры, LFO) и последовательность. */
export interface Pattern {
  /** Сэмпл: 'file:<n>' — загруженный с iPad, '' — нет сэмпла. */
  sample: string;
  params: Record<string, number>;
  assigns: Record<string, LfoAssign>;
  pages: Step[][];
  length: number;
  playFrom: number;
  playTo: number;
}

/**
 * Дорожка. Поля params…playTo — это активный паттерн (его играем и редактируем);
 * остальные паттерны столбца лежат в slots, при переключении они меняются местами.
 */
export interface Track {
  name: string;
  sample: string;
  /** Параметры дорожки и её LFO (lfo1.*, lfo2.*). */
  params: Record<string, number>;
  assigns: Record<string, LfoAssign>;
  pages: Step[][];
  /** Длина паттерна в шагах (1..pages*16). */
  length: number;
  /** Какие страницы играют: диапазон playFrom..playTo. */
  playFrom: number;
  playTo: number;
  mute: boolean;
  solo: boolean;
  /** Параметры меняли с зажатым TRACK (на всю дорожку) — на дорожке жёлтая точка. */
  trackEdit: boolean;
  /** Значения до изменений с TRACK: по ним TRACK + UNDO возвращает дорожку назад. */
  trackOrig: Record<string, number>;
  trackOrigAssign: Record<string, LfoAssign | null>;
  /** Ячейки столбца сетки паттернов (null — пустая). */
  slots: (Pattern | null)[];
  /** Активная ячейка (её паттерн сейчас в полях дорожки). */
  slot: number;
  /** Дорожка остановлена в сетке паттернов (не играет). */
  stopped: boolean;
}

/** Полоса эквалайзера. */
export interface EqBand {
  on: boolean;
  /** Индекс в EQ_TYPES. */
  type: number;
  freq: number;
  gain: number;
  q: number;
  /** Индекс в EQ_SLOPES (для low cut и high cut). */
  slope: number;
  /** Индекс в EQ_MS: 0 STEREO (нет поля — тоже), 1 MID, 2 SIDE. */
  ms?: number;
  /** Динамическая полоса: −1 или нет поля — OFF, 0 — SELF, n — дорожка n (1…16). */
  dyn?: number;
  /** Порог детектора, dBFS, и сдвиг усиления, dB (у динамической полосы). */
  thr?: number;
  range?: number;
}

/** Эквалайзер канала: 8 мест под полосы (null — полосы нет). */
export interface Eq {
  on: boolean;
  bands: (EqBand | null)[];
}

/** Строка сетки паттернов (сцена): имя и число повторов до перехода на следующую (0 — без перехода). */
export interface Scene {
  name: string;
  repeats: number;
}

/** Звук в папке дорожки: сэмпл (ключ файла) или пресет синта (копия). */
export type FolderItem = { sample: string } | { preset: Preset };
export interface Folder { items: FolderItem[]; index: number }

export interface Doc {
  bpm: number;
  scale: number;
  root: number;
  tracks: Track[];
  fx: Record<string, number>;
  /** Громкости дорожек (микшер). */
  mixer: Record<string, number>;
  /** Компрессор и лимитер мастера. */
  master: Record<string, number>;
  /** Индекс в RATIOS (кнопка RATIO). */
  ratio: number;
  /** Лимитер мастера выключен (кнопка BYPASS). */
  limBypass: boolean;
  /** Громкость выхода мастера после лимитера, dB (VOL_MIN_DB — тишина; 0 — без ослабления). */
  outVol: number;
  /** Компрессор мастера выключен (кнопка BYPASS). */
  cmpBypass: boolean;
  /** BYPASS клиппера мастера. */
  clipBypass: boolean;
  /**
   * Свои последовательности каналов MIX и MST: шаги без нот, только p-lock параметров
   * микшера и мастера. Хранятся как дорожки (страницы, длина, играющие страницы).
   */
  chanSeqs: Track[];
  /**
   * Назначения LFO и ENV на параметры FX (общие эффекты): источник — LFO/ENV дорожки track,
   * выбранной при назначении.
   */
  fxAssigns: Record<string, LfoAssign & { track: number }>;
  /** Папки дорожек: загруженные сэмплы и пресеты, их перелистывают стрелки под окном сэмпла. */
  folders: Folder[];
  /** Строки сетки паттернов: имена и повторы. */
  scenes: Scene[];
  /** Эквалайзеры дорожек и мастера. */
  eqs: Eq[];
  masterEq: Eq;
  /** Имена загруженных файлов: ключ сэмпла → имя. */
  files: Record<string, string>;
  /** Определённая высота сэмплов: ключ → MIDI-нота (нет — C3). */
  roots: Record<string, number>;
}

export type GridMode = 'track' | 'fx' | 'mod' | 'mix' | 'master';
/** Что выбрано в строке дорожек: дорожка, канал микшера MIX или мастер MST. */
export type Channel = 'track' | 'mix' | 'master';
export type HoldButton = 'lfo1' | 'lfo2' | 'lfo3' | 'env' | 'track' | 'fx' | 'mod';

export interface HeldStep {
  index: number;
  /** На удержании уже что-то сделали (p-lock, длина) — триг на отпускании не трогаем. */
  used: boolean;
}

export interface Ui {
  selectedTrack: number;
  channel: Channel;
  viewPage: number;
  held: Record<HoldButton, boolean>;
  /** Порядок нажатия FX/MOD: побеждает нажатая последней. */
  modeOrder: ('fx' | 'mod')[];
  /** Последняя нажатая LFO-кнопка (если удерживаются обе). */
  lastLfo: Mod;
  heldSteps: Map<number, HeldStep>;
  playing: boolean;
  rec: boolean;
  clipboard: Step[] | null;
  pageMenu: number | null;
  patternClipboard: Pattern | null;
  topMenu: 'scale' | 'root' | 'progression' | null;
  metronome: boolean;
  /** Пианоролл. */
  octave: number;
  chordMode: boolean;
  progression: number;
  /** Выбранные ноты: ими ставятся новые триги. */
  selNotes: number[];
  /** Зажатые клавиши пианоролла: палец (pointerId) → его ноты. */
  pressedKeys: Map<number, number[]>;
  /** Центр экрана: сетка паттернов 8×8 вместо ручек. */
  patternView: boolean;
  /** Центр экрана: эквалайзер выбранной дорожки или мастера. */
  eqView: boolean;
  /** Редактор сэмпла (удержание окна сэмпла) на месте центра экрана, как EQ. */
  sampleView: boolean;
  /** Браузер библиотеки сэмплов и пресетов на месте центра экрана. */
  browserView: boolean;
  /** Выбранная полоса EQ (−1 — нет). */
  eqBand: number;
  /** Включён режим MORPH (временные изменения ручек). */
  morph: boolean;
  /** Превью формы волны LFO в окне сэмпла. */
  lfoPreviewUntil: number;
}

export interface Runtime {
  /** Текущий шаг проигрывания каждой дорожки (−1 = стоп). */
  playPos: number[];
  /** До какого момента (performance.now) мигает дорожка. */
  flashUntil: number[];
  lfoPhase: number[][];
  lfoRandom: number[][];
  /** Огибающая ENV: момент запуска и конец гейта (performance.now), start < 0 — не запускалась. */
  env: { start: number; gateEnd: number }[];
  /** Запуски ENV, запланированные наперёд (ноты секвенсора ставятся заранее), по времени. */
  envQueue: { start: number; gateEnd: number }[][];
  /** Ноты, которые сейчас звучат на дорожке (подсветка пианоролла). */
  noteFlash: { notes: number[]; until: number }[];
  /** Глобальный тик, с которого дорожка играет текущий паттерн. */
  trackStart: number[];
  /** Ожидает запуска по окончании текущего паттерна: номер ячейки, 'stop' или null. */
  queued: (number | 'stop' | null)[];
  /** Играющая строка (сцена): номер, тик запуска и длина прохода в шагах. */
  scene: { row: number; start: number; len: number } | null;
  /** Строка, которая ждёт запуска с начала следующего такта. */
  sceneQueued: number | null;
  /** P-lock проигрываемого шага каждой дорожки (индикация на ручках). */
  playLocks: { locks: Record<string, number>; until: number }[];
  /** Мигание метронома: до какого момента и сильная ли доля. */
  beatUntil: number;
  beatAccent: boolean;
}

// ---------- Создание ----------

function defaults(grid: Slot[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const p of grid) if (p) out[p.id] = p.def;
  return out;
}

export function emptyPage(): Step[] {
  return Array.from({ length: STEPS_PER_PAGE }, () => ({ on: false, len: 1, notes: [], locks: {} }));
}

function newEq(): Eq {
  return { on: true, bands: Array(EQ_BANDS).fill(null) };
}

function newTrack(i: number, name = `T${i + 1}`): Track {
  return {
    name,
    sample: '',
    params: { ...defaults(TRACK_GRID), ...defaults(SYNTH_GRID), ...defaults(MOD_GRID) },
    assigns: {},
    pages: [emptyPage()],
    length: STEPS_PER_PAGE,
    playFrom: 0,
    playTo: 0,
    mute: false,
    solo: false,
    trackEdit: false,
    trackOrig: {},
    trackOrigAssign: {},
    slots: Array(PATTERN_SLOTS).fill(null),
    slot: 0,
    stopped: false,
  };
}

/** Новый пустой проект. */
export function makeDoc(): Doc {
  return {
  bpm: 120,
  scale: 0,
  root: 0,
  tracks: Array.from({ length: TRACK_COUNT }, (_, i) => newTrack(i)),
  fx: defaults(FX_GRID),
  mixer: defaults(MIX_GRID),
  master: defaults(MASTER_GRID),
  ratio: 0,
  limBypass: false,
  cmpBypass: false,
  clipBypass: false,
  outVol: 0,
  chanSeqs: [newTrack(0, 'MIX'), newTrack(0, 'MST')],
  scenes: Array.from({ length: PATTERN_SLOTS }, () => ({ name: '', repeats: 0 })),
  folders: Array.from({ length: TRACK_COUNT }, () => ({ items: [], index: -1 })),
  fxAssigns: {},
  eqs: Array.from({ length: TRACK_COUNT }, () => newEq()),
  masterEq: newEq(),
  files: {},
  roots: {},
  };
}

export const doc: Doc = makeDoc();

export const ui: Ui = {
  selectedTrack: 0,
  channel: 'track',
  viewPage: 0,
  held: { lfo1: false, lfo2: false, lfo3: false, env: false, track: false, fx: false, mod: false },
  modeOrder: [],
  lastLfo: 1,
  heldSteps: new Map(),
  playing: false,
  rec: false,
  clipboard: null,
  pageMenu: null,
  patternClipboard: null,
  topMenu: null,
  metronome: false,
  octave: OCTAVE_DEF,
  chordMode: false,
  progression: 0,
  selNotes: [],
  pressedKeys: new Map(),
  patternView: false,
  eqView: false,
  sampleView: false,
  browserView: false,
  morph: false,
  eqBand: -1,
  lfoPreviewUntil: 0,
};

export const rt: Runtime = {
  playPos: Array(SEQ_COUNT).fill(-1),
  flashUntil: Array(TRACK_COUNT).fill(0),
  lfoPhase: Array.from({ length: TRACK_COUNT }, () => [0, 0, 0]),
  lfoRandom: Array.from({ length: TRACK_COUNT }, () => [0, 0, 0].map(() => Math.random() * 2 - 1)),
  env: Array.from({ length: TRACK_COUNT }, () => ({ start: -1, gateEnd: -1 })),
  envQueue: Array.from({ length: TRACK_COUNT }, () => []),
  noteFlash: Array.from({ length: TRACK_COUNT }, () => ({ notes: [], until: 0 })),
  playLocks: Array.from({ length: SEQ_COUNT }, () => ({ locks: {}, until: 0 })),
  trackStart: Array(SEQ_COUNT).fill(0),
  queued: Array(TRACK_COUNT).fill(null),
  scene: null,
  sceneQueued: null,
  beatUntil: 0,
  beatAccent: false,
};

// ---------- UNDO ----------

const undoStack: string[] = [];
/** Отменённые шаги (REDO); новое действие её очищает. */
const redoStack: string[] = [];
const UNDO_LIMIT = 200;
let gestureDepth = 0;
let gestureSnapshot = '';

const snapshot = () => JSON.stringify(doc);

/** Растёт при каждом изменении стека UNDO (новая запись, UNDO, REDO) — для дубля записи. */
let undoSerial = 0;

function pushUndo(snap: string) {
  undoSerial++;
  redoStack.length = 0;
  undoStack.push(snap);
  if (undoStack.length > UNDO_LIMIT) undoStack.shift();
}

/** Дискретное действие: одна запись в UNDO, если что-то изменилось. */
function edit(fn: () => void) {
  if (gestureDepth > 0) { fn(); return; }
  const before = snapshot();
  fn();
  if (snapshot() !== before) pushUndo(before);
}

/** Непрерывный жест (поворот ручки, протягивание ноты) — одна запись в UNDO на весь жест. */
export function beginGesture() {
  if (gestureDepth++ === 0) gestureSnapshot = snapshot();
}

export function endGesture() {
  if (gestureDepth === 0) return;
  if (--gestureDepth === 0 && snapshot() !== gestureSnapshot) pushUndo(gestureSnapshot);
}

export function undo() {
  const snap = undoStack.pop();
  if (!snap) return;
  undoSerial++;
  redoStack.push(snapshot());
  Object.assign(doc, JSON.parse(snap) as Doc);
  clampView();
}

/** REDO: вернуть отменённое UNDO. */
export function redo() {
  const snap = redoStack.pop();
  if (!snap) return;
  undoSerial++;
  undoStack.push(snapshot());
  Object.assign(doc, JSON.parse(snap) as Doc);
  clampView();
}

export const canRedo = () => redoStack.length > 0;

export const canUndo = () => undoStack.length > 0;

// ---------- Режимы ----------

export function gridMode(): GridMode {
  for (let i = ui.modeOrder.length - 1; i >= 0; i--) if (ui.held[ui.modeOrder[i]]) return ui.modeOrder[i];
  return ui.channel;
}

export function gridFor(mode: GridMode): Slot[] {
  // У дорожки с синтом колонка 1 — Harmonics, Timbre, Morph, Level.
  const engine = synthEngine(selTrack().sample);
  const track = engine !== null ? synthGrid(engine) : TRACK_GRID;
  return { track, fx: FX_GRID, mod: MOD_GRID, mix: MIX_GRID, master: MASTER_GRID }[mode];
}

export function setHeld(btn: HoldButton, down: boolean) {
  ui.held[btn] = down;
  if (down && (btn === 'fx' || btn === 'mod')) ui.modeOrder = [...ui.modeOrder.filter((m) => m !== btn), btn];
  const m = MOD_SOURCES.find((s) => MOD_BUTTON[s] === btn);
  if (down && m) ui.lastLfo = m;
}

/** Активная LFO-кнопка, если удерживается. */
export function heldLfo(): Mod | null {
  if (ui.held[MOD_BUTTON[ui.lastLfo]]) return ui.lastLfo;
  return MOD_SOURCES.find((m) => ui.held[MOD_BUTTON[m]]) ?? null;
}

/**
 * Дорожка, к которой применяется действие ручки — всегда выбранная.
 * С зажатым TRACK изменение идёт на всю дорожку (p-lock шагов остаются),
 * а на дорожке появляется жёлтая точка.
 */
function targetTracks(paramId: string, kind: 'param' | 'assign'): Track[] {
  const t = doc.tracks[ui.selectedTrack];
  if (ui.morph) {
    t.trackEdit = true;
    // Запоминаем исходное значение при первом изменении в режиме MORPH.
    if (kind === 'param' && !(paramId in t.trackOrig)) t.trackOrig[paramId] = t.params[paramId];
    if (kind === 'assign' && !(paramId in t.trackOrigAssign)) t.trackOrigAssign[paramId] = t.assigns[paramId] ?? null;
  }
  return [t];
}

/** TRACK + UNDO: отменить все изменения ручек, сделанные с TRACK, сразу на всех дорожках. */
/**
 * Кнопка MORPH (тап): включает режим, в котором ручки меняют дорожки временно; повторный тап
 * выключает его и возвращает все изменённые параметры к моменту включения.
 */
export function toggleMorph() {
  if (ui.morph) undoTrackEdits();
  ui.morph = !ui.morph;
}

export function undoTrackEdits() {
  edit(() => {
    for (const t of doc.tracks) {
      Object.assign(t.params, t.trackOrig);
      for (const [id, a] of Object.entries(t.trackOrigAssign)) {
        if (a) t.assigns[id] = a;
        else delete t.assigns[id];
      }
      t.trackOrig = {};
      t.trackOrigAssign = {};
      t.trackEdit = false;
    }
  });
}

export const selTrack = () => doc.tracks[ui.selectedTrack];

// ---------- Последовательности: дорожки и каналы MIX, MST ----------

export const seqAt = (k: number): Track => (k < TRACK_COUNT ? doc.tracks[k] : doc.chanSeqs[k - TRACK_COUNT]);
/** Последовательность, которую показывает секвенсор: выбранная дорожка, MIX или MST. */
export const seqIndex = () => (ui.channel === 'track' ? ui.selectedTrack : ui.channel === 'mix' ? SEQ_MIX : SEQ_MST);
export const curSeq = () => seqAt(seqIndex());
/** На шагах MIX и MST нет нот — только p-lock. */
export const seqHasNotes = () => ui.channel === 'track';

/** P-lock шага, который сейчас играет в последовательности k (или null). */
export function liveLocks(k: number, now = performance.now()): Record<string, number> | null {
  const pl = rt.playLocks[k];
  return ui.playing && pl && now < pl.until ? pl.locks : null;
}

/** Значения с p-lock играющих шагов: base, перекрытый p-lock последовательностей seqs. */
function withLocks(base: Record<string, number>, seqs: number[], now: number): Record<string, number> {
  let out: Record<string, number> | null = null;
  for (const k of seqs) {
    const l = liveLocks(k, now);
    if (!l) continue;
    for (const id in l) {
      if (!(id in base)) continue;
      out ??= { ...base };
      out[id] = l[id];
    }
  }
  return out ?? base;
}

const ALL_SEQS = Array.from({ length: SEQ_COUNT }, (_, k) => k);
/**
 * Общие FX с p-lock (шаг любой дорожки или MIX, MST меняет их на время шага) и с назначенными
 * LFO/ENV.
 */
export function liveFx(now = performance.now()): Record<string, number> {
  const fx = withLocks(doc.fx, ALL_SEQS, now);
  const ids = Object.keys(doc.fxAssigns);
  if (!ids.length) return fx;
  const out = { ...fx };
  for (const id of ids) {
    const p = PARAM_BY_ID[id];
    if (p && id in out) out[id] = fromNorm(p, fxModNorm(p, out[id]));
  }
  return out;
}
/** Громкости микшера с p-lock шагов последовательности MIX. */
export const liveMixer = (now = performance.now()) => withLocks(doc.mixer, [SEQ_MIX], now);
/** Компрессор и лимитер мастера с p-lock шагов последовательности MST. */
export const liveMaster = (now = performance.now()) => withLocks(doc.master, [SEQ_MST], now);
/** Параметры дорожки с p-lock её играющего шага (LFO, ENV — p-lock в режиме MOD). */
export const liveParams = (i: number, now = performance.now()) => withLocks(doc.tracks[i].params, [i], now);

// ---------- Параметры ----------

export function paramValue(mode: GridMode, p: ParamDef, track = selTrack()): number {
  if (mode === 'fx') return doc.fx[p.id];
  if (mode === 'mix') return doc.mixer[p.id];
  if (mode === 'master') return doc.master[p.id];
  return track.params[p.id];
}

export function setParamNorm(mode: GridMode, p: ParamDef, norm: number) {
  const v = fromNorm(p, norm);
  if (mode === 'fx') doc.fx[p.id] = v;
  else if (mode === 'mix') doc.mixer[p.id] = v;
  else if (mode === 'master') doc.master[p.id] = v;
  else for (const t of targetTracks(p.id, 'param')) t.params[p.id] = v;
  if (p.id.startsWith('lfo') || p.id.startsWith('env.')) ui.lfoPreviewUntil = performance.now() + 1500;
}

// ---------- LFO ----------

export function lfoShape(wave: number, phase: number, rnd: number): number {
  switch (wave) {
    case 0: return Math.sin(phase * 2 * Math.PI);
    case 1: return phase < 0.25 ? phase * 4 : phase < 0.75 ? 2 - phase * 4 : phase * 4 - 4;
    case 2: return phase * 2 - 1;
    case 3: return phase < 0.5 ? 1 : -1;
    default: return rnd;
  }
}

/** Выход LFO дорожки −1..+1 с учётом Depth и Invert. */
export function lfoOut(trackIndex: number, n: 1 | 2 | 3): number {
  const p = liveParams(trackIndex);
  const pre = `lfo${n}.`;
  const shape = lfoShape(p[pre + 'wave'], rt.lfoPhase[trackIndex][n - 1], rt.lfoRandom[trackIndex][n - 1]);
  const depth = p[pre + 'depth'] / 100;
  const polarity = 1 - 2 * p[pre + 'invert'];
  return shape * depth * polarity;
}

/** Продвинуть фазы всех LFO (LFO работают всегда, независимо от PLAY). */
export function advanceLfos(dt: number) {
  doc.tracks.forEach((_, i) => {
    const p = liveParams(i);
    for (const n of [1, 2, 3] as const) {
      let ph = rt.lfoPhase[i][n - 1] + dt * p[`lfo${n}.speed`];
      if (ph >= 1) {
        ph %= 1;
        rt.lfoRandom[i][n - 1] = Math.random() * 2 - 1;
      }
      rt.lfoPhase[i][n - 1] = ph;
    }
  });
}

// ---------- Огибающая ENV ----------

/** Уровень ADSR (0..1) через t мс после запуска при гейте gate мс; p — параметры дорожки. */
export function envShape(p: Record<string, number>, t: number, gate: number): number {
  const a = p['env.attack'];
  const d = p['env.decay'];
  const s = p['env.sustain'] / 100;
  const r = p['env.release'];
  const ads = (x: number) => (x < a ? x / a : x < a + d ? 1 - (1 - s) * (x - a) / d : s);
  if (t < 0) return 0;
  if (t < gate) return ads(t);
  const rel = t - gate;
  return rel < r ? ads(gate) * (1 - rel / r) : 0;
}

/**
 * Запуск огибающей дорожки тригом в момент start (performance.now, может быть в будущем —
 * ноты секвенсора планируются заранее); gateMs — длительность ноты.
 */
export function triggerEnv(trackIndex: number, start: number, gateMs: number) {
  const q = rt.envQueue[trackIndex];
  q.push({ start, gateEnd: start + gateMs });
  q.sort((a, b) => a.start - b.start);
  promoteEnv(trackIndex, performance.now());
}

/** Живая нота отпущена (палец снят с клавиши) — у огибающей начинается Release. */
export function releaseEnv(trackIndex: number, now = performance.now()) {
  const e = rt.env[trackIndex];
  if (e.start >= 0 && e.gateEnd > now) e.gateEnd = now;
}

/** Наступившие запуски из очереди становятся текущей огибающей. */
function promoteEnv(trackIndex: number, now: number) {
  const q = rt.envQueue[trackIndex];
  while (q.length && q[0].start <= now) rt.env[trackIndex] = q.shift()!;
}

/** Запуск огибающей, который действует в момент at (последний начавшийся к этому времени). */
export function envAt(trackIndex: number, at: number): { start: number; gateEnd: number } {
  const now = performance.now();
  promoteEnv(trackIndex, now);
  let e = rt.env[trackIndex];
  // Момент в будущем (начало запланированной ноты) — учитываем запланированные запуски.
  if (at > now) for (const x of rt.envQueue[trackIndex]) if (x.start <= at) e = x;
  return e;
}

export function envOut(trackIndex: number, at = performance.now()): number {
  const e = envAt(trackIndex, at);
  if (e.start < 0) return 0;
  return envShape(liveParams(trackIndex, at), at - e.start, e.gateEnd - e.start);
}

/** Выход источника модуляции: LFO −1..+1, ENV 0..1 (at — момент, по умолчанию сейчас). */
export function modOut(trackIndex: number, m: Mod, at?: number): number {
  return m === 4 ? envOut(trackIndex, at) : lfoOut(trackIndex, m);
}

/**
 * Значение ручки дорожки в 0..1 с учётом LFO (base — базовое или p-lock значение). at — момент
 * (начало запланированной ноты: ENV берётся на этот момент, а не на сейчас).
 */
export function modulatedNorm(trackIndex: number, p: ParamDef, base: number, at?: number): number {
  const a = doc.tracks[trackIndex].assigns[p.id];
  const n = toNorm(p, base);
  if (!a) return n;
  return Math.min(1, Math.max(0, n + a.amount * modOut(trackIndex, a.lfo, at)));
}

export function setLfoAmount(p: ParamDef, lfo: Mod, amount: number, mode: GridMode = 'track') {
  amount = Math.min(1, Math.max(-1, amount));
  // FX: источник — LFO/ENV выбранной дорожки.
  if (mode === 'fx') { doc.fxAssigns[p.id] = { lfo, amount, track: ui.selectedTrack }; return; }
  for (const t of targetTracks(p.id, 'assign')) t.assigns[p.id] = { lfo, amount };
}

export function clearLfoAssign(p: ParamDef, lfo: Mod, mode: GridMode = 'track') {
  edit(() => {
    if (mode === 'fx') { if (doc.fxAssigns[p.id]?.lfo === lfo) delete doc.fxAssigns[p.id]; return; }
    for (const t of targetTracks(p.id, 'assign')) if (t.assigns[p.id]?.lfo === lfo) delete t.assigns[p.id];
  });
}

/** Назначение LFO/ENV на ручку в режиме mode (дорожка или FX). */
export function assignFor(mode: GridMode, p: ParamDef): LfoAssign | undefined {
  if (mode === 'fx') return doc.fxAssigns[p.id];
  if (mode === 'track' || mode === 'mod') return selTrack().assigns[p.id];
  return undefined;
}

/** Значение параметра FX в 0..1 с учётом назначенного LFO/ENV. */
export function fxModNorm(p: ParamDef, base: number): number {
  const a = doc.fxAssigns[p.id];
  const n = toNorm(p, base);
  if (!a) return n;
  return Math.min(1, Math.max(0, n + a.amount * modOut(a.track, a.lfo)));
}

// ---------- Шаги и p-lock ----------

export function stepAt(t: Track, index: number): Step | undefined {
  return t.pages[Math.floor(index / STEPS_PER_PAGE)]?.[index % STEPS_PER_PAGE];
}

function turnOn(s: Step) {
  if (s.on) return;
  s.on = true;
  if (s.notes.length === 0) s.notes = trigNotes();
}

export function toggleStep(index: number) {
  if (!seqHasNotes()) return;
  edit(() => {
    const s = stepAt(curSeq(), index);
    if (!s) return;
    if (!s.on) { turnOn(s); return; }
    s.on = false;
    s.len = 1;
    s.notes = [];
    // Снятый триг забывает и p-lock, и свой звук шага.
    s.locks = {};
    delete s.sound;
  });
}

/** Протягивание: триг на шаге index длиной len шагов. */
export function setNoteLength(index: number, len: number) {
  if (!seqHasNotes()) return;
  const s = stepAt(curSeq(), index);
  if (!s) return;
  turnOn(s);
  s.len = Math.max(1, len);
}

export const hasLocks = (s: Step) => Object.keys(s.locks).length > 0 || !!s.sound;

/** Свой звук на шагах indices выбранной дорожки (null — снова звук дорожки). */
export function setStepSound(track: number, indices: number[], key: string | null, fileName?: string, root?: number | null) {
  edit(() => {
    for (const i of indices) {
      const s = stepAt(doc.tracks[track], i);
      if (!s) continue;
      if (key) s.sound = key;
      else delete s.sound;
    }
    if (key && fileName) doc.files[key] = fileName;
    if (key && typeof root === 'number') doc.roots[key] = root;
  });
}

/** Свой звук первого удерживаемого шага выбранной дорожки (для окна сэмпла) или null. */
export function heldStepSound(): string | null {
  const idx = firstHeldStep();
  if (idx === null || ui.channel !== 'track') return null;
  return stepAt(selTrack(), idx)?.sound ?? null;
}


export function setPatternLength(lastIndex: number) {
  edit(() => {
    const t = curSeq();
    t.length = Math.min(t.pages.length * STEPS_PER_PAGE, Math.max(1, lastIndex + 1));
  });
}

export function lockValue(index: number, p: ParamDef): number | undefined {
  return stepAt(curSeq(), index)?.locks[p.id];
}

export function setLockNorm(p: ParamDef, norm: number) {
  const v = fromNorm(p, norm);
  for (const h of ui.heldSteps.values()) {
    const s = stepAt(curSeq(), h.index);
    if (!s) continue;
    s.locks[p.id] = v;
    h.used = true;
  }
}

export function clearLock(p: ParamDef) {
  edit(() => {
    for (const h of ui.heldSteps.values()) {
      const s = stepAt(curSeq(), h.index);
      if (s) delete s.locks[p.id];
      h.used = true;
    }
  });
}

/** Первый удерживаемый шаг (для отображения p-lock на ручках). */
export function firstHeldStep(): number | null {
  for (const h of ui.heldSteps.values()) return h.index;
  return null;
}

// ---------- Страницы ----------

function clampView() {
  const t = curSeq();
  if (ui.viewPage >= t.pages.length) ui.viewPage = t.pages.length - 1;
}

export function selectTrack(i: number) {
  ui.selectedTrack = i;
  ui.channel = 'track';
  ui.heldSteps.clear();
  clampView();
}

/** Сохранить длину и диапазон «на все страницы», если они были полными. */
function changePages(t: Track, fn: () => void) {
  const full = t.length === t.pages.length * STEPS_PER_PAGE;
  const allPlay = t.playFrom === 0 && t.playTo === t.pages.length - 1;
  fn();
  const last = t.pages.length - 1;
  const max = t.pages.length * STEPS_PER_PAGE;
  t.length = full ? max : Math.min(t.length, max);
  if (allPlay) { t.playFrom = 0; t.playTo = last; }
  t.playTo = Math.min(t.playTo, last);
  t.playFrom = Math.min(t.playFrom, t.playTo);
}

/** Шаги, которые проигрываются: выбранные страницы, обрезанные длиной паттерна. */
export function playRange(t: Track): [number, number] {
  const a = t.playFrom * STEPS_PER_PAGE;
  let b = (t.playTo + 1) * STEPS_PER_PAGE - 1;
  if (t.length > a) b = Math.min(b, t.length - 1);
  return [a, b];
}

export function setPlayPages(from: number, to: number) {
  const t = curSeq();
  edit(() => {
    t.playFrom = Math.max(0, Math.min(from, to));
    t.playTo = Math.min(t.pages.length - 1, Math.max(from, to));
  });
}

const clonePage = (p: Step[]): Step[] => JSON.parse(JSON.stringify(p));

export function addPage() {
  const t = curSeq();
  if (t.pages.length >= MAX_PAGES) return;
  edit(() => changePages(t, () => t.pages.push(emptyPage())));
  ui.viewPage = t.pages.length - 1;
}

export function duplicatePage(i: number) {
  const t = curSeq();
  if (t.pages.length >= MAX_PAGES) return;
  edit(() => changePages(t, () => t.pages.splice(i + 1, 0, clonePage(t.pages[i]))));
  ui.viewPage = i + 1;
}

export function copyPage(i: number) {
  ui.clipboard = clonePage(curSeq().pages[i]);
}

export function pastePage(i: number) {
  const clip = ui.clipboard;
  if (!clip) return;
  edit(() => { curSeq().pages[i] = clonePage(clip); });
}

/** CLEAR: очистить страницу — все шаги пустые (ноты, триги, p-lock и звуки шагов убираются). */
export function clearPage(i: number) {
  const t = curSeq();
  if (!t.pages[i]) return;
  edit(() => { t.pages[i] = emptyPage(); });
}

export function deletePage(i: number) {
  const t = curSeq();
  if (t.pages.length <= 1) return;
  edit(() => changePages(t, () => t.pages.splice(i, 1)));
  clampView();
}

// ---------- Дорожки и верхняя панель ----------

export function renameTrack(i: number, name: string) {
  const n = name.trim().slice(0, 12);
  if (n) edit(() => { doc.tracks[i].name = n; });
}


/**
 * Свайп по дорожке: если включён mute или solo — любой свайп (вверх или вниз) его выключает;
 * иначе свайп вниз включает mute, вверх — solo. Одновременно mute и solo не бывает.
 */
export function swipeTrack(i: number, dir: 'up' | 'down') {
  edit(() => {
    const t = doc.tracks[i];
    if (t.mute) t.mute = false;
    else if (t.solo) t.solo = false;
    else if (dir === 'down') t.mute = true;
    else t.solo = true;
  });
}

/** Слышна ли дорожка с учётом mute/solo. */
export function audible(i: number): boolean {
  const anySolo = doc.tracks.some((t) => t.solo);
  const t = doc.tracks[i];
  return anySolo ? t.solo : !t.mute;
}

/** Громкость выхода мастера (регулятор на измерителе справа), dB. */
export function setOutVol(db: number) { doc.outVol = Math.min(0, Math.max(VOL_MIN_DB, db)); }
export function setBpm(v: number) { doc.bpm = Math.round(Math.min(BPM_MAX, Math.max(BPM_MIN, v))); }
export function setScale(v: number) { doc.scale = ((Math.round(v) % SCALES.length) + SCALES.length) % SCALES.length; }
export function setProgression(v: number) { ui.progression = ((Math.round(v) % PROGRESSIONS.length) + PROGRESSIONS.length) % PROGRESSIONS.length; }

// ---------- Пианоролл и аккорды ----------

/** Нижняя нота пианоролла: корневая нота выбранной октавы. */
export const baseNote = () => 12 * (ui.octave + 1) + doc.root;

export function setOctave(o: number) {
  ui.octave = Math.min(OCTAVE_MAX, Math.max(OCTAVE_MIN, o));
}

/** Ноты гаммы от baseNote на count ступеней вверх. */
export function scaleNotes(count: number, from = 0): number[] {
  const steps = SCALES[doc.scale].steps;
  const out: number[] = [];
  for (let k = from; k < from + count; k++) {
    const oct = Math.floor(k / steps.length);
    out.push(baseNote() + 12 * oct + steps[((k % steps.length) + steps.length) % steps.length]);
  }
  return out;
}

/** Трезвучие от ступени degree (ноты гаммы через одну). */
export function chordOnDegree(degree: number): number[] {
  return [0, 2, 4].map((k) => scaleNotes(1, degree + k)[0]);
}

/** Название аккорда ступени: C, Am, Bdim. */
export function chordName(degree: number): string {
  const [r, t, f] = chordOnDegree(degree);
  const third = t - r;
  const fifth = f - r;
  const q = fifth === 6 ? 'dim' : fifth === 8 ? 'aug' : third === 3 ? 'm' : '';
  return NOTE_NAMES[r % 12] + q;
}

export const isRoot = (midi: number) => midi % 12 === doc.root;

/** Ноты для нового трига: выбранные или корневая нота. */
export function trigNotes(): number[] {
  return ui.selNotes.length ? [...ui.selNotes].sort((a, b) => a - b) : [baseNote()];
}

/** Ноты удерживаемых шагов выбранной дорожки (для подсветки пианоролла). */
export function heldStepNotes(): number[] | null {
  const idx = firstHeldStep();
  if (idx === null) return null;
  return stepAt(curSeq(), idx)?.notes ?? [];
}

/** Все ноты, зажатые сейчас на пианоролле (по возрастанию). */
export function pressedNotes(): number[] {
  const all = new Set<number>();
  for (const notes of ui.pressedKeys.values()) notes.forEach((n) => all.add(n));
  return [...all].sort((a, b) => a - b);
}

/**
 * Нажатие на пианоролле: выбранными становятся все зажатые сейчас ноты
 * (одна нота — одна, несколько одновременно — все). Если удерживается шаг —
 * его ноты заменяются зажатыми.
 */
export function inputNotes() {
  const notes = pressedNotes();
  if (notes.length === 0) return;
  if (ui.heldSteps.size > 0 && seqHasNotes()) {
    edit(() => {
      for (const h of ui.heldSteps.values()) {
        const s = stepAt(selTrack(), h.index);
        if (!s) continue;
        h.used = true;
        s.notes = [...notes];
        s.on = true;
      }
    });
    return;
  }
  ui.selNotes = notes;
}

/**
 * Дубль записи: все ноты, записанные с REC за один проход (пока горят REC и PLAY и между ними не было
 * других действий), — одна запись в UNDO. Номер изменения стека UNDO после первой ноты дубля; −1 — дубля нет.
 */
let recTake = -1;
/** REC или PLAY выключены — дубль закончен (следующая запись — новый пункт UNDO). */
export const endRecTake = () => { recTake = -1; };

/** Запись с REC: ноты на шаг index. merge — добавить к уже записанным на этом проходе. */
export function recordNotes(trackIndex: number, index: number, notes: number[], merge: boolean) {
  const write = () => {
    const s = stepAt(doc.tracks[trackIndex], index);
    if (!s) return;
    s.notes = merge && s.on ? [...new Set([...s.notes, ...notes])].sort((a, b) => a - b) : [...notes];
    s.on = true;
    s.len = 1;
  };
  // Продолжение дубля — без новой записи в UNDO: UNDO отменяет весь дубль сразу.
  if (recTake >= 0 && recTake === undoSerial) { write(); return; }
  const before = undoSerial;
  edit(write);
  // Дубль начинается с первой ноты, которая что-то изменила (появилась запись в UNDO).
  recTake = undoSerial !== before ? undoSerial : -1;
}
export function setRoot(v: number) { doc.root = ((Math.round(v) % NOTE_NAMES.length) + NOTE_NAMES.length) % NOTE_NAMES.length; }


// ---------- Сетка паттернов 8×8 ----------

const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

function takePattern(t: Track): Pattern {
  return clone({ sample: t.sample, params: t.params, assigns: t.assigns, pages: t.pages, length: t.length, playFrom: t.playFrom, playTo: t.playTo });
}

function putPattern(t: Track, p: Pattern) {
  Object.assign(t, clone(p));
}

/** Ячейка не пустая. Активная ячейка всегда занята. */
export const slotFilled = (t: Track, k: number) => k === t.slot || t.slots[k] !== null;

/** Сделать ячейку k активной: текущий паттерн уходит в свою ячейку, паттерн k загружается. */
export function activateSlot(i: number, k: number) {
  edit(() => {
    const t = doc.tracks[i];
    if (k !== t.slot) {
      t.slots[t.slot] = takePattern(t);
      const next = t.slots[k];
      if (next) putPattern(t, next);
      t.slots[k] = null;
      t.slot = k;
    }
    t.stopped = false;
  });
  if (i === ui.selectedTrack) {
    ui.heldSteps.clear();
    clampView();
  }
}

export function stopTrack(i: number) {
  edit(() => { doc.tracks[i].stopped = true; });
}

/** Новый паттерн в пустой ячейке: копия звука дорожки, пустая последовательность. */
export function createPattern(i: number, k: number) {
  edit(() => {
    const t = doc.tracks[i];
    t.slots[k] = {
      sample: t.sample, params: clone(t.params), assigns: clone(t.assigns), pages: [emptyPage()],
      length: STEPS_PER_PAGE, playFrom: 0, playTo: 0,
    };
  });
}

/** Копия паттерна ячейки (null — пустая). */
export function patternAt(t: Track, k: number): Pattern | null {
  if (k === t.slot) return takePattern(t);
  return t.slots[k] ? clone(t.slots[k]) : null;
}

function setPatternAt(t: Track, k: number, p: Pattern) {
  if (k === t.slot) putPattern(t, p);
  else t.slots[k] = clone(p);
}

/** Ближайшая пустая ячейка ниже k (потом сверху), −1 — свободных нет. */
export function freeSlotAfter(t: Track, k: number): number {
  for (let d = 1; d < PATTERN_SLOTS; d++) {
    const j = (k + d) % PATTERN_SLOTS;
    if (!slotFilled(t, j)) return j;
  }
  return -1;
}

export function duplicatePattern(i: number, k: number) {
  const t = doc.tracks[i];
  const j = freeSlotAfter(t, k);
  const p = patternAt(t, k);
  if (j < 0 || !p) return;
  edit(() => { t.slots[j] = p; });
}

export function copyPattern(i: number, k: number) {
  ui.patternClipboard = patternAt(doc.tracks[i], k);
}

/** Перетаскивание: копия паттерна (i, k) в ячейку (j, m) — новая или вместо прежнего. */
export function dropPattern(i: number, k: number, j: number, m: number) {
  if (i === j && k === m) return;
  const p = patternAt(doc.tracks[i], k);
  if (!p) return;
  edit(() => setPatternAt(doc.tracks[j], m, p));
  if (j === ui.selectedTrack) clampView();
}

export function pastePattern(i: number, k: number) {
  const clip = ui.patternClipboard;
  if (!clip) return;
  edit(() => setPatternAt(doc.tracks[i], k, clip));
  if (i === ui.selectedTrack) clampView();
}

/** Удаление: ячейка пустеет; у активной очищаются шаги (звук остаётся) и дорожка останавливается. */
export function deletePattern(i: number, k: number) {
  const t = doc.tracks[i];
  edit(() => {
    if (k !== t.slot) { t.slots[k] = null; return; }
    putPattern(t, { ...takePattern(t), pages: [emptyPage()], length: STEPS_PER_PAGE, playFrom: 0, playTo: 0 });
    t.stopped = true;
  });
  if (i === ui.selectedTrack) { ui.heldSteps.clear(); clampView(); }
}

// ---------- Микшер, мастер, сэмплы ----------

export function selectChannel(c: Channel) {
  ui.channel = c;
  ui.heldSteps.clear();
  clampView();
}

/** Кнопка BYPASS компрессора мастера. */
export function toggleCmpBypass() {
  edit(() => { doc.cmpBypass = !doc.cmpBypass; });
}

export function toggleClipBypass() {
  edit(() => { doc.clipBypass = !doc.clipBypass; });
}

/** Кнопка BYPASS лимитера мастера. */
export function toggleLimBypass() {
  edit(() => { doc.limBypass = !doc.limBypass; });
}

/** Кнопка RATIO мастера: следующее значение по кругу. */
export function cycleRatio() {
  edit(() => { doc.ratio = (doc.ratio + 1) % RATIOS.length; });
}

/** Поставить сэмпл на дорожку (активный паттерн). */
export function setTrackSample(i: number, key: string, fileName?: string, root?: number | null) {
  edit(() => {
    doc.tracks[i].sample = key;
    if (fileName) doc.files[key] = fileName;
    if (typeof root === 'number') doc.roots[key] = root;
  });
}

/** Синт на дорожке: движок Plaits engine (меню окна сэмпла). */
export function setTrackSynth(i: number, engine: number) {
  setTrackSample(i, synthKey(engine));
}

// ---------- Пресеты синта ----------

/** Пресет синта: движок и параметры звука (PRESET_PARAMS). */
export interface Preset { name: string; sound: string; params: Record<string, number> }

// Папка пресетов общая для всех дорожек и хранится в браузере (переживает перезагрузку).
const PRESET_STORE = 'jambo.presets';
let presetList: Preset[] = loadPresets();

function loadPresets(): Preset[] {
  try {
    const list = JSON.parse(localStorage.getItem(PRESET_STORE) ?? '[]');
    return Array.isArray(list) ? list : [];
  } catch { return []; }
}

function storePresets() {
  try { localStorage.setItem(PRESET_STORE, JSON.stringify(presetList)); } catch { /* хранилище недоступно */ }
}

export const presets = () => presetList;

/** Имя нового пресета по умолчанию: движок и номер. */
export function nextPresetName(i: number): string {
  const e = synthEngine(doc.tracks[i].sample);
  const base = e !== null ? SYNTH_ENGINES[e].name : 'PRESET';
  return `${base} ${presetList.filter((p) => p.name.startsWith(base)).length + 1}`;
}

/** Сохранить синт дорожки i в библиотеку пресетов и в папку дорожки. */
export function savePreset(i: number, name: string) {
  const t = doc.tracks[i];
  if (synthEngine(t.sample) === null) return;
  const params: Record<string, number> = {};
  for (const id of PRESET_PARAMS) params[id] = t.params[id];
  const p = { name: name.trim() || nextPresetName(i), sound: t.sample, params };
  presetList.push(p);
  storePresets();
  edit(() => addItems(i, [{ preset: clone(p) }]));
}

/** Пресет из синта дорожки i (SAVE в браузер библиотеки); у сэмпла — null. */
export function presetFromTrack(i: number, name: string): Preset | null {
  const t = doc.tracks[i];
  if (synthEngine(t.sample) === null) return null;
  const params: Record<string, number> = {};
  for (const id of PRESET_PARAMS) params[id] = t.params[id];
  return { name: name.trim() || nextPresetName(i), sound: t.sample, params };
}

/** Сохранённый пресет — и в папку дорожки (стрелки под окном сэмпла его перелистывают). */
export function addPresetToFolder(i: number, p: Preset) {
  edit(() => addItems(i, [{ preset: clone(p) }]));
}

/** Пресет из библиотеки (браузер): добавляется в папку дорожки и звучит на ней. */
export function applyPreset(i: number, p: Preset) {
  edit(() => {
    const at = addItems(i, [{ preset: clone(p) }]);
    applyItem(i, doc.folders[i].items[at]);
  });
}

/** Пресет k из библиотеки (LOAD): добавляется в папку дорожки и звучит на ней. */
export function loadPreset(i: number, k: number) {
  const p = presetList[k];
  if (!p) return;
  edit(() => {
    const at = addItems(i, [{ preset: clone(p) }]);
    applyItem(i, doc.folders[i].items[at]);
  });
}

/** Меню удержания пресета: переименовать. */
export function renamePreset(k: number, name: string) {
  const p = presetList[k];
  const n = name.trim();
  if (!p || !n) return;
  p.name = n.slice(0, 16);
  storePresets();
}

/** Меню удержания пресета: копия сразу после него. */
export function duplicatePreset(k: number) {
  const p = presetList[k];
  if (!p) return;
  presetList.splice(k + 1, 0, { ...clone(p), name: `${p.name} copy`.slice(0, 16) });
  storePresets();
}

/** Меню удержания пресета: удалить из библиотеки (в папках дорожек копии остаются). */
export function deletePreset(k: number) {
  if (!presetList[k]) return;
  presetList.splice(k, 1);
  storePresets();
}

// ---------- Папка дорожки: сэмплы и пресеты на стрелках ----------

const itemKey = (it: FolderItem) => ('sample' in it ? it.sample : it.preset.sound);
export const itemName = (it: FolderItem) => ('sample' in it ? sampleName(it.sample) : it.preset.name);

/** Добавить звуки в папку дорожки (уже лежащий там сэмпл не повторяется); номер первого. */
function addItems(i: number, items: FolderItem[]): number {
  const f = doc.folders[i];
  let first = -1;
  for (const it of items) {
    let k = 'sample' in it ? f.items.findIndex((x) => 'sample' in x && x.sample === it.sample) : -1;
    if (k < 0) { f.items.push(it); k = f.items.length - 1; }
    if (first < 0) first = k;
  }
  if (first >= 0) f.index = first;
  return first;
}

/** Поставить звук из папки на дорожку (пресет — движок и его параметры). */
function applyItem(i: number, it: FolderItem) {
  const t = doc.tracks[i];
  if ('sample' in it) { t.sample = it.sample; return; }
  t.sample = it.preset.sound;
  for (const id of PRESET_PARAMS) if (typeof it.preset.params[id] === 'number') t.params[id] = it.preset.params[id];
}

/** Загруженные файлы (уже декодированные, ключи keys) — в папку дорожки, первый звучит. */
export function addSamplesToFolder(i: number, keys: string[]) {
  edit(() => {
    const at = addItems(i, keys.map((sample) => ({ sample })));
    if (at >= 0) applyItem(i, doc.folders[i].items[at]);
  });
}

/** Добавить сэмплы в папку, не меняя звук дорожки (выбор файла для зажатого шага). */
export function addSamplesQuiet(i: number, keys: string[]) {
  const f = doc.folders[i];
  const index = f.index;
  edit(() => { addItems(i, keys.map((sample) => ({ sample }))); f.index = index < 0 ? f.index : index; });
}

/**
 * Редактор сэмпла: отредактированная копия (newKey) встаёт на дорожку вместо oldKey — и в папке
 * на его место (UNDO возвращает исходный).
 */
export function replaceSample(i: number, oldKey: string, newKey: string) {
  edit(() => {
    const t = doc.tracks[i];
    const f = doc.folders[i];
    const k = f.items.findIndex((it) => 'sample' in it && it.sample === oldKey);
    if (k >= 0) { f.items[k] = { sample: newKey }; f.index = k; }
    else addItems(i, [{ sample: newKey }]);
    t.sample = newKey;
  });
}

/** Стрелки: соседний звук папки на дорожку. */
export function stepFolder(i: number, dir: 1 | -1) {
  const f = doc.folders[i];
  const n = f.items.length;
  if (!n) return;
  edit(() => {
    f.index = f.index < 0 ? (dir > 0 ? 0 : n - 1) : (f.index + dir + n) % n;
    applyItem(i, f.items[f.index]);
  });
}

/** Номер звука шага в папке (по его звуку) или −1. */
function stepItemIndex(i: number, s: Step): number {
  if (!s.sound) return -1;
  return doc.folders[i].items.findIndex((it) => itemKey(it) === s.sound);
}

/**
 * Зажат шаг + стрелка: шагу — соседний звук папки (p-lock звука; у пресета ещё и p-lock его
 * параметров). Начинаем от звука шага, а если его нет — от звука дорожки.
 */
export function stepFolderOnSteps(i: number, indices: number[], dir: 1 | -1) {
  const f = doc.folders[i];
  const n = f.items.length;
  if (!n) return;
  edit(() => {
    for (const idx of indices) {
      const s = stepAt(doc.tracks[i], idx);
      if (!s) continue;
      const cur = stepItemIndex(i, s);
      const base = cur >= 0 ? cur : f.index;
      const k = base < 0 ? (dir > 0 ? 0 : n - 1) : (base + dir + n) % n;
      const it = f.items[k];
      s.sound = itemKey(it);
      if ('preset' in it) for (const id of PRESET_PARAMS) if (typeof it.preset.params[id] === 'number') s.locks[id] = it.preset.params[id];
    }
  });
}

/** Позиция для подписи между стрелками: [номер, всего]; с зажатым шагом — звук шага. */
export function folderPos(i: number): [number, number] {
  const f = doc.folders[i];
  const idx = firstHeldStep();
  if (idx !== null && ui.channel === 'track') {
    const s = stepAt(doc.tracks[i], idx);
    if (s?.sound) return [stepItemIndex(i, s) + 1, f.items.length];
  }
  return [f.index + 1, f.items.length];
}

/** Имя текущего звука папки, если он сейчас на дорожке ('' — нет). */
export function folderItemName(i: number): string {
  const f = doc.folders[i];
  const it = f.items[f.index];
  return it && itemKey(it) === doc.tracks[i].sample && 'preset' in it ? it.preset.name : '';
}

/** Имя звука для окна сэмпла (файл или движок синта). */
export function sampleName(key: string): string {
  if (!key) return 'No sample';
  const e = synthEngine(key);
  if (e !== null) return SYNTH_ENGINES[e]?.name ?? 'SYNTH';
  return doc.files[key] ?? 'file';
}

// ---------- Эквалайзер ----------

/** EQ, который показывает панель: выбранной дорожки, а при MIX и MST — мастера. */
export const eqTarget = (): Eq => (ui.channel === 'track' ? doc.eqs[ui.selectedTrack] : doc.masterEq);
export const eqTargetName = () => (ui.channel === 'track' ? doc.tracks[ui.selectedTrack].name : 'MASTER');
export const selectedBand = (): EqBand | null => (ui.eqBand >= 0 ? eqTarget().bands[ui.eqBand] : null);

const clampN = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** Кнопки PATTERNS и EQ переключают центр экрана (одновременно открыт только один вид). */
export function toggleView(v: 'patterns' | 'eq' | 'sample' | 'browser') {
  const open = v === 'patterns' ? !ui.patternView : v === 'eq' ? !ui.eqView : v === 'sample' ? !ui.sampleView : !ui.browserView;
  ui.patternView = v === 'patterns' && open;
  ui.eqView = v === 'eq' && open;
  ui.sampleView = v === 'sample' && open;
  ui.browserView = v === 'browser' && open;
}

/** Новая bell-полоса (двойной тап по пустому месту); −1, если мест нет. */
export function addEqBand(freq: number, gain: number): number {
  const eq = eqTarget();
  const k = eq.bands.indexOf(null);
  if (k < 0) return -1;
  edit(() => {
    eq.bands[k] = { on: true, type: EQ_BELL, freq: clampN(freq, EQ_FREQ_MIN, EQ_FREQ_MAX), gain: clampN(gain, -EQ_GAIN_MAX, EQ_GAIN_MAX), q: EQ_Q_DEF, slope: 0 };
  });
  ui.eqBand = k;
  return k;
}

/** Изменить значения полосы (внутри жеста — одна запись UNDO на жест). */
export function setEqBand(k: number, patch: Partial<Pick<EqBand, 'freq' | 'gain' | 'q'>>) {
  const b = eqTarget().bands[k];
  if (!b) return;
  edit(() => {
    if (patch.freq !== undefined) b.freq = clampN(patch.freq, EQ_FREQ_MIN, EQ_FREQ_MAX);
    if (patch.gain !== undefined) b.gain = Math.round(clampN(patch.gain, -EQ_GAIN_MAX, EQ_GAIN_MAX) * 10) / 10;
    if (patch.q !== undefined) b.q = clampN(patch.q, EQ_Q_MIN, EQ_Q_MAX);
  });
}

export function setEqType(k: number, type: number) {
  const b = eqTarget().bands[k];
  if (b) edit(() => { b.type = ((Math.round(type) % EQ_TYPES.length) + EQ_TYPES.length) % EQ_TYPES.length; });
}

export function setEqSlope(k: number, slope: number) {
  const b = eqTarget().bands[k];
  if (b) edit(() => { b.slope = slope; });
}

/** Режим полосы: 0 STEREO, 1 MID, 2 SIDE. */
export function setEqMs(k: number, ms: number) {
  const b = eqTarget().bands[k];
  if (b) edit(() => { b.ms = ms; });
}

/** Источник динамической полосы: −1 OFF, 0 SELF, n — дорожка n. */
export function setEqDyn(k: number, src: number) {
  const b = eqTarget().bands[k];
  if (b) edit(() => { b.dyn = src; });
}

/** Порог (dBFS) и сдвиг (dB) динамической полосы (внутри жеста — одна запись UNDO). */
export function setEqDynParams(k: number, patch: { thr?: number; range?: number }) {
  const b = eqTarget().bands[k];
  if (!b) return;
  edit(() => {
    if (patch.thr !== undefined) b.thr = Math.round(clampN(patch.thr, EQ_DYN_THR_MIN, 0) * 10) / 10;
    if (patch.range !== undefined) b.range = Math.round(clampN(patch.range, -EQ_DYN_RANGE_MAX, EQ_DYN_RANGE_MAX) * 10) / 10;
  });
}

/** Двойной тап по точке: включить или выключить полосу. */
export function toggleEqBand(k: number) {
  const b = eqTarget().bands[k];
  if (b) edit(() => { b.on = !b.on; });
}

export function deleteEqBand(k: number) {
  const eq = eqTarget();
  edit(() => { eq.bands[k] = null; });
  if (ui.eqBand === k) ui.eqBand = -1;
}

/** Кнопка EQ ON: включение и выключение эквалайзера канала (bypass). */
export function toggleEq() {
  const eq = eqTarget();
  edit(() => { eq.on = !eq.on; });
}

/** Кнопка RESET: удалить все полосы канала. */
export function resetEq() {
  const eq = eqTarget();
  edit(() => { eq.bands = Array(EQ_BANDS).fill(null); });
  ui.eqBand = -1;
}

// ---------- Строки сетки паттернов (сцены) ----------

/** В строке k есть хотя бы один паттерн. */
export const rowFilled = (k: number) => doc.tracks.some((t) => slotFilled(t, k));

/** Имя строки для колонки сцен (без имени — номер). */
export const sceneName = (k: number) => doc.scenes[k].name || String(k + 1);

/** Имя и число повторов строки (меню по удержанию ячейки сцены). */
export function setScene(k: number, name: string, repeats: number) {
  edit(() => {
    doc.scenes[k] = { name: name.trim().slice(0, 12), repeats: Math.max(0, Math.min(64, Math.round(repeats))) };
  });
}

// ---------- Проекты: замена документа и переход между проектами ----------

/** Сбросить историю UNDO (при открытии другого проекта). */
export function resetUndo() {
  undoStack.length = 0;
  redoStack.length = 0;
}

/**
 * Привести сохранённый документ к текущему формату: недостающие поля берутся из нового
 * проекта (в том числе новые параметры дорожек и паттернов).
 */
export function normalizeDoc(raw: unknown): Doc {
  const base = makeDoc();
  const d = { ...base, ...(raw as Partial<Doc>) } as Doc;
  const trackDefaults = base.tracks[0].params;
  const fixParams = (p: { params: Record<string, number> }) => { p.params = { ...trackDefaults, ...p.params }; };
  d.tracks = base.tracks.map((bt, i) => {
    const t = { ...bt, ...(d.tracks?.[i] ?? {}) } as Track;
    fixParams(t);
    t.slots = Array.from({ length: PATTERN_SLOTS }, (_, k) => t.slots?.[k] ?? null);
    t.slots.forEach((p) => { if (p) fixParams(p); });
    return t;
  });
  d.chanSeqs = base.chanSeqs.map((b, k) => ({ ...b, ...(d.chanSeqs?.[k] ?? {}) }));
  d.scenes = base.scenes.map((b, k) => d.scenes?.[k] ?? b);
  d.folders = base.folders.map((b, k) => d.folders?.[k] ?? b);
  d.eqs = base.eqs.map((b, k) => d.eqs?.[k] ?? b);
  for (const key of ['fx', 'mixer', 'master'] as const) d[key] = { ...base[key], ...d[key] };
  // RATIO теперь 2:1, 4:1, 10:1 — прежние 8:1 и 20:1 становятся 10:1.
  d.ratio = Math.min(RATIOS.length - 1, Math.max(0, Math.round(d.ratio ?? 0)));
  // Значения мастера — в пределах нынешних шкал (у компрессора они стали другими).
  for (const p of MASTER_GRID) if (p && !isAuto(d.master[p.id]) && !(p.offBottom && d.master[p.id] <= 0)) d.master[p.id] = Math.min(p.max, Math.max(p.min, d.master[p.id]));
  return d;
}

/** Ключи всех сэмплов, на которые ссылается документ. */
export function sampleKeys(d: Doc): string[] {
  const keys = new Set<string>(Object.keys(d.files));
  const add = (k?: string) => { if (k && k.startsWith('s:')) keys.add(k); };
  const pats = (t: Track) => [t, ...t.slots.filter((p): p is Pattern => !!p)];
  for (const t of d.tracks) {
    for (const p of pats(t)) {
      add(p.sample);
      p.pages.forEach((pg) => pg.forEach((st) => add(st.sound)));
    }
  }
  d.folders.forEach((f) => f.items.forEach((it) => add('sample' in it ? it.sample : undefined)));
  return [...keys].filter((k) => k.startsWith('s:'));
}

/** Сброс выбора и удержаний интерфейса при открытии проекта. */
function resetUi() {
  ui.selectedTrack = 0;
  ui.channel = 'track';
  ui.viewPage = 0;
  ui.heldSteps.clear();
  ui.eqBand = -1;
  ui.morph = false;
  ui.pageMenu = null;
}

/** Открыть проект без перехода: документ целиком заменяется. */
export function loadDoc(d: Doc) {
  transition = null;
  xfade = null;
  Object.assign(doc, d);
  resetUndo();
  resetUi();
  rt.queued.fill(null);
  rt.scene = null;
  rt.sceneQueued = null;
}

/**
 * Переход между проектами во время игры: играющие паттерны старого проекта опускаются в нижнюю
 * строку сетки (строка 8, PREV) и доигрывают; строки 1–7 нового проекта стоят на своих местах,
 * его строка 8 временно скрыта. Когда в строке 8 больше ничего не играет, она возвращается.
 * Общие настройки (темп, гамма, FX, микшер, мастер, EQ) переходят от старого проекта к новому
 * вертикальным кроссфейдером справа от сетки паттернов (внизу — старый, вверху — новый).
 */
/** real[i] — в строке PREV дорожки настоящий старый паттерн (иначе пустая заглушка). */
interface Transition { hidden: (Pattern | null)[]; origSlot: number[]; hiddenScene: Scene; real: boolean[] }
let transition: Transition | null = null;
export const inTransition = () => transition !== null;
/** Ячейка строки PREV без старого паттерна (рисуется пустой). */
export const isPrevPlaceholder = (i: number, k: number) => !!transition && k === PATTERN_SLOTS - 1 && !transition.real[i];
const LAST = PATTERN_SLOTS - 1;

/** Строки, из которых старые паттерны опустились вниз (для анимации): дорожка → строка. */
export const transitionMoves: { track: number; from: number }[] = [];

/** Все паттерны столбца по строкам (активный — из полей дорожки). */
const rowsOf = (t: Track) => Array.from({ length: PATTERN_SLOTS }, (_, k) => patternAt(t, k));

/** Перестроить столбец дорожки: паттерны по строкам и активная строка. */
function setRows(t: Track, rows: (Pattern | null)[], active: number) {
  putPattern(t, rows[active]!);
  t.slots = rows.map((p, k) => (k === active ? null : p ? clone(p) : null));
  t.slot = active;
}

/** Пустой паттерн со звуком p (заглушка активной строки). */
const emptyLike = (p: Pattern): Pattern => ({ ...clone(p), pages: [emptyPage()], length: STEPS_PER_PAGE, playFrom: 0, playTo: 0 });

// ---------- Кроссфейдер общих настроек ----------

const GLOBAL_KEYS = ['bpm', 'scale', 'root', 'fx', 'mixer', 'master', 'ratio', 'limBypass', 'cmpBypass', 'clipBypass', 'eqs', 'masterEq', 'outVol'] as const;
type Globals = Pick<Doc, (typeof GLOBAL_KEYS)[number]>;
const takeGlobals = (d: Doc): Globals => clone(Object.fromEntries(GLOBAL_KEYS.map((k) => [k, d[k]])) as Globals);

/** Кроссфейдер: от общих настроек старого проекта (0) к новому (1). */
let xfade: { from: Globals; to: Globals; pos: number } | null = null;
export const crossfade = () => (xfade ? xfade.pos : null);

/** Числа — плавно, ступенчатые и всё прочее (гамма, нота, Ratio, BYPASS, EQ) — на середине. */
function blendRecord(a: Record<string, number>, b: Record<string, number>, t: number): Record<string, number> {
  const out: Record<string, number> = {};
  for (const id of Object.keys(b)) {
    const x = a[id] ?? b[id];
    const p = PARAM_BY_ID[id];
    out[id] = p && p.kind === 'smooth' ? x + (b[id] - x) * t : t < 0.5 ? x : b[id];
  }
  return out;
}

/** Положение кроссфейдера 0..1: общие настройки документа — смесь старых и новых. */
export function setCrossfade(pos: number) {
  if (!xfade) return;
  const t = Math.max(0, Math.min(1, pos));
  xfade.pos = t;
  const { from: a, to: b } = xfade;
  const half = t < 0.5 ? a : b;
  doc.bpm = Math.round(a.bpm + (b.bpm - a.bpm) * t);
  doc.outVol = a.outVol + (b.outVol - a.outVol) * t;
  doc.scale = half.scale;
  doc.root = half.root;
  doc.fx = blendRecord(a.fx, b.fx, t);
  doc.mixer = blendRecord(a.mixer, b.mixer, t);
  doc.master = blendRecord(a.master, b.master, t);
  doc.ratio = half.ratio;
  doc.limBypass = half.limBypass;
  doc.cmpBypass = half.cmpBypass;
  doc.clipBypass = half.clipBypass;
  doc.eqs = clone(half.eqs);
  doc.masterEq = clone(half.masterEq);
  // У NEW — ровно настройки нового проекта. Кроссфейдер исчезает вместе со строкой PREV
  // (updateTransition), когда дорожки перешли на новые паттерны.
  if (t >= 1) Object.assign(doc, clone(b));
}

export function switchWithTransition(next: Doc) {
  // В PREV ложатся все старые паттерны с тригами; играть продолжают только те, что звучали
  // (идёт проигрывание и дорожка не остановлена), остальные стоят незапущенными.
  // Дорожка, которая ждала остановки, тоже остаётся стоять.
  const old = doc.tracks.map((t, i) => {
    const trigs = t.pages.some((pg) => pg.some((st) => st.on));
    return { trigs, playing: ui.playing && !t.stopped && rt.queued[i] !== 'stop' && trigs, pattern: takePattern(t), row: t.slot, mute: t.mute, solo: t.solo };
  });
  const from = takeGlobals(doc);
  const tr: Transition = { hidden: [], origSlot: [], hiddenScene: next.scenes[LAST], real: [] };
  transitionMoves.length = 0;
  next.tracks.forEach((t, i) => {
    const rows = rowsOf(t);
    tr.hidden[i] = rows[LAST];
    tr.origSlot[i] = t.slot;
    const { playing, trigs } = old[i];
    tr.real[i] = trigs;
    const prev = trigs ? old[i].pattern : emptyLike(takePattern(t));
    setRows(t, [...rows.slice(0, LAST), prev], LAST);
    t.stopped = !playing;
    // Mute и solo дорожек переходят из старого проекта: заглушённая дорожка молчит и на новых паттернах.
    t.mute = old[i].mute;
    t.solo = old[i].solo;
    if (trigs) transitionMoves.push({ track: i, from: old[i].row });
  });
  next.scenes = [...next.scenes.slice(0, LAST), { name: 'PREV', repeats: 0 }];
  const to = takeGlobals(next);
  Object.assign(doc, next);
  transition = tr;
  // Общие настройки пока старые — кроссфейдер внизу.
  xfade = { from, to, pos: 0 };
  setCrossfade(0);
  resetUndo();
  resetUi();
  rt.queued.fill(null);
  rt.scene = null;
  rt.sceneQueued = null;
}

/** Вернуть строку 8 нового проекта вместо строки PREV в документе d. */
function unshiftDoc(d: Doc, tr: Transition) {
  d.tracks.forEach((t, i) => {
    const rows = [...rowsOf(t).slice(0, LAST), tr.hidden[i]];
    const fromPrev = t.slot === LAST;
    let active = fromPrev ? tr.origSlot[i] : t.slot;
    if (!rows[active]) active = rows.findIndex((p) => p);
    if (active < 0) { rows[0] = emptyLike(takePattern(t)); active = 0; }
    setRows(t, rows, active);
    if (fromPrev) t.stopped = true;
  });
  d.scenes = [...d.scenes.slice(0, LAST), tr.hiddenScene];
}

/** Документ для сохранения: без строки PREV и с общими настройками нового проекта. */
export function docForSave(): Doc {
  if (!transition && !xfade) return doc;
  const d = clone(doc);
  if (transition) unshiftDoc(d, transition);
  if (xfade) Object.assign(d, clone(xfade.to));
  return d;
}

/**
 * Каждый кадр: закончить переход (строка PREV уступает место строке 8 нового проекта, кроссфейдер
 * исчезает), когда кроссфейдер доведён до NEW, ни одна дорожка не играет старый паттерн из PREV и ничего не ждёт
 * запуска из PREV. До этого старые паттерны остаются в PREV — их можно запускать снова.
 */
export function updateTransition() {
  const tr = transition;
  if (!tr) return;
  const busy = (xfade !== null && xfade.pos < 1)
    || doc.tracks.some((t, i) => (tr.real[i] && t.slot === LAST && !t.stopped && slotFilled(t, LAST)) || rt.queued[i] === LAST)
    || rt.scene?.row === LAST || rt.sceneQueued === LAST;
  if (busy) return;
  unshiftDoc(doc, tr);
  transition = null;
  xfade = null;
  resetUndo();
  clampView();
}

// ---------- Пресеты EQ ----------

/** Пресет EQ: имя, BYPASS и полосы. Библиотека общая для всех дорожек и проектов (в браузере). */
export interface EqPreset { name: string; eq: Eq }
const EQ_PRESET_STORE = 'jambo.eqPresets';
let eqPresetList: EqPreset[] = (() => {
  try {
    const list = JSON.parse(localStorage.getItem(EQ_PRESET_STORE) ?? '[]');
    return Array.isArray(list) ? list : [];
  } catch { return []; }
})();

function storeEqPresets() {
  try { localStorage.setItem(EQ_PRESET_STORE, JSON.stringify(eqPresetList)); } catch { /* хранилище недоступно */ }
}

export const eqPresets = () => eqPresetList;

/** Имя нового пресета EQ по умолчанию. */
export const nextEqPresetName = () => `EQ ${eqPresetList.length + 1}`;

/** Сохранить EQ канала, который показывает панель, в библиотеку. */
export function saveEqPreset(name: string) {
  eqPresetList.push({ name: name.trim().slice(0, 16) || nextEqPresetName(), eq: clone(eqTarget()) });
  storeEqPresets();
}

/** Загрузить пресет k в EQ канала, который показывает панель (отмена — UNDO). */
export function loadEqPreset(k: number) {
  const p = eqPresetList[k];
  if (!p) return;
  const eq = eqTarget();
  edit(() => {
    eq.on = p.eq.on;
    eq.bands = Array.from({ length: EQ_BANDS }, (_, i) => (p.eq.bands[i] ? clone(p.eq.bands[i]) : null));
  });
  ui.eqBand = -1;
}

export function renameEqPreset(k: number, name: string) {
  const p = eqPresetList[k];
  const n = name.trim().slice(0, 16);
  if (!p || !n) return;
  p.name = n;
  storeEqPresets();
}

export function deleteEqPreset(k: number) {
  if (!eqPresetList[k]) return;
  eqPresetList.splice(k, 1);
  storeEqPresets();
}
