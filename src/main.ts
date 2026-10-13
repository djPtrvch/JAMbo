import './style.css';
import { applyTheme } from './ui/theme';

// Оформление до первой отрисовки (светлое или тёмное — по настройке или как в системе).
applyTheme();

// Веб-приложение с экрана «Домой» (iOS): при запуске первые кадры (~0,4 с) WebKit показывает страницу
// с чужим масштабом вьюпорта (как будто ширина портретная), потом поправляет сам. Пока ширина
// страницы не совпала с длинной/короткой стороной экрана и масштаб не 1, приложение скрыто (виден
// только фон); не дольше 1 с — на случай окна Stage Manager, где ширина и не совпадёт.
const standalone = (navigator as { standalone?: boolean }).standalone === true
  || matchMedia('(display-mode: standalone)').matches;
if (standalone) {
  const rootEl = document.documentElement;
  const ok = () => {
    const long = Math.max(screen.width, screen.height);
    const short = Math.min(screen.width, screen.height);
    const want = innerWidth > innerHeight ? long : short;
    const scale = window.visualViewport?.scale ?? 1;
    return Math.abs(innerWidth - want) <= 2 && Math.abs(scale - 1) < 0.01;
  };
  if (!ok()) {
    rootEl.style.visibility = 'hidden';
    const t0 = performance.now();
    const check = () => {
      if (ok() || performance.now() - t0 > 1000) { rootEl.style.visibility = ''; return; }
      requestAnimationFrame(check);
    };
    requestAnimationFrame(check);
  }
}
import { setTrackCountParams, setTrackNameParams } from './params';
import { advanceLfos, autoRecordFrame, doc, onGateChange, onTrackDeleted, ui, updateTransition, syncLead } from './state';
import { buildAuto, renderAuto, toggleAuto } from './ui/auto';
import { attachDebug, markGate } from './ui/debug';
import { applyAllGates, synthLoad, trackDeleted, unlockAudio, updateAudio } from './audio/engine';
import { initProjects } from './project';
import { initMidi, registerAction, sendFeedback, setNoteHandler } from './midi';
import { settings } from './settings';
import { updateTransport } from './transport';
import { buildEqButton, buildLeftButtons, buildShiftButton, buildPatternsButton, buildRightButtons, buildTransportButtons, renderButtons } from './ui/buttons';
import { renderFields } from './ui/controls';
import { buildEq, renderEq } from './ui/eq';
import { buildLimiterWindow, renderLimiterWindow } from './ui/limiter';
import { buildSampleEditor, renderSampleEditor } from './ui/sampleedit';
import { buildBrowser, renderBrowser } from './ui/browser';
import { h, setClass, setText } from './ui/dom';
import { buildKnobGrid, renderKnobs } from './ui/knobs';
import { buildLearnBar, renderLearn } from './ui/learn';
import { buildPages, renderPages } from './ui/pages';
import { buildScope, buildScopeButtons, renderScope } from './ui/scope';
import { eqSampleRate } from './audio/engine';
import { buildPatternGrid, renderPatternGrid } from './ui/patterns';
import { buildPiano, press, renderPiano } from './ui/piano';
import { buildMeter, renderMeter, tickMeter } from './ui/meter';
import { buildSample, buildSampleNav, renderSample } from './ui/sample';
import { buildSequencer, renderSequencer } from './ui/sequencer';
import { buildTopbar, renderTopbar } from './ui/topbar';
import { buildTracks, renderTracks } from './ui/tracks';
import { SCROLL_SEL } from './ui/scrollbar';

const app = document.getElementById('app')!;

// Центр: слева окно сэмпла и кнопки модуляции, справа миниатюры страниц и кнопки.
// В режиме паттернов остаётся только сетка во всю ширину.
const left = h('div', 'side left');
left.append(buildSample(), buildSampleNav(), buildLeftButtons());

const right = h('div', 'side right');
// При MST на месте миниатюр страниц — скоп мастера (гониометр, осциллоскоп).
const pagesEl = buildPages();
// При MST на месте MORPH, RANDOM, FX, MOD — кнопки точки съёма скопа.
const rightBtns = buildRightButtons();
right.append(pagesEl, buildScope(), rightBtns, buildScopeButtons(buildShiftButton()));

const main = h('div', 'main');
// Центр: ручки 4×4, сетка паттернов 8×8 (кнопка PATTERNS), эквалайзер (кнопка EQ) или редактор
// сэмпла (удержание окна сэмпла).
const knobGrid = buildKnobGrid();
const center = h('div', 'center');
center.append(knobGrid, buildPatternGrid(), buildEq(), buildLimiterWindow(), buildSampleEditor(), buildBrowser(), buildAuto());
// Справа с краю — измеритель уровня.
const meter = buildMeter();
main.append(left, center, right, meter);

