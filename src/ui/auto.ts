// Окно автоматизации (кнопка AUTO): на месте центра экрана, как EQ и редактор сэмпла.
// Сверху: кнопка выбора (шириной с MIX: дорожка и параметр; тап — список автоматизаций паттерна),
// «+» (выбор ручки), DELETE, LINE | SPLINE (режим кривой), карандаш (свободное рисование), SIMPLIFY,
// SNAP по X и Y, CLEAR, страницы, закрытие. Поле — во всю ширину над шагами секвенсора.
// Запись — основной кнопкой REC при игре: поворот ручки пишет её автоматизацию.
// Поле: 16 ячеек шагов (страницы паттерна листаются, при игре — за позицией), деления 1/2 и 1/4 шага,
// линии 0/25/50/75/100 %, линия позиции. Тап по пустому месту — точка; тап по точке — выбор; удержание
// и перетаскивание — двигает; двойной тап — удаление; удержание без движения — тип сегмента.

import { AUTO_PARAMS, AUTO_MAX_POINTS, evalAuto, insertPoint, isStepped, segType, type AutoPoint, type SegType } from '../automation';
import { fromNorm, STEPS_PER_PAGE, synthEngine, synthGrid, TRACK_GRID, type ParamDef } from '../params';
import {
  addAuto, AUTO_SNAP_X, autoSnapStep, insertTake, autoDef, autoList, autoPos, autoRecPieces, autoSpan, beginGesture, canResimplify, clearAuto, curAuto, deleteAuto,
  editAuto, endGesture, selTrack, setAutoCurve, setAutoSimplify, toggleView, ui,
  pageLen,
} from '../state';
import { DOUBLE_TAP_MS, h, setClass, setText } from './dom';
import { makePopup, popupButton, type Popup } from './popup';
import { color } from './theme';

/** Поле рисования: отступ сверху и снизу, чтобы точки на 0 и 100 % были видны целиком. */
const PAD = 14;
/** Зона попадания в точку (радиус, px) — 44 pt в поперечнике. */
const HIT = 22;
const HOLD_MS = 450;
const MOVE_PX = 6;
/** Привязка по X, шаги: выкл., 1/16 (шаг), 1/4 (4 шага), 1 (такт — 16 шагов). */
const SNAP_X_NAMES = ['OFF', '1/16', '1/4', '1'];
const SNAP_Y = [0, 0.1, 0.25];
const SNAP_Y_NAMES = ['OFF', '10%', '25%'];

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let note: HTMLElement;
let tip: HTMLElement;
let nameText: HTMLElement;
let plusBtn: HTMLElement;
let delBtn: HTMLElement;
let snapXBtn: HTMLElement;
let snapYBtn: HTMLElement;
let simpBox: HTMLElement;
let simpFill: HTMLElement;
let simpText: HTMLElement;
const toolBtns: Record<string, HTMLElement> = {};
const editBtns: HTMLElement[] = [];
let pickMenu: Popup;
let pointMenu: Popup;

let W = 0;
let H = 0;
/** Страница поля (16 шагов); при игре — страница позиции. */
/** Страницы, показанные в поле (выбор квадратиками; на игру не влияет); при игре — за позицией. */
let viewFrom = 0;
let viewTo = 0;
/** Выбранная точка (индекс в открытой автоматизации; −1 — нет). */
let sel = -1;
let listMenu: Popup;

interface Drag {
  id: number;
  x0: number;
  y0: number;
  moved: boolean;
  /** Точка под пальцем (индекс) или свободное рисование (FREE). */
  point: number;
  free: AutoPoint[] | null;
  timer: number;
  gesture: boolean;
}
let drag: Drag | null = null;
let lastTap = { point: -1, t: -1e9 };

// ---------- Координаты ----------

const pageX0 = () => viewFrom * STEPS_PER_PAGE;
/** Шагов в поле: все показанные страницы. */
const viewSteps = () => (viewTo - viewFrom + 1) * STEPS_PER_PAGE;
/**
 * Как шаги секвенсора: шаг — ячейка, между ячейками зазор STEP_GAP; граница шагов — середина зазора.
 * На одной странице ячейки поля стоят ровно над шагами секвенсора.
 */
