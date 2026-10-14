// Редактор сэмпла: удержание окна сэмпла открывает его на месте центра экрана (как EQ, справа
// остаётся измеритель уровня). Форма волны сэмпла выбранной дорожки (стерео — L и R), два маркера
// обрезки (тянутся за ручки внизу, можно оба сразу двумя пальцами, над пальцем — время) и маркеры нарезки
// (двойной тап — новый, флажок тянут, двойной тап по флажку — удалить; нота — по порядку (SETTINGS → SAMPLER),
// удержание флажка + клавиша — своя нота маркера).
// Палец по пустому месту: вверх-вниз — масштаб, влево-вправо — прокрутка (жёлтая полоса сверху).
// Внизу: имя, длина и выделение; LOAD (браузер библиотеки), SAVE (в библиотеку; WAV в «Файлы» —
// EXPORT в браузере), TRIM (оставить выделенное), NORMALIZE (пик −0.1 dBFS), MONO (среднее L и R), CLOSE.
// TRIM, NORMALIZE и MONO сразу ставят на дорожку отредактированную копию (в папке — на месте
// исходного сэмпла); UNDO в верхней панели возвращает исходный.

import { addEditedSample, audioInputs, captureActive, captureChunks, previewSample, previewing, sampleBuffer, samplePlayheads, startCapture, stopCapture, stopPreview, type CaptureSource } from '../audio/engine';
import { saveRecording } from '../stems';
import { makePopup, popupButton, type Popup } from './popup';
import { openBrowser } from './browser';
import { noteName, synthEngine } from '../params';
import { addRecordedSample, addSlice, clearTrackSample, beginGesture, deleteSlice, doc, endGesture, markNote, moveSlice, replaceSample, sampleName, setSliceNote, sliceMarks, toggleView, ui, type SliceMark } from '../state';
import { closeButton, h, setClass, setText } from './dom';
import { color } from './theme';

/** NORMALIZE: пик сэмпла, dBFS (чуть ниже 0 dB — метры не горят красным). */
const PEAK_DB = -0.1;

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let note: HTMLElement;
let nameText: HTMLElement;
let tip: HTMLElement;
let trimBtn: HTMLElement;
let normBtn: HTMLElement;
let monoBtn: HTMLElement;
let clearBtn: HTMLElement;
let saveBtn: HTMLElement;
let playBtn: HTMLElement;
const tools: HTMLElement[] = [];

/** Маркеры обрезки (доля длины 0..1) для сэмпла key. */
const mark = { key: '', a: 0, b: 1 };
let busy = false;
let W = 0;
let H = 0;
/** Огибающая для текущей ширины: min/max по пикселям, по каналам. */
let env: { key: string; w: number; a: number; span: number; min: Float32Array[]; max: Float32Array[] } | null = null;

/** Сэмпл выбранной дорожки (не синт) или ''. */
function currentKey(): string {
  if (ui.channel !== 'track') return '';
  const s = doc.tracks[ui.selectedTrack].sample;
  return s && synthEngine(s) === null ? s : '';
}

const fmtTime = (s: number) => (s < 10 ? `${s.toFixed(3)} s` : `${s.toFixed(2)} s`);

function tool(label: string, fn: () => void): HTMLElement {
  const el = h('div', 'btn eq-tool', label);
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    if (!el.classList.contains('disabled') && !busy) fn();
  });
  tools.push(el);
  return el;
}

/** Каналы выделения или всего сэмпла. */
function channels(buf: AudioBuffer, from = 0, to = buf.length): Float32Array[] {
  return Array.from({ length: buf.numberOfChannels }, (_, c) => buf.getChannelData(c).slice(from, to));
}

