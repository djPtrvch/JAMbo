// Кнопки: LFO1, LFO2, LFO3, ENV (слева, под окном сэмпла); PLAY, REC (справа над миниатюрами
// страниц); TRACK, UNDO, FX, MOD (справа внизу); PATTERNS (в верхней панели).
// LFO1/LFO2/LFO3/ENV/TRACK/FX/MOD работают на удержание.

import { canUndo, gridMode, setHeld, ui, undo, type HoldButton } from '../state';
import { unlockAudio } from '../audio';
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

/** PLAY и REC над миниатюрами страниц — видны и в режиме сетки паттернов. */
export function buildTransportButtons(): HTMLElement {
  const el = h('div', 'btn-grid transport');
  playBtn = tapButton('PLAY', () => { unlockAudio(); setPlaying(!ui.playing); });
  playBtn.addEventListener('pointerup', unlockAudio);
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; });
  el.append(playBtn, recBtn);
  return el;
}

let patternsBtn: HTMLElement;

/** Кнопка PATTERNS рядом с корневой нотой: переключает центр экрана на сетку паттернов. */
export function buildPatternsButton(): HTMLElement {
  patternsBtn = tapButton('PATTERNS', () => { ui.patternView = !ui.patternView; });
  patternsBtn.classList.add('patterns-btn');
  return patternsBtn;
}

export function buildRightButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  undoBtn = tapButton('UNDO', undo);
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
  setClass(undoBtn, 'disabled', !canUndo());
}
