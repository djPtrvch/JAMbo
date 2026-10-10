// Единый модуль состояния приложения.
// doc — то, что сохраняется и отменяется через UNDO (позже сюда подключится звук).
// ui — текущие удержания кнопок/шагов и выбор. rt — данные реального времени (LFO, проигрывание).

import {
  FX_GRID, MAX_PAGES, MOD_GRID, STEPS_PER_PAGE, TRACK_COUNT, TRACK_GRID,
  BPM_MAX, BPM_MIN, NOTE_NAMES, SCALES, fromNorm, toNorm, type ParamDef, type Slot,
} from './params';

export interface Step {
  on: boolean;
  /** Длина ноты в шагах. */
  len: number;
  /** P-lock: id параметра → значение. */
  locks: Record<string, number>;
}

export interface LfoAssign {
  lfo: 1 | 2;
  /** Степень воздействия −1..+1 (в долях хода ручки). */
  amount: number;
}

export interface Track {
  name: string;
  /** Параметры дорожки и её LFO (lfo1.*, lfo2.*). */
  params: Record<string, number>;
  assigns: Record<string, LfoAssign>;
  pages: Step[][];
  /** Длина паттерна в шагах (1..pages*16). */
  length: number;
  mute: boolean;
  solo: boolean;
}

export interface Doc {
  bpm: number;
  scale: number;
  root: number;
  tracks: Track[];
  fx: Record<string, number>;
}

export type GridMode = 'track' | 'fx' | 'mod';
export type HoldButton = 'lfo1' | 'lfo2' | 'track' | 'fx' | 'mod';

export interface HeldStep {
  index: number;
  /** На удержании уже что-то сделали (p-lock, длина) — триг на отпускании не трогаем. */
  used: boolean;
}

export interface Ui {
  selectedTrack: number;
  viewPage: number;
  held: Record<HoldButton, boolean>;
  /** Порядок нажатия FX/MOD: побеждает нажатая последней. */
  modeOrder: GridMode[];
  /** Последняя нажатая LFO-кнопка (если удерживаются обе). */
  lastLfo: 1 | 2;
  heldSteps: Map<number, HeldStep>;
  playing: boolean;
  rec: boolean;
  clipboard: Step[] | null;
  pageMenu: number | null;
}

export interface Runtime {
  /** Текущий шаг проигрывания каждой дорожки (−1 = стоп). */
  playPos: number[];
  /** До какого момента (performance.now) мигает дорожка. */
  flashUntil: number[];
  lfoPhase: [number, number][];
  lfoRandom: [number, number][];
}

// ---------- Создание ----------

function defaults(grid: Slot[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const p of grid) if (p) out[p.id] = p.def;
  return out;
}

export function emptyPage(): Step[] {
  return Array.from({ length: STEPS_PER_PAGE }, () => ({ on: false, len: 1, locks: {} }));
}

function newTrack(i: number): Track {
  return {
    name: `T${i + 1}`,
    params: { ...defaults(TRACK_GRID), ...defaults(MOD_GRID) },
    assigns: {},
    pages: [emptyPage()],
    length: STEPS_PER_PAGE,
    mute: false,
    solo: false,
  };
}

export const doc: Doc = {
  bpm: 120,
  scale: 0,
  root: 0,
  tracks: Array.from({ length: TRACK_COUNT }, (_, i) => newTrack(i)),
  fx: defaults(FX_GRID),
};

export const ui: Ui = {
  selectedTrack: 0,
  viewPage: 0,
  held: { lfo1: false, lfo2: false, track: false, fx: false, mod: false },
  modeOrder: [],
  lastLfo: 1,
  heldSteps: new Map(),
  playing: false,
  rec: false,
  clipboard: null,
  pageMenu: null,
};

export const rt: Runtime = {
  playPos: Array(TRACK_COUNT).fill(-1),
  flashUntil: Array(TRACK_COUNT).fill(0),
  lfoPhase: Array.from({ length: TRACK_COUNT }, () => [0, 0] as [number, number]),
  lfoRandom: Array.from({ length: TRACK_COUNT }, () => [Math.random() * 2 - 1, Math.random() * 2 - 1] as [number, number]),
};

// ---------- UNDO ----------

const undoStack: string[] = [];
const UNDO_LIMIT = 200;
let gestureDepth = 0;
let gestureSnapshot = '';

