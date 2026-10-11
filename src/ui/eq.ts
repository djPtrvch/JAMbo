// Графический эквалайзер (кнопка EQ): на месте центра экрана, размером как сетка паттернов.
// Показывает EQ выбранной дорожки, а при MIX и MST — мастера. 8 полос, по умолчанию их нет.
//
// Управление касанием: двойной тап по пустому месту — новая bell-полоса (частота по горизонтали,
// усиление по вертикали); точку тянут (у cut и notch — только частота); двойной тап по точке
// включает и выключает полосу; долгое нажатие — меню типа, крутизны среза и удаления.
// Внизу поля выбранной полосы: тип, Freq, Gain, Q (удержание — ввод числа; двойной тап по Q — сброс).
//
// Фон — сетка частот и уровней; спектр до EQ — серая линия, после — серая полупрозрачная
// заливка; суммарная кривая белая; точки полос белые с номерами,
// выбранная крупнее и жёлтая, выключенные серые. Анализаторы работают, только пока панель открыта.

import { bandResponse } from '../audio/eq';
import { eqDynDb, eqSampleRate, eqSpectrum, setEqScope } from '../audio/engine';
import {
  EQ_DYN_RANGE_DEF, EQ_DYN_THR_DEF, EQ_FREQ_MAX, EQ_FREQ_MIN, EQ_MS, EQ_Q_DEF, EQ_SLOPES, EQ_TYPE_ORDER, EQ_TYPES, eqDynOn, eqHasGain, eqIsCut, noteName,
} from '../params';
import {
  addEqBand, beginGesture, deleteEqBand, endGesture, eqTarget, eqTargetName, resetEq, selectedBand,
  setEqBand, setEqDyn, setEqDynParams, setEqMs, setEqSlope, setEqType, toggleEq, toggleEqBand, ui, doc, type EqBand,
  deleteEqPreset, eqPresets, loadEqPreset, nextEqPresetName, renameEqPreset, saveEqPreset,
} from '../state';
import { dragField } from './controls';
import { color } from './theme';
import { h, setClass, setText } from './dom';
import { makePopup, openInput, popupButton } from './popup';

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
/** Сдвиг динамической полосы k сейчас, dB (0 — не динамическая). */
function dynOff(b: EqBand, k: number): number {
  if (!eqDynOn(b) || !b.on) return 0;
  return eqDynDb()?.[k] ?? 0;
}
/** Точка полосы — с текущим сдвигом динамической полосы. */
const pointY = (b: EqBand, k = -1) => yOfGain(eqHasGain(b.type) ? b.gain + (k >= 0 ? dynOff(b, k) : 0) : 0);

function fmtHz(f: number): string {
  if (f < 1000) return `${f.toFixed(f < 100 ? 1 : 0)} Hz`;
  return `${(f / 1000).toFixed(f < 10000 ? 2 : 1)} kHz`;
}
const fmtGain = (g: number) => `${g > 0 ? '+' : ''}${g.toFixed(1)} dB`;
/** Частота из введённого текста: «440», «440 Hz», «1.5k», «2 kHz»; null — не число. */
function parseFreq(text: string): number | null {
  const m = text.trim().toLowerCase().replace(',', '.').match(/^([0-9]*\.?[0-9]+)\s*(k)?/);
  if (!m) return null;
  const v = parseFloat(m[1]) * (m[2] ? 1000 : 1);
  return Number.isFinite(v) && v > 0 ? v : null;
}
const noteOf = (f: number) => noteName(Math.max(0, Math.round(69 + 12 * Math.log2(f / 440))));

// ---------- Касания ----------

interface Touch {
  id: number; x: number; y: number; x0: number; y0: number;
  band: number; f0: number; g0: number;
  moved: boolean; menu: boolean; gesture: boolean; timer: number;
}
const touches = new Map<number, Touch>();
let lastTap: { t: number; x: number; y: number; band: number } | null = null;
let lastQTap = 0;

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
    const d = Math.hypot(xOf(b.freq) - x, pointY(b, k) - y) - (k === ui.eqBand ? 6 : 0);
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
  if (hit < 0) return;
  // Одну точку держит один палец.
  if ([...touches.values()].some((o) => o !== t && o.band === hit)) return;
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
menu.box.append(...EQ_TYPE_ORDER.map((i) => typeBtns[i]), ...slopeBtns, deleteBtn);
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

