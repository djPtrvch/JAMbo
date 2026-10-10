// Графический эквалайзер (кнопка EQ): на месте центра экрана, размером как сетка паттернов.
// Показывает EQ выбранной дорожки, а при MIX и MST — мастера. 8 полос, по умолчанию их нет.
//
// Управление касанием: двойной тап по пустому месту — новая bell-полоса (частота по горизонтали,
// усиление по вертикали); точку тянут (у cut и notch — только частота); щипок по выбранной точке
// меняет Q; двойной тап по точке включает и выключает полосу; долгое нажатие — меню типа,
// крутизны среза и удаления. Внизу поля выбранной полосы: тип, Freq, Gain, Q.
//
// Фон — сетка частот и уровней; спектр до EQ — серая линия, после — заливка (жёлтая, выше −6 dB
// оранжевая, выше 0 dB красная); суммарная кривая белая; точки полос белые с номерами,
// выбранная крупнее и жёлтая, выключенные серые. Анализаторы работают, только пока панель открыта.

import { bandResponse } from '../audio/eq';
import { eqSampleRate, eqSpectrum, setEqScope } from '../audio/engine';
import {
  EQ_FREQ_MAX, EQ_FREQ_MIN, EQ_SLOPES, EQ_TYPES, eqHasGain, eqIsCut, noteName,
} from '../params';
import {
  addEqBand, beginGesture, deleteEqBand, endGesture, eqTarget, eqTargetName, resetEq, selectedBand,
  setEqBand, setEqSlope, setEqType, toggleEq, toggleEqBand, ui, type EqBand,
} from '../state';
import { dragField } from './controls';
import { h, setClass, setText } from './dom';
import { makePopup, popupButton } from './popup';

/** Вертикальная шкала кривой EQ: ±DB_RANGE дБ на всю высоту (усиление полос — до ±18 дБ). */
const DB_RANGE = 21;
/** Шкала спектра, dBFS. */
const SPEC_TOP = 6;
const SPEC_BOT = -90;
const OCTAVES = Math.log2(EQ_FREQ_MAX / EQ_FREQ_MIN);
/** Радиус зоны касания точки (зона не меньше 44 px). */
const HIT_R = 24;
const MOVE_PX = 8;
const LONG_MS = 500;
const DOUBLE_MS = 320;

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let nameText: HTMLElement;
let bypassBtn: HTMLElement;
let anchor: HTMLElement;
const tips: HTMLElement[] = [];
let W = 0;
let H = 0;

// ---------- Координаты ----------

const xOf = (f: number) => (W * Math.log2(f / EQ_FREQ_MIN)) / OCTAVES;
const freqAt = (x: number) => EQ_FREQ_MIN * Math.pow(2, (x / W) * OCTAVES);
const yOfGain = (g: number) => H / 2 - (g / DB_RANGE) * (H / 2);
const gainAt = (y: number) => ((H / 2 - y) / (H / 2)) * DB_RANGE;
const yOfSpec = (db: number) => (H * (SPEC_TOP - db)) / (SPEC_TOP - SPEC_BOT);
const pointY = (b: EqBand) => yOfGain(eqHasGain(b.type) ? b.gain : 0);

function fmtHz(f: number): string {
  if (f < 1000) return `${f.toFixed(f < 100 ? 1 : 0)} Hz`;
  return `${(f / 1000).toFixed(f < 10000 ? 2 : 1)} kHz`;
}
const fmtGain = (g: number) => `${g > 0 ? '+' : ''}${g.toFixed(1)} dB`;
const noteOf = (f: number) => noteName(Math.max(0, Math.round(69 + 12 * Math.log2(f / 440))));

// ---------- Касания ----------

interface Touch {
  id: number; x: number; y: number; x0: number; y0: number;
  band: number; f0: number; g0: number;
  moved: boolean; menu: boolean; gesture: boolean; timer: number;
}
const touches = new Map<number, Touch>();
let pinch: { band: number; a: number; b: number; d0: number; q0: number } | null = null;
let lastTap: { t: number; x: number; y: number; band: number } | null = null;

