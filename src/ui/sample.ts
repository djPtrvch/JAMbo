// Окно сэмпла: имя, определённая высота и форма волны сэмпла выбранной дорожки, Start/End
// затемняют отрезанное. Тап — меню звука дорожки: SAMPLE (выбор аудиофайлов с iPad, можно сразу
// несколько — это «папка»: первый заменяет сэмпл, стрелки под окном перелистывают остальные),
// один из 16 движков Mutable Instruments Plaits или MIDI OUT. У синта в окне имя движка и что
// делают Harmonics, Timbre, Morph; стрелки перелистывают движки.
// MIX — уровень каждой дорожки (как измеритель справа). MST — как в Ableton: у компрессора и
// лимитера вход с меткой порога, снижение громкости и выход, под ними BYPASS (и RATIO у компрессора).
// Пока меняются параметры модуляции (MOD) — здесь сразу видны миниатюры LFO1, LFO2, LFO3
// (форма волны с Wave, Depth и Invert, бегущая точка фазы) и огибающей ENV (форма ADSR).

import {
  audioState, limiterLookahead, limiterReduction, sampleIsStereo, trackDuckDb, trackIsStereo,
  type Level, masterLevels, masterReduction, samplePeaks,
  sampleRoot, trackLevel,
} from '../audio/engine';
import { LFO_WAVES, OVER_PEAK, RATIOS, SYNTH_ENGINES, TRACK_COUNT, noteName, synthEngine, synthKey } from '../params';
import { fmtDb, levelFrac } from './meter';
import { makePopup, popupButton } from './popup';
import { audible, cycleRatio, doc, heldStepSound, liveMaster, setStepSound, folderItemName, folderPos, stepFolder, stepFolderOnSteps, setTrackSynth, toggleCmpBypass, toggleLimBypass, envAt, envOut, envShape, lfoShape, rt, sampleName, selTrack, ui } from '../state';
import { openSampleEditor } from './sampleedit';
import { iconView, renderIcon, type IconView } from './engineIcon';
import { openBrowser } from './browser';
import { h, setAttr, setClass, setText, svg } from './dom';

const W = 200;
const H = 80;
const POINTS = 100;
/** Фиксированный «случайный» рисунок для формы Random. */
/** Удержание окна сэмпла — редактор сэмпла. */
const SAMPLE_HOLD_MS = 500;
const RANDOM_STEPS = [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.75, -0.1];

interface Mini { title: HTMLElement; wave: SVGPathElement; dot: SVGCircleElement }
let stub: HTMLElement;
let stubName: HTMLElement;
let waveTitle: HTMLElement;
let wavePath: SVGPathElement;
let cutStart: SVGRectElement;
let cutEnd: SVGRectElement;
let wavePeaksKey = '';
let waveSvg: SVGSVGElement;
let synthInfo: HTMLElement;
let synthFull: HTMLElement;
let bigIcon: IconView;
const BIG_ICON_PX = 120;
const synthRows: HTMLElement[] = [];
let previews: HTMLElement;
let masterPanel: HTMLElement;
let ratioBtn: HTMLElement;
let lookaheadText: HTMLElement;
let limBypassBtn: HTMLElement;
let cmpBypassBtn: HTMLElement;
let mixPanel: HTMLElement;
let navLabel: HTMLElement;
let navRow: HTMLElement;

/**
 * Вертикальный метр (1 или 2 канала): заливка, пик-холд (тонкая светлая линия ~1,5 с),
 * метка клиппинга сверху, метка порога (белая линия), число и подпись.
 * kind: 'yellow' — жёлтый (микшер, как измеритель справа; выше 0 dB — красный);
 * 'meter' — метр мастера: тоже жёлтый (выше 0 dB — красный), со шкалой в dB;
 * 'gr' — снижение громкости, оранжевым сверху.
 */
type BarKind = 'yellow' | 'meter' | 'gr';
interface VBar {
  root: HTMLElement; chans: HTMLElement[]; fills: HTMLElement[]; holds: HTMLElement[]; gr: HTMLElement;
  clipMark: HTMLElement; mark: HTMLElement; value: HTMLElement; label: HTMLElement; kind: BarKind;
}
const mixBars: VBar[] = [];
const compBars: VBar[] = [];
const limBars: VBar[] = [];