// Верхняя панель: слева бутерброд, темп и метроном (ширина левой колонки); дальше SCALE, ROOT
// (заполняет промежуток до UNDO), над центром сетки ручек UNDO, PLAY, REC (значки, вдвое уже), REDO,
// справа EQ; над правой колонкой PATTERNS и ARRANGE (пока неактивна).
const topbar = buildTopbar();
const [leftGroup, ...fields] = [...topbar.children];
const topMid = h('div', 'top-mid');
// Между REDO и EQ — кнопка AUTO: окно автоматизации на месте центра экрана (повторное нажатие — закрыть).
const autoBtn = h('div', 'btn tb-auto');
autoBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleAuto(); });
registerAction('AUTO', { label: 'AUTO', press: toggleAuto, state: () => ui.autoView }, autoBtn);
autoBtn.innerHTML = '<svg class="tr-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2 13c3-8 7-8 10 0s7 8 10 0"/><circle cx="2.5" cy="13" r="1.9" fill="currentColor"/><circle cx="7" cy="7" r="1.9" fill="currentColor"/><circle cx="17" cy="19" r="1.9" fill="currentColor"/><circle cx="21.5" cy="13" r="1.9" fill="currentColor"/></svg>';
topMid.append(...fields, ...buildTransportButtons().children, autoBtn, buildEqButton());
const topRight = h('div', 'top-right');
// Справа от EQ, над измерителем уровня — загрузка процессора.
const cpu = h('div', 'cpu', 'CPU\n–');
// ARRANGE (режим аранжировки) — позже; пока неактивна, как SHIFT.
topRight.append(buildPatternsButton(), h('div', 'btn disabled arrange-slot', 'ARRANGE'), cpu);
attachDebug(cpu);

// Mute/solo звучат сразу из жеста, не дожидаясь кадра.
onGateChange(() => markGate(applyAllGates()));
onTrackDeleted(trackDeleted);
topbar.append(leftGroup, topMid, topRight);

// Число столбцов дорожек: строка дорожек и сетка паттернов совпадают по ширине столбцов
// (дорожек 8…12; MIX и MST — постоянной ширины).

let trackCols = 0;
let trackNames = '';
function syncTrackCount() {
  const names = doc.tracks.map((t) => t.name);
  const sig = names.join('\n');
  if (sig !== trackNames) { trackNames = sig; setTrackNameParams(names); }
  const n = doc.tracks.length;
  if (n === trackCols) return;
  trackCols = n;
  app.style.setProperty('--tracks', String(n));
  setTrackCountParams(n);
}
syncTrackCount();

app.append(topbar, main, buildTracks(), buildSequencer(), buildPiano(), buildLearnBar());

// Блокируем системные жесты Safari: масштаб двойным тапом и щипком, лупу, контекстное меню.
// Всё управление идёт через pointer-события, поэтому touch-события можно гасить целиком.
// Поля ввода и прокручиваемые меню и списки получают обычные касания.
const allowNative = (e: Event) => e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement
  || (e.target instanceof Element && e.target.closest(SCROLL_SEL) !== null);
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
  // Следующий кадр — сразу: ошибка в кадре (пишется в консоль) не останавливает интерфейс и звук.
  requestAnimationFrame(frame);
  try { frameBody(now); } catch (e) { console.error('frame', e); }
}

function frameBody(now: number) {
  syncTrackCount();
  const t0 = performance.now();
  advanceLfos(Math.min(0.1, (now - last) / 1000));
  last = now;
  updateTransport(now);
  // Запись автоматизации: положение ручки — в кривую (~60 раз в секунду, позиция — по часам секвенсора).
  autoRecordFrame(now);
  updateTransition();
  syncLead();
  updateAudio(now);
  renderTopbar(now);
  renderFields();
  renderSample(now);
  setClass(knobGrid, 'hidden', ui.patternView || ui.eqView || ui.limView || ui.sampleView || ui.browserView || ui.autoView);
  // Сетка паттернов занимает всю ширину; эквалайзер — до края миниатюр страниц, справа измеритель.
  setClass(main, 'patterns', ui.patternView);
  // Редактор сэмпла — на том же месте, что эквалайзер.
  // Окно лимитера мастера — тоже на месте EQ.
  setClass(main, 'eq', ui.eqView || ui.limView || ui.sampleView || ui.browserView || ui.autoView);
  // Окно AUTO — во всю ширину (над шагами 1–16), измеритель скрыт.
  setClass(main, 'auto-full', ui.autoView);
  setClass(autoBtn, 'active', ui.autoView);
  // REC при игре: поворот ручки пишет автоматизацию — у кнопки AUTO красный контур.
  setClass(autoBtn, 'auto-armed', ui.rec && ui.playing);
  renderKnobs(now);
  renderPatternGrid();
  renderEq();
  renderLimiterWindow(now);
  renderSampleEditor();
  renderBrowser();
  renderAuto();
  renderTracks(now);
  renderSequencer();
  renderPiano(now);
  renderPages();
  setClass(pagesEl, 'hidden', ui.channel === 'master');
  setClass(rightBtns, 'hidden', ui.channel === 'master');
  renderScope(eqSampleRate());
  renderButtons();
  renderLearn();
  sendFeedback(now);
  if (!ui.patternView) renderMeter(now);
  else tickMeter(now);
  busy += performance.now() - t0;
  renderCpu(now);
}
requestAnimationFrame(frame);

// Последний открытый проект (или новый) и автосохранение.
void initProjects();

// MIDI: если маппинги уже есть — подключаемся сразу (без открытия меню MIDI).
if (settings.mappings.length) void initMidi();

// Ноты с MIDI-входов играют выбранную дорожку, как пианоролл (или дорожку по номеру канала).
setNoteHandler((note, vel, track) => {
  // VELOCITY: сила ноты из сообщения MIDI (1–127).
  const v = settings.velocity ? Math.max(1, vel) / 127 : 1;
  if (track === null) press([note], null, false, v);
  else if (track < doc.tracks.length) press([note], track, false, v);
});