function local(e: PointerEvent): [number, number] {
  const r = canvas.getBoundingClientRect();
  return [e.clientX - r.left, e.clientY - r.top];
}

/** Ближайшая точка полосы в зоне касания (выбранная — в приоритете). */
function hitBand(x: number, y: number): number {
  let best = -1;
  let bestD = HIT_R;
  eqTarget().bands.forEach((b, k) => {
    if (!b) return;
    const d = Math.hypot(xOf(b.freq) - x, pointY(b) - y) - (k === ui.eqBand ? 6 : 0);
    if (d < bestD) { bestD = d; best = k; }
  });
  return best;
}

function down(e: PointerEvent) {
  e.preventDefault();
  canvas.setPointerCapture(e.pointerId);
  const [x, y] = local(e);
  const hit = hitBand(x, y);
  const t: Touch = { id: e.pointerId, x, y, x0: x, y0: y, band: -1, f0: 0, g0: 0, moved: false, menu: false, gesture: false, timer: 0 };
  touches.set(e.pointerId, t);
  // Второй палец рядом с выбранной точкой, которую уже держат, — щипок (Q).
  const holder = [...touches.values()].find((o) => o !== t && o.band >= 0 && o.band === ui.eqBand);
  const sel = selectedBand();
  if (holder && sel && !pinch && (hit < 0 || hit === ui.eqBand)) {
    clearTimeout(holder.timer);
    holder.moved = true;
    pinch = { band: ui.eqBand, a: holder.id, b: t.id, d0: Math.max(20, Math.hypot(holder.x - x, holder.y - y)), q0: sel.q };
    t.moved = true;
    return;
  }
  if (hit < 0) return;
  const b = eqTarget().bands[hit]!;
  ui.eqBand = hit;
  Object.assign(t, { band: hit, f0: b.freq, g0: b.gain, gesture: true });
  beginGesture();
  t.timer = window.setTimeout(() => {
    if (t.moved || !touches.has(t.id)) return;
    t.menu = true;
    openBandMenu(hit, t.x, t.y);
  }, LONG_MS);
}

function move(e: PointerEvent) {
  const t = touches.get(e.pointerId);
  if (!t) return;
  [t.x, t.y] = local(e);
  if (!t.moved && Math.hypot(t.x - t.x0, t.y - t.y0) > MOVE_PX) { t.moved = true; clearTimeout(t.timer); }
  if (pinch && (t.id === pinch.a || t.id === pinch.b)) {
    const a = touches.get(pinch.a);
    const b = touches.get(pinch.b);
    if (!a || !b) return;
    // Пальцы врозь — полоса шире (Q меньше), сведение — уже.
    const d = Math.max(20, Math.hypot(a.x - b.x, a.y - b.y));
    setEqBand(pinch.band, { q: pinch.q0 * (pinch.d0 / d) });
    return;
  }
  if (t.band < 0 || t.menu || !t.moved) return;
  const b = eqTarget().bands[t.band];
  if (!b) return;
  const freq = t.f0 * Math.pow(2, ((t.x - t.x0) / W) * OCTAVES);
  setEqBand(t.band, eqHasGain(b.type) ? { freq, gain: t.g0 + gainAt(t.y) - gainAt(t.y0) } : { freq });
}

function up(e: PointerEvent) {
  const t = touches.get(e.pointerId);
  if (!t) return;
  touches.delete(e.pointerId);
  clearTimeout(t.timer);
  if (pinch && (t.id === pinch.a || t.id === pinch.b)) {
    // Оставшийся палец продолжает тянуть точку с текущего места.
    const other = touches.get(t.id === pinch.a ? pinch.b : pinch.a);
    const b = eqTarget().bands[pinch.band];
    if (other && b) Object.assign(other, { x0: other.x, y0: other.y, f0: b.freq, g0: b.gain });
    pinch = null;
  }
  if (t.gesture) endGesture();
  if (t.moved || t.menu || e.type !== 'pointerup') return;
  const now = performance.now();
  if (lastTap && now - lastTap.t < DOUBLE_MS && Math.hypot(lastTap.x - t.x, lastTap.y - t.y) < 30 && lastTap.band === t.band) {
    if (t.band >= 0) toggleEqBand(t.band);
    else addEqBand(freqAt(t.x), gainAt(t.y));
    lastTap = null;
  } else {
    lastTap = { t: now, x: t.x, y: t.y, band: t.band };
  }
}

