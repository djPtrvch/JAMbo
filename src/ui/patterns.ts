// Сетка паттернов 8×8 (вместо центра экрана по кнопке PATTERNS): столбцы совпадают с дорожками,
// строки — ячейки. В ячейке миниатюра паттерна (страницы строками, триги точками).
// Тап по ячейке выбирает дорожку и запускает её паттерн, когда текущий доиграет:
// пустая ячейка — новый паттерн с копией звука дорожки; играющая — остановка дорожки;
// повторный тап по ожидающей ячейке отменяет запуск.
// Быстрый свайп вверх по ячейке — меню duplicate / copy / paste / delete. Медленное перетаскивание
// паттерна (копия едет за пальцем) на другую ячейку в любом столбце кладёт туда его копию:
// в пустую — новый, в занятую — вместо прежнего; копия плавно встаёт на место.
// Колонка строк (сцен) над MIX: тап запускает всю строку (пустые ячейки останавливают дорожку;
// во время проигрывания — с начала такта), удержание — меню: имя строки и число повторов, после
// которых играет следующая строка (∞ — без перехода).

import { MAX_TRACKS, PATTERN_SLOTS, STEPS_PER_PAGE } from '../params';
import {
  crossfade, inTransition, isPrevPlaceholder, rowFilled, sceneName, setCrossfade, setScene, transitionMoves,
  addSceneRow, canAddRow, copyRow, deleteRow, duplicateRow, pasteRow, setArrangement, rowLoopOn, setPlusMode, toggleRowLoop, visibleRows,
  copyPattern, createPattern, dropPattern, deletePattern, doc, duplicatePattern, freeSlotAfter, hasManualLocks, tailMask, pastePattern,
  clipView, openSlot, selectEmptySlot, setEditSlot, outsideStep, passOffset, playLen, rt, selectTrack, slotFilled, ui, patternHasAuto,
} from '../state';
import { queuePattern, queueScene, sceneProgress } from '../transport';
import { registerAction } from '../midi';
import { autoBadge, h, setAttr, setClass, setText, svg } from './dom';
import { makePopup, popupButton, type Popup } from './popup';

const SWIPE_PX = 24;
/** Сдвиг, после которого паттерн берётся пальцем; быстрый свайп вверх короче FLICK_MS — меню. */
const DRAG_PX = 12;
const FLICK_MS = 280;
const HOLD_MS = 500;

interface SceneCell { root: HTMLElement; name: HTMLElement; reps: HTMLElement; bar: HTMLElement }
const sceneCells: SceneCell[] = [];
let sceneMenu: Popup;
let sceneInput: HTMLInputElement;
let sceneReps: HTMLElement;
let sceneRow = -1;
let sceneRepsValue = 0;
const rowActs: Record<string, HTMLButtonElement> = {};

const fmtReps = (n: number) => (n === 0 ? '∞' : `×${n}`);

function buildSceneMenu() {
  sceneMenu = makePopup('scene-menu');
  sceneInput = h('input', 'rename-input');
  sceneInput.type = 'text';
  sceneInput.maxLength = 12;
  sceneInput.placeholder = 'name';
  const row = h('div', 'scene-reps-row');
  const minus = popupButton('−', () => { sceneRepsValue = Math.max(1, sceneRepsValue - 1); showReps(); });
  const plus = popupButton('+', () => { sceneRepsValue = Math.min(64, sceneRepsValue + 1); showReps(); });
  sceneReps = h('div', 'scene-reps');
  row.append(h('div', 'scene-reps-label', 'REPEATS'), minus, sceneReps, plus);
  const done = () => {
    if (sceneRow >= 0) setScene(sceneRow, sceneInput.value, sceneRepsValue);
    sceneInput.blur();
    sceneMenu.close();
  };
  sceneInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') done(); });
  // DUPLICATE (копия строки сразу под ней), COPY, PASTE, DELETE (строки ниже сдвигаются вверх).
  const acts = h('div', 'scene-acts');
  const act = (label: string, fn: (k: number) => void) => {
    const b = popupButton(label, () => { const k = sceneRow; sceneInput.blur(); sceneMenu.close(); if (k >= 0) fn(k); });
    rowActs[label] = b;
    acts.append(b);
  };
  act('DUPLICATE', duplicateRow);
  act('COPY', copyRow);
  act('PASTE', pasteRow);
  act('DELETE', deleteRow);
  sceneMenu.box.append(sceneInput, row, acts, popupButton('OK', done));
}

