// Пианоролл под секвенсором: ноты выбранной гаммы (две октавы), корневая нота выделена.
// Слева — режим аккордов, справа — стрелки октавы; в режиме аккордов снизу всплывает выбор прогрессии.
// Зажатые ноты (одна или несколько одновременно) становятся выбранными — ими ставятся триги;
// при удержании шага зажатые ноты заменяют ноты шага;
// с REC во время проигрывания — записывает ноты в реальном времени.

import { PROGRESSIONS, SCALES, noteName } from '../params';
import {
  chordName, chordOnDegree, doc, heldStepNotes, inputNotes, isRoot, pressedNotes, recordNotes, rt, scaleNotes,
  setOctave, setProgression, ui,
} from '../state';
import { recStep } from '../transport';
import { h, setClass, setText } from './dom';
import { choiceMenu, dragField } from './controls';

const MAX_KEYS = 25;
const MAX_CHORDS = 8;

const keys: HTMLElement[] = [];
const chips: HTMLElement[] = [];
let chordBtn: HTMLElement;
let progRow: HTMLElement;

/** Клавиш на экране: две октавы гаммы + верхняя корневая нота. */
const keyCount = () => Math.min(MAX_KEYS, SCALES[doc.scale].steps.length * 2 + 1);

/** Нажатие ноты/аккорда: запись, редактирование шага или выбор. */
function press(notes: number[]) {
  const ti = ui.selectedTrack;
  if (ui.rec && ui.playing && ui.heldSteps.size === 0) {
    const now = performance.now();
    const at = recStep(ti, now);
    if (at) recordNotes(ti, at.index, notes, at.merge);
    rt.flashUntil[ti] = now + 90;
    rt.noteFlash[ti] = { notes, until: now + 200 };
    return;
  }
  inputNotes();
}

function pressHandlers(el: HTMLElement, notes: () => number[]) {
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const n = notes();
    ui.pressedKeys.set(e.pointerId, n);
    press(n);
  });
  const up = (e: PointerEvent) => { ui.pressedKeys.delete(e.pointerId); };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
}

export function buildPiano(): HTMLElement {
  const el = h('div', 'piano');

  chordBtn = h('div', 'btn chord-btn', 'CHORD');
  chordBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); ui.chordMode = !ui.chordMode; });

  const keyRow = h('div', 'keys');
  for (let k = 0; k < MAX_KEYS; k++) {
    const key = h('div', 'key');
    key.append(h('span'));
    pressHandlers(
      key,
      () => (ui.chordMode ? chordOnDegree(k) : [scaleNotes(1, k)[0]]),
    );
    keys.push(key);
    keyRow.append(key);
  }

  const oct = h('div', 'octave');
  const down = h('div', 'btn arrow', '◀');
  const up = h('div', 'btn arrow', '▶');
  down.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave - 1); });
  up.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave + 1); });
  oct.append(down, up);

  el.append(chordBtn, keyRow, oct);
  return el;
}

export function buildProgression(): HTMLElement {
  progRow = h('div', 'progression');
  const menu = choiceMenu(PROGRESSIONS.map((p) => p.name), 2, () => ui.progression, setProgression);
  progRow.append(dragField('PROGRESSION', () => ui.progression, setProgression, () => PROGRESSIONS[ui.progression].name, 24, menu));
  const chipRow = h('div', 'chips');
  for (let c = 0; c < MAX_CHORDS; c++) {
    const chip = h('div', 'chip');
    pressHandlers(chip, () => chordOnDegree(PROGRESSIONS[ui.progression].degrees[c] ?? 0));
    chips.push(chip);
    chipRow.append(chip);
  }
  progRow.append(chipRow);
  return progRow;
}

export function renderPiano(now: number) {
  const count = keyCount();
  const notes = scaleNotes(count);
  const held = heldStepNotes();
  const pressed = new Set(pressedNotes());
  const shown = new Set(held ?? ui.selNotes);
  const flash = rt.noteFlash[ui.selectedTrack];
  const playing = new Set(now < flash.until ? flash.notes : []);
  // Без выбранных нот триг ставится на корневую ноту — подсвечиваем её как выбранную.
  if (!held && ui.selNotes.length === 0) shown.add(notes[0]);
  keys.forEach((key, k) => {
    const n = notes[k];
    setClass(key, 'hidden', k >= count);
    if (k >= count) return;
    setText(key.firstElementChild!, noteName(n));
    setClass(key, 'root', isRoot(n));
    setClass(key, 'selected', shown.has(n));
    setClass(key, 'step-notes', held !== null && shown.has(n));
    setClass(key, 'playing', playing.has(n));
    setClass(key, 'pressed', pressed.has(n));
  });
  setClass(chordBtn, 'active', ui.chordMode);

  const degrees = PROGRESSIONS[ui.progression].degrees;
  chips.forEach((chip, c) => {
    setClass(chip, 'hidden', c >= degrees.length);
    if (c >= degrees.length) return;
    setText(chip, chordName(degrees[c]));
    const chord = chordOnDegree(degrees[c]);
    setClass(chip, 'playing', chord.every((n) => playing.has(n)));
    setClass(chip, 'pressed', chord.every((n) => pressed.has(n)));
  });
  // Строка прогрессии всплывает снизу только в режиме аккордов.
  setClass(progRow, 'hidden', !ui.chordMode);
  setClass(document.getElementById('app')!, 'chord', ui.chordMode);
}
