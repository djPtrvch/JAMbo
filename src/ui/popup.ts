// Всплывающее окно с кнопками (меню страниц, дорожек, гаммы, ноты).

import { h } from './dom';

export interface Popup {
  root: HTMLElement;
  box: HTMLElement;
  /** Показать окно под (или над) элементом. */
  openAt(anchor: Element, width: number): void;
  /** Показать окно ровно поверх элемента (тот же размер и место). */
  openOver(target: Element): void;
  close(): void;
  isOpen(): boolean;
}

export function makePopup(cls = ''): Popup {
  const root = h('div', 'popup hidden');
  const box = h('div', `popup-box ${cls}`);
  root.append(box);
  document.body.append(root);
  const p: Popup = {
    root,
    box,
    openAt(anchor, width) {
      root.classList.remove('hidden');
      box.style.width = `${width}px`;
      const r = anchor.getBoundingClientRect();
      const bh = box.offsetHeight;
      const below = r.bottom + 6 + bh < window.innerHeight;
      box.style.top = `${below ? r.bottom + 6 : Math.max(8, r.top - 6 - bh)}px`;
      box.style.left = `${Math.max(8, Math.min(window.innerWidth - width - 8, r.left + r.width / 2 - width / 2))}px`;
    },
    openOver(target) {
      root.classList.remove('hidden');
      const r = target.getBoundingClientRect();
      Object.assign(box.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    },
    close() {
      root.classList.add('hidden');
      box.style.height = '';
    },
    isOpen: () => !root.classList.contains('hidden'),
  };
  // Тап мимо окна закрывает его.
  root.addEventListener('pointerdown', (e) => { if (e.target === root) p.close(); });
  return p;
}

let inputPopup: Popup | null = null;
let inputField: HTMLInputElement;
let inputDone: ((v: string) => void) | null = null;

/**
 * Поле ввода рядом с элементом anchor (имя дорожки, частота EQ). Своё, на странице: системный
 * window.prompt в Safari прерывает звук (аудиоконтекст становится «interrupted»).
 */
export function openInput(anchor: Element, value: string, done: (v: string) => void, numeric = false) {
  if (!inputPopup) {
    const p = makePopup('rename');
    inputField = h('input', 'rename-input');
    inputField.type = 'text';
    const ok = () => {
      inputDone?.(inputField.value);
      inputDone = null;
      inputField.blur();
      p.close();
    };
    inputField.addEventListener('keydown', (e) => { if (e.key === 'Enter') ok(); });
    p.box.append(inputField, popupButton('OK', ok));
    inputPopup = p;
  }
  inputDone = done;
  inputField.value = value;
  inputField.maxLength = numeric ? 10 : 12;
  inputField.inputMode = numeric ? 'decimal' : 'text';
  inputPopup.openAt(anchor, 220);
  inputField.focus();
  inputField.select();
}

export function popupButton(label: string, onTap: () => void): HTMLButtonElement {
  const b = h('button', 'popup-btn', label);
  b.addEventListener('pointerup', () => { if (!b.disabled) onTap(); });
  return b;
}
