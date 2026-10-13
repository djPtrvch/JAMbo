// Окно автоматизации (кнопка AUTO): на месте центра экрана, как EQ и редактор сэмпла.
// Слева — список автоматизаций активного паттерна выбранной дорожки (по подписи ручки; выбранная —
// жёлтая; свайп влево — корзина, второй тап — удалить) и «+» (выбор ручки). Сверху — имя, инструмент
// LINE | SPLINE | FREE, SNAP по X и Y, REC, SIMPLIFY и число точек, COPY, PASTE, CLEAR, закрытие.
// Поле: 16 ячеек шагов (страницы паттерна листаются, при игре — за позицией), деления 1/2 и 1/4 шага,
// линии 0/25/50/75/100 %, линия позиции. Тап по пустому месту — точка; тап по точке — выбор; удержание
// и перетаскивание — двигает; двойной тап — удаление; удержание без движения — тип сегмента.

import { AUTO_PARAMS, AUTO_MAX_POINTS, evalAuto, insertPoint, isStepped, segType, simplify, spliceRecording, type AutoPoint, type SegType } from '../automation';
import { fromNorm, STEPS_PER_PAGE, synthEngine, synthGrid, TRACK_GRID, type ParamDef } from '../params';
import {
  addAuto, autoDef, autoList, autoPos, autoRecPieces, autoSpan, beginGesture, canResimplify, clearAuto, copyAuto, curAuto, deleteAuto,
  editAuto, endGesture, pasteAuto, selTrack, setAutoSimplify, toggleView, ui,
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
let pagesBox: HTMLElement;
let countText: HTMLElement;
let recBtn: HTMLElement;
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
let confirmDel = '';

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

const toolType = (def: ParamDef | undefined): SegType => segType(def, ui.autoTool === 'line' ? 'linear' : 'smooth');

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
  } else if (ui.autoTool === 'free') {
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

/** Строка списка: тап — открыть; свайп влево — корзина (второй тап — удалить). */
function listRow(id: string): HTMLElement {
  const row = h('div', 'project-row lib-row auto-row');
  const acts = h('div', 'lib-acts');
  const trash = h('div', 'lib-act lib-trash');
  const icon = '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  trash.innerHTML = icon;
  trash.addEventListener('pointerup', () => {
    // Подтверждение — вторым тапом.
    if (confirmDel !== id) { confirmDel = id; trash.textContent = 'DELETE?'; return; }
    confirmDel = '';
    deleteAuto(id);
    listSig = '';
  });
  acts.append(trash);
  const ACT = 72;
  const item = h('div', 'popup-btn project-item lib-item auto-item', autoLabel(id));
  setClass(item, 'current', ui.autoParam === id);
  row.append(acts, item);
  let pid = -1;
  let x0 = 0;
  let base = 0;
  let dx = 0;
  const place = (x: number) => { item.style.width = x ? `calc(100% - ${-x}px)` : ''; };
  item.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    pid = e.pointerId;
    x0 = e.clientX;
    dx = 0;
    base = row.classList.contains('open') ? -ACT : 0;
    item.setPointerCapture(e.pointerId);
  });
  item.addEventListener('pointermove', (e) => {
    if (e.pointerId !== pid) return;
    dx = e.clientX - x0;
    if (Math.abs(dx) > 6) place(Math.max(-ACT, Math.min(0, base + dx)));
  });
  const end = (e: PointerEvent) => {
    if (e.pointerId !== pid) return;
    pid = -1;
    if (Math.abs(dx) <= 6) {
      if (row.classList.contains('open')) { row.classList.remove('open'); place(0); return; }
      ui.autoParam = id;
      sel = -1;
      return;
    }
    const opened = base + dx < -ACT / 2;
    listBox.querySelectorAll('.auto-row.open').forEach((r) => { if (r !== row) { r.classList.remove('open'); (r.querySelector('.auto-item') as HTMLElement).style.width = ''; } });
    row.classList.toggle('open', opened);
    if (!opened) { confirmDel = ''; trash.innerHTML = icon; }
    place(opened ? -ACT : 0);
  };
  item.addEventListener('pointerup', end);
  item.addEventListener('pointercancel', end);
  return row;
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
  confirmDel = '';
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

  const bar = h('div', 'eq-bar auto-bar');
  nameText = h('div', 'eq-name auto-name');
  for (const [k, label] of [['line', 'LINE'], ['spline', 'SPLINE'], ['free', 'FREE']] as const) {
    toolBtns[k] = tool(label, () => { ui.autoTool = k; });
  }
  snapXBtn = tool('', () => { ui.autoSnapX = (ui.autoSnapX + 1) % SNAP_X.length; });
  snapYBtn = tool('', () => { ui.autoSnapY = (ui.autoSnapY + 1) % SNAP_Y.length; });
  recBtn = tool('', () => { ui.autoRec = !ui.autoRec; }, 'sq rec-btn');
  recBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="6" fill="currentColor"/></svg>';
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
  countText = h('div', 'auto-count');
  const copy = tool('COPY', copyAuto);
  const paste = tool('PASTE', pasteAuto);
  const clear = tool('CLEAR', () => { clearAuto(); sel = -1; });
  editBtns.push(copy, paste, clear, toolBtns.line, toolBtns.spline, toolBtns.free, snapXBtn, snapYBtn, recBtn);
  const close = closeButton(() => toggleView('auto'));
  bar.append(nameText, toolBtns.line, toolBtns.spline, toolBtns.free, snapXBtn, snapYBtn, recBtn, simpBox, countText, copy, paste, clear, h('div', 'sedit-space'), close);

  const body = h('div', 'auto-body');
  const side = h('div', 'auto-side');
  listBox = h('div', 'auto-list scrolly');
  pagesBox = h('div', 'auto-pages');
  side.append(listBox, pagesBox);
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