// ---------- Меню STEREO / MID / SIDE и DYN ----------

const msMenu = makePopup('eq-list');
const msScroll = h('div', 'eq-scroll one-col');
const msBtns = EQ_MS.map((name, i) => popupButton(name, () => { setEqMs(ui.eqBand, i); msMenu.close(); }));
msScroll.append(...msBtns);
msMenu.box.append(h('div', 'source-title', 'CHANNEL'), msScroll);

function openMsMenu(el: Element) {
  const b = selectedBand();
  if (!b) return;
  msBtns.forEach((btn, i) => btn.classList.toggle('current', i === (b.ms ?? 0)));
  msMenu.openAt(el, 200);
}

const dynMenu = makePopup('eq-list');
const dynScroll = h('div', 'eq-scroll');
const dynFields = h('div', 'eq-dyn-fields');
dynFields.append(
  dragField('THRESHOLD', () => Math.round((selectedBand()?.thr ?? EQ_DYN_THR_DEF) * 2),
    (v) => setEqDynParams(ui.eqBand, { thr: v / 2 }),
    () => `${(selectedBand()?.thr ?? EQ_DYN_THR_DEF).toFixed(1)} dB`, 3),
  dragField('RANGE', () => Math.round((selectedBand()?.range ?? EQ_DYN_RANGE_DEF) * 2),
    (v) => setEqDynParams(ui.eqBand, { range: v / 2 }),
    () => fmtGain(selectedBand()?.range ?? EQ_DYN_RANGE_DEF), 3),
);
for (const f of dynFields.children) f.classList.add('eq-field');
dynMenu.box.append(h('div', 'source-title', 'DYNAMIC · SOURCE'), dynScroll, dynFields);

/** Подпись источника динамической полосы. */
const dynName = (b: EqBand) => (!eqHasGain(b.type) ? '—' : !eqDynOn(b) ? 'OFF' : b.dyn === 0 ? 'SELF' : doc.tracks[b.dyn! - 1]?.name ?? `T${b.dyn}`);

function openDynMenu(el: Element) {
  const b = selectedBand();
  if (!b || !eqHasGain(b.type)) return;
  const items: [string, number][] = [['OFF', -1], ['SELF', 0], ...doc.tracks.map((t, i): [string, number] => [t.name, i + 1])];
  dynScroll.replaceChildren(...items.map(([name, v]) => {
    const btn = popupButton(name, () => { setEqDyn(ui.eqBand, v); for (const x of dynScroll.children) x.classList.toggle('current', x === btn); });
    btn.classList.toggle('current', (b.dyn ?? -1) === v || (v === -1 && !eqDynOn(b)));
    return btn;
  }));
  dynMenu.openAt(el, 300);
}

// ---------- Пресеты EQ ----------

const presetMenu = makePopup('eq-presets');
const presetActions = makePopup();
let presetAnchor: Element;
let actionK = -1;

presetActions.box.append(
  popupButton('RENAME', () => {
    presetActions.close();
    const k = actionK;
    openInput(presetMenu.box, eqPresets()[k]?.name ?? '', (n) => { renameEqPreset(k, n); openEqPresets(presetAnchor); });
  }),
  popupButton('DELETE', () => { presetActions.close(); deleteEqPreset(actionK); openEqPresets(presetAnchor); }),
);

