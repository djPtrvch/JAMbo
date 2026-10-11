// Боковая панель мастера (при MST — вся левая колонка): блоки COMP | CLIP | LIM в порядке цепочки —
// один компонент сегментных столбцов IN | GR | OUT для всех трёх: одинаковые размеры, зазоры,
// 24 сегмента, цвета, тусклые сегменты, баллистика, peak hold, шрифты и кнопки. Различаются только
// параметры: шкалы, белые риски (порог компрессора, CEILING клиппера и лимитера), условие клипа и кнопки.
// Подъём мгновенный, спад 20 dB/s, пиковая метка 1.5 с тонкой линией того же цвета; неактивные
// сегменты серые. GR растёт сверху вниз, оранжевый; рядом число — пик GR за 1.5 с; за краем шкалы
// нижний сегмент мигает. Над OUT индикатор клипа — держится до тапа. В bypass столбцы серые, GR ноль.
// Кнопки RATIO и BYPASS — на месте LFO1–3/ENV под окном (buttons.ts). Неактивные сегменты — серые.
// Цвета — из темы: жёлтый ниже −6 dB, оранжевый от −6 до 0, красный выше 0. Холст рисуется в общем кадре.

import { clipperMeter, glueMeter, limiterMeter, type DynLevels } from '../audio/engine';
import { doc, liveMaster } from '../state';
import { h, setClass, setText } from './dom';
import { color } from './theme';

const SEGMENTS = 24;
const FALL_DB_S = 20;
const HOLD_MS = 1500;
/** Промежуток между столбцами, px (столько же — между кнопками). */
const GAP = 4;
/** Данные worklet старше этого — тишина (звук остановлен). */
const STALE_MS = 150;

type Range = [number, number];
interface Ballistic { disp: number; hold: number; holdAt: number }
const ball = (): Ballistic => ({ disp: -120, hold: -120, holdAt: 0 });
const toDb = (x: number) => 20 * Math.log10(Math.max(x, 1e-6));

/** Столбец уровня: мгновенный подъём, спад 20 dB/s, пиковая метка 1.5 с. */
function step(b: Ballistic, v: number, dt: number, now: number) {
  b.disp = Math.max(v, b.disp - FALL_DB_S * dt);
  if (v >= b.hold || now - b.holdAt > HOLD_MS) { b.hold = Math.max(v, b.disp); b.holdAt = now; }
}

interface DynOptions {
  title: string;
  meter: () => DynLevels;
  bypass: () => boolean;
  inRange: Range;
  outRange: Range;
  grMax: number;
  /** Белые риски на IN и OUT (dB) или null. */
  inMark: () => number | null;
  outMark: () => number | null;
  /** Выход перешёл границу клипа (линейный пик выхода). */
  clips: (outPeak: number) => boolean;
}

class DynView {
  el: HTMLElement;
  private canvas: HTMLCanvasElement;
  private grText: HTMLElement;
  private clipEl: HTMLElement;
  private bIn = ball();
  private bOut = ball();
  private bGr = { disp: 0, hold: 0, holdAt: 0 };
  private clipped = false;
  private last = 0;

  constructor(private o: DynOptions) {
    this.el = h('div', 'vbar-group glue');
    // Над столбцами: пик GR числом (над IN и GR, по правому краю GR) | индикатор клипа над OUT.
    const top = h('div', 'glue-row glue-top');
    this.grText = h('div', 'glue-gr-text');
    this.clipEl = h('div', 'glue-clip');
    this.clipEl.addEventListener('pointerdown', (e) => { e.preventDefault(); this.clipped = false; });
    top.append(this.grText, this.clipEl);
    this.canvas = h('canvas', 'glue-canvas');
    const labels = h('div', 'glue-row glue-labels');
    labels.append(h('div', '', 'IN'), h('div', '', 'GR'), h('div', '', 'OUT'));
    this.el.style.setProperty('--glue-gap', `${GAP}px`);
    this.el.append(h('div', 'vbar-title', o.title), top, this.canvas, labels);
  }

  render(now: number) {
    const o = this.o;
    const dt = this.last ? Math.min(0.1, (now - this.last) / 1000) : 0;
    this.last = now;
    const m = o.meter();
    const live = now - m.at < STALE_MS;
    const bypass = o.bypass();
    step(this.bIn, live ? toDb(m.in) : -120, dt, now);
    step(this.bOut, live ? toDb(m.out) : -120, dt, now);
    const gr = live && !bypass ? m.gr : 0;
    const g = this.bGr;
    g.disp = Math.max(gr, g.disp - FALL_DB_S * dt);
    if (gr >= g.hold || now - g.holdAt > HOLD_MS) { g.hold = Math.max(gr, g.disp); g.holdAt = now; }
    if (live && !bypass && o.clips(m.out)) this.clipped = true;
    setText(this.grText, g.hold > 0.05 ? `-${g.hold.toFixed(1)} dB` : '0.0 dB');
    setClass(this.clipEl, 'on', this.clipped);
    this.draw(now, bypass);
  }