// ---------- Меню полосы (долгое нажатие, тап по полю типа) ----------

const menu = makePopup('grid cols-3 eq-menu');
const typeBtns = EQ_TYPES.map((tp, i) => popupButton(tp.name.toUpperCase(), () => { setEqType(menuBand, i); menu.close(); }));
const slopeBtns = EQ_SLOPES.map((s, i) => popupButton(`${s} dB/oct`, () => { setEqSlope(menuBand, i); menu.close(); }));
const deleteBtn = popupButton('DELETE', () => { deleteEqBand(menuBand); menu.close(); });
deleteBtn.classList.add('wide');
menu.box.append(...typeBtns, ...slopeBtns, deleteBtn);
let menuBand = -1;

function openBandMenu(k: number, x: number, y: number) {
  const b = eqTarget().bands[k];
  if (!b) return;
  menuBand = k;
  typeBtns.forEach((btn, i) => btn.classList.toggle('current', i === b.type));
  slopeBtns.forEach((btn, i) => {
    btn.disabled = !eqIsCut(b.type);
    btn.classList.toggle('current', eqIsCut(b.type) && i === b.slope);
  });
  anchor.style.left = `${x}px`;
  anchor.style.top = `${y}px`;
  menu.openAt(anchor, 390);
}

// ---------- Построение ----------

export function buildEq(): HTMLElement {
  panel = h('div', 'eq-panel hidden');
  plot = h('div', 'eq-plot');
  canvas = document.createElement('canvas');
  canvas.className = 'eq-canvas';
  anchor = h('div', 'eq-anchor');
  plot.append(canvas, anchor);
  for (let i = 0; i < 4; i++) {
    const tip = h('div', 'eq-tip hidden');
    tips.push(tip);
    plot.append(tip);
  }
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);

  const bar = h('div', 'eq-bar');
  nameText = h('div', 'eq-name');
  const k = () => ui.eqBand;
  const typeField = dragField(
    'TYPE', () => selectedBand()?.type ?? 0, (v) => setEqType(k(), v),
    () => { const b = selectedBand(); return b ? EQ_TYPES[b.type].name + (eqIsCut(b.type) ? ` ${EQ_SLOPES[b.slope]}` : '') : '—'; },
    30, (el) => { if (selectedBand()) { const r = el.getBoundingClientRect(), p = plot.getBoundingClientRect(); openBandMenu(k(), r.left + r.width / 2 - p.left, r.top - p.top); } },
  );
  const freqField = dragField(
    'FREQ', () => Math.round(Math.log2((selectedBand()?.freq ?? 1000) / EQ_FREQ_MIN) * 24),
    (v) => setEqBand(k(), { freq: EQ_FREQ_MIN * Math.pow(2, v / 24) }),
    () => { const b = selectedBand(); return b ? fmtHz(b.freq) : '—'; }, 2,
  );
  const gainField = dragField(
    'GAIN', () => Math.round((selectedBand()?.gain ?? 0) * 10),
    (v) => { const b = selectedBand(); if (b && eqHasGain(b.type)) setEqBand(k(), { gain: v / 10 }); },
    () => { const b = selectedBand(); return b && eqHasGain(b.type) ? fmtGain(b.gain) : '—'; }, 1,
  );
  const qField = dragField(
    'Q', () => Math.round(Math.log2(selectedBand()?.q ?? 1) * 12),
    (v) => setEqBand(k(), { q: Math.pow(2, v / 12) }),
    () => { const b = selectedBand(); return b ? b.q.toFixed(2) : '—'; }, 3,
  );
  for (const f of [typeField, freqField, gainField, qField]) f.classList.add('eq-field');
  bypassBtn = h('div', 'btn eq-tool', 'BYPASS');
  bypassBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleEq(); });
  const resetBtn = h('div', 'btn eq-tool', 'RESET');
  resetBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); resetEq(); });
  bar.append(nameText, typeField, freqField, gainField, qField, bypassBtn, resetBtn);

  panel.append(plot, bar);
  return panel;
}

