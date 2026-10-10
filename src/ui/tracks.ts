// Строка дорожек: слева канал микшера MIX, справа мастер MST (тап — ручки показывают их).
// Дорожки: тап — выбор, свайп вниз — mute (красный контур), свайп вверх — solo,
// удержание — меню rename / copy / paste / delete.
// Дорожка мигает при срабатывании своих шагов; жёлтая точка — параметры этой дорожки
// меняли с зажатым TRACK (на всю дорожку).

import { TRACK_COUNT } from '../params';
import {
  audible, copyTrack, deleteTrack, doc, pasteTrack, renameTrack, rt, selectChannel, selectTrack, toggleMute,
  toggleSolo, ui, type Channel,
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
let renamePopup: ReturnType<typeof makePopup>;
let renameInput: HTMLInputElement;
let renameIndex = -1;

/**
 * Своё окно переименования: системный window.prompt в Safari прерывает звук
 * (аудиоконтекст становится «interrupted»), поэтому поле ввода — прямо на странице.
 */
function buildRename() {
  renamePopup = makePopup('rename');
  renameInput = h('input', 'rename-input');
  renameInput.type = 'text';
  renameInput.maxLength = 12;
  const done = () => {
    if (renameIndex >= 0) renameTrack(renameIndex, renameInput.value);
    renameIndex = -1;
    renameInput.blur();
    renamePopup.close();
  };
  renameInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') done(); });
  renamePopup.box.append(renameInput, popupButton('OK', done));
}

function openRename(i: number) {
  renameIndex = i;
  renameInput.value = doc.tracks[i].name;
  renamePopup.openAt(views[i].root, 220);
  renameInput.focus();
  renameInput.select();
}

function buildMenu() {
  buildRename();
  menu = makePopup();
  const act = (fn: (i: number) => void) => () => {
    const i = ui.trackMenu;
    menu.close();
    ui.trackMenu = null;
    if (i !== null) fn(i);
  };
  pasteBtn = popupButton('PASTE', act(pasteTrack));
  menu.box.append(
    popupButton('RENAME', act(openRename)),
    popupButton('COPY', act(copyTrack)),
    pasteBtn,
    popupButton('DELETE', act(deleteTrack)),
  );
}

const channels: [HTMLElement, Channel][] = [];

function channelCell(label: string, c: Channel): HTMLElement {
  const el = h('div', 'track channel', label);
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); selectChannel(c); });
  channels.push([el, c]);
  return el;
}

export function buildTracks(): HTMLElement {
  buildMenu();
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
  if (!menu.isOpen()) ui.trackMenu = null;
}
