// Миниатюры страниц паттерна: тап — показать страницу, «+» — добавить (до 4),
// удержание — окно duplicate / copy / paste / delete.

import { MAX_PAGES, STEPS_PER_PAGE } from '../params';
import { addPage, copyPage, deletePage, duplicatePage, pastePage, rt, selTrack, ui } from '../state';
import { playPage } from '../transport';
import { h, setClass } from './dom';

const HOLD_MS = 450;

interface Thumb { root: HTMLElement; dots: HTMLElement[] }
const thumbs: Thumb[] = [];
let plus: HTMLElement;
let menu: HTMLElement;
const menuButtons: Record<string, HTMLButtonElement> = {};

export function buildPages(): HTMLElement {
  const el = h('div', 'pages');
  for (let i = 0; i < MAX_PAGES; i++) {
    const root = h('div', 'thumb');
    const dots: HTMLElement[] = [];
    for (let k = 0; k < STEPS_PER_PAGE; k++) {
      const d = h('div', 'thumb-dot');
      dots.push(d);
      root.append(d);
    }
    let timer = 0;
    let opened = false;
    root.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      opened = false;
      timer = window.setTimeout(() => { opened = true; openMenu(i); }, HOLD_MS);
    });
    root.addEventListener('pointerup', () => {
      clearTimeout(timer);
      if (!opened) ui.viewPage = i;
    });
    root.addEventListener('pointercancel', () => clearTimeout(timer));
    thumbs.push({ root, dots });
    el.append(root);
  }
  plus = h('div', 'thumb plus', '+');
  plus.addEventListener('pointerdown', (e) => { e.preventDefault(); addPage(); });
  el.append(plus);

  menu = h('div', 'page-menu hidden');
  const actions: [string, (i: number) => void][] = [
    ['duplicate', duplicatePage], ['copy', copyPage], ['paste', pastePage], ['delete', deletePage],
  ];
  const box = h('div', 'page-menu-box');
  for (const [name, fn] of actions) {
    const b = h('button', 'page-menu-btn', name.toUpperCase());
    b.addEventListener('pointerup', () => {
      if (ui.pageMenu !== null && !b.disabled) fn(ui.pageMenu);
      ui.pageMenu = null;
    });
    menuButtons[name] = b;
    box.append(b);
  }
  menu.append(box);
  // Тап мимо окна закрывает его.
  menu.addEventListener('pointerdown', (e) => { if (e.target === menu) ui.pageMenu = null; });
  document.body.append(menu);
  return el;
}

function openMenu(i: number) {
  ui.pageMenu = i;
  const r = thumbs[i].root.getBoundingClientRect();
  const box = menu.firstElementChild as HTMLElement;
  box.style.top = `${r.bottom + 8}px`;
  box.style.left = `${Math.max(8, Math.min(window.innerWidth - 188, r.left + r.width / 2 - 90))}px`;
}

export function renderPages() {
  const t = selTrack();
  const playing = ui.playing ? playPage(ui.selectedTrack) : -1;
  thumbs.forEach((th, i) => {
    const exists = i < t.pages.length;
    setClass(th.root, 'hidden', !exists);
    if (!exists) return;
    setClass(th.root, 'current', i === ui.viewPage);
    setClass(th.root, 'playing', i === playing);
    setClass(th.root, 'outside', i * STEPS_PER_PAGE >= t.length);
    th.dots.forEach((d, k) => {
      const s = t.pages[i][k];
      const index = i * STEPS_PER_PAGE + k;
      setClass(d, 'on', s.on);
      setClass(d, 'plock', s.on && Object.keys(s.locks).length > 0);
      setClass(d, 'pos', ui.playing && rt.playPos[ui.selectedTrack] === index);
    });
  });
  setClass(plus, 'hidden', t.pages.length >= MAX_PAGES);

  setClass(menu, 'hidden', ui.pageMenu === null);
  menuButtons.duplicate.disabled = t.pages.length >= MAX_PAGES;
  menuButtons.paste.disabled = !ui.clipboard;
  menuButtons.delete.disabled = t.pages.length <= 1;
}
