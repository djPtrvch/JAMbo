// Строка дорожек: тап — выбор, свайп вниз — mute, свайп вверх — solo.
// Дорожка мигает при срабатывании своих шагов; при удержании TRACK — жёлтый маркер.

import { TRACK_COUNT } from '../params';
import { audible, doc, rt, selectTrack, toggleMute, toggleSolo, ui } from '../state';
import { h, setClass, setText } from './dom';

const SWIPE_PX = 24;

interface TrackView { root: HTMLElement; state: HTMLElement }
const views: TrackView[] = [];

export function buildTracks(): HTMLElement {
  const el = h('div', 'tracks');
  for (let i = 0; i < TRACK_COUNT; i++) {
    const root = h('div', 'track');
    root.append(h('div', 'track-name', doc.tracks[i].name), h('div', 'track-marker'));
    const state = h('div', 'track-state');
    root.append(state);

    let startY = 0;
    let id = -1;
    root.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      root.setPointerCapture(e.pointerId);
      id = e.pointerId;
      startY = e.clientY;
    });
    const finish = (e: PointerEvent, cancelled: boolean) => {
      if (e.pointerId !== id) return;
      id = -1;
      if (cancelled) return;
      const dy = e.clientY - startY;
      if (dy > SWIPE_PX) toggleMute(i);
      else if (dy < -SWIPE_PX) toggleSolo(i);
      else selectTrack(i);
    };
    root.addEventListener('pointerup', (e) => finish(e, false));
    root.addEventListener('pointercancel', (e) => finish(e, true));

    views.push({ root, state });
    el.append(root);
  }
  return el;
}

export function renderTracks(now: number) {
  views.forEach((v, i) => {
    const t = doc.tracks[i];
    setClass(v.root, 'selected', i === ui.selectedTrack);
    setClass(v.root, 'muted', t.mute);
    setClass(v.root, 'soloed', t.solo);
    setClass(v.root, 'silent', !audible(i));
    setClass(v.root, 'flash', now < rt.flashUntil[i]);
    setClass(v.root, 'track-all', ui.held.track);
    setText(v.state, t.solo ? 'S' : t.mute ? 'M' : '');
  });
}
