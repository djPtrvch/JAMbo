// Таймер по BPM: двигает шаги дорожек, запускает звук, мигает дорожками и нотами пианоролла,
// ведёт метроном. Probability, Ratchet и Swing (с p-lock и LFO) влияют на звук и мигание.

import { clickAt, triggerTrack } from './audio/engine';
import { PARAM_BY_ID, STEPS_PER_PAGE, fromNorm } from './params';
import { triggerEnv, activateSlot, audible, doc, modulatedNorm, playRange, rt, stepAt, stopTrack, ui } from './state';

/** Шаги планируются заранее, чтобы звук и щелчок метронома попадали точно в долю. */
const LOOKAHEAD_MS = 100;
let nextTime = 0;
let tick = 0;
interface Flash { time: number; track: number; dur: number; notes: number[]; noteDur: number }
const flashes: Flash[] = [];
const lockEvents: { time: number; track: number; locks: Record<string, number>; until: number }[] = [];

export const stepMs = () => 60000 / doc.bpm / 4;

export function setPlaying(on: boolean) {
  ui.playing = on;
  flashes.length = 0;
  lockEvents.length = 0;
  rt.playLocks.forEach((l) => { l.until = 0; });
  rt.playPos.fill(-1);
  rt.trackStart.fill(0);
  if (on) {
    // Паттерны, выбранные в сетке до старта, запускаются сразу.
    rt.queued.forEach((q, i) => applyQueued(i, q));
    tick = 0;
    nextTime = performance.now() + 30;
  }
}

/** Шаг дорожки на глобальном тике: проигрываются только выбранные страницы. */
function posAt(i: number, k: number): number {
  const [a, b] = playRange(doc.tracks[i]);
  const n = k - rt.trackStart[i];
  const len = b - a + 1;
  return a + (((n % len) + len) % len);
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

/** Пора ли запускать ожидающий паттерн дорожки на тике k. */
function atBoundary(i: number, k: number): boolean {
  const t = doc.tracks[i];
  if (t.stopped) return k % 16 === 0;
  const [a, b] = playRange(t);
  return (k - rt.trackStart[i]) % (b - a + 1) === 0;
}

/** Значение параметра на шаге с учётом p-lock и LFO. */
function playValue(trackIndex: number, id: string, locks: Record<string, number>): number {
  const p = PARAM_BY_ID[id];
  const base = locks[id] ?? doc.tracks[trackIndex].params[id];
  return fromNorm(p, modulatedNorm(trackIndex, p, base));
}

function playStep(time: number) {
  const dur = stepMs();
  if (tick % 4 === 0) {
    const accent = tick % 16 === 0;
    flashes.push({ time, track: -1, dur: 90, notes: [], noteDur: accent ? 1 : 0 });
    if (ui.metronome) clickAt(time, accent);
  }
  doc.tracks.forEach((t, i) => {
    if (rt.queued[i] !== null && atBoundary(i, tick)) {
      applyQueued(i, rt.queued[i]);
      rt.trackStart[i] = tick;
    }
    if (t.stopped) { rt.playPos[i] = -1; return; }
    const pos = posAt(i, tick);
    rt.playPos[i] = pos;
    const s = stepAt(t, pos);
    // P-lock шага (и на шаге без ноты) показываем на ручках, пока идёт шаг.
    if (s && Object.keys(s.locks).length > 0) lockEvents.push({ time, track: i, locks: s.locks, until: time + dur });
    if (!s?.on || !audible(i)) return;
    if (Math.random() * 100 >= playValue(i, 'prob', s.locks)) return;
    const ratchet = playValue(i, 'ratchet', s.locks) + 1;
    const swing = playValue(i, 'swing', s.locks);
    const offset = pos % 2 === 1 ? ((swing - 50) / 50) * dur : 0;
    const sub = dur / ratchet;
    for (let r = 0; r < ratchet; r++) {
      triggerTrack(i, time + offset + r * sub, s.notes, s.locks);
      flashes.push({ time: time + offset + r * sub, track: i, dur: Math.min(90, sub * 0.6), notes: s.notes, noteDur: ratchet > 1 ? sub * 0.6 : s.len * dur * 0.9 });
    }
  });
  tick++;
}

/** Вызывается каждый кадр. */
export function updateTransport(now: number) {
  if (ui.playing) {
    // Если вкладка была в фоне — не догоняем пропущенные шаги.
    if (now - nextTime > 1000) nextTime = now;
    while (now + LOOKAHEAD_MS >= nextTime) {
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
    triggerEnv(f.track, now, f.noteDur);
    rt.noteFlash[f.track] = { notes: f.notes, until: now + f.noteDur };
  }
}

/**
 * Шаг для записи с REC: ближайший к моменту нажатия (квантизация к 1/16).
 * merge = нажатие попало на тот же шаг, что и предыдущее (аккорд пальцами).
 */
let lastRec = { track: -1, tick: -1 };
export function recStep(trackIndex: number, now: number): { index: number; merge: boolean } | null {
  if (!ui.playing) return null;
  const k = Math.max(0, tick + Math.round((now - nextTime) / stepMs()));
  const merge = lastRec.track === trackIndex && lastRec.tick === k;
  lastRec = { track: trackIndex, tick: k };
  return { index: posAt(trackIndex, k), merge };
}

/** Страница, на которой сейчас играет дорожка. */
export function playPage(trackIndex: number): number {
  const pos = rt.playPos[trackIndex];
  return pos < 0 ? -1 : Math.floor(pos / STEPS_PER_PAGE);
}
