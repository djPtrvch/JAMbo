// MIX: на месте миниатюр страниц — превью паттернов дорожек, строка на дорожку (сверху T1).
// В строке — играющая страница активного паттерна дорожки (без проигрывания — первая из
// выбранных для игры), триги как в миниатюрах страниц, шаг под курсором обведён.
// Остановленная или заглушённая дорожка — бледнее. Строк столько, сколько дорожек.

import { STEPS_PER_PAGE, TRACK_COUNT } from '../params';
import { audible, doc, hasLocks, playRange, rt, ui } from '../state';
import { h, setClass, setText } from './dom';

interface Row { root: HTMLElement; name: HTMLElement; cells: HTMLElement[] }
const rows: Row[] = [];
let el: HTMLElement;

export function buildMixPreview(): HTMLElement {
  el = h('div', 'mix-preview hidden');
  el.style.gridTemplateRows = `repeat(${TRACK_COUNT}, minmax(0, 1fr))`;
  for (let i = 0; i < TRACK_COUNT; i++) {
    const root = h('div', 'mix-prev-row');
    const name = h('div', 'mix-prev-name');
    const thumb = h('div', 'thumb');
    const cells: HTMLElement[] = [];
    for (let k = 0; k < STEPS_PER_PAGE; k++) {
      const c = h('div', 'thumb-cell');
      if (k % 4 === 0) c.classList.add('beat');
      cells.push(c);
      thumb.append(c);
    }
    root.append(name, thumb);
    rows.push({ root, name, cells });
    el.append(root);
  }
  return el;
}

export function renderMixPreview() {
  const show = ui.channel === 'mix';
  setClass(el, 'hidden', !show);
  if (!show) return;
  rows.forEach((r, i) => {
    const t = doc.tracks[i];
    setText(r.name, t.name);
    const pos = ui.playing && !t.stopped ? rt.playPos[i] : -1;
    const page = pos >= 0 ? Math.floor(pos / STEPS_PER_PAGE) : Math.floor(playRange(t)[0] / STEPS_PER_PAGE);
    setClass(r.root, 'dim', t.stopped || !audible(i));
    r.cells.forEach((c, k) => {
      const s = t.pages[page]?.[k];
      const index = page * STEPS_PER_PAGE + k;
      setClass(c, 'on', !!s?.on);
      setClass(c, 'plock', !!s?.on && hasLocks(s));
      setClass(c, 'lock-only', !!s && !s.on && hasLocks(s));
      setClass(c, 'outside', index >= t.length);
      setClass(c, 'pos', index === pos);
    });
  });
}
