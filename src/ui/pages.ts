// Миниатюры страниц паттерна — строки одна под другой во всю ширину.
// Тап — эта страница играет (и открывается в секвенсоре); протянуть по нескольким — играют они все,
// вокруг играющих страниц общая обводка (края тянутся по высоте пальца, за середину переносится). Удержание — страница
// открывается в секвенсоре для редактирования (играющие не меняются), удержание и протягивание — новое
// выделение. Двойной тап — окно duplicate / copy / paste / clear / delete.
// «+» — добавить страницу (до 8).

import { MAX_PAGES, STEPS_PER_PAGE } from '../params';
import {
  addPage, clearPage, copyPage, deletePage, duplicatePage, hasLocks, pastePage, rt, curSeq, seqIndex, setPlayPages, ui,
} from '../state';
import { DOUBLE_TAP_MS, h, setClass } from './dom';
import { makePopup, popupButton, type Popup } from './popup';

const HOLD_MS = 450;

interface Thumb { root: HTMLElement; cells: HTMLElement[] }
const thumbs: Thumb[] = [];
let list: HTMLElement;
let plus: HTMLElement;
/** Общая обводка вокруг играющих страниц. */
let outline: HTMLElement;
let menu: Popup;
const menuButtons: Record<string, HTMLButtonElement> = {};

/** Текущее протягивание по миниатюрам. */
let drag: Drag | null = null;
/**
 * Протягивание: mode — что делает палец (top / bottom — край обводки, move — вся обводка, new — новое
 * выделение от страницы from); y0 — где коснулся; range — играющие страницы по ходу протягивания.
 */
interface Drag {
  id: number; y0: number; from: number; mode: 'top' | 'bottom' | 'move' | 'new'; held: boolean; moved: boolean;
  f: number; t: number; n: number; range: [number, number] | null; timer: number;
}
/** Сдвиг пальца, после которого касание уже не тап. */
const MOVE_PX = 8;
/** Зона края обводки (доля высоты страницы с каждой стороны границы). */
const EDGE_ZONE = 0.4;
/** Страница добавляется (или убирается), когда край зашёл в неё на эту долю высоты. */
const SNAP = 0.3;

/** Геометрия миниатюр: верх первой страницы и шаг между страницами (с зазором), px. */
function geom(): { top: number; pitch: number } {
  const a = thumbs[0].root.getBoundingClientRect();
  const b = thumbs[1].root.getBoundingClientRect();
  const d = b.top - a.top;
  return { top: a.top, pitch: b.height > 0 && d > 0 ? d : a.height + 4 };
}

/** На сколько страниц сдвинули край: d — сдвиг в долях страницы; страница считается с доли SNAP. */
const snapSteps = (d: number) => Math.sign(d) * Math.floor(Math.abs(d) + 1 - SNAP);

/**
 * Играющие страницы при пальце на высоте y. Край обводки (верхний или нижний) идёт за пальцем
 * (растягивается и сужается, но не меньше одной страницы); за середину обводка переносится целиком;
 * новое выделение (касание снаружи или удержание) — от страницы касания до страницы под пальцем.
 */
function dragRange(d: Drag, y: number): [number, number] {
  const { top, pitch } = geom();
  const steps = snapSteps((y - d.y0) / pitch);
  if (d.mode === 'top') return [Math.max(0, Math.min(d.t, d.f + steps)), d.t];
  if (d.mode === 'bottom') return [d.f, Math.min(d.n - 1, Math.max(d.f, d.t + steps))];
  if (d.mode === 'move') {
    const k = Math.max(-d.f, Math.min(d.n - 1 - d.t, steps));
    return [d.f + k, d.t + k];
  }
  const at = Math.max(0, Math.min(d.n - 1, Math.floor((y - top) / pitch)));
  return [Math.min(d.from, at), Math.max(d.from, at)];
}
/** Тап по миниатюре, который ждёт второго (двойной тап — меню). */
let tapPage = -1;
let tapTimer = 0;

