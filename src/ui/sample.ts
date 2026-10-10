// Окно сэмпла: имя, определённая высота и форма волны сэмпла выбранной дорожки, Start/End
// затемняют отрезанное. Тап — выбор аудиофайлов с iPad (можно сразу несколько — это «папка»):
// первый заменяет сэмпл дорожки, стрелки под окном перелистывают остальные.
// MIX — уровень каждой дорожки (как измеритель справа). MST — как в Ableton: у компрессора и
// лимитера вход с меткой порога, снижение громкости и выход, под ними BYPASS (и RATIO у компрессора).
// Пока меняются параметры модуляции (MOD) — здесь сразу видны миниатюры LFO1, LFO2, LFO3
// (форма волны с Wave, Depth и Invert, бегущая точка фазы) и огибающей ENV (форма ADSR).

import {
  audioState, limiterReduction, trackIsStereo, loadSampleFiles, masterLevels, masterReduction, sampleListPos, samplePeaks,
  sampleRoot, stepSample, trackLevel,
} from '../audio/engine';
import { LFO_WAVES, RATIOS, TRACK_COUNT, noteName } from '../params';
import { fmtDb, levelFrac } from './meter';
import { cycleRatio, doc, toggleBypass, envOut, envShape, lfoShape, rt, sampleName, selTrack, ui } from '../state';
import { h, setAttr, setClass, setText, svg } from './dom';

const W = 200;
const H = 80;
const POINTS = 100;
/** Фиксированный «случайный» рисунок для формы Random. */
const RANDOM_STEPS = [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.75, -0.1];

interface Mini { title: HTMLElement; wave: SVGPathElement; dot: SVGCircleElement }
let stub: HTMLElement;
let stubName: HTMLElement;
let waveTitle: HTMLElement;
let wavePath: SVGPathElement;
let cutStart: SVGRectElement;
let cutEnd: SVGRectElement;
let wavePeaksKey = '';
let previews: HTMLElement;
let masterPanel: HTMLElement;
let ratioBtn: HTMLElement;
let cmpBypassBtn: HTMLElement;
let limBypassBtn: HTMLElement;
let mixPanel: HTMLElement;
let navLabel: HTMLElement;
let navRow: HTMLElement;

/**
 * Вертикальная полоса уровня (1 или 2 канала) с меткой, числом и подписью.
 * kind: 'yellow' — жёлтая (микшер, как измеритель справа); 'meter' — как в Ableton:
 * градиент зелёный → жёлтый → красный со шкалой; 'gr' — снижение громкости, оранжевая сверху.
 */
type BarKind = 'yellow' | 'meter' | 'gr';
interface VBar { root: HTMLElement; chans: HTMLElement[]; fills: HTMLElement[]; mark: HTMLElement; value: HTMLElement; label: HTMLElement; kind: BarKind }
const mixBars: VBar[] = [];
const compBars: VBar[] = [];
const limBars: VBar[] = [];

/** Отметки шкалы в dB (как сетка на измерителях Ableton). */
const TICKS = [-6, -12, -24, -48];

function vbar(label: string, kind: BarKind): VBar {
  const root = h('div', 'vbar-col');
  const box = h('div', 'vbar-box');
  const chans: HTMLElement[] = [];
  const fills: HTMLElement[] = [];
  for (let ch = 0; ch < (kind === 'gr' ? 1 : 2); ch++) {
    const bar = h('div', `vbar ${kind}`);
    const fill = h('div', 'vbar-fill');
    bar.append(fill);
    chans.push(bar);
    fills.push(fill);
    box.append(bar);
  }
  if (kind === 'meter') {
    for (const db of TICKS) {
      const t = h('div', 'vbar-tick');
      t.style.bottom = `${(dbFrac(db) * 100).toFixed(1)}%`;
      box.append(t);
    }
  }
  const mark = h('div', 'vbar-mark hidden');
  box.append(mark);
  const value = h('div', 'vbar-val');
  const lab = h('div', 'vbar-label', label);
  root.append(box, value, lab);
  return { root, chans, fills, mark, value, label: lab, kind };
}