/** Применить правку: новый сэмпл из data — на дорожку. */
async function apply(key: string, data: Float32Array[], rate: number) {
  busy = true;
  try {
    const track = ui.selectedTrack;
    const next = await addEditedSample(key, data, rate);
    replaceSample(track, key, next);
    mark.key = next;
    mark.a = 0;
    mark.b = 1;
  } catch (e) {
    console.error('sample edit', e);
    window.alert('Could not edit the sample');
  } finally {
    busy = false;
  }
}

function trim() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  void apply(key, channels(buf, Math.floor(mark.a * buf.length), Math.ceil(mark.b * buf.length)), buf.sampleRate);
}

function normalize() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  const data = channels(buf);
  let peak = 0;
  for (const d of data) for (let i = 0; i < d.length; i++) peak = Math.max(peak, Math.abs(d[i]));
  if (peak <= 0) return;
  const g = Math.pow(10, PEAK_DB / 20) / peak;
  for (const d of data) for (let i = 0; i < d.length; i++) d[i] *= g;
  void apply(key, data, buf.sampleRate);
}

function mono() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf || buf.numberOfChannels < 2) return;
  const data = channels(buf);
  const out = new Float32Array(buf.length);
  for (const d of data) for (let i = 0; i < d.length; i++) out[i] += d[i] / data.length;
  void apply(key, [out], buf.sampleRate);
}

// ---------- Жесты: обрезка, маркеры нарезки, масштаб и прокрутка ----------

/** Видимая часть сэмпла (доли длины): начало и ширина окна. */
const view = { a: 0, span: 1 };
/** Верхняя полоса (над формой волны): сверху полоса прокрутки (при увеличении), под ней флажки маркеров нарезки. */
const TOP = 40;
const BAR_H = 3;
/** Флажок-пятиугольник: тело (с нотой) и острие вниз, к линии маркера. */
const FLAG_Y = 8;
const FLAG_H = 18;
/** Ручки маркеров обрезки — внизу. */
const HANDLE = 22;
/** Сдвиг пальца, после которого касание — жест (направление фиксируется), мм не тап. */
const SLOP = 10;
/** Вертикальный ход пальца на удвоение масштаба. */
const ZOOM_PX = 110;
const DOUBLE_MS = 350;

type Drag =
  | { kind: 'trim'; m: 'a' | 'b' }
  | { kind: 'slice'; idx: number; x0: number; y0: number; moved: boolean; assigned?: boolean }
  | { kind: 'nav'; x0: number; y0: number; a0: number; span0: number; f0: number; axis: '' | 'x' | 'y' };
const drags = new Map<number, Drag>();
/** Последний тап по пустому месту или флажку — для двойного тапа. */
let lastTap = { t: 0, x: 0, flag: -1 };

const toX = (f: number) => ((f - view.a) / view.span) * W;
const localX = (e: PointerEvent) => e.clientX - canvas.getBoundingClientRect().left;
const localY = (e: PointerEvent) => e.clientY - canvas.getBoundingClientRect().top;
const fracAt = (x: number) => Math.min(1, Math.max(0, view.a + (x / Math.max(1, W)) * view.span));
const clampView = () => {
  view.span = Math.min(1, view.span);
  view.a = Math.min(1 - view.span, Math.max(0, view.a));
};

/** Наименьшее окно — 256 отсчётов (или весь сэмпл). */
const minSpan = (buf: AudioBuffer) => Math.min(1, 256 / buf.length);

function marks(): SliceMark[] {
  return sliceMarks(doc.tracks[ui.selectedTrack], currentKey());
}

/** Тело флажка маркера — по центру линии. */
function flagRect(f: number, label: string): { x: number; w: number } {
  const w = Math.max(30, label.length * 8 + 10);
  return { x: toX(f) - w / 2, w };
}

/** Флажок маркера под пальцем или −1. */
function flagAt(x: number, y: number): number {
  if (y > TOP + 8) return -1;
  const m = marks();
  // Сверху — последний нарисованный (правее), зона попадания шире флажка на 6 px.
  for (let k = m.length - 1; k >= 0; k--) {
    const r = flagRect(m[k].at, noteName(markNote(m, k)));
    if (x >= r.x - 6 && x <= r.x + r.w + 6) return k;
  }
  return -1;
}