/** Отметки шкалы в dB (как сетка на измерителях Ableton). */
const TICKS = [-6, -12, -24, -48];

function vbar(label: string, kind: BarKind, valueOnTop = false): VBar {
  const root = h('div', 'vbar-col');
  const clipMark = h('div', 'vbar-clip');
  const box = h('div', 'vbar-box');
  const chans: HTMLElement[] = [];
  const fills: HTMLElement[] = [];
  const holds: HTMLElement[] = [];
  for (let ch = 0; ch < (kind === 'gr' ? 1 : 2); ch++) {
    const bar = h('div', `vbar ${kind}`);
    const fill = h('div', 'vbar-fill');
    bar.append(fill);
    // У GR пик-холда нет (линии сверху не нужно).
    if (kind !== 'gr') {
      const hold = h('div', 'vbar-hold');
      bar.append(hold);
      holds.push(hold);
    }
    chans.push(bar);
    fills.push(fill);
    box.append(bar);
  }
  if (kind === 'meter' || kind === 'yellow') {
    for (const db of TICKS) {
      const t = h('div', 'vbar-tick');
      t.style.bottom = `${(dbFrac(db) * 100).toFixed(1)}%`;
      box.append(t);
    }
  }
  // Снижение громкости от sidechain на метре дорожки — оранжевым сверху.
  const gr = h('div', 'vbar-gr hidden');
  const mark = h('div', 'vbar-mark hidden');
  box.append(gr, mark);
  const value = h('div', 'vbar-val');
  const lab = h('div', 'vbar-label', label);
  if (valueOnTop) root.append(value, clipMark, box, lab);
  else root.append(clipMark, box, value, lab);
  if (kind === 'gr') clipMark.classList.add('invisible');
  return { root, chans, fills, holds, gr, clipMark, mark, value, label: lab, kind };
}

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

/** Метр уровня: доли по каналам, пик-холд, перегрузка, метка порога, число. */
function setLevelBar(b: VBar, lv: Level, stereo: boolean, text: string, mark: number | null = null, grDb = 0) {
  const fr = stereo ? [levelFrac(lv.l), levelFrac(lv.r)] : [levelFrac(Math.max(lv.l, lv.r))];
  const hd = stereo ? [levelFrac(lv.holdL), levelFrac(lv.holdR)] : [levelFrac(Math.max(lv.holdL, lv.holdR))];
  b.chans.forEach((c, i) => setClass(c, 'hidden', i >= fr.length));
  // Выше 0 dB (пик ≥ 1.0) полоса канала горит красным — так во всех метрах проекта.
  const pk = stereo ? [lv.l, lv.r] : [Math.max(lv.l, lv.r)];
  b.fills.forEach((f, i) => {
    if (i >= fr.length) return;
    setAttr(f, 'style', `height:${(clamp01(fr[i]) * 100).toFixed(1)}%`);
    setClass(f, 'over', pk[i] >= OVER_PEAK);
  });
  b.holds.forEach((hl, i) => {
    if (i >= hd.length) return;
    setClass(hl, 'hidden', hd[i] <= 0.01);
    setAttr(hl, 'style', `bottom:${(clamp01(hd[i]) * 100).toFixed(1)}%`);
  });
  setClass(b.clipMark, 'on', lv.clip);
  setClass(b.mark, 'hidden', mark === null);
  if (mark !== null) setAttr(b.mark, 'style', `bottom:${(clamp01(mark) * 100).toFixed(1)}%`);
  setClass(b.gr, 'hidden', grDb > -0.1);
  if (grDb <= -0.1) setAttr(b.gr, 'style', `height:${(clamp01(-grDb / 24) * 100).toFixed(1)}%`);
  setText(b.value, text);
}

/** Метр снижения громкости (GR): доля сверху вниз, число в dB. */
function setGrBar(b: VBar, grDb: number) {
  setAttr(b.fills[0], 'style', `height:${(clamp01(-grDb / 24) * 100).toFixed(1)}%`);
  setText(b.value, grDb.toFixed(1));
}

