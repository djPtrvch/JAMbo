// Кнопки: LFO1, LFO2, LFO3, ENV (слева, под окном сэмпла); TRACK, UNDO, FX, MOD (справа внизу);
// PLAY, REC (по центру верхней панели), PATTERNS (в верхней панели справа).
// LFO1/LFO2/LFO3/ENV/TRACK/FX/MOD работают на удержание.

import { canUndo, doc, gridMode, setHeld, ui, undo, undoTrackEdits, type HoldButton } from '../state';
import { unlockAudio } from '../audio/engine';
import { setPlaying } from '../transport';
import { h, setClass } from './dom';

const holdViews: [HTMLElement, HoldButton][] = [];
let playBtn: HTMLElement;
let recBtn: HTMLElement;
let undoBtn: HTMLElement;

function holdButton(label: string, btn: HoldButton): HTMLElement {
  const el = h('div', 'btn', label);
  const pointers = new Set<number>();
  const release = (e: PointerEvent) => {
    pointers.delete(e.pointerId);
    if (pointers.size === 0) setHeld(btn, false);
  };
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    pointers.add(e.pointerId);
    setHeld(btn, true);
  });
  el.addEventListener('pointerup', release);
  el.addEventListener('pointercancel', release);
  holdViews.push([el, btn]);
  return el;
}

function tapButton(label: string, fn: () => void): HTMLElement {
  const el = h('div', 'btn', label);
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
  return el;
}

export function buildLeftButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  el.append(holdButton('LFO1', 'lfo1'), holdButton('LFO2', 'lfo2'), holdButton('LFO3', 'lfo3'), holdButton('ENV', 'env'));
  return el;
}

/** PLAY и REC по центру верхней панели — видны и в режиме сетки паттернов. */
export function buildTransportButtons(): HTMLElement {
  const el = h('div', 'transport');
  playBtn = tapButton('PLAY', () => { unlockAudio(); setPlaying(!ui.playing); });
  playBtn.addEventListener('pointerup', unlockAudio);
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; });
  el.append(playBtn, recBtn);
  return el;
}

let patternsBtn: HTMLElement;

/** Кнопка PATTERNS в правом верхнем углу (над правой колонкой): переключает центр экрана на сетку паттернов. */
export function buildPatternsButton(): HTMLElement {
  patternsBtn = tapButton('PATTERNS', () => { ui.patternView = !ui.patternView; });
  patternsBtn.classList.add('patterns-btn');
  return patternsBtn;
}

export function buildRightButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  // С зажатым TRACK — отмена всех изменений, сделанных с TRACK, на всех дорожках.
  undoBtn = tapButton('UNDO', () => (ui.held.track ? undoTrackEdits() : undo()));
  el.append(holdButton('TRACK', 'track'), undoBtn, holdButton('FX', 'fx'), holdButton('MOD', 'mod'));
  return el;
}

export function renderButtons() {
  const mode = gridMode();
  for (const [el, btn] of holdViews) {
    setClass(el, 'active', ui.held[btn]);
    if (btn === 'fx' || btn === 'mod') setClass(el, 'mode', mode === btn);
  }
  setClass(playBtn, 'active', ui.playing);
  setClass(patternsBtn, 'active', ui.patternView);
  setClass(recBtn, 'rec', ui.rec);
  setClass(undoBtn, 'disabled', ui.held.track ? !doc.tracks.some((t) => t.trackEdit) : !canUndo());
}