const STEP_GAP = 4;
const pitch = () => (W + STEP_GAP) / viewSteps();
const xToPx = (x: number) => (x - pageX0()) * pitch() - STEP_GAP / 2;
const pxToX = (px: number) => pageX0() + (px + STEP_GAP / 2) / pitch();
const yToPx = (y: number) => PAD + (1 - y) * (H - 2 * PAD);
const pxToY = (py: number) => Math.min(1, Math.max(0, 1 - (py - PAD) / (H - 2 * PAD)));

function local(e: PointerEvent): { px: number; py: number } {
  const r = canvas.getBoundingClientRect();
  return { px: e.clientX - r.left, py: e.clientY - r.top };
}

/** Ячейка ручки открытой автоматизации. */
const curDef = (): ParamDef | undefined => { const a = curAuto(); return a ? autoDef(selTrack(), a.param) : undefined; };

/** Привязка по X (доля шага) и Y (доля диапазона); у ступенчатой — к пунктам. */
const clampX = (x: number) => Math.min(autoSpan(), Math.max(0, x));
function snapX(x: number): number {
  const q = autoSnapStep();
  x = q ? Math.round(x / q) * q : x;
  return Math.min(autoSpan(), Math.max(0, x));
}
function snapY(y: number, def: ParamDef | undefined): number {
  if (def && isStepped(def)) {
    const n = def.steps ?? Math.round(def.max - def.min) + 1;
    if (def.steps) return (Math.min(n - 1, Math.floor(y * n)) + 0.5) / n;
    return Math.round(y * (n - 1)) / (n - 1);
  }
  const q = SNAP_Y[ui.autoSnapY];
  return q ? Math.round(y / q) * q : y;
}

/** Тип новой точки: smooth (в режиме LINE рисуется прямой), у ступенчатых — hold. */
const toolType = (def: ParamDef | undefined): SegType => segType(def, 'smooth');

/** Значение для подсказки: в единицах ручки. */
function fmtVal(def: ParamDef | undefined, y: number): string {
  if (!def) return `${Math.round(y * 100)}%`;
  return def.format(fromNorm(def, y)).replace('\n', ' ');
}
const fmtStep = (x: number) => `STEP ${(x + 1).toFixed(2).replace(/\.?0+$/, '')}`;

function showTip(px: number, py: number, text: string) {
  tip.style.left = `${Math.min(W - 60, Math.max(60, px))}px`;
  tip.style.top = `${Math.max(4, py - 70)}px`;
  setText(tip, text);
  setClass(tip, 'hidden', false);
}

// ---------- Поле: жесты ----------

/** Точка открытой автоматизации под пальцем (ближайшая в зоне HIT) или −1. */
function hitPoint(px: number, py: number): number {
  const a = curAuto();
  if (!a) return -1;
  let best = -1;
  let bd = HIT * HIT;
  a.points.forEach((p, i) => {
    const d = (xToPx(p.x) - px) ** 2 + (yToPx(p.y) - py) ** 2;
    if (d <= bd) { bd = d; best = i; }
  });
  return best;
}