/** Ручка маркера обрезки под пальцем (внизу) или null. */
function trimAt(x: number, y: number): 'a' | 'b' | null {
  if (y < H - HANDLE - 10) return null;
  const used = new Set([...drags.values()].map((d) => (d.kind === 'trim' ? d.m : '')));
  const da = Math.abs(x - (toX(mark.a) + HANDLE / 2));
  const db = Math.abs(x - (toX(mark.b) - HANDLE / 2));
  const best: 'a' | 'b' = da <= db ? 'a' : 'b';
  if (Math.min(da, db) > HANDLE) return null;
  if (!used.has(best)) return best;
  const other = best === 'a' ? 'b' : 'a';
  return !used.has(other) && (other === 'a' ? da : db) <= HANDLE ? other : null;
}

function showTip(e: PointerEvent, text: string) {
  const r = plot.getBoundingClientRect();
  tip.style.left = `${Math.min(W - 50, Math.max(50, e.clientX - r.left))}px`;
  tip.style.top = `${Math.max(4, e.clientY - r.top - 70)}px`;
  setText(tip, text);
  setClass(tip, 'hidden', false);
}

function down(e: PointerEvent) {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  e.preventDefault();
  // Ложные касания: ладонь (большое пятно) не считается.
  if (e.pointerType === 'touch' && e.width > 60 && e.height > 60) return;
  const x = localX(e);
  const y = localY(e);
  const tm = trimAt(x, y);
  const fl = tm ? -1 : flagAt(x, y);
  let d: Drag;
  if (tm) d = { kind: 'trim', m: tm };
  else if (fl >= 0) d = { kind: 'slice', idx: fl, x0: x, y0: y, moved: false };
  else {
    // Масштаб и прокрутка — одним пальцем; второй палец по пустому месту ничего не делает.
    if ([...drags.values()].some((v) => v.kind === 'nav')) return;
    d = { kind: 'nav', x0: x, y0: y, a0: view.a, span0: view.span, f0: fracAt(x), axis: '' };
  }
  try { canvas.setPointerCapture(e.pointerId); } catch { /* указатель уже отпущен */ }
  drags.set(e.pointerId, d);
  if (d.kind === 'trim') move(e);
}

function move(e: PointerEvent) {
  const d = drags.get(e.pointerId);
  if (!d) return;
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  const x = localX(e);
  const y = localY(e);
  if (d.kind === 'trim') {
    // Между маркерами обрезки — не меньше 64 сэмплов.
    const gap = Math.min(0.5, 64 / buf.length);
    const f = fracAt(x);
    if (d.m === 'a') mark.a = Math.max(0, Math.min(f, mark.b - gap));
    else mark.b = Math.min(1, Math.max(f, mark.a + gap));
    showTip(e, `${d.m === 'a' ? 'START' : 'END'}\n${fmtTime((d.m === 'a' ? mark.a : mark.b) * buf.duration)}`);
    return;
  }
  if (d.kind === 'slice') {
    if (!d.moved) {
      if (Math.hypot(x - d.x0, y - d.y0) < SLOP) return;
      d.moved = true;
      beginGesture();
    }
    moveSlice(ui.selectedTrack, key, d.idx, fracAt(x), 32 / buf.length);
    const m = marks();
    showTip(e, `${noteName(markNote(m, d.idx))}\n${fmtTime((m[d.idx]?.at ?? 0) * buf.duration)}`);
    return;
  }
  // Направление жеста фиксируется после SLOP px: вверх-вниз — масштаб, влево-вправо — прокрутка.
  const dx = x - d.x0;
  const dy = y - d.y0;
  if (!d.axis) {
    if (Math.hypot(dx, dy) < SLOP) return;
    d.axis = Math.abs(dy) > Math.abs(dx) ? 'y' : 'x';
    // Отсчёт — от точки, где жест определился: без скачка на SLOP.
    d.x0 = x; d.y0 = y; d.a0 = view.a; d.span0 = view.span; d.f0 = fracAt(x);
    return;
  }
  if (d.axis === 'y') {
    // Палец вверх — крупнее; точка под пальцем остаётся на месте.
    view.span = Math.min(1, Math.max(minSpan(buf), d.span0 * Math.pow(2, (y - d.y0) / ZOOM_PX)));
    view.a = d.f0 - (d.x0 / Math.max(1, W)) * view.span;
  } else {
    view.a = d.a0 - (dx / Math.max(1, W)) * d.span0;
  }
  clampView();
}