function showReps() {
  setText(sceneReps, fmtReps(sceneRepsValue));
}

function openSceneMenu(k: number) {
  sceneRow = k;
  sceneInput.value = doc.scenes[k].name;
  sceneRepsValue = doc.scenes[k].repeats;
  showReps();
  rowActs.DUPLICATE.disabled = !canAddRow() || inTransition();
  rowActs.PASTE.disabled = !ui.rowClipboard;
  rowActs.DELETE.disabled = inTransition();
  // Меню строки — шириной от колонки строк до правого края первой дорожки; может лечь на дорожки.
  openSpan(sceneMenu, sceneCells[k].root, sceneCells[k].root, cells[0][k].root, true);
}

/** Ячейка строки (сцены) в колонке над MIX. */
function buildSceneCell(k: number): HTMLElement {
  const root = h('div', 'pattern-cell scene-cell');
  root.style.gridColumn = '1';
  root.style.gridRow = String(k + 1);
  const name = h('div', 'scene-name');
  const reps = h('div', 'scene-reps-badge');
  const bar = h('div', 'pattern-bar');
  root.append(name, reps, bar);
  let id = -1;
  let timer = 0;
  let held = false;
  root.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    root.setPointerCapture(e.pointerId);
    id = e.pointerId;
    held = false;
    timer = window.setTimeout(() => { held = true; openSceneMenu(k); }, HOLD_MS);
  });
  const finish = (e: PointerEvent, cancelled: boolean) => {
    if (e.pointerId !== id) return;
    id = -1;
    clearTimeout(timer);
    if (!cancelled && !held) queueScene(k);
  };
  root.addEventListener('pointerup', (e) => finish(e, false));
  root.addEventListener('pointercancel', (e) => finish(e, true));
  // MIDI: запуск строки (для Clip launcher).
  registerAction(`ROW${k + 1}`, { label: `ROW ${k + 1}`, press: () => queueScene(k), state: () => rt.scene?.row === k }, root);
  sceneCells.push({ root, name, reps, bar });
  return root;
}

interface Cell { root: HTMLElement; bar: HTMLElement; thumb: SVGSVGElement; sig: string; wave: HTMLElement }
const cells: Cell[][] = [];
let grid: HTMLElement;
let menu: Popup;
let menuCell: [number, number] | null = null;
const menuButtons: Record<string, HTMLButtonElement> = {};

/** Короткая вспышка ячейки: действие сейчас недоступно. */
function flashCell(root: HTMLElement) {
  root.classList.remove('deny');
  void root.offsetWidth;
  root.classList.add('deny');
  window.setTimeout(() => root.classList.remove('deny'), 400);
}

function tapCell(i: number, k: number) {
  const t = doc.tracks[i];
  // Пустая заглушка строки PREV не запускается.
  if (isPrevPlaceholder(i, k)) return;
  selectTrack(i);
  setEditSlot(i, k);
  if (!slotFilled(t, k)) {
    // Новый клип — пустой паттерн (новая страница), сразу открыт в секвенсоре; страниц больше нет — вспышка.
    if (!createPattern(i, k)) { flashCell(cells[i][k].root); return; }
    queuePattern(i, k);
  } else if (k === t.slot && !t.stopped) {
    queuePattern(i, 'stop');
  } else {
    queuePattern(i, k);
  }
}

function openMenu(i: number, k: number) {
  const t = doc.tracks[i];
  const filled = slotFilled(t, k);
  menuCell = [i, k];
  menuButtons.duplicate.disabled = !filled || freeSlotAfter(t, k) < 0;
  menuButtons.copy.disabled = !filled;
  menuButtons.paste.disabled = !ui.patternClipboard;
  menuButtons.delete.disabled = !filled;
  menu.openAt(cells[i][k].root, 180);
}

function buildMenu() {
  menu = makePopup();
  const actions: [string, (i: number, k: number) => void][] = [
    ['duplicate', duplicatePattern], ['copy', copyPattern], ['paste', pastePattern], ['delete', deletePattern],
  ];
  for (const [name, fn] of actions) {
    const b = popupButton(name.toUpperCase(), () => {
      const c = menuCell;
      menu.close();
      menuCell = null;
      if (c) fn(c[0], c[1]);
    });
    menuButtons[name] = b;
    menu.box.append(b);
  }
}