function openEqPresets(anchor: Element) {
  presetAnchor = anchor;
  const list = eqPresets();
  const grid = h('div', 'preset-grid');
  list.forEach((p, k) => {
    let held = false;
    let timer = 0;
    const bands = p.eq.bands.filter((b) => b).length;
    const b = popupButton(`${p.name}\n${bands} band${bands === 1 ? '' : 's'}`, () => {
      if (held) return;
      loadEqPreset(k);
      presetMenu.close();
    });
    b.addEventListener('pointerdown', () => {
      held = false;
      timer = window.setTimeout(() => { held = true; actionK = k; presetActions.openAt(b, 160); }, 500);
    });
    for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) b.addEventListener(ev, () => clearTimeout(timer));
    grid.append(b);
  });
  if (!list.length) grid.append(h('div', 'preset-empty', 'No EQ presets yet — save one with SAVE'));
  const save = popupButton('SAVE', () => {
    presetMenu.close();
    openInput(anchor, nextEqPresetName(), (n) => saveEqPreset(n));
  });
  presetMenu.box.replaceChildren(h('div', 'source-title', `EQ PRESETS · ${list.length}`), save, grid);
  presetMenu.openAt(anchor, 340);
}

/** Число из введённого текста (запятая — как точка); null — не число. */
function parseNum(text: string): number | null {
  const v = parseFloat(text.trim().replace(',', '.'));
  return Number.isFinite(v) ? v : null;
}

/**
 * Ввод значения выбранной полосы числом (Freq, Gain, Q) — окно внутри поля эквалайзера, вверху
 * (по горизонтали — над полем): нижнюю часть экрана на iPad закрывает клавиатура.
 */
function numInput(el: HTMLElement, field: 'freq' | 'gain' | 'q') {
  const b = selectedBand();
  const k = ui.eqBand;
  if (!b || (field === 'gain' && !eqHasGain(b.type))) return;
  const r = el.getBoundingClientRect();
  const p = plot.getBoundingClientRect();
  anchor.style.left = `${r.left + r.width / 2 - p.left}px`;
  anchor.style.top = "12px";
  const init = field === 'freq' ? String(Math.round(b.freq)) : field === 'gain' ? b.gain.toFixed(1) : b.q.toFixed(2);
  openInput(anchor, init, (v) => {
    const n = field === 'freq' ? parseFreq(v) : parseNum(v);
    if (n === null) return;
    if (field === 'q' && n <= 0) return;
    setEqBand(k, { [field]: n });
  }, true);
}
const freqInput = (el: HTMLElement) => numInput(el, 'freq');

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
    // Вертикальное движение идёт по порядку меню (EQ_TYPE_ORDER): палец вниз — следующий тип.
    'TYPE', () => -EQ_TYPE_ORDER.indexOf(selectedBand()?.type ?? 0),
    (v) => setEqType(k(), EQ_TYPE_ORDER[((-v % EQ_TYPE_ORDER.length) + EQ_TYPE_ORDER.length) % EQ_TYPE_ORDER.length]),
    () => { const b = selectedBand(); return b ? EQ_TYPES[b.type].name + (eqIsCut(b.type) ? ` ${EQ_SLOPES[b.slope]}` : '') : '—'; },
    30, (el) => { if (selectedBand()) { const r = el.getBoundingClientRect(), p = plot.getBoundingClientRect(); openBandMenu(k(), r.left + r.width / 2 - p.left, r.top - p.top); } },
  );
  const freqField = dragField(
    'FREQ', () => Math.round(Math.log2((selectedBand()?.freq ?? 1000) / EQ_FREQ_MIN) * 24),
    (v) => setEqBand(k(), { freq: EQ_FREQ_MIN * Math.pow(2, v / 24) }),
    () => { const b = selectedBand(); return b ? fmtHz(b.freq) : '—'; }, 2,
    // Тап (в момент отпускания — iOS показывает клавиатуру) и удержание — ввод частоты числом
    // (Гц; «1.5k» — килогерцы).
    (el) => freqInput(el), (el) => freqInput(el),
  );
  const gainField = dragField(
    'GAIN', () => Math.round((selectedBand()?.gain ?? 0) * 10),
    (v) => { const b = selectedBand(); if (b && eqHasGain(b.type)) setEqBand(k(), { gain: v / 10 }); },
    () => { const b = selectedBand(); return b && eqHasGain(b.type) ? fmtGain(b.gain) : '—'; }, 1,
    // Удержание — ввод усиления числом (dB).
    undefined, (el) => numInput(el, 'gain'),
  );
  const qField = dragField(
    'Q', () => Math.round(Math.log2(selectedBand()?.q ?? 1) * 12),
    (v) => setEqBand(k(), { q: Math.pow(2, v / 12) }),
    () => { const b = selectedBand(); return b ? b.q.toFixed(2) : '—'; }, 3,
    () => {
      // Двойной тап по Q — сброс к значению по умолчанию.
      const now = performance.now();
      if (now - lastQTap < DOUBLE_MS && selectedBand()) { setEqBand(k(), { q: EQ_Q_DEF }); lastQTap = 0; }
      else lastQTap = now;
    },
    // Удержание — ввод Q числом.
    (el) => numInput(el, 'q'),
  );
  // STEREO / MID / SIDE: тап — меню, палец вниз — следующий режим.
  const msField = dragField(
    'M/S', () => -(selectedBand()?.ms ?? 0),
    (v) => setEqMs(k(), ((-v % 3) + 3) % 3),
    () => { const b = selectedBand(); return b ? EQ_MS[b.ms ?? 0] : '—'; }, 30,
    (el) => openMsMenu(el),
  );
  // DYN: тап — меню источника (OFF, SELF, дорожки) с THRESHOLD и RANGE.
  const dynField = dragField(
    'DYN', () => 0, () => { /* только тап */ },
    () => { const b = selectedBand(); return b ? dynName(b) : '—'; }, 1000,
    (el) => openDynMenu(el),
  );
  for (const f of [typeField, freqField, gainField, qField, msField, dynField]) f.classList.add('eq-field');
  bypassBtn = h('div', 'btn eq-tool', 'BYPASS');
  bypassBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); toggleEq(); });
  const resetBtn = h('div', 'btn eq-tool', 'RESET');
  resetBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); resetEq(); });
  // PRESETS — библиотека пресетов EQ: SAVE (сохранить EQ канала), тап по пресету — загрузить,
  // удержание — RENAME / DELETE.
  const presetBtn = h('div', 'btn eq-tool', 'PRESETS');
  presetBtn.addEventListener('pointerup', () => openEqPresets(presetBtn));
  bar.append(nameText, typeField, freqField, gainField, qField, msField, dynField, presetBtn, bypassBtn, resetBtn);

  panel.append(plot, bar);
  return panel;
}

