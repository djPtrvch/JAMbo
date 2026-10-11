// Скоп мастера: при MST на месте миниатюр страниц. Сверху гониометр (стереобаза: точки L/R,
// повёрнутые на 45° — вертикаль mid, горизонталь side, с послесвечением), под ним осциллоскоп
// (L+R, ~40 ms, синхронизация по переходу через ноль вверх) до кнопок. Кнопки SAT, COMP, CLIP, LIM —
// точка съёма (после сатуратора, компрессора, клиппера или лимитера) — на месте MORPH, RANDOM, FX, MOD. Анализаторы работают,
// только пока скоп виден.

import { masterScope, setMasterScope } from '../audio/engine';
import { ui } from '../state';
import { h, setClass } from './dom';
import { color } from './theme';

const POINTS = ['SAT', 'COMP', 'CLIP', 'LIM'];
/** Окно осциллоскопа, с. */
const OSC_SEC = 0.04;
/** Послесвечение гониометра: доля прошлого кадра, которая остаётся. */
const PERSIST = 0.75;

let root: HTMLElement;
let gonio: HTMLCanvasElement;
let osc: HTMLCanvasElement;
let btnGrid: HTMLElement;
const btns: HTMLElement[] = [];
/** Точка съёма; по умолчанию — после лимитера (в проекте не хранится). */
let point = 3;
const L = new Float32Array(4096);
const R = new Float32Array(4096);

export function buildScope(): HTMLElement {
  root = h('div', 'mscope hidden');
  gonio = document.createElement('canvas');
  gonio.className = 'mscope-gonio';
  osc = document.createElement('canvas');
  osc.className = 'mscope-osc';
  root.append(gonio, osc);
  return root;
}

/** Кнопки точки съёма: сетка 2×2 на месте MORPH, RANDOM, FX, MOD (видна только при MST). */
export function buildScopeButtons(): HTMLElement {
  btnGrid = h('div', 'btn-grid hidden');
  POINTS.forEach((name, i) => {
    const b = h('div', 'btn master-btn', name);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); point = i; });
    btns.push(b);
    btnGrid.append(b);
  });
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
  for (let i = 0; i < L.length; i += 2) {
    const m = (L[i] + R[i]) * Math.SQRT1_2;
    const s = (L[i] - R[i]) * Math.SQRT1_2;
    const x = cx + Math.max(-1.2, Math.min(1.2, s)) * r;
    const y = cy - Math.max(-1.2, Math.min(1.2, m)) * r;
    g.fillRect(x - 0.6, y - 0.6, 1.2, 1.2);
  }
  g.globalAlpha = 1;
}

function drawOsc(ok: boolean, sr: number) {
  const [g, w, hh] = fit(osc);
  g.fillStyle = color('--panel');
  g.fillRect(0, 0, w, hh);
  const cy = hh / 2;
  g.strokeStyle = color('--grid-strong');
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(0, cy); g.lineTo(w, cy);
  g.stroke();
  if (!ok) return;
  const n = Math.min(L.length / 2, Math.round(OSC_SEC * sr));
  // Синхронизация: первый переход через ноль вверх в первой половине буфера.
  let start = 0;
  for (let i = 1; i < L.length - n; i++) {
    if (L[i - 1] + R[i - 1] < 0 && L[i] + R[i] >= 0) { start = i; break; }
  }
  g.beginPath();
  for (let x = 0; x <= w; x++) {
    const i = start + Math.floor((x / w) * (n - 1));
    const v = (L[i] + R[i]) / 2;
    const y = cy - Math.max(-1, Math.min(1, v)) * (hh / 2 - 2);
    (x ? g.lineTo : g.moveTo).call(g, x, y);
  }
  g.strokeStyle = color('--ink');
  g.lineWidth = 1.4;
  g.stroke();
}

export function renderScope(sampleRate: number) {
  const show = ui.channel === 'master';
  setClass(root, 'hidden', !show);
  setClass(btnGrid, 'hidden', !show);
  setMasterScope(show ? point : null);
  if (!show) return;
  btns.forEach((b, i) => setClass(b, 'active', i === point));
  const ok = masterScope(L, R);
  if (!ok) { L.fill(0); R.fill(0); }
  drawGonio(ok);
  drawOsc(ok, sampleRate);
}
