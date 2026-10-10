// Окно сэмпла: имя, определённая высота и форма волны сэмпла выбранной дорожки, Start/End
// затемняют отрезанное. Тап — выбор аудиофайлов с iPad (можно сразу несколько — это «папка»):
// первый заменяет сэмпл дорожки, стрелки под окном перелистывают остальные.
// MIX — жёлтые полосы уровня каждой дорожки. MST — по три полосы компрессора (Threshold,
// Gain reduction, Makeup) и лимитера (Ceiling, снижение громкости, выход) и кнопка RATIO.
// Пока меняются параметры модуляции (MOD) — здесь сразу видны миниатюры LFO1, LFO2, LFO3
// (форма волны с Wave, Depth и Invert, бегущая точка фазы) и огибающей ENV (форма ADSR).

import {
  audioState, limiterReduction, loadSampleFiles, masterLevels, masterReduction, sampleListPos, samplePeaks,
  sampleRoot, stepSample, trackLevel,
} from '../audio/engine';
import { LFO_WAVES, RATIOS, TRACK_COUNT, noteName } from '../params';
import { levelFrac } from './meter';
import { cycleRatio, doc, envOut, envShape, lfoShape, rt, sampleName, selTrack, ui } from '../state';
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
let mixPanel: HTMLElement;
let navLabel: HTMLElement;
let navRow: HTMLElement;

/** Вертикальная полоса: заливка, метка уровня (линия) и подпись. */
interface VBar { root: HTMLElement; fill: HTMLElement; mark: HTMLElement; label: HTMLElement }
const mixBars: VBar[] = [];
const compBars: VBar[] = [];
const limBars: VBar[] = [];

function vbar(label: string, down = false): VBar {
  const root = h('div', 'vbar-col');
  const bar = h('div', 'vbar');
  const fill = h('div', down ? 'vbar-fill down' : 'vbar-fill');
  const mark = h('div', 'vbar-mark hidden');
  bar.append(fill, mark);
  const lab = h('div', 'vbar-label', label);
  root.append(bar, lab);
  return { root, fill, mark, label: lab };
}

function setBar(b: VBar, frac: number, mark: number | null = null) {
  setAttr(b.fill, 'style', `height:${(Math.min(1, Math.max(0, frac)) * 100).toFixed(1)}%`);
  setClass(b.mark, 'hidden', mark === null);
  if (mark !== null) setAttr(b.mark, 'style', `bottom:${(Math.min(1, Math.max(0, mark)) * 100).toFixed(1)}%`);
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

  masterPanel = h('div', 'master-panel hidden');
  ratioBtn = h('div', 'btn ratio-btn');
  ratioBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); cycleRatio(); });
  const groups = h('div', 'vbar-groups');
  const comp = h('div', 'vbar-group');
  const lim = h('div', 'vbar-group');
  compBars.push(vbar('THR'), vbar('GR', true), vbar('MKP'));
  limBars.push(vbar('CEIL'), vbar('GR', true), vbar('OUT'));
  comp.append(h('div', 'vbar-title', 'COMP'), wrap(compBars));
  lim.append(h('div', 'vbar-title', 'LIMIT'), wrap(limBars));
  groups.append(comp, lim);
  masterPanel.append(groups, ratioBtn);

  mixPanel = h('div', 'master-panel hidden');
  for (let i = 0; i < TRACK_COUNT; i++) mixBars.push(vbar(`T${i + 1}`));
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

function renderMaster(now: number) {
  setText(ratioBtn, `RATIO ${RATIOS[doc.ratio]}:1`);
  const m = masterLevels(now);
  const peakDb = (l: { l: number; r: number }) => { const p = Math.max(l.l, l.r); return p > 0 ? 20 * Math.log10(p) : -100; };
  // Компрессор: уровень входа с меткой Threshold, понижение усиления, Makeup.
  setBar(compBars[0], dbFrac(peakDb(m.comp)), dbFrac(doc.master['cmp.threshold']));
  setBar(compBars[1], -Math.min(0, masterReduction()) / 24);
  setBar(compBars[2], doc.master['cmp.makeup'] / 24);
  // Лимитер: уровень входа с меткой Ceiling, снижение громкости, выход.
  setBar(limBars[0], dbFrac(peakDb(m.lim)), dbFrac(doc.master['lim.ceiling']));
  setBar(limBars[1], -Math.min(0, limiterReduction()) / 24);
  setBar(limBars[2], dbFrac(peakDb(m.out)));
}

function renderMix(now: number) {
  mixBars.forEach((b, i) => {
    const lv = trackLevel(i, now);
    setText(b.label, doc.tracks[i].name);
    setBar(b, levelFrac(Math.max(lv.l, lv.r)));
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
  if (!show) return;
  renderLfo(minis[0], 1);
  renderLfo(minis[1], 2);
  renderLfo(minis[2], 3);
  renderEnv(minis[3], now);
}