// ---------- Отрисовка ----------

let freqs = new Float32Array(0);
/** Суммарные кривые: стерео-полосы, середина (стерео + MID), бока (стерео + SIDE). */
let curve = new Float32Array(0);
let curveMid = new Float32Array(0);
let curveSide = new Float32Array(0);
let band = new Float32Array(0);
let curveSig = '';
let hasMid = false;
let hasSide = false;
let hasStereo = false;
const pre = new Float32Array(2048);
const post = new Float32Array(2048);
const STEP = 2;

/** Суммарные кривые EQ по точкам через STEP пикселей (с текущим сдвигом динамических полос; пересчёт только при изменениях). */
function updateCurve() {
  const eq = eqTarget();
  const n = Math.ceil(W / STEP) + 1;
  const sr = eqSampleRate();
  const offs = eq.bands.map((b, k) => (b ? dynOff(b, k).toFixed(1) : '')).join(',');
  const sig = `${n}|${sr}|${JSON.stringify(eq)}|${offs}`;
  if (sig === curveSig) return;
  curveSig = sig;
  if (freqs.length !== n) {
    freqs = new Float32Array(n);
    curve = new Float32Array(n);
    curveMid = new Float32Array(n);
    curveSide = new Float32Array(n);
    band = new Float32Array(n);
  }
  for (let i = 0; i < n; i++) freqs[i] = Math.min(sr / 2, freqAt(i * STEP));
  curve.fill(0);
  curveMid.fill(0);
  curveSide.fill(0);
  hasMid = hasSide = hasStereo = false;
  eq.bands.forEach((b, k) => {
    if (!b || !b.on) return;
    const off = dynOff(b, k);
    bandResponse(off ? { ...b, gain: b.gain + off } : b, freqs, band, sr);
    const ms = b.ms ?? 0;
    if (ms === 0) hasStereo = true;
    if (ms === 1) hasMid = true;
    if (ms === 2) hasSide = true;
    for (let i = 0; i < n; i++) {
      if (ms === 0) curve[i] += band[i];
      if (ms !== 2) curveMid[i] += band[i];
      if (ms !== 1) curveSide[i] += band[i];
    }
  });
}

