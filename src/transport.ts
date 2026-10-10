// Таймер по BPM без звука: двигает шаги дорожек и заставляет их мигать.
// Probability, Ratchet и Swing (с p-lock и LFO) влияют на мигание, чтобы их можно было проверить на глаз.

import { PARAM_BY_ID, STEPS_PER_PAGE, fromNorm } from './params';
import { audible, doc, modulatedNorm, rt, stepAt, ui } from './state';

let nextTime = 0;
let tick = 0;
const flashes: { time: number; track: number; dur: number }[] = [];

const stepMs = () => 60000 / doc.bpm / 4;

export function setPlaying(on: boolean) {
  ui.playing = on;
  flashes.length = 0;
  rt.playPos.fill(-1);
  if (on) {
    tick = 0;
    nextTime = performance.now() + 30;
  }
}

/** Значение параметра на шаге с учётом p-lock и LFO. */
function playValue(trackIndex: number, id: string, locks: Record<string, number>): number {
  const p = PARAM_BY_ID[id];
  const base = locks[id] ?? doc.tracks[trackIndex].params[id];
  return fromNorm(p, modulatedNorm(trackIndex, p, base));
}

function playStep(now: number) {
  const dur = stepMs();
  doc.tracks.forEach((t, i) => {
    const pos = tick % t.length;
    rt.playPos[i] = pos;
    const s = stepAt(t, pos);
    if (!s?.on || !audible(i)) return;
    if (Math.random() * 100 >= playValue(i, 'prob', s.locks)) return;
    const ratchet = playValue(i, 'ratchet', s.locks) + 1;
    const swing = playValue(i, 'swing', s.locks);
    const offset = pos % 2 === 1 ? ((swing - 50) / 50) * dur : 0;
    const sub = dur / ratchet;
    for (let r = 0; r < ratchet; r++) {
      flashes.push({ time: now + offset + r * sub, track: i, dur: Math.min(90, sub * 0.6) });
    }
  });
  tick++;
}

/** Вызывается каждый кадр. */
export function updateTransport(now: number) {
  if (ui.playing) {
    // Если вкладка была в фоне — не догоняем пропущенные шаги.
    if (now - nextTime > 1000) nextTime = now;
    while (now >= nextTime) {
      playStep(nextTime);
      nextTime += stepMs();
    }
  }
  for (let k = flashes.length - 1; k >= 0; k--) {
    const f = flashes[k];
    if (now >= f.time) {
      rt.flashUntil[f.track] = Math.max(rt.flashUntil[f.track], now + f.dur);
      flashes.splice(k, 1);
    }
  }
}

/** Страница, на которой сейчас играет дорожка. */
export function playPage(trackIndex: number): number {
  const pos = rt.playPos[trackIndex];
  return pos < 0 ? -1 : Math.floor(pos / STEPS_PER_PAGE);
}
