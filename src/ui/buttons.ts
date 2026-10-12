// Кнопки: LFO1, LFO2, LFO3, ENV (слева, под окном сэмпла; при MST — RATIO и BYPASS устройств мастера); MORPH, SHIFT, FX, MOD (справа внизу);
// PLAY, REC, UNDO, REDO, PATTERNS и EQ (в верхней панели справа).
// LFO1/LFO2/LFO3/ENV/FX/MOD работают на удержание; MORPH — тап (режим) и удержание (+ UNDO).

import { canRedo, canUndo, endRecTake, cycleRatio, redo, doc, gridMode, setHeld, toggleClipBypass, toggleCmpBypass, toggleLimBypass, toggleMorph, toggleView, ui, undo, undoTrackEdits, type HoldButton } from '../state';
import { RATIOS } from '../params';
import { registerAction } from '../midi';
import { setPlaying } from '../transport';
import { h, setClass, setText } from './dom';
import { heldKnobSources } from './knobs';
import { markPlay, markPlayNote } from './debug';
import { audioState, probeNextNote, unlockAudio } from '../audio/engine';

const holdViews: [HTMLElement, HoldButton][] = [];
let playBtn: HTMLElement;
let recBtn: HTMLElement;
let undoBtn: HTMLElement;
let redoBtn: HTMLElement;
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

function tapButton(label: string, fn: (e?: PointerEvent) => void, state?: () => boolean): HTMLElement {
  const el = h('div', 'btn', label);
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(e); });
  registerAction(label, { label, press: fn, state }, el);
  return el;
}

let lfoGrid: HTMLElement;
let masterGrid: HTMLElement;
let ratioBtn: HTMLElement;
let compBypassBtn: HTMLElement;
let clipBypassBtn: HTMLElement;
let limBypassBtn: HTMLElement;

/**
 * Слева под окном сэмпла: LFO1, LFO2, LFO3, ENV. При MST на их месте (тот же размер и порядок
 * сетки) кнопки мастера: BYPASS компрессора, BYPASS клиппера, RATIO компрессора, BYPASS лимитера.
 */
export function buildLeftButtons(): HTMLElement {
  const el = h('div', 'left-btns');
  lfoGrid = h('div', 'btn-grid');
  lfoGrid.append(holdButton('LFO1', 'lfo1'), holdButton('LFO2', 'lfo2'), holdButton('LFO3', 'lfo3'), holdButton('ENV', 'env'));
  const tap = (label: string, fn: () => void) => {
    const b = h('div', 'btn master-btn', label);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return b;
  };
  ratioBtn = tap('', cycleRatio);
  ratioBtn.classList.add('ratio-btn');
  clipBypassBtn = tap('BYPASS\nCLIP', toggleClipBypass);
  compBypassBtn = tap('BYPASS\nCOMP', toggleCmpBypass);
  limBypassBtn = tap('BYPASS\nLIM', toggleLimBypass);
  masterGrid = h('div', 'btn-grid hidden');
  masterGrid.append(compBypassBtn, clipBypassBtn, ratioBtn, limBypassBtn);
  el.append(lfoGrid, masterGrid);
  return el;
}

/**
 * PLAY (зелёная), REC (красная), UNDO и REDO слева от PATTERNS — видны во всех режимах (паттерны, EQ,
 * редактор сэмпла). С зажатой MORPH тап по UNDO сбрасывает изменения, сделанные в режиме MORPH.
 */
export function buildTransportButtons(): HTMLElement {
  const el = h('div', 'transport');
  playBtn = tapButton('PLAY', (e) => {
    // Звук мог быть приостановлен (Safari): будим сразу, на касании, а не на отпускании.
    if (audioState() !== 'running') unlockAudio();
    if (!ui.playing && e) probeNextNote(markPlayNote);
    setPlaying(!ui.playing);
    if (ui.playing && e) markPlay(e.timeStamp);
  }, () => ui.playing);
  playBtn.classList.add('play-btn');
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; endRecTake(); }, () => ui.rec);
  recBtn.classList.add('rec-btn');
  undoBtn = tapButton('UNDO', () => {
    if (ui.held.track) { morphUsed = true; undoTrackEdits(); } else undo();
  });
  redoBtn = tapButton('REDO', redo);
  el.append(playBtn, recBtn, undoBtn, redoBtn);
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
  // MORPH: тап включает и выключает режим (выключение возвращает параметры к моменту включения);
  // удержание MORPH + тап по UNDO (в верхней панели) сбрасывает изменения, сделанные в режиме MORPH.
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
  // SHIFT — на месте прежней RANDOM; что она делает, ещё не определено (пока неактивна).
  const shift = h('div', 'btn disabled', 'SHIFT');
  el.append(morphBtn, shift, holdButton('FX', 'fx'), holdButton('MOD', 'mod'));
  return el;
}

export function renderButtons() {
  const mode = gridMode();
  // Пока палец держит ручку с назначенным LFO/ENV — кнопка этого источника обведена.
  const srcs = heldKnobSources();
  const SRC: Partial<Record<HoldButton, number>> = { lfo1: 1, lfo2: 2, lfo3: 3, env: 4 };
  for (const [el, btn] of holdViews) {
    // MORPH белой не загорается: сразу показывает, каким станет режим (жёлтая — включён).
    setClass(el, 'active', ui.held[btn] && btn !== 'track');
    setClass(el, 'mod-src', SRC[btn] !== undefined && srcs.has(SRC[btn] as 1 | 2 | 3 | 4));
    if (btn === 'fx' || btn === 'mod') setClass(el, 'mode', mode === btn);
  }
  const master = ui.channel === 'master';
  setClass(lfoGrid, 'hidden', master);
  setClass(masterGrid, 'hidden', !master);
  if (master) {
    setText(ratioBtn, `RATIO\n${RATIOS[doc.ratio]}:1`);
    setClass(compBypassBtn, 'active', doc.cmpBypass);
    setClass(clipBypassBtn, 'active', doc.clipBypass);
    setClass(limBypassBtn, 'active', doc.limBypass);
  }
  setClass(playBtn, 'active', ui.playing);
  setClass(patternsBtn, 'active', ui.patternView);
  setClass(eqBtn, 'active', ui.eqView);
  setClass(recBtn, 'rec', ui.rec);
  // Пока MORPH держат (и UNDO не нажимали) — уже видно состояние после отпускания.
  setClass(morphBtn, 'morph-on', ui.held.track && !morphUsed ? !ui.morph : ui.morph);
  setClass(redoBtn, 'disabled', !canRedo());
  setClass(undoBtn, 'disabled', ui.held.track ? !doc.tracks.some((t) => t.trackEdit) : !canUndo());
}
