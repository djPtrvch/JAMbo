// Скоп мастера: при MST на месте миниатюр страниц. Сверху гониометр (стереобаза конечного сигнала
// мастера — после громкости выхода: точки L/R,
// повёрнутые на 45° — вертикаль mid, горизонталь side, с послесвечением), под ним до кнопок
// осциллоскоп как в Drambo (бегущая форма волны L+R за ~1 с, без чисел).
// Сигнал после сатуратора (белый) виден всегда; кнопки COMP, CLIP, LIM включают и выключают точки съёма
// после компрессора, клиппера, лимитера (формы волны накладываются разными цветами) — на месте FX, MOD,
// MORPH (SHIFT остаётся на своём месте). Анализаторы работают, только пока скоп виден.

import { masterGonio, masterScope, setMasterScope } from '../audio/engine';
import { ui } from '../state';
import { h, setClass } from './dom';
import { color } from './theme';

const POINTS = ['SAT', 'COMP', 'CLIP', 'LIM'];
/** Окно осциллоскопа (вся ширина), с. */
const OSC_WINDOW = 1;
/** Послесвечение гониометра: доля прошлого кадра, которая остаётся. */
const PERSIST = 0.75;

let root: HTMLElement;
let gonio: HTMLCanvasElement;
let osc: HTMLCanvasElement;
let btnGrid: HTMLElement;
const btns: HTMLElement[] = [];
/**
 * Включённые точки съёма: SAT (после сатуратора, белая) видна всегда; COMP, CLIP, LIM — кнопками
 * (переключаются независимо; по умолчанию — LIM); в проекте не хранится.
 */
const on = [true, false, false, true];
/** Цвета форм волны: SAT белая, COMP жёлтая, CLIP оранжевая, LIM красная (цвета темы). */
const TRACE_COLORS = ['--ink', '--plock', '--gr', '--rec'];
/** Прозрачность форм волны (наложение). */
const TRACE_ALPHA = 0.6;
const L = new Float32Array(4096);
const R = new Float32Array(4096);
/** Гониометр — конечный сигнал мастера. */
const GL = new Float32Array(4096);
const GR = new Float32Array(4096);

export function buildScope(): HTMLElement {
  root = h('div', 'mscope hidden');
  gonio = document.createElement('canvas');
  gonio.className = 'mscope-gonio';
  osc = document.createElement('canvas');
  osc.className = 'mscope-osc';
  // Холсты — абсолютно внутри обёрток: в Safari размер холста в flex иначе влияет на раскладку.
  const gw = h('div', 'canvas-wrap mscope-gonio');
  const ow = h('div', 'canvas-wrap mscope-osc');
  gonio.className = '';
  osc.className = '';
  gw.append(gonio);
  ow.append(osc);
  root.append(gw, ow);
  return root;
}

/** Кнопки точек съёма COMP, CLIP, LIM на месте FX, MOD, MORPH и SHIFT на своём месте (сетка видна только при MST). */
export function buildScopeButtons(shift: HTMLElement): HTMLElement {
  btnGrid = h('div', 'btn-grid hidden');
  POINTS.forEach((name, i) => {
    if (i === 0) return;
    const b = h('div', 'btn master-btn', name);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); on[i] = !on[i]; });
    btns[i] = b;
  });
  // Вверху COMP и CLIP, внизу SHIFT (на своём месте, слева) и LIM.
  btnGrid.append(btns[1], btns[2], shift, btns[3]);
  return btnGrid;
}

/** Холст под размер элемента (с учётом плотности пикселей). */
function fit(c: HTMLCanvasElement): [CanvasRenderingContext2D, number, number, number] {
  const dpr = window.devicePixelRatio || 1;
  const w = c.clientWidth;
  const hh = c.clientHeight;
  const changed = c.width !== Math.round(w * dpr) || c.height !== Math.round(hh * dpr);
  if (changed) { c.width = Math.round(w * dpr); c.height = Math.round(hh * dpr); }
  const g = c.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  return [g, w, hh, changed ? 1 : 0];
}

