// Браузер библиотеки сэмплов и пресетов (library.ts) на месте центра экрана, как EQ.
// Открывается из меню звука (SAMPLE, LOAD — загрузка; SAVE — сохранить пресет синта) и из
// редактора сэмпла (LOAD; SAVE — сохранить сэмпл). Папки вложенные: тап — войти, ‹ — на уровень
// выше. Свайп влево по строке открывает справа EDIT (имя), EXPORT (в «Файлы» — на iPad или в
// iCloud Drive: сэмпл — исходным файлом, пресет — .jambopreset, папка — .zip со всем содержимым)
// и корзину (у папки с содержимым — второй тап для подтверждения).
// Загрузка: тап по сэмплу или пресету ставит его на дорожку (и в её папку), браузер остаётся
// открытым — можно пробовать звуки пианороллом; звук дорожки в списке подсвечен. Удержание
// сэмпла — выбор нескольких: тапы отмечают, LOAD кладёт все в папку дорожки (первый звучит,
// остальные — на стрелках под окном сэмпла), как прежний выбор нескольких файлов. Зажатые шаги (меню звука для шагов) получают
// сэмпл как свой звук. IMPORT — файлы из «Файлов» (iPad, iCloud Drive) в открытую папку: аудио,
// .jambopreset и .zip (папки архива восстанавливаются).
// Сохранение: внизу имя и SAVE HERE — в открытую папку.
// LOAD TABLE (из меню звука у дорожки с WTABLE): только папки и таблицы; в корне — папка
// BUILT-IN TABLES (встроенные, всегда есть); IMPORT читает WAV как таблицу (размер кадра — из метки
// Serum или выбором 256…2048 / AUTO); тап по таблице ставит её на дорожку.

import { previewPreset, previewSample, useLibrarySample } from '../audio/engine';
import {
  BUILTIN_TABLES, FRAME_SIZES, MAX_TABLE_BYTES, autoFrameSize, builtinKey, framesFor, parseWav, userTableKey, type WavTable,
} from '../audio/wavetable';
import { exportNode, importInto } from '../libio';
import {
  ROOT, RECORDINGS, addPreset, addSample, addTable, children, countInside, createFolder, freeName, node, onLibraryChanged, overwrite, path, remove, rename,
  sameName, type LibNode,
} from '../library';
import { isJambo, SYNTH_ENGINES, synthEngine } from '../params';
import {
  addPresetToFolder, addSamplesQuiet, doc, folderItemName, nextPresetName, presetFromTrack, setFolder, type FolderItem,
  sampleName, setStepSound, setTrackTable, toggleView, ui,
} from '../state';
import { putSample, sampleKey } from '../storage';
import { closeButton, h, setClass, setText } from './dom';
import { makePopup, openInput, popupButton, type Popup } from './popup';

/** Кнопка SAVE HERE (к ней привязано окно «перезаписать или сохранить как»). */
let saveHereBtn: HTMLElement;
/** Имена в библиотеке — до 40 знаков (как в library.ts). */
const LIB_NAME_MAX = 40;

/** Что делает браузер: загрузка (в дорожку или на зажатые шаги) или сохранение пресета / сэмпла. */
type Mode =
  | { kind: 'load'; steps: number[] }
  | { kind: 'load-table' }
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
/** Выбор нескольких сэмплов (удержание сэмпла): id отмеченных; null — выбора нет. */
let picked: Set<string> | null = null;
let pickBar: HTMLElement;
let pickText: HTMLElement;
/** Что загружено последним (строка внизу). */
let loadedMsg = '';
const HOLD_MS = 500;
/** Удержание сработало — следующий click (после отпускания, уже по перерисованной строке) не тап. */
let swallowClick = false;
let mode: Mode = { kind: 'load', steps: [] };
/** Папка, где корзина ждёт второго тапа (подтверждение удаления непустой папки). */
let confirmId = '';