/** dB (−60…0) → доля высоты. */
const dbFrac = (db: number) => (db + 60) / 60;
const WAVE_W = 200;
const WAVE_H = 100;
const minis: Mini[] = [];

function buildMini(axis: boolean): [HTMLElement, Mini] {
  const el = h('div', 'mod-mini');
  const title = h('div', 'lfo-title');
  const box = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'lfo-svg' });
  if (axis) box.append(svg('line', { x1: 0, y1: H / 2, x2: W, y2: H / 2, class: 'lfo-axis' }));
  const wave = svg('path', { class: 'lfo-wave' });
  const dot = svg('circle', { r: 5, class: 'lfo-dot' });
  box.append(wave, dot);
  el.append(title, box);
  return [el, { title, wave, dot }];
}

export function buildSample(): HTMLElement {
  const root = h('div', 'sample');
  stub = h('div', 'sample-stub');
  stubName = h('div', 'sample-name');
  waveTitle = h('div', 'sample-title');
  const wave = svg('svg', { viewBox: `0 0 ${WAVE_W} ${WAVE_H}`, preserveAspectRatio: 'none', class: 'sample-wave' });
  waveSvg = wave;
  synthInfo = h('div', 'synth-info hidden');
  synthFull = h('div', 'synth-full');
  // Крупная живая иконка движка; тап по ней (как по всему окну) открывает меню звука.
  const iconEl = h('div', 'synth-icon engine-icon');
  bigIcon = iconView(iconEl, BIG_ICON_PX);
  synthInfo.append(iconEl, synthFull);
  for (let i = 0; i < 3; i++) {
    const row = h('div', 'synth-row');
    synthRows.push(row);
    synthInfo.append(row);
  }
  wavePath = svg('path', { class: 'sample-wave-path' });
  cutStart = svg('rect', { x: 0, y: 0, height: WAVE_H, class: 'sample-cut' });
  cutEnd = svg('rect', { y: 0, height: WAVE_H, class: 'sample-cut' });
  wave.append(wavePath, cutStart, cutEnd);
  // Тап по окну — меню звука. Оно закрывает всю левую колонку (окно сэмпла, стрелки, LFO и ENV),
  // пока выбирают звук: группы SYNTH (музыкальные движки), DRUMS (шумы и ударные) и
  // SAMPLE · MIDI. Кнопка SAMPLE — с настоящим полем выбора файла поверх (на iOS системный
  // выбор файла надёжно открывается только прямым тапом по полю).
  const menu = makePopup('source-menu');
  // Шаги, зажатые в момент открытия меню: выбранный звук ставится на них, а не на дорожку
  // (пальцы со шагов можно убрать — например, пока открыт выбор файла).
  let stepTargets: number[] = [];
  const stepTitle = h('div', 'source-title step-title hidden');
  menu.box.append(stepTitle);
  // SAMPLE — браузер библиотеки (сэмплы и пресеты по папкам; файлы с iPad и iCloud — IMPORT там).
  // Для зажатых шагов сэмпл из браузера становится их звуком.
  const sampleBtn = popupButton('SAMPLE', () => {
    menu.close();
    openBrowser({ kind: 'load', steps: stepTargets });
  });
  // MIDI OUT: Web MIDI в Safari недоступен — выход MIDI появится в нативном приложении.
  // Для зажатого шага на этом месте TRACK — вернуть шагу звук дорожки.
  const midiBtn = popupButton('MIDI', () => {
    if (stepTargets.length) setStepSound(ui.selectedTrack, stepTargets, null);
    menu.close();
  });
  // SAVE — сохранить синт дорожки пресетом в библиотеку (папку выбирают в браузере) и в папку дорожки.
  const saveBtn = popupButton('SAVE', () => {
    menu.close();
    openBrowser({ kind: 'save-preset' });
  });
  const engineBtns = SYNTH_ENGINES.map((e, k) => popupButton(e.name, () => {
    if (stepTargets.length) setStepSound(ui.selectedTrack, stepTargets, synthKey(k));
    else setTrackSynth(ui.selectedTrack, k);
    menu.close();
  }));
  const group = (title: string, cols: number, items: HTMLElement[]) => {
    const g = h('div', `source-group cols-${cols}`);
    // Высота группы — по числу рядов: кнопки во всех группах одной высоты.
    g.style.flex = `${Math.ceil(items.length / cols)} 1 0`;
    g.append(...items);
    menu.box.append(h('div', 'source-title', title), g);
  };
  group('SYNTH', 2, engineBtns.filter((_, k) => SYNTH_ENGINES[k].bank === 'synth'));
  group('DRUMS', 2, engineBtns.filter((_, k) => SYNTH_ENGINES[k].bank === 'drum'));
  // LOAD — браузер библиотеки (пресеты и сэмплы по папкам).
  const loadBtn = popupButton('LOAD', () => {
    menu.close();
    openBrowser({ kind: 'load', steps: [] });
  });
  group('SAMPLE · MIDI · PRESET', 2, [sampleBtn, midiBtn, saveBtn, loadBtn]);
  // Меню закрывает всю левую колонку (окно сэмпла, стрелки и кнопки LFO/ENV) — кнопки крупнее.
  const menuRect = () => {
    const side = (root.closest('.side') ?? root).getBoundingClientRect();
    return { left: side.left, top: side.top, width: side.width, height: side.height };
  };
  let downY = 0;
  // Удержание окна сэмпла (без зажатого шага) — редактор сэмпла; отпускание тогда меню не открывает.
  let holdTimer = 0;
  let heldOpen = false;
  stub.addEventListener('pointerdown', (e) => {
    downY = e.clientY;
    heldOpen = false;
    clearTimeout(holdTimer);
    if (ui.channel !== 'track' || ui.heldSteps.size) return;
    holdTimer = window.setTimeout(() => { heldOpen = true; openSampleEditor(); }, SAMPLE_HOLD_MS);
  });
  stub.addEventListener('pointermove', (e) => { if (Math.abs(e.clientY - downY) > 10) clearTimeout(holdTimer); });
  stub.addEventListener('pointercancel', () => clearTimeout(holdTimer));
  stub.addEventListener('pointerup', (e) => {
    clearTimeout(holdTimer);
    if (heldOpen) { heldOpen = false; return; }
    if (Math.abs(e.clientY - downY) > 10) return;
    // Зажат шаг — меню выбирает звук этого шага (тоже p-lock).
    const held = ui.channel === 'track' ? [...ui.heldSteps.values()] : [];
    held.forEach((hs) => { hs.used = true; });
    stepTargets = held.map((hs) => hs.index);
    const step = stepTargets.length > 0;
    setClass(stepTitle, 'hidden', !step);
    setText(stepTitle, `STEP ${stepTargets.map((i) => i + 1).join(', ')}`);
    const key = step ? heldStepSound() ?? '' : selTrack().sample;
    const cur = synthEngine(key);
    engineBtns.forEach((b, k) => b.classList.toggle('current', k === cur));
    sampleBtn.classList.toggle('current', cur === null && key !== '');
    setText(midiBtn, step ? 'TRACK' : 'MIDI');
    midiBtn.disabled = !step;
    saveBtn.disabled = step || cur === null;
    loadBtn.disabled = step;
    menu.openRect(menuRect());
  });
  stub.append(waveTitle, wave, synthInfo, stubName);

  // MST как в Ableton: у компрессора вход (белая линия Threshold), снижение громкости (GR) и выход
  // после Makeup; под ними BYPASS и RATIO с числом. У лимитера вход (после Input), GR и выход с белой
  // линией Ceiling, пик-холдом и меткой клиппинга (тот же уровень, что у метра справа);
  // под ними BYPASS и Lookahead числом (это не метр).
  // Полосы обоих устройств одной длины.
  masterPanel = h('div', 'master-panel hidden');
  ratioBtn = h('div', 'btn dev-btn');
  ratioBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); cycleRatio(); });
  lookaheadText = h('div', 'dev-info');
  const groups = h('div', 'vbar-groups');
  const comp = h('div', 'vbar-group');
  const lim = h('div', 'vbar-group');
  compBars.push(vbar('IN', 'meter'), vbar('GR', 'gr'), vbar('OUT', 'meter'));
  limBars.push(vbar('IN', 'meter'), vbar('GR', 'gr'), vbar('OUT', 'meter'));
  cmpBypassBtn = h('div', 'btn dev-btn', 'BYPASS');
  cmpBypassBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleCmpBypass(); });
  const compBtns = h('div', 'dev-btns');
  compBtns.append(cmpBypassBtn, ratioBtn);
  limBypassBtn = h('div', 'btn dev-btn', 'BYPASS');
  limBypassBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleLimBypass(); });
  const limBtns = h('div', 'dev-btns');
  limBtns.append(limBypassBtn, lookaheadText);
  comp.append(h('div', 'vbar-title', 'COMP'), wrap(compBars), compBtns);
  lim.append(h('div', 'vbar-title', 'LIMIT'), wrap(limBars), limBtns);
  groups.append(comp, lim);
  masterPanel.append(groups);

  // MIX: уровень каждой дорожки после громкости микшера — как измеритель справа: жёлтый, стерео —
  // две полосы, моно — одна, выше 0 dB — красный; заглушённая дорожка — серая; снижение
  // громкости от sidechain — оранжевым сверху. Положение регуляторов видно на самих ручках.
  mixPanel = h('div', 'master-panel mix-panel hidden');
  for (let i = 0; i < TRACK_COUNT; i++) mixBars.push(vbar(`T${i + 1}`, 'yellow', true));
  mixPanel.append(h('div', 'vbar-title', 'MIXER'), wrap(mixBars));

  previews = h('div', 'mod-previews hidden');
  for (let k = 0; k < 4; k++) {
    const [el, mini] = buildMini(k < 3);
    minis.push(mini);
    previews.append(el);
  }
  root.append(stub, masterPanel, mixPanel, previews);
  return root;
}

