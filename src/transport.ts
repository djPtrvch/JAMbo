// Таймер по BPM: двигает шаги дорожек, запускает звук, мигает дорожками и нотами пианоролла,
// ведёт метроном. Probability, Ratchet и Swing (с p-lock и LFO) влияют на звук и мигание.

import { clickAt, triggerTrack } from './audio/engine';
import { stemEndsAtBoundary, stemRecording, stemsOnPlay, stemsOnStep, stemsOnStop } from './stems';
import { PARAM_BY_ID, SEQ_MIX, SEQ_MST, STEPS_PER_PAGE, fromNorm } from './params';
import {
  triggerEnv, endRecTake, activateSlot, audible, doc, inTransition, visibleRows, modulatedNorm, playIndex, playLen, rowFilled, rt, seqAt, slotFilled, stepAt, stopTrack, ui,
  rowLoopOn, baseValue, setAutoClock,
} from './state';

/** Шаги планируются заранее, чтобы звук и щелчок метронома попадали точно в долю. */
const LOOKAHEAD_MS = 100;
let nextTime = 0;
let tick = 0;
interface Flash { time: number; track: number; dur: number; notes: number[]; noteDur: number }
const flashes: Flash[] = [];
const lockEvents: { time: number; track: number; locks: Record<string, number>; until: number }[] = [];

export const stepMs = () => 60000 / doc.bpm / 4;

/** at — момент остановки (performance.now; конец строк — граница такта впереди): там же кончаются стемы. */
export function setPlaying(on: boolean, at = performance.now()) {
  if (!on && ui.playing) stemsOnStop(at);
  ui.playing = on;
  endRecTake();
  flashes.length = 0;
  lockEvents.length = 0;
  rt.playLocks.forEach((l) => { l.until = 0; });
  rt.playPos.fill(-1);
  rt.trackStart.fill(0);
  if (on) {
    // Паттерны, выбранные в сетке до старта, запускаются сразу.
    const queued = rt.queued.some((q) => q !== null);
    rt.queued.forEach((q, i) => applyQueued(i, q));
    if (rt.sceneQueued !== null) startScene(rt.sceneQueued, 0);
    // Иначе — строка старта из меню сетки паттернов (если в ней есть паттерны).
    else if (!queued && !inTransition()) {
      const k = Math.min(doc.arrStart ?? 0, visibleRows() - 1);
      if (rowFilled(k)) startScene(k, 0);
    }
    if (rt.scene) rt.scene.start = 0;
    tick = 0;
    wrappedAt = -1;
    // Первый шаг — сразу, в момент нажатия (не в следующем кадре).
    nextTime = performance.now();
    // Запись стемов готовых дорожек — с первого шага (его время — nextTime).
    stemsOnPlay(nextTime);
    updateTransport(nextTime);
  }
}

/** Шаг дорожки на глобальном тике: проигрываются только выбранные страницы. */
function posAt(i: number, k: number): number {
  return playIndex(seqAt(i), k - rt.trackStart[i]);
}

function applyQueued(i: number, q: number | 'stop' | null) {
  rt.queued[i] = null;
  if (q === 'stop') stopTrack(i);
  else if (q !== null) activateSlot(i, q);
}

/**
 * Выбор паттерна в сетке. Во время проигрывания он ждёт, пока текущий паттерн дорожки
 * доиграет (у остановленной дорожки — начала такта); без проигрывания — сразу.
 */
export function queuePattern(i: number, q: number | 'stop') {
  if (!ui.playing) { applyQueued(i, q); return; }
  rt.queued[i] = rt.queued[i] === q ? null : q;
}

/**
 * Запуск строки (сцены) k на тике at: на каждой дорожке — паттерн этой строки, дорожки
 * с пустой ячейкой останавливаются. Длина прохода — самый длинный паттерн строки.
 */
function startScene(k: number, at: number) {
  let len = 0;
  doc.tracks.forEach((t, i) => {
    rt.queued[i] = null;
    rt.trackStart[i] = at;
    if (!slotFilled(t, k)) { stopTrack(i); return; }
    activateSlot(i, k);
    len = Math.max(len, playLen(t));
  });
  rt.scene = { row: k, start: at, len: len || 16 };
  rt.sceneQueued = null;
}

/**
 * Тап по ячейке строки: без проигрывания строка запускается сразу, во время проигрывания —
 * с начала следующего такта (повторный тап по ожидающей — отмена).
 */
export function queueScene(k: number) {
  if (!ui.playing) { startScene(k, 0); return; }
  rt.sceneQueued = rt.sceneQueued === k ? null : k;
}

/** Следующая видимая строка после k — и пустая (тогда дорожки молчат её проход), или null. */
function nextScene(k: number): number | null {
  return k + 1 < visibleRows() ? k + 1 : null;
}

/** Пора ли запускать ожидающий паттерн дорожки на тике k. */
function atBoundary(i: number, k: number): boolean {
  const t = doc.tracks[i];
  if (t.stopped) return k % 16 === 0;
  return (k - rt.trackStart[i]) % playLen(t) === 0;
}