/**
 * Удержание маркера + клавиша (пианоролл, MIDI): маркеру назначается нота. true — нота ушла маркеру
 * (маркер держат, не двигая), иначе — обычная нота.
 */
/** Отказ в назначении ноты (она у другого маркера): флажок красный до until. */
let refused = { idx: -1, until: 0 };

export function assignHeldSlice(note: number): boolean {
  if (!ui.sampleView) return false;
  const key = currentKey();
  for (const d of drags.values()) {
    if (d.kind !== 'slice' || d.moved || !key) continue;
    d.assigned = true;
    // Нота уже у другого маркера — не назначается: флажок коротко вспыхивает красным.
    if (!setSliceNote(ui.selectedTrack, key, d.idx, note)) refused = { idx: d.idx, until: performance.now() + 500 };
    return true;
  }
  return false;
}

function up(e: PointerEvent) {
  const d = drags.get(e.pointerId);
  drags.delete(e.pointerId);
  if (![...drags.values()].some((v) => v.kind !== 'nav')) setClass(tip, 'hidden', true);
  if (!d || e.type === 'pointercancel') { if (d?.kind === 'slice' && d.moved) endGesture(); return; }
  if (d.kind === 'slice' && d.moved) { endGesture(); return; }
  if (d.kind === 'slice' && d.assigned) return;
  const key = currentKey();
  const x = localX(e);
  const now = performance.now();
  // Тап (без движения): одиночный ничего не делает, двойной — маркер (по пустому месту) или удаление (по флажку).
  const tap = d.kind === 'slice' ? !d.moved : d.kind === 'nav' && !d.axis;
  if (!tap || !key) return;
  const flag = d.kind === 'slice' ? d.idx : -1;
  const dbl = now - lastTap.t < DOUBLE_MS && Math.abs(x - lastTap.x) < 24 && lastTap.flag === flag;
  if (!dbl) { lastTap = { t: now, x, flag }; return; }
  lastTap = { t: 0, x: 0, flag: -1 };
  if (flag >= 0) deleteSlice(ui.selectedTrack, key, flag);
  else addSlice(ui.selectedTrack, key, fracAt(x));
}

// ---------- Запись сэмпла (REC) ----------

/** Наибольшая длина записи, с. */
const REC_MAX_S = 60;
let recBtn: HTMLElement;
let recMenu: Popup;
/** Идёт запись: на какую дорожку, имя источника, начало (performance.now). */
let rec: { track: number; name: string; start: number } | null = null;

/** Отсчётов на точку формы волны во время записи. */
const REC_BLOCK = 128;
/** Пики пришедших кусков записи (по каналам, по блокам REC_BLOCK): форма волны во время записи. */
const recPeaks = { n: 0, lo: [[], []] as number[][], hi: [[], []] as number[][] };

