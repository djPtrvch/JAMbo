// Миниатюры страниц паттерна — строки одна под другой во всю ширину.
// Тап — эта страница играет (и открывается в секвенсоре); протянуть по нескольким — играют они все,
// вокруг играющих страниц общая обводка (края тянутся по высоте пальца, за середину переносится). Удержание — страница
// открывается в секвенсоре для редактирования (играющие не меняются), удержание и протягивание — перенос
// страницы на другое место (остальные сдвигаются). Двойной тап — окно duplicate / copy / paste / clear / delete.
// «+» — добавить страницу (до 8).

import { MAX_PAGES, STEPS_PER_PAGE } from '../params';
import {
  addPage, clearPage, movePage, nudgePage, pageRange, copyPage, deletePage, duplicatePage, hasLocks, hasManualLocks, tailMask, pastePage, rt, curSeq, seqIndex, setPlayPages, ui, patternHasAuto,
  pageLen,
} from '../state';
import { autoBadge, DOUBLE_TAP_MS, h, setClass } from './dom';
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
  id: number; y0: number; from: number; mode: 'top' | 'bottom' | 'move' | 'new' | 'reorder'; held: boolean; moved: boolean;
  f: number; t: number; n: number; range: [number, number] | null; timer: number;
  /** Перенос страницы: место, куда она встанет, и шаг между миниатюрами. */
  to?: number; pitch?: number;
}

// ---------- Перенос страницы: удержание миниатюры и протягивание ----------

/** Поднятая миниатюра — за пальцем, страницы между from и to — на соседнее место (анимация CSS). */
function layoutReorder(d: Drag, y: number) {
  const pitch = d.pitch!;
  d.to = Math.max(0, Math.min(d.n - 1, d.from + Math.round((y - d.y0) / pitch)));
  for (let k = 0; k < d.n; k++) {
    const r = thumbs[k].root;
    if (k === d.from) { r.style.transform = `translateY(${y - d.y0}px) scale(1.04)`; continue; }
    const p = d.from < d.to ? (k > d.from && k <= d.to ? k - 1 : k) : (k >= d.to && k < d.from ? k + 1 : k);
    r.style.transform = p === k ? '' : `translateY(${(p - k) * pitch}px)`;
  }
}

function endReorder(d: Drag, y: number) {
  for (let k = 0; k < d.n; k++) {
    thumbs[k].root.classList.remove('thumb-lifted', 'thumb-shift');
    thumbs[k].root.style.transform = '';
  }
  const to = d.to ?? d.from;
  movePage(d.from, to);
  // Сразу перерисовать: на местах уже новый порядок; перенесённая плавно встаёт на место.
  renderPages();
  const r = thumbs[to].root;
  r.classList.add('thumb-lifted');
  r.style.transform = `translateY(${y - d.y0 - (to - d.from) * d.pitch!}px) scale(1.04)`;
  void r.offsetWidth;
  r.classList.add('thumb-settle');
  r.style.transform = '';
  window.setTimeout(() => r.classList.remove('thumb-lifted', 'thumb-settle'), 200);
}
/** Сдвиг пальца, после которого касание уже не тап. */
const MOVE_PX = 8;
/** Зона края обводки (доля высоты страницы с каждой стороны границы). */
const EDGE_ZONE = 0.4;
/**
 * Удержание у самой границы обводки (ближе этой доли высоты страницы) — край остаётся за пальцем
 * (не перенос страницы): палец часто замирает, прежде чем тянуть край.
 */
const EDGE_HOLD = 0.25;
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

let pageWave: HTMLElement;