function wrap(list: VBar[]): HTMLElement {
  const el = h('div', 'vbar-row');
  el.append(...list.map((b) => b.root));
  return el;
}

/** Стрелки под окном сэмпла: соседний файл из выбранных. */
export function buildSampleNav(): HTMLElement {
  navRow = h('div', 'sample-nav');
  const prev = h('div', 'btn arrow', '◀');
  const next = h('div', 'btn arrow', '▶');
  navLabel = h('div', 'sample-nav-label');
  // Стрелка: соседний звук папки дорожки; с зажатым шагом — звук этого шага (p-lock).
  const step = (dir: 1 | -1) => {
    const held = ui.channel === 'track' ? [...ui.heldSteps.values()] : [];
    if (held.length) {
      held.forEach((hs) => { hs.used = true; });
      stepFolderOnSteps(ui.selectedTrack, held.map((hs) => hs.index), dir);
    } else stepFolder(ui.selectedTrack, dir);
  };
  prev.addEventListener('pointerdown', (e) => { e.preventDefault(); step(-1); });
  next.addEventListener('pointerdown', (e) => { e.preventDefault(); step(1); });
  navRow.append(prev, navLabel, next);
  return navRow;
}

/** LFO n: значение формы волны с Depth и Invert, −1..+1. */
function lfoValue(n: 1 | 2 | 3, phase: number): number {
  const p = selTrack().params;
  const rnd = RANDOM_STEPS[Math.floor(phase * RANDOM_STEPS.length) % RANDOM_STEPS.length];
  return lfoShape(p[`lfo${n}.wave`], phase, rnd) * (p[`lfo${n}.depth`] / 100) * (1 - 2 * p[`lfo${n}.invert`]);
}