const fail = (what: string) => (e: unknown) => { console.error(what, e); window.alert(`${what} failed`); };

function iconFor(n: LibNode): string {
  if (n.kind === 'folder') return n.system ? '●' : '▸';
  if (n.kind === 'table') return '▦';
  return n.kind === 'sample' ? '∿' : '◆';
}

/** Виртуальная папка встроенных таблиц WTABLE (в режиме LOAD TABLE, в корне). */
const BUILTIN_DIR = 'builtin-tables';
const builtinFolder: LibNode = { id: BUILTIN_DIR, parent: ROOT, kind: 'folder', name: 'BUILT-IN TABLES', system: true, updated: 0 };
const builtinNodes: LibNode[] = BUILTIN_TABLES.map((name) => ({ id: `bt:${name}`, parent: BUILTIN_DIR, kind: 'table', name, key: builtinKey(name), system: true, updated: 0 }));
const tableMode = () => mode.kind === 'load-table';

/** Строки открытой папки: в LOAD TABLE — папки и таблицы, иначе — всё, кроме таблиц. */
function items(): LibNode[] {
  if (tableMode()) {
    if (folder === BUILTIN_DIR) return builtinNodes;
    const list = children(folder).filter((n) => n.kind === 'folder' || n.kind === 'table');
    return folder === ROOT ? [builtinFolder, ...list] : list;
  }
  return children(folder).filter((n) => n.kind !== 'table');
}

function detail(n: LibNode): string {
  if (n.id === BUILTIN_DIR) return `${builtinNodes.length}`;
  if (n.kind === 'table') return n.key?.startsWith('wt:') ? `table · ${n.key.split(':').pop()}` : 'built-in table';
  if (n.kind === 'folder') {
    const c = children(n.id).length;
    return n.id === RECORDINGS && !c ? 'track stems' : `${c}`;
  }
  if (n.kind === 'preset') {
    const e = n.preset ? synthEngine(n.preset.sound) : null;
    // У движков Plaits — с префиксом MI, у своих движков JAMbo — без него.
    return e !== null ? `${isJambo(e) ? '' : 'MI '}${SYNTH_ENGINES[e].name}` : 'preset';
  }
  return 'sample';
}

/** Тап по строке: папка — войти; сэмпл или пресет — загрузить (в режиме загрузки). */
async function open(n: LibNode) {
  if (n.kind === 'folder') { if (!picked) { folder = n.id; confirmId = ''; fill(); } return; }
  if (mode.kind === 'load-table') {
    if (n.kind !== 'table' || n.key === undefined) return;
    setTrackTable(ui.selectedTrack, n.key);
    loadedMsg = `${trackName(ui.selectedTrack)}: table ${n.name}`;
    fill();
    return;
  }
  if (mode.kind !== 'load') return;
  // Режим выбора: тап отмечает сэмпл.
  if (picked) {
    if (picked.has(n.id)) picked.delete(n.id); else picked.add(n.id);
    fill();
    return;
  }
  const track = ui.selectedTrack;
  if (n.kind === 'sample' && n.key) {
    if (!(await useLibrarySample(n.key, n.name))) { window.alert('This sample is no longer stored on this iPad'); return; }
    // Звук дорожки: в её папке остаётся только он (несколько — удержанием, выбором и LOAD).
    if (mode.steps.length) { addSamplesQuiet(track, [n.key]); setStepSound(track, mode.steps, n.key); } else setFolder(track, [{ sample: n.key }]);
  } else if (n.kind === 'preset' && n.preset && !mode.steps.length) {
    setFolder(track, [{ preset: n.preset }]);
  } else return;
  loadedMsg = `${mode.steps.length ? `Step ${mode.steps.map((s) => s + 1).join(', ')}` : trackName(track)}: ${n.name}`;
  fill();
}

const trackName = (i: number) => `Track ${doc.tracks[i]?.name ?? i + 1}`;

