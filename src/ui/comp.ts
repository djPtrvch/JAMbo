// Окно компрессора мастера (этап 7): тап по блоку COMP при MST. На месте EQ (от левого края до края миниатюр
// страниц, справа — общий измеритель). THRESHOLD, ATTACK, RELEASE, MAKEUP — те же параметры, что у ручек 2.1–2.4
// в MST (и MIDI по позиции); RATIO, KNEE, RANGE, HOLD, MIX, LINK, SC HPF — только в окне. Сверху вниз:
// — строка значений (как ряд EQ): THRESHOLD, ATTACK, RELEASE, MAKEUP | RATIO — только показ; параметр, который
//   меняют, — в жёлтой рамке и ещё 400 ms (RATIO — только при изменении в окне); при BYPASS ячейки серые; крестик;
// — TRANSFER (кривая передачи: точка порога тянется вдоль диагонали, кружок RATIO на правом краю) | LEVEL (уровень
//   за 4 с: вход серый, выход после MAKEUP жёлтый, GR оранжевый сверху; пунктир THRESHOLD тянется, тап — FREEZE) |
//   блок COMP (LevelBars, шкала по SCALE). Шкала у TRANSFER и LEVEL общая — линии на одной высоте;
// — нижняя панель (две строки): поля ATTACK, RELEASE, MAKEUP, RATIO, KNEE, RANGE, HOLD, MIX, LINK, SC HPF и кнопки
//   BYPASS, AUDIT, SCALE.

import { compTele, LIM_TELE } from '../audio/engine';
import { CMP_RANGE_OFF, CMP_SCHPF_OFF, PARAM_BY_ID, RATIOS, isAuto, toNorm, type ParamDef } from '../params';
import { beginGesture, doc, endGesture, setParamNorm, toggleCmpBypass, toggleView, ui } from '../state';
import { saveSettings, settings } from '../settings';
import { dragField } from './controls';
import { LevelBars, glueBars } from './dynamics';
import { closeButton, h, setClass, setText } from './dom';
import { parseRelease } from './limiter';
import {
  Freeze, HotTracker, LINE_HIT, SCALES, drawDbGrid, drawGrPeaks, drawPauseLabel, fitCanvas, historyColumns, mfmt as fmt, msetVal as setVal,
  mval as val, num, numInputIn,
} from './masterwin';
import { color } from './theme';

/** Подписи пиков GR: не чаще, ms. */
const PEAK_GAP_MS = 100;
/** Кружок RATIO, px (диаметр). */
const RATIO_HANDLE = 28;
/** Делений поля на весь ход (240 px — как у ручек сетки). */
const FIELD_UNITS = 200;
const FIELD_PX = 1.2;

const P = {
  threshold: PARAM_BY_ID['cmp.threshold'],
  attack: PARAM_BY_ID['cmp.attack'],
  release: PARAM_BY_ID['cmp.release'],
  makeup: PARAM_BY_ID['cmp.makeup'],
  ratio: PARAM_BY_ID['cmp.ratio'],
  knee: PARAM_BY_ID['cmp.knee'],
  range: PARAM_BY_ID['cmp.range'],
  hold: PARAM_BY_ID['cmp.hold'],
  mix: PARAM_BY_ID['cmp.mix'],
  link: PARAM_BY_ID['cmp.link'],
  schpf: PARAM_BY_ID['cmp.schpf'],
};

let panel: HTMLElement;
let anchor: HTMLElement;
let tBox: HTMLElement;
let tCanvas: HTMLCanvasElement;
let lBox: HTMLElement;
let lCanvas: HTMLCanvasElement;
let bars: LevelBars;
let bypassBtn: HTMLElement;
let auditBtn: HTMLElement;
let scaleBtn: HTMLElement;
const cells = new Map<string, { root: HTMLElement; value: HTMLElement }>();
const fieldEls = new Map<string, HTMLElement>();

// RATIO подсвечивается только при изменении в окне (внешних источников у него нет, UNDO не подсвечивает).
const hotT = new HotTracker(Object.values(P), ['cmp.ratio']);
const freeze = new Freeze(compTele);

