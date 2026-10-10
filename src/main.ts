import './style.css';
import { TRACK_COUNT } from './params';
import { advanceLfos, ui } from './state';
import { synthLoad, unlockAudio, updateAudio } from './audio/engine';
import { updateTransport } from './transport';
import { buildEqButton, buildLeftButtons, buildPatternsButton, buildRightButtons, buildTransportButtons, renderButtons } from './ui/buttons';
import { renderFields } from './ui/controls';
import { buildEq, renderEq } from './ui/eq';
import { h, setClass, setText } from './ui/dom';
import { buildKnobGrid, renderKnobs } from './ui/knobs';
import { buildPages, renderPages } from './ui/pages';
import { buildPatternGrid, renderPatternGrid } from './ui/patterns';
import { buildPiano, buildProgression, renderPiano } from './ui/piano';
import { buildMeter, renderMeter } from './ui/meter';
import { buildSample, buildSampleNav, renderSample } from './ui/sample';
import { buildSequencer, renderSequencer } from './ui/sequencer';
import { buildTopbar, renderTopbar } from './ui/topbar';
import { buildTracks, renderTracks } from './ui/tracks';

const app = document.getElementById('app')!;

// Центр: слева окно сэмпла и кнопки модуляции, справа миниатюры страниц и кнопки.
// В режиме паттернов остаётся только сетка во всю ширину.
const left = h('div', 'side left');
left.append(buildSample(), buildSampleNav(), buildLeftButtons());

const right = h('div', 'side right');
right.append(buildPages(), buildRightButtons());

const main = h('div', 'main');
// Центр: ручки 4×4, сетка паттернов 8×8 (кнопка PATTERNS) или эквалайзер (кнопка EQ).
const knobGrid = buildKnobGrid();
const center = h('div', 'center');
center.append(knobGrid, buildPatternGrid(), buildEq());
// Справа с краю — измеритель уровня.
const meter = buildMeter();
main.append(left, center, right, meter);

// Верхняя панель: слева поля; справа PLAY и REC, а за ними PATTERNS и EQ над правой колонкой.
const topbar = buildTopbar();
const topLeft = h('div', 'top-left');
topLeft.append(...topbar.children);
const topRight = h('div', 'top-right');
// Справа от EQ, над измерителем уровня — загрузка процессора.
const cpu = h('div', 'cpu', 'CPU\n–');
topRight.append(buildPatternsButton(), buildEqButton(), cpu);
topbar.append(topLeft, buildTransportButtons(), topRight);

// Число столбцов дорожек: строка дорожек и сетка паттернов совпадают по ширине столбцов.
app.style.setProperty('--tracks', String(TRACK_COUNT));

app.append(topbar, main, buildTracks(), buildSequencer(), buildPiano(), buildProgression());

// Блокируем системные жесты Safari: масштаб двойным тапом и щипком, лупу, контекстное меню.
// Всё управление идёт через pointer-события, поэтому touch-события можно гасить целиком.
// Поля ввода и прокручиваемый список пресетов получают обычные касания.
const allowNative = (e: Event) => e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement
  || (e.target instanceof Element && e.target.closest('.preset-grid') !== null);
// touchend не гасим: в iOS именно отпускание пальца — действие пользователя, которое включает звук.
// Масштаб двойным тапом отключён через CSS (touch-action: none на всех элементах).
for (const type of ['touchstart', 'touchmove'] as const) {
  document.addEventListener(type, (e) => { if (!allowNative(e)) e.preventDefault(); }, { passive: false });
}
document.addEventListener('dblclick', (e) => e.preventDefault());
document.addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('gesturestart', (e) => e.preventDefault());

// Звук включается отпусканием пальца (iOS Safari разрешает звук только из действия пользователя).
document.addEventListener('touchend', unlockAudio);
document.addEventListener('pointerup', unlockAudio);

// Загрузка процессора: доля времени, которую занимает работа интерфейса и транспорта в кадре
// (основной поток), плюс расчёт синтов в AudioWorklet. Встроенные узлы Web Audio браузер
// не отчитывает — их здесь нет. Обновляется дважды в секунду.
let busy = 0;
let cpuFrom = performance.now();

function renderCpu(now: number) {
  if (now - cpuFrom < 500) return;
  const pct = Math.round((busy / (now - cpuFrom) + synthLoad()) * 100);
  busy = 0;
  cpuFrom = now;
  setText(cpu, `CPU\n${pct}%`);
  setClass(cpu, 'high', pct >= 70);
}

let last = performance.now();
function frame(now: number) {
  const t0 = performance.now();
  advanceLfos(Math.min(0.1, (now - last) / 1000));
  last = now;
  updateTransport(now);
  updateAudio(now);
  renderTopbar(now);
  renderFields();
  renderSample(now);
  setClass(knobGrid, 'hidden', ui.patternView || ui.eqView);
  // Сетка паттернов занимает всю ширину; эквалайзер — до края миниатюр страниц, справа измеритель.
  setClass(main, 'patterns', ui.patternView);
  setClass(main, 'eq', ui.eqView);
  renderKnobs(now);
  renderPatternGrid();
  renderEq();
  renderTracks(now);
  renderSequencer();
  renderPiano(now);
  renderPages();
  renderButtons();
  if (!ui.patternView) renderMeter(now);
  busy += performance.now() - t0;
  renderCpu(now);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
