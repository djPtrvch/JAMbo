// Сетка паттернов 8×8 (вместо центра экрана по кнопке PATTERNS): столбцы совпадают с дорожками,
// строки — ячейки. В ячейке миниатюра паттерна (страницы строками, триги точками).
// Тап по ячейке выбирает дорожку и запускает её паттерн, когда текущий доиграет:
// пустая ячейка — новый паттерн с копией звука дорожки; играющая — остановка дорожки;
// повторный тап по ожидающей ячейке отменяет запуск.
// Свайп вверх по ячейке — меню duplicate / copy / paste / delete. Перетаскивание паттерна на
// другую ячейку (в любом столбце) кладёт туда его копию: в пустую — новый, в занятую — вместо.
// Колонка строк (сцен) над MIX: тап запускает всю строку (пустые ячейки останавливают дорожку;
// во время проигрывания — с начала такта), удержание — меню: имя строки и число повторов, после
// которых играет следующая строка (∞ — без перехода).

import { PATTERN_SLOTS, STEPS_PER_PAGE, TRACK_COUNT } from '../params';
import {
  rowFilled, sceneName, setScene,
  copyPattern, createPattern, dropPattern, deletePattern, doc, duplicatePattern, freeSlotAfter, hasLocks, pastePattern,
  playRange, rt, selectTrack, slotFilled, ui, type Pattern,
} from '../state';
import { queuePattern, queueScene, sceneProgress } from '../transport';
import { h, setAttr, setClass, setText, svg } from './dom';
import { makePopup, popupButton, type Popup } from './popup';

const SWIPE_PX = 24;
const HOLD_MS = 500;

interface SceneCell { root: HTMLElement; name: HTMLElement; reps: HTMLElement; bar: HTMLElement }
const sceneCells: SceneCell[] = [];
let sceneMenu: Popup;
let sceneInput: HTMLInputElement;
let sceneReps: HTMLElement;
let sceneRow = -1;
let sceneRepsValue = 0;

const fmtReps = (n: number) => (n === 0 ? '∞' : `×${n}`);

function buildSceneMenu() {
  sceneMenu = makePopup('scene-menu');
  sceneInput = h('input', 'rename-input');
  sceneInput.type = 'text';
  sceneInput.maxLength = 12;
  sceneInput.placeholder = 'имя';
  const row = h('div', 'scene-reps-row');
  const minus = popupButton('−', () => { sceneRepsValue = Math.max(0, sceneRepsValue - 1); showReps(); });
  const plus = popupButton('+', () => { sceneRepsValue = Math.min(64, sceneRepsValue + 1); showReps(); });
  sceneReps = h('div', 'scene-reps');
  row.append(h('div', 'scene-reps-label', 'ПОВТОРЫ'), minus, sceneReps, plus);
  const done = () => {
    if (sceneRow >= 0) setScene(sceneRow, sceneInput.value, sceneRepsValue);
    sceneInput.blur();
    sceneMenu.close();
  };
  sceneInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') done(); });
  sceneMenu.box.append(sceneInput, row, popupButton('OK', done));
}

function showReps() {
  setText(sceneReps, fmtReps(sceneRepsValue));
}

function openSceneMenu(k: number) {
  sceneRow = k;
  sceneInput.value = doc.scenes[k].name;
  sceneRepsValue = doc.scenes[k].repeats;
  showReps();
  sceneMenu.openAt(sceneCells[k].root, 260);
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
  sceneCells.push({ root, name, reps, bar });
  return root;
}

interface Cell { root: HTMLElement; bar: HTMLElement; thumb: SVGSVGElement; sig: string }
const cells: Cell[][] = [];
let grid: HTMLElement;
let menu: Popup;
let menuCell: [number, number] | null = null;
const menuButtons: Record<string, HTMLButtonElement> = {};