  private draw(now: number, bypass: boolean) {
    const o = this.o;
    const canvas = this.canvas;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.round(canvas.clientWidth * dpr);
    const hh = Math.round(canvas.clientHeight * dpr);
    if (!w || !hh) return;
    if (canvas.width !== w || canvas.height !== hh) { canvas.width = w; canvas.height = hh; }
    const c = canvas.getContext('2d')!;
    c.clearRect(0, 0, w, hh);
    const gap = GAP * dpr;
    const colW = (w - 2 * gap) / 3;
    const segGap = Math.max(1, Math.round(dpr));
    const segH = (hh - (SEGMENTS - 1) * segGap) / SEGMENTS;
    const line = Math.max(1, 1.5 * dpr);
    const yellow = color('--plock');
    const orange = color('--gr');
    const red = color('--rec');
    const grey = color('--mute-grey');
    const ink = color('--ink');
    // Неактивные сегменты — серые (цвет выключенного элемента темы).
    const off = color('--off');
    const levelColor = (db: number) => (bypass ? grey : db > 0 ? red : db >= -6 ? orange : yellow);
    const segY = (k: number) => hh - (k + 1) * segH - k * segGap;
    const yOf = (v: number, [lo, hi]: Range) => hh - Math.min(1, Math.max(0, (v - lo) / (hi - lo))) * hh;

    const level = (col: number, range: Range, b: Ballistic, mark: number | null) => {
      const [lo, hi] = range;
      const x = col * (colW + gap);
      const per = (hi - lo) / SEGMENTS;
      for (let k = 0; k < SEGMENTS; k++) {
        const bottom = lo + k * per;
        c.fillStyle = b.disp > bottom ? levelColor(bottom + per / 2) : off;
        c.fillRect(x, segY(k), colW, segH);
      }
      // Пиковая метка — тонкая линия цвета своего сегмента.
      if (b.hold > lo) {
        c.fillStyle = levelColor(b.hold);
        c.fillRect(x, yOf(b.hold, range) - dpr, colW, line);
      }
      // Белая риска (порог / CEILING).
      if (mark !== null) {
        c.fillStyle = ink;
        c.fillRect(x, yOf(mark, range) - dpr, colW, line);
      }
    };
    level(0, o.inRange, this.bIn, o.inMark());
    level(2, o.outRange, this.bOut, o.outMark());

    // GR: сверху вниз от нулевой линии; за краем шкалы нижний сегмент мигает.
    const x = colW + gap;
    const per = o.grMax / SEGMENTS;
    const g = this.bGr;
    const blink = Math.floor(now / 250) % 2 === 0;
    for (let k = 0; k < SEGMENTS; k++) {
      let lit = g.disp > k * per;
      if (k === SEGMENTS - 1 && g.disp > o.grMax) lit = blink;
      c.fillStyle = lit ? (bypass ? grey : orange) : off;
      c.fillRect(x, k * (segH + segGap), colW, segH);
    }
    if (g.hold > 0.05 && !bypass) {
      c.fillStyle = orange;
      c.fillRect(x, Math.min(1, g.hold / o.grMax) * hh - dpr, colW, line);
    }
  }
}

let glue: DynView;
let clip: DynView;
let lim: DynView;

/** Компрессор: IN −42…0, GR 0…−18, OUT −42…+3; риска порога на IN; клип — выход выше 0 dBFS. */
export function buildGlue(): HTMLElement {
  glue = new DynView({
    title: 'COMP', meter: glueMeter, bypass: () => doc.cmpBypass,
    inRange: [-42, 0], outRange: [-42, 3], grMax: 18,
    inMark: () => liveMaster()['cmp.threshold'], outMark: () => null,
    clips: (pk) => pk > 1,
  });
  return glue.el;
}

/** Клиппер: IN −30…+12, GR 0…−12, OUT −30…0; риски CEILING на IN и OUT; клип — сэмпл выхода выше 0 dBFS. */
export function buildClipper(): HTMLElement {
  const ceiling = () => liveMaster()['clip.ceiling'];
  clip = new DynView({
    title: 'CLIP', meter: clipperMeter, bypass: () => doc.clipBypass,
    inRange: [-30, 12], outRange: [-30, 0], grMax: 12,
    inMark: ceiling, outMark: ceiling,
    clips: (pk) => pk > 1,
  });
  return clip.el;
}

/** Лимитер: IN −30…+12, GR 0…−12, OUT −30…0; риски CEILING на IN и OUT; клип — true peak выше CEILING. */
export function buildLimiter(): HTMLElement {
  const ceiling = () => liveMaster()['lim.ceiling'];
  lim = new DynView({
    title: 'LIM', meter: limiterMeter, bypass: () => doc.limBypass,
    inRange: [-30, 12], outRange: [-30, 0], grMax: 12,
    inMark: ceiling, outMark: ceiling,
    // Небольшой допуск — от округления значений при сглаживании CEILING.
    clips: (pk) => toDb(pk) > ceiling() + 0.05,
  });
  return lim.el;
}

export function renderDynamics(now: number) {
  glue.render(now);
  clip.render(now);
  lim.render(now);
}
