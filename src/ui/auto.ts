// Окно автоматизации (кнопка AUTO): на месте центра экрана, как EQ и редактор сэмпла.
// Слева (шириной с MIX) — список автоматизаций активного паттерна выбранной дорожки (по подписи ручки;
// выбранная — жёлтая; двойной тап — меню DELETE) и «+» (выбор ручки). Сверху — дорожка и параметр,
// LINE | SPLINE (режим кривой), карандаш (свободное рисование), SIMPLIFY, SNAP по X и Y, CLEAR, закрытие.
// Запись — основной кнопкой REC при игре: поворот ручки пишет её автоматизацию.
// Поле: 16 ячеек шагов (страницы паттерна листаются, при игре — за позицией), деления 1/2 и 1/4 шага,
// линии 0/25/50/75/100 %, линия позиции. Тап по пустому месту — точка; тап по точке — выбор; удержание
// и перетаскивание — двигает; двойной тап — удаление; удержание без движения — тип сегмента.

import { AUTO_PARAMS, AUTO_MAX_POINTS, evalAuto, insertPoint, isStepped, segType, simplify, spliceRecording, type AutoPoint, type SegType } from '../automation';
import { fromNorm, STEPS_PER_PAGE, synthEngine, synthGrid, TRACK_GRID, type ParamDef } from '../params';
import {
  addAuto, autoDef, setPlayPages, autoList, autoPos, autoRecPieces, autoSpan, beginGesture, canResimplify, clearAuto, curAuto, deleteAuto,
  editAuto, endGesture, selTrack, setAutoCurve, setAutoSimplify, toggleView, ui,
} from '../state';
import { closeButton, DOUBLE_TAP_MS, h, setClass, setText } from './dom';
import { makePopup, popupButton, type Popup } from './popup';
import { color } from './theme';

/** Поле рисования: отступ сверху и снизу, чтобы точки на 0 и 100 % были видны целиком. */
const PAD = 14;
/** Зона попадания в точку (радиус, px) — 44 pt в поперечнике. */
const HIT = 22;
const HOLD_MS = 450;
const MOVE_PX = 6;
const SNAP_X = [0, 0.25, 0.5, 1];
const SNAP_X_NAMES = ['OFF', '1/4', '1/2', '1'];
const SNAP_Y = [0, 0.1, 0.25];
const SNAP_Y_NAMES = ['OFF', '10%', '25%'];

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let note: HTMLElement;
let tip: HTMLElement;
let nameText: HTMLElement;
let listBox: HTMLElement;
let side: HTMLElement;
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
let page = 0;
let lastPlayPage = -1;
/** Выбранная точка (индекс в открытой автоматизации; −1 — нет). */
let sel = -1;
/** Подпись списка: перестраивается при изменении. */
let listSig = '';
let listMenu: Popup;
const listTap = { id: '', t: -1e9 };

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

const pageX0 = () => page * STEPS_PER_PAGE;
const xToPx = (x: number) => ((x - pageX0()) / STEPS_PER_PAGE) * W;
const pxToX = (px: number) => pageX0() + (px / W) * STEPS_PER_PAGE;
const yToPx = (y: number) => PAD + (1 - y) * (H - 2 * PAD);
const pxToY = (py: number) => Math.min(1, Math.max(0, 1 - (py - PAD) / (H - 2 * PAD)));

function local(e: PointerEvent): { px: number; py: number } {
  const r = canvas.getBoundingClientRect();
  return { px: e.clientX - r.left, py: e.clientY - r.top };
}

/** Ячейка ручки открытой автоматизации. */
const curDef = (): ParamDef | undefined => { const a = curAuto(); return a ? autoDef(selTrack(), a.param) : undefined; };