function down(e: PointerEvent) {
  const a = curAuto();
  if (!a || drag) return;
  e.preventDefault();
  canvas.setPointerCapture(e.pointerId);
  const { px, py } = local(e);
  const def = curDef();
  const now = performance.now();
  let point = hitPoint(px, py);
  const d: Drag = { id: e.pointerId, x0: px, y0: py, moved: false, point, free: null, timer: 0, gesture: false };
  if (point >= 0) {
    // Двойной тап по точке — удалить её.
    if (lastTap.point === point && now - lastTap.t < DOUBLE_TAP_MS) {
      lastTap = { point: -1, t: -1e9 };
      editAuto((au) => { au.points.splice(point, 1); });
      sel = -1;
      return;
    }
    sel = point;
    // Удержание без движения — меню типа сегмента.
    d.timer = window.setTimeout(() => {
      if (drag === d && !d.moved) { drag = null; openPointMenu(point, e.clientX, e.clientY); }
    }, HOLD_MS);
  } else if (ui.autoFree) {
    // Свободное рисование: точки по ходу пальца, после отпускания — упрощение.
    d.free = [{ x: clampX(pxToX(px)), y: snapY(pxToY(py), def), type: 'smooth' }];
  } else {
    // Тап по пустому месту — новая точка (её же можно сразу тянуть).
    if (a.points.length >= AUTO_MAX_POINTS) return;
    beginGesture();
    d.gesture = true;
    const p: AutoPoint = { x: snapX(pxToX(px)), y: snapY(pxToY(py), def), type: toolType(def) };
    point = insertPoint(a.points, p);
    d.point = point;
    sel = point;
    d.moved = true;
    showTip(px, py, `${fmtVal(def, p.y)}\n${fmtStep(p.x)}`);
  }
  drag = d;
}

function move(e: PointerEvent) {
  const d = drag;
  if (!d || e.pointerId !== d.id) return;
  const { px, py } = local(e);
  const def = curDef();
  if (!d.moved && Math.hypot(px - d.x0, py - d.y0) < MOVE_PX) return;
  if (!d.moved) { d.moved = true; clearTimeout(d.timer); }
  if (d.free) {
    // Привязка X — после отпускания (точка на каждом узле сетки, insertTake).
    const p: AutoPoint = { x: clampX(pxToX(px)), y: snapY(pxToY(py), def), type: 'smooth' };
    // Палец пошёл назад — перерисовывает уже нарисованное.
    while (d.free.length && d.free[d.free.length - 1].x >= p.x) d.free.pop();
    d.free.push(p);
    showTip(px, py, `${fmtVal(def, p.y)}\n${fmtStep(p.x)}`);
    return;
  }
  const a = curAuto();
  if (!a || d.point < 0 || d.point >= a.points.length) return;
  if (!d.gesture) { beginGesture(); d.gesture = true; }
  const pts = a.points;
  const i = d.point;
  // Точка не переходит через соседние (порядок по x сохраняется).
  const lo = i > 0 ? pts[i - 1].x + 0.01 : 0;
  const hi = i < pts.length - 1 ? pts[i + 1].x - 0.01 : autoSpan();
  const p = pts[i];
  p.x = Math.min(hi, Math.max(lo, snapX(pxToX(px))));
  p.y = snapY(pxToY(py), def);
  showTip(px, py, `${fmtVal(def, p.y)}\n${fmtStep(p.x)}`);
}

function up(e: PointerEvent) {
  const d = drag;
  if (!d || e.pointerId !== d.id) return;
  drag = null;
  clearTimeout(d.timer);
  setClass(tip, 'hidden', true);
  if (d.free) {
    const free = d.free;
    const def = curDef();
    if (free.length >= 2) {
      const stepped = isStepped(def);
      editAuto((a) => { a.points = insertTake(a.points, free, stepped, autoSpan()); });
    } else if (free.length === 1) {
      editAuto((a) => { sel = insertPoint(a.points, { ...free[0], x: snapX(free[0].x), type: toolType(def) }); });
    }
    return;
  }
  if (d.gesture) endGesture();
  // Тап по точке (без движения) — запомнить для двойного тапа.
  if (!d.moved && d.point >= 0) lastTap = { point: d.point, t: performance.now() };
  else lastTap = { point: -1, t: -1e9 };
}