function tapCell(i: number, k: number) {
  const t = doc.tracks[i];
  selectTrack(i);
  if (!slotFilled(t, k)) {
    createPattern(i, k);
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
  for (let k = 0; k < PATTERN_SLOTS; k++) grid.append(buildSceneCell(k));
  for (let k = 0; k < PATTERN_SLOTS; k++) {
    for (let i = 0; i < TRACK_COUNT; i++) {
      const root = h('div', 'pattern-cell');
      // Столбцы сетки стоят ровно над дорожками (первый столбец — над MIX, строки).
      root.style.gridColumn = String(i + 2);
      root.style.gridRow = String(k + 1);
      const thumb = svg('svg', { class: 'pattern-thumb', preserveAspectRatio: 'none' });
      const bar = h('div', 'pattern-bar');
      root.append(thumb, bar);
      let id = -1;
      let startY = 0;
      root.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        root.setPointerCapture(e.pointerId);
        id = e.pointerId;
        startY = e.clientY;
      });
      root.addEventListener('pointermove', (e) => {
        if (e.pointerId !== id) return;
        const target = slotFilled(doc.tracks[i], k) ? cellAt(e.clientX, e.clientY) : null;
        setDropTarget(target && (target[0] !== i || target[1] !== k) ? target : null);
      });
      const finish = (e: PointerEvent, cancelled: boolean) => {
        if (e.pointerId !== id) return;
        id = -1;
        const target = dropTarget;
        setDropTarget(null);
        if (cancelled) return;
        // Короткий свайп вверх в ячейку над собой — это меню, а не перетаскивание.
        const swipe = startY - e.clientY > SWIPE_PX && startY - e.clientY < root.offsetHeight * 0.9;
        if (target && !(swipe && target[0] === i && target[1] === k - 1)) dropPattern(i, k, target[0], target[1]);
        else if (startY - e.clientY > SWIPE_PX) openMenu(i, k);
        else tapCell(i, k);
      };
      root.addEventListener('pointerup', (e) => finish(e, false));
      root.addEventListener('pointercancel', (e) => finish(e, true));
      (cells[i] ??= []).push({ root, bar, thumb, sig: '' });
      grid.append(root);
    }
  }
  return grid;
}

/** Миниатюра: строка на страницу, точка на триг (жёлтая — с p-lock). */
function drawThumb(c: Cell, p: Pattern | null) {
  let sig = '';
  if (p) {
    sig = `${p.pages.length}:${p.length}:`;
    p.pages.forEach((pg) => pg.forEach((s) => { sig += s.on ? (hasLocks(s) ? 'y' : 'x') : '.'; }));
  }
  if (sig === c.sig) return;
  c.sig = sig;
  c.thumb.replaceChildren();
  if (!p) return;
  // Не меньше 4 строк по высоте, чтобы точки одной страницы не растягивались; по центру.
  const rows = p.pages.length;
  const height = Math.max(rows, 4);
  const top = (height - rows) / 2;
  setAttr(c.thumb, 'viewBox', `0 0 ${STEPS_PER_PAGE} ${height}`);
  p.pages.forEach((pg, r) => pg.forEach((s, col) => {
    const outside = r * STEPS_PER_PAGE + col >= p.length;
    const cls = s.on ? (hasLocks(s) ? 'pt-dot plock' : 'pt-dot on') : 'pt-dot';
    c.thumb.append(svg('rect', {
      x: col + 0.15, y: top + r + 0.15, width: 0.7, height: 0.7, class: outside ? `${cls} outside` : cls,
    }));
  }));
}

export function renderPatternGrid() {
  setClass(grid, 'hidden', !ui.patternView);
  if (!ui.patternView) return;
  if (!menu.isOpen()) menuCell = null;
  const prog = sceneProgress();
  sceneCells.forEach((c, k) => {
    const sc = doc.scenes[k];
    const playing = rt.scene?.row === k && ui.playing;
    setText(c.name, sceneName(k));
    // Повторы: у играющей строки — номер прохода.
    setText(c.reps, playing && prog && sc.repeats > 0 ? `${Math.min(prog.pass + 1, sc.repeats)}/${sc.repeats}` : fmtReps(sc.repeats));
    setClass(c.root, 'filled', rowFilled(k));
    setClass(c.root, 'active', rt.scene?.row === k);
    setClass(c.root, 'queued', rt.sceneQueued === k);
    setAttr(c.bar, 'style', `width:${playing && prog ? Math.round(prog.frac * 100) : 0}%`);
  });
  doc.tracks.forEach((t, i) => {
    const q = rt.queued[i];
    cells[i].forEach((c, k) => {
      const filled = slotFilled(t, k);
      const active = k === t.slot;
      setClass(c.root, 'filled', filled);
      setClass(c.root, 'active', active && !t.stopped);
      setClass(c.root, 'queued', q === k);
      setClass(c.root, 'stopping', active && q === 'stop');
      setClass(c.root, 'selected-col', i === ui.selectedTrack);
      drawThumb(c, active ? t : t.slots[k]);
      // Прогресс проигрывания активного паттерна.
      let progress = 0;
      if (active && !t.stopped && ui.playing && rt.playPos[i] >= 0) {
        const [a, b] = playRange(t);
        progress = (rt.playPos[i] - a + 1) / (b - a + 1);
      }
      setAttr(c.bar, 'style', `width:${Math.round(progress * 100)}%`);
    });
  });
}