/** Привязка по X (доля шага) и Y (доля диапазона); у ступенчатой — к пунктам. */
function snapX(x: number): number {
  const q = SNAP_X[ui.autoSnapX];
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
    d.free = [{ x: snapX(pxToX(px)), y: snapY(pxToY(py), def), type: 'smooth' }];
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
    const p: AutoPoint = { x: snapX(pxToX(px)), y: snapY(pxToY(py), def), type: 'smooth' };
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
      const pts = simplify(free, (ui.autoSimplify / 100) * 0.05).map((p) => ({ ...p, type: segType(def, 'smooth') }));
      editAuto((a) => { a.points = spliceRecording(a.points, pts, stepped); });
    } else if (free.length === 1) {
      editAuto((a) => { sel = insertPoint(a.points, { ...free[0], type: toolType(def) }); });
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

/** Размер шрифта кнопки списка — по длине подписи (длинная — мельче; из двух слов — в две строки). */
function labelSize(label: string): number {
  const longest = Math.max(...label.split(/\s+/).map((w) => w.length));
  const n = label.includes(' ') ? longest : label.length;
  return n <= 6 ? 14 : n <= 8 ? 12 : n <= 10 ? 11 : 10;
}

/** Кнопка списка: тап — открыть; двойной тап — меню DELETE. */
function listRow(id: string): HTMLElement {
  const label = autoLabel(id);
  const item = h('div', 'btn auto-item', label);
  item.style.fontSize = `${labelSize(label)}px`;
  setClass(item, 'current', ui.autoParam === id);
  item.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const now = performance.now();
    if (listTap.id === id && now - listTap.t < DOUBLE_TAP_MS) {
      listTap.id = '';
      listMenu.box.replaceChildren(popupButton('DELETE', () => { listMenu.close(); deleteAuto(id); listSig = ''; }));
      listMenu.openAt(item, 160);
      return;
    }
    listTap.id = id;
    listTap.t = now;
    ui.autoParam = id;
    sel = -1;
  });
  return item;
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
    const b = popupButton(`${p.label}${has.has(p.id) ? '  •' : ''}`, () => { pickMenu.close(); addAuto(p.id); sel = -1; listSig = ''; });
    return b;
  }));
  pickMenu.openAt(anchor, 220);
}

function renderList() {
  const list = autoList();
  // Открытая автоматизация есть у паттерна (сменили дорожку или паттерн — первая из списка).
  if (!list.some((a) => a.param === ui.autoParam)) { ui.autoParam = list[0]?.param ?? ''; sel = -1; }
  const sig = `${ui.selectedTrack}|${selTrack().slot}|${selTrack().sample}|${ui.autoParam}|${list.map((a) => a.param).join(',')}`;
  if (sig === listSig) return;
  listSig = sig;
  const plus = h('div', 'btn auto-plus', '+');
  plus.addEventListener('pointerdown', (e) => { e.preventDefault(); openPick(plus); });
  listBox.replaceChildren(...list.map((a) => listRow(a.param)), plus);
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
  nameText = h('div', 'eq-name auto-name');
  // LINE | SPLINE — режим кривой открытой автоматизации (LINE — все сегменты прямые).
  toolBtns.line = tool('LINE', () => setAutoCurve('line'));
  toolBtns.spline = tool('SPLINE', () => setAutoCurve('spline'));
  // Карандаш — свободное рисование пальцем.
  toolBtns.free = tool('', () => { ui.autoFree = !ui.autoFree; }, 'sq');
  toolBtns.free.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20l1-4L16 5l3 3L8 19z"/><path d="M14 7l3 3"/></svg>';
  snapXBtn = tool('', () => { ui.autoSnapX = (ui.autoSnapX + 1) % SNAP_X.length; });
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
  const close = closeButton(() => toggleView('auto'));
  bar.append(nameText, toolBtns.line, toolBtns.spline, toolBtns.free, simpBox, snapXBtn, snapYBtn, clear, buildPagesRow(), close);

  const body = h('div', 'auto-body');
  side = h('div', 'auto-side');
  listBox = h('div', 'auto-list');
  side.append(listBox);
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
  body.append(side, plot);
  panel.append(bar, body);
  return panel;
}

/** Кнопка AUTO в верхней панели. */
export function toggleAuto() { toggleView('auto'); }

// ---------- Отрисовка (каждый кадр, пока окно открыто) ----------

// ---------- Страницы паттерна: квадратики в верхней панели ----------
// Как миниатюры страниц дорожки, только по горизонтали: белая обводка — играющие страницы; тап — одна
// страница (через 0,3 с, если не было второго тапа); протягивание — несколько; касание у края обводки
// тянет этот край влево-вправо, в середине — переносит обводку целиком. Открытая в поле страница — светлее.

