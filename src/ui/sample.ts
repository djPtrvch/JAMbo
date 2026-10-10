// Окно сэмпла (пока заглушка). Пока меняются параметры LFO (MOD) — здесь видна форма волны
// с учётом Wave, Depth и Invert и бегущая точка текущей фазы.

import { LFO_WAVES } from '../params';
import { lfoShape, rt, selTrack, ui } from '../state';
import { h, setAttr, setClass, setText, svg } from './dom';

const W = 200;
const H = 100;
const POINTS = 120;

let root: HTMLElement;
let stub: HTMLElement;
let stubName: HTMLElement;
let preview: HTMLElement;
let title: HTMLElement;
let wave: SVGPathElement;
let dot: SVGCircleElement;
/** Фиксированный «случайный» рисунок для формы Random. */
const RANDOM_STEPS = [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.75, -0.1];

export function buildSample(): HTMLElement {
  root = h('div', 'sample');
  stub = h('div', 'sample-stub');
  stubName = h('div', 'sample-name');
  stub.append(h('div', 'sample-title', 'SAMPLE'), stubName);

  preview = h('div', 'lfo-preview hidden');
  title = h('div', 'lfo-title');
  const box = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'lfo-svg' });
  box.append(svg('line', { x1: 0, y1: H / 2, x2: W, y2: H / 2, class: 'lfo-axis' }));
  wave = svg('path', { class: 'lfo-wave' });
  dot = svg('circle', { r: 4, class: 'lfo-dot' });
  box.append(wave, dot);
  preview.append(title, box);

  root.append(stub, preview);
  return root;
}

/** Значение формы волны с Depth и Invert, −1..+1. */
function value(n: 1 | 2, phase: number): number {
  const p = selTrack().params;
  const w = p[`lfo${n}.wave`];
  const rnd = RANDOM_STEPS[Math.floor(phase * RANDOM_STEPS.length) % RANDOM_STEPS.length];
  return lfoShape(w, phase, rnd) * (p[`lfo${n}.depth`] / 100) * (1 - 2 * p[`lfo${n}.invert`]);
}

const y = (v: number) => (H / 2 - v * (H / 2 - 6)).toFixed(1);

export function renderSample(now: number) {
  const show = now < ui.lfoPreviewUntil || ui.held.mod;
  setClass(stub, 'hidden', show);
  setClass(preview, 'hidden', !show);
  setText(stubName, `${selTrack().name} — пусто`);
  if (!show) return;

  const n = ui.lfoPreview;
  const p = selTrack().params;
  setText(title, `LFO${n} · ${LFO_WAVES[p[`lfo${n}.wave`]]} · ${p[`lfo${n}.speed`].toFixed(2)}Hz`);
  let d = '';
  for (let i = 0; i <= POINTS; i++) {
    const ph = i / POINTS;
    const v = value(n, Math.min(ph, 0.9999));
    d += `${i ? 'L' : 'M'}${(ph * W).toFixed(1)} ${y(v)}`;
  }
  setAttr(wave, 'd', d);
  const phase = rt.lfoPhase[ui.selectedTrack][n - 1];
  setAttr(dot, 'cx', (phase * W).toFixed(1));
  setAttr(dot, 'cy', y(value(n, phase)));
}
