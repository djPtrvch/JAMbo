// Пианоролл под секвенсором: ноты выбранной гаммы (две октавы), корневая нота выделена.
// Слева — кнопка CHORD (шириной с первый шаг): режим аккордов этой дорожки; включена — клавиши
// квадратные, под ними PROGRESSION и аккорды прогрессии; выключена — клавиши на всю высоту.
// Справа — стрелки октавы ▲ ▼ одна над другой (шириной с последний шаг).
// Зажатые ноты (одна или несколько одновременно) становятся выбранными — ими ставятся триги;
// при удержании шага зажатые ноты заменяют ноты шага;
// с REC во время проигрывания — записывает ноты в реальном времени.

import { PROGRESSIONS, SCALES, noteName } from '../params';
import { recordLength, releaseEnv,
  chordName, chordOnDegree, doc, heldStepNotes, inputNotes, isRoot, pressedNotes, recordNotes, rt, scaleNotes,
  setOctave, setProgression, ui,
} from '../state';
import { playNow, releaseLive, unlockAudio } from '../audio/engine';
import { recLength, recStep } from '../transport';
import { h, setClass, setText } from './dom';
import { makePopup, popupButton, toggleRow, type Popup } from './popup';
import { saveSettings, settings } from '../settings';
import { choiceMenu, dragField } from './controls';
import { registerAction } from '../midi';
import { assignHeldSlice } from './sampleedit';

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

/** Клавиш на экране: одна или две октавы гаммы (меню пианоролла) + верхняя корневая нота. */
const keyCount = (oct: number = settings.pianoOctaves) => Math.min(MAX_KEYS, SCALES[doc.scale].steps.length * oct + 1);

/**
 * Нажатие ноты/аккорда: запись, редактирование шага или выбор (и ноты с MIDI-входов).
 * track — дорожка для нот с MIDI по каналам (без неё — выбранная).
 */
export function press(notes: number[], track: number | null = null, held = false, velocity = 1): { track: number; index: number } | null {
  const ti = track ?? ui.selectedTrack;
  // Удерживают маркер нарезки в редакторе сэмпла: нота назначается маркеру (и сразу звучит его кусок).
  if (track === null && assignHeldSlice(notes[0])) { unlockAudio(); playNow(ti, notes.slice(0, 1), held, velocity); return null; }
  // Живой наигрыш: нота сразу звучит звуком выбранной дорожки (с VELOCITY — с силой нажатия).
  unlockAudio();
  playNow(ti, notes, held, velocity);
  if (ui.rec && ui.playing && ui.heldSteps.size === 0) {
    const now = performance.now();
    const at = recStep(ti, now);
    if (at) recordNotes(ti, at.index, notes, at.merge, settings.velocity ? velocity : undefined);
    rt.flashUntil[ti] = now + 90;
    rt.noteFlash[ti] = { notes, until: now + 200 };
    return at ? { track: ti, index: at.index } : null;
  }
  if (ti === ui.selectedTrack) inputNotes();
  return null;
}

/** Зажатые клавиши: дорожка, ноты и записанный с REC шаг (длина — при отпускании). */
const keyHolds = new Map<number, { track: number; notes: number[]; rec: { track: number; index: number } | null; t0: number }>();

/**
 * Сила нажатия клавиши (0.2…1) при включённом VELOCITY: Apple Pencil — по давлению; палец (сила
 * касания браузеру на iPad не видна) — по месту на клавише: верх — тихо, низ — громко.
 */
function touchVelocity(el: HTMLElement, e: PointerEvent): number {
  if (!settings.velocity) return 1;
  if (e.pointerType === 'pen' && e.pressure > 0) return Math.max(VEL_MIN, Math.min(1, e.pressure));
  const r = el.getBoundingClientRect();
  const y = Math.min(1, Math.max(0, (e.clientY - r.top) / Math.max(1, r.height)));
  return VEL_MIN + (1 - VEL_MIN) * y;
}
const VEL_MIN = 0.2;

let pianoMenu: Popup | null = null;
/**
 * Меню бутерброда под CHORD: снизу вверх от кнопки, правее неё (на ширину CHORD — бутерброд виден),
 * не выше секвенсора шагов, шириной 4 шага; что не помещается — прокрутка (как во всех меню).
 */
function openPianoMenu(anchor: HTMLElement) {
  pianoMenu ??= makePopup('piano-menu-pop');
  const pop = pianoMenu;
  // VELOCITY — рычажок, как все вкл./выкл. в меню (после анимации меню перерисовывается — пояснение под ним).
  const vel = toggleRow('VELOCITY', settings.velocity, (v) => saveSettings({ velocity: v }), () => openPianoMenu(anchor));
  // Одна или две октавы на клавишах (высота пианоролла та же — клавиши шире).
  const octRow = h('div', 'arrange-row');
  for (const n of [1, 2] as const) {
    const b = popupButton(n === 1 ? '1 OCTAVE' : '2 OCTAVES', () => { saveSettings({ pianoOctaves: n }); openPianoMenu(anchor); });
    b.classList.toggle('current', settings.pianoOctaves === n);
    octRow.append(b);
  }
  pop.box.replaceChildren(
    octRow,
    vel,
    h('div', 'settings-note', settings.velocity
      ? 'Touch lower on a key — louder, higher — softer (Apple Pencil: pressure). Changes the note Level; REC writes it as a Level p-lock.'
      : 'Keys play at the track Level.'),
  );
  const steps = document.querySelectorAll<HTMLElement>('.step');
  const a = anchor.getBoundingClientRect();
  // От второго шага (сдвиг на ширину CHORD — бутерброд остаётся виден), шириной 4 шага.
  const s0 = steps[1]?.getBoundingClientRect(), s3 = steps[4]?.getBoundingClientRect();
  const left = s0 ? s0.left : a.left;
  const width = s0 && s3 ? s3.right - s0.left : 4 * a.width;
  const top = s0 ? s0.top : 8;
  pop.openAt(anchor, width);
  const box = pop.box;
  box.style.left = `${left}px`;
  box.style.maxHeight = `${a.bottom - top}px`;
  box.style.top = `${Math.max(top, a.bottom - box.offsetHeight)}px`;
}