const snapshot = () => JSON.stringify(doc);

function pushUndo(snap: string) {
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
  Object.assign(doc, JSON.parse(snap) as Doc);
  clampView();
}

export const canUndo = () => undoStack.length > 0;

// ---------- Режимы ----------

export function gridMode(): GridMode {
  for (let i = ui.modeOrder.length - 1; i >= 0; i--) if (ui.held[ui.modeOrder[i]]) return ui.modeOrder[i];
  return 'track';
}

export function gridFor(mode: GridMode): Slot[] {
  return mode === 'fx' ? FX_GRID : mode === 'mod' ? MOD_GRID : TRACK_GRID;
}

export function setHeld(btn: HoldButton, down: boolean) {
  ui.held[btn] = down;
  if (down && (btn === 'fx' || btn === 'mod')) ui.modeOrder = [...ui.modeOrder.filter((m) => m !== btn), btn];
  if (down && btn === 'lfo1') ui.lastLfo = 1;
  if (down && btn === 'lfo2') ui.lastLfo = 2;
}

/** Активная LFO-кнопка, если удерживается. */
export function heldLfo(): 1 | 2 | null {
  if (ui.held.lfo1 && ui.held.lfo2) return ui.lastLfo;
  return ui.held.lfo1 ? 1 : ui.held.lfo2 ? 2 : null;
}

/** Дорожки, к которым применяется действие: выбранная или все (TRACK). */
function targetTracks(): Track[] {
  return ui.held.track ? doc.tracks : [doc.tracks[ui.selectedTrack]];
}

export const selTrack = () => doc.tracks[ui.selectedTrack];

// ---------- Параметры ----------

export function paramValue(mode: GridMode, p: ParamDef, track = selTrack()): number {
  return mode === 'fx' ? doc.fx[p.id] : track.params[p.id];
}

export function setParamNorm(mode: GridMode, p: ParamDef, norm: number) {
  const v = fromNorm(p, norm);
  if (mode === 'fx') doc.fx[p.id] = v;
  else for (const t of targetTracks()) t.params[p.id] = v;
}

// ---------- LFO ----------

function lfoShape(wave: number, phase: number, rnd: number): number {
  switch (wave) {
    case 0: return Math.sin(phase * 2 * Math.PI);
    case 1: return phase < 0.25 ? phase * 4 : phase < 0.75 ? 2 - phase * 4 : phase * 4 - 4;
    case 2: return phase * 2 - 1;
    case 3: return phase < 0.5 ? 1 : -1;
    default: return rnd;
  }
}

/** Выход LFO дорожки −1..+1 с учётом Depth и Invert. */
export function lfoOut(trackIndex: number, n: 1 | 2): number {
  const t = doc.tracks[trackIndex];
  const pre = `lfo${n}.`;
  const shape = lfoShape(t.params[pre + 'wave'], rt.lfoPhase[trackIndex][n - 1], rt.lfoRandom[trackIndex][n - 1]);
  const depth = t.params[pre + 'depth'] / 100;
  const polarity = 1 - 2 * t.params[pre + 'invert'];
  return shape * depth * polarity;
}

/** Продвинуть фазы всех LFO (LFO работают всегда, независимо от PLAY). */
export function advanceLfos(dt: number) {
  doc.tracks.forEach((t, i) => {
    for (const n of [1, 2] as const) {
      let ph = rt.lfoPhase[i][n - 1] + dt * t.params[`lfo${n}.speed`];
      if (ph >= 1) {
        ph %= 1;
        rt.lfoRandom[i][n - 1] = Math.random() * 2 - 1;
      }
      rt.lfoPhase[i][n - 1] = ph;
    }
  });
}

/** Значение ручки дорожки в 0..1 с учётом LFO (base — базовое или p-lock значение). */
export function modulatedNorm(trackIndex: number, p: ParamDef, base: number): number {
  const a = doc.tracks[trackIndex].assigns[p.id];
  const n = toNorm(p, base);
  if (!a) return n;
  return Math.min(1, Math.max(0, n + a.amount * lfoOut(trackIndex, a.lfo)));
}

export function setLfoAmount(p: ParamDef, lfo: 1 | 2, amount: number) {
  amount = Math.min(1, Math.max(-1, amount));
  for (const t of targetTracks()) t.assigns[p.id] = { lfo, amount };
}

