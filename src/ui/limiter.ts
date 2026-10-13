// Окно лимитера мастера (этап 7): тап по блоку LIM при MST. На месте EQ (от левого края до края миниатюр страниц,
// справа — общий измеритель). Параметры — те же, что у ручек 4.1–4.4 в MST (и MIDI по позиции): окно и ручки
// меняют одни значения. Сверху вниз:
// — одна строка вверху (как ряд EQ): GAIN и CEILING (только показывают), поля LOOKAHEAD, RELEASE, LINK, кнопки
//   BYPASS, UNITY, AUDIT, SCALE и крестик; параметр, который меняют (палец, ручка, Twister, UNDO), — в жёлтой рамке и ещё 400 ms;
// — слева GAIN-слайдер, в центре дисплей уровня во времени (4 с), справа блок LIM (LevelBars, шкала по SCALE);
// Дисплей: сетка dB; вход после GAIN — серая заливка; выход — красный контур и полупрозрачная заливка; GR — оранжевая
// заливка сверху вниз; белая линия CEILING (тянется пальцем); подписи пиков GR; тап — HOLD (пауза).

import { LIM_TELE, limTele, limTeleRate } from '../audio/engine';
import { PARAM_BY_ID, isAuto, toNorm, type ParamDef } from '../params';
import { beginGesture, doc, endGesture, paramValue, setParamNorm, toggleLimBypass, toggleView, ui } from '../state';
import { saveSettings, settings } from '../settings';
import { dragField } from './controls';
import { LevelBars, limiterBars } from './dynamics';
import { closeButton, h, setClass, setText } from './dom';
import { openInput } from './popup';
import { color } from './theme';

/** Окно дисплея, с. */
const WINDOW_S = 4;
/** Рамка у параметра после изменения, ms. */
const HOT_MS = 400;
/** Зона касания линии CEILING, px (±). */
const LINE_HIT = 22;
/** Ход ручки на весь диапазон, px (как у ручек сетки). */
const TRAVEL_PX = 240;
/** Подписи пиков GR: порог, не чаще, не больше на экране. */
const PEAK_MIN_DB = 1;
const PEAK_GAP_MS = 80;
const PEAK_MAX = 6;
/** Перегрузка выхода — точка, если выход выше CEILING больше чем на, dB. */
const OVER_DB = 0.1;
const SCALES = [48, 32, 16] as const;

const P = {
  gain: PARAM_BY_ID['lim.input'],
  ceiling: PARAM_BY_ID['lim.ceiling'],
  lookahead: PARAM_BY_ID['lim.lookahead'],
  release: PARAM_BY_ID['lim.release'],
  link: PARAM_BY_ID['lim.link'],
};
const val = (p: ParamDef) => paramValue('master', p);
const setVal = (p: ParamDef, v: number) => setParamNorm('master', p, toNorm(p, Math.min(p.max, Math.max(p.min, v))));
const fmt = (p: ParamDef) => p.format(val(p)).replace('\n', ' ');

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let anchor: HTMLElement;
let slider: HTMLElement;
let sliderFill: HTMLElement;
let sliderValue: HTMLElement;
let bars: LevelBars;
let bypassBtn: HTMLElement;
let unityBtn: HTMLElement;
let auditBtn: HTMLElement;
let scaleBtn: HTMLElement;
const cells = new Map<string, { root: HTMLElement; value: HTMLElement }>();
const fieldEls = new Map<string, HTMLElement>();

/** Когда параметр менялся в последний раз (подсветка 400 ms) и прошлые значения. */
const changedAt = new Map<string, number>();
const lastVal = new Map<string, number>();
/** Пальцы на элементах окна: id параметра. */
const holding = new Map<number, string>();

// ---------- HOLD: снимок истории ----------
let hold = false;
const snap = { in: new Float32Array(LIM_TELE), out: new Float32Array(LIM_TELE), gr: new Float32Array(LIM_TELE), n: 0 };

function setHold(on: boolean) {
  hold = on;
  if (on) {
    snap.in.set(limTele.in); snap.out.set(limTele.out); snap.gr.set(limTele.gr);
    snap.n = limTele.n;
  }
}

