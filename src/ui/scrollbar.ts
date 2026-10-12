/**
 * Прокрутка меню и списков пальцем и полоса прокрутки справа. В iOS Safari системная полоса
 * видна только во время прокрутки, поэтому рисуем свою: полупрозрачная, видна всегда, пока
 * содержимое не помещается в окно. Полосы лежат в отдельном слое поверх страницы и следуют
 * за прокручиваемыми элементами — разметку меню они не трогают.
 */

/** Прокручиваемые меню и списки (касания в них — обычные, как у браузера). */
export const SCROLL_SEL = '.scrolly, .preset-grid, .project-list, .popup-box, .eq-scroll, .mm-body';

const layer = document.createElement('div');
layer.className = 'scroll-layer';
document.body.append(layer);
const thumbs: HTMLElement[] = [];
let scrollers: Element[] = [];
let frame = 0;

function tick() {
  // Список прокручиваемых — раз в ~0,25 с (меню открываются и закрываются).
  if (frame++ % 15 === 0) scrollers = [...document.querySelectorAll(SCROLL_SEL)];
  let n = 0;
  for (const el of scrollers) {
    const { scrollHeight: sh, clientHeight: ch, scrollTop: st } = el;
    if (sh <= ch + 1 || !el.isConnected) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const th = Math.max(24, (ch * ch) / sh);
    const y = r.top + (r.height - th) * Math.min(1, Math.max(0, st / (sh - ch)));
    let t = thumbs[n];
    if (!t) { t = document.createElement('div'); t.className = 'scroll-thumb'; layer.append(t); thumbs.push(t); }
    t.style.cssText = `display:block;left:${r.right - 5}px;top:${y + 2}px;height:${th - 4}px`;
    n++;
  }
  for (let i = n; i < thumbs.length; i++) thumbs[i].style.display = 'none';
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