/** Нажатие клавиши (палец — по pointerId; MIDI — по своему отрицательному id): ноты звучат и становятся выбранными. */
function keyDown(id: number, n: number[], velocity: number) {
  ui.pressedKeys.set(id, n);
  const track = ui.selectedTrack;
  const rec = press(n, null, true, velocity);
  keyHolds.set(id, { track, notes: n, rec, t0: performance.now() });
}
/** Отпущена клавиша — её ноты гаснут (Decay); последняя — у ENV начинается Release. С REC длина записанной
 *  ноты — по времени удержания. */
function keyUp(id: number) {
  if (!ui.pressedKeys.delete(id)) return;
  const k = keyHolds.get(id);
  keyHolds.delete(id);
  if (k) {
    releaseLive(k.track, k.notes);
    if (k.rec) recordLength(k.rec.track, k.rec.index, recLength(performance.now() - k.t0));
  }
  if (ui.pressedKeys.size === 0) releaseEnv(ui.selectedTrack);
}

/**
 * Касание клавиши или аккорда; name — действие для MIDI (KEY n, CHORD n): нажатие и отпускание — как палец
 * (держится, пока держат; с REC пишется), id — свой, отрицательный (не путается с пальцами).
 */
function pressHandlers(el: HTMLElement, notes: () => number[] | null, name: string, label: string, id: number) {
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const n = notes();
    if (n) keyDown(e.pointerId, n, touchVelocity(el, e));
  });
  const up = (e: PointerEvent) => keyUp(e.pointerId);
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  registerAction(name, {
    label,
    press: () => { const n = notes(); if (n) keyDown(id, n, 1); },
    release: () => keyUp(id),
    state: () => ui.pressedKeys.has(id),
  }, el);
}

export function buildPiano(): HTMLElement {
  const el = h('div', 'piano');
  pianoEl = el;

  chordBtn = h('div', 'btn scale-btn chord-btn', 'CHORD');
  const chordToggle = () => { ui.chordMode = !ui.chordMode; };
  chordBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); chordToggle(); });
  registerAction('CHORD', { label: 'CHORD', press: chordToggle, state: () => ui.chordMode }, chordBtn);

  const keyRow = h('div', 'keys');
  new ResizeObserver(() => { rowW = keyRow.clientWidth; }).observe(keyRow);
  for (let k = 0; k < MAX_KEYS; k++) {
    const key = h('div', 'key');
    key.append(h('span'));
    // Клавиша по позиции (KEY 1 — левая); за числом клавиш на экране — нет.
    pressHandlers(
      key,
      () => (k >= keyCount() ? null : ui.chordMode ? chordOnDegree(k) : [scaleNotes(1, k)[0]]),
      `KEY${k + 1}`, `KEY ${k + 1}`, -100 - k,
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
    // Аккорд прогрессии по позиции (PROG 1 — левый); у прогрессии короче — нет; без CHORD — нет.
    pressHandlers(chip, () => {
      const d = PROGRESSIONS[ui.progression].degrees[c];
      return d === undefined || !ui.chordMode ? null : chordOnDegree(d);
    }, `PROG${c + 1}`, `PROG CHORD ${c + 1}`, -200 - c);
    chips.push(chip);
    chipRow.append(chip);
  }
  panel.append(progField, chipRow);

  const oct = h('div', 'octave');
  const up = h('div', 'btn arrow', '▲');
  const down = h('div', 'btn arrow', '▼');
  down.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave - 1); });
  up.addEventListener('pointerdown', (e) => { e.preventDefault(); setOctave(ui.octave + 1); });
  registerAction('OCTUP', { label: 'OCTAVE ▲', press: () => setOctave(ui.octave + 1) }, up);
  registerAction('OCTDOWN', { label: 'OCTAVE ▼', press: () => setOctave(ui.octave - 1) }, down);
  oct.append(up, down);

  // Под CHORD — бутерброд: меню пианоролла (октавы, VELOCITY).
  const menuBtn = h('div', 'btn piano-menu');
  const lines = h('div', 'burger-lines');
  lines.append(h('span'), h('span'), h('span'));
  menuBtn.append(lines);
  menuBtn.addEventListener('pointerup', () => openPianoMenu(menuBtn));

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
  // Размер клавиш и строка аккордов — по двум октавам: с одной октавой высота пианоролла та же, клавиши шире.
  sizeKeys(keyCount(2));
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