/** Значение параметра на шаге с учётом p-lock и LFO. */
function playValue(trackIndex: number, id: string, locks: Record<string, number>, at?: number): number {
  const p = PARAM_BY_ID[id];
  return fromNorm(p, modulatedNorm(trackIndex, p, baseValue(trackIndex, id, locks, at), at));
}

/**
 * Часы автоматизации: позиция дорожки i в паттерне (шаги, дробная) в момент at (performance.now) —
 * от тика секвенсора, а не от кадров (кадр может опоздать или пропасть при сворачивании).
 */
setAutoClock((i, at) => {
  if (!ui.playing) return null;
  const t = doc.tracks[i];
  if (!t || t.stopped) return null;
  return playIndex(t, tick + (at - nextTime) / stepMs() - rt.trackStart[i]);
});

function playStep(time: number) {
  const dur = stepMs();
  // Строки и ожидающие паттерны — до записи стемов и звука: на этом тике паттерны уже сменились.
  if (!advanceScenes(time)) return;
  doc.tracks.forEach((_, i) => {
    if (rt.queued[i] !== null && atBoundary(i, tick)) {
      applyQueued(i, rt.queued[i]);
      rt.trackStart[i] = tick;
    }
  });
  // Стемы: на границе прохода повтор того же паттерна или остановка дорожки заканчивают запись;
  // после PLAY во время записи — стоп, когда все стемы дописаны (паттерны доиграли до конца).
  if (stemsOnStep(time, passStart, { on: arranged(), wrapped: wrappedAt === tick })) { setPlaying(false); return; }
  if (tick % 4 === 0) {
    const accent = tick % 16 === 0;
    flashes.push({ time, track: -1, dur: 90, notes: [], noteDur: accent ? 1 : 0 });
    if (ui.metronome) clickAt(time, accent);
  }
  // Свои последовательности MIX и MST: только p-lock микшера и мастера на время шага.
  for (const k of [SEQ_MIX, SEQ_MST]) {
    const pos = posAt(k, tick);
    rt.playPos[k] = pos;
    const s = stepAt(seqAt(k), pos);
    if (s && Object.keys(s.locks).length > 0) lockEvents.push({ time, track: k, locks: s.locks, until: time + dur });
  }
  doc.tracks.forEach((t, i) => {
    if (t.stopped) { rt.playPos[i] = -1; return; }
    const pos = posAt(i, tick);
    rt.playPos[i] = pos;
    const s = stepAt(t, pos);
    // P-lock шага (и на шаге без ноты) показываем на ручках, пока идёт шаг.
    if (s && Object.keys(s.locks).length > 0) lockEvents.push({ time, track: i, locks: s.locks, until: time + dur });
    // Заглушённая дорожка играет дальше (её выход глушит движок): уровень виден в MIX, она источник
    // sidechain и динамического EQ; не мигает.
    if (!s?.on) return;
    if (Math.random() * 100 >= playValue(i, 'prob', s.locks, time)) return;
    const ratchet = playValue(i, 'ratchet', s.locks, time) + 1;
    const swing = playValue(i, 'swing', s.locks, time);
    const offset = pos % 2 === 1 ? ((swing - 50) / 50) * dur : 0;
    const sub = dur / ratchet;
    for (let r = 0; r < ratchet; r++) {
      const at = time + offset + r * sub;
      // Нота от 2 шагов держится до самого конца (до следующей ноты, без провала на стыке); в 1 шаг — как раньше.
      const noteDur = ratchet > 1 ? sub * 0.6 : s.len >= 2 ? s.len * dur : dur * 0.9;
      // ENV запускается в момент ноты (запланирован заранее, как и сама нота): начальные
      // значения ноты берут ENV на этот момент, а не хвост предыдущей.
      triggerEnv(i, at, noteDur);
      // Нота длиной от 2 шагов держит уровень до своего конца (Decay — после); в 1 шаг — как раньше.
      triggerTrack(i, at, s.notes, s.locks, s.sound, ratchet === 1 && s.len >= 2 ? noteDur / 1000 : undefined);
      if (audible(i)) flashes.push({ time: at, track: i, dur: Math.min(90, sub * 0.6), notes: s.notes, noteDur });
    }
  });
  tick++;
}

/**
 * Строки: ожидающая — с начала такта; играющая с повторами — после N проходов следующая строка.
 * false — транспорт остановлен (строки кончились, AT THE END: STOP).
 */
function advanceScenes(time: number): boolean {
  if (rt.sceneQueued !== null && tick % 16 === 0) startScene(rt.sceneQueued, tick);
  else if (rt.scene && sceneEndsAt(tick)) {
    const n = nextScene(rt.scene.row);
    if (n !== null) startScene(n, tick);
    // Строки кончились: STOP — останавливается всё (и дорожки, запущенные по отдельности),
    // LOOP — снова с начала, со строки старта.
    else if (doc.arrEnd === 'stop') { setPlaying(false, time); return false; }
    else { startScene(Math.min(doc.arrStart ?? 0, visibleRows() - 1), tick); wrappedAt = tick; }
  }
  return true;
}