const yBi = (v: number) => (H / 2 - v * (H / 2 - 6)).toFixed(1);
const yUni = (v: number) => (H - 6 - v * (H - 12)).toFixed(1);

function renderLfo(m: Mini, n: 1 | 2 | 3) {
  const p = selTrack().params;
  setText(m.title, `LFO${n} · ${LFO_WAVES[p[`lfo${n}.wave`]]} · ${p[`lfo${n}.speed`].toFixed(2)}Hz`);
  let d = '';
  for (let i = 0; i <= POINTS; i++) {
    const ph = i / POINTS;
    d += `${i ? 'L' : 'M'}${(ph * W).toFixed(1)} ${yBi(lfoValue(n, Math.min(ph, 0.9999)))}`;
  }
  setAttr(m.wave, 'd', d);
  const phase = rt.lfoPhase[ui.selectedTrack][n - 1];
  setAttr(m.dot, 'cx', (phase * W).toFixed(1));
  setAttr(m.dot, 'cy', yBi(lfoValue(n, phase)));
}

/** ENV: форма ADSR с условным гейтом; точка по высоте — текущий уровень огибающей. */
function renderEnv(m: Mini, now: number) {
  const p = selTrack().params;
  const a = p['env.attack'];
  const dcy = p['env.decay'];
  const r = p['env.release'];
  const gate = a + dcy + Math.max(200, (a + dcy + r) * 0.3);
  const total = gate + r;
  setText(m.title, `ENV · A${Math.round(a)} D${Math.round(dcy)} S${Math.round(p['env.sustain'])}% R${Math.round(r)}`);
  let d = '';
  for (let i = 0; i <= POINTS; i++) {
    const t = (i / POINTS) * total;
    d += `${i ? 'L' : 'M'}${((i / POINTS) * W).toFixed(1)} ${yUni(envShape(p, t, gate))}`;
  }
  setAttr(m.wave, 'd', d);
  const e = envAt(ui.selectedTrack, now);
  const level = envOut(ui.selectedTrack, now);
  // Позиция точки: время с запуска, растянутое по реальному гейту в условную шкалу.
  let x = 0;
  if (e.start >= 0) {
    const t = now - e.start;
    const g = e.gateEnd - e.start;
    x = t < g ? Math.min(gate, t) : gate + Math.min(r, t - g);
  }
  setAttr(m.dot, 'cx', ((x / total) * W).toFixed(1));
  setAttr(m.dot, 'cy', yUni(level));
}

