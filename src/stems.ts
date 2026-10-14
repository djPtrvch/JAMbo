// Запись стемов. Кнопка ● у ручки громкости дорожки в MIX (и ARM n с MIDI) готовит дорожку к записи
// (кнопка горит); запись всех готовых дорожек начинается с PLAY — с первого шага. Стем дорожки
// идёт по срабатыванию паттернов: если строки идут по сетке (повторы ×N, переходы), пишется всё как играет
// (A ×3, потом B — A, A, A, B), конец — когда строки пошли по кругу; без строк (или одна строка, LOOP ROW)
// паттерн по кругу пишется один раз; остановилась дорожка (пустая ячейка строки) — стем кончается там же.
// Тап по ● во время записи — стем дорожки дописывается до конца прохода паттерна. PLAY во время записи не останавливает сразу: паттерны пишущихся дорожек доигрывают до конца
// прохода, затем стоп. Стем (WAV 24 бит) ложится в папку RECORDINGS библиотеки, во вложенную папку
// «проект дд.мм.гггг» (одна на проект и день), с именем «дорожка чч-мм-сс».
// На пишущейся дорожке мигает красная точка, за 5 секунд до конца записи — чаще.
// Мастер — кнопка ● MASTER в окне MIX: выход мастера (после громкости выхода) по тем же правилам, точка — на MST.

import { isStemRecording, MASTER_STEM, prepareStems, startStem, stopStem } from './audio/engine';
import { addSample, children, createFolder, RECORDINGS } from './library';
import { project } from './project';
import { doc } from './state';

/** Готовые к записи дорожки (кнопка ● горит; не в проекте и не в UNDO). */
const armed = new Set<number>();
/** Паттерны (слоты), уже записанные в стем дорожки: повтор любого из них заканчивает стем. */
const slotOf = new Map<number, Set<number>>();
/** Момент начала стема (первый шаг): на этой границе он не кончается. */
const startAt = new Map<number, number>();
/** PLAY во время записи: остановить транспорт, когда допишутся все стемы. */
let stopAsked = false;
/** Тап по ● во время записи: стем дорожки кончится на конце текущего прохода паттерна. */
const finishAsked = new Set<number>();

export const stemArmed = (i: number) => armed.has(i);
export const stemRecording = (i: number) => isStemRecording(i);
export const anyStemRecording = () => isStemRecording(MASTER_STEM) || doc.tracks.some((_, i) => isStemRecording(i));

// ---------- Мастер (кнопка ● MASTER в окне MIX): выход мастера, по тем же правилам ----------

let masterArmed = false;
/** Уже записанные в стем мастера паттерны играющих дорожек («дорожка:слот»). */
let masterSeen = new Set<string>();
let masterStart = -Infinity;
let masterFinish = false;

export const masterStemArmed = () => masterArmed;
export const masterStemRecording = () => isStemRecording(MASTER_STEM);

/** Паттерны, которые сейчас играют («дорожка:слот»). */
const playingKeys = () => doc.tracks.flatMap((t, i) => (t.stopped ? [] : [`${i}:${t.slot}`]));

/** Кнопка ● MASTER: готовность записи мастера; во время записи — дописать до конца прохода. */
export function toggleMasterStem() {
  if (isStemRecording(MASTER_STEM)) { masterFinish = true; masterArmed = false; return; }
  masterArmed = !masterArmed;
  if (masterArmed) prepareStems();
}

/** Кончится ли запись мастера на ближайшей границе прохода (для частого мигания). */
export function masterEndsAtEdge(arranged: boolean): boolean {
  if (stopAsked || masterFinish) return true;
  return !arranged && playingKeys().every((k) => masterSeen.has(k));
}

function finishMaster(at: number) {
  masterSeen = new Set();
  masterStart = -Infinity;
  masterFinish = false;
  const d = new Date();
  const two = (x: number) => String(x).padStart(2, '0');
  const name = `MASTER ${two(d.getHours())}-${two(d.getMinutes())}-${two(d.getSeconds())}`;
  const folder = `${project.name || 'Project'} ${two(d.getDate())}.${two(d.getMonth() + 1)}.${d.getFullYear()}`;
  void stopStem(MASTER_STEM, name, at).then((key) => { if (key) addSample(recordingsFolder(folder), key, name); });
}
export const stopRequested = () => stopAsked;

/** Кнопка ●: готовность дорожки; во время записи — стем дописывается до конца прохода паттерна. */
export function toggleStem(i: number) {
  if (!doc.tracks[i]) return;
  if (isStemRecording(i)) { finishAsked.add(i); armed.delete(i); return; }
  if (armed.has(i)) armed.delete(i); else { armed.add(i); prepareStems(); }
}

