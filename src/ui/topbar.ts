// Верхняя панель: бутерброд-меню (PROJECTS, SETTINGS), BPM, метроном, гамма и корневая нота.
// Тап по гамме и ноте открывает меню выбора.

import { unlockAudio } from '../audio/engine';
import { BPM_MAX, BPM_MIN, NOTE_NAMES, SCALES } from '../params';
import { registerAction } from '../midi';
import { doc, enterBpm, rt, setBpm, setRoot, setScale, ui } from '../state';
import { choiceMenu, dragField } from './controls';
import { openMainMenu } from './settings';
import { h, setClass } from './dom';
import { openInput } from './popup';
import { settings } from '../settings';
import { beatPos } from '../transport';

let metro: HTMLElement;

function metronomeIcon(): HTMLElement {
  const el = h('div', 'metro');
  el.innerHTML = '<svg viewBox="0 0 24 24"><path d="M9 3h6l4 18H5L9 3z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 16l5-9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M7 16h10" stroke="currentColor" stroke-width="1.8"/></svg>';
  const toggle = () => { unlockAudio(); ui.metronome = !ui.metronome; };
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); toggle(); });
  registerAction('METRONOME', { label: 'METRONOME', press: toggle, state: () => ui.metronome }, el);
  // iOS иногда разрешает звук только на отпускании пальца.
  el.addEventListener('pointerup', unlockAudio);
  return el;
}

export function buildTopbar(): HTMLElement {
  const el = h('div', 'topbar');
  const burger = h('div', 'burger');
  burger.append(h('span'), h('span'), h('span'));
  // Бутерброд — меню PROJECTS и SETTINGS.
  burger.addEventListener('pointerup', () => openMainMenu(burger));
  metro = metronomeIcon();
  // Бутерброд, темп и метроном — группа шириной с левую колонку (край по окну сэмпла).
  const leftGroup = h('div', 'top-left-group');
  // Удержание темпа без движения — ввод числом.
  const bpm = dragField('BPM', () => doc.bpm, setBpm, () => String(doc.bpm), 4, undefined,
    (el) => openInput(el, String(doc.bpm), (v) => { const n = parseFloat(v.replace(',', '.')); if (Number.isFinite(n)) enterBpm(n); }, true));
  bpm.classList.add('bpm-field');
  // Полоса внизу поля BPM: доли фразы SYNC QUANTUM (по 4 на такт).
  phaseBar = h('div', 'bpm-phase');
  bpm.append(phaseBar);
  // MIDI: темп — регулятор (как ручка: ABSOLUTE по диапазону 40–240, RELATIVE — шагами).
  registerAction('BPM', {
    label: 'BPM', press: () => {},
    value: { get: () => (doc.bpm - BPM_MIN) / (BPM_MAX - BPM_MIN), set: (n) => setBpm(BPM_MIN + n * (BPM_MAX - BPM_MIN)) },
  }, bpm);
  leftGroup.append(burger, bpm, metro);
  // Гамма и нота — той же ширины, что PLAY и REC.
  const scaleMenu = choiceMenu(SCALES.map((sc) => sc.name), 3, () => doc.scale, setScale);
  const rootMenu = choiceMenu(NOTE_NAMES, 4, () => doc.root, setRoot);
  const scale = dragField('SCALE', () => doc.scale, setScale, () => SCALES[doc.scale].name, 24, scaleMenu);
  const root = dragField('ROOT', () => doc.root, setRoot, () => NOTE_NAMES[doc.root], 24, rootMenu);
  scale.classList.add('narrow-field');
  root.classList.add('narrow-field');
  el.append(leftGroup, scale, root);
  return el;
}

let phaseBar: HTMLElement;
let phaseKey = '';
/** Полоса доль: при игре жёлтые — доли от начала фразы до текущей; стоп — все серые. */
function renderPhase(now: number) {
  const n = 4 * settings.sync.quantum;
  const pos = beatPos(now);
  const lit = pos === null ? -1 : Math.floor(pos) % n;
  const key = `${n}:${lit}`;
  if (key === phaseKey) return;
  phaseKey = key;
  if (phaseBar.childElementCount !== n) phaseBar.replaceChildren(...Array.from({ length: n }, () => h('span')));
  [...phaseBar.children].forEach((c, k) => c.classList.toggle('on', k <= lit));
}

export function renderTopbar(now: number) {
  renderPhase(now);
  setClass(metro, 'on', ui.metronome);
  setClass(metro, 'beat', ui.playing && now < rt.beatUntil);
  setClass(metro, 'accent', rt.beatAccent);
}