const numInput = (el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string) => numInputIn(panel, anchor, el, p, parse, init);

/** Статическая кривая: GR (dB ≥ 0) на уровне входа L по THRESHOLD, RATIO, KNEE, RANGE — как в glue-worklet.js. */
export function staticGr(L: number, thr: number, ratio: number, knee: number, range: number): number {
  const s = 1 - 1 / Math.max(1, ratio);
  const x = L - thr;
  let gr: number;
  if (knee <= 0) gr = x > 0 ? s * x : 0;
  else if (x < -knee / 2) gr = 0;
  else if (x <= knee / 2) gr = (s * (x + knee / 2) ** 2) / (2 * knee);
  else gr = s * x;
  return range >= CMP_RANGE_OFF ? gr : Math.min(gr, range);
}
/** Кривая по значениям кадра (параметры читаются один раз за кадр). */
let curve = { thr: -10, ratio: 2, knee: 6, range: CMP_RANGE_OFF };
const curveGr = (L: number) => staticGr(L, curve.thr, curve.ratio, curve.knee, curve.range);

/** Следующий пресет RATIO по тапу: 2 → 4 → 10 → 2 (выше 10 — 2; 3.3 — 4). */
export const nextRatio = (r: number) => RATIOS.find((x) => x > r + 1e-3) ?? RATIOS[0];

// ---------- Построение ----------

/** Поле нижней панели по положению параметра (0..1): вертикальный ход 240 px на весь диапазон, удержание — ввод числом. */
function normField(label: string, p: ParamDef, parse: (t: string) => number | null, init: () => string, onTap?: () => void) {
  const f = dragField(label, () => Math.round(toNorm(p, val(p)) * FIELD_UNITS),
    (v) => setParamNorm('master', p, Math.min(1, Math.max(0, v / FIELD_UNITS))), () => fmt(p), FIELD_PX,
    onTap ? () => onTap() : undefined, (el) => numInput(el, p, parse, init()));
  f.classList.add('eq-field', 'comp-field');
  fieldEls.set(p.id, f);
  return f;
}