function drawGrid(g: CanvasRenderingContext2D) {
  g.lineWidth = 1;
  for (let d = 10; d <= 10000; d *= 10) {
    for (let m = 1; m <= 9; m++) {
      const f = d * m;
      if (f < EQ_FREQ_MIN || f > EQ_FREQ_MAX) continue;
      const x = Math.round(xOf(f)) + 0.5;
      g.strokeStyle = m === 1 ? color('--grid-strong') : color('--grid');
      g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke();
    }
  }
  for (let db = -18; db <= 18; db += 6) {
    const y = Math.round(yOfGain(db)) + 0.5;
    g.strokeStyle = db === 0 ? color('--grid-strong') : color('--grid');
    g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke();
  }
  g.fillStyle = color('--dim');
  g.font = '11px -apple-system, sans-serif';
  g.textBaseline = 'bottom';
  for (const [f, s] of [[100, '100 Hz'], [1000, '1 kHz'], [10000, '10 kHz']] as const) g.fillText(s, xOf(f) + 4, H - 4);
  g.textBaseline = 'middle';
  for (const db of [12, 0, -12]) g.fillText(`${db > 0 ? '+' : ''}${db} dB`, 6, yOfGain(db) - 8);
}

// ---------- Спектр (плавный, как в FabFilter) ----------

/** Шаг столбцов спектра, px. */
const SPEC_STEP = 3;
/** Ширина усреднения — 1/6 октавы. */
const SPEC_BAND = Math.pow(2, 1 / 12);
/** Спад, dB/с (подъём — сразу). */
const SPEC_FALL = 30;
const cumPre = new Float64Array(2049);
const cumPost = new Float64Array(2049);
let dispPre = new Float32Array(0);
let dispPost = new Float32Array(0);
let specT = 0;

/** Накопленная сумма мощности по бинам (для среднего по полосе). */
function cumulate(data: Float32Array, cum: Float64Array) {
  cum[0] = 0;
  for (let i = 0; i < data.length; i++) cum[i + 1] = cum[i] + Math.pow(10, data[i] / 10);
}

/** Средняя мощность (dB) между частотами f0 и f1, с долями крайних бинов. */
function bandDb(cum: Float64Array, f0: number, f1: number, binHz: number): number {
  const n = cum.length - 1;
  const at = (f: number) => {
    const p = Math.min(n, Math.max(0, f / binHz + 0.5));
    const i = Math.min(n - 1, Math.floor(p));
    return cum[i] + (cum[i + 1] - cum[i]) * (p - i);
  };
  const w = Math.max(1e-3, (f1 - f0) / binHz);
  return 10 * Math.log10(Math.max(1e-12, (at(f1) - at(f0)) / w));
}

/** Плавная линия через точки (квадратичные кривые через середины отрезков). */
function smoothPath(g: CanvasRenderingContext2D, ys: Float32Array, start: boolean) {
  const n = ys.length;
  if (start) g.moveTo(0, ys[0]); else g.lineTo(0, ys[0]);
  for (let i = 1; i < n - 1; i++) {
    const x = i * SPEC_STEP;
    g.quadraticCurveTo(x, ys[i], x + SPEC_STEP / 2, (ys[i] + ys[i + 1]) / 2);
  }
  g.lineTo((n - 1) * SPEC_STEP, ys[n - 1]);
}