// ---------- Ввод числом (окно — внутри окна лимитера, вверху) ----------
function numInput(el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string) {
  const r = el.getBoundingClientRect();
  const pr = panel.getBoundingClientRect();
  anchor.style.left = `${r.left + r.width / 2 - pr.left}px`;
  anchor.style.top = '56px';
  openInput(anchor, init, (t) => {
    const v = parse(t);
    if (v === null) return;
    beginGesture();
    setVal(p, v);
    endGesture();
  }, true);
}
const num = (t: string) => { const v = parseFloat(t.trim().replace(',', '.')); return Number.isFinite(v) ? v : null; };
/** RELEASE: «auto» — AUTO, иначе мс (или «1.2 s»). */
const parseRelease = (t: string) => {
  if (/auto/i.test(t)) return P.release.max + 1;
  const v = num(t);
  if (v === null) return null;
  return /s\s*$/i.test(t) && !/ms/i.test(t) ? v * 1000 : v;
};

// ---------- Построение ----------

export function buildLimiterWindow(): HTMLElement {
  panel = h('div', 'eq-panel lim-panel hidden');
  anchor = h('div', 'eq-anchor');

  // Одна строка вверху, как ряд EQ (тот же размер и поля): MASTER LIM, GAIN и CEILING (только показывают —
  // меняются слайдером и линией), поля LOOKAHEAD, RELEASE, LINK, кнопки BYPASS, UNITY, AUDIT, SCALE и крестик.
  const strip = h('div', 'eq-bar lim-strip');
  const head = h('div', 'eq-name', 'MASTER\nLIM');
  strip.append(head);
  for (const [key, label] of [['lim.input', 'GAIN'], ['lim.ceiling', 'CEILING']] as const) {
    const root = h('div', 'field eq-field lim-cell');
    const value = h('div', 'field-value');
    root.append(h('div', 'field-label', label), value);
    cells.set(key, { root, value });
    strip.append(root);
  }

  // GAIN-слайдер: палец вверх-вниз (ход как у ручек), удержание значения — ввод числом.
  slider = h('div', 'lim-slider');
  sliderFill = h('div', 'lim-slider-fill');
  sliderValue = h('div', 'lim-slider-value');
  slider.append(h('div', 'lim-slider-label', 'GAIN'), sliderFill, sliderValue);
  let sy = 0, sn = 0, sid = -1, sMoved = false, sTimer = 0;
  slider.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    slider.setPointerCapture(e.pointerId);
    sid = e.pointerId; sy = e.clientY; sn = toNorm(P.gain, val(P.gain)); sMoved = false;
    holding.set(e.pointerId, 'lim.input');
    beginGesture();
    sTimer = window.setTimeout(() => { if (!sMoved && sid === e.pointerId) numInput(sliderValue, P.gain, num, val(P.gain).toFixed(1)); }, 500);
  });
  slider.addEventListener('pointermove', (e) => {
    if (e.pointerId !== sid) return;
    if (!sMoved && Math.abs(e.clientY - sy) < 4) return;
    sMoved = true; clearTimeout(sTimer);
    setParamNorm('master', P.gain, Math.min(1, Math.max(0, sn + (sy - e.clientY) / TRAVEL_PX)));
  });
  const sUp = (e: PointerEvent) => { if (e.pointerId !== sid) return; sid = -1; clearTimeout(sTimer); holding.delete(e.pointerId); endGesture(); };
  slider.addEventListener('pointerup', sUp);
  slider.addEventListener('pointercancel', sUp);

  // Дисплей: линия CEILING тянется (±22 px), иначе тап — HOLD.
  plot = h('div', 'eq-plot lim-plot');
  canvas = document.createElement('canvas');
  canvas.className = 'eq-canvas';
  plot.append(canvas);
  const lineDrag = new Map<number, { y0: number; v0: number; moved: boolean }>();
  canvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    canvas.setPointerCapture(e.pointerId);
    const r = canvas.getBoundingClientRect();
    const y = e.clientY - r.top;
    if (Math.abs(y - yOf(val(P.ceiling), r.height)) <= LINE_HIT) {
      lineDrag.set(e.pointerId, { y0: e.clientY, v0: val(P.ceiling), moved: false });
      holding.set(e.pointerId, 'lim.ceiling');
      beginGesture();
    } else lineDrag.set(e.pointerId, { y0: e.clientY, v0: NaN, moved: false });
  });
  canvas.addEventListener('pointermove', (e) => {
    const d = lineDrag.get(e.pointerId);
    if (!d) return;
    if (Math.abs(e.clientY - d.y0) > 6) d.moved = true;
    if (Number.isNaN(d.v0)) return;
    // Линия идёт за пальцем по шкале дисплея.
    const h0 = canvas.getBoundingClientRect().height;
    setVal(P.ceiling, d.v0 - ((e.clientY - d.y0) / h0) * settings.limScale);
  });
  const cUp = (e: PointerEvent) => {
    const d = lineDrag.get(e.pointerId);
    if (!d) return;
    lineDrag.delete(e.pointerId);
    if (!Number.isNaN(d.v0)) { holding.delete(e.pointerId); endGesture(); return; }
    if (!d.moved && e.type === 'pointerup') setHold(!hold);
  };
  canvas.addEventListener('pointerup', cUp);
  canvas.addEventListener('pointercancel', cUp);

  bars = new LevelBars(limiterBars({ levelLo: () => -settings.limScale }));
  bars.el.classList.add('lim-bars');

  const mid = h('div', 'lim-mid');
  mid.append(slider, plot, bars.el);

  // Поля (как поля EQ) и кнопки — в той же строке.
  const look = dragField('LOOKAHEAD', () => Math.round(val(P.lookahead) * 10), (v) => setVal(P.lookahead, v / 10), () => fmt(P.lookahead), 6,
    undefined, (el) => numInput(el, P.lookahead, num, val(P.lookahead).toFixed(1)));
  const rel = dragField('RELEASE', () => Math.round(toNorm(P.release, val(P.release)) * 200),
    (v) => setParamNorm('master', P.release, Math.min(1, Math.max(0, v / 200))), () => fmt(P.release), 1.2,
    undefined, (el) => numInput(el, P.release, parseRelease, isAuto(val(P.release)) ? 'AUTO' : String(Math.round(val(P.release)))));
  const link = dragField('LINK', () => Math.round(val(P.link)), (v) => setVal(P.link, v), () => fmt(P.link), 2.4,
    undefined, (el) => numInput(el, P.link, num, String(Math.round(val(P.link)))));
  for (const [f, key] of [[look, 'lim.lookahead'], [rel, 'lim.release'], [link, 'lim.link']] as const) {
    f.classList.add('eq-field', 'lim-field');
    fieldEls.set(key, f);
  }
  const btn = (label: string, fn: () => void) => {
    const b = h('div', 'btn eq-tool lim-btn', label);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return b;
  };
  bypassBtn = btn('BYPASS', () => toggleLimBypass());
  unityBtn = btn('UNITY', () => { ui.limUnity = !ui.limUnity; });
  auditBtn = btn('AUDIT', () => { ui.limAudit = !ui.limAudit; });
  scaleBtn = btn('SCALE', () => {
    const k = SCALES.indexOf(settings.limScale);
    saveSettings({ limScale: SCALES[(k + 1) % SCALES.length] });
  });
  // Крестик — как у остальных окон (редактор сэмпла, браузер).
  strip.append(look, rel, link, bypassBtn, unityBtn, auditBtn, scaleBtn, closeButton(closeLimiterWindow));

  panel.append(strip, mid, anchor);
  return panel;
}