let pagesSig = '';
function renderPagesBox(n: number) {
  const sig = `${n}|${page}`;
  if (sig === pagesSig) return;
  pagesSig = sig;
  if (n <= 1) { pagesBox.replaceChildren(); return; }
  pagesBox.replaceChildren(...Array.from({ length: n }, (_, k) => {
    const b = h('div', `btn auto-page${k === page ? ' on' : ''}`, String(k + 1));
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); page = k; });
    return b;
  }));
}

export function renderAuto() {
  setClass(panel, 'hidden', !ui.autoView);
  if (!ui.autoView) { if (pickMenu?.isOpen()) pickMenu.close(); return; }
  const isTrack = ui.channel === 'track';
  const t = selTrack();
  renderList();
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
  renderPagesBox(isTrack ? pages : 1);

  setText(nameText, a ? `${autoLabel(a.param)}\n${t.name}` : isTrack ? `AUTOMATION\n${t.name}` : 'AUTOMATION');
  for (const [k, b] of Object.entries(toolBtns)) setClass(b, 'on', ui.autoTool === k);
  setText(snapXBtn, `X ${SNAP_X_NAMES[ui.autoSnapX]}`);
  setText(snapYBtn, `Y ${SNAP_Y_NAMES[ui.autoSnapY]}`);
  setClass(snapXBtn, 'on', ui.autoSnapX > 0);
  setClass(snapYBtn, 'on', ui.autoSnapY > 0);
  setClass(recBtn, 'rec', ui.autoRec);
  for (const b of editBtns) setClass(b, 'disabled', !a);
  setClass(editBtns[1], 'disabled', !a || !ui.autoClipboard);
  setText(simpText, `SIMPLIFY ${ui.autoSimplify}%`);
  simpFill.style.width = `${ui.autoSimplify}%`;
  setClass(simpBox, 'live', canResimplify());
  setText(countText, a ? `${a.points.length}\npts` : '');
  setClass(note, 'hidden', !!a);
  setText(note, !isTrack ? 'Select a track to automate its knobs.' : 'No automation in this pattern — tap + to add one.');

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
      const y = evalAuto(a.points, pxToX(px), stepped) ?? 0;
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