/** Звук дорожки сейчас — этот узел (подсветка в списке). */
function isCurrent(n: LibNode): boolean {
  if (ui.channel !== 'track') return false;
  const t = doc.tracks[ui.selectedTrack];
  if (n.kind === 'table') return tableMode() && (t.table ?? '') === n.key;
  if (n.kind === 'sample') return !!n.key && t.sample === n.key;
  if (n.kind === 'preset' && n.preset) return t.sample === n.preset.sound && folderItemName(ui.selectedTrack) === n.name;
  return false;
}

/** LOAD в режиме выбора: в папке дорожки — только отмеченные сэмплы и пресеты (по списку), первый звучит. */
async function loadPicked() {
  if (!picked) return;
  const list = children(folder).filter((n) => n.kind !== 'folder' && picked!.has(n.id));
  const items: FolderItem[] = [];
  for (const n of list) {
    if (n.kind === 'sample' && n.key) { if (await useLibrarySample(n.key, n.name)) items.push({ sample: n.key }); }
    else if (n.kind === 'preset' && n.preset) items.push({ preset: n.preset });
  }
  setFolder(ui.selectedTrack, items);
  loadedMsg = `${trackName(ui.selectedTrack)}: ${items.length} sound${items.length === 1 ? '' : 's'} in the track folder`;
  picked = null;
  fill();
}

/** Строка: свайп влево открывает EDIT (и EXPORT у сэмпла) и корзину справа. */
function libRow(n: LibNode): HTMLElement {
  const row = h('div', 'project-row lib-row');
  const acts = h('div', 'lib-acts');
  const edit = h('div', 'lib-act', 'EDIT');
  edit.addEventListener('pointerup', () => openInput(edit, n.name, (v) => rename(n.id, v), false, LIB_NAME_MAX));
  const exp = h('div', 'lib-act', 'EXPORT');
  // EXPORT: окно «Поделиться» → «Сохранить в Файлы» (папка на iPad или в iCloud Drive).
  exp.addEventListener('pointerup', () => { void exportNode(n.id).catch(fail('Export')); });
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
  acts.append(edit, exp, trash);
  const actsW = ACT_W * acts.children.length;
  const item = h('div', 'popup-btn project-item lib-item');
  const name = h('div', 'lib-name', `${iconFor(n)}  ${n.name}`);
  // RECORDINGS — обычным шрифтом, перед именем маленькая красная точка.
  if (n.id === RECORDINGS) { name.textContent = n.name; name.prepend(h('span', 'lib-rec-dot')); }
  // Слева — столбец предпрослушки: ▶ у сэмпла и пресета (не загружает звук и не меняет выбор).
  const play = h('div', 'lib-play', n.kind === 'sample' || n.kind === 'preset' ? '▶' : '');
  if (play.textContent) {
    for (const t of ['pointerdown', 'pointerup', 'pointercancel'] as const) play.addEventListener(t, (e) => e.stopPropagation());
    play.addEventListener('click', (e) => {
      e.stopPropagation();
      if (n.kind === 'sample' && n.key) void previewSample(n.key).catch(fail('Preview'));
      else if (n.kind === 'preset' && n.preset) previewPreset(n.preset.sound, n.preset.params);
      play.classList.add('on');
      window.setTimeout(() => play.classList.remove('on'), 200);
    });
  }
  // У папок (и таблиц) столбца нет — имя от левого края.
  if (play.textContent) item.append(play);
  item.append(name, h('div', 'lib-detail', `${detail(n)}${n.kind === 'folder' ? '  ›' : ''}`));
  item.classList.toggle('system', !!n.system);
  item.classList.toggle('recordings', n.id === RECORDINGS);
  item.classList.toggle('current', (mode.kind === 'load' || tableMode()) && !picked && isCurrent(n));
  item.classList.toggle('picked', !!picked?.has(n.id));
  row.append(acts, item);

  let id = -1;
  let x0 = 0;
  let base = 0;
  let dx = 0;
  // Строка не уезжает, а сужается справа (имя у левого края остаётся видно).
  const place = (x: number) => { item.style.width = x ? `calc(100% - ${-x}px)` : ''; };
  // Удержание сэмпла (без сдвига) — выбор нескольких.
  let holdTimer = 0;
  let held = false;
  let swiped = false;
  item.addEventListener('pointerdown', (e) => {
    id = e.pointerId;
    x0 = e.clientX;
    base = row.classList.contains('open') ? -actsW : 0;
    dx = 0;
    held = false;
    swiped = false;
    swallowClick = false;
    item.classList.add('dragging');
    clearTimeout(holdTimer);
    if (n.kind !== 'folder' && mode.kind === 'load' && !mode.steps.length && !picked && !base) {
      holdTimer = window.setTimeout(() => {
        if (Math.abs(dx) > 10) return;
        held = true;
        swallowClick = true;
        picked = new Set([n.id]);
        fill();
      }, HOLD_MS);
    }
  });
  item.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id || n.system) return;
    dx = e.clientX - x0;
    if (Math.abs(dx) > 10) clearTimeout(holdTimer);
    if (Math.abs(dx) > 6 && !picked) place(Math.max(-actsW, Math.min(0, base + dx)));
  });
  // Тап — по click: в прокручиваемом списке iOS может прислать pointercancel вместо pointerup,
  // а click приходит только на настоящий тап (не на прокрутку и не на свайп).
  item.addEventListener('click', () => {
    if (held || swiped || swallowClick) { held = false; swiped = false; swallowClick = false; return; }
    if (row.classList.contains('open')) { row.classList.remove('open'); place(0); return; }
    void open(n).catch(fail('Load'));
  });
  const end = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = -1;
    item.classList.remove('dragging');
    clearTimeout(holdTimer);
    swiped = Math.abs(dx) > 6;
    if (held || !swiped || picked) return;
    if (n.system) return;
    const opened = base + dx < -actsW / 2;
    // Открыта может быть только одна строка.
    if (opened) list.querySelectorAll('.lib-row.open').forEach((r) => { if (r !== row) { r.classList.remove('open'); (r.querySelector('.lib-item') as HTMLElement).style.width = ''; } });
    row.classList.toggle('open', opened);
    place(opened ? -actsW : 0);
  };
  item.addEventListener('pointerup', end);
  item.addEventListener('pointercancel', end);
  return row;
}

