// Строка дорожек: слева канал микшера MIX, справа мастер MST (тап — ручки показывают их).
// Дорожки: тап — выбор; свайп вниз — mute (красный контур), свайп вверх — solo (жёлтая дорожка);
// включённый mute или solo выключается любым свайпом. Удержание дорожки ничего не делает.
// Переименование — в MIX: удержание подписи под ручкой громкости дорожки открывает поле ввода имени.
// Дорожка мигает при срабатывании своих шагов; жёлтая точка — параметры этой дорожки
// меняли с зажатым TRACK (на всю дорожку).

import { TRACK_COUNT } from '../params';
import { audible, doc, renameTrack, rt, selectChannel, selectTrack, swipeTrack, ui, type Channel } from '../state';
import { registerAction } from '../midi';
import { h, setClass, setText } from './dom';
import { openInput } from './popup';

const SWIPE_PX = 24;

interface TrackView { root: HTMLElement; name: HTMLElement; state: HTMLElement; dot: HTMLElement }
const views: TrackView[] = [];
/** Окно переименования дорожки i рядом с элементом anchor (подписью ручки громкости в MIX). */
export function openRename(i: number, anchor: Element) {
  openInput(anchor, doc.tracks[i].name, (v) => renameTrack(i, v));
}

const channels: [HTMLElement, Channel][] = [];

function channelCell(label: string, c: Channel): HTMLElement {
  const el = h('div', 'track channel', label);
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); selectChannel(c); });
  channels.push([el, c]);
  registerAction(label, { label, press: () => selectChannel(c), state: () => ui.channel === c }, el);
  return el;
}

export function buildTracks(): HTMLElement {
  const el = h('div', 'tracks');
  el.append(channelCell('MIX', 'mix'));
  for (let i = 0; i < TRACK_COUNT; i++) {
    const root = h('div', 'track');
    const name = h('div', 'track-name');
    const state = h('div', 'track-state');
    const dot = h('div', 'track-dot');
    root.append(name, state, dot);

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
      if (dy > SWIPE_PX) swipeTrack(i, 'down');
      else if (dy < -SWIPE_PX) swipeTrack(i, 'up');
      else selectTrack(i);
    };
    root.addEventListener('pointerup', (e) => finish(e, false));
    root.addEventListener('pointercancel', (e) => finish(e, true));

    // С MIDI — выбор дорожки (T1…T8 — по номеру, не по имени).
    registerAction(`T${i + 1}`, { label: `TRACK ${i + 1}`, press: () => selectTrack(i), state: () => ui.channel === 'track' && ui.selectedTrack === i }, root);
    views.push({ root, name, state, dot });
    el.append(root);
  }
  el.append(channelCell('MST', 'master'));
  return el;
}

export function renderTracks(now: number) {
  views.forEach((v, i) => {
    const t = doc.tracks[i];
    setText(v.name, t.name);
    setClass(v.root, 'selected', ui.channel === 'track' && i === ui.selectedTrack);
    setClass(v.root, 'muted', t.mute);
    setClass(v.root, 'soloed', t.solo);
    setClass(v.root, 'silent', !audible(i));
    setClass(v.root, 'flash', now < rt.flashUntil[i]);
    setClass(v.dot, 'hidden', !t.trackEdit);
    setText(v.state, t.solo ? 'S' : t.mute ? 'M' : '');
  });
  for (const [el, c] of channels) setClass(el, 'selected', ui.channel === c);
}
