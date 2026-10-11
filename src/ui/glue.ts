// Индикация компрессора мастера «glue» (окно сэмпла при MST, группа COMP слева от лимитера):
// три столбца IN | GR | OUT по 24 сегмента (холст, 60 fps — в общем кадре), под ними BYPASS и RATIO.
// Подъём мгновенный, спад 20 dB/s, пиковая метка 1.5 с тонкой линией того же цвета; неактивные
// сегменты тусклые. IN: −42…0 dB, белая риска порога. GR: 0…−18 dB сверху вниз, оранжевый, рядом
// число — пик GR за 1.5 с; больше 18 dB — нижний сегмент мигает. OUT: −42…+3 dB, над ним индикатор
// клипа (выход выше 0 dBFS) — держится до тапа. В bypass столбцы серые, GR на нуле.
// Цвета — из темы: жёлтый ниже −6 dB, оранжевый от −6 до 0, красный выше 0.

import { glueMeter } from '../audio/engine';
import { RATIOS } from '../params';
import { cycleRatio, doc, liveMaster, toggleCmpBypass } from '../state';
import { h, setClass, setText } from './dom';
import { color } from './theme';

const SEGMENTS = 24;
const FALL_DB_S = 20;
const HOLD_MS = 1500;
const DIM_ALPHA = 0.15;
const IN_RANGE: [number, number] = [-42, 0];
const OUT_RANGE: [number, number] = [-42, 3];
const GR_MAX = 18;
/** Промежуток между столбцами, px (столько же — между BYPASS и RATIO). */
const GAP = 4;
/** Данные worklet старше этого — тишина (звук остановлен). */
const STALE_MS = 150;

interface Ballistic { disp: number; hold: number; holdAt: number }
const ball = (): Ballistic => ({ disp: -120, hold: -120, holdAt: 0 });
const bIn = ball();
const bOut = ball();
/** GR в dB (≥ 0): отображение и пик за 1.5 с. */
const bGr = { disp: 0, hold: 0, holdAt: 0 };

let canvas: HTMLCanvasElement;
let grText: HTMLElement;
let clipEl: HTMLElement;
let bypassBtn: HTMLElement;
let ratioBtn: HTMLElement;
let clipped = false;
let last = 0;

const toDb = (x: number) => 20 * Math.log10(Math.max(x, 1e-6));

/** Столбец уровня: мгновенный подъём, спад 20 dB/s, пиковая метка 1.5 с. */
function step(b: Ballistic, db: number, dt: number, now: number) {
  b.disp = Math.max(db, b.disp - FALL_DB_S * dt);
  if (db >= b.hold || now - b.holdAt > HOLD_MS) { b.hold = Math.max(db, b.disp); b.holdAt = now; }
}

export function buildGlue(): HTMLElement {
  const el = h('div', 'vbar-group glue');
  // Над столбцами: пусто | пик GR числом | индикатор клипа OUT.
  const top = h('div', 'glue-row glue-top');
  grText = h('div', 'glue-gr-text');
  clipEl = h('div', 'glue-clip');
  clipEl.addEventListener('pointerdown', (e) => { e.preventDefault(); clipped = false; });
  top.append(h('div'), grText, clipEl);
  canvas = h('canvas', 'glue-canvas');
  const labels = h('div', 'glue-row glue-labels');
  labels.append(h('div', '', 'IN'), h('div', '', 'GR'), h('div', '', 'OUT'));
  // BYPASS и RATIO: вместе по ширине трёх столбцов, зазор — как между столбцами.
  const btns = h('div', 'glue-btns');
  bypassBtn = h('div', 'btn dev-btn', 'BYPASS');
  bypassBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleCmpBypass(); });
  ratioBtn = h('div', 'btn dev-btn glue-ratio');
  ratioBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); cycleRatio(); });
  btns.append(bypassBtn, ratioBtn);
  el.style.setProperty('--glue-gap', `${GAP}px`);
  el.append(h('div', 'vbar-title', 'COMP'), top, canvas, labels, btns);
  return el;
}