export function buildPages(): HTMLElement {
  list = h('div', 'pages');
  outline = h('div', 'play-outline');
  list.append(outline);
  for (let i = 0; i < MAX_PAGES; i++) {
    const root = h('div', 'thumb');
    root.dataset.page = String(i);
    root.style.gridRow = String(i + 1);
    const cells: HTMLElement[] = [];
    for (let k = 0; k < STEPS_PER_PAGE; k++) {
      const c = h('div', 'thumb-cell');
      if (k % 4 === 0) c.classList.add('beat');
      cells.push(c);
      root.append(c);
    }
    root.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      if (drag) return;
      root.releasePointerCapture?.(e.pointerId);
      const t = curSeq();
      // Что взяли: край обводки (в зоне вокруг её границы — и снаружи, и внутри), середину или страницу снаружи.
      const { top, pitch } = geom();
      const pos = (e.clientY - top) / pitch;
      const mode = Math.abs(pos - t.playFrom) <= EDGE_ZONE ? 'top'
        : Math.abs(pos - (t.playTo + 1)) <= EDGE_ZONE ? 'bottom'
          : pos > t.playFrom && pos < t.playTo + 1 ? 'move' : 'new';
      drag = {
        id: e.pointerId, y0: e.clientY, from: i, mode, held: false, moved: false, range: null,
        f: t.playFrom, t: t.playTo, n: t.pages.length,
        // Удержание без протягивания — страница открывается для редактирования (играющие не меняются);
        // если потом потянуть — новое выделение от этой страницы.
        timer: window.setTimeout(() => { if (drag && !drag.moved) { drag.held = true; drag.mode = 'new'; ui.viewPage = i; } }, HOLD_MS),
      };
    });
    thumbs.push({ root, cells });
    list.append(root);
  }
  plus = h('div', 'thumb plus', '+');
  plus.addEventListener('pointerdown', (e) => { e.preventDefault(); addPage(); });
  list.append(plus);

  document.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    // По высоте пальца (не по ячейке под ним): палец может уйти вбок или в зазор между страницами.
    if (!drag.moved && Math.abs(e.clientY - drag.y0) < MOVE_PX) return;
    if (!drag.moved) { drag.moved = true; clearTimeout(drag.timer); }
    drag.range = dragRange(drag, e.clientY);
  });
  const up = (e: PointerEvent) => {
    if (!drag || e.pointerId !== drag.id) return;
    clearTimeout(drag.timer);
    if (e.type === 'pointerup') {
      if (drag.moved) {
        // Протянули — играют выбранные страницы (если выбор изменился), сразу; тапом это не считается.
        clearTimeout(tapTimer);
        tapPage = -1;
        const r = drag.range;
        if (r && (r[0] !== drag.f || r[1] !== drag.t)) {
          setPlayPages(r[0], r[1]);
          ui.viewPage = drag.mode === 'new' ? drag.from : r[0];
        }
      } else if (drag.held) {
        // Удержание без протягивания — только открыть страницу (уже открыта по таймеру).
      } else if (tapPage === drag.from) {
        // Двойной тап — меню страницы; одиночный тап не срабатывает (обводка не двигается).
        clearTimeout(tapTimer);
        tapPage = -1;
        openMenu(drag.from);
      } else {
        // Одиночный тап срабатывает, если за DOUBLE_TAP_MS не было второго.
        clearTimeout(tapTimer);
        const i = drag.from;
        tapPage = i;
        tapTimer = window.setTimeout(() => {
          tapPage = -1;
          if (i >= curSeq().pages.length) return;
          setPlayPages(i, i);
          ui.viewPage = i;
        }, DOUBLE_TAP_MS);
      }
    }
    drag = null;
  };
  document.addEventListener('pointerup', up);
  document.addEventListener('pointercancel', up);

  menu = makePopup();
  const actions: [string, (i: number) => void][] = [
    ['duplicate', duplicatePage], ['copy', copyPage], ['paste', pastePage], ['clear', clearPage], ['delete', deletePage],
  ];
  for (const [name, fn] of actions) {
    const b = popupButton(name.toUpperCase(), () => {
      const i = ui.pageMenu;
      menu.close();
      if (i !== null) fn(i);
    });
    menuButtons[name] = b;
    menu.box.append(b);
  }
  return list;
}

function openMenu(i: number) {
  ui.pageMenu = i;
  const t = curSeq();
  menuButtons.duplicate.disabled = t.pages.length >= MAX_PAGES;
  menuButtons.paste.disabled = !ui.clipboard;
  menuButtons.delete.disabled = t.pages.length <= 1;
  menu.openAt(thumbs[i].root, 180);
}

export function renderPages() {
  const t = curSeq();
  const pos = ui.playing ? rt.playPos[seqIndex()] : -1;
  // Обводка следует за пальцем, только когда протягивают по нескольким страницам; на касании
  // одной она не прыгает (тап переключит её при отпускании, удержание её не меняет).
  const [from, to] = drag?.moved && drag.range ? drag.range : [t.playFrom, t.playTo];
  thumbs.forEach((th, i) => {
    const exists = i < t.pages.length;
    setClass(th.root, 'hidden', !exists);
    if (!exists) return;
    setClass(th.root, 'current', i === ui.viewPage);
    th.cells.forEach((c, k) => {
      const s = t.pages[i][k];
      const index = i * STEPS_PER_PAGE + k;
      setClass(c, 'on', s.on);
      setClass(c, 'plock', s.on && hasLocks(s));
      setClass(c, 'lock-only', !s.on && hasLocks(s));
      setClass(c, 'outside', index >= t.length);
      setClass(c, 'pos', index === pos);
    });
  });
  setClass(plus, 'hidden', t.pages.length >= MAX_PAGES);

  // Обводка от первой до последней играющей страницы.
  const first = thumbs[from].root;
  const last = thumbs[Math.min(to, t.pages.length - 1)].root;
  outline.style.top = `${first.offsetTop - 3}px`;
  outline.style.height = `${last.offsetTop + last.offsetHeight - first.offsetTop + 6}px`;
  if (!menu.isOpen()) ui.pageMenu = null;
}