let dropTarget: [number, number] | null = null;

// ---------- Строка «+» и меню сетки (бутерброд справа) ----------

let scenePlus: HTMLElement;

/** «+» под последней видимой строкой — только в колонке строк: новая строка (пустая или с копиями
 * играющих паттернов — по меню сетки). */
function buildPlusRow(): HTMLElement {
  scenePlus = h('div', 'pattern-cell plus-cell', '+');
  scenePlus.style.gridColumn = '1';
  // Тап (отпустили, не сдвинув палец) — строка по настройке + ADDS (меню сетки).
  let id = -1, x0 = 0, y0 = 0;
  scenePlus.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    id = e.pointerId; x0 = e.clientX; y0 = e.clientY;
  });
  scenePlus.addEventListener('pointermove', (e) => {
    if (e.pointerId === id && Math.hypot(e.clientX - x0, e.clientY - y0) > 10) id = -1;
  });
  const end = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = -1;
    if (e.type === 'pointerup') addSceneRow();
  };
  scenePlus.addEventListener('pointerup', end);
  scenePlus.addEventListener('pointercancel', end);
  return scenePlus;
}

let arrBtn: HTMLElement;
let loopBtn: HTMLElement;

/** Под бутербродом — LOOP ROW (значок лупа): играющая строка повторяется бесконечно; жёлтая, пока включена. */
function buildLoopButton(): HTMLElement {
  loopBtn = h('div', 'btn row-loop-btn');
  loopBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 2l3 3-3 3"/><path d="M4 11V9a4 4 0 0 1 4-4h12"/><path d="M7 22l-3-3 3-3"/><path d="M20 13v2a4 4 0 0 1-4 4H4"/></svg>';
  loopBtn.style.gridRow = '2';
  loopBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleRowLoop(); });
  return loopBtn;
}

/** Открыть окно под (или над) anchor, по горизонтали — от левого края from до правого края to. */
function openSpan(p: Popup, anchor: Element, from: Element, to: Element, overTracks = false) {
  const l = from.getBoundingClientRect().left;
  const r = to.getBoundingClientRect().right;
  p.box.style.maxHeight = '';
  p.openAt(anchor, r - l);
  p.box.style.left = `${l}px`;
  // По высоте — между верхом сетки и строкой дорожек (overTracks — в пределах окна, поверх дорожек);
  // что не помещается — прокрутка. Под ячейкой, если там хватает места (или его там больше), иначе над ней.
  const a = anchor.getBoundingClientRect();
  const top = overTracks ? 8 : sceneCells[0].root.getBoundingClientRect().top;
  const bottom = overTracks ? window.innerHeight - 8 : (document.querySelector('.tracks')?.getBoundingClientRect().top ?? window.innerHeight) - 6;
  const below = bottom - (a.bottom + 6);
  const above = a.top - 6 - top;
  const hgt = p.box.scrollHeight;
  const down = hgt <= below || below >= above;
  const room = down ? below : above;
  p.box.style.maxHeight = `${room}px`;
  p.box.style.top = `${down ? a.bottom + 6 : a.top - 6 - Math.min(hgt, room)}px`;
}
let arrMenu: Popup;

/** Бутерброд справа от сетки: строка старта (с неё начинается PLAY) и что в конце строк — STOP или LOOP. */
function buildArrangeButton(): HTMLElement {
  arrBtn = h('div', 'btn arrange-btn');
  const lines = h('div', 'burger-lines');
  lines.append(h('span'), h('span'), h('span'));
  arrBtn.append(lines);
  arrBtn.style.gridRow = '1';
  arrMenu = makePopup('arrange-menu');
  arrBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); openArrangeMenu(); });
  return arrBtn;
}