const recTime = (ms: number) => { const s = Math.floor(ms / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

async function beginRec(src: CaptureSource, name: string) {
  recMenu.close();
  if (rec || captureActive()) return;
  const track = ui.selectedTrack;
  rec = { track, name, start: performance.now() };
  recPeaks.n = 0;
  recPeaks.lo = [[], []];
  recPeaks.hi = [[], []];
  if (!(await startCapture(src))) {
    rec = null;
    window.alert(src.kind === 'input' ? 'No access to the audio input' : 'Could not start recording');
    return;
  }
  const r = rec;
  r.start = performance.now();
  // Не дольше 60 с — и тогда, когда окно редактора закрыли.
  window.setTimeout(() => { if (rec === r) void endRec(); }, REC_MAX_S * 1000);
}

async function endRec() {
  const r = rec;
  if (!r) return;
  rec = null;
  busy = true;
  try {
    const d = new Date();
    const two = (x: number) => String(x).padStart(2, '0');
    const name = `${r.name} ${two(d.getHours())}-${two(d.getMinutes())}-${two(d.getSeconds())}`;
    const key = await stopCapture(name);
    // Записанное — на дорожку (в её папку) и копия в RECORDINGS библиотеки; дальше его можно править здесь же.
    if (key) { addRecordedSample(r.track, key, name); saveRecording(key, name); }
  } finally {
    busy = false;
  }
}

/** Меню источника записи: входы (микрофон iPad, аудиоинтерфейс), дорожки (после своей обработки), мастер. */
async function openRecMenu() {
  recMenu ??= makePopup('rec-src-menu');
  const box = recMenu.box;
  box.replaceChildren(h('div', 'menu-head', 'RECORD FROM'));
  const inputs = await audioInputs();
  box.append(h('div', 'source-title', 'INPUT'));
  const list = inputs.length ? inputs : [{ id: '', name: 'iPad microphone' }];
  for (const d of list) box.append(popupButton(d.name, () => void beginRec({ kind: 'input', id: d.id }, d.name.split(' ')[0].toUpperCase() === 'IPAD' ? 'MIC' : d.name)));
  box.append(h('div', 'source-title', 'TRACK'));
  const grid = h('div', 'rec-src-grid');
  doc.tracks.forEach((t, i) => grid.append(popupButton(t.name || String(i + 1), () => void beginRec({ kind: 'track', i }, t.name || String(i + 1)))));
  box.append(grid, h('div', 'source-title', 'MASTER'), popupButton('MASTER', () => void beginRec({ kind: 'master' }, 'MASTER')));
  box.append(h('div', 'settings-note', `Recording stops by tapping REC again or after ${REC_MAX_S} s. Tracks are recorded after their own processing, the master after the master effects.`));
  recMenu.openAt(recBtn, 320);
}

// ---------- Построение ----------

export function buildSampleEditor(): HTMLElement {
  panel = h('div', 'eq-panel sedit hidden');
  plot = h('div', 'eq-plot');
  canvas = document.createElement('canvas');
  canvas.className = 'eq-canvas';
  note = h('div', 'sedit-note hidden');
  tip = h('div', 'eq-tip hidden');
  plot.append(canvas, note, tip);
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);

  const bar = h('div', 'eq-bar');
  nameText = h('div', 'eq-name sedit-name');
  // LOAD — браузер библиотеки (сэмпл на дорожку; файлы с iPad и iCloud — IMPORT там).
  const load = tool('LOAD', () => openBrowser({ kind: 'load', steps: [] }));
  trimBtn = tool('TRIM', trim);
  normBtn = tool('NORMALIZE', normalize);
  monoBtn = tool('MONO', mono);
  // SAVE — сэмпл в библиотеку (папку выбирают в браузере); WAV в «Файлы» — EXPORT в браузере.
  saveBtn = tool('SAVE', () => openBrowser({ kind: 'save-sample', key: currentKey() }));
  // ▶ — прослушать выделение (без выделения — весь сэмпл) в исходной высоте; повторный тап — стоп.
  playBtn = tool('', () => {
    const key = currentKey();
    if (!key) return;
    if (previewing()) { stopPreview(); return; }
    const sel = mark.key === key ? mark : { a: 0, b: 1 };
    void previewSample(key, sel.a, sel.b);
  });
  playBtn.classList.add('sq');
  playBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24"><path d="M7 4.5v15l13-7.5z" fill="currentColor"/></svg>';
  const close = closeButton(() => toggleView('sample'));
  // LOAD и SAVE рядом, за ними правки.
  // REC — запись сэмпла: тап — меню источника (вход, дорожка, мастер), во время записи — стоп (не больше 60 с).
  recBtn = h('div', 'btn eq-tool sedit-rec');
  recBtn.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    if (busy) return;
    if (rec) { void endRec(); return; }
    if (ui.channel !== 'track') return;
    void openRecMenu();
  });
  // CLEAR — убрать сэмпл с дорожки и из её папки (отмена — UNDO).
  clearBtn = tool('CLEAR', () => clearTrackSample(ui.selectedTrack));
  bar.append(nameText, h('div', 'sedit-space'), recBtn, playBtn, load, saveBtn, trimBtn, normBtn, monoBtn, clearBtn, close);
  // Кнопки — над формой волны.
  panel.append(bar, plot);
  return panel;
}