function fill() {
  if (folder === BUILTIN_DIR && !tableMode()) folder = ROOT;
  if (!node(folder) && folder !== ROOT && folder !== BUILTIN_DIR) folder = ROOT;
  const crumbs = folder === BUILTIN_DIR ? [builtinFolder.name] : path(folder).map((n) => n.name);
  setText(pathText, [tableMode() ? 'TABLES' : 'LIBRARY', ...crumbs].join('  /  '));
  setClass(upBtn, 'disabled', folder === ROOT);
  const rows = items();
  list.replaceChildren(...(rows.length ? rows.map(libRow) : [h('div', 'settings-note lib-empty', folder === RECORDINGS
    ? 'Stems recorded from each track will be saved here.'
    : tableMode() ? 'No tables here. IMPORT a wavetable WAV from the iPad or iCloud Drive.'
    : 'Empty folder. NEW FOLDER, or IMPORT files from the iPad or iCloud Drive.')]));
  setClass(saveBar, 'hidden', mode.kind === 'load' || tableMode());
  setClass(pickBar, 'hidden', !picked);
  if (picked) setText(pickText, `${picked.size} selected · tap samples and presets to add or remove`);
  setText(note, loadedMsg ? `Loaded → ${loadedMsg}`
    : mode.kind === 'load' && mode.steps.length ? `Loading a sample onto step ${mode.steps.map((s) => s + 1).join(', ')}.`
    : mode.kind === 'load' ? 'Tap a sample or preset to load it on the track. Hold a sample to select several.'
    : tableMode() ? 'Tap a table to load it on the WTABLE track. IMPORT reads WAV files as wavetables.'
    : 'Choose a folder, name it and SAVE HERE.');
}

