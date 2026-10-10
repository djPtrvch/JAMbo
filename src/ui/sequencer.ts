// 16-шаговый секвенсор выбранной дорожки (или своей последовательности MIX, MST — только p-lock).
// Тап — триг; нажать и протянуть вправо — длинная нота; удержание шага + ручка — p-lock;
// удержать первый шаг и дважды тапнуть по другому — последний шаг паттерна.

import { STEPS_PER_PAGE, noteName } from '../params';
import {
  beginGesture, curSeq, endGesture, hasLocks, seqIndex, setNoteLength, setPatternLength, stepAt, toggleStep, ui, rt,
} from '../state';
import { DOUBLE_TAP_MS, h, setClass, setText } from './dom';

/** Дольше этого — уже удержание, триг не переключается. */
const TAP_MS = 350;

interface Press {
  id: number;
  col: number;
  index: number;
  t0: number;
  dragged: boolean;
  /** Нажатие, пока удерживается первый шаг (режим длины паттерна). */
  secondary: boolean;
}

const cells: HTMLElement[] = [];
const labels: HTMLElement[] = [];
const presses = new Map<number, Press>();
const lastTap: number[] = Array(STEPS_PER_PAGE).fill(-1e9);
let grid: HTMLElement;

function colAt(x: number, y: number): number {
  const el = document.elementFromPoint(x, y)?.closest('.step') as HTMLElement | null;
  return el && grid.contains(el) ? Number(el.dataset.col) : -1;
}

function firstStepHeld(): Press | undefined {
  for (const p of presses.values()) if (p.col === 0) return p;
  return undefined;
}

export function buildSequencer(): HTMLElement {
  grid = h('div', 'sequencer');
  for (let col = 0; col < STEPS_PER_PAGE; col++) {
    const cell = h('div', 'step');
    cell.dataset.col = String(col);
    if (col % 4 === 0) cell.classList.add('beat');
    const fill = h('div', 'step-fill');
    const label = h('div', 'step-note');
    fill.append(label);
    labels.push(label);
    cell.append(fill);
    cells.push(cell);
    grid.append(cell);

    cell.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      cell.releasePointerCapture?.(e.pointerId);
      const index = ui.viewPage * STEPS_PER_PAGE + col;
      const now = performance.now();
      const first = firstStepHeld();
      const secondary = !!first && col !== 0;
      if (secondary && now - lastTap[col] < DOUBLE_TAP_MS) {
        setPatternLength(index);
        const h0 = ui.heldSteps.get(first!.id);
        if (h0) h0.used = true;
        lastTap[col] = -1e9;
      }
      presses.set(e.pointerId, { id: e.pointerId, col, index, t0: now, dragged: false, secondary });
      ui.heldSteps.set(e.pointerId, { index, used: secondary });
      beginGesture();
    });
  }
  // Движение и отпускание ловим на уровне документа: палец уходит с ячейки при протягивании.
  document.addEventListener('pointermove', onMove);
  document.addEventListener('pointerup', (e) => onUp(e, false));
  document.addEventListener('pointercancel', (e) => onUp(e, true));
  return grid;
}

function onMove(e: PointerEvent) {
  const p = presses.get(e.pointerId);
  if (!p || p.secondary) return;
  const col = colAt(e.clientX, e.clientY);
  if (col < 0) return;
  if (col === p.col && !p.dragged) return;
  if (col < p.col) return;
  p.dragged = true;
  setNoteLength(p.index, col - p.col + 1);
  const held = ui.heldSteps.get(e.pointerId);
  if (held) held.used = true;
}

function onUp(e: PointerEvent, cancelled: boolean) {
  const p = presses.get(e.pointerId);
  if (!p) return;
  presses.delete(e.pointerId);
  const held = ui.heldSteps.get(e.pointerId);
  ui.heldSteps.delete(e.pointerId);
  endGesture();
  if (cancelled) return;
  const quick = performance.now() - p.t0 < TAP_MS;
  if (quick && !p.dragged) lastTap[p.col] = performance.now();
  if (quick && !p.dragged && !p.secondary && !held?.used) toggleStep(p.index);
}

export function renderSequencer() {
  const t = curSeq();
  const page = ui.viewPage;
  const playPos = ui.playing ? rt.playPos[seqIndex()] : -1;
  const heldIdx = new Set([...ui.heldSteps.values()].map((s) => s.index));

  // Хвосты длинных нот (могут начинаться на предыдущих страницах).
  const tail = new Set<number>();
  t.pages.forEach((pg, pi) => pg.forEach((s, si) => {
    if (!s.on) return;
    const start = pi * STEPS_PER_PAGE + si;
    for (let k = 1; k < s.len; k++) tail.add(start + k);
  }));

  cells.forEach((cell, col) => {
    const index = page * STEPS_PER_PAGE + col;
    const s = stepAt(t, index);
    const on = !!s?.on;
    setClass(cell, 'on', on);
    setClass(cell, 'plock', on && hasLocks(s!));
    // P-lock без ноты — жёлтая обводка.
    setClass(cell, 'lock-only', !on && !!s && hasLocks(s));
    setClass(cell, 'tail', !on && tail.has(index));
    setText(labels[col], on ? (s!.notes.length > 1 ? 'POLY' : s!.notes.length === 1 ? noteName(s!.notes[0]) : '') : '');
    setClass(cell, 'held', heldIdx.has(index));
    setClass(cell, 'playing', index === playPos);
    setClass(cell, 'outside', index >= t.length);
    setClass(cell, 'last', index === t.length - 1);
  });
}