/** Тик, на котором строки пошли по кругу (AT THE END: LOOP) — там кончаются стемы. */
let wrappedAt = -1;
/** Строки идут по сетке: играет строка с повторами, строк больше одной и LOOP ROW выключена. */
function arranged(): boolean {
  return !!rt.scene && doc.scenes[rt.scene.row].repeats > 0 && !rowLoopOn() && visibleRows() > 1;
}

/** Играющая строка с повторами кончается на тике k (одна строка в сетке или LOOP ROW — играет по кругу). */
function sceneEndsAt(k: number): boolean {
  if (!rt.scene) return false;
  const reps = doc.scenes[rt.scene.row].repeats;
  return reps > 0 && !rowLoopOn() && visibleRows() > 1 && k - rt.scene.start >= reps * rt.scene.len;
}

/** Тик — начало прохода паттерна дорожки (в том числе только что запущенного). */
function passStart(i: number): boolean {
  const t = doc.tracks[i];
  if (!t || t.stopped) return false;
  return (tick - rt.trackStart[i]) % playLen(t) === 0;
}

/**
 * Сколько осталось до конца записи стема дорожки, мс (null — не пишется или конец пока не виден):
 * ближайшая граница прохода, если на ней стем кончится.
 */
export function stemEndIn(i: number, now: number): number | null {
  const t = doc.tracks[i];
  if (!t || !ui.playing || !stemRecording(i) || t.stopped) return null;
  const len = playLen(t);
  const n = tick - rt.trackStart[i];
  const at = rt.trackStart[i] + Math.max(1, Math.ceil(n / len)) * len;
  const scene = rt.sceneQueued !== null || (!!rt.scene && sceneEndsAt(at));
  if (stemEndsAtBoundary(i, rt.queued[i], arranged(), scene)) return (at - tick) * stepMs() + (nextTime - now);
  // Строки по сетке: стем кончится, когда последняя строка доиграет (дальше — по кругу или STOP).
  if (arranged() && rt.scene && nextScene(rt.scene.row) === null) {
    const end = rt.scene.start + doc.scenes[rt.scene.row].repeats * rt.scene.len;
    return (end - tick) * stepMs() + (nextTime - now);
  }
  return null;
}

/** Вызывается каждый кадр. */
export function updateTransport(now: number) {
  if (ui.playing) {
    // Если вкладка была в фоне — не догоняем пропущенные шаги.
    if (now - nextTime > 1000) nextTime = now;
    while (ui.playing && now + LOOKAHEAD_MS >= nextTime) {
      playStep(nextTime);
      nextTime += stepMs();
    }
  }
  for (let k = lockEvents.length - 1; k >= 0; k--) {
    const e = lockEvents[k];
    if (now < e.time) continue;
    lockEvents.splice(k, 1);
    rt.playLocks[e.track] = { locks: e.locks, until: e.until };
  }
  for (let k = flashes.length - 1; k >= 0; k--) {
    const f = flashes[k];
    if (now < f.time) continue;
    flashes.splice(k, 1);
    if (f.track < 0) {
      rt.beatUntil = now + f.dur;
      rt.beatAccent = f.noteDur === 1;
      continue;
    }
    rt.flashUntil[f.track] = Math.max(rt.flashUntil[f.track], now + f.dur);
    rt.noteFlash[f.track] = { notes: f.notes, until: now + f.noteDur };
  }
}

/**
 * Шаг для записи с REC: ближайший к моменту нажатия (квантизация к 1/16).
 * merge = нажатие попало на тот же шаг, что и предыдущее (аккорд пальцами).
 */
let lastRec = { track: -1, tick: -1 };
/** Длина записанной ноты в шагах по времени удержания клавиши (округление до шага, не меньше 1). */
export const recLength = (ms: number) => Math.max(1, Math.round(ms / stepMs()));

export function recStep(trackIndex: number, now: number): { index: number; merge: boolean } | null {
  if (!ui.playing) return null;
  const k = Math.max(0, tick + Math.round((now - nextTime) / stepMs()));
  const merge = lastRec.track === trackIndex && lastRec.tick === k;
  lastRec = { track: trackIndex, tick: k };
  return { index: posAt(trackIndex, k), merge };
}

/** Пройдено проходов играющей строки (0-based) и доля текущего прохода. */
export function sceneProgress(): { pass: number; frac: number } | null {
  if (!rt.scene || !ui.playing) return null;
  const n = Math.max(0, tick - 1 - rt.scene.start);
  return { pass: Math.floor(n / rt.scene.len), frac: ((n % rt.scene.len) + 1) / rt.scene.len };
}

/** Страница, на которой сейчас играет дорожка. */
export function playPage(trackIndex: number): number {
  const pos = rt.playPos[trackIndex];
  return pos < 0 ? -1 : Math.floor(pos / STEPS_PER_PAGE);
}
