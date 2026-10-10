// Сетка паттернов 8×8 (вместо ручек по кнопке PATTERNS): столбцы — дорожки, строки — ячейки.
// Тап по ячейке выбирает дорожку и запускает её паттерн, когда текущий доиграет:
// пустая ячейка — новый паттерн с копией звука дорожки; играющая — остановка дорожки;
// повторный тап по ожидающей ячейке отменяет запуск.

import { PATTERN_SLOTS, TRACK_COUNT } from '../params';
import { createPattern, doc, playRange, rt, selectTrack, slotFilled, ui } from '../state';
import { queuePattern } from '../transport';
import { h, setAttr, setClass, setText } from './dom';

interface Cell { root: HTMLElement; bar: HTMLElement }
const cells: Cell[][] = [];
const heads: HTMLElement[] = [];
let grid: HTMLElement;

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

export function buildPatternGrid(): HTMLElement {
  grid = h('div', 'pattern-grid hidden');
  for (let i = 0; i < TRACK_COUNT; i++) {
    const head = h('div', 'pattern-head');
    head.style.gridColumn = String(i + 1);
    heads.push(head);
    grid.append(head);
  }
  for (let k = 0; k < PATTERN_SLOTS; k++) {
    for (let i = 0; i < TRACK_COUNT; i++) {
      const root = h('div', 'pattern-cell');
      const bar = h('div', 'pattern-bar');
      root.append(bar);
      root.addEventListener('pointerdown', (e) => { e.preventDefault(); tapCell(i, k); });
      (cells[i] ??= []).push({ root, bar });
      grid.append(root);
    }
  }
  return grid;
}

export function renderPatternGrid() {
  setClass(grid, 'hidden', !ui.patternView);
  if (!ui.patternView) return;
  doc.tracks.forEach((t, i) => {
    setText(heads[i], t.name);
    setClass(heads[i], 'selected', i === ui.selectedTrack);
    const q = rt.queued[i];
    cells[i].forEach((c, k) => {
      const filled = slotFilled(t, k);
      const active = k === t.slot;
      const playing = active && !t.stopped && ui.playing;
      setClass(c.root, 'filled', filled);
      setClass(c.root, 'active', active && !t.stopped);
      setClass(c.root, 'queued', q === k);
      setClass(c.root, 'stopping', active && q === 'stop');
      setClass(c.root, 'selected-col', i === ui.selectedTrack);
      // Прогресс проигрывания активного паттерна.
      let progress = 0;
      if (playing && rt.playPos[i] >= 0) {
        const [a, b] = playRange(t);
        progress = (rt.playPos[i] - a + 1) / (b - a + 1);
      }
      setAttr(c.bar, 'style', `width:${Math.round(progress * 100)}%`);
    });
  });
}