export function buildCompWindow(): HTMLElement {
  panel = h('div', 'eq-panel lim-panel comp-panel hidden');
  anchor = h('div', 'eq-anchor');

  // Строка значений вверху (как ряд EQ): только показ; RATIO — за чертой (не ручка); крестик справа.
  const strip = h('div', 'eq-bar lim-strip comp-strip');
  strip.append(h('div', 'eq-name', 'MASTER\nCOMP'));
  for (const [key, label] of [['cmp.threshold', 'THRESHOLD'], ['cmp.attack', 'ATTACK'], ['cmp.release', 'RELEASE'], ['cmp.makeup', 'MAKEUP'], ['cmp.ratio', 'RATIO']] as const) {
    if (key === 'cmp.ratio') strip.append(h('div', 'comp-sep'));
    const root = h('div', 'field eq-field lim-cell');
    const value = h('div', 'field-value');
    root.append(h('div', 'field-label', label), value);
    cells.set(key, { root, value });
    strip.append(root);
  }
  strip.append(closeButton(closeCompWindow));

  // TRANSFER: точка порога (палец — вдоль диагонали, значение по горизонтали) и кружок RATIO (вертикально).
  tBox = h('div', 'eq-plot comp-transfer');
  tCanvas = document.createElement('canvas');
  tCanvas.className = 'eq-canvas';
  tBox.append(tCanvas, h('div', 'comp-plot-title', 'TRANSFER'));
  const tDrag = new Map<number, { kind: 'thr' | 'ratio'; x0: number; y0: number; v0: number }>();
  tCanvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const r = tCanvas.getBoundingClientRect();
    const x = e.clientX - r.left;
    const y = e.clientY - r.top;
    const hr = ratioHandle(r.width, r.height);
    const thr = val(P.threshold);
    const tx = xOf(thr, r.width);
    const ty = yOf(thr, r.height);
    let kind: 'thr' | 'ratio' | null = null;
    if (Math.hypot(x - hr.x, y - hr.y) <= Math.max(LINE_HIT, RATIO_HANDLE / 2 + 8)) kind = 'ratio';
    else if (Math.hypot(x - tx, y - ty) <= LINE_HIT + 6) kind = 'thr';
    if (!kind) return;
    tCanvas.setPointerCapture(e.pointerId);
    tDrag.set(e.pointerId, { kind, x0: e.clientX, y0: e.clientY, v0: kind === 'thr' ? thr : hr.y });
    hotT.hold(e.pointerId, kind === 'thr' ? 'cmp.threshold' : 'cmp.ratio');
    beginGesture();
  });
  tCanvas.addEventListener('pointermove', (e) => {
    const d = tDrag.get(e.pointerId);
    if (!d) return;
    const r = tCanvas.getBoundingClientRect();
    const scale = settings.limScale;
    if (d.kind === 'thr') {
      // Вдоль диагонали: значение — по горизонтали (вверх-вниз тоже двигает — точка лежит на диагонали).
      const dx = ((e.clientX - d.x0) / r.width) * scale;
      const dy = (-(e.clientY - d.y0) / r.height) * scale;
      setVal(P.threshold, d.v0 + (Math.abs(dx) >= Math.abs(dy) ? dx : dy));
      return;
    }
    // RATIO: выход на 0 dB по высоте кружка; ratio = (0 − thr) / (out0 − thr).
    const thr = val(P.threshold);
    if (-thr < 0.5) return;
    const out0 = Math.min(0, -((d.v0 + e.clientY - d.y0) / r.height) * scale);
    setVal(P.ratio, -thr / Math.max(1e-3, out0 - thr));
  });
  const tUp = (e: PointerEvent) => {
    if (!tDrag.delete(e.pointerId)) return;
    hotT.release(e.pointerId);
    endGesture();
  };
  tCanvas.addEventListener('pointerup', tUp);
  tCanvas.addEventListener('pointercancel', tUp);

  // LEVEL: пунктир THRESHOLD тянется (±22 px, приоритет выше FREEZE), иначе тап — FREEZE.
  lBox = h('div', 'eq-plot lim-plot comp-level');
  lCanvas = document.createElement('canvas');
  lCanvas.className = 'eq-canvas';
  lBox.append(lCanvas);
  const lDrag = new Map<number, { y0: number; v0: number; moved: boolean }>();
  lCanvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    lCanvas.setPointerCapture(e.pointerId);
    const r = lCanvas.getBoundingClientRect();
    if (Math.abs(e.clientY - r.top - yOf(val(P.threshold), r.height)) <= LINE_HIT) {
      lDrag.set(e.pointerId, { y0: e.clientY, v0: val(P.threshold), moved: false });
      hotT.hold(e.pointerId, 'cmp.threshold');
      beginGesture();
    } else lDrag.set(e.pointerId, { y0: e.clientY, v0: NaN, moved: false });
  });
  lCanvas.addEventListener('pointermove', (e) => {
    const d = lDrag.get(e.pointerId);
    if (!d) return;
    if (Math.abs(e.clientY - d.y0) > 6) d.moved = true;
    if (Number.isNaN(d.v0)) return;
    setVal(P.threshold, d.v0 - ((e.clientY - d.y0) / lCanvas.getBoundingClientRect().height) * settings.limScale);
  });
  const lUp = (e: PointerEvent) => {
    const d = lDrag.get(e.pointerId);
    if (!d) return;
    lDrag.delete(e.pointerId);
    if (!Number.isNaN(d.v0)) { hotT.release(e.pointerId); endGesture(); return; }
    if (!d.moved && e.type === 'pointerup') freeze.set(!freeze.on);
  };
  lCanvas.addEventListener('pointerup', lUp);
  lCanvas.addEventListener('pointercancel', lUp);

  // Блок COMP — тот же компонент и данные, что слева; IN и OUT — по SCALE.
  bars = new LevelBars(glueBars({ levelLo: () => -settings.limScale }));
  bars.el.classList.add('lim-bars');

  const mid = h('div', 'lim-mid');
  mid.append(tBox, lBox, bars.el);

  // Нижняя панель: две строки полей и кнопок.
  const msInit = (p: ParamDef) => () => { const v = val(p); return v < 10 ? v.toFixed(1) : String(Math.round(v)); };
  const relInit = () => (isAuto(val(P.release)) ? 'AUTO' : String(Math.round(val(P.release))));
  const offParse = (off: number) => (t: string) => (/off/i.test(t) ? off : num(t));
  const row1 = h('div', 'comp-row');
  row1.append(
    normField('ATTACK', P.attack, num, msInit(P.attack)),
    normField('RELEASE', P.release, (t) => parseRelease(t, P.release.max), relInit),
    normField('MAKEUP', P.makeup, num, () => val(P.makeup).toFixed(1)),
    normField('RATIO', P.ratio, num, () => val(P.ratio).toFixed(1), () => {
      hotT.touch('cmp.ratio');
      beginGesture();
      setVal(P.ratio, nextRatio(val(P.ratio)));
      endGesture();
    }),
    normField('KNEE', P.knee, num, () => val(P.knee).toFixed(1)),
    normField('RANGE', P.range, offParse(CMP_RANGE_OFF), () => (val(P.range) >= CMP_RANGE_OFF ? 'OFF' : val(P.range).toFixed(1))),
    normField('HOLD', P.hold, num, () => String(Math.round(val(P.hold)))),
  );
  const btn = (label: string, fn: () => void) => {
    const b = h('div', 'btn eq-tool lim-btn comp-btn', label);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return b;
  };
  bypassBtn = btn('BYPASS', () => toggleCmpBypass());
  auditBtn = btn('AUDIT', () => { ui.compAudit = !ui.compAudit; });
  scaleBtn = btn('SCALE', () => {
    const k = SCALES.indexOf(settings.limScale);
    saveSettings({ limScale: SCALES[(k + 1) % SCALES.length] });
  });
  const row2 = h('div', 'comp-row');
  row2.append(
    normField('MIX', P.mix, num, () => String(Math.round(val(P.mix)))),
    normField('LINK', P.link, num, () => String(Math.round(val(P.link)))),
    normField('SC HPF', P.schpf, offParse(CMP_SCHPF_OFF), () => (val(P.schpf) <= CMP_SCHPF_OFF ? 'OFF' : String(Math.round(val(P.schpf))))),
    bypassBtn, auditBtn, scaleBtn,
  );
  const bottom = h('div', 'comp-bottom');
  bottom.append(row1, row2);

  panel.append(strip, mid, bottom, anchor);
  return panel;
}