// ---------- Отрисовка ----------

let freqs = new Float32Array(0);
let curve = new Float32Array(0);
let band = new Float32Array(0);
let curveSig = '';
const pre = new Float32Array(2048);
const post = new Float32Array(2048);
const STEP = 2;

/** Суммарная кривая EQ по точкам через STEP пикселей (пересчёт только при изменениях). */
function updateCurve() {
  const eq = eqTarget();
  const n = Math.ceil(W / STEP) + 1;
  const sr = eqSampleRate();
  const sig = `${n}|${sr}|${JSON.stringify(eq)}`;
  if (sig === curveSig) return;
  curveSig = sig;
  if (freqs.length !== n) {
    freqs = new Float32Array(n);
    curve = new Float32Array(n);
    band = new Float32Array(n);
  }
  for (let i = 0; i < n; i++) freqs[i] = Math.min(sr / 2, freqAt(i * STEP));
  curve.fill(0);
  for (const b of eq.bands) {
    if (!b || !b.on) continue;
    bandResponse(b, freqs, band, sr);
    for (let i = 0; i < n; i++) curve[i] += band[i];
  }
}

/** Значение спектра (dBFS) на частоте f: максимум по бинам в столбце пикселей. */
function specAt(data: Float32Array, f0: number, f1: number, binHz: number): number {
  const i0 = Math.max(1, Math.floor(f0 / binHz));
  const i1 = Math.min(data.length - 1, Math.floor(f1 / binHz));
  if (i1 <= i0) {
    // Низкие частоты: бинов меньше, чем пикселей — интерполяция между соседними бинами.
    const p = Math.min(data.length - 2, f0 / binHz);
    const i = Math.floor(p);
    return data[i] + (data[i + 1] - data[i]) * (p - i);
  }
  let m = -Infinity;
  for (let i = i0; i <= i1; i++) m = Math.max(m, data[i]);
  return m;
}

function drawGrid(g: CanvasRenderingContext2D) {
  g.lineWidth = 1;
  for (let d = 10; d <= 10000; d *= 10) {
    for (let m = 1; m <= 9; m++) {
      const f = d * m;
      if (f < EQ_FREQ_MIN || f > EQ_FREQ_MAX) continue;
      const x = Math.round(xOf(f)) + 0.5;
      g.strokeStyle = m === 1 ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.06)';
      g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke();
    }
  }
  for (let db = -18; db <= 18; db += 6) {
    const y = Math.round(yOfGain(db)) + 0.5;
    g.strokeStyle = db === 0 ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.06)';
    g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke();
  }
  g.fillStyle = '#7d838c';
  g.font = '11px -apple-system, sans-serif';
  g.textBaseline = 'bottom';
  for (const [f, s] of [[100, '100 Hz'], [1000, '1 kHz'], [10000, '10 kHz']] as const) g.fillText(s, xOf(f) + 4, H - 4);
  g.textBaseline = 'middle';
  for (const db of [12, 0, -12]) g.fillText(`${db > 0 ? '+' : ''}${db} dB`, 6, yOfGain(db) - 8);
}

