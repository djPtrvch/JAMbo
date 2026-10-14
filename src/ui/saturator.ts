// Окно сатуратора мастера (этап 7): тап по кнопке SAT при MST. На месте EQ (от левого края до края миниатюр
// страниц, справа — общий измеритель). DRIVE, TYPE, TONE, MIX — те же параметры, что у ручек 1.1–1.4 в MST
// (и MIDI по позиции); FOCUS, BIAS, OUTPUT, AUTO — только в окне. Нижней панели нет. Сверху вниз:
// — строка (как ряд EQ): поля DRIVE, TYPE, TONE, MIX, FOCUS, BIAS, OUTPUT, AUTO (палец вверх-вниз, удержание —
//   ввод; у TYPE и AUTO тап — следующее значение), кнопки BYPASS, SCALE и крестик;
// — TRANSFER (кривая формирователя после DRIVE, оси −1…+1: палец по вертикали — DRIVE, по горизонтали — BIAS) |
//   DISPLAY: сверху WAVE (форма за 4 с: вход — серая заливка, выход — белый контур), снизу SPECTRUM (вход — серая
//   заливка, выход — белый контур, линия FOCUS тянется по горизонтали); тап по любой половине — FREEZE.

import { LIM_TELE, eqSampleRate, satSpectrum, satTele, setSatScope, limTeleRate } from '../audio/engine';
import { PARAM_BY_ID, SAT_FOCUS_OFF, toNorm, type ParamDef } from '../params';
import { beginGesture, doc, endGesture, setParamNorm, toggleSatBypass, toggleView, ui } from '../state';
import { saveSettings, settings } from '../settings';
import { closeButton, h, setClass, setText } from './dom';
import {
  HotTracker, LINE_HIT, SCALES, WINDOW_S, drawPauseLabel, fitCanvas, gridStep, msetVal as setVal, mval as val, num, numInputIn, paramField, toDb,
} from './masterwin';
import { color } from './theme';

/** Палец по вертикали на весь диапазон DRIVE, px (как у ручек). */
const TRAVEL_PX = 240;
/** Точка-ручка на кривой — при входе, px (диаметр). */
const HANDLE = 28;
/** Вход, на котором стоит ручка кривой (доля полной шкалы). */
const HANDLE_X = 0.5;
/** SPECTRUM: частоты, пол — 2·SCALE dB. */
const F_LO = 20;
const F_HI = 20000;
const FOCUS_MAX = 2000;
const TUBE_BIAS = 0.35;
const TB = Math.tanh(TUBE_BIAS);
const TD = 1 - TB * TB;

/** Кривые — как в saturator-worklet.js. */
const SHAPE = [
  (u: number) => Math.tanh(u),
  (u: number) => (Math.tanh(u + TUBE_BIAS) - TB) / TD,
  (u: number) => u / Math.sqrt(Math.sqrt(1 + u * u * u * u)),
];

const P = {
  drive: PARAM_BY_ID['sat.drive'],
  type: PARAM_BY_ID['sat.type'],
  tone: PARAM_BY_ID['sat.tone'],
  mix: PARAM_BY_ID['sat.mix'],
  focus: PARAM_BY_ID['sat.focus'],
  bias: PARAM_BY_ID['sat.bias'],
  out: PARAM_BY_ID['sat.out'],
  auto: PARAM_BY_ID['sat.auto'],
};
const TYPES = ['TAPE', 'TUBE', 'EDGE'];

let panel: HTMLElement;
let anchor: HTMLElement;
let tBox: HTMLElement;
let tCanvas: HTMLCanvasElement;
let wBox: HTMLElement;
let wCanvas: HTMLCanvasElement;
let sBox: HTMLElement;
let sCanvas: HTMLCanvasElement;
let bypassBtn: HTMLElement;
let scaleBtn: HTMLElement;
const fieldEls = new Map<string, HTMLElement>();
const hotT = new HotTracker(Object.values(P));