/** Удержание точки — тип сегмента от неё (LINEAR, SMOOTH, HOLD) и удаление. */
function openPointMenu(i: number, x: number, y: number) {
  const def = curDef();
  const a = curAuto();
  if (!a || !a.points[i]) return;
  const cur = a.points[i].type;
  const stepped = isStepped(def);
  const items: [string, SegType][] = [['LINEAR', 'linear'], ['SMOOTH', 'smooth'], ['HOLD', 'hold']];
  pointMenu.box.replaceChildren(
    ...items.map(([label, t]) => {
      const b = popupButton(label, () => { pointMenu.close(); editAuto((au) => { if (au.points[i]) au.points[i].type = t; }); });
      b.classList.toggle('current', cur === t);
      b.disabled = stepped && t !== 'hold';
      return b;
    }),
    popupButton('DELETE', () => { pointMenu.close(); editAuto((au) => { au.points.splice(i, 1); }); sel = -1; }),
  );
  pointMenu.openRect({ left: Math.min(window.innerWidth - 168, x + 12), top: Math.max(8, Math.min(window.innerHeight - 240, y - 40)), width: 160, height: 0 });
  pointMenu.box.style.height = '';
}

// ---------- Список автоматизаций ----------

const autoLabel = (id: string) => autoDef(selTrack(), id).label;

/** Кнопка выбора (шириной с MIX): тап — список добавленных автоматизаций, открытая — жёлтая. */
function openList(anchor: Element) {
  const list = autoList();
  if (!list.length) { openPick(plusBtn); return; }
  // Размер и место — как у списка ручек «+» (меряем его, открыв у той же кнопки).
  openPick(anchor);
  const r = pickMenu.box.getBoundingClientRect();
  pickMenu.close();
  listMenu.box.replaceChildren(...list.map((a) => {
    const b = popupButton(autoLabel(a.param), () => { listMenu.close(); ui.autoParam = a.param; sel = -1; });
    b.classList.toggle('current', a.param === ui.autoParam);
    return b;
  }));
  // Верх — по верхнему краю поля; высота — по числу автоматизаций, растёт вниз, а если внизу не
  // помещается — вверх (не выше края окна; дальше — прокрутка).
  const top0 = plot.getBoundingClientRect().top;
  const bottom = window.innerHeight - 8;
  listMenu.openRect({ left: r.left, top: top0, width: r.width, height: 0 });
  const box = listMenu.box;
  box.style.height = '';
  box.style.maxHeight = `${bottom - 8}px`;
  const hgt = box.offsetHeight;
  box.style.top = `${Math.max(8, Math.min(top0, bottom - hgt))}px`;
}

/** «+»: выбор ручки дорожки (уже назначенная — просто открывается). */
function openPick(anchor: Element) {
  const t = selTrack();
  const e = synthEngine(t.sample);
  const grid = e !== null ? synthGrid(e) : TRACK_GRID;
  // Порядок — как в сетке: по колонкам (1.1, 1.2, …).
  const params: ParamDef[] = [];
  for (let col = 0; col < 4; col++) for (let row = 0; row < 4; row++) {
    const p = grid[row * 4 + col];
    if (p && AUTO_PARAMS.has(p.id)) params.push(p);
  }
  const has = new Set(autoList().map((a) => a.param));
  pickMenu.box.replaceChildren(...params.map((p) => {
    const b = popupButton(`${p.label}${has.has(p.id) ? '  •' : ''}`, () => { pickMenu.close(); addAuto(p.id); sel = -1; });
    return b;
  }));
  pickMenu.openAt(anchor, 220);
}

/** Открытая автоматизация есть у паттерна (сменили дорожку или паттерн — первая из списка). */
function syncOpen() {
  const list = autoList();
  if (!list.some((a) => a.param === ui.autoParam)) { ui.autoParam = list[0]?.param ?? ''; sel = -1; }
}

// ---------- Построение ----------

function tool(label: string, fn: () => void, cls = ''): HTMLElement {
  const el = h('div', `btn eq-tool auto-tool ${cls}`, label);
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    if (!el.classList.contains('disabled')) fn();
  });
  return el;
}