export function renderGlue(now: number) {
  const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
  last = now;
  const m = glueMeter();
  const live = now - m.at < STALE_MS;
  const bypass = doc.cmpBypass;
  step(bIn, live ? toDb(m.in) : -120, dt, now);
  step(bOut, live ? toDb(m.out) : -120, dt, now);
  const gr = live && !bypass ? m.gr : 0;
  bGr.disp = Math.max(gr, bGr.disp - FALL_DB_S * dt);
  if (gr >= bGr.hold || now - bGr.holdAt > HOLD_MS) { bGr.hold = Math.max(gr, bGr.disp); bGr.holdAt = now; }
  if (live && m.out > 1) clipped = true;

  setText(ratioBtn, `${RATIOS[doc.ratio]}:1`);
  setClass(bypassBtn, 'active', bypass);
  setText(grText, bGr.hold > 0.05 ? `-${bGr.hold.toFixed(1)} dB` : '0.0 dB');
  setClass(clipEl, 'on', clipped);
  draw(now, bypass);
}

function draw(now: number, bypass: boolean) {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.round(canvas.clientWidth * dpr);
  const hh = Math.round(canvas.clientHeight * dpr);
  if (!w || !hh) return;
  if (canvas.width !== w || canvas.height !== hh) { canvas.width = w; canvas.height = hh; }
  const g = canvas.getContext('2d')!;
  g.clearRect(0, 0, w, hh);
  const gap = GAP * dpr;
  const colW = (w - 2 * gap) / 3;
  const segGap = Math.max(1, Math.round(dpr));
  const segH = (hh - (SEGMENTS - 1) * segGap) / SEGMENTS;
  const yellow = color('--plock');
  const orange = color('--gr');
  const red = color('--rec');
  const grey = color('--mute-grey');
  const ink = color('--ink');
  const levelColor = (db: number) => (bypass ? grey : db > 0 ? red : db >= -6 ? orange : yellow);
  // Сегмент k (0 — нижний) — его прямоугольник.
  const segY = (k: number) => hh - (k + 1) * segH - k * segGap;

  const level = (col: number, [lo, hi]: [number, number], b: Ballistic) => {
    const x = col * (colW + gap);
    const per = (hi - lo) / SEGMENTS;
    for (let k = 0; k < SEGMENTS; k++) {
      const bottom = lo + k * per;
      g.globalAlpha = b.disp > bottom ? 1 : DIM_ALPHA;
      g.fillStyle = levelColor(bottom + per / 2);
      g.fillRect(x, segY(k), colW, segH);
    }
    g.globalAlpha = 1;
    // Пиковая метка — тонкая линия цвета своего сегмента.
    if (b.hold > lo) {
      const f = Math.min(1, (b.hold - lo) / (hi - lo));
      g.fillStyle = levelColor(b.hold);
      g.fillRect(x, hh - f * hh - dpr, colW, Math.max(1, 1.5 * dpr));
    }
  };
  level(0, IN_RANGE, bIn);
  level(2, OUT_RANGE, bOut);
  // Риска порога на IN.
  const thr = liveMaster()['cmp.threshold'];
  const tf = (thr - IN_RANGE[0]) / (IN_RANGE[1] - IN_RANGE[0]);
  g.fillStyle = ink;
  g.fillRect(0, hh - tf * hh - dpr, colW, Math.max(1, 1.5 * dpr));

  // GR: сверху вниз от нулевой линии.
  const x = colW + gap;
  const per = GR_MAX / SEGMENTS;
  const blink = Math.floor(now / 250) % 2 === 0;
  for (let k = 0; k < SEGMENTS; k++) {
    const y = k * (segH + segGap);
    let lit = bGr.disp > k * per;
    // Сжатие больше 18 dB — нижний сегмент мигает.
    if (k === SEGMENTS - 1 && bGr.disp > GR_MAX) lit = blink;
    g.globalAlpha = lit ? 1 : DIM_ALPHA;
    g.fillStyle = bypass ? grey : orange;
    g.fillRect(x, y, colW, segH);
  }
  g.globalAlpha = 1;
  if (bGr.hold > 0.05 && !bypass) {
    const f = Math.min(1, bGr.hold / GR_MAX);
    g.fillStyle = orange;
    g.fillRect(x, f * hh - dpr, colW, Math.max(1, 1.5 * dpr));
  }
}