/** PLAY: запись всех готовых и играющих дорожек — с первого шага (at). */
export function stemsOnPlay(at: number) {
  stopAsked = false;
  // Мастер — если что-то играет: с первого шага, как стемы дорожек.
  if (masterArmed && playingKeys().length) {
    masterSeen = new Set(playingKeys());
    masterStart = at;
    void startStem(MASTER_STEM, at);
  }
  for (const i of armed) {
    const t = doc.tracks[i];
    if (!t || t.stopped) continue;
    slotOf.set(i, new Set([t.slot]));
    startAt.set(i, at);
    void startStem(i, at);
  }
}

/** PLAY во время записи: дописать проходы и остановиться. true — запрос принят (не останавливать сразу). */
export function requestStop(): boolean {
  if (!anyStemRecording()) return false;
  stopAsked = true;
  return true;
}

/**
 * Начало шага на тике (паттерны на этом тике уже сменились): у пишущихся дорожек на границе прохода —
 * конец стема, если дорожка остановилась, дальше повтор того же паттерна или просили остановиться.
 * Результат — пора ли остановить транспорт (все стемы дописаны после PLAY).
 */
export function stemsOnStep(at: number, boundary: (i: number) => boolean, arr: { on: boolean; wrapped: boolean }, masterEdge = false): boolean {
  // Мастер: граница прохода — у строки (её самый длинный паттерн) или у самого длинного играющего паттерна;
  // конец — как у дорожек: строки пошли по кругу, без строк — все играющие паттерны уже записаны; всё остановилось.
  if (isStemRecording(MASTER_STEM)) {
    const keys = playingKeys();
    if (!keys.length) finishMaster(at);
    else if (masterEdge && at > masterStart) {
      if (stopAsked || masterFinish || (arr.on ? arr.wrapped : keys.every((k) => masterSeen.has(k)))) finishMaster(at);
      else keys.forEach((k) => masterSeen.add(k));
    }
  }
  for (let i = 0; i < doc.tracks.length; i++) {
    if (!isStemRecording(i)) continue;
    const t = doc.tracks[i];
    if (t.stopped) { finish(i, at); continue; }
    if (!boundary(i) || at <= (startAt.get(i) ?? -Infinity)) continue;
    const seen = slotOf.get(i)!;
    // Строки идут по сетке (повторы, переходы) — пишется всё, как срабатывает; конец — когда строки пошли
    // по кругу. Без строк (или одна строка, LOOP ROW) — паттерн по кругу пишется один раз.
    if (stopAsked || finishAsked.has(i) || (arr.on ? arr.wrapped : seen.has(t.slot))) finish(i, at);
    else seen.add(t.slot);
  }
  if (stopAsked && !anyStemRecording()) { stopAsked = false; return true; }
  return false;
}

/** Транспорт остановили иначе (STOP в конце строк, новый проект): дописать всё сейчас. */
export function stemsOnStop(at: number) {
  stopAsked = false;
  finishAsked.clear();
  for (let i = 0; i < doc.tracks.length; i++) if (isStemRecording(i)) finish(i, at);
  if (isStemRecording(MASTER_STEM)) finishMaster(at);
}

/**
 * Будет ли стем дорожки закончен на ближайшей границе прохода (для частого мигания за 5 с до конца):
 * просили остановиться (PLAY, ●), впереди остановка дорожки или (без строк) повтор того же паттерна.
 */
export function stemEndsAtBoundary(i: number, queued: number | 'stop' | null, arranged: boolean, sceneChanges: boolean): boolean {
  if (stopAsked || finishAsked.has(i) || queued === 'stop') return true;
  if (arranged) return false;
  if (queued !== null) return !!slotOf.get(i)?.has(queued);
  return !sceneChanges;
}

function finish(i: number, at: number) {
  slotOf.delete(i);
  finishAsked.delete(i);
  startAt.delete(i);
  const t = doc.tracks[i];
  const d = new Date();
  const two = (x: number) => String(x).padStart(2, '0');
  const name = `${t?.name ?? i + 1} ${two(d.getHours())}-${two(d.getMinutes())}-${two(d.getSeconds())}`;
  const folder = `${project.name || 'Project'} ${two(d.getDate())}.${two(d.getMonth() + 1)}.${d.getFullYear()}`;
  void stopStem(i, name, at).then((key) => { if (key) addSample(recordingsFolder(folder), key, name); });
}

/** Папка проекта и дня внутри RECORDINGS (создаётся при первой записи). */
function recordingsFolder(name: string): string {
  const have = children(RECORDINGS).find((n) => n.kind === 'folder' && n.name === name);
  return (have ?? createFolder(RECORDINGS, name)).id;
}

/** Запись сэмпла (редактор, REC): копия — в RECORDINGS библиотеки, в папку «проект дд.мм.гггг». */
export function saveRecording(key: string, name: string) {
  const d = new Date();
  const two = (x: number) => String(x).padStart(2, '0');
  addSample(recordingsFolder(`${project.name || 'Project'} ${two(d.getDate())}.${two(d.getMonth() + 1)}.${d.getFullYear()}`), key, name);
}