function drawSpectrum(g: CanvasRenderingContext2D) {
  if (!eqSpectrum(pre, post)) return;
  const now = performance.now();
  const dt = Math.min(0.1, (now - specT) / 1000);
  specT = now;
  const binHz = eqSampleRate() / 4096;
  cumulate(pre, cumPre);
  cumulate(post, cumPost);
  const n = Math.ceil(W / SPEC_STEP) + 1;
  if (dispPre.length !== n) { dispPre = new Float32Array(n).fill(SPEC_BOT); dispPost = new Float32Array(n).fill(SPEC_BOT); }
  const yPre = new Float32Array(n);
  const yPost = new Float32Array(n);
  const fall = SPEC_FALL * dt;
  for (let i = 0; i < n; i++) {
    const f = freqAt(i * SPEC_STEP);
    const a = Math.max(SPEC_BOT, bandDb(cumPre, f / SPEC_BAND, f * SPEC_BAND, binHz));
    const b = Math.max(SPEC_BOT, bandDb(cumPost, f / SPEC_BAND, f * SPEC_BAND, binHz));
    dispPre[i] = a > dispPre[i] ? a : Math.max(a, dispPre[i] - fall);
    dispPost[i] = b > dispPost[i] ? b : Math.max(b, dispPost[i] - fall);
    yPre[i] = yOfSpec(dispPre[i]);
    yPost[i] = yOfSpec(dispPost[i]);
  }
  // После EQ — серая полупрозрачная заливка.
  g.beginPath();
  g.moveTo(0, H);
  smoothPath(g, yPost, false);
  g.lineTo(W, H);
  g.closePath();
  g.fillStyle = color('--dim');
  g.globalAlpha = 0.22;
  g.fill();
  g.globalAlpha = 1;
  // До EQ — серая линия.
  g.beginPath();
  smoothPath(g, yPre, true);
  g.strokeStyle = color('--dim');
  g.globalAlpha = 0.6;
  g.lineWidth = 1.2;
  g.lineJoin = 'round';
  g.stroke();
  g.globalAlpha = 1;
}

function strokeCurve(g: CanvasRenderingContext2D, c: Float32Array, col: string, alpha: number) {
  g.beginPath();
  for (let i = 0; i < c.length; i++) {
    const y = yOfGain(Math.max(-DB_RANGE * 1.2, Math.min(DB_RANGE * 1.2, c[i])));
    (i ? g.lineTo : g.moveTo).call(g, i * STEP, y);
  }
  g.strokeStyle = col;
  g.globalAlpha = alpha;
  g.lineWidth = 2;
  g.stroke();
  g.globalAlpha = 1;
}

/**
 * Кривые: белая — стерео-полосы; при полосах MID/SIDE ещё кривые середины (стерео + MID) и боков
 * (стерео + SIDE) их цветами.
 */
function drawCurve(g: CanvasRenderingContext2D, on: boolean) {
  updateCurve();
  const a = on ? 1 : 0.35;
  if (hasStereo || (!hasMid && !hasSide)) strokeCurve(g, curve, color('--ink'), a);
  if (hasMid) strokeCurve(g, curveMid, color('--eq-mid'), a);
  if (hasSide) strokeCurve(g, curveSide, color('--eq-side'), a);
}

/** Цвет точки по режиму: STEREO — белая, MID — красная, SIDE — оранжевая (цвета интерфейса). */
const msColor = (b: EqBand) => color((b.ms ?? 0) === 1 ? '--eq-mid' : (b.ms ?? 0) === 2 ? '--eq-side' : '--ink');

function drawPoints(g: CanvasRenderingContext2D) {
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  eqTarget().bands.forEach((b, k) => {
    if (!b) return;
    const sel = k === ui.eqBand;
    const r = sel ? 13 : 10;
    const x = xOf(b.freq);
    const y = pointY(b, k);
    // Динамическая полоса: на месте статического усиления — полое кольцо.
    if (eqDynOn(b) && b.on) {
      g.beginPath();
      g.arc(x, pointY(b), r - 1, 0, Math.PI * 2);
      g.strokeStyle = msColor(b);
      g.lineWidth = 1.5;
      g.globalAlpha = 0.7;
      g.stroke();
      g.globalAlpha = 1;
    }
    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fillStyle = !b.on ? color('--mute-grey') : sel ? color('--accent') : msColor(b);
    g.fill();
    // Выбранная MID/SIDE — жёлтая с кольцом цвета режима.
    if (sel && b.on && (b.ms ?? 0) > 0) {
      g.beginPath();
      g.arc(x, y, r + 2.5, 0, Math.PI * 2);
      g.strokeStyle = msColor(b);
      g.lineWidth = 3;
      g.stroke();
    }
    g.fillStyle = sel ? color('--on-accent') : color('--bg');
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
