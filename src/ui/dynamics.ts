// Боковая панель мастера (при MST — окно сэмпла): блоки COMP | CLIP | LIM в порядке цепочки — один
// компонент LevelBars в стиле Drambo: три тонких стержня IN | GR | OUT одной высоты, сплошная заливка
// без сегментов, шкал, чисел и peak hold. IN и OUT — снизу вверх, −48…0 dBFS, цвет всего стержня по
// пику (жёлтый ниже −6 dB, оранжевый до 0, красный выше 0 — держится не меньше 300 ms); GR — сверху
// вниз, оранжевый, шкала у компрессора 18 dB, у клиппера и лимитера 12 dB. Белая риска порога
// (THRESHOLD / CEILING) — только на IN. Подъём мгновенный, спад 20 dB/s. В bypass стержни серые, GR ноль.
// Кнопки RATIO и BYPASS — на месте LFO1–3/ENV под окном (buttons.ts). Цвета — из темы (--meter-*).
// Холст рисуется в общем кадре.
import { clipperMeter, glueMeter, limiterMeter, type DynLevels } from '../audio/engine';
import { doc, liveMaster } from '../state';
import { h } from './dom';
import { color } from './theme';

/** Шкала IN и OUT, dB (низ…верх). */
const LEVEL_LO = -48;
const LEVEL_HI = 0;
const FALL_DB_S = 20;
/** Красный держится не меньше, ms. */
const OVER_HOLD_MS = 300;
/** Ширина стержня, px; риска шире на RISK_EXTRA с каждой стороны, толщина RISK_H. */
const BAR_W = 10;
const RISK_EXTRA = 6;
const RISK_H = 2;
/** Высота строки подписей IN / GR / OUT под стержнями, px. */
const LABEL_H = 14;
/** Данные worklet старше этого — тишина (звук остановлен). */
const STALE_MS = 150;

const toDb = (x: number) => 20 * Math.log10(Math.max(x, 1e-6));

/** Цвет темы светлее на долю k (для серых стержней в bypass). */
function lighten(css: string, k: number): string {
  let r = 128, g = 128, b = 128;
  const hex = css.trim().match(/^#([0-9a-f]{6})$/i);
  const rgb = css.match(/rgba?\(([^)]+)\)/);
  if (hex) { const n = parseInt(hex[1], 16); r = n >> 16; g = (n >> 8) & 255; b = n & 255; }
  else if (rgb) [r, g, b] = rgb[1].split(',').map((v) => parseFloat(v));
  const f = (v: number) => Math.round(v + (255 - v) * k);
  return `rgb(${f(r)}, ${f(g)}, ${f(b)})`;
}

interface Level { disp: number; overUntil: number }

interface BarsOptions {
  title: string;
  meter: () => DynLevels;
  bypass: () => boolean;
  /** Шкала GR, dB. */
  grMax: number;
  /** Белая риска порога на IN (dB). */
  inMark: () => number;
}

/** LevelBars: общий компонент индикации компрессора, клиппера и лимитера. */
class LevelBars {
  el: HTMLElement;
  private canvas: HTMLCanvasElement;
  private lIn: Level = { disp: -120, overUntil: 0 };
  private lOut: Level = { disp: -120, overUntil: 0 };
  private gr = 0;
  private last = 0;

  constructor(private o: BarsOptions) {
    this.el = h('div', 'vbar-group glue');
    this.canvas = h('canvas', 'glue-canvas');
    this.el.append(h('div', 'vbar-title', o.title), this.canvas);
  }

  private level(l: Level, v: number, dt: number, now: number) {
    l.disp = Math.max(v, l.disp - FALL_DB_S * dt);
    if (v > 0) l.overUntil = now + OVER_HOLD_MS;
  }

  render(now: number) {
    const o = this.o;
    const dt = this.last ? Math.min(0.1, (now - this.last) / 1000) : 0;
    this.last = now;
    const m = o.meter();
    const live = now - m.at < STALE_MS;
    const bypass = o.bypass();
    this.level(this.lIn, live ? toDb(m.in) : -120, dt, now);
    this.level(this.lOut, live ? toDb(m.out) : -120, dt, now);
    const gr = live && !bypass ? m.gr : 0;
    this.gr = bypass ? 0 : Math.max(gr, this.gr - FALL_DB_S * dt);
    this.draw(now, bypass);
  }