/** Крестик и выход из MST: окно закрывается, AUDIT выключается (toggleView), FREEZE снимается. */
export function closeCompWindow() {
  if (ui.compView) toggleView('comp');
  freeze.set(false);
}

// ---------- Отрисовка ----------

/** dB → y (верх 0 dBFS, низ −SCALE) и dB → x на TRANSFER (слева −SCALE, справа 0). */
const yOf = (db: number, H: number) => Math.min(H, Math.max(0, (-db / settings.limScale) * H));
const xOf = (db: number, W: number) => Math.min(W, Math.max(0, (1 + db / settings.limScale) * W));
/** Кружок RATIO: на правом краю, на высоте выхода при входе 0 dB (без колена и RANGE). */
function ratioHandle(W: number, H: number) {
  const thr = val(P.threshold);
  const out0 = thr + (0 - thr) / Math.max(1, val(P.ratio));
  return { x: W - RATIO_HANDLE / 2 - 2, y: yOf(out0, H) };
}

export function renderCompWindow(now: number) {
  // Выход из MST закрывает окно.
  if (ui.compView && ui.channel !== 'master') closeCompWindow();
  setClass(panel, 'hidden', !ui.compView);
  if (!ui.compView) return;

  hotT.update(now, [...fieldEls].filter(([, f]) => f.classList.contains('active')).map(([id]) => id));
  const hot = (id: string) => hotT.hot(id, now);
  const bypass = doc.cmpBypass;
  for (const [id, c] of cells) {
    setText(c.value, fmt(PARAM_BY_ID[id]));
    setClass(c.root, 'hot', hot(id));
    setClass(c.root, 'off', bypass);
  }
  for (const [id, f] of fieldEls) setClass(f, 'hot', hot(id));
  setClass(bypassBtn, 'active', bypass);
  setClass(auditBtn, 'active', ui.compAudit);
  setText(scaleBtn, `SCALE ${settings.limScale}`);
  bars.render(now);
  curve = { thr: val(P.threshold), ratio: val(P.ratio), knee: val(P.knee), range: val(P.range) };
  const live = now - compTele.at < 300;
  drawTransfer(hot, live);
  drawLevel(hot, live);
}