function renderWave() {
  // Пока зажат шаг со своим звуком — окно показывает звук шага.
  const tr = selTrack();
  const stepSound = heldStepSound();
  const t = stepSound ? { ...tr, sample: stepSound } : tr;
  const engine = synthEngine(t.sample);
  setClass(waveSvg, 'hidden', engine !== null);
  setClass(synthInfo, 'hidden', engine === null);
  const root = sampleRoot(t.sample);
  // Стерео-сэмпл отмечен ST и рисуется двумя дорожками (L сверху, R снизу), моно — M.
  const ch = t.sample ? (sampleIsStereo(t.sample) ? 'ST' : 'M') : '';
  const preset = stepSound ? '' : folderItemName(ui.selectedTrack);
  setText(waveTitle, engine !== null ? `MI · ${SYNTH_ENGINES[engine].name}${preset ? ` · ${preset}` : ''}`
    : t.sample ? `${sampleName(t.sample)} · ${root !== null ? noteName(root) : '—'} · ${ch}` : sampleName(t.sample));
  // Пока звук не включён — подсказка с состоянием (помогает понять, почему тихо).
  const state = audioState();
  setText(stubName, state === 'running'
    ? `${t.name} · tap to choose sound`
    : `Audio off (${state}) — tap the screen`);
  setClass(stubName, 'warn', state !== 'running');
  if (engine !== null) {
    // Синт: полное имя движка и названия его ручек 1.1–1.3.
    const e = SYNTH_ENGINES[engine];
    setText(synthFull, e.full);
    renderIcon(bigIcon, ui.selectedTrack, performance.now());
    // Только названия ручек 1.1–1.3 этого движка (как подписи ручек, с заглавной буквы).
    [e.harm, e.timbre, e.morph].forEach((what, i) => setText(synthRows[i], what.charAt(0).toUpperCase() + what.slice(1)));
    return;
  }
  const p = samplePeaks(t.sample);
  const key = p ? t.sample : '';
  if (key !== wavePeaksKey) {
    wavePeaksKey = key;
    let d = '';
    if (p) {
      const laneH = WAVE_H / p.length;
      p.forEach((lane, li) => {
        const mid = laneH * (li + 0.5);
        const amp = (laneH / 2) * 0.9;
        lane.forEach((v, i) => {
          const x = ((i + 0.5) / lane.length) * WAVE_W;
          d += `M${x.toFixed(1)} ${(mid - v * amp).toFixed(1)}V${(mid + v * amp).toFixed(1)}`;
        });
      });
    }
    setAttr(wavePath, 'd', d);
  }
  const s = (t.params.start / 100) * WAVE_W;
  const e = Math.max(s, (t.params.end / 100) * WAVE_W);
  setAttr(cutStart, 'width', s.toFixed(1));
  setAttr(cutEnd, 'x', e.toFixed(1));
  setAttr(cutEnd, 'width', (WAVE_W - e).toFixed(1));
}