export function buildBrowser(): HTMLElement {
  panel = h('div', 'eq-panel browser hidden');
  const head = h('div', 'eq-bar lib-head');
  upBtn = h('div', 'btn eq-tool lib-up', '‹');
  upBtn.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const n = folder === BUILTIN_DIR ? builtinFolder : node(folder);
    if (n) { folder = n.parent; confirmId = ''; picked = null; fill(); }
  });
  pathText = h('div', 'lib-path');
  const newFolder = h('div', 'btn eq-tool', 'NEW FOLDER');
  newFolder.addEventListener('pointerup', () => openInput(newFolder, 'New folder', (v) => { createFolder(folder, v); }, false, LIB_NAME_MAX));
  // IMPORT — поле выбора файла прозрачно поверх кнопки (на iOS выбор файла — только прямым тапом).
  const importBtn = h('div', 'btn eq-tool sample-pick', 'IMPORT');
  const input = h('input', 'sample-file');
  input.type = 'file';
  input.multiple = true;
  // Без accept: на iOS список расширений (.jambopreset, .zip) может сделать файлы в «Файлах»
  // серыми — выбрать можно любой файл, неподходящие пропускаются при импорте.
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? []);
    input.value = '';
    if (!files.length) return;
    // LOAD TABLE: WAV-файлы — таблицами WTABLE в открытую папку.
    if (tableMode()) { void importTables(folder === BUILTIN_DIR ? ROOT : folder, files, importBtn).catch(fail('Import')); return; }
    // Аудио, пресеты (.jambopreset) и папки архивом (.zip) — в открытую папку.
    void importInto(folder, files).then((k) => { if (!k) window.alert('Nothing to import: no audio, presets or folders found'); })
      .catch(fail('Import'));
  });
  importBtn.append(input);
  const close = closeButton(closeBrowser);
  head.append(upBtn, pathText, newFolder, importBtn, close);

  list = h('div', 'project-list lib-list');
  saveBar = h('div', 'eq-bar lib-save hidden');
  nameInput = h('input', 'rename-input lib-name-input');
  nameInput.type = 'text';
  nameInput.maxLength = LIB_NAME_MAX;
  const saveHere = h('div', 'btn eq-tool lib-save-btn', 'SAVE HERE');
  saveHereBtn = saveHere;
  saveHere.addEventListener('pointerup', () => save());
  nameInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') save(); });
  saveBar.append(h('div', 'lib-save-label', 'NAME'), nameInput, saveHere);
  // Выбор нескольких: сколько отмечено, LOAD и CANCEL.
  pickBar = h('div', 'eq-bar lib-save hidden');
  pickText = h('div', 'lib-path');
  const pickLoad = h('div', 'btn eq-tool lib-save-btn', 'LOAD');
  pickLoad.addEventListener('pointerup', () => { void loadPicked().catch(fail('Load')); });
  const pickCancel = h('div', 'btn eq-tool', 'CANCEL');
  pickCancel.addEventListener('pointerup', () => { picked = null; fill(); });
  pickBar.append(pickText, pickLoad, pickCancel);
  note = h('div', 'settings-note lib-note');
  panel.append(head, list, saveBar, pickBar, note);
  onLibraryChanged(() => { if (ui.browserView) fill(); });
  return panel;
}

/**
 * IMPORT в LOAD TABLE: WAV (16/24 бит или float 32; стерео — левый канал, до 4 МБ) — таблицей WTABLE.
 * Размер кадра — из метки Serum ('clm '), иначе выбор 256 / 512 / 1024 / 2048 или AUTO (по длине).
 */