// ---------- FREEZE: обе половины DISPLAY ----------
let frozen = false;
const snapT = { inLo: new Float32Array(LIM_TELE), inHi: new Float32Array(LIM_TELE), outLo: new Float32Array(LIM_TELE), outHi: new Float32Array(LIM_TELE), n: 0 };
const pre = new Float32Array(2048);
const post = new Float32Array(2048);
let haveSpec = false;
function setFreeze(on: boolean) {
  frozen = on;
  if (!on) return;
  const t = satTele;
  snapT.inLo.set(t.inLo); snapT.inHi.set(t.inHi); snapT.outLo.set(t.outLo); snapT.outHi.set(t.outHi);
  snapT.n = t.n;
}

const numInput = (el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string) => numInputIn(panel, anchor, el, p, parse, init);

/** Компенсация громкости (AUTO): пик кривой на синусе −12 dBFS · g (без постоянной составляющей), как в worklet. */
let compKey = '';
let compVal = 1;
function comp(type: number, g: number): number {
  const key = `${type}:${g.toFixed(4)}`;
  if (key === compKey) return compVal;
  const f = SHAPE[type];
  const N = 256;
  const v = new Float64Array(N);
  let mean = 0;
  for (let k = 0; k < N; k++) { v[k] = f(0.25 * g * Math.sin((2 * Math.PI * k) / N)); mean += v[k]; }
  mean /= N;
  let pk = 0;
  for (let k = 0; k < N; k++) pk = Math.max(pk, Math.abs(v[k] - mean));
  compKey = key;
  compVal = pk / 0.25;
  return compVal;
}
/** Кривая графика: (кривая(x·g + b) − кривая(b)) / c · OUTPUT (без TONE и MIX). */
function curveFn() {
  const type = Math.round(val(P.type));
  const g = Math.pow(10, val(P.drive) / 20);
  const b = val(P.bias);
  const c = val(P.auto) >= 0.5 ? comp(type, g) : 1;
  const og = Math.pow(10, val(P.out) / 20);
  const f = SHAPE[type];
  const fb = f(b);
  return (x: number) => ((f(x * g + b) - fb) / c) * og;
}

// ---------- Построение ----------

