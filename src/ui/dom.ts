// Мелкие помощники для DOM без фреймворков.

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, cls = '', text = ''): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (cls) el.className = cls;
  if (text) el.textContent = text;
  return el;
}

const SVG_NS = 'http://www.w3.org/2000/svg';

export function svg<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string | number> = {}): SVGElementTagNameMap[K] {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
  return el;
}

/** Меняет DOM только при реальном изменении значения (рендер идёт каждый кадр). */
const cache = new WeakMap<Element, Map<string, string>>();

function changed(el: Element, key: string, value: string): boolean {
  let m = cache.get(el);
  if (!m) cache.set(el, (m = new Map()));
  if (m.get(key) === value) return false;
  m.set(key, value);
  return true;
}

export function setText(el: Element, text: string) {
  if (changed(el, '#text', text)) el.textContent = text;
}

export function setAttr(el: Element, name: string, value: string | number) {
  const v = String(value);
  if (changed(el, name, v)) el.setAttribute(name, v);
}

export function setClass(el: Element, name: string, on: boolean) {
  if (changed(el, '.' + name, on ? '1' : '0')) el.classList.toggle(name, on);
}

/** Двойной тап: два касания без движения в пределах 300 мс. */
export const DOUBLE_TAP_MS = 300;
