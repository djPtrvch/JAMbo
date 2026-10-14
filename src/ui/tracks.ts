// Строка дорожек: слева канал микшера MIX, справа мастер MST (тап — ручки показывают их).
// Дорожки: тап — выбор; свайп вниз — mute (красный контур), свайп вверх — solo (жёлтая дорожка);
// включённый mute или solo выключается любым свайпом. Удержание дорожки ничего не делает.
// Переименование — в MIX: удержание подписи под ручкой громкости дорожки открывает поле ввода имени.
// Дорожка мигает при срабатывании своих шагов; жёлтая точка — параметры этой дорожки
// меняли с зажатым TRACK (на всю дорожку).

import { MAX_TRACKS } from '../params';
import { audible, doc, renameTrack, rt, selectChannel, selectTrack, swipeTrack, ui, type Channel } from '../state';
import { registerAction } from '../midi';
import { masterStemRecording, stemRecording } from '../stems';
import { masterEndIn, stemEndIn } from '../transport';
import { h, setClass, setText } from './dom';
import { openInput } from './popup';
import { markSwipe } from './debug';

const SWIPE_PX = 24;
const RAW = 'onpointerrawupdate' in window;

interface TrackView { root: HTMLElement; name: HTMLElement; state: HTMLElement; dot: HTMLElement; rec: HTMLElement }
const views: TrackView[] = [];
/** Окно переименования дорожки i рядом с элементом anchor (подписью ручки громкости в MIX). */
export function openRename(i: number, anchor: Element) {
  openInput(anchor, doc.tracks[i].name, (v) => renameTrack(i, v));
}

const channels: [HTMLElement, Channel][] = [];

/** Точка записи мастера на MST (мигает, пока пишется; за 5 с до конца — чаще). */
let mstRec: HTMLElement;

function channelCell(label: string, c: Channel): HTMLElement {
  const el = h('div', 'track channel', label);
  if (c === 'master') { mstRec = h('div', 'track-rec hidden'); el.append(mstRec); }
  el.addEventListener('pointerdown', (e) => { e.preventDefault(); selectChannel(c); });
  channels.push([el, c]);
  registerAction(label, { label, press: () => selectChannel(c), state: () => ui.channel === c }, el);
  return el;
}

export function buildTracks(): HTMLElement {
  const el = h('div', 'tracks');
  el.append(channelCell('MIX', 'mix'));
  for (let i = 0; i < MAX_TRACKS; i++) {
    const root = h('div', 'track');
    const name = h('div', 'track-name');
    const state = h('div', 'track-state');
    const dot = h('div', 'track-dot');
    // Идёт запись стема — мигающая красная точка в левом верхнем углу.
    const rec = h('div', 'track-rec hidden');
    root.append(name, state, dot, rec);

    let startY = 0;
    let downT = 0;
    let id = -1;
    /** Свайп уже сработал (mute/solo включаются, как только палец прошёл порог, не дожидаясь отпускания). */
    let swiped = false;
    root.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      root.setPointerCapture(e.pointerId);
      id = e.pointerId;
      startY = e.clientY;
      downT = e.timeStamp;
      swiped = false;
    });
    // pointerrawupdate (где есть) приходит сразу, pointermove браузер придерживает до кадра.
    root.addEventListener(RAW ? 'pointerrawupdate' as 'pointermove' : 'pointermove', (e) => {
      if (e.pointerId !== id || swiped) return;
      const dy = e.clientY - startY;
      if (Math.abs(dy) > SWIPE_PX) {
        swiped = true;
        markSwipe(downT, e.timeStamp);
        swipeTrack(i, dy > 0 ? 'down' : 'up');
      }
    });
    const finish = (e: PointerEvent, cancelled: boolean) => {
      if (e.pointerId !== id) return;
      id = -1;
      if (cancelled || swiped) return;
      selectTrack(i);
    };
    root.addEventListener('pointerup', (e) => finish(e, false));
    root.addEventListener('pointercancel', (e) => finish(e, true));

    // С MIDI — выбор дорожки (T1…T8 — по номеру, не по имени).
    registerAction(`T${i + 1}`, { label: `TRACK ${i + 1}`, press: () => selectTrack(i), state: () => ui.channel === 'track' && ui.selectedTrack === i }, root);
    views.push({ root, name, state, dot, rec });
    el.append(root);
  }
  el.append(channelCell('MST', 'master'));
  return el;
}

export function renderTracks(now: number) {
  views.forEach((v, i) => {
    const t = doc.tracks[i];
    setClass(v.root, 'hidden', !t);
    if (!t) return;
    setText(v.name, t.name);
    setClass(v.root, 'selected', ui.channel === 'track' && i === ui.selectedTrack);
    setClass(v.root, 'muted', t.mute);
    setClass(v.root, 'soloed', t.solo);
    setClass(v.root, 'silent', !audible(i));
    setClass(v.root, 'flash', now < rt.flashUntil[i]);
    setClass(v.dot, 'hidden', !t.trackEdit);
    setClass(v.rec, 'hidden', !stemRecording(i));
    const left = stemEndIn(i, now);
    setClass(v.rec, 'ending', left !== null && left <= 5000);
    setText(v.state, t.solo ? 'S' : t.mute ? 'M' : '');
  });
  for (const [el, c] of channels) setClass(el, 'selected', ui.channel === c);
  setClass(mstRec, 'hidden', !masterStemRecording());
  const left = masterEndIn(now);
  setClass(mstRec, 'ending', left !== null && left <= 5000);
}