function openArrangeMenu() {
  const start = Math.min(doc.arrStart ?? 0, visibleRows() - 1);
  const end = doc.arrEnd ?? 'loop';
  const startRow = h('div', 'arrange-row');
  for (let k = 0; k < visibleRows(); k++) {
    const b = popupButton(sceneName(k), () => { setArrangement(k, end); openArrangeMenu(); });
    b.classList.toggle('current', k === start);
    startRow.append(b);
  }
  // Что делает «+»: пустая строка или строка с копиями играющих паттернов.
  const plus = doc.plusMode ?? 'copy';
  const plusRow = h('div', 'arrange-row');
  for (const [v, label] of [['empty', 'NEW PATTERNS'], ['copy', 'COPY PLAYING']] as const) {
    const b = popupButton(label, () => { setPlusMode(v); openArrangeMenu(); });
    b.classList.toggle('current', v === plus);
    plusRow.append(b);
  }
  const endRow = h('div', 'arrange-row');
  for (const v of ['stop', 'loop'] as const) {
    const b = popupButton(v.toUpperCase(), () => { setArrangement(start, v); openArrangeMenu(); });
    b.classList.toggle('current', v === end);
    endRow.append(b);
  }
  const scroll = arrMenu.isOpen() ? arrMenu.box.scrollTop : 0;
  arrMenu.box.replaceChildren(
    h('div', 'popup-title', 'START FROM ROW'), startRow,
    h('div', 'popup-title', 'AT THE END'), endRow,
    h('div', 'popup-title', '+ ADDS'), plusRow,
  );
  // Меню сетки — от левого края последней дорожки до правого края бутерброда.
  openSpan(arrMenu, arrBtn, cells[doc.tracks.length - 1][0].root, arrBtn);
  arrMenu.box.scrollTop = scroll;
}

// ---------- Кроссфейдер перехода между проектами (справа от сетки, над MST) ----------

let xf: HTMLElement;
let xfThumb: HTMLElement;
let xfFill: HTMLElement;

/** Вертикальный кроссфейдер: внизу — общие настройки старого проекта, вверху — нового. */
function buildCrossfader(): HTMLElement {
  xf = h('div', 'xfader hidden');
  xf.style.gridRow = `1 / ${PATTERN_SLOTS + 1}`;
  const track = h('div', 'xf-track');
  xfFill = h('div', 'xf-fill');
  xfThumb = h('div', 'xf-thumb');
  track.append(xfFill, xfThumb);
  // Без надписей: внизу — старый проект, вверху — новый.
  xf.append(track);
  let id = -1;
  const setFrom = (y: number) => {
    const r = track.getBoundingClientRect();
    setCrossfade(1 - (y - r.top) / r.height);
  };
  xf.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    xf.setPointerCapture(e.pointerId);
    id = e.pointerId;
    setFrom(e.clientY);
  });
  xf.addEventListener('pointermove', (e) => { if (e.pointerId === id) setFrom(e.clientY); });
  const up = (e: PointerEvent) => { if (e.pointerId === id) id = -1; };
  xf.addEventListener('pointerup', up);
  xf.addEventListener('pointercancel', up);
  return xf;
}

function renderCrossfader() {
  const pos = crossfade();
  setClass(xf, 'hidden', pos === null);
  if (pos === null) return;
  const pct = `${(pos * 100).toFixed(1)}%`;
  setAttr(xfThumb, 'style', `bottom:${pct}`);
  setAttr(xfFill, 'style', `height:${pct}`);
}

/** Анимация: старые паттерны опускаются в нижнюю строку, остальные ячейки проявляются. */
function animateTransition() {
  if (!transitionMoves.length) return;
  const moves = transitionMoves.splice(0);
  if (!ui.patternView) return;
  const last = PATTERN_SLOTS - 1;
  const pitch = cells[0][1].root.offsetTop - cells[0][0].root.offsetTop;
  const moved = new Set(moves.map((m) => m.track));
  cells.forEach((col, i) => col.forEach((c, k) => {
    if (k === last && moved.has(i)) return;
    c.root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 450, easing: 'ease-out' });
  }));
  for (const m of moves) {
    const dy = (m.from - last) * pitch;
    cells[m.track][last].root.animate(
      [{ transform: `translateY(${dy}px)`, zIndex: 2 }, { transform: 'none', zIndex: 2 }],
      { duration: 650, easing: 'cubic-bezier(.2,.8,.2,1)' },
    );
  }
}