export function buildSatWindow(): HTMLElement {
  panel = h('div', 'eq-panel lim-panel sat-panel hidden');
  anchor = h('div', 'eq-anchor');

  const strip = h('div', 'eq-bar lim-strip sat-strip');
  strip.append(h('div', 'eq-name', 'MASTER\nSAT'));
  const field = (label: string, p: ParamDef, parse: (t: string) => number | null, init: () => string, onTap?: () => void) => {
    const f = paramField(label, p, numInput, parse, init, onTap);
    f.classList.add('lim-field');
    fieldEls.set(p.id, f);
    return f;
  };
  const tapNext = (p: ParamDef) => () => { beginGesture(); setVal(p, (Math.round(val(p)) + 1) % (p.max + 1)); endGesture(); };
  const typeParse = (t: string) => { const i = TYPES.indexOf(t.trim().toUpperCase()); if (i >= 0) return i; const v = num(t); return v === null ? null : Math.round(v) - 1; };
  strip.append(
    field('DRIVE', P.drive, num, () => val(P.drive).toFixed(1)),
    field('TYPE', P.type, typeParse, () => TYPES[Math.round(val(P.type))], tapNext(P.type)),
    // TONE: в поле и на ручке — наклон в dB; ввод — проценты −100…100.
    field('TONE', P.tone, num, () => String(Math.round(val(P.tone)))),
    field('MIX', P.mix, num, () => String(Math.round(val(P.mix)))),
    field('FOCUS', P.focus, (t) => (/off/i.test(t) ? SAT_FOCUS_OFF : num(t)), () => (val(P.focus) <= SAT_FOCUS_OFF + 0.5 ? 'OFF' : String(Math.round(val(P.focus))))),
    field('BIAS', P.bias, num, () => val(P.bias).toFixed(2)),
    field('OUTPUT', P.out, num, () => val(P.out).toFixed(1)),
    field('AUTO', P.auto, (t) => (/on/i.test(t) ? 1 : /off/i.test(t) ? 0 : null), () => (val(P.auto) >= 0.5 ? 'ON' : 'OFF'), tapNext(P.auto)),
  );
  const btn = (label: string, fn: () => void) => {
    const b = h('div', 'btn eq-tool lim-btn', label);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return b;
  };
  bypassBtn = btn('BYPASS', () => toggleSatBypass());
  scaleBtn = btn('SCALE', () => {
    const k = SCALES.indexOf(settings.limScale);
    saveSettings({ limScale: SCALES[(k + 1) % SCALES.length] });
  });
  strip.append(bypassBtn, scaleBtn, closeButton(closeSatWindow));

  // TRANSFER: палец в любом месте поля — по вертикали DRIVE, по горизонтали BIAS (относительно касания).
  tBox = h('div', 'eq-plot sat-transfer');
  tCanvas = document.createElement('canvas');
  tCanvas.className = 'eq-canvas';
  tBox.append(tCanvas, h('div', 'comp-plot-title', 'TRANSFER'));
  const tDrag = new Map<number, { x0: number; y0: number; d0: number; b0: number }>();
  tCanvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    tCanvas.setPointerCapture(e.pointerId);
    tDrag.set(e.pointerId, { x0: e.clientX, y0: e.clientY, d0: toNorm(P.drive, val(P.drive)), b0: val(P.bias) });
    hotT.hold(e.pointerId, 'sat.drive');
    hotT.hold(-1 - e.pointerId, 'sat.bias');
    beginGesture();
  });
  tCanvas.addEventListener('pointermove', (e) => {
    const d = tDrag.get(e.pointerId);
    if (!d) return;
    const w = tCanvas.getBoundingClientRect().width;
    setParamNorm('master', P.drive, Math.min(1, Math.max(0, d.d0 + (d.y0 - e.clientY) / TRAVEL_PX)));
    setVal(P.bias, Math.round((d.b0 + ((e.clientX - d.x0) / w) * 2) * 100) / 100);
  });
  const tUp = (e: PointerEvent) => {
    if (!tDrag.delete(e.pointerId)) return;
    hotT.release(e.pointerId);
    hotT.release(-1 - e.pointerId);
    endGesture();
  };
  tCanvas.addEventListener('pointerup', tUp);
  tCanvas.addEventListener('pointercancel', tUp);

  // DISPLAY: WAVE сверху, SPECTRUM снизу; тап — FREEZE (обе), линия FOCUS тянется (±22 px, приоритет выше FREEZE).
  const display = h('div', 'sat-display');
  wBox = h('div', 'eq-plot sat-half');
  wCanvas = document.createElement('canvas');
  wCanvas.className = 'eq-canvas';
  wBox.append(wCanvas);
  sBox = h('div', 'eq-plot sat-half');
  sCanvas = document.createElement('canvas');
  sCanvas.className = 'eq-canvas';
  sBox.append(sCanvas);
  display.append(wBox, sBox);
  const tap = new Map<number, { x: number; y: number; moved: boolean; focus: boolean }>();
  for (const cv of [wCanvas, sCanvas]) {
    cv.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      cv.setPointerCapture(e.pointerId);
      const r = cv.getBoundingClientRect();
      const onFocus = cv === sCanvas && Math.abs(e.clientX - r.left - fx(val(P.focus), r.width)) <= LINE_HIT;
      tap.set(e.pointerId, { x: e.clientX, y: e.clientY, moved: false, focus: onFocus });
      if (onFocus) { hotT.hold(e.pointerId, 'sat.focus'); beginGesture(); }
    });
    cv.addEventListener('pointermove', (e) => {
      const d = tap.get(e.pointerId);
      if (!d) return;
      if (Math.hypot(e.clientX - d.x, e.clientY - d.y) > 6) d.moved = true;
      if (!d.focus) return;
      const r = cv.getBoundingClientRect();
      const f = F_LO * Math.pow(F_HI / F_LO, (e.clientX - r.left) / r.width);
      setVal(P.focus, Math.min(FOCUS_MAX, Math.max(SAT_FOCUS_OFF, Math.round(f))));
    });
    const up = (e: PointerEvent) => {
      const d = tap.get(e.pointerId);
      if (!d) return;
      tap.delete(e.pointerId);
      if (d.focus) { hotT.release(e.pointerId); endGesture(); return; }
      if (!d.moved && e.type === 'pointerup') setFreeze(!frozen);
    };
    cv.addEventListener('pointerup', up);
    cv.addEventListener('pointercancel', up);
  }

  const mid = h('div', 'lim-mid');
  mid.append(tBox, display);
  panel.append(strip, mid, anchor);
  return panel;
}