export function buildAuto(): HTMLElement {
  panel = h('div', 'eq-panel auto hidden');
  pickMenu = makePopup();
  pointMenu = makePopup();

  listMenu = makePopup();
  const bar = h('div', 'eq-bar auto-bar');
  nameText = h('div', 'btn auto-name');
  nameText.addEventListener('pointerdown', (e) => { e.preventDefault(); if (ui.channel === 'track') openList(nameText); });
  // «+» — новая автоматизация (выбор ручки); DELETE — удалить открытую (отмена — UNDO).
  plusBtn = tool('+', () => openPick(plusBtn), 'sq auto-plus');
  delBtn = tool('DELETE', () => { deleteAuto(ui.autoParam); sel = -1; }, 'auto-del');
  // LINE | SPLINE — режим кривой открытой автоматизации (LINE — все сегменты прямые).
  toolBtns.line = tool('LINE', () => setAutoCurve('line'));
  toolBtns.spline = tool('SPLINE', () => setAutoCurve('spline'));
  // Карандаш — свободное рисование пальцем.
  toolBtns.free = tool('', () => { ui.autoFree = !ui.autoFree; }, 'sq');
  toolBtns.free.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20l1-4L16 5l3 3L8 19z"/><path d="M14 7l3 3"/></svg>';
  snapXBtn = tool('', () => { ui.autoSnapX = (ui.autoSnapX + 1) % AUTO_SNAP_X.length; });
  snapYBtn = tool('', () => { ui.autoSnapY = (ui.autoSnapY + 1) % SNAP_Y.length; });
  // SIMPLIFY: палец вбок по полю (0…100 %) — упрощение последней записи заново.
  simpBox = h('div', 'btn eq-tool auto-simp');
  simpFill = h('div', 'auto-simp-fill');
  simpText = h('div', 'auto-simp-text');
  simpBox.append(simpFill, simpText);
  let sx = -1;
  let sv = 0;
  simpBox.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    simpBox.setPointerCapture(e.pointerId);
    sx = e.clientX;
    sv = ui.autoSimplify;
    beginGesture();
  });
  simpBox.addEventListener('pointermove', (e) => {
    if (sx < 0) return;
    setAutoSimplify(Math.round(sv + ((e.clientX - sx) / simpBox.clientWidth) * 100));
  });
  const simpEnd = () => { if (sx < 0) return; sx = -1; endGesture(); };
  simpBox.addEventListener('pointerup', simpEnd);
  simpBox.addEventListener('pointercancel', simpEnd);
  const clear = tool('CLEAR', () => { clearAuto(); sel = -1; });
  editBtns.push(clear, toolBtns.line, toolBtns.spline, toolBtns.free, snapXBtn, snapYBtn);
  bar.append(nameText, plusBtn, delBtn, toolBtns.line, toolBtns.spline, toolBtns.free, simpBox, snapXBtn, snapYBtn, clear, buildPagesRow());

  const body = h('div', 'auto-body');
  plot = h('div', 'eq-plot');
  canvas = document.createElement('canvas');
  canvas.className = 'eq-canvas auto-canvas';
  note = h('div', 'sedit-note hidden');
  tip = h('div', 'eq-tip hidden');
  plot.append(canvas, note, tip);
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);
  body.append(plot);
  panel.append(bar, body);
  return panel;
}

/** Кнопка AUTO в верхней панели. */
export function toggleAuto() { toggleView('auto'); }

// ---------- Отрисовка (каждый кадр, пока окно открыто) ----------

// ---------- Страницы паттерна: квадратики в верхней панели ----------
// Какие страницы показаны в поле (на воспроизведение не влияет). Выделение — как у миниатюр страниц
// дорожки, только по горизонтали: белая обводка — показанные страницы; тап — одна страница; протягивание —
// несколько; касание у края обводки тянет этот край влево-вправо, в середине — переносит обводку целиком.

const EDGE = 0.4;
let pagesRow: HTMLElement;
let pageCells: HTMLElement[] = [];
let pageOutline: HTMLElement;
let pagesSig = '';
let pdrag: { id: number; x0: number; from: number; mode: 'left' | 'right' | 'move' | 'new'; f: number; t: number; p0: number; moved: boolean; range: [number, number] | null } | null = null;