/** Удержание окна сэмпла: открыть редактор. */
export function openSampleEditor() {
  if (!ui.sampleView) toggleView('sample');
}

// ---------- Отрисовка (каждый кадр, пока открыт) ----------

function envelope(key: string, buf: AudioBuffer, w: number) {
  if (env && env.key === key && env.w === w && env.a === view.a && env.span === view.span) return env;
  const chans = Math.min(2, buf.numberOfChannels);
  const min = Array.from({ length: chans }, () => new Float32Array(w));
  const max = Array.from({ length: chans }, () => new Float32Array(w));
  const n = buf.length;
  for (let c = 0; c < chans; c++) {
    const d = buf.getChannelData(c);
    for (let x = 0; x < w; x++) {
      // Окно view: при сильном увеличении на пиксель меньше отсчёта — берётся ближайший.
      const i0 = Math.min(n - 1, Math.floor((view.a + (x / w) * view.span) * n));
      const i1 = Math.min(n, Math.max(i0 + 1, Math.floor((view.a + ((x + 1) / w) * view.span) * n)));
      let lo = 0;
      let hi = 0;
      for (let i = i0; i < i1; i++) { const v = d[i]; if (v < lo) lo = v; if (v > hi) hi = v; }
      min[c][x] = lo;
      max[c][x] = hi;
    }
  }
  env = { key, w, a: view.a, span: view.span, min, max };
  return env;
}

/**
 * Форма волны во время записи: пики кусков (по 4096 кадров) по мере прихода; по ширине — записанное время
 * (не меньше 5 с), L сверху, R снизу, справа — красная линия текущего места.
 */
function drawRecording(g: CanvasRenderingContext2D) {
  const ch = captureChunks();
  if (!ch) return;
  // Пики — по блокам REC_BLOCK отсчётов (куски записи по 4096 — слишком крупно: форма была бы квадратами).
  for (; recPeaks.n < ch.L.length; recPeaks.n++) {
    [ch.L[recPeaks.n], ch.R[recPeaks.n]].forEach((d, c) => {
      for (let i0 = 0; i0 < d.length; i0 += REC_BLOCK) {
        let lo = 0;
        let hi = 0;
        for (let i = i0; i < Math.min(d.length, i0 + REC_BLOCK); i++) { const v = d[i]; if (v < lo) lo = v; if (v > hi) hi = v; }
        recPeaks.lo[c].push(lo);
        recPeaks.hi[c].push(hi);
      }
    });
  }
  const n = recPeaks.lo[0].length;
  const span = Math.max(n, Math.ceil((5 * 48000) / REC_BLOCK));
  const lh = (H - TOP) / 2;
  for (let c = 0; c < 2; c++) {
    const mid = TOP + lh * c + lh / 2;
    const amp = lh / 2 - 6;
    g.fillStyle = color('--line');
    g.fillRect(0, mid, W, 1);
    g.fillStyle = color('--ink');
    for (let x = 0; x < W; x++) {
      const k0 = Math.floor((x / W) * span);
      const k1 = Math.max(k0 + 1, Math.floor(((x + 1) / W) * span));
      if (k0 >= n) break;
      let lo = 0;
      let hi = 0;
      for (let k = k0; k < Math.min(k1, n); k++) { lo = Math.min(lo, recPeaks.lo[c][k]); hi = Math.max(hi, recPeaks.hi[c][k]); }
      g.fillRect(x, mid - hi * amp, 1, Math.max(1, (hi - lo) * amp));
    }
  }
  g.fillStyle = color('--rec');
  g.fillRect(Math.min(W - 2, (n / span) * W), TOP, 2, H - TOP);
}