/** Крестик и выход из MST: окно закрывается, UNITY и AUDIT выключаются (toggleView). */
export function closeLimiterWindow() {
  if (ui.limView) toggleView('lim');
  hold = false;
}

// ---------- Отрисовка ----------

/** dB → y на дисплее высоты H (верх 0 dBFS, низ −SCALE). */
const yOf = (db: number, H: number) => Math.min(H, Math.max(0, (-db / settings.limScale) * H));
const toDb = (x: number) => 20 * Math.log10(Math.max(x, 1e-6));

export function renderLimiterWindow(now: number) {
  // Выход из MST закрывает окно.
  if (ui.limView && ui.channel !== 'master') closeLimiterWindow();
  setClass(panel, 'hidden', !ui.limView);
  if (!ui.limView) return;

  // Подсветка: параметр менялся последние 400 ms или его держит палец (в окне или поле).
  for (const p of [P.gain, P.ceiling, P.lookahead, P.release, P.link]) {
    const v = val(p);
    if (lastVal.has(p.id) && lastVal.get(p.id) !== v) changedAt.set(p.id, now);
    lastVal.set(p.id, v);
  }
  const held = new Set(holding.values());
  for (const [id, f] of fieldEls) if (f.classList.contains('active')) held.add(id);
  const hot = (id: string) => held.has(id) || now - (changedAt.get(id) ?? -1e9) < HOT_MS;

  const bypass = doc.limBypass;
  for (const [id, c] of cells) {
    setText(c.value, fmt(PARAM_BY_ID[id]));
    setClass(c.root, 'hot', hot(id));
    setClass(c.root, 'off', bypass);
  }
  for (const [id, f] of fieldEls) setClass(f, 'hot', hot(id));
  setClass(slider, 'hot', hot('lim.input'));
  setClass(plot, 'hot', hot('lim.ceiling'));
  sliderFill.style.height = `${toNorm(P.gain, val(P.gain)) * 100}%`;
  setText(sliderValue, fmt(P.gain));
  setClass(bypassBtn, 'active', bypass);
  setClass(unityBtn, 'active', ui.limUnity);
  setClass(auditBtn, 'active', ui.limAudit);
  setText(scaleBtn, `SCALE ${settings.limScale}`);
  bars.render(now);
  draw(now);
}

