// Кнопки: LFO1, LFO2, TRACK, UNDO (слева) и PLAY, REC, FX, MOD (справа).
// LFO1/LFO2/TRACK/FX/MOD работают на удержание.

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
  undoBtn = tapButton('UNDO', undo);
  el.append(holdButton('LFO1', 'lfo1'), holdButton('LFO2', 'lfo2'), undoBtn, holdButton('TRACK', 'track'));
  return el;
}

export function buildRightButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  playBtn = tapButton('PLAY', () => { unlockAudio(); setPlaying(!ui.playing); });
  playBtn.addEventListener('pointerup', unlockAudio);
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; });
  el.append(playBtn, recBtn, holdButton('FX', 'fx'), holdButton('MOD', 'mod'));
  return el;
}

export function renderButtons() {
  const mode = gridMode();
  for (const [el, btn] of holdViews) {
    setClass(el, 'active', ui.held[btn]);
    if (btn === 'fx' || btn === 'mod') setClass(el, 'mode', mode === btn);
  }
  setClass(playBtn, 'active', ui.playing);
  setClass(recBtn, 'rec', ui.rec);
  setClass(undoBtn, 'disabled', !canUndo());
}
