// Кнопки: LFO1, LFO2, LFO3, ENV (слева, под окном сэмпла); MORPH, UNDO, FX, MOD (справа внизу);
// PLAY, REC, PATTERNS и EQ (в верхней панели справа).
// LFO1/LFO2/LFO3/ENV/FX/MOD работают на удержание; MORPH — тап (режим) и удержание (+ UNDO).

import { canUndo, doc, gridMode, setHeld, toggleMorph, toggleView, ui, undo, undoTrackEdits, type HoldButton } from '../state';
import { registerAction } from '../midi';
import { setPlaying } from '../transport';
import { h, setClass } from './dom';

const holdViews: [HTMLElement, HoldButton][] = [];
let playBtn: HTMLElement;
let recBtn: HTMLElement;
let undoBtn: HTMLElement;
let morphBtn: HTMLElement;
/** На удержании MORPH уже нажали UNDO — отпускание не переключает режим. */
let morphUsed = false;

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
  if (btn !== 'track') registerAction(label, { label, press: () => setHeld(btn, true), release: () => setHeld(btn, false), state: () => ui.held[btn] }, el);
  return el;
}

function tapButton(label: string, fn: () => void, state?: () => boolean): HTMLElement {
  const el = h('div', 'btn', label);
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
  registerAction(label, { label, press: fn, state }, el);
  return el;
}

export function buildLeftButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  el.append(holdButton('LFO1', 'lfo1'), holdButton('LFO2', 'lfo2'), holdButton('LFO3', 'lfo3'), holdButton('ENV', 'env'));
  return el;
}

/** PLAY (зелёная) и REC (красная) слева от PATTERNS — видны и в режиме сетки паттернов. */
export function buildTransportButtons(): HTMLElement {
  const el = h('div', 'transport');
  playBtn = tapButton('PLAY', () => setPlaying(!ui.playing), () => ui.playing);
  playBtn.classList.add('play-btn');
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; }, () => ui.rec);
  recBtn.classList.add('rec-btn');
  el.append(playBtn, recBtn);
  return el;
}

let patternsBtn: HTMLElement;

/** Кнопка PATTERNS в правом верхнем углу (над правой колонкой): переключает центр экрана на сетку паттернов. */
export function buildPatternsButton(): HTMLElement {
  patternsBtn = tapButton('PATTERNS', () => toggleView('patterns'), () => ui.patternView);
  patternsBtn.classList.add('patterns-btn');
  return patternsBtn;
}

let eqBtn: HTMLElement;

/** Кнопка EQ справа от PATTERNS: эквалайзер выбранной дорожки или мастера на месте центра экрана. */
export function buildEqButton(): HTMLElement {
  eqBtn = tapButton('EQ', () => toggleView('eq'), () => ui.eqView);
  eqBtn.classList.add('eq-btn');
  return eqBtn;
}

export function buildRightButtons(): HTMLElement {
  const el = h('div', 'btn-grid');
  // С зажатым TRACK — отмена всех изменений, сделанных с TRACK, на всех дорожках.
  // MORPH: тап включает и выключает режим (выключение возвращает параметры к моменту включения);
  // удержание MORPH + тап по UNDO сбрасывает изменения, сделанные в режиме MORPH.
  undoBtn = tapButton('UNDO', () => {
    if (ui.held.track) { morphUsed = true; undoTrackEdits(); } else undo();
  });
  morphBtn = holdButton('MORPH', 'track');
  morphBtn.addEventListener('pointerdown', () => { morphUsed = false; });
  morphBtn.addEventListener('pointerup', () => { if (!morphUsed && !ui.held.track) toggleMorph(); });
  // С MIDI — так же: нажатие держит MORPH, отпускание без UNDO переключает режим.
  registerAction('MORPH', {
    label: 'MORPH',
    press: () => { morphUsed = false; setHeld('track', true); },
    release: () => { setHeld('track', false); if (!morphUsed) toggleMorph(); },
    state: () => ui.morph,
  }, morphBtn);
  el.append(morphBtn, undoBtn, holdButton('FX', 'fx'), holdButton('MOD', 'mod'));
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
  setClass(eqBtn, 'active', ui.eqView);
  setClass(recBtn, 'rec', ui.rec);
  setClass(morphBtn, 'morph-on', ui.morph);
  setClass(undoBtn, 'disabled', ui.held.track ? !doc.tracks.some((t) => t.trackEdit) : !canUndo());
}
