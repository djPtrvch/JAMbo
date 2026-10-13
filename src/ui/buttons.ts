// Кнопки: LFO1, LFO2, LFO3, ENV (слева, под окном сэмпла; при MST — BYPASS устройств мастера); FX, MOD, MORPH, SHIFT (справа внизу);
// PLAY, REC, UNDO, REDO, PATTERNS и EQ (в верхней панели справа).
// LFO1/LFO2/LFO3/ENV/FX/MOD работают на удержание; MORPH — тап (режим) и удержание (+ UNDO).

import { requestStop } from '../stems';
import { canRedo, canUndo, endRecTake, cycleRatio, redo, doc, gridMode, setHeld, toggleClipBypass, toggleCmpBypass, toggleSatBypass, toggleLimBypass, toggleMorph, toggleView, ui, undo, undoTrackEdits, type HoldButton } from '../state';
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

function holdButton(label: string, btn: HoldButton, midi = true): HTMLElement {
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
  if (btn !== 'track' && midi) registerAction(label, { label, press: () => setHeld(btn, true), release: () => setHeld(btn, false), state: () => ui.held[btn] }, el);
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
let compBypassBtn: HTMLElement;
let satBypassBtn: HTMLElement;
let clipBypassBtn: HTMLElement;
let limBypassBtn: HTMLElement;

/**
 * Слева под окном сэмпла: LFO1, LFO2, LFO3, ENV. При MST на их месте (тот же размер и сетка)
 * BYPASS сатуратора, компрессора (с SHIFT — RATIO), клиппера и лимитера.
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
  // Вверху BYPASS CLIP и BYPASS COMP (с зажатой SHIFT на её месте RATIO), внизу BYPASS SAT и BYPASS LIM;
  // включённый bypass — цветом своего модуля, как формы волны скопа (SAT белая, COMP жёлтая, CLIP оранжевая, LIM красная).
  satBypassBtn = tap('BYPASS\nSAT', toggleSatBypass);
  satBypassBtn.classList.add('byp-sat');
  compBypassBtn = tap('BYPASS\nCOMP', () => (ui.held.shift ? cycleRatio() : toggleCmpBypass()));
  compBypassBtn.classList.add('byp-comp');
  clipBypassBtn = tap('BYPASS\nCLIP', toggleClipBypass);
  clipBypassBtn.classList.add('byp-clip');
  limBypassBtn = tap('BYPASS\nLIM', toggleLimBypass);
  limBypassBtn.classList.add('byp-lim');
  masterGrid = h('div', 'btn-grid hidden');
  masterGrid.append(clipBypassBtn, compBypassBtn, satBypassBtn, limBypassBtn);
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
    // Идёт запись стемов: PLAY не останавливает сразу — паттерны доигрывают до конца прохода.
    if (ui.playing && requestStop()) return;
    setPlaying(!ui.playing);
    if (ui.playing && e) markPlay(e.timeStamp);
  }, () => ui.playing);
  playBtn.classList.add('play-btn');
  recBtn = tapButton('REC', () => { ui.rec = !ui.rec; endRecTake(); }, () => ui.rec);
  recBtn.classList.add('rec-btn');
  // На PLAY и REC — значки вместо надписей.
  playBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24"><path d="M7 4.5v15l13-7.5z" fill="currentColor"/></svg>';
  recBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="7" fill="currentColor"/></svg>';
  undoBtn = tapButton('UNDO', () => {
    if (ui.held.track) { morphUsed = true; undoTrackEdits(); } else undo();
  });
  redoBtn = tapButton('REDO', redo);
  // UNDO и REDO — значки: закруглённая стрелка влево (отмена) и вправо (повтор).
  undoBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/></svg>';
  redoBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 14l5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/></svg>';
  undoBtn.classList.add('popup-pass');
  redoBtn.classList.add('popup-pass');
  playBtn.classList.add('tb-play');
  recBtn.classList.add('tb-rec');
  undoBtn.classList.add('tb-undo');
  redoBtn.classList.add('tb-redo');
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

/** SHIFT при MST — справа внизу сетки скопа (та же кнопка удержания; MIDI-цель одна — основная). */
export const buildShiftButton = () => holdButton('SHIFT', 'shift', false);

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
  // Вверху FX и MOD, внизу MORPH и SHIFT. SHIFT — удержание, даёт дополнительные действия:
  // с тапом по ручке дорожки снимает все её p-lock, при MST — RATIO на месте BYPASS COMP.
  el.append(holdButton('FX', 'fx'), holdButton('MOD', 'mod'), morphBtn, holdButton('SHIFT', 'shift'));
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
    // С зажатой SHIFT на месте BYPASS COMP — RATIO компрессора.
    const ratio = ui.held.shift;
    setText(compBypassBtn, ratio ? `RATIO\n${RATIOS[doc.ratio]}:1` : 'BYPASS\nCOMP');
    setClass(compBypassBtn, 'ratio-btn', ratio);
    setClass(compBypassBtn, 'active', !ratio && doc.cmpBypass);
    setClass(clipBypassBtn, 'active', doc.clipBypass);
    setClass(satBypassBtn, 'active', !!doc.satBypass);
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