export function renderSampleEditor() {
  setClass(panel, 'hidden', !ui.sampleView);
  if (!ui.sampleView) return;
  const key = currentKey();
  const buf = key ? sampleBuffer(key) : null;
  if (key !== mark.key) { mark.key = key; mark.a = 0; mark.b = 1; drags.clear(); view.a = 0; view.span = 1; }

  const full = mark.a <= 0 && mark.b >= 1;
  setClass(trimBtn, 'disabled', !buf || full);
  setClass(normBtn, 'disabled', !buf);
  setClass(monoBtn, 'disabled', !buf || buf.numberOfChannels < 2);
  setClass(saveBtn, 'disabled', !buf);
  for (const t of tools) setClass(t, 'busy', busy);

  // Запись: на кнопке время, в 60 с — стоп.
  const recMs = rec ? performance.now() - rec.start : 0;
  if (rec && recMs >= REC_MAX_S * 1000) void endRec();
  setClass(recBtn, 'on', !!rec);
  setClass(recBtn, 'disabled', !rec && ui.channel !== 'track');
  const recHtml = rec ? `<span class="rec-sq"></span>${recTime(recMs)}` : '<span class="rec-dot"></span>REC';
  if (recBtn.innerHTML !== recHtml) recBtn.innerHTML = recHtml;
  setClass(note, 'rec', !!rec);
  setClass(clearBtn, 'disabled', !buf || !!rec);
  setClass(note, 'hidden', !!buf || !!rec);
  setText(note, ui.channel !== 'track' ? 'Select a track to edit its sample.'
    : key ? 'Loading…' : 'No sample on this track — LOAD a file or REC.');
  if (buf) {
    const sel = (mark.b - mark.a) * buf.duration;
    setText(nameText, `${sampleName(key)}\n${full ? fmtTime(buf.duration) : `${fmtTime(sel)} of ${fmtTime(buf.duration)}`}${buf.numberOfChannels > 1 ? ' · ST' : ' · M'}`);
  } else setText(nameText, 'SAMPLE\nEDITOR');
  if (rec) setText(nameText, `REC · ${rec.name}\n${recTime(recMs)} / 1:00`);

  const dpr = window.devicePixelRatio || 1;
  W = plot.clientWidth;
  H = plot.clientHeight;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const g = canvas.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, W, H);
  if (rec) { drawRecording(g); return; }
  if (!buf) return;

  // Верхняя полоса — под флажки маркеров и полосу прокрутки; форма волны — ниже.
  g.fillStyle = color('--meter-track');
  g.globalAlpha = 0.35;
  g.fillRect(0, 0, W, TOP);
  g.globalAlpha = 1;
  // Форма волны: каналы полосами (L сверху, R снизу), центр — линия.
  const e = envelope(key, buf, Math.max(1, Math.round(W)));
  const lanes = e.min.length;
  const lh = (H - TOP) / lanes;
  for (let c = 0; c < lanes; c++) {
    const mid = TOP + lh * c + lh / 2;
    const amp = lh / 2 - 6;
    g.fillStyle = color('--ink');
    for (let x = 0; x < e.w; x++) {
      const y0 = mid - e.max[c][x] * amp;
      const y1 = mid - e.min[c][x] * amp;
      g.fillRect(x, y0, 1, Math.max(1, y1 - y0));
    }
    g.fillStyle = color('--line');
    g.fillRect(0, mid, W, 1);
    if (lanes > 1) {
      g.fillStyle = color('--dim');
      g.font = '11px -apple-system, system-ui, sans-serif';
      g.fillText(c ? 'R' : 'L', 8, TOP + lh * c + 16);
    }
  }
  // Отрезаемое — затемнено, маркеры обрезки — жёлтые линии с ручками внизу.
  const xa = toX(mark.a);
  const xb = toX(mark.b);
  g.fillStyle = color('--scrim');
  if (xa > 0) g.fillRect(0, TOP, Math.min(W, xa), H - TOP);
  if (xb < W) g.fillRect(Math.max(0, xb), TOP, W - Math.max(0, xb), H - TOP);
  g.fillStyle = color('--accent');
  for (const [x, right] of [[xa, false], [xb, true]] as [number, boolean][]) {
    if (x < -HANDLE || x > W + HANDLE) continue;
    g.fillRect(Math.round(x) - 1, TOP, 2, H - TOP);
    g.fillRect(right ? x - HANDLE : x, H - HANDLE, HANDLE, HANDLE);
  }
  // Маркеры нарезки: линия и флажок с нотой (по SETTINGS → SAMPLER: хроматически или по гамме); тянут — жёлтый.
  const held = new Set([...drags.values()].map((d) => (d.kind === 'slice' ? d.idx : -1)));
  g.font = '600 12px -apple-system, system-ui, sans-serif';
  g.textBaseline = 'middle';
  const all = marks();
  all.forEach(({ at: f }, k) => {
    const x = toX(f);
    if (x < -60 || x > W + 60) return;
    const label = noteName(markNote(all, k));
    const r = flagRect(f, label);
    const c = refused.idx === k && performance.now() < refused.until ? color('--rec') : held.has(k) ? color('--accent') : color('--ink');
    g.fillStyle = c;
    // Линия от острия флажка до низа; флажок — пятиугольник острием вниз, нота внутри.
    const tip = TOP - 2;
    g.fillRect(Math.round(x), tip, 1, H - tip);
    g.beginPath();
    g.moveTo(r.x, FLAG_Y);
    g.lineTo(r.x + r.w, FLAG_Y);
    g.lineTo(r.x + r.w, FLAG_Y + FLAG_H);
    g.lineTo(x + 0.5, tip);
    g.lineTo(r.x, FLAG_Y + FLAG_H);
    g.closePath();
    g.fill();
    g.fillStyle = color('--bg');
    g.textAlign = 'center';
    g.fillText(label, x + 0.5, FLAG_Y + FLAG_H / 2 + 1);
    g.textAlign = 'left';
  });
  g.textBaseline = 'alphabetic';
  // Полоса воспроизведения: звучащие голоса сэмпла — тонкие жёлтые линии.
  g.fillStyle = color('--accent');
  for (const { f, a } of samplePlayheads(ui.selectedTrack, key)) {
    const x = toX(f);
    g.globalAlpha = a;
    if (x >= 0 && x <= W) g.fillRect(Math.round(x) - 1, TOP, 2, H - TOP);
  }
  g.globalAlpha = 1;
  // Полоса прокрутки (при увеличении): видимая часть сэмпла — жёлтым.
  if (view.span < 1) {
    g.fillStyle = color('--meter-track');
    g.fillRect(0, 1, W, BAR_H);
    g.fillStyle = color('--accent');
    g.fillRect(view.a * W, 1, Math.max(6, view.span * W), BAR_H);
  }
}