/** Крестик и выход из MST: окно закрывается, анализаторы спектра снимаются, FREEZE снимается. */
export function closeSatWindow() {
  if (ui.satView) toggleView('sat');
  frozen = false;
}

// ---------- Отрисовка ----------

const fx = (f: number, W: number) => (Math.log(f / F_LO) / Math.log(F_HI / F_LO)) * W;
let scopeOn = false;

export function renderSatWindow(now: number) {
  if (ui.satView && ui.channel !== 'master') closeSatWindow();
  setClass(panel, 'hidden', !ui.satView);
  // Анализаторы спектра — только пока окно открыто.
  // (каждый кадр: после перезапуска звука граф новый — анализаторы подключаются заново).
  if (scopeOn !== ui.satView) { scopeOn = ui.satView; haveSpec = false; if (!scopeOn) setSatScope(false); }
  if (ui.satView) setSatScope(true);
  if (!ui.satView) return;

  hotT.update(now, [...fieldEls].filter(([, f]) => f.classList.contains('active')).map(([id]) => id));
  const hot = (id: string) => hotT.hot(id, now);
  const bypass = !!doc.satBypass;
  for (const [id, f] of fieldEls) { setClass(f, 'hot', hot(id)); setClass(f, 'off', bypass); }
  setClass(bypassBtn, 'active', bypass);
  setText(scaleBtn, `SCALE ${settings.limScale}`);
  const live = now - satTele.at < 300;
  drawTransfer(hot, live);
  drawWave(live);
  drawSpectrum(hot);
}

function drawTransfer(hot: (id: string) => boolean, live: boolean) {
  const f = fitCanvas(tCanvas, tBox);
  if (!f) return;
  const { g, W, H } = f;
  const sx = (x: number) => ((x + 1) / 2) * W;
  const sy = (y: number) => Math.min(H, Math.max(0, ((1 - y) / 2) * H));
  // Сетка через 0.5 и подписи.
  g.font = '10px -apple-system, sans-serif';
  g.textBaseline = 'top';
  g.textAlign = 'left';
  for (const v of [-0.5, 0, 0.5]) {
    g.fillStyle = v === 0 ? color('--dim') : color('--line');
    g.fillRect(0, Math.round(sy(v)) + 0.5, W, 1);
    g.fillRect(Math.round(sx(v)) + 0.5, 0, 1, H);
  }
  g.fillStyle = color('--dim');
  g.fillText('+1', 4, 2);
  g.textBaseline = 'bottom';
  g.fillText('-1', 4, H - 2);
  // Диагональ.
  g.strokeStyle = color('--dim');
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(0, H);
  g.lineTo(W, 0);
  g.stroke();
  // Кривая.
  const fn = curveFn();
  const bypass = !!doc.satBypass;
  g.strokeStyle = bypass ? color('--dim') : color('--text');
  g.lineWidth = 1.5;
  g.beginPath();
  for (let x = 0; x <= W; x++) { const y = sy(fn((x / W) * 2 - 1)); if (x) g.lineTo(x, y); else g.moveTo(x, y); }
  g.stroke();
  // Точка текущего уровня — пока идёт сигнал.
  const t = satTele;
  if (live && !bypass && Math.abs(t.px) > 1e-4) {
    g.fillStyle = color('--text');
    g.beginPath();
    g.arc(sx(Math.max(-1, Math.min(1, t.px))), sy(t.py), 3, 0, 2 * Math.PI);
    g.fill();
  }
  // Ручка на кривой (вход HANDLE_X) с подписью DRIVE и BIAS.
  const hx = sx(HANDLE_X), hy = sy(fn(HANDLE_X));
  const hHot = hot('sat.drive') || hot('sat.bias');
  g.lineWidth = 1.5;
  g.strokeStyle = hHot ? color('--accent') : color('--text');
  g.fillStyle = color('--panel');
  g.beginPath();
  g.arc(hx, hy, HANDLE / 2 - 1, 0, 2 * Math.PI);
  g.fill();
  g.stroke();
  g.fillStyle = hHot ? color('--accent') : color('--text');
  g.font = '11px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = hy > H / 2 ? 'bottom' : 'top';
  const lbl = `DRIVE ${P.drive.format(val(P.drive))} · BIAS ${P.bias.format(val(P.bias))}`;
  g.fillText(lbl, Math.min(W - 6, hx + HANDLE), hy > H / 2 ? hy - HANDLE / 2 - 4 : hy + HANDLE / 2 + 4);
}