/** Пунктирная линия порога (белая; в светлой теме — чёрная). */
function dashed(g: CanvasRenderingContext2D, x0: number, y0: number, x1: number, y1: number, on: boolean) {
  g.save();
  g.strokeStyle = on ? color('--accent') : color('--meter-thr');
  g.lineWidth = on ? 1.5 : 1;
  g.setLineDash([4, 4]);
  g.beginPath();
  g.moveTo(x0, y0);
  g.lineTo(x1, y1);
  g.stroke();
  g.restore();
}

function drawTransfer(hot: (id: string) => boolean, live: boolean) {
  const f = fitCanvas(tCanvas, tBox);
  if (!f) return;
  const { g, W, H } = f;
  const scale = settings.limScale;
  const thr = val(P.threshold);
  const knee = val(P.knee);
  const bypass = doc.cmpBypass;
  // Сетка: горизонтали — как у LEVEL (та же шкала), вертикали — те же деления по входу.
  drawDbGrid(g, W, H, scale);
  const step = scale === 48 ? 6 : scale === 32 ? 4 : 2;
  g.fillStyle = color('--line');
  for (let db = -step; db > -scale; db -= step) g.fillRect(Math.round(xOf(db, W)) + 0.5, 0, 1, H);
  // Колено: полупрозрачная серая полоса шириной KNEE вокруг порога.
  if (knee > 0) {
    g.fillStyle = color('--lim-in');
    const a = xOf(thr - knee / 2, W), b = xOf(thr + knee / 2, W);
    g.fillRect(a, 0, b - a, H);
  }
  // Диагональ 1:1.
  g.strokeStyle = color('--dim');
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(0, H);
  g.lineTo(W, 0);
  g.stroke();
  // Кривая передачи (без MAKEUP).
  const pts: [number, number][] = [];
  for (let x = 0; x <= W; x++) {
    const L = -scale + (x / W) * scale;
    pts.push([x, yOf(L - curveGr(L), H)]);
  }
  g.strokeStyle = bypass ? color('--dim') : color('--text');
  g.lineWidth = 1.5;
  g.beginPath();
  pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y)));
  g.stroke();
  // Пунктир порога по вертикали и горизонтали — пересекаются в точке порога.
  const tx = xOf(thr, W), ty = yOf(thr, H);
  const thrHot = hot('cmp.threshold');
  dashed(g, tx, 0, tx, H, thrHot);
  dashed(g, 0, ty, W, ty, thrHot);
  // Живая точка: уровень детектора последнего кадра — на кривой. Компрессия: участок кривой от порога до места,
  // где статическое GR равно текущему GR (то же число, что на стержне GR и на LEVEL), — оранжевый.
  const last = (compTele.n - 1 + LIM_TELE) % LIM_TELE;
  const has = live && compTele.n > 0;
  const det = has ? compTele.det[last] : -200;
  const grNow = has ? compTele.gr[last] : 0;
  if (!bypass && grNow > 0.05) {
    const a = Math.max(0, Math.floor(xOf(thr - knee / 2, W)));
    let b = a;
    while (b < W && curveGr(-scale + (b / W) * scale) < grNow) b++;
    g.strokeStyle = color('--meter-gr');
    g.lineWidth = 2.5;
    g.beginPath();
    for (let x = a; x <= b; x++) (x === a ? g.moveTo(pts[x][0], pts[x][1]) : g.lineTo(pts[x][0], pts[x][1]));
    g.stroke();
  }
  if (!bypass && det > -scale) {
    g.fillStyle = color('--text');
    g.beginPath();
    g.arc(xOf(det, W), yOf(det - curveGr(det), H), 3, 0, 2 * Math.PI);
    g.fill();
  }
  // Точка порога (тянется) и кружок RATIO на правом краю.
  g.fillStyle = thrHot ? color('--accent') : color('--meter-thr');
  g.beginPath();
  g.arc(tx, ty, thrHot ? 6 : 5, 0, 2 * Math.PI);
  g.fill();
  const hr = ratioHandle(W, H);
  const rHot = hot('cmp.ratio');
  g.lineWidth = 1.5;
  g.strokeStyle = rHot ? color('--accent') : color('--text');
  g.fillStyle = color('--panel');
  g.beginPath();
  g.arc(hr.x, hr.y, RATIO_HANDLE / 2 - 1, 0, 2 * Math.PI);
  g.fill();
  g.stroke();
  g.fillStyle = rHot ? color('--accent') : color('--text');
  g.font = '9px -apple-system, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  const r = val(P.ratio);
  g.fillText(r < 9.95 ? r.toFixed(1) : String(Math.round(r)), hr.x, hr.y);
}

