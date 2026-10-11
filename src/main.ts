import './style.css';
import { TRACK_COUNT } from './params';
import { advanceLfos, ui, updateTransition } from './state';
import { synthLoad, unlockAudio, updateAudio } from './audio/engine';
import { initProjects } from './project';
import { initMidi, sendFeedback, setNoteHandler } from './midi';
import { settings } from './settings';
import { updateTransport } from './transport';
import { buildEqButton, buildLeftButtons, buildPatternsButton, buildRightButtons, buildTransportButtons, renderButtons } from './ui/buttons';
import { renderFields } from './ui/controls';
import { buildEq, renderEq } from './ui/eq';
import { buildSampleEditor, renderSampleEditor } from './ui/sampleedit';
import { h, setClass, setText } from './ui/dom';
import { buildKnobGrid, renderKnobs } from './ui/knobs';
import { buildLearnBar, renderLearn } from './ui/learn';
import { buildPages, renderPages } from './ui/pages';
import { buildPatternGrid, renderPatternGrid } from './ui/patterns';
import { buildPiano, buildProgression, press, renderPiano } from './ui/piano';
import { buildMeter, renderMeter, tickMeter } from './ui/meter';
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
// Центр: ручки 4×4, сетка паттернов 8×8 (кнопка PATTERNS), эквалайзер (кнопка EQ) или редактор
// сэмпла (удержание окна сэмпла).
const knobGrid = buildKnobGrid();
const center = h('div', 'center');
center.append(knobGrid, buildPatternGrid(), buildEq(), buildSampleEditor());
// Справа с краю — измеритель уровня.
const meter = buildMeter();
main.append(left, center, right, meter);

// Верхняя панель: слева бутерброд, темп и метроном (ширина левой колонки); дальше одной сеткой
// равной ширины SCALE, ROOT, PLAY, REC, UNDO, REDO; справа PATTERNS и EQ над правой колонкой.
const topbar = buildTopbar();
const [leftGroup, ...fields] = [...topbar.children];
const topMid = h('div', 'top-mid');
topMid.append(...fields, ...buildTransportButtons().children);
const topRight = h('div', 'top-right');
// Справа от EQ, над измерителем уровня — загрузка процессора.
const cpu = h('div', 'cpu', 'CPU\n–');
topRight.append(buildPatternsButton(), buildEqButton(), cpu);
topbar.append(leftGroup, topMid, topRight);

// Число столбцов дорожек: строка дорожек и сетка паттернов совпадают по ширине столбцов.
app.style.setProperty('--tracks', String(TRACK_COUNT));

app.append(topbar, main, buildTracks(), buildSequencer(), buildPiano(), buildProgression(), buildLearnBar());

// Блокируем системные жесты Safari: масштаб двойным тапом и щипком, лупу, контекстное меню.
// Всё управление идёт через pointer-события, поэтому touch-события можно гасить целиком.
// Поля ввода и прокручиваемый список пресетов получают обычные касания.
const allowNative = (e: Event) => e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement
  || (e.target instanceof Element && e.target.closest('.preset-grid, .project-list') !== null);
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
  updateTransition();
  updateAudio(now);
  renderTopbar(now);
  renderFields();
  renderSample(now);
  setClass(knobGrid, 'hidden', ui.patternView || ui.eqView || ui.sampleView);
  // Сетка паттернов занимает всю ширину; эквалайзер — до края миниатюр страниц, справа измеритель.
  setClass(main, 'patterns', ui.patternView);
  // Редактор сэмпла — на том же месте, что эквалайзер.
  setClass(main, 'eq', ui.eqView || ui.sampleView);
  renderKnobs(now);
  renderPatternGrid();
  renderEq();
  renderSampleEditor();
  renderTracks(now);
  renderSequencer();
  renderPiano(now);
  renderPages();
  renderButtons();
  renderLearn();
  sendFeedback(now);
  if (!ui.patternView) renderMeter(now);
  else tickMeter(now);
  busy += performance.now() - t0;
  renderCpu(now);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// Последний открытый проект (или новый) и автосохранение.
void initProjects();

// MIDI: если маппинги уже есть — подключаемся сразу (без открытия меню MIDI).
if (settings.mappings.length) void initMidi();

// Ноты с MIDI-входов играют выбранную дорожку, как пианоролл (или дорожку по номеру канала).
setNoteHandler((note, _vel, track) => {
  if (track === null) press([note]);
  else if (track < TRACK_COUNT) press([note], track);
});
