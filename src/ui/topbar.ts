// Верхняя панель: бутерброд-меню (заглушка), BPM, метроном, гамма и корневая нота.
// Тап по гамме и ноте открывает меню выбора.

import { unlockAudio } from '../audio';
import { NOTE_NAMES, SCALES } from '../params';
import { doc, rt, setBpm, setRoot, setScale, ui } from '../state';
import { choiceMenu, dragField } from './controls';
import { h, setClass } from './dom';

let metro: HTMLElement;

function metronomeIcon(): HTMLElement {
  const el = h('div', 'metro');
  el.innerHTML = '<svg viewBox="0 0 24 24"><path d="M9 3h6l4 18H5L9 3z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 16l5-9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M7 16h10" stroke="currentColor" stroke-width="1.8"/></svg>';
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    unlockAudio();
    ui.metronome = !ui.metronome;
  });
  // iOS иногда разрешает звук только на отпускании пальца.
  el.addEventListener('pointerup', unlockAudio);
  return el;
}

export function buildTopbar(): HTMLElement {
  const el = h('div', 'topbar');
  const burger = h('div', 'burger');
  burger.append(h('span'), h('span'), h('span'));
  metro = metronomeIcon();
  const scaleMenu = choiceMenu(SCALES.map((s) => s.name), 3, () => doc.scale, setScale);
  const rootMenu = choiceMenu(NOTE_NAMES, 4, () => doc.root, setRoot);
  el.append(
    burger,
    dragField('BPM', () => doc.bpm, setBpm, () => String(doc.bpm), 4),
    metro,
    dragField('SCALE', () => doc.scale, setScale, () => SCALES[doc.scale].name, 24, scaleMenu),
    dragField('ROOT', () => doc.root, setRoot, () => NOTE_NAMES[doc.root], 24, rootMenu),
  );
  return el;
}

export function renderTopbar(now: number) {
  setClass(metro, 'on', ui.metronome);
  setClass(metro, 'beat', ui.playing && now < rt.beatUntil);
  setClass(metro, 'accent', rt.beatAccent);
}
