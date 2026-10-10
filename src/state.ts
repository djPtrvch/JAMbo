// Единый модуль состояния приложения.
// doc — то, что сохраняется и отменяется через UNDO (позже сюда подключится звук).
// ui — текущие удержания кнопок/шагов и выбор. rt — данные реального времени (LFO, проигрывание).

import {
  FX_GRID, MAX_PAGES, MOD_GRID, STEPS_PER_PAGE, TRACK_COUNT, TRACK_GRID, OCTAVE_DEF, OCTAVE_MAX, OCTAVE_MIN,
  BPM_MAX, BPM_MIN, NOTE_NAMES, PROGRESSIONS, SCALES, fromNorm, toNorm, type ParamDef, type Slot,
} from './params';

export interface Step {
  on: boolean;
  /** Длина ноты в шагах. */
  len: number;
  /** Ноты шага (MIDI). Несколько нот — POLY. */
  notes: number[];
  /** P-lock: id параметра → значение. Может быть и на шаге без ноты. */
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
  /** Какие страницы играют: диапазон playFrom..playTo. */
  playFrom: number;
  playTo: number;
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
  trackClipboard: Track | null;
  trackMenu: number | null;
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
  /** Превью формы волны LFO в окне сэмпла. */
  lfoPreviewUntil: number;
  lfoPreview: 1 | 2;
}

export interface Runtime {
  /** Текущий шаг проигрывания каждой дорожки (−1 = стоп). */
  playPos: number[];
  /** До какого момента (performance.now) мигает дорожка. */
  flashUntil: number[];
  lfoPhase: [number, number][];
  lfoRandom: [number, number][];
  /** Ноты, которые сейчас звучат на дорожке (подсветка пианоролла). */
  noteFlash: { notes: number[]; until: number }[];
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

function newTrack(i: number): Track {
  return {
    name: `T${i + 1}`,
    params: { ...defaults(TRACK_GRID), ...defaults(MOD_GRID) },
    assigns: {},
    pages: [emptyPage()],
    length: STEPS_PER_PAGE,
    playFrom: 0,
    playTo: 0,
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
  trackClipboard: null,
  trackMenu: null,
  topMenu: null,
  metronome: false,
  octave: OCTAVE_DEF,
  chordMode: false,
  progression: 0,
  selNotes: [],
  pressedKeys: new Map(),
  lfoPreviewUntil: 0,
  lfoPreview: 1,
};

export const rt: Runtime = {
  playPos: Array(TRACK_COUNT).fill(-1),
  flashUntil: Array(TRACK_COUNT).fill(0),
  lfoPhase: Array.from({ length: TRACK_COUNT }, () => [0, 0] as [number, number]),
  lfoRandom: Array.from({ length: TRACK_COUNT }, () => [Math.random() * 2 - 1, Math.random() * 2 - 1] as [number, number]),
  noteFlash: Array.from({ length: TRACK_COUNT }, () => ({ notes: [], until: 0 })),
  playLocks: Array.from({ length: TRACK_COUNT }, () => ({ locks: {}, until: 0 })),
  beatUntil: 0,
  beatAccent: false,
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
  if (p.id.startsWith('lfo')) {
    ui.lfoPreview = p.id.startsWith('lfo1') ? 1 : 2;
    ui.lfoPreviewUntil = performance.now() + 1500;
  }
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

function turnOn(s: Step) {
  if (s.on) return;
  s.on = true;
  if (s.notes.length === 0) s.notes = trigNotes();
}

export function toggleStep(index: number) {
  edit(() => {
    const s = stepAt(selTrack(), index);
    if (!s) return;
    if (!s.on) { turnOn(s); return; }
    s.on = false;
    s.len = 1;
    s.notes = [];
    s.locks = {};
  });
}

/** Протягивание: триг на шаге index длиной len шагов. */
export function setNoteLength(index: number, len: number) {
  const s = stepAt(selTrack(), index);
  if (!s) return;
  turnOn(s);
  s.len = Math.max(1, len);
}

export const hasLocks = (s: Step) => Object.keys(s.locks).length > 0;


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
  const t = selTrack();
  edit(() => {
    t.playFrom = Math.max(0, Math.min(from, to));
    t.playTo = Math.min(t.pages.length - 1, Math.max(from, to));
  });
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

export function renameTrack(i: number, name: string) {
  const n = name.trim().slice(0, 12);
  if (n) edit(() => { doc.tracks[i].name = n; });
}

export function copyTrack(i: number) {
  ui.trackClipboard = JSON.parse(JSON.stringify(doc.tracks[i]));
}

/** Вставка: звук и паттерн из буфера, имя дорожки остаётся. */
export function pasteTrack(i: number) {
  const clip = ui.trackClipboard;
  if (!clip) return;
  edit(() => {
    const name = doc.tracks[i].name;
    doc.tracks[i] = { ...JSON.parse(JSON.stringify(clip)), name };
  });
  clampView();
}

/** Удаление: дорожка очищается до исходного состояния. */
export function deleteTrack(i: number) {
  edit(() => { doc.tracks[i] = newTrack(i); });
  clampView();
}

export function toggleMute(i: number) {
  edit(() => { doc.tracks[i].mute = !doc.tracks[i].mute; });
}

export function toggleSolo(i: number) {
  edit(() => { doc.tracks[i].solo = !doc.tracks[i].solo; });
}

const TRACK_DEFAULTS = { ...defaults(TRACK_GRID), ...defaults(MOD_GRID) };

/** Параметры дорожки изменены ручками (на всю дорожку, не p-lock) или назначен LFO. */
export function trackEdited(t: Track): boolean {
  if (Object.keys(t.assigns).length > 0) return true;
  return Object.entries(TRACK_DEFAULTS).some(([id, v]) => t.params[id] !== v);
}

/** Слышна ли дорожка с учётом mute/solo. */
export function audible(i: number): boolean {
  const anySolo = doc.tracks.some((t) => t.solo);
  const t = doc.tracks[i];
  return anySolo ? t.solo : !t.mute;
}

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
  return stepAt(selTrack(), idx)?.notes ?? [];
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
  if (ui.heldSteps.size > 0) {
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

/** Запись с REC: ноты на шаг index. merge — добавить к уже записанным на этом проходе. */
export function recordNotes(trackIndex: number, index: number, notes: number[], merge: boolean) {
  edit(() => {
    const s = stepAt(doc.tracks[trackIndex], index);
    if (!s) return;
    s.notes = merge && s.on ? [...new Set([...s.notes, ...notes])].sort((a, b) => a - b) : [...notes];
    s.on = true;
    s.len = 1;
  });
}
export function setRoot(v: number) { doc.root = ((Math.round(v) % NOTE_NAMES.length) + NOTE_NAMES.length) % NOTE_NAMES.length; }

