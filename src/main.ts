import './style.css';
import { TRACK_COUNT } from './params';
import { advanceLfos, ui } from './state';
import { updateTransport } from './transport';
import { buildLeftButtons, buildPatternsButton, buildRightButtons, buildTransportButtons, renderButtons } from './ui/buttons';
import { renderFields } from './ui/controls';
import { h, setClass } from './ui/dom';
import { buildKnobGrid, renderKnobs } from './ui/knobs';
import { buildPages, renderPages } from './ui/pages';
import { buildPatternGrid, renderPatternGrid } from './ui/patterns';
import { buildPiano, buildProgression, renderPiano } from './ui/piano';
import { buildSample, renderSample } from './ui/sample';
import { buildSequencer, renderSequencer } from './ui/sequencer';
import { buildTopbar, renderTopbar } from './ui/topbar';
import { buildTracks, renderTracks } from './ui/tracks';

const app = document.getElementById('app')!;

// Центр — сетка из областей: слева окно сэмпла и кнопки модуляции, справа PLAY/REC сверху,
// под ними миниатюры страниц и кнопки. В режиме паттернов остаются только PLAY/REC и сетка.
const left = h('div', 'side left');
left.append(buildSample(), buildLeftButtons());

const right = h('div', 'side right');
right.append(buildPages(), buildRightButtons());

const main = h('div', 'main');
// Центр: ручки 4×4 или сетка паттернов 8×8 (кнопка PATTERNS).
const knobGrid = buildKnobGrid();
const center = h('div', 'center');
center.append(knobGrid, buildPatternGrid());
main.append(left, center, buildTransportButtons(), right);

// Кнопка PATTERNS — рядом с корневой нотой.
const topbar = buildTopbar();
topbar.append(buildPatternsButton());

// Число столбцов дорожек: строка дорожек и сетка паттернов совпадают по ширине столбцов.
app.style.setProperty('--tracks', String(TRACK_COUNT));

app.append(topbar, main, buildTracks(), buildSequencer(), buildPiano(), buildProgression());

// Блокируем системные жесты Safari: масштаб двойным тапом и щипком, лупу, контекстное меню.
// Всё управление идёт через pointer-события, поэтому touch-события можно гасить целиком.
const allowNative = (e: Event) => e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement;
for (const type of ['touchstart', 'touchmove', 'touchend'] as const) {
  document.addEventListener(type, (e) => { if (!allowNative(e)) e.preventDefault(); }, { passive: false });
}
document.addEventListener('dblclick', (e) => e.preventDefault());
document.addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('gesturestart', (e) => e.preventDefault());

let last = performance.now();
function frame(now: number) {
  advanceLfos(Math.min(0.1, (now - last) / 1000));
  last = now;
  updateTransport(now);
  renderTopbar(now);
  renderFields();
  renderSample(now);
  setClass(knobGrid, 'hidden', ui.patternView);
  // Сетка паттернов занимает всю ширину, боковые колонки скрываются.
  setClass(main, 'patterns', ui.patternView);
  renderKnobs(now);
  renderPatternGrid();
  renderTracks(now);
  renderSequencer();
  renderPiano(now);
  renderPages();
  renderButtons();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
