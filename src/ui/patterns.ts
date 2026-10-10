// Сетка паттернов 8×8 (вместо центра экрана по кнопке PATTERNS): столбцы совпадают с дорожками,
// строки — ячейки. В ячейке миниатюра паттерна (страницы строками, триги точками).
// Тап по ячейке выбирает дорожку и запускает её паттерн, когда текущий доиграет:
// пустая ячейка — новый паттерн с копией звука дорожки; играющая — остановка дорожки;
// повторный тап по ожидающей ячейке отменяет запуск.
// Свайп вверх по ячейке — меню duplicate / copy / paste / delete.

import { PATTERN_SLOTS, STEPS_PER_PAGE, TRACK_COUNT } from '../params';
import {
  copyPattern, createPattern, deletePattern, doc, duplicatePattern, freeSlotAfter, hasLocks, pastePattern,
  playRange, rt, selectTrack, slotFilled, ui, type Pattern,
} from '../state';
import { queuePattern } from '../transport';
import { h, setAttr, setClass, svg } from './dom';
import { makePopup, popupButton, type Popup } from './popup';

const SWIPE_PX = 24;

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

export function buildPatternGrid(): HTMLElement {
  buildMenu();
  grid = h('div', 'pattern-grid hidden');
  for (let k = 0; k < PATTERN_SLOTS; k++) {
    for (let i = 0; i < TRACK_COUNT; i++) {
      const root = h('div', 'pattern-cell');
      // Столбцы сетки стоят ровно над дорожками (первый столбец — под MIX, пустой).
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
      const finish = (e: PointerEvent, cancelled: boolean) => {
        if (e.pointerId !== id) return;
        id = -1;
        if (cancelled) return;
        if (startY - e.clientY > SWIPE_PX) openMenu(i, k);
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
