// Окно сэмпла: имя и форма волны сэмпла выбранной дорожки, Start/End затемняют отрезанное.
// Тап — выбор аудиофайла с iPad (WAV/MP3/M4A…), он заменяет сэмпл дорожки.
// Пока меняются параметры модуляции (MOD) — здесь сразу видны миниатюры LFO1, LFO2, LFO3
// (форма волны с Wave, Depth и Invert, бегущая точка фазы) и огибающей ENV (форма ADSR).
// При выбранном мастере (MST) — кнопка RATIO компрессора и индикатор его работы.

import { loadSampleFile, masterReduction, samplePeaks } from '../audio/engine';
import { LFO_WAVES, RATIOS } from '../params';
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
let grBar: HTMLElement;
let grText: HTMLElement;
let mixPanel: HTMLElement;
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
  input.accept = 'audio/*';
  input.addEventListener('change', () => {
    const f = input.files?.[0];
    if (f) void loadSampleFile(f).catch(() => window.alert('Не удалось открыть файл как аудио'));
    input.value = '';
  });
  stub.append(waveTitle, wave, stubName, input);

  masterPanel = h('div', 'master-panel hidden');
  ratioBtn = h('div', 'btn ratio-btn');
  ratioBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); cycleRatio(); });
  const gr = h('div', 'gr-meter');
  grBar = h('div', 'gr-bar');
  gr.append(grBar);
  grText = h('div', 'sample-name');
  masterPanel.append(h('div', 'sample-title', 'MASTER'), ratioBtn, h('div', 'sample-name', 'Gain reduction'), gr, grText);

  mixPanel = h('div', 'master-panel hidden');
  mixPanel.append(h('div', 'sample-title', 'MIXER'), h('div', 'sample-name', 'Громкости дорожек'));

  previews = h('div', 'mod-previews hidden');
  for (let k = 0; k < 4; k++) {
    const [el, mini] = buildMini(k < 3);
    minis.push(mini);
    previews.append(el);
  }
  root.append(stub, masterPanel, mixPanel, previews);
  return root;
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
  setText(waveTitle, sampleName(t.sample));
  setText(stubName, `${t.name} · тап — загрузить файл`);
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

function renderMaster() {
  setText(ratioBtn, `RATIO ${RATIOS[doc.ratio]}:1`);
  const gr = Math.min(0, masterReduction());
  setAttr(grBar, 'style', `width:${Math.min(100, (-gr / 24) * 100).toFixed(0)}%`);
  setText(grText, `${gr.toFixed(1)} dB`);
}

export function renderSample(now: number) {
  const show = now < ui.lfoPreviewUntil || ui.held.mod;
  const panel = show ? 'mod' : ui.channel === 'master' ? 'master' : ui.channel === 'mix' ? 'mix' : 'wave';
  setClass(stub, 'hidden', panel !== 'wave');
  setClass(masterPanel, 'hidden', panel !== 'master');
  setClass(mixPanel, 'hidden', panel !== 'mix');
  setClass(previews, 'hidden', panel !== 'mod');
  if (panel === 'wave') renderWave();
  if (panel === 'master') renderMaster();
  if (!show) return;
  renderLfo(minis[0], 1);
  renderLfo(minis[1], 2);
  renderLfo(minis[2], 3);
  renderEnv(minis[3], now);
}