/** Ячейка паттерна под точкой экрана: [дорожка, строка] или null. */
function cellAt(x: number, y: number): [number, number] | null {
  for (let i = 0; i < cells.length; i++) {
    for (let k = 0; k < cells[i].length; k++) {
      const r = cells[i][k].root.getBoundingClientRect();
      if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) return [i, k];
    }
  }
  return null;
}

/** Копия ячейки поверх экрана — едет за пальцем; исходная ячейка бледнеет. */
function liftCell(root: HTMLElement): HTMLElement {
  const r = root.getBoundingClientRect();
  const g = root.cloneNode(true) as HTMLElement;
  g.classList.add('drag-ghost');
  g.classList.remove('drop-target', 'queued', 'stopping');
  Object.assign(g.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
  document.body.append(g);
  root.classList.add('lifted');
  return g;
}

/** Копия плавно встаёт в ячейку to (или возвращается на место) и исчезает. */
function dropGhost(g: HTMLElement, from: HTMLElement, to: HTMLElement) {
  const a = from.getBoundingClientRect();
  const b = to.getBoundingClientRect();
  const end = `translate(${b.left - a.left}px, ${b.top - a.top}px) scale(1)`;
  const anim = g.animate([{ transform: g.style.transform || 'none' }, { transform: end }], { duration: 220, easing: 'cubic-bezier(.2,.8,.2,1)', fill: 'forwards' });
  anim.onfinish = () => {
    g.remove();
    from.classList.remove('lifted');
    if (to !== from) to.animate([{ boxShadow: 'inset 0 0 0 2px var(--plock)' }, { boxShadow: 'inset 0 0 0 0 transparent' }], { duration: 400 });
  };
}

/** Подсветка ячейки, куда упадёт перетаскиваемый паттерн. */
function setDropTarget(t: [number, number] | null) {
  if (dropTarget) cells[dropTarget[0]][dropTarget[1]].root.classList.remove('drop-target');
  dropTarget = t;
  if (t) cells[t[0]][t[1]].root.classList.add('drop-target');
}

export function buildPatternGrid(): HTMLElement {
  buildMenu();
  buildSceneMenu();
  grid = h('div', 'pattern-grid hidden');
  grid.append(buildCrossfader(), buildArrangeButton(), buildLoopButton(), buildPlusRow());
  for (let k = 0; k < PATTERN_SLOTS; k++) grid.append(buildSceneCell(k));
  for (let k = 0; k < PATTERN_SLOTS; k++) {
    for (let i = 0; i < MAX_TRACKS; i++) {
      const root = h('div', 'pattern-cell');
      // Столбцы сетки стоят ровно над дорожками (первый столбец — над MIX, строки).
      root.style.gridColumn = String(i + 2);
      root.style.gridRow = String(k + 1);
      const thumb = svg('svg', { class: 'pattern-thumb', preserveAspectRatio: 'none' });
      // MIDI: ячейка как тап (запуск, остановка, новый паттерн) — для Clip launcher.
      registerAction(`CLIP${i + 1}.${k + 1}`, {
        label: `CLIP T${i + 1} · ${k + 1}`, press: () => tapCell(i, k),
        state: () => !!doc.tracks[i] && doc.tracks[i].slot === k && !doc.tracks[i].stopped,
      }, root);
      const bar = h('div', 'pattern-bar');
      // Значок волны: в паттерне есть автоматизация.
      const wave = autoBadge();
      root.append(thumb, bar, wave);
      let id = -1;
      let x0 = 0;
      let y0 = 0;
      let t0 = 0;
      let ghost: HTMLElement | null = null;
      // Удержание паттерна без движения — открыть его для правки без запуска.
      let holdTimer = 0;
      let held = false;
      root.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        root.setPointerCapture(e.pointerId);
        id = e.pointerId;
        x0 = e.clientX;
        y0 = e.clientY;
        t0 = performance.now();
        ghost = null;
        held = false;
        clearTimeout(holdTimer);
        holdTimer = window.setTimeout(() => {
          if (id !== e.pointerId || ghost || isPrevPlaceholder(i, k)) return;
          held = true;
          selectTrack(i);
          // Пустая ячейка — только выбирается (паттерн не создаётся); заполненная — правка без запуска.
          if (!slotFilled(doc.tracks[i], k)) { selectEmptySlot(i, k); ui.editSlot = k; }
          else if (!openSlot(i, k)) flashCell(root);
          else ui.editSlot = k;
        }, HOLD_MS);
      });
      root.addEventListener('pointermove', (e) => {
        if (e.pointerId !== id) return;
        const dx = e.clientX - x0;
        const dy = e.clientY - y0;
        // Паттерн с ячейки «берётся» пальцем: копия ячейки едет за ним.
        if (Math.hypot(dx, dy) > DRAG_PX) clearTimeout(holdTimer);
        if (held) return;
        // Быстрый свайп вверх (меню) ячейку не поднимает: пока не прошло FLICK_MS, движение вверх — ещё
        // возможный свайп; дальше палец «берёт» паттерн.
        const early = performance.now() - t0 < FLICK_MS && -dy > Math.abs(dx);
        if (!ghost && !early && slotFilled(doc.tracks[i], k) && !isPrevPlaceholder(i, k) && Math.hypot(dx, dy) > DRAG_PX) ghost = liftCell(root);
        if (!ghost) return;
        ghost.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
        const target = cellAt(e.clientX, e.clientY);
        setDropTarget(target && (target[0] !== i || target[1] !== k) ? target : null);
      });
      const finish = (e: PointerEvent, cancelled: boolean) => {
        if (e.pointerId !== id) return;
        id = -1;
        clearTimeout(holdTimer);
        if (held) return;
        const target = dropTarget;
        setDropTarget(null);
        const dx = e.clientX - x0;
        const dy = e.clientY - y0;
        // Быстрый свайп вверх — меню (на любой ячейке), медленное движение — перетаскивание.
        const flick = performance.now() - t0 < FLICK_MS && -dy > SWIPE_PX && Math.abs(dx) < -dy;
        const g = ghost;
        ghost = null;
        if (cancelled) { if (g) dropGhost(g, root, root); return; }
        if (flick) { if (g) dropGhost(g, root, root); openMenu(i, k); return; }
        if (g) {
          if (target) {
            dropGhost(g, root, cells[target[0]][target[1]].root);
            dropPattern(i, k, target[0], target[1]);
          } else dropGhost(g, root, root);
          return;
        }
        if (Math.hypot(dx, dy) <= DRAG_PX) tapCell(i, k);
      };
      root.addEventListener('pointerup', (e) => finish(e, false));
      root.addEventListener('pointercancel', (e) => finish(e, true));
      (cells[i] ??= []).push({ root, bar, thumb, sig: '', wave });
      grid.append(root);
    }
  }
  return grid;
}