function pageGeom() {
  const first = pageCells[0]?.getBoundingClientRect();
  const second = pageCells[1]?.getBoundingClientRect();
  return { left: first?.left ?? 0, pitch: second && first ? second.left - first.left : (first?.width ?? 40) + 6 };
}

function buildPagesRow(): HTMLElement {
  pagesRow = h('div', 'auto-pages');
  pageOutline = h('div', 'auto-pages-outline');
  pagesRow.append(pageOutline);
  pagesRow.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const t = selTrack();
    if (pdrag || ui.channel !== 'track' || t.pages.length < 1) return;
    pagesRow.setPointerCapture(e.pointerId);
    const { left, pitch } = pageGeom();
    const pos = (e.clientX - left) / pitch;
    const i = Math.min(t.pages.length - 1, Math.max(0, Math.floor(pos)));
    const mode = Math.abs(pos - viewFrom) <= EDGE ? 'left' : Math.abs(pos - (viewTo + 1)) <= EDGE ? 'right'
      : pos > viewFrom && pos < viewTo + 1 ? 'move' : 'new';
    pdrag = { id: e.pointerId, x0: e.clientX, from: i, mode, f: viewFrom, t: viewTo, p0: pos, moved: false, range: null };
  });
  pagesRow.addEventListener('pointermove', (e) => {
    const d = pdrag;
    if (!d || e.pointerId !== d.id) return;
    if (!d.moved && Math.abs(e.clientX - d.x0) < MOVE_PX) return;
    d.moved = true;
    const n = selTrack().pages.length;
    const { left, pitch } = pageGeom();
    const pos = (e.clientX - left) / pitch;
    const cl = (v: number) => Math.min(n - 1, Math.max(0, v));
    // Край берёт страницу, когда зашёл в неё на треть.
    if (d.mode === 'left') d.range = [Math.min(d.t, cl(Math.ceil(pos - 2 / 3))), d.t];
    else if (d.mode === 'right') d.range = [d.f, Math.max(d.f, cl(Math.floor(pos - 1 / 3)))];
    else if (d.mode === 'move') {
      const len = d.t - d.f;
      const f = Math.min(n - 1 - len, Math.max(0, d.f + Math.round(pos - d.p0)));
      d.range = [f, f + len];
    } else {
      const k = cl(Math.floor(pos));
      d.range = [Math.min(d.from, k), Math.max(d.from, k)];
    }
  });
  const end = (e: PointerEvent) => {
    const d = pdrag;
    if (!d || e.pointerId !== d.id) return;
    pdrag = null;
    if (e.type !== 'pointerup') return;
    if (d.moved) {
      if (d.range) [viewFrom, viewTo] = d.range;
      return;
    }
    // Тап: в поле — одна эта страница.
    viewFrom = viewTo = d.from;
  };
  pagesRow.addEventListener('pointerup', end);
  pagesRow.addEventListener('pointercancel', end);
  return pagesRow;
}

function renderPagesRow(isTrack: boolean) {
  const t = selTrack();
  const n = isTrack ? t.pages.length : 0;
  if (pageCells.length !== n) {
    pageCells = Array.from({ length: n }, (_, k) => h('div', 'auto-page', String(k + 1)));
    pagesRow.replaceChildren(...pageCells, pageOutline);
    pagesSig = '';
  }
  const [f, to] = pdrag?.range ?? [viewFrom, viewTo];
  const sig = `${n}|${f}|${to}|${pagesRow.clientWidth}`;
  if (sig === pagesSig) return;
  pagesSig = sig;
  pageCells.forEach((c, k) => setClass(c, 'on', k >= f && k <= to));
  setClass(pageOutline, 'hidden', !n);
  if (!n) return;
  const a = pageCells[Math.min(f, n - 1)];
  const b = pageCells[Math.min(to, n - 1)];
  pageOutline.style.left = `${a.offsetLeft - 3}px`;
  pageOutline.style.width = `${b.offsetLeft + b.offsetWidth - a.offsetLeft + 6}px`;
}