const pk = (l: Level) => Math.max(l.l, l.r);

function renderMaster(now: number) {
  setText(ratioBtn, `RATIO\n${RATIOS[doc.ratio]}:1`);
  setText(lookaheadText, `LOOKAHEAD\n${limiterLookahead().toFixed(1)} ms`);
  setClass(limBypassBtn, 'active', doc.limBypass);
  setClass(cmpBypassBtn, 'active', doc.cmpBypass);
  const m = masterLevels(now);
  // Метры компрессора и лимитера — одной полосой (наибольший из L и R).
  // Компрессор: вход с линией Threshold, GR (Threshold, Ratio, Attack, Release), выход после Makeup.
  setLevelBar(compBars[0], m.comp, false, fmtDb(pk(m.comp)), dbFrac(liveMaster()['cmp.threshold']));
  // В тишине браузер может отдавать «залипшее» значение reduction — без сигнала GR = 0.
  const silent = (l: Level) => pk(l) < 1e-4;
  setGrBar(compBars[1], doc.cmpBypass || silent(m.comp) ? 0 : Math.min(0, masterReduction()));
  setLevelBar(compBars[2], m.compOut, false, fmtDb(pk(m.compOut)));
  // Лимитер: вход после Input, GR, выход с линией Ceiling, пик-холдом и меткой клиппинга.
  setLevelBar(limBars[0], m.lim, false, fmtDb(pk(m.lim)));
  setGrBar(limBars[1], doc.limBypass || silent(m.lim) ? 0 : Math.min(0, limiterReduction()));
  setLevelBar(limBars[2], m.out, false, fmtDb(pk(m.out)), dbFrac(liveMaster()['lim.ceiling']));
}

function renderMix(now: number) {
  mixBars.forEach((b, i) => {
    const t = doc.tracks[i];
    const lv = trackLevel(i, now);
    setText(b.label, t.name);
    setClass(b.root, 'muted', !audible(i));
    setLevelBar(b, lv, trackIsStereo(i), '', null, trackDuckDb(i));
  });
}

export function renderSample(now: number) {
  const show = now < ui.lfoPreviewUntil || ui.held.mod;
  const panel = show ? 'mod' : ui.channel === 'master' ? 'master' : ui.channel === 'mix' ? 'mix' : 'wave';
  setClass(stub, 'hidden', panel !== 'wave');
  setClass(masterPanel, 'hidden', panel !== 'master');
  setClass(mixPanel, 'hidden', panel !== 'mix');
  setClass(previews, 'hidden', panel !== 'mod');
  if (panel === 'wave') renderWave();
  if (panel === 'master') renderMaster(now);
  if (panel === 'mix') renderMix(now);
  const [pos, total] = folderPos(ui.selectedTrack);
  setText(navLabel, total ? `${pos || '–'} / ${total}` : 'folder');
  setClass(navRow, 'disabled', total < 1);
  // У MIX и MST сэмплов нет — стрелки скрыты.
  setClass(navRow, 'hidden', ui.channel !== 'track');
  if (!show) return;
  renderLfo(minis[0], 1);
  renderLfo(minis[1], 2);
  renderLfo(minis[2], 3);
  renderEnv(minis[3], now);
}
