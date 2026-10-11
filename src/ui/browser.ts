// Браузер библиотеки сэмплов и пресетов (library.ts) на месте центра экрана, как EQ.
// Открывается из меню звука (SAMPLE, LOAD — загрузка; SAVE — сохранить пресет синта) и из
// редактора сэмпла (LOAD; SAVE — сохранить сэмпл). Папки вложенные: тап — войти, ‹ — на уровень
// выше. Свайп влево по строке открывает справа EDIT (имя) и корзину (у папки с содержимым —
// второй тап для подтверждения); у сэмпла ещё EXPORT (WAV в «Файлы» / iCloud Drive).
// Загрузка: тап по сэмплу или пресету ставит его на дорожку (и в её папку), браузер остаётся
// открытым — можно пробовать звуки пианороллом. Зажатые шаги (меню звука для шагов) получают
// сэмпл как свой звук. IMPORT — файлы из «Файлов» (iPad, iCloud Drive) в открытую папку.
// Сохранение: внизу имя и SAVE HERE — в открытую папку.

import { downloadSample, importAudioFiles, useLibrarySample } from '../audio/engine';
import {
  ROOT, RECORDINGS, addPreset, addSample, children, countInside, createFolder, node, onLibraryChanged, path, remove, rename,
  type LibNode,
} from '../library';
import { SYNTH_ENGINES, synthEngine } from '../params';
import {
  addPresetToFolder, addSamplesQuiet, addSamplesToFolder, applyPreset, nextPresetName, presetFromTrack, sampleName,
  setStepSound, toggleView, ui,
} from '../state';
import { h, setClass, setText } from './dom';
import { openInput } from './popup';

/** Что делает браузер: загрузка (в дорожку или на зажатые шаги) или сохранение пресета / сэмпла. */
type Mode =
  | { kind: 'load'; steps: number[] }
  | { kind: 'save-preset' }
  | { kind: 'save-sample'; key: string };

const ACT_W = 72;

let panel: HTMLElement;
let pathText: HTMLElement;
let upBtn: HTMLElement;
let list: HTMLElement;
let saveBar: HTMLElement;
let nameInput: HTMLInputElement;
let note: HTMLElement;
let folder = ROOT;
let mode: Mode = { kind: 'load', steps: [] };
/** Папка, где корзина ждёт второго тапа (подтверждение удаления непустой папки). */
let confirmId = '';

const fail = (what: string) => (e: unknown) => { console.error(what, e); window.alert(`${what} failed`); };

function iconFor(n: LibNode): string {
  if (n.kind === 'folder') return n.system ? '●' : '▸';
  return n.kind === 'sample' ? '∿' : '◆';
}

function detail(n: LibNode): string {
  if (n.kind === 'folder') {
    const c = children(n.id).length;
    return n.id === RECORDINGS && !c ? 'track stems' : `${c}`;
  }
  if (n.kind === 'preset') {
    const e = n.preset ? synthEngine(n.preset.sound) : null;
    return e !== null ? SYNTH_ENGINES[e].name : 'preset';
  }
  return 'sample';
}

/** Тап по строке: папка — войти; сэмпл или пресет — загрузить (в режиме загрузки). */
async function open(n: LibNode) {
  if (n.kind === 'folder') { folder = n.id; confirmId = ''; fill(); return; }
  if (mode.kind !== 'load') return;
  const track = ui.selectedTrack;
  if (n.kind === 'sample' && n.key) {
    if (!(await useLibrarySample(n.key, n.name))) { window.alert('This sample is no longer stored on this iPad'); return; }
    if (mode.steps.length) { addSamplesQuiet(track, [n.key]); setStepSound(track, mode.steps, n.key); } else addSamplesToFolder(track, [n.key]);
  } else if (n.kind === 'preset' && n.preset && !mode.steps.length) {
    applyPreset(track, n.preset);
  }
  fill();
}

