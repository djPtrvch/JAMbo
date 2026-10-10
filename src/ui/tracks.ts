// Строка дорожек: тап — выбор, свайп вниз — mute (красный контур), свайп вверх — solo,
// удержание — меню rename / copy / paste / delete.
// Дорожка мигает при срабатывании своих шагов; жёлтая точка — параметры этой дорожки
// меняли с зажатым TRACK (на всю дорожку).

import { TRACK_COUNT } from '../params';
import {
  audible, copyTrack, deleteTrack, doc, pasteTrack, renameTrack, rt, selectTrack, toggleMute, toggleSolo, ui,
} from '../state';
import { h, setClass, setText } from './dom';
import { makePopup, popupButton } from './popup';

const SWIPE_PX = 24;
const HOLD_MS = 450;
const MOVE_CANCEL_PX = 10;

interface TrackView { root: HTMLElement; name: HTMLElement; state: HTMLElement; dot: HTMLElement }
const views: TrackView[] = [];
let menu: ReturnType<typeof makePopup>;
let pasteBtn: HTMLButtonElement;

function buildMenu() {
  menu = makePopup();
  const act = (fn: (i: number) => void) => () => {
    const i = ui.trackMenu;
    menu.close();
    ui.trackMenu = null;
    if (i !== null) fn(i);
  };
  pasteBtn = popupButton('PASTE', act(pasteTrack));
  menu.box.append(
    popupButton('RENAME', act((i) => {
      const name = window.prompt('Название дорожки', doc.tracks[i].name);
      if (name !== null) renameTrack(i, name);
    })),
    popupButton('COPY', act(copyTrack)),
    pasteBtn,
    popupButton('DELETE', act(deleteTrack)),
  );
}

export function buildTracks(): HTMLElement {
  buildMenu();
  const el = h('div', 'tracks');
  for (let i = 0; i < TRACK_COUNT; i++) {
    const root = h('div', 'track');
    const name = h('div', 'track-name');
    const state = h('div', 'track-state');
    const dot = h('div', 'track-dot');
    root.append(name, state, dot);

    let startY = 0;
    let id = -1;
    let timer = 0;
    let opened = false;
    root.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      root.setPointerCapture(e.pointerId);
      id = e.pointerId;
      startY = e.clientY;
      opened = false;
      timer = window.setTimeout(() => {
        opened = true;
        ui.trackMenu = i;
        pasteBtn.disabled = !ui.trackClipboard;
        menu.openAt(root, 180);
      }, HOLD_MS);
    });
    root.addEventListener('pointermove', (e) => {
      if (e.pointerId === id && Math.abs(e.clientY - startY) > MOVE_CANCEL_PX) clearTimeout(timer);
    });
    const finish = (e: PointerEvent, cancelled: boolean) => {
      if (e.pointerId !== id) return;
      id = -1;
      clearTimeout(timer);
      if (cancelled || opened) return;
      const dy = e.clientY - startY;
      if (dy > SWIPE_PX) toggleMute(i);
      else if (dy < -SWIPE_PX) toggleSolo(i);
      else selectTrack(i);
    };
    root.addEventListener('pointerup', (e) => finish(e, false));
    root.addEventListener('pointercancel', (e) => finish(e, true));

    views.push({ root, name, state, dot });
    el.append(root);
  }
  return el;
}

export function renderTracks(now: number) {
  views.forEach((v, i) => {
    const t = doc.tracks[i];
    setText(v.name, t.name);
    setClass(v.root, 'selected', i === ui.selectedTrack);
    setClass(v.root, 'muted', t.mute);
    setClass(v.root, 'soloed', t.solo);
    setClass(v.root, 'silent', !audible(i));
    setClass(v.root, 'flash', now < rt.flashUntil[i]);
    setClass(v.dot, 'hidden', !t.trackEdit);
    setText(v.state, t.solo ? 'S' : t.mute ? 'M' : '');
  });
  if (!menu.isOpen()) ui.trackMenu = null;
}