/** WAVE: огибающая мин./макс. за 4 с; по высоте — dB со знаком (0 dBFS у краёв, −SCALE в середине). */
function drawWave(live: boolean) {
  const f = fitCanvas(wCanvas, wBox);
  if (!f) return;
  const { g, W, H } = f;
  const scale = settings.limScale;
  const mid = H / 2;
  const half = H / 2 - 2;
  const yv = (v: number) => { const a = Math.max(0, Math.min(1, 1 + toDb(Math.abs(v)) / scale)); return mid - Math.sign(v) * a * half; };
  // Сетка: 0 dB у краёв, деления по шкале.
  const step = gridStep(scale) * 2;
  g.font = '10px -apple-system, sans-serif';
  g.textAlign = 'left';
  g.textBaseline = 'top';
  for (let d = 0; d > -scale; d -= step) {
    const a = 1 + d / scale;
    g.fillStyle = color('--line');
    g.fillRect(0, Math.round(mid - a * half) + 0.5, W, 1);
    g.fillRect(0, Math.round(mid + a * half) + 0.5, W, 1);
    g.fillStyle = color('--dim');
    g.fillText(d === 0 ? '0' : String(d), 4, mid - a * half + 2);
  }
  g.fillStyle = color('--dim');
  g.fillRect(0, Math.round(mid) + 0.5, W, 1);
  const t = satTele;
  const src = frozen ? snapT : t;
  const frames = Math.min(LIM_TELE, Math.round(WINDOW_S * limTeleRate()));
  const end = src.n;
  const cols = Math.max(1, Math.floor(W));
  if (frozen || live) {
    const iLo = new Float32Array(cols), iHi = new Float32Array(cols), oLo = new Float32Array(cols), oHi = new Float32Array(cols);
    for (let x = 0; x < cols; x++) {
      const a = end - frames + Math.floor((x * frames) / cols);
      const b = end - frames + Math.floor(((x + 1) * frames) / cols);
      let l1 = 0, h1 = 0, l2 = 0, h2 = 0;
      for (let k = Math.max(a, end - LIM_TELE, 0); k < Math.max(b, a + 1) && k < end; k++) {
        const q = k % LIM_TELE;
        if (src.inLo[q] < l1) l1 = src.inLo[q];
        if (src.inHi[q] > h1) h1 = src.inHi[q];
        if (src.outLo[q] < l2) l2 = src.outLo[q];
        if (src.outHi[q] > h2) h2 = src.outHi[q];
      }
      iLo[x] = l1; iHi[x] = h1; oLo[x] = l2; oHi[x] = h2;
    }
    // Вход — серая заливка между мин. и макс.
    g.beginPath();
    g.moveTo(0, yv(iHi[0]));
    for (let x = 0; x < cols; x++) g.lineTo(x, yv(iHi[x]));
    for (let x = cols - 1; x >= 0; x--) g.lineTo(x, yv(iLo[x]));
    g.closePath();
    g.fillStyle = color('--lim-in');
    g.fill();
    // Выход — белый контур (макс. и мин.).
    g.strokeStyle = doc.satBypass ? color('--dim') : color('--text');
    g.lineWidth = 1.5;
    for (const arr of [oHi, oLo]) {
      g.beginPath();
      for (let x = 0; x < cols; x++) (x ? g.lineTo(x, yv(arr[x])) : g.moveTo(x, yv(arr[x])));
      g.stroke();
    }
  }
  g.fillStyle = color('--dim');
  g.font = '9px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = 'bottom';
  g.fillText('WAVE', W - 6, H - 4);
  if (frozen) drawPauseLabel(g, 'FREEZE');
}