/** Миниатюра: строка на страницу, точка на триг (жёлтая — с ручными p-lock, обведённая — свой звук шага). */
function drawThumb(c: Cell, p: ReturnType<typeof clipView>) {
  let sig = '';
  if (p) {
    sig = `${p.pages.length}:${p.lens.join(',')}:${p.playFrom}:${p.playTo}:`;
    p.pages.forEach((pg) => pg.forEach((s) => { sig += s.on ? (hasManualLocks(s) ? 'y' : 'x') + (s.sound ? 's' : '') + s.len : '.'; }));
  }
  if (sig === c.sig) return;
  c.sig = sig;
  c.thumb.replaceChildren();
  if (!p) return;
  // Только играющие страницы (как выбраны в миниатюрах дорожки). Не меньше 4 строк по высоте,
  // чтобы точки одной страницы не растягивались; по центру.
  const from = Math.min(p.playFrom, p.pages.length - 1), to = Math.min(Math.max(p.playTo, from), p.pages.length - 1);
  const rows = to - from + 1;
  const tails = tailMask(p.pages);
  const height = Math.max(rows, 4);
  const top = (height - rows) / 2;
  setAttr(c.thumb, 'viewBox', `0 0 ${STEPS_PER_PAGE} ${height}`);
  p.pages.slice(from, to + 1).forEach((pg, r) => pg.forEach((s, col) => {
    const index = (from + r) * STEPS_PER_PAGE + col;
    const outside = outsideStep(p, index);
    // Жёлтая — ручные p-lock, обведённая — свой звук шага (сэмпл, пресет), полупрозрачная — хвост длинной ноты.
    const cls = s.on ? (hasManualLocks(s) ? 'pt-dot plock' : 'pt-dot on') + (s.sound ? ' own-sound' : '') : tails[index] ? 'pt-dot tail' : 'pt-dot';
    c.thumb.append(svg('rect', {
      x: col + 0.15, y: top + r + 0.15, width: 0.7, height: 0.7, class: outside ? `${cls} outside` : cls,
    }));
  }));
}