async function importTables(into: string, files: File[], anchor: HTMLElement) {
  let added = 0;
  for (const f of files) {
    if (f.size > MAX_TABLE_BYTES) { window.alert(`${f.name}: a wavetable must be up to 4 MB`); continue; }
    const bytes = await f.arrayBuffer();
    let w: WavTable;
    try { w = parseWav(bytes); } catch { continue; }
    const size = w.clm && FRAME_SIZES.includes(w.clm) ? w.clm : await askFrameSize(f.name, w, anchor);
    if (!size) continue;
    const key = await sampleKey(bytes);
    await putSample({ key, name: f.name, bytes });
    addTable(into, userTableKey(key, size), f.name.replace(/\.[^.]+$/, ''));
    added++;
  }
  if (files.length && !added) window.alert('Nothing to import: no wavetable WAV files found');
}

let sizePopup: Popup | null = null;
/** Размер кадра таблицы: AUTO (по длине файла) или 256…2048; null — отмена. */
function askFrameSize(name: string, w: WavTable, anchor: HTMLElement): Promise<number | null> {
  sizePopup ??= makePopup();
  const pop = sizePopup;
  return new Promise((resolve) => {
    const pick = (v: number | null) => { pop.close(); resolve(v); };
    const auto = autoFrameSize(w);
    pop.box.replaceChildren(
      h('div', 'popup-title', `${name}: frame size`),
      popupButton(`AUTO · ${auto} · ${framesFor(w, auto)} frames`, () => pick(auto)),
      ...FRAME_SIZES.map((s) => popupButton(`${s} · ${framesFor(w, s)} frames`, () => pick(s))),
      popupButton('CANCEL', () => pick(null)),
    );
    pop.openAt(anchor, 260);
  });
}

/** SAVE HERE: пресет синта дорожки или сэмпл — в открытую папку. */
function save() {
  const into = folder === RECORDINGS ? ROOT : folder;
  const name = nameInput.value.trim() || (mode.kind === 'save-sample' ? sampleName(mode.key) : '');
  nameInput.blur();
  const same = sameName(into, name);
  // Такое имя уже есть — вопрос: перезаписать или сохранить под другим именем.
  if (same) { askOverwrite(same.id, into, name); return; }
  saveAs(into, name);
}

function saveAs(into: string, name: string, over?: string) {
  if (mode.kind === 'save-preset') {
    const p = presetFromTrack(ui.selectedTrack, name);
    if (!p) return;
    if (over) overwrite(over, { preset: p });
    const n = over ? node(over)! : addPreset(into, p);
    addPresetToFolder(ui.selectedTrack, { ...p, name: n.name });
  } else if (mode.kind === 'save-sample') {
    if (over) overwrite(over, { key: mode.key });
    else addSample(into, mode.key, name);
  }
  mode = { kind: 'load', steps: [] };
  fill();
}

let askPopup: Popup | null = null;
function askOverwrite(id: string, into: string, name: string) {
  askPopup ??= makePopup();
  const pop = askPopup;
  pop.box.replaceChildren(
    h('div', 'popup-title', `“${name}” already exists`),
    popupButton('OVERWRITE', () => { pop.close(); saveAs(into, name, id); }),
    popupButton('SAVE AS…', () => {
      pop.close();
      // Новое имя (по умолчанию свободное «Name 2»); если и оно занято — снова вопрос.
      openInput(saveHereBtn, freeName(into, name), (v) => {
        const nm = v.trim() || freeName(into, name);
        const again = sameName(into, nm);
        if (again) askOverwrite(again.id, into, nm); else saveAs(into, nm);
      }, false, LIB_NAME_MAX);
    }),
    popupButton('CANCEL', () => pop.close()),
  );
  pop.openAt(saveHereBtn, 220);
}

/** Открыть браузер: загрузка (steps — зажатые шаги) или сохранение. */
export function openBrowser(m: Mode) {
  mode = m;
  confirmId = '';
  picked = null;
  loadedMsg = '';
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