const EDGE = 0.4;
let pagesRow: HTMLElement;
let pageCells: HTMLElement[] = [];
let pageOutline: HTMLElement;
let pagesSig = '';
let pdrag: { id: number; x0: number; from: number; mode: 'left' | 'right' | 'move' | 'new'; f: number; t: number; p0: number; moved: boolean; range: [number, number] | null } | null = null;
let pageTapTimer = 0;

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
    const mode = Math.abs(pos - t.playFrom) <= EDGE ? 'left' : Math.abs(pos - (t.playTo + 1)) <= EDGE ? 'right'
      : pos > t.playFrom && pos < t.playTo + 1 ? 'move' : 'new';
    pdrag = { id: e.pointerId, x0: e.clientX, from: i, mode, f: t.playFrom, t: t.playTo, p0: pos, moved: false, range: null };
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
      if (d.range && (d.range[0] !== d.f || d.range[1] !== d.t)) { setPlayPages(d.range[0], d.range[1]); page = d.range[0]; }
      return;
    }
    // Тап: одна страница играет и открыта в поле.
    clearTimeout(pageTapTimer);
    const i = d.from;
    pageTapTimer = window.setTimeout(() => {
      if (i >= selTrack().pages.length) return;
      setPlayPages(i, i);
      page = i;
    }, DOUBLE_TAP_MS);
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
  const [f, to] = pdrag?.range ?? [t.playFrom, t.playTo];
  const sig = `${n}|${page}|${f}|${to}|${pagesRow.clientWidth}`;
  if (sig === pagesSig) return;
  pagesSig = sig;
  pageCells.forEach((c, k) => setClass(c, 'on', k === page));
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
  renderList();
  // Кнопки списка не прокручиваются: если не помещаются — становятся ниже (до 52 px).
  const n = listBox.children.length;
  const rowH = n ? Math.max(20, Math.min(52, Math.floor((listBox.clientHeight - 6 * (n - 1)) / n))) : 52;
  const rows = `${rowH}px`;
  if (listBox.style.gridAutoRows !== rows) listBox.style.gridAutoRows = rows;
  setClass(listBox, 'hidden', !isTrack);
  const a = curAuto();
  const def = curDef();
  const pages = t.pages.length;
  // При игре поле следует за позицией (страница позиции).
  const pos = isTrack ? autoPos(ui.selectedTrack) : null;
  if (pos !== null) {
    const pp = Math.floor(pos / STEPS_PER_PAGE);
    if (pp !== lastPlayPage) { lastPlayPage = pp; page = pp; }
  } else lastPlayPage = -1;
  page = Math.min(page, pages - 1);
  renderPagesRow(isTrack);

  // Сверху: дорожка (жирным), под ней — параметр.
  const title = `${isTrack ? t.name : ''}\n${a ? autoLabel(a.param) : 'Automation'}`;
  if (nameText.dataset.t !== title) {
    nameText.dataset.t = title;
    const [tn, pn] = title.split('\n');
    nameText.replaceChildren(h('b', '', tn), h('span', '', pn));
  }
  // Боковые кнопки и имя — шириной с MIX в строке дорожек.
  const mixW = (document.querySelector('.track.channel') as HTMLElement | null)?.offsetWidth ?? 0;
  if (mixW) { const w = `${mixW}px`; if (side.style.width !== w) { side.style.width = w; nameText.style.minWidth = w; } }
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

  // Поле по шагам секвенсора: от левого края 2-го шага до правого края 15-го (слева — колонка списка над 1-м).
  const steps = document.querySelectorAll('.sequencer .step');
  if (steps.length >= 15) {
    const a2 = steps[1].getBoundingClientRect();
    const a15 = steps[14].getBoundingClientRect();
    const ml = `${Math.round(a2.left - side.getBoundingClientRect().right - 6)}px`;
    const w = `${Math.round(a15.right - a2.left)}px`;
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

  // Ячейки шагов (16 на страницу, как шаги секвенсора); доли — светлее; за длиной паттерна — затемнено.
  const cw = W / STEPS_PER_PAGE;
  const gap = 2;
  for (let k = 0; k < STEPS_PER_PAGE; k++) {
    const idx = pageX0() + k;
    g.fillStyle = color(k % 4 === 0 ? '--panel-2' : '--panel');
    g.globalAlpha = idx >= t.length ? 0.4 : 1;
    g.fillRect(k * cw + gap / 2, 0, cw - gap, H);
  }
  g.globalAlpha = 1;
  // Деления внутри шага: 1/2 и 1/4.
  g.fillStyle = color('--grid');
  for (let k = 0; k < STEPS_PER_PAGE; k++) for (const f of [0.25, 0.5, 0.75]) g.fillRect(Math.round((k + f) * cw), f === 0.5 ? 0 : H * 0.35, 1, f === 0.5 ? H : H * 0.3);
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
    g.beginPath();
    for (let px = 0; px <= W; px += 1) {
      const y = evalAuto(a.points, pxToX(px), stepped, a.curve === 'line') ?? 0;
      if (px === 0) g.moveTo(px, yToPx(y)); else g.lineTo(px, yToPx(y));
    }
    g.stroke();
    g.lineTo(W, H);
    g.lineTo(0, H);
    g.closePath();
    g.fillStyle = color('--grid');
    g.fill();
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
  if (pos !== null && pos >= pageX0() && pos < pageX0() + STEPS_PER_PAGE) {
    g.fillStyle = color('--accent');
    g.fillRect(Math.round(xToPx(pos)) - 1, 0, 2, H);
  }
}