export function clearLfoAssign(p: ParamDef, lfo: 1 | 2) {
  edit(() => {
    for (const t of targetTracks()) if (t.assigns[p.id]?.lfo === lfo) delete t.assigns[p.id];
  });
}

// ---------- Шаги и p-lock ----------

export function stepAt(t: Track, index: number): Step | undefined {
  return t.pages[Math.floor(index / STEPS_PER_PAGE)]?.[index % STEPS_PER_PAGE];
}

export function toggleStep(index: number) {
  edit(() => {
    const s = stepAt(selTrack(), index);
    if (!s) return;
    s.on = !s.on;
    if (!s.on) { s.len = 1; s.locks = {}; }
  });
}

/** Протягивание: триг на шаге index длиной len шагов. */
export function setNoteLength(index: number, len: number) {
  const s = stepAt(selTrack(), index);
  if (!s) return;
  s.on = true;
  s.len = Math.max(1, len);
}

export function setPatternLength(lastIndex: number) {
  edit(() => {
    const t = selTrack();
    t.length = Math.min(t.pages.length * STEPS_PER_PAGE, Math.max(1, lastIndex + 1));
  });
}

export function lockValue(index: number, p: ParamDef): number | undefined {
  return stepAt(selTrack(), index)?.locks[p.id];
}

export function setLockNorm(p: ParamDef, norm: number) {
  const v = fromNorm(p, norm);
  for (const h of ui.heldSteps.values()) {
    const s = stepAt(selTrack(), h.index);
    if (!s) continue;
    s.on = true;
    s.locks[p.id] = v;
    h.used = true;
  }
}

export function clearLock(p: ParamDef) {
  edit(() => {
    for (const h of ui.heldSteps.values()) {
      const s = stepAt(selTrack(), h.index);
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
  const t = selTrack();
  if (ui.viewPage >= t.pages.length) ui.viewPage = t.pages.length - 1;
}

export function selectTrack(i: number) {
  ui.selectedTrack = i;
  ui.heldSteps.clear();
  clampView();
}

/** Сохранить длину «на все страницы», если она была полной. */
function changePages(t: Track, fn: () => void) {
  const full = t.length === t.pages.length * STEPS_PER_PAGE;
  fn();
  const max = t.pages.length * STEPS_PER_PAGE;
  t.length = full ? max : Math.min(t.length, max);
}

const clonePage = (p: Step[]): Step[] => JSON.parse(JSON.stringify(p));

export function addPage() {
  const t = selTrack();
  if (t.pages.length >= MAX_PAGES) return;
  edit(() => changePages(t, () => t.pages.push(emptyPage())));
  ui.viewPage = t.pages.length - 1;
}

export function duplicatePage(i: number) {
  const t = selTrack();
  if (t.pages.length >= MAX_PAGES) return;
  edit(() => changePages(t, () => t.pages.splice(i + 1, 0, clonePage(t.pages[i]))));
  ui.viewPage = i + 1;
}

export function copyPage(i: number) {
  ui.clipboard = clonePage(selTrack().pages[i]);
}

export function pastePage(i: number) {
  const clip = ui.clipboard;
  if (!clip) return;
  edit(() => { selTrack().pages[i] = clonePage(clip); });
}

export function deletePage(i: number) {
  const t = selTrack();
  if (t.pages.length <= 1) return;
  edit(() => changePages(t, () => t.pages.splice(i, 1)));
  clampView();
}

// ---------- Дорожки и верхняя панель ----------

export function toggleMute(i: number) {
  edit(() => { doc.tracks[i].mute = !doc.tracks[i].mute; });
}

export function toggleSolo(i: number) {
  edit(() => { doc.tracks[i].solo = !doc.tracks[i].solo; });
}

/** Слышна ли дорожка с учётом mute/solo. */
export function audible(i: number): boolean {
  const anySolo = doc.tracks.some((t) => t.solo);
  const t = doc.tracks[i];
  return anySolo ? t.solo : !t.mute;
}

export function setBpm(v: number) { doc.bpm = Math.round(Math.min(BPM_MAX, Math.max(BPM_MIN, v))); }
export function setScale(v: number) { doc.scale = ((Math.round(v) % SCALES.length) + SCALES.length) % SCALES.length; }
export function setRoot(v: number) { doc.root = ((Math.round(v) % NOTE_NAMES.length) + NOTE_NAMES.length) % NOTE_NAMES.length; }

