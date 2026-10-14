// Всплывающее окно с кнопками (меню страниц, дорожек, гаммы, ноты).

import { h } from './dom';


export interface Popup {
  root: HTMLElement;
  box: HTMLElement;
  /** Показать окно под (или над) элементом. */
  openAt(anchor: Element, width: number): void;
  /** Показать окно в заданном прямоугольнике (в координатах окна браузера). */
  openRect(r: { left: number; top: number; width: number; height: number }): void;
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
    openRect(r) {
      root.classList.remove('hidden');
      Object.assign(box.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    },
    close() {
      root.classList.add('hidden');
      box.style.height = '';
    },
    isOpen: () => !root.classList.contains('hidden'),
  };
  // Тап мимо окна закрывает его.
  // UNDO и REDO работают и при открытом окне: касание по ним закрывает окно и передаётся кнопке.
  root.addEventListener('pointerdown', (e) => {
    if (e.target !== root) return;
    p.close();
    const btn = document.elementFromPoint(e.clientX, e.clientY)?.closest('.popup-pass');
    if (btn) btn.dispatchEvent(new PointerEvent('pointerdown', e));
  });
  return p;
}

let inputPopup: Popup | null = null;
let inputField: HTMLInputElement;
let inputDone: ((v: string) => void) | null = null;

/**
 * Поле ввода рядом с элементом anchor (имя дорожки, частота EQ). Своё, на странице: системный
 * window.prompt в Safari прерывает звук (аудиоконтекст становится «interrupted»).
 */
export function openInput(anchor: Element, value: string, done: (v: string) => void, numeric = false, maxLen = 12) {
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
  // Не короче подставленного значения — иначе дописать в него ничего нельзя.
  inputField.maxLength = Math.max(numeric ? 10 : maxLen, value.length);
  inputField.inputMode = numeric ? 'decimal' : 'text';
  inputPopup.openAt(anchor, 220);
  inputField.focus();
  inputField.select();
  // Окно открыто удержанием (по таймеру, не в момент касания): iOS показывает клавиатуру, только
  // если фокус ставится в обработчике касания — ставим его ещё раз, когда палец отпустят.
  const refocus = () => {
    if (inputPopup?.isOpen() && document.activeElement !== inputField) { inputField.focus(); inputField.select(); }
  };
  document.addEventListener('touchend', refocus, { once: true, capture: true });
}

export function popupButton(label: string, onTap: () => void): HTMLButtonElement {
  const b = h('button', 'popup-btn', label);
  // Все надписи DELETE — красным.
  if (/^delete/i.test(label)) b.classList.add('danger');
  b.addEventListener('pointerup', () => { if (!b.disabled) onTap(); });
  return b;
}

/**
 * Строка-переключатель ON/OFF (меню бутерброда): подпись слева, рычажок справа (как в iOS: жёлтый — ON,
 * серый — OFF, бегунок переезжает с анимацией). Тап по строке переключает; after — перерисовать меню
 * после анимации (если от значения зависят другие строки).
 */
export function toggleRow(label: string, on: boolean, pick: (v: boolean) => void, after?: () => void, unavailable?: string): HTMLElement {
  const row = h('div', 'toggle-row');
  const sw = h('div', `switch${on ? ' on' : ''}`);
  const text = h('div', 'toggle-label', label);
  // Недоступен в этой сборке — серый, под подписью причина, тап ничего не делает.
  if (unavailable) {
    row.classList.add('disabled');
    text.append(h('div', 'toggle-sub', unavailable));
    row.append(text, sw);
    return row;
  }
  row.append(text, sw);
  let cur = on;
  row.addEventListener('pointerup', () => {
    cur = !cur;
    sw.classList.toggle('on', cur);
    pick(cur);
    if (after) window.setTimeout(after, 220);
  });
  return row;
}

/** Заголовок вложенного меню: стрелка назад и название. */
export function backHeader(title: HTMLElement, onBack: () => void): HTMLElement {
  const row = h('div', 'menu-header');
  const back = h('div', 'menu-back', '‹');
  back.addEventListener('pointerup', onBack);
  row.append(back, title);
  return row;
}

/**
 * Меню «бутерброд» и его подменю (PROJECTS, SETTINGS, MIDI): вровень с кнопками верхней панели —
 * от левого края кнопки меню до правого края поля SCALE.
 */
export function openMenuPanel(p: Popup, anchor: Element) {
  const a = anchor.getBoundingClientRect();
  const col = document.querySelector('.top-mid > :first-child')?.getBoundingClientRect();
  p.openAt(anchor, col ? col.right - a.left : 420);
  // Размер всегда один: по ширине — от бутерброда до края SCALE, по высоте — от верхней панели до
  // строки дорожек (низ кнопок LFO3 и ENV). Не помещается — прокрутка пальцем вверх-вниз.
  const top = a.bottom + 6;
  const tracks = document.querySelector('.tracks')?.getBoundingClientRect();
  const bottom = tracks ? tracks.top - 6 : window.innerHeight - 8;
  p.box.classList.add('menu-panel');
  Object.assign(p.box.style, { left: `${a.left}px`, top: `${top}px`, height: `${Math.max(120, bottom - top)}px` });
}