/**
 * Обновить полосу: доли по каналам (0..1; для 'gr' — доля снижения сверху),
 * stereo — показывать ли второй канал, mark — метка (порог), text — число под полосой.
 */
function setBar(b: VBar, fracs: number[], stereo: boolean, text: string, mark: number | null = null, clip = false) {
  b.chans.forEach((c, i) => setClass(c, 'hidden', i > 0 && !stereo));
  b.fills.forEach((f, i) => {
    const v = Math.min(1, Math.max(0, fracs[Math.min(i, fracs.length - 1)]));
    // У градиентной полосы закрывается незаполненная часть сверху, у остальных растёт заливка.
    setAttr(f, 'style', `height:${((b.kind === 'meter' ? 1 - v : v) * 100).toFixed(1)}%`);
    setClass(f, 'clip', clip);
  });
  setClass(b.mark, 'hidden', mark === null);
  if (mark !== null) setAttr(b.mark, 'style', `bottom:${(Math.min(1, Math.max(0, mark)) * 100).toFixed(1)}%`);
  setText(b.value, text);
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
  wavePath = svg('path', { class: 'sample-wave-path' });
  cutStart = svg('rect', { x: 0, y: 0, height: WAVE_H, class: 'sample-cut' });
  cutEnd = svg('rect', { y: 0, height: WAVE_H, class: 'sample-cut' });
  wave.append(wavePath, cutStart, cutEnd);
  // Настоящее поле выбора файла поверх окна: системный выбор файла открывается по тапу.
  const input = h('input', 'sample-file');
  input.type = 'file';
  input.multiple = true;
  // Явные расширения: на iOS один 'audio/*' иногда не даёт выбрать файл в «Файлах».
  input.accept = 'audio/*,.wav,.wave,.aif,.aiff,.mp3,.m4a,.aac,.caf,.flac,.ogg';
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? []);
    if (files.length) void loadSampleFiles(files).catch(() => window.alert('Не удалось открыть файл как аудио'));
    input.value = '';
  });
  stub.append(waveTitle, wave, stubName, input);

  // MST как в Ableton: у каждого устройства вход (с меткой порога), снижение громкости, выход;
  // полосы одной длины, под ними кнопки: у компрессора BYPASS и RATIO, у лимитера BYPASS.
  masterPanel = h('div', 'master-panel hidden');
  const tapBtn = (cls: string, fn: () => void) => {
    const el = h('div', `btn ${cls}`);
    el.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return el;
  };
  ratioBtn = tapBtn('dev-btn', cycleRatio);
  cmpBypassBtn = tapBtn('dev-btn', () => toggleBypass('cmp'));
  limBypassBtn = tapBtn('dev-btn', () => toggleBypass('lim'));
  setText(cmpBypassBtn, 'BYPASS');
  setText(limBypassBtn, 'BYPASS');
  const groups = h('div', 'vbar-groups');
  const comp = h('div', 'vbar-group');
  const lim = h('div', 'vbar-group');
  compBars.push(vbar('IN', 'meter'), vbar('GR', 'gr'), vbar('OUT', 'meter'));
  limBars.push(vbar('IN', 'meter'), vbar('GR', 'gr'), vbar('OUT', 'meter'));
  const compBtns = h('div', 'dev-btns');
  compBtns.append(cmpBypassBtn, ratioBtn);
  const limBtns = h('div', 'dev-btns');
  limBtns.append(limBypassBtn);
  comp.append(h('div', 'vbar-title', 'COMP'), wrap(compBars), compBtns);
  lim.append(h('div', 'vbar-title', 'LIMIT'), wrap(limBars), limBtns);
  groups.append(comp, lim);
  masterPanel.append(groups);

  // MIX: уровень каждой дорожки после громкости микшера — как измеритель справа
  // (жёлтый, стерео — две полосы, моно — одна, перегрузка — красная).
  mixPanel = h('div', 'master-panel hidden');
  for (let i = 0; i < TRACK_COUNT; i++) mixBars.push(vbar(`T${i + 1}`, 'yellow'));
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
  prev.addEventListener('pointerdown', (e) => { e.preventDefault(); void stepSample(-1); });
  next.addEventListener('pointerdown', (e) => { e.preventDefault(); void stepSample(1); });
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
  const e = rt.env[ui.selectedTrack];
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
  const t = selTrack();
  const root = sampleRoot(t.sample);
  setText(waveTitle, t.sample ? `${sampleName(t.sample)} · ${root !== null ? noteName(root) : '—'}` : sampleName(t.sample));
  // Пока звук не включён — подсказка с состоянием (помогает понять, почему тихо).
  const state = audioState();
  setText(stubName, state === 'running'
    ? `${t.name} · тап — ${t.sample ? 'заменить' : 'загрузить'} файл`
    : `Звук выключен (${state}) — коснитесь экрана`);
  setClass(stubName, 'warn', state !== 'running');
  const p = samplePeaks(t.sample);
  const key = p ? t.sample : '';
  if (key !== wavePeaksKey) {
    wavePeaksKey = key;
    let d = '';
    if (p) {
      const mid = WAVE_H / 2;
      p.forEach((v, i) => {
        const x = ((i + 0.5) / p.length) * WAVE_W;
        d += `M${x.toFixed(1)} ${(mid - v * mid * 0.9).toFixed(1)}V${(mid + v * mid * 0.9).toFixed(1)}`;
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

const pk = (l: { l: number; r: number }) => Math.max(l.l, l.r);
const lvFracs = (l: { l: number; r: number }) => [levelFrac(l.l), levelFrac(l.r)];

function renderMaster(now: number) {
  setText(ratioBtn, `RATIO\n${RATIOS[doc.ratio]}:1`);
  setClass(cmpBypassBtn, 'active', doc.bypass.cmp);
  setClass(limBypassBtn, 'active', doc.bypass.lim);
  const m = masterLevels(now);
  const cgr = doc.bypass.cmp ? 0 : Math.min(0, masterReduction());
  const lgr = doc.bypass.lim ? 0 : Math.min(0, limiterReduction());
  // Компрессор: вход с меткой Threshold, снижение громкости, выход после Makeup.
  setBar(compBars[0], lvFracs(m.comp), true, fmtDb(pk(m.comp)), dbFrac(doc.master['cmp.threshold']), m.comp.clip);
  setBar(compBars[1], [-cgr / 24], false, cgr.toFixed(1));
  setBar(compBars[2], lvFracs(m.compOut), true, fmtDb(pk(m.compOut)), null, m.compOut.clip);
  // Лимитер: вход с меткой Ceiling, снижение громкости, выход.
  setBar(limBars[0], lvFracs(m.lim), true, fmtDb(pk(m.lim)), dbFrac(doc.master['lim.ceiling']), m.lim.clip);
  setBar(limBars[1], [-lgr / 24], false, lgr.toFixed(1));
  setBar(limBars[2], lvFracs(m.out), true, fmtDb(pk(m.out)), null, m.out.clip);
}

function renderMix(now: number) {
  mixBars.forEach((b, i) => {
    const lv = trackLevel(i, now);
    const stereo = trackIsStereo(i);
    setText(b.label, doc.tracks[i].name);
    setBar(b, stereo ? lvFracs(lv) : [levelFrac(pk(lv))], stereo, fmtDb(pk(lv)), null, lv.clip);
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
  const [pos, total] = sampleListPos();
  setText(navLabel, total ? `${pos} / ${total}` : 'файлы');
  setClass(navRow, 'disabled', total < 2);
  // У MIX и MST сэмплов нет — стрелки скрыты.
  setClass(navRow, 'hidden', ui.channel !== 'track');
  if (!show) return;
  renderLfo(minis[0], 1);
  renderLfo(minis[1], 2);
  renderLfo(minis[2], 3);
  renderEnv(minis[3], now);
}
