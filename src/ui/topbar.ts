// Верхняя панель: бутерброд-меню (заглушка), BPM, гамма и корневая нота.
// Значения меняются вертикальным движением пальца, как ручки.

import { NOTE_NAMES, SCALES } from '../params';
import { beginGesture, doc, endGesture, setBpm, setRoot, setScale } from '../state';
import { h, setText } from './dom';

interface Field { value: HTMLElement; read: () => string }
const fields: Field[] = [];

/** Поле с вертикальным управлением: pxPerUnit пикселей на единицу значения. */
function dragField(label: string, get: () => number, set: (v: number) => void, show: () => string, pxPerUnit: number): HTMLElement {
  const el = h('div', 'field');
  const value = h('div', 'field-value');
  el.append(h('div', 'field-label', label), value);
  let id = -1;
  let startY = 0;
  let startV = 0;
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    id = e.pointerId;
    startY = e.clientY;
    startV = get();
    el.classList.add('active');
    beginGesture();
  });
  el.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id) return;
    set(startV + Math.round((startY - e.clientY) / pxPerUnit));
  });
  const up = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = -1;
    el.classList.remove('active');
    endGesture();
  };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  fields.push({ value, read: show });
  return el;
}

export function buildTopbar(): HTMLElement {
  const el = h('div', 'topbar');
  const burger = h('div', 'burger');
  burger.append(h('span'), h('span'), h('span'));
  el.append(
    burger,
    dragField('BPM', () => doc.bpm, setBpm, () => String(doc.bpm), 4),
    dragField('SCALE', () => doc.scale, setScale, () => SCALES[doc.scale], 24),
    dragField('ROOT', () => doc.root, setRoot, () => NOTE_NAMES[doc.root], 24),
  );
  return el;
}

export function renderTopbar() {
  for (const f of fields) setText(f.value, f.read());
}