function draw(now: number) {
  const dpr = window.devicePixelRatio || 1;
  const W = plot.clientWidth;
  const H = plot.clientHeight;
  if (!W || !H) return;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const g = canvas.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, W, H);
  const scale = settings.limScale;
  const dim = color('--dim');

  // 1) Сетка и подписи dB.
  const step = scale === 48 ? 6 : scale === 32 ? 4 : 2;
  g.font = '10px -apple-system, sans-serif';
  g.textBaseline = 'top';
  g.textAlign = 'left';
  for (let db = 0; db > -scale; db -= step) {
    const y = Math.round(yOf(db, H)) + 0.5;
    g.fillStyle = color('--line');
    g.fillRect(0, y, W, 1);
    g.fillStyle = dim;
    g.fillText(db === 0 ? '0' : String(db), 4, y + 2);
  }

  // История: последние WINDOW_S секунд (при HOLD — снимок с момента паузы); каждый пиксель — максимум своего отрезка.
  const src = hold ? snap : limTele;
  const frames = Math.min(LIM_TELE, Math.round(WINDOW_S * limTeleRate()));
  const end = src.n;
  const live = hold || now - limTele.at < 300;
  const cols = Math.max(1, Math.floor(W));
  const inDb = new Float32Array(cols).fill(-200);
  const outDb = new Float32Array(cols).fill(-200);
  const grDb = new Float32Array(cols);
  if (live) {
    for (let x = 0; x < cols; x++) {
      const a = end - frames + Math.floor((x * frames) / cols);
      const b = end - frames + Math.floor(((x + 1) * frames) / cols);
      let mi = 0, mo = 0, mg = 0;
      for (let k = Math.max(a, end - LIM_TELE, 0); k < Math.max(b, a + 1) && k < end; k++) {
        const q = k % LIM_TELE;
        if (src.in[q] > mi) mi = src.in[q];
        if (src.out[q] > mo) mo = src.out[q];
        if (src.gr[q] > mg) mg = src.gr[q];
      }
      inDb[x] = mi > 0 ? toDb(mi) : -200;
      outDb[x] = mo > 0 ? toDb(mo) : -200;
      grDb[x] = mg;
    }
  }
  const bypass = doc.limBypass;
  const path = (data: Float32Array) => {
    g.beginPath();
    g.moveTo(0, H);
    for (let x = 0; x < cols; x++) g.lineTo(x, yOf(data[x], H));
    g.lineTo(cols, H);
    g.closePath();
  };
  // 2) Вход после GAIN — серая заливка с тонким контуром (выше 0 dBFS упирается в верх, светлее).
  path(inDb);
  g.fillStyle = color('--lim-in');
  g.fill();
  g.strokeStyle = dim;
  g.lineWidth = 1;
  g.stroke();
  g.fillStyle = color('--lim-in-over');
  for (let x = 0; x < cols; x++) {
    if (inDb[x] <= 0) continue;
    let e = x;
    while (e + 1 < cols && inDb[e + 1] > 0) e++;
    g.fillRect(x, 0, e - x + 1, 3);
    x = e;
  }
  // 3) Выход — красный контур и полупрозрачная красная заливка.
  if (!bypass) {
    path(outDb);
    g.fillStyle = color('--lim-out-fill');
    g.fill();
    g.strokeStyle = color('--meter-over');
    g.lineWidth = 1.5;
    g.beginPath();
    for (let x = 0; x < cols; x++) { const y = yOf(outDb[x], H); if (x) g.lineTo(x, y); else g.moveTo(x, y); }
    g.stroke();
  }
  // 4) GR — оранжевая заливка сверху вниз (высота — GR в dB по шкале дисплея).
  if (!bypass) {
    g.fillStyle = color('--meter-gr');
    g.beginPath();
    g.moveTo(0, 0);
    for (let x = 0; x < cols; x++) { const y = Math.min(H, (grDb[x] / scale) * H); g.lineTo(x, y); g.lineTo(x + 1, y); }
    g.lineTo(cols, 0);
    g.closePath();
    g.fill();
  }
  // 5) Линия CEILING и число справа.
  const ceil = val(P.ceiling);
  const cy = Math.round(yOf(ceil, H));
  g.fillStyle = color('--meter-thr');
  g.fillRect(0, cy - 1, W, 2);
  g.font = '11px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = cy > 16 ? 'bottom' : 'top';
  g.fillText(ceil.toFixed(1), W - 6, cy > 16 ? cy - 3 : cy + 3);

  // Подписи пиков GR: локальные максимумы ≥ 1 dB, не чаще 80 ms, до 6 самых сильных.
  if (!bypass) {
    const gapCols = Math.max(1, Math.round((PEAK_GAP_MS / 1000 / WINDOW_S) * cols));
    const peaks: { x: number; v: number }[] = [];
    for (let x = 1; x < cols - 1; x++) {
      const v = grDb[x];
      if (v < PEAK_MIN_DB || v < grDb[x - 1] || v < grDb[x + 1]) continue;
      const last = peaks[peaks.length - 1];
      if (last && x - last.x < gapCols) { if (v > last.v) { last.x = x; last.v = v; } continue; }
      peaks.push({ x, v });
    }
    peaks.sort((a, b) => b.v - a.v);
    g.fillStyle = color('--meter-gr');
    g.font = '10px -apple-system, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'top';
    for (const p of peaks.slice(0, PEAK_MAX)) {
      const y = Math.min(H - 12, (p.v / scale) * H + 3);
      g.fillText(`-${p.v.toFixed(1)}`, Math.min(W - 14, Math.max(14, p.x)), y);
    }
    // Перегрузка выхода: выход выше CEILING больше чем на 0.1 dB — красная точка у верхней кромки.
    g.fillStyle = color('--meter-over');
    for (let x = 0; x < cols; x++) {
      if (outDb[x] > ceil + OVER_DB) { g.beginPath(); g.arc(x, 4, 3, 0, 2 * Math.PI); g.fill(); }
    }
  }
  if (hold) {
    g.fillStyle = color('--accent');
    g.font = '600 11px -apple-system, sans-serif';
    g.textAlign = 'left';
    g.textBaseline = 'top';
    g.fillText('HOLD', 30, 6);
  }
}
