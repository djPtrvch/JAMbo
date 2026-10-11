// Оформление: светлое и тёмное. SETTINGS → APPEARANCE: SYSTEM (как в системе — меняется вместе
// с настройкой iPad), LIGHT, DARK. Цвета — переменные CSS (style.css, :root[data-theme]); холсты
// (EQ, редактор сэмпла) берут их через color().

import { saveSettings, settings } from '../settings';

const media = window.matchMedia('(prefers-color-scheme: dark)');
let cache = new Map<string, string>();

/** Тема, которая сейчас на экране. */
export const currentTheme = (): 'light' | 'dark' => (settings.theme === 'system' ? (media.matches ? 'dark' : 'light') : settings.theme);

export function applyTheme() {
  const t = currentTheme();
  document.documentElement.dataset.theme = t;
  // Цвет полосы Safari и строки состояния — как фон.
  cache = new Map();
  let meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) { meta = document.createElement('meta'); meta.setAttribute('name', 'theme-color'); document.head.append(meta); }
  meta.setAttribute('content', color('--bg'));
}

export function setTheme(theme: 'system' | 'light' | 'dark') {
  saveSettings({ theme });
  applyTheme();
}

/** Значение переменной цвета для холста (кэшируется до смены темы). */
export function color(name: string): string {
  let v = cache.get(name);
  if (v === undefined) {
    v = getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#888';
    cache.set(name, v);
  }
  return v;
}

// Система сменила тему (iPad: светлое/тёмное, в том числе автоматически) — следуем, если SYSTEM.
media.addEventListener('change', () => { if (settings.theme === 'system') applyTheme(); });
