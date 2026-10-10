// Окно сэмпла (пока заглушка). Пока меняются параметры модуляции (MOD) — здесь сразу видны
// миниатюры LFO1, LFO2, LFO3 (форма волны с Wave, Depth и Invert, бегущая точка фазы)
// и огибающей ENV (форма ADSR, точка — текущий уровень).

import { LFO_WAVES } from '../params';
import { envOut, envShape, lfoShape, rt, selTrack, ui } from '../state';
import { h, setAttr, setClass, setText, svg } from './dom';

const W = 200;
const H = 80;
const POINTS = 100;
/** Фиксированный «случайный» рисунок для формы Random. */
const RANDOM_STEPS = [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.75, -0.1];

interface Mini { title: HTMLElement; wave: SVGPathElement; dot: SVGCircleElement }
let stub: HTMLElement;
let stubName: HTMLElement;
let previews: HTMLElement;
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
  stub.append(h('div', 'sample-title', 'SAMPLE'), stubName);

  previews = h('div', 'mod-previews hidden');
  for (let k = 0; k < 4; k++) {
    const [el, mini] = buildMini(k < 3);
    minis.push(mini);
    previews.append(el);
  }
  root.append(stub, previews);
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

export function renderSample(now: number) {
  const show = now < ui.lfoPreviewUntil || ui.held.mod;
  setClass(stub, 'hidden', show);
  setClass(previews, 'hidden', !show);
  setText(stubName, `${selTrack().name} — пусто`);
  if (!show) return;
  renderLfo(minis[0], 1);
  renderLfo(minis[1], 2);
  renderLfo(minis[2], 3);
  renderEnv(minis[3], now);
}
