// Миниатюры страниц паттерна — строки одна под другой во всю ширину.
// Тап — эта страница играет (и открывается в секвенсоре); протянуть по нескольким — играют они все,
// вокруг играющих страниц общая обводка.
// «+» — добавить страницу (до 8); удержание — окно duplicate / copy / paste / clear / delete.

import { MAX_PAGES, STEPS_PER_PAGE } from '../params';
import {
  addPage, clearPage, copyPage, deletePage, duplicatePage, hasLocks, pastePage, rt, curSeq, seqIndex, setPlayPages, ui,
} from '../state';
import { h, setClass } from './dom';
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
let drag: { id: number; from: number; to: number; timer: number; menu: boolean } | null = null;

function thumbAt(x: number, y: number): number {
  const el = document.elementFromPoint(x, y)?.closest('.thumb') as HTMLElement | null;
  return el && list.contains(el) && el.dataset.page ? Number(el.dataset.page) : -1;
}

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
      drag = {
        id: e.pointerId, from: i, to: i, menu: false,
        timer: window.setTimeout(() => { if (drag && drag.to === drag.from) { drag.menu = true; openMenu(i); } }, HOLD_MS),
      };
    });
    thumbs.push({ root, cells });
    list.append(root);
  }
  plus = h('div', 'thumb plus', '+');
  plus.addEventListener('pointerdown', (e) => { e.preventDefault(); addPage(); });
  list.append(plus);

  document.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id || drag.menu) return;
    const i = thumbAt(e.clientX, e.clientY);
    if (i >= 0 && i < curSeq().pages.length && i !== drag.to) {
      drag.to = i;
      clearTimeout(drag.timer);
    }
  });
  const up = (e: PointerEvent) => {
    if (!drag || e.pointerId !== drag.id) return;
    clearTimeout(drag.timer);
    if (!drag.menu && e.type === 'pointerup') {
      setPlayPages(drag.from, drag.to);
      ui.viewPage = drag.from;
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
  const from = drag && !drag.menu ? Math.min(drag.from, drag.to) : t.playFrom;
  const to = drag && !drag.menu ? Math.max(drag.from, drag.to) : t.playTo;
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