function drawSpectrum(g: CanvasRenderingContext2D) {
  if (!eqSpectrum(pre, post)) return;
  const binHz = eqSampleRate() / 4096;
  const n = Math.ceil(W / STEP) + 1;
  const yPre = new Float32Array(n);
  const yPost = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const f0 = freqAt(i * STEP);
    const f1 = freqAt((i + 1) * STEP);
    yPre[i] = yOfSpec(Math.max(SPEC_BOT, specAt(pre, f0, f1, binHz)));
    yPost[i] = yOfSpec(Math.max(SPEC_BOT, specAt(post, f0, f1, binHz)));
  }
  // После EQ — заливка: жёлтая, выше −6 dB оранжевая, выше 0 dB красная (как в метрах).
  const p0 = yOfSpec(0) / H;
  const p6 = yOfSpec(-6) / H;
  const grad = g.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, '#ff4d4d');
  grad.addColorStop(p0, '#ff4d4d');
  grad.addColorStop(p0, '#ff8a3d');
  grad.addColorStop(p6, '#ff8a3d');
  grad.addColorStop(p6, '#ffd23f');
  grad.addColorStop(1, '#ffd23f');
  g.beginPath();
  g.moveTo(0, H);
  for (let i = 0; i < n; i++) g.lineTo(i * STEP, yPost[i]);
  g.lineTo(W, H);
  g.closePath();
  g.globalAlpha = 0.7;
  g.fillStyle = grad;
  g.fill();
  g.globalAlpha = 1;
  // До EQ — серая линия.
  g.beginPath();
  for (let i = 0; i < n; i++) (i ? g.lineTo : g.moveTo).call(g, i * STEP, yPre[i]);
  g.strokeStyle = 'rgba(200,205,212,0.55)';
  g.lineWidth = 1.2;
  g.stroke();
}

function drawCurve(g: CanvasRenderingContext2D, on: boolean) {
  updateCurve();
  g.beginPath();
  for (let i = 0; i < curve.length; i++) {
    const y = yOfGain(Math.max(-DB_RANGE * 1.2, Math.min(DB_RANGE * 1.2, curve[i])));
    (i ? g.lineTo : g.moveTo).call(g, i * STEP, y);
  }
  g.strokeStyle = on ? '#ffffff' : 'rgba(255,255,255,0.35)';
  g.lineWidth = 2;
  g.stroke();
}

function drawPoints(g: CanvasRenderingContext2D) {
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  eqTarget().bands.forEach((b, k) => {
    if (!b) return;
    const sel = k === ui.eqBand;
    const r = sel ? 13 : 10;
    const x = xOf(b.freq);
    const y = pointY(b);
    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fillStyle = !b.on ? '#6b7078' : sel ? '#ffd23f' : '#ffffff';
    g.fill();
    g.fillStyle = '#111214';
    g.font = `600 ${sel ? 13 : 11}px -apple-system, sans-serif`;
    g.fillText(String(k + 1), x, y + 0.5);
  });
  g.textAlign = 'start';
}

/** Подсказки над пальцами, которые держат точки: частота (Гц и нота), усиление, Q. */
function renderTips() {
  const held = [...touches.values()].filter((t) => t.band >= 0 && !t.menu);
  tips.forEach((tip, i) => {
    const t = held[i];
    const b = t ? eqTarget().bands[t.band] : null;
    setClass(tip, 'hidden', !b);
    if (!t || !b) return;
    setText(tip, `${fmtHz(b.freq)} · ${noteOf(b.freq)}\n${eqHasGain(b.type) ? fmtGain(b.gain) : '—'} · Q ${b.q.toFixed(2)}`);
    tip.style.left = `${Math.max(60, Math.min(W - 60, t.x))}px`;
    tip.style.top = `${Math.max(4, t.y - 90)}px`;
  });
}

let shownKey = '';

export function renderEq() {
  setClass(panel, 'hidden', !ui.eqView);
  if (!ui.eqView) {
    setEqScope(null);
    return;
  }
  setEqScope(ui.channel === 'track' ? ui.selectedTrack : 'master');
  const eq = eqTarget();
  // Другой канал — выбор полосы сбрасывается.
  const key = ui.channel === 'track' ? `t${ui.selectedTrack}` : 'master';
  if (key !== shownKey) { shownKey = key; ui.eqBand = -1; }
  if (ui.eqBand >= 0 && !eq.bands[ui.eqBand]) ui.eqBand = -1;
  setText(nameText, `${eqTargetName()}\nEQ`);
  setClass(bypassBtn, 'active', !eq.on);

  const dpr = window.devicePixelRatio || 1;
  W = plot.clientWidth;
  H = plot.clientHeight;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const g = canvas.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, W, H);
  drawGrid(g);
  drawSpectrum(g);
  drawCurve(g, eq.on);
  drawPoints(g);
  renderTips();
}
