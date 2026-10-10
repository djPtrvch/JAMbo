// Общие элементы управления: поле с вертикальным управлением и меню выбора.

import { beginGesture, endGesture } from '../state';
import { h, setText } from './dom';
import { makePopup, popupButton } from './popup';

interface Field { value: HTMLElement; read: () => string }
const fields: Field[] = [];
const TAP_PX = 6;

/**
 * Поле с вертикальным управлением: pxPerUnit пикселей на единицу значения.
 * onTap — действие на тап без движения (например, открыть меню).
 */
export function dragField(
  label: string, get: () => number, set: (v: number) => void, show: () => string, pxPerUnit: number,
  onTap?: (el: HTMLElement) => void,
): HTMLElement {
  const el = h('div', 'field');
  const value = h('div', 'field-value');
  el.append(h('div', 'field-label', label), value);
  let id = -1;
  let startY = 0;
  let startV = 0;
  let moved = false;
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    id = e.pointerId;
    startY = e.clientY;
    startV = get();
    moved = false;
    el.classList.add('active');
    beginGesture();
  });
  el.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id) return;
    if (Math.abs(startY - e.clientY) > TAP_PX) moved = true;
    if (moved) set(startV + Math.round((startY - e.clientY) / pxPerUnit));
  });
  const up = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = -1;
    el.classList.remove('active');
    endGesture();
    if (!moved && e.type === 'pointerup') onTap?.(el);
  };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  fields.push({ value, read: show });
  return el;
}

/** Меню выбора из списка (сетка кнопок). */
export function choiceMenu(names: string[], columns: number, current: () => number, choose: (i: number) => void) {
  const menu = makePopup(`grid cols-${columns}`);
  const buttons = names.map((n, i) => {
    const b = popupButton(n, () => { menu.close(); beginGesture(); choose(i); endGesture(); });
    menu.box.append(b);
    return b;
  });
  return (anchor: Element) => {
    buttons.forEach((b, i) => b.classList.toggle('current', i === current()));
    menu.openAt(anchor, columns * 104);
  };
}

/** Обновить значения всех полей (каждый кадр). */
export function renderFields() {
  for (const f of fields) setText(f.value, f.read());
}