/** SPECTRUM: 20 Hz…20 kHz (логарифм), уровень 0…−2·SCALE dB; вход — серая заливка, выход — белый контур, линия FOCUS. */
function drawSpectrum(hot: (id: string) => boolean) {
  const f = fitCanvas(sCanvas, sBox);
  if (!f) return;
  const { g, W, H } = f;
  const floor = -2 * settings.limScale;
  const yOf = (d: number) => Math.min(H, Math.max(0, (d / floor) * H));
  // Сетка: 100 Hz, 1 kHz, 10 kHz и уровни.
  g.font = '10px -apple-system, sans-serif';
  g.textBaseline = 'top';
  g.textAlign = 'left';
  for (const [hz, l] of [[100, '100'], [1000, '1k'], [10000, '10k']] as const) {
    const x = Math.round(fx(hz, W)) + 0.5;
    g.fillStyle = color('--line');
    g.fillRect(x, 0, 1, H);
    g.fillStyle = color('--dim');
    g.fillText(l, x + 3, H - 13);
  }
  const step = settings.limScale / 2;
  for (let d = 0; d > floor; d -= step) {
    g.fillStyle = color('--line');
    g.fillRect(0, Math.round(yOf(d)) + 0.5, W, 1);
    g.fillStyle = color('--dim');
    g.fillText(d === 0 ? '0' : String(d), 4, yOf(d) + 2);
  }
  if (!frozen && satSpectrum(pre, post)) haveSpec = true;
  if (haveSpec) {
    const sr = eqSampleRate();
    const bins = pre.length;
    const cols = Math.max(1, Math.floor(W));
    const colOf = (arr: Float32Array) => {
      const outA = new Float32Array(cols).fill(-200);
      for (let x = 0; x < cols; x++) {
        const f0 = F_LO * Math.pow(F_HI / F_LO, x / cols);
        const f1 = F_LO * Math.pow(F_HI / F_LO, (x + 1) / cols);
        const a = Math.max(1, Math.floor((f0 / sr) * 2 * bins));
        const b = Math.min(bins - 1, Math.max(a, Math.floor((f1 / sr) * 2 * bins)));
        let m = -200;
        for (let k = a; k <= b; k++) if (arr[k] > m) m = arr[k];
        outA[x] = m;
      }
      return outA;
    };
    const a = colOf(pre);
    const b = colOf(post);
    g.beginPath();
    g.moveTo(0, H);
    for (let x = 0; x < cols; x++) g.lineTo(x, yOf(a[x]));
    g.lineTo(cols, H);
    g.closePath();
    g.fillStyle = color('--lim-in');
    g.fill();
    g.strokeStyle = doc.satBypass ? color('--dim') : color('--text');
    g.lineWidth = 1.5;
    g.beginPath();
    for (let x = 0; x < cols; x++) (x ? g.lineTo(x, yOf(b[x])) : g.moveTo(x, yOf(b[x])));
    g.stroke();
  }
  // Линия FOCUS (на 20 Hz — OFF, у левого края).
  const fHot = hot('sat.focus');
  const fv = val(P.focus);
  const x = Math.max(1, fx(fv, W));
  g.fillStyle = fHot ? color('--accent') : color('--meter-thr');
  g.fillRect(Math.round(x) - 1, 0, 2, H);
  g.font = '11px -apple-system, sans-serif';
  g.textAlign = x > W - 80 ? 'right' : 'left';
  g.textBaseline = 'top';
  g.fillText(`FOCUS ${P.focus.format(fv)}`, x > W - 80 ? x - 6 : x + 6, 4);
  g.fillStyle = color('--dim');
  g.font = '9px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = 'bottom';
  g.fillText('SPECTRUM', W - 6, H - 4);
  if (frozen) drawPauseLabel(g, 'FREEZE');
}
