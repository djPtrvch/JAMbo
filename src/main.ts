import './style.css';
import { TRACK_COUNT } from './params';
import { advanceLfos, ui } from './state';
import { initAudio, unlockAudio, updateAudio } from './audio/engine';
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

// Центр: слева окно сэмпла и кнопки модуляции, справа миниатюры страниц и кнопки.
// В режиме паттернов остаётся только сетка во всю ширину.
const left = h('div', 'side left');
left.append(buildSample(), buildLeftButtons());

const right = h('div', 'side right');
right.append(buildPages(), buildRightButtons());

const main = h('div', 'main');
// Центр: ручки 4×4 или сетка паттернов 8×8 (кнопка PATTERNS).
const knobGrid = buildKnobGrid();
const center = h('div', 'center');
center.append(knobGrid, buildPatternGrid());
main.append(left, center, right);

// Верхняя панель: слева поля, по центру PLAY и REC, справа (над правой колонкой) PATTERNS.
const topbar = buildTopbar();
const topLeft = h('div', 'top-left');
topLeft.append(...topbar.children);
const topRight = h('div', 'top-right');
topRight.append(buildPatternsButton());
topbar.append(topLeft, buildTransportButtons(), topRight);

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

// Звук: контекст создаётся сразу (на паузе) и включается любым касанием экрана
// (iOS Safari разрешает звук только из действия пользователя).
initAudio();
document.addEventListener('pointerdown', unlockAudio);
document.addEventListener('pointerup', unlockAudio);
document.addEventListener('touchend', unlockAudio);

let last = performance.now();
function frame(now: number) {
  advanceLfos(Math.min(0.1, (now - last) / 1000));
  last = now;
  updateTransport(now);
  updateAudio(now);
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