function drawGonio(ok: boolean) {
  const [g, w, hh] = fit(gonio);
  // Послесвечение: прошлый кадр гаснет под фоном.
  g.globalAlpha = 1 - PERSIST;
  g.fillStyle = color('--panel');
  g.fillRect(0, 0, w, hh);
  g.globalAlpha = 1;
  const cx = w / 2;
  const cy = hh / 2;
  const r = Math.min(w, hh) / 2 - 4;
  // Оси: M (вертикаль), S (горизонталь), L и R (диагонали).
  g.strokeStyle = color('--grid-strong');
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(cx, cy - r); g.lineTo(cx, cy + r);
  g.moveTo(cx - r, cy); g.lineTo(cx + r, cy);
  const d = r * Math.SQRT1_2;
  g.moveTo(cx - d, cy - d); g.lineTo(cx + d, cy + d);
  g.moveTo(cx + d, cy - d); g.lineTo(cx - d, cy + d);
  g.stroke();
  g.fillStyle = color('--dim');
  g.font = '9px -apple-system, sans-serif';
  g.fillText('L', cx - d - 2, cy - d - 3);
  g.fillText('R', cx + d - 4, cy - d - 3);
  if (!ok) return;
  g.fillStyle = color('--accent');
  g.globalAlpha = 0.55;
  for (let i = 0; i < GL.length; i += 2) {
    const m = (GL[i] + GR[i]) * Math.SQRT1_2;
    const s = (GL[i] - GR[i]) * Math.SQRT1_2;
    const x = cx + Math.max(-1.2, Math.min(1.2, s)) * r;
    const y = cy - Math.max(-1.2, Math.min(1.2, m)) * r;
    g.fillRect(x - 0.6, y - 0.6, 1.2, 1.2);
  }
  g.globalAlpha = 1;
}

// Осциллоскоп как в Drambo: бегущая форма волны за OSC_WINDOW с, по столбцу на пиксель
// (штрих от минимума до максимума отрезка). Включённые точки съёма рисуются одна поверх другой своими
// цветами (порядок цепочки: SAT снизу, LIM сверху) — видно, что срезает каждый модуль.

/** История одной точки съёма: столбцы min/max по кругу. */
class Trace {
  min = new Float32Array(0);
  max = new Float32Array(0);
  pos = 0;
  /** Отсчёты, не уместившиеся в целый столбец (переходят в следующий кадр). */
  carry = 0;
  cMin = 0;
  cMax = 0;

  resize(W: number) {
    if (this.min.length === W) return;
    this.min = new Float32Array(W);
    this.max = new Float32Array(W);
    this.pos = 0;
    this.carry = 0;
  }

  /** Новые отсчёты кадра (последние n из буфера анализатора) — в столбцы по spc отсчётов. */
  push(n: number, spc: number) {
    const W = this.min.length;
    for (let i = L.length - n; i < L.length; i++) {
      const v = (L[i] + R[i]) / 2;
      if (this.carry === 0) { this.cMin = v; this.cMax = v; } else { if (v < this.cMin) this.cMin = v; if (v > this.cMax) this.cMax = v; }
      if (++this.carry >= spc) {
        this.min[this.pos] = this.cMin;
        this.max[this.pos] = this.cMax;
        this.pos = (this.pos + 1) % W;
        this.carry = 0;
      }
    }
  }

  clear() { this.min.fill(0); this.max.fill(0); }
}

const traces = POINTS.map(() => new Trace());
let oscT = 0;

function drawOsc(sr: number) {
  const [g, w, hh] = fit(osc);
  const W = Math.max(1, Math.round(w));
  const now = performance.now();
  const dt = oscT ? Math.min(0.1, (now - oscT) / 1000) : 0;
  oscT = now;
  g.fillStyle = color('--panel');
  g.fillRect(0, 0, w, hh);
  const cy = hh / 2;
  const amp = hh / 2 - 2;
  const y = (v: number) => cy - Math.max(-1, Math.min(1, v)) * amp;
  g.fillStyle = color('--grid-strong');
  g.fillRect(0, Math.round(cy), w, 1);
  traces.forEach((t, k) => {
    t.resize(W);
    if (!on[k]) { t.clear(); return; }
    if (masterScope(k, L, R)) t.push(Math.min(L.length, Math.round(dt * sr)), Math.max(1, (OSC_WINDOW * sr) / W));
    g.fillStyle = color(TRACE_COLORS[k]);
    // Полупрозрачные — при наложении видны все включённые формы волны.
    g.globalAlpha = TRACE_ALPHA;
    for (let x = 0; x < W; x++) {
      const i = (t.pos + x) % W;
      const a = t.min[i];
      const b = t.max[i];
      const top = y(b);
      g.fillRect(x, top, 1, Math.max(1, y(a) - top));
    }
    g.globalAlpha = 1;
  });
}

export function renderScope(sampleRate: number) {
  const show = ui.channel === 'master';
  setClass(root, 'hidden', !show);
  setClass(btnGrid, 'hidden', !show);
  setMasterScope(show ? on : null);
  if (!show) return;
  btns.forEach((b, i) => {
    // Включённая кнопка — цветом своей формы волны.
    b.style.background = on[i] ? color(TRACE_COLORS[i]) : '';
    b.style.color = on[i] ? color('--on-accent') : '';
  });
  drawGonio(masterGonio(GL, GR));
  drawOsc(sampleRate);
}