export function buildPages(): HTMLElement {
  list = h('div', 'pages');
  outline = h('div', 'play-outline');
  // Значок волны: в паттерне есть автоматизация.
  pageWave = autoBadge();
  list.append(outline, pageWave);
  for (let i = 0; i < MAX_PAGES; i++) {
    const root = h('div', 'thumb');
    root.dataset.page = String(i);
    root.style.gridRow = String(i + 1);
    const cells: HTMLElement[] = [];
    for (let k = 0; k < STEPS_PER_PAGE; k++) {
      const c = h('div', 'thumb-cell');
      cells.push(c);
      root.append(c);
    }
    root.addEventListener('pointerdown', (e) => startDrag(e, i, root));
    thumbs.push({ root, cells });
    list.append(root);
  }
  plus = h('div', 'thumb plus', '+');
  // «+» — новая страница по тапу (отпустили, не сдвинув палец). Касание у нижней границы обводки
  // (обводка на последней странице) — это её край: протягивание тянет край, страница не добавляется.
  let plusDown: { id: number; y0: number; moved: boolean } | null = null;
  plus.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const t = curSeq();
    const last = t.pages.length - 1;
    const { top, pitch } = geom();
    if (t.playTo === last && (e.clientY - top) / pitch - (last + 1) <= EDGE_ZONE) { startDrag(e, last, thumbs[last].root); return; }
    plusDown = { id: e.pointerId, y0: e.clientY, moved: false };
  });
  plus.addEventListener('pointermove', (e) => {
    if (plusDown && e.pointerId === plusDown.id && Math.abs(e.clientY - plusDown.y0) > MOVE_PX) plusDown.moved = true;
  });
  plus.addEventListener('pointerup', (e) => {
    if (plusDown && e.pointerId === plusDown.id && !plusDown.moved) addPage();
    plusDown = null;
  });
  plus.addEventListener('pointercancel', () => { plusDown = null; });
  list.append(plus);

  /** Касание страницы i (или края обводки у «+»): край обводки, середина, страница снаружи; удержание. */
  function startDrag(e: PointerEvent, i: number, root: HTMLElement) {
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
      const nearEdge = (mode === 'top' && Math.abs(pos - t.playFrom) <= EDGE_HOLD)
        || (mode === 'bottom' && Math.abs(pos - (t.playTo + 1)) <= EDGE_HOLD);
      drag = {
        id: e.pointerId, y0: e.clientY, from: i, mode, held: false, moved: false, range: null,
        f: t.playFrom, t: t.playTo, n: t.pages.length,
        // Удержание без протягивания — страница открывается для редактирования (играющие не меняются);
        // если потом потянуть — страница переносится на другое место (остальные сдвигаются).
        timer: window.setTimeout(() => {
          if (!drag || drag.moved) return;
          drag.held = true;
          // У самой границы обводки удержание — открыть страницу, а протягивание потом — край.
          if (nearEdge) { ui.viewPage = i; return; }
          drag.mode = 'reorder';
          ui.viewPage = i;
          if (drag.n < 2) return;
          drag.pitch = geom().pitch;
          root.classList.add('thumb-lifted');
          for (let k = 0; k < drag.n; k++) if (k !== i) thumbs[k].root.classList.add('thumb-shift');
        }, HOLD_MS),
      };
  }

  document.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    if (drag.mode === 'reorder') {
      if (drag.n < 2) return;
      drag.moved = true;
      layoutReorder(drag, e.clientY);
      return;
    }
    // По высоте пальца (не по ячейке под ним): палец может уйти вбок или в зазор между страницами.
    if (!drag.moved && Math.abs(e.clientY - drag.y0) < MOVE_PX) return;
    if (!drag.moved) { drag.moved = true; clearTimeout(drag.timer); }
    drag.range = dragRange(drag, e.clientY);
  });
  const up = (e: PointerEvent) => {
    if (!drag || e.pointerId !== drag.id) return;
    clearTimeout(drag.timer);
    if (drag.mode === 'reorder') {
      if (drag.n >= 2) endReorder(drag, drag.moved ? e.clientY : drag.y0);
    } else if (e.type === 'pointerup') {
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
  // Вверху — стрелки: ◀ ▶ сдвигают шаги страницы на один, ▲ ▼ — ноты на октаву. Меню не закрывается.
  const arrows = h('div', 'popup-arrows');
  for (const [label, dir] of [['◀', 'left'], ['▶', 'right'], ['▲', 'up'], ['▼', 'down']] as const) {
    arrows.append(popupButton(label, () => { if (ui.pageMenu !== null) nudgePage(ui.pageMenu, dir); }));
  }
  menu.box.append(arrows);
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
  // Внутри белой обводки — всё действует на весь играющий диапазон.
  const [a, b] = pageRange(i);
  const n = b - a + 1;
  menuButtons.duplicate.disabled = t.pages.length + n > MAX_PAGES;
  menuButtons.paste.disabled = !ui.clipboard;
  menuButtons.delete.disabled = t.pages.length - n < 1;
  menu.openAt(thumbs[i].root, 180);
}

export function renderPages() {
  const t = curSeq();
  const pos = ui.playing ? rt.playPos[seqIndex()] : -1;
  // Обводка следует за пальцем, только когда протягивают по нескольким страницам; на касании
  // одной она не прыгает (тап переключит её при отпускании, удержание её не меняет).
  const [from, to] = drag?.moved && drag.range ? drag.range : [t.playFrom, t.playTo];
  const tails = tailMask(t.pages);
  thumbs.forEach((th, i) => {
    const exists = i < t.pages.length;
    setClass(th.root, 'hidden', !exists);
    if (!exists) return;
    setClass(th.root, 'current', i === ui.viewPage);
    th.cells.forEach((c, k) => {
      const s = t.pages[i][k];
      const index = i * STEPS_PER_PAGE + k;
      setClass(c, 'on', s.on);
      setClass(c, 'tail', !s.on && tails[index]);
      setClass(c, 'plock', s.on && hasManualLocks(s));
      setClass(c, 'own-sound', s.on && !!s.sound);
      setClass(c, 'lock-only', !s.on && hasLocks(s));
      setClass(c, 'outside', k >= pageLen(t, i));
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
  setClass(pageWave, 'hidden', !patternHasAuto(t));
}