export function renderPatternGrid() {
  setClass(grid, 'hidden', !ui.patternView);
  if (!ui.patternView) return;
  if (!menu.isOpen()) menuCell = null;
  renderCrossfader();
  animateTransition();
  const prog = sceneProgress();
  sceneCells.forEach((c, k) => {
    const sc = doc.scenes[k];
    const playing = rt.scene?.row === k && ui.playing;
    setText(c.name, sceneName(k));
    // Повторы: у играющей строки — номер прохода.
    setText(c.reps, playing && rowLoopOn() ? '∞' : playing && prog && sc.repeats > 0 ? `${Math.min(prog.pass + 1, sc.repeats)}/${sc.repeats}` : fmtReps(sc.repeats));
    setClass(c.root, 'filled', rowFilled(k));
    setClass(c.root, 'active', rt.scene?.row === k);
    setClass(c.root, 'queued', rt.sceneQueued === k);
    setAttr(c.bar, 'style', `width:${playing && prog ? Math.round(prog.frac * 100) : 0}%`);
  });
  // Столбцов столько, сколько дорожек; справа от последнего — бутерброд, под ним кроссфейдер.
  const last = doc.tracks.length + 2;
  // При переходе MIX бутерброда нет — кроссфейдер во всю высоту, как раньше.
  const mixing = crossfade() !== null;
  setAttr(xf, 'style', `grid-column:${last};grid-row:${mixing ? 1 : 3} / ${PATTERN_SLOTS + 1}`);
  arrBtn.style.gridColumn = String(last);
  setClass(arrBtn, 'hidden', mixing);
  loopBtn.style.gridColumn = String(last);
  setClass(loopBtn, 'hidden', mixing);
  setClass(loopBtn, 'on', rowLoopOn());
  if (mixing && arrMenu.isOpen()) arrMenu.close();
  // Видны строки 1…visibleRows (при переходе MIX — и строка PREV внизу), под ними — «+».
  const rows = visibleRows();
  const shown = (k: number) => k < rows || (inTransition() && k === PATTERN_SLOTS - 1);
  sceneCells.forEach((c, k) => setClass(c.root, 'hidden', !shown(k)));
  cells.forEach((col, i) => col.forEach((c, k) => setClass(c.root, 'hidden', i >= doc.tracks.length || !shown(k))));
  const plus = canAddRow();
  setClass(scenePlus, 'hidden', !plus);
  scenePlus.style.gridRow = String(rows + 1);
  doc.tracks.forEach((t, i) => {
    const q = rt.queued[i];
    cells[i].forEach((c, k) => {
      // Во время перехода нижняя строка (PREV) у дорожки без старого паттерна — пустая заглушка.
      const filled = slotFilled(t, k) && !isPrevPlaceholder(i, k);
      const active = k === t.slot;
      setClass(c.root, 'filled', filled);
      setClass(c.root, 'active', active && !t.stopped);
      setClass(c.root, 'queued', q === k);
      setClass(c.root, 'stopping', active && q === 'stop');
      setClass(c.root, 'selected-col', i === ui.selectedTrack);
      // Выбранная для правки — белая обводка и светлее; клип с пустым паттерном — пунктир.
      setClass(c.root, 'editing', i === ui.selectedTrack && ui.channel === 'track' && k === ui.editSlot && !isPrevPlaceholder(i, k));
      const view = filled ? clipView(t, k) : null;
      drawThumb(c, view);
      setClass(c.root, 'empty-pattern', !!view && !view.pages.slice(view.playFrom, view.playTo + 1).some((pg) => pg.some((s) => s.on)));
      setClass(c.wave, 'hidden', !view || !patternHasAuto(view));
      // Прогресс проигрывания активного паттерна.
      let progress = 0;
      if (active && !t.stopped && ui.playing && rt.playPos[i] >= 0) {
        progress = (passOffset(t, rt.playPos[i]) + 1) / playLen(t);
      }
      setAttr(c.bar, 'style', `width:${Math.round(progress * 100)}%`);
    });
  });
}