  private draw(now: number, bypass: boolean) {
    const o = this.o;
    const canvas = this.canvas;
    const dpr = window.devicePixelRatio || 1;
    const cw = canvas.clientWidth;
    const ch = canvas.clientHeight;
    if (!cw || !ch) return;
    const w = Math.round(cw * dpr);
    const hh = Math.round(ch * dpr);
    if (canvas.width !== w || canvas.height !== hh) { canvas.width = w; canvas.height = hh; }
    const c = canvas.getContext('2d')!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, cw, ch);
    const track = color('--meter-track');
    const off = lighten(track, 0.2);
    const barH = ch - LABEL_H;
    // Стержни разнесены равномерно: центры на 1/6, 3/6, 5/6 ширины блока.
    const cx = [cw / 6, cw / 2, (5 * cw) / 6];
    const x0 = (k: number) => Math.round(cx[k] - BAR_W / 2);
    const levelColor = (l: Level) => {
      if (bypass) return off;
      if (l.disp > 0 || now < l.overUntil) return color('--meter-over');
      return l.disp >= -6 ? color('--meter-warn') : color('--meter-ok');
    };
    const frac = (db: number) => Math.min(1, Math.max(0, (db - LEVEL_LO) / (LEVEL_HI - LEVEL_LO)));
    // IN и OUT — снизу вверх.
    const bar = (k: number, l: Level) => {
      c.fillStyle = track;
      c.fillRect(x0(k), 0, BAR_W, barH);
      const f = frac(l.disp);
      if (f > 0) {
        c.fillStyle = levelColor(l);
        c.fillRect(x0(k), barH * (1 - f), BAR_W, barH * f);
      }
    };
    bar(0, this.lIn);
    bar(2, this.lOut);
    // GR — сверху вниз.
    c.fillStyle = track;
    c.fillRect(x0(1), 0, BAR_W, barH);
    const g = Math.min(1, this.gr / o.grMax);
    if (g > 0) {
      c.fillStyle = bypass ? off : color('--meter-gr');
      c.fillRect(x0(1), 0, BAR_W, barH * g);
    }
    // Белая риска порога — только на IN.
    c.fillStyle = color('--meter-thr');
    const ry = Math.round(barH * (1 - frac(o.inMark())) - RISK_H / 2);
    c.fillRect(x0(0) - RISK_EXTRA, Math.max(0, Math.min(barH - RISK_H, ry)), BAR_W + 2 * RISK_EXTRA, RISK_H);
    // Подписи под стержнями.
    c.fillStyle = color('--dim');
    c.font = '9px -apple-system, sans-serif';
    c.textAlign = 'center';
    c.textBaseline = 'bottom';
    ['IN', 'GR', 'OUT'].forEach((t, k) => c.fillText(t, cx[k], ch));
  }
}

let glue: LevelBars;
let clip: LevelBars;
let lim: LevelBars;

/** Компрессор: GR 0…−18 dB, риска THRESHOLD на IN. */
export function buildGlue(): HTMLElement {
  glue = new LevelBars({ title: 'COMP', meter: glueMeter, bypass: () => doc.cmpBypass, grMax: 18, inMark: () => liveMaster()['cmp.threshold'] });
  return glue.el;
}

/** Клиппер: GR 0…−12 dB, риска CEILING на IN. */
export function buildClipper(): HTMLElement {
  clip = new LevelBars({ title: 'CLIP', meter: clipperMeter, bypass: () => doc.clipBypass, grMax: 12, inMark: () => liveMaster()['clip.ceiling'] });
  return clip.el;
}

/** Лимитер: GR 0…−12 dB, риска CEILING на IN. */
export function buildLimiter(): HTMLElement {
  lim = new LevelBars({ title: 'LIM', meter: limiterMeter, bypass: () => doc.limBypass, grMax: 12, inMark: () => liveMaster()['lim.ceiling'] });
  return lim.el;
}

export function renderDynamics(now: number) {
  glue.render(now);
  clip.render(now);
  lim.render(now);
}
