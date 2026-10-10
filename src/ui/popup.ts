// Всплывающее окно с кнопками (меню страниц, дорожек, гаммы, ноты).

import { h } from './dom';

export interface Popup {
  root: HTMLElement;
  box: HTMLElement;
  /** Показать окно под (или над) элементом. */
  openAt(anchor: Element, width: number): void;
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
    close() { root.classList.add('hidden'); },
    isOpen: () => !root.classList.contains('hidden'),
  };
  // Тап мимо окна закрывает его.
  root.addEventListener('pointerdown', (e) => { if (e.target === root) p.close(); });
  return p;
}

export function popupButton(label: string, onTap: () => void): HTMLButtonElement {
  const b = h('button', 'popup-btn', label);
  b.addEventListener('pointerup', () => { if (!b.disabled) onTap(); });
  return b;
}