/** Строка: свайп влево открывает EDIT (и EXPORT у сэмпла) и корзину справа. */
function libRow(n: LibNode): HTMLElement {
  const row = h('div', 'project-row lib-row');
  const acts = h('div', 'lib-acts');
  const edit = h('div', 'lib-act', 'EDIT');
  edit.addEventListener('pointerup', () => openInput(edit, n.name, (v) => rename(n.id, v)));
  const exp = h('div', 'lib-act', 'EXPORT');
  exp.addEventListener('pointerup', () => {
    if (!n.key) return;
    void useLibrarySample(n.key, n.name).then((ok) => { if (ok) downloadSample(n.key!); }).catch(fail('Export'));
  });
  const trash = h('div', 'lib-act lib-trash');
  trash.innerHTML = '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  trash.addEventListener('pointerup', () => {
    // Непустая папка — второй тап подтверждает (DELETE?).
    if (n.kind === 'folder' && countInside(n.id) > 0 && confirmId !== n.id) {
      confirmId = n.id;
      trash.textContent = 'DELETE?';
      return;
    }
    confirmId = '';
    remove(n.id);
  });
  acts.append(edit, ...(n.kind === 'sample' ? [exp] : []), trash);
  const actsW = ACT_W * acts.children.length;
  const item = h('div', 'popup-btn project-item lib-item');
  const name = h('div', 'lib-name', `${iconFor(n)}  ${n.name}`);
  item.append(name, h('div', 'lib-detail', `${detail(n)}${n.kind === 'folder' ? '  ›' : ''}`));
  item.classList.toggle('system', !!n.system);
  row.append(acts, item);

  let id = -1;
  let x0 = 0;
  let base = 0;
  let dx = 0;
  // Строка не уезжает, а сужается справа (имя у левого края остаётся видно).
  const place = (x: number) => { item.style.width = x ? `calc(100% - ${-x}px)` : ''; };
  item.addEventListener('pointerdown', (e) => {
    id = e.pointerId;
    x0 = e.clientX;
    base = row.classList.contains('open') ? -actsW : 0;
    dx = 0;
    item.classList.add('dragging');
  });
  item.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id || n.system) return;
    dx = e.clientX - x0;
    if (Math.abs(dx) > 6) place(Math.max(-actsW, Math.min(0, base + dx)));
  });
  const end = (e: PointerEvent, cancel: boolean) => {
    if (e.pointerId !== id) return;
    id = -1;
    item.classList.remove('dragging');
    if (Math.abs(dx) <= 6 && !cancel) {
      if (base) { row.classList.remove('open'); place(0); return; }
      void open(n).catch(fail('Load'));
      return;
    }
    if (n.system) return;
    const opened = base + dx < -actsW / 2;
    // Открыта может быть только одна строка.
    if (opened) list.querySelectorAll('.lib-row.open').forEach((r) => { if (r !== row) { r.classList.remove('open'); (r.querySelector('.lib-item') as HTMLElement).style.width = ''; } });
    row.classList.toggle('open', opened);
    place(opened ? -actsW : 0);
  };
  item.addEventListener('pointerup', (e) => end(e, false));
  item.addEventListener('pointercancel', (e) => end(e, true));
  return row;
}

function fill() {
  if (!node(folder) && folder !== ROOT) folder = ROOT;
  const crumbs = path(folder).map((n) => n.name);
  setText(pathText, ['LIBRARY', ...crumbs].join('  /  '));
  setClass(upBtn, 'disabled', folder === ROOT);
  const items = children(folder);
  list.replaceChildren(...(items.length ? items.map(libRow) : [h('div', 'settings-note lib-empty', folder === RECORDINGS
    ? 'Stems recorded from each track will be saved here.'
    : 'Empty folder. NEW FOLDER, or IMPORT files from the iPad or iCloud Drive.')]));
  setClass(saveBar, 'hidden', mode.kind === 'load');
  setText(note, mode.kind === 'load' && mode.steps.length
    ? `Loading a sample onto step ${mode.steps.map((s) => s + 1).join(', ')}.`
    : 'The library is stored on this iPad (in the browser). IMPORT brings files from the iPad or iCloud Drive; EXPORT (swipe left on a sample) saves a WAV there.');
}