function drawLevel(hot: (id: string) => boolean, live: boolean) {
  const f = fitCanvas(lCanvas, lBox);
  if (!f) return;
  const { g, W, H } = f;
  const scale = settings.limScale;
  drawDbGrid(g, W, H, scale);
  const cols = Math.max(1, Math.floor(W));
  const { inDb, outDb, grDb } = historyColumns(freeze.tele, cols, freeze.on || live);
  const bypass = doc.cmpBypass;
  const area = (data: Float32Array) => {
    g.beginPath();
    g.moveTo(0, H);
    for (let x = 0; x < cols; x++) g.lineTo(x, yOf(data[x], H));
    g.lineTo(cols, H);
    g.closePath();
  };
  const line = (data: Float32Array) => {
    g.beginPath();
    for (let x = 0; x < cols; x++) { const y = yOf(data[x], H); if (x) g.lineTo(x, y); else g.moveTo(x, y); }
  };
  // Вход до компрессора — серая заливка с тонким серым контуром.
  area(inDb);
  g.fillStyle = color('--lim-in');
  g.fill();
  g.strokeStyle = color('--dim');
  g.lineWidth = 1;
  g.stroke();
  // Выход после MAKEUP — жёлтый контур 1.5 px и полупрозрачная жёлтая заливка.
  area(outDb);
  g.fillStyle = color('--comp-out-fill');
  g.fill();
  line(outDb);
  g.strokeStyle = color('--meter-ok');
  g.lineWidth = 1.5;
  g.stroke();
  // GR — оранжевая линия с лёгкой заливкой, свисает от верхней кромки.
  if (!bypass) {
    const gy = (x: number) => Math.min(H, (grDb[x] / scale) * H);
    g.beginPath();
    g.moveTo(0, 0);
    for (let x = 0; x < cols; x++) g.lineTo(x, gy(x));
    g.lineTo(cols, 0);
    g.closePath();
    g.fillStyle = color('--comp-gr-fill');
    g.fill();
    g.beginPath();
    for (let x = 0; x < cols; x++) (x ? g.lineTo(x, gy(x)) : g.moveTo(x, gy(x)));
    g.strokeStyle = color('--meter-gr');
    g.lineWidth = 1.5;
    g.stroke();
    drawGrPeaks(g, grDb, W, H, scale, PEAK_GAP_MS);
  }
  // Пунктир THRESHOLD — на той же высоте, что на TRANSFER.
  const ty = yOf(val(P.threshold), H);
  dashed(g, 0, ty, W, ty, hot('cmp.threshold'));
  g.fillStyle = hot('cmp.threshold') ? color('--accent') : color('--meter-thr');
  g.font = '11px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = ty > 16 ? 'bottom' : 'top';
  g.fillText(val(P.threshold).toFixed(1), W - 6, ty > 16 ? ty - 3 : ty + 3);
  g.fillStyle = color('--dim');
  g.font = '9px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = 'bottom';
  g.fillText('LEVEL', W - 6, H - 4);
  if (freeze.on) drawPauseLabel(g, 'FREEZE');
}
