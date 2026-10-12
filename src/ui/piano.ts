// Пианоролл под секвенсором: ноты выбранной гаммы (две октавы), корневая нота выделена.
// Слева — кнопка CHORD (шириной с первый шаг): режим аккордов этой дорожки; включена — клавиши
// квадратные, под ними PROGRESSION и аккорды прогрессии; выключена — клавиши на всю высоту.
// Справа — стрелки октавы ▲ ▼ одна над другой (шириной с последний шаг).
// Зажатые ноты (одна или несколько одновременно) становятся выбранными — ими ставятся триги;
// при удержании шага зажатые ноты заменяют ноты шага;
// с REC во время проигрывания — записывает ноты в реальном времени.

import { PROGRESSIONS, SCALES, noteName } from '../params';
import { releaseEnv,
  chordName, chordOnDegree, doc, heldStepNotes, inputNotes, isRoot, pressedNotes, recordNotes, rt, scaleNotes,
  setOctave, setProgression, ui,
} from '../state';
import { playNow, unlockAudio } from '../audio/engine';
import { recStep } from '../transport';
import { h, setClass, setText } from './dom';
import { choiceMenu, dragField } from './controls';

const MAX_KEYS = 25;
const MAX_CHORDS = 8;
/** Зазор между клавишами, px (как в style.css). */
const KEY_GAP = 3;

const keys: HTMLElement[] = [];
const chips: HTMLElement[] = [];
let chordBtn: HTMLElement;
let pianoEl: HTMLElement;
let progField: HTMLElement;
let chipRow: HTMLElement;
/** Ширина ряда клавиш (px) и число клавиш, по которым посчитан размер клавиши. */
let rowW = 0;
let sized = '';

/** Клавиш на экране: две октавы гаммы + верхняя корневая нота. */
const keyCount = () => Math.min(MAX_KEYS, SCALES[doc.scale].steps.length * 2 + 1);

/**
 * Нажатие ноты/аккорда: запись, редактирование шага или выбор (и ноты с MIDI-входов).
 * track — дорожка для нот с MIDI по каналам (без неё — выбранная).
 */
export function press(notes: number[], track: number | null = null, held = false) {
  const ti = track ?? ui.selectedTrack;
  // Живой наигрыш: нота сразу звучит звуком выбранной дорожки.
  unlockAudio();
  playNow(ti, notes, held);
  if (ui.rec && ui.playing && ui.heldSteps.size === 0) {
    const now = performance.now();
    const at = recStep(ti, now);
    if (at) recordNotes(ti, at.index, notes, at.merge);
    rt.flashUntil[ti] = now + 90;
    rt.noteFlash[ti] = { notes, until: now + 200 };
    return;
  }
  if (ti === ui.selectedTrack) inputNotes();
}

function pressHandlers(el: HTMLElement, notes: () => number[]) {
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const n = notes();
    ui.pressedKeys.set(e.pointerId, n);
    press(n, null, true);
  });
  // Отпущена последняя клавиша — у ENV начинается Release.
  const up = (e: PointerEvent) => {
    if (!ui.pressedKeys.delete(e.pointerId)) return;
    if (ui.pressedKeys.size === 0) releaseEnv(ui.selectedTrack);
  };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
}

export function buildPiano(): HTMLElement {
  const el = h('div', 'piano');
  pianoEl = el;

  chordBtn = h('div', 'btn scale-btn chord-btn', 'CHORD');
  chordBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); ui.chordMode = !ui.chordMode; });

  const keyRow = h('div', 'keys');
  new ResizeObserver(() => { rowW = keyRow.clientWidth; }).observe(keyRow);
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

  // Строка под клавишами (в режиме аккордов): прогрессия и её аккорды.
  const panel = h('div', 'scale-panel');
  const progMenu = choiceMenu(PROGRESSIONS.map((p) => p.name), 2, () => ui.progression, setProgression);
  progField = dragField('PROGRESSION', () => ui.progression, setProgression, () => PROGRESSIONS[ui.progression].name, 24, progMenu);
  progField.classList.add('narrow-field', 'sp-prog');
  chipRow = h('div', 'chips');
  for (let c = 0; c < MAX_CHORDS; c++) {
    const chip = h('div', 'chip');
    pressHandlers(chip, () => chordOnDegree(PROGRESSIONS[ui.progression].degrees[c] ?? 0));
    chips.push(chip);
    chipRow.append(chip);
  }
  panel.append(progField, chipRow);

  const oct = h('div', 'octave');
  const up = h('div', 'btn arrow', '▲');
  const down = h('div', 'btn arrow', '▼');
  down.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave - 1); });
  up.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave + 1); });
  oct.append(up, down);

  // Под SCALE — кнопка-бутерброд (пока неактивна: что в ней, определим позже).
  const menuBtn = h('div', 'btn piano-menu');
  const lines = h('div', 'burger-lines');
  lines.append(h('span'), h('span'), h('span'));
  menuBtn.append(lines);

  el.append(chordBtn, menuBtn, keyRow, panel, oct);
  return el;
}

/**
 * Клавиши в компактном виде (SCALE включена) квадратные: сторона = ширина клавиши (зависит от числа
 * нот гаммы); по ней — высота пианоролла (--key-h) и сетка строки SCALE (--keys, --key-w).
 */
function sizeKeys(count: number) {
  if (!rowW) return;
  const sig = `${count}|${rowW}`;
  if (sig === sized) return;
  sized = sig;
  const w = (rowW - KEY_GAP * (count - 1)) / count;
  const app = document.getElementById('app')!;
  app.style.setProperty('--key-h', `${w.toFixed(1)}px`);
  app.style.setProperty('--key-w', `${w.toFixed(1)}px`);
  app.style.setProperty('--keys', String(count));
}

export function renderPiano(now: number) {
  const count = keyCount();
  sizeKeys(count);
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
  setClass(pianoEl, 'open', ui.chordMode);
}