export function buildBrowser(): HTMLElement {
  panel = h('div', 'eq-panel browser hidden');
  const head = h('div', 'eq-bar lib-head');
  upBtn = h('div', 'btn eq-tool lib-up', '‹');
  upBtn.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const n = node(folder);
    if (n) { folder = n.parent; confirmId = ''; fill(); }
  });
  pathText = h('div', 'lib-path');
  const newFolder = h('div', 'btn eq-tool', 'NEW FOLDER');
  newFolder.addEventListener('pointerup', () => openInput(newFolder, 'New folder', (v) => { createFolder(folder, v); }));
  // IMPORT — поле выбора файла прозрачно поверх кнопки (на iOS выбор файла — только прямым тапом).
  const importBtn = h('div', 'btn eq-tool sample-pick', 'IMPORT');
  const input = h('input', 'sample-file');
  input.type = 'file';
  input.multiple = true;
  input.accept = 'audio/*,.wav,.wave,.aif,.aiff,.mp3,.m4a,.aac,.caf,.flac,.ogg';
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? []);
    input.value = '';
    if (!files.length) return;
    const into = folder === RECORDINGS ? ROOT : folder;
    void importAudioFiles(files).then((got) => { for (const f of got) addSample(into, f.key, f.name); })
      .catch(() => window.alert('Could not open the file as audio'));
  });
  importBtn.append(input);
  const close = h('div', 'btn eq-tool', 'CLOSE');
  close.addEventListener('pointerdown', (e) => { e.preventDefault(); closeBrowser(); });
  head.append(upBtn, pathText, newFolder, importBtn, close);

  list = h('div', 'project-list lib-list');
  saveBar = h('div', 'eq-bar lib-save hidden');
  nameInput = h('input', 'rename-input lib-name-input');
  nameInput.type = 'text';
  nameInput.maxLength = 40;
  const saveHere = h('div', 'btn eq-tool lib-save-btn', 'SAVE HERE');
  saveHere.addEventListener('pointerup', () => save());
  nameInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') save(); });
  saveBar.append(h('div', 'lib-save-label', 'NAME'), nameInput, saveHere);
  note = h('div', 'settings-note lib-note');
  panel.append(head, list, saveBar, note);
  onLibraryChanged(() => { if (ui.browserView) fill(); });
  return panel;
}

/** SAVE HERE: пресет синта дорожки или сэмпл — в открытую папку. */
function save() {
  const into = folder === RECORDINGS ? ROOT : folder;
  if (mode.kind === 'save-preset') {
    const p = presetFromTrack(ui.selectedTrack, nameInput.value);
    if (!p) return;
    const n = addPreset(into, p);
    addPresetToFolder(ui.selectedTrack, { ...p, name: n.name });
  } else if (mode.kind === 'save-sample') {
    addSample(into, mode.key, nameInput.value || sampleName(mode.key));
  }
  nameInput.blur();
  mode = { kind: 'load', steps: [] };
  fill();
}

/** Открыть браузер: загрузка (steps — зажатые шаги) или сохранение. */
export function openBrowser(m: Mode) {
  mode = m;
  confirmId = '';
  if (m.kind === 'save-preset') nameInput.value = nextPresetName(ui.selectedTrack);
  else if (m.kind === 'save-sample') nameInput.value = sampleName(m.key).replace(/\.[^.]+$/, '');
  if (!ui.browserView) toggleView('browser');
  fill();
}

export function closeBrowser() {
  if (ui.browserView) toggleView('browser');
}

export function renderBrowser() {
  setClass(panel, 'hidden', !ui.browserView);
}