export function renderAuto() {
  setClass(panel, 'hidden', !ui.autoView);
  if (!ui.autoView) { if (pickMenu?.isOpen()) pickMenu.close(); return; }
  const isTrack = ui.channel === 'track';
  const t = selTrack();
  syncOpen();
  const a = curAuto();
  const def = curDef();
  const pages = t.pages.length;
  const pos = isTrack ? autoPos(ui.selectedTrack) : null;
  viewTo = Math.min(viewTo, pages - 1);
  viewFrom = Math.min(viewFrom, viewTo);
  renderPagesRow(isTrack);

  // Сверху: дорожка (жирным), под ней — параметр.
  const title = `${isTrack ? t.name : ''}\n${a ? autoLabel(a.param) : 'Automation'}`;
  if (nameText.dataset.t !== title) {
    nameText.dataset.t = title;
    const [tn, pn] = title.split('\n');
    nameText.replaceChildren(h('b', '', tn), h('span', '', pn));
    nameText.dataset.fit = '';
  }
  // Длинное имя — шрифт мельче, чтобы влезло в ширину кнопки (высота строки та же).
  if (!nameText.dataset.fit && nameText.clientWidth) {
    nameText.dataset.fit = '1';
    for (const el of nameText.children as HTMLCollectionOf<HTMLElement>) {
      el.style.fontSize = '';
      const avail = nameText.clientWidth - 16;
      if (el.scrollWidth > avail) el.style.fontSize = `${Math.max(9, Math.floor((13 * avail) / el.scrollWidth))}px`;
    }
  }
  // Кнопка выбора — шириной с MIX в строке дорожек.
  const mixW = (document.querySelector('.track.channel') as HTMLElement | null)?.offsetWidth ?? 0;
  if (mixW && nameText.style.width !== `${mixW}px`) nameText.style.width = `${mixW}px`;
  setClass(delBtn, 'disabled', !a);
  setClass(plusBtn, 'disabled', !isTrack);
  const curve = a?.curve ?? 'spline';
  setClass(toolBtns.line, 'on', curve === 'line');
  setClass(toolBtns.spline, 'on', curve === 'spline');
  setClass(toolBtns.free, 'on', ui.autoFree);
  setText(snapXBtn, `X ${SNAP_X_NAMES[ui.autoSnapX]}`);
  setText(snapYBtn, `Y ${SNAP_Y_NAMES[ui.autoSnapY]}`);
  setClass(snapXBtn, 'on', ui.autoSnapX > 0);
  setClass(snapYBtn, 'on', ui.autoSnapY > 0);
  for (const b of editBtns) setClass(b, 'disabled', !a);
  setText(simpText, `SIMPLIFY ${ui.autoSimplify}%`);
  simpFill.style.width = `${ui.autoSimplify}%`;
  setClass(simpBox, 'live', canResimplify());
  setClass(note, 'hidden', !!a);
  setText(note, !isTrack ? 'Select a track to automate its knobs.' : 'No automation in this pattern — tap + to add one.');

  // Поле во всю ширину над шагами 1–16 секвенсора (список слева лежит поверх 1-го шага).
  const steps = document.querySelectorAll('.sequencer .step');
  if (steps.length >= 16) {
    const a1 = steps[0].getBoundingClientRect();
    const a16 = steps[15].getBoundingClientRect();
    const body = plot.parentElement!.getBoundingClientRect();
    const ml = `${Math.round(a1.left - body.left)}px`;
    const w = `${Math.round(a16.right - a1.left)}px`;
    if (plot.style.width !== w || plot.style.marginLeft !== ml) {
      plot.style.flex = 'none';
      plot.style.width = w;
      plot.style.marginLeft = ml;
    }
  }
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
  if (!isTrack) return;

  // Сетка — вертикальные линии на границах шагов (сильнее — доли по 4 шага, ещё сильнее — границы
  // страниц); больше страниц — сетка мельче. За длиной паттерна — затемнено.
  const span = viewSteps();
  const cw = pitch();
  for (let k = 0; k <= span; k++) {
    const idx = pageX0() + k;
    const pageEdge = idx % STEPS_PER_PAGE === 0;
    const beat = idx % 4 === 0;
    if (!pageEdge && !beat && cw < 6) continue;
    g.fillStyle = color(pageEdge && k > 0 && k < span ? '--dim' : beat ? '--grid-strong' : '--grid');
    const lx = Math.max(0, Math.min(W - 1, Math.round(xToPx(pageX0() + k))));
    g.fillRect(lx - (pageEdge && k > 0 && k < span ? 1 : 0), 0, pageEdge && k > 0 && k < span ? 2 : 1, H);
  }
  // У каждого паттерна (страницы) своя длина: шаги за ней затемнены.
  g.fillStyle = color('--scrim');
  for (let pg = Math.floor(pageX0() / STEPS_PER_PAGE); pg * STEPS_PER_PAGE < pageX0() + span; pg++) {
    const len = pg < t.pages.length ? pageLen(t, pg) : 0;
    if (len >= STEPS_PER_PAGE) continue;
    const x0 = xToPx(pg * STEPS_PER_PAGE + len);
    const x1 = Math.min(W, xToPx((pg + 1) * STEPS_PER_PAGE));
    if (x1 > x0) g.fillRect(x0, 0, x1 - x0, H);
  }
  // Горизонтали 0/25/50/75/100 %; у двухполярных — линия нуля ярче.
  for (const y of [0, 0.25, 0.5, 0.75, 1]) {
    g.fillStyle = color(y === 0.5 && def?.bipolar ? '--grid-strong' : '--grid');
    g.fillRect(0, Math.round(yToPx(y)), W, 1);
  }
  if (!a) return;
  const stepped = isStepped(def);
  // Кривая: по пикселям.
  if (a.points.length) {
    g.strokeStyle = color('--ink');
    g.lineWidth = 2;
    g.lineJoin = 'round';
    // Кривая — только там, где действует (страницы с точками, от первой точки до последней): участками.
    const pts = a.points;
    const runs: [number, number][][] = [];
    let run: [number, number][] | null = null;
    for (let px = 0; px <= W; px += 1) {
      const y = evalAuto(pts, pxToX(px), stepped, a.curve === 'line');
      if (y === null) { run = null; continue; }
      if (!run) runs.push((run = []));
      run.push([px, yToPx(y)]);
    }
    g.fillStyle = color('--grid');
    for (const r of runs) {
      g.beginPath();
      r.forEach(([x, y], k) => (k ? g.lineTo(x, y) : g.moveTo(x, y)));
      g.stroke();
      g.lineTo(r[r.length - 1][0], H);
      g.lineTo(r[0][0], H);
      g.closePath();
      g.fill();
    }
  }
  // Запись: что пишется сейчас — красным.
  const drawRaw = (pts: AutoPoint[], c: string) => {
    if (pts.length < 2) return;
    g.strokeStyle = color(c);
    g.lineWidth = 2;
    g.beginPath();
    pts.forEach((p, k) => (k ? g.lineTo(xToPx(p.x), yToPx(p.y)) : g.moveTo(xToPx(p.x), yToPx(p.y))));
    g.stroke();
  };
  for (const piece of autoRecPieces() ?? []) drawRaw(piece, '--rec');
  if (drag?.free) drawRaw(drag.free, '--accent');
  // Точки страницы: выбранная — крупнее и жёлтая.
  if (sel >= a.points.length) sel = -1;
  a.points.forEach((p, i) => {
    const x = xToPx(p.x);
    if (x < -HIT || x > W + HIT) return;
    g.beginPath();
    g.arc(x, yToPx(p.y), i === sel ? 7 : 5, 0, Math.PI * 2);
    g.fillStyle = color(i === sel ? '--accent' : '--ink');
    g.fill();
  });
  // Линия позиции воспроизведения.
  if (pos !== null && pos >= pageX0() && pos < pageX0() + viewSteps()) {
    g.fillStyle = color('--accent');
    g.fillRect(Math.round(xToPx(pos)) - 1, 0, 2, H);
  }
}
