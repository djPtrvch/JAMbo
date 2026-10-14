// Окно клиппера мастера (этап 7): тап по блоку CLIP при MST (или по кнопке CLIP). На месте EQ (от левого края до края
// миниатюр страниц, справа — общий измеритель). INPUT, CEILING, SOFTNESS, BASS — те же параметры, что у ручек 3.1–3.4
// в MST (и MIDI по позиции); MIX — только в окне. Нижней панели нет. Сверху вниз:
// — строка (как ряд EQ): поля INPUT, CEILING, SOFTNESS, BASS | MIX (палец вверх-вниз, удержание — ввод числом),
//   кнопки VIEW, UNITY, AUDIT, BYPASS и крестик; поле, которое меняют, — в жёлтой рамке и ещё 400 ms;
// — TRANSFER (кривая передачи, −30…0 dB; угол тянется пальцем: по горизонтали INPUT, по вертикали CEILING) |
//   DISPLAY (WAVE — форма вокруг пика, LEVEL — уровень за 4 с; линии потолка тянутся, тап — FREEZE) | блок CLIP.

import { clipTele, clipWave, LIM_TELE } from '../audio/engine';
import { PARAM_BY_ID, type ParamDef } from '../params';
import { beginGesture, doc, endGesture, toggleClipBypass, toggleView, ui } from '../state';
import { saveSettings, settings } from '../settings';
import { LevelBars, clipperBars } from './dynamics';
import { closeButton, h, setClass, setText } from './dom';
import { masterTitle,
  Freeze, HotTracker, LINE_HIT, drawDbGrid, drawGrPeaks, drawPauseLabel, fitCanvas, historyColumns, msetVal as setVal,
  mval as val, num, numInputIn, paramField, toDb,
} from './masterwin';
import { color } from './theme';

/** TRANSFER: обе оси −30…0 dB (не зависит от SCALE). */
const T_RANGE = 30;
/** Ручка-угол, px (диаметр). */
const CORNER = 28;
/** Подписи пиков GR: не чаще, ms. */
const PEAK_GAP_MS = 100;
/** Снимок WAVE старше этого — тишина. */
const WAVE_STALE_MS = 300;

const P = {
  input: PARAM_BY_ID['clip.drive'],
  ceiling: PARAM_BY_ID['clip.ceiling'],
  softness: PARAM_BY_ID['clip.softness'],
  bass: PARAM_BY_ID['clip.bass'],
  mix: PARAM_BY_ID['clip.mix'],
};

let panel: HTMLElement;
let anchor: HTMLElement;
let tBox: HTMLElement;
let tCanvas: HTMLCanvasElement;
let dBox: HTMLElement;
let dCanvas: HTMLCanvasElement;
let bars: LevelBars;
let viewBtn: HTMLElement;
let bypassBtn: HTMLElement;
let unityBtn: HTMLElement;
let auditBtn: HTMLElement;
const fieldEls = new Map<string, HTMLElement>();

const hotT = new HotTracker(Object.values(P));
/** FREEZE: LEVEL — снимок истории, WAVE — последний снимок формы. */
const freeze = new Freeze(clipTele);
const waveSnap = { inp: new Float32Array(1024), out: new Float32Array(1024), ch: 0 };
function setFreeze(on: boolean) {
  freeze.set(on);
  if (on) { waveSnap.inp = clipWave.inp.slice(); waveSnap.out = clipWave.out.slice(); waveSnap.ch = clipWave.ch; }
}

const numInput = (el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string) => numInputIn(panel, anchor, el, p, parse, init);
const round1 = (v: number) => Math.round(v * 10) / 10;

/** Кривая передачи: выход клиппера (dB, до MIX) при уровне источника x dB до INPUT. */
export function clipCurve(x: number, input: number, ceiling: number, softness: number): number {
  const k = 1 - 0.6 * (softness / 100);
  const u = Math.pow(10, (x + input - ceiling) / 20);
  let y: number;
  if (u <= k) y = u;
  else { const s = 1 - k; y = s > 1e-9 ? k + s * Math.tanh((u - k) / s) : 1; }
  return ceiling + 20 * Math.log10(y);
}

// ---------- Построение ----------

export function buildClipWindow(): HTMLElement {
  panel = h('div', 'eq-panel lim-panel clip-panel hidden');
  anchor = h('div', 'eq-anchor');

  // Строка вверху: поля (как у ручек 3.1–3.4), за чертой MIX, кнопки и крестик.
  const strip = h('div', 'eq-bar lim-strip clip-strip');
  strip.append(masterTitle('clip'));
  const field = (label: string, p: ParamDef, parse: (t: string) => number | null, init: () => string) => {
    const f = paramField(label, p, numInput, parse, init);
    f.classList.add('lim-field');
    fieldEls.set(p.id, f);
    return f;
  };
  strip.append(
    field('INPUT', P.input, num, () => val(P.input).toFixed(1)),
    field('CEILING', P.ceiling, num, () => val(P.ceiling).toFixed(1)),
    field('SOFTNESS', P.softness, num, () => String(Math.round(val(P.softness)))),
    field('BASS', P.bass, (t) => (/off/i.test(t) ? 0 : num(t)), () => (val(P.bass) <= 0 ? 'OFF' : String(Math.round(val(P.bass))))),
    h('div', 'comp-sep'),
    field('MIX', P.mix, num, () => String(Math.round(val(P.mix)))),
  );
  const btn = (label: string, fn: () => void) => {
    const b = h('div', 'btn eq-tool lim-btn', label);
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); fn(); });
    return b;
  };
  viewBtn = btn('WAVE', () => saveSettings({ clipDisplay: settings.clipDisplay === 'wave' ? 'level' : 'wave' }));
  bypassBtn = btn('BYPASS', () => toggleClipBypass());
  unityBtn = btn('UNITY', () => { ui.clipUnity = !ui.clipUnity; });
  auditBtn = btn('AUDIT', () => { ui.clipAudit = !ui.clipAudit; });
  // BYPASS — рядом с крестиком (как во всех окнах модулей мастера).
  strip.append(viewBtn, unityBtn, auditBtn, bypassBtn, closeButton(closeClipWindow));

  // TRANSFER: только ручка-угол (x — INPUT, y — CEILING); SOFTNESS пальцем на кривой не меняется.
  tBox = h('div', 'eq-plot clip-transfer');
  tCanvas = document.createElement('canvas');
  tCanvas.className = 'eq-canvas';
  tBox.append(tCanvas, h('div', 'comp-plot-title', 'TRANSFER'));
  const tDrag = new Set<number>();
  const cornerTo = (e: PointerEvent) => {
    const r = tCanvas.getBoundingClientRect();
    const x = -T_RANGE + ((e.clientX - r.left) / r.width) * T_RANGE;
    const y = -((e.clientY - r.top) / r.height) * T_RANGE;
    const ceil = round1(Math.min(P.ceiling.max, Math.max(P.ceiling.min, y)));
    setVal(P.ceiling, ceil);
    setVal(P.input, round1(Math.min(P.input.max, Math.max(P.input.min, ceil - x))));
  };
  tCanvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const r = tCanvas.getBoundingClientRect();
    const c = corner(r.width, r.height);
    if (Math.hypot(e.clientX - r.left - c.x, e.clientY - r.top - c.y) > LINE_HIT) return;
    tCanvas.setPointerCapture(e.pointerId);
    tDrag.add(e.pointerId);
    hotT.hold(e.pointerId, 'clip.drive');
    hotT.hold(-1 - e.pointerId, 'clip.ceiling');
    beginGesture();
  });
  tCanvas.addEventListener('pointermove', (e) => { if (tDrag.has(e.pointerId)) cornerTo(e); });
  const tUp = (e: PointerEvent) => {
    if (!tDrag.delete(e.pointerId)) return;
    hotT.release(e.pointerId);
    hotT.release(-1 - e.pointerId);
    endGesture();
  };
  tCanvas.addEventListener('pointerup', tUp);
  tCanvas.addEventListener('pointercancel', tUp);

  // DISPLAY: линии потолка тянутся (±22 px, приоритет выше FREEZE), иначе тап — FREEZE.
  dBox = h('div', 'eq-plot lim-plot clip-display');
  dCanvas = document.createElement('canvas');
  dCanvas.className = 'eq-canvas';
  dBox.append(dCanvas);
  const dDrag = new Map<number, { y0: number; v0: number; moved: boolean }>();
  dCanvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    dCanvas.setPointerCapture(e.pointerId);
    const r = dCanvas.getBoundingClientRect();
    const y = e.clientY - r.top;
    const lines = ceilingLines(r.height);
    if (lines.some((ly) => Math.abs(y - ly) <= LINE_HIT)) {
      dDrag.set(e.pointerId, { y0: e.clientY, v0: val(P.ceiling), moved: false });
      hotT.hold(e.pointerId, 'clip.ceiling');
      beginGesture();
    } else dDrag.set(e.pointerId, { y0: e.clientY, v0: NaN, moved: false });
  });
  dCanvas.addEventListener('pointermove', (e) => {
    const d = dDrag.get(e.pointerId);
    if (!d) return;
    if (Math.abs(e.clientY - d.y0) > 6) d.moved = true;
    if (Number.isNaN(d.v0)) return;
    const r = dCanvas.getBoundingClientRect();
    if (settings.clipDisplay === 'wave') {
      // WAVE: амплитуда по положению пальца (от середины), в dB.
      const a = Math.abs(e.clientY - r.top - r.height / 2) / (waveHalf(r.height));
      setVal(P.ceiling, round1(toDb(a)));
    } else setVal(P.ceiling, round1(d.v0 - ((e.clientY - d.y0) / r.height) * settings.limScale));
  });
  const dUp = (e: PointerEvent) => {
    const d = dDrag.get(e.pointerId);
    if (!d) return;
    dDrag.delete(e.pointerId);
    if (!Number.isNaN(d.v0)) { hotT.release(e.pointerId); endGesture(); return; }
    if (!d.moved && e.type === 'pointerup') setFreeze(!freeze.on);
  };
  dCanvas.addEventListener('pointerup', dUp);
  dCanvas.addEventListener('pointercancel', dUp);

  // Блок CLIP — тот же компонент и данные, что слева; IN и OUT — по SCALE.
  bars = new LevelBars(clipperBars({ levelLo: () => -settings.limScale }));
  bars.el.classList.add('lim-bars');

  const mid = h('div', 'lim-mid');
  mid.append(tBox, dBox, bars.el);
  panel.append(strip, mid, anchor);
  return panel;
}

/** Крестик и выход из MST: окно закрывается, UNITY и AUDIT выключаются (toggleView), FREEZE снимается. */
export function closeClipWindow() {
  if (ui.clipView) toggleView('clip');
  freeze.set(false);
}

// ---------- Отрисовка ----------

const tx = (db: number, W: number) => ((db + T_RANGE) / T_RANGE) * W;
const ty = (db: number, H: number) => Math.min(H, Math.max(0, (-db / T_RANGE) * H));
/** Угол: (CEILING − INPUT, CEILING). */
function corner(W: number, H: number) {
  const ceil = val(P.ceiling);
  return { x: tx(ceil - val(P.input), W), y: ty(ceil, H) };
}
/** WAVE: полувысота для амплитуды 1 (небольшой запас сверху и снизу). */
const waveHalf = (H: number) => H / 2 - 6;
/** y линий потолка на дисплее (в WAVE — две, ±C; в LEVEL — одна). */
function ceilingLines(H: number): number[] {
  const ceil = val(P.ceiling);
  if (settings.clipDisplay === 'wave') {
    const a = Math.pow(10, ceil / 20) * waveHalf(H);
    return [H / 2 - a, H / 2 + a];
  }
  return [Math.min(H, Math.max(0, (-ceil / settings.limScale) * H))];
}

export function renderClipWindow(now: number) {
  // Выход из MST закрывает окно.
  if (ui.clipView && ui.channel !== 'master') closeClipWindow();
  setClass(panel, 'hidden', !ui.clipView);
  if (!ui.clipView) return;

  hotT.update(now, [...fieldEls].filter(([, f]) => f.classList.contains('active')).map(([id]) => id));
  const hot = (id: string) => hotT.hot(id, now);
  const bypass = doc.clipBypass;
  for (const [id, f] of fieldEls) { setClass(f, 'hot', hot(id)); setClass(f, 'off', bypass); }
  setText(viewBtn, settings.clipDisplay === 'wave' ? 'WAVE' : 'LEVEL');
  setClass(bypassBtn, 'active', bypass);
  setClass(unityBtn, 'active', ui.clipUnity);
  setClass(auditBtn, 'active', ui.clipAudit);
  bars.render(now);
  const live = now - clipTele.at < 300;
  drawTransfer(hot, live);
  if (settings.clipDisplay === 'wave') drawWave(now, hot);
  else drawLevel(hot, live);
}

function dashedH(g: CanvasRenderingContext2D, y: number, W: number, hotOn: boolean) {
  g.save();
  g.strokeStyle = hotOn ? color('--accent') : color('--meter-thr');
  g.lineWidth = hotOn ? 1.5 : 1;
  g.setLineDash([4, 4]);
  g.beginPath();
  g.moveTo(0, y);
  g.lineTo(W, y);
  g.stroke();
  g.restore();
}

function drawTransfer(hot: (id: string) => boolean, live: boolean) {
  const f = fitCanvas(tCanvas, tBox);
  if (!f) return;
  const { g, W, H } = f;
  const input = val(P.input), ceil = val(P.ceiling), soft = val(P.softness);
  const bypass = doc.clipBypass;
  // Сетка через 6 dB по обеим осям, подписи слева.
  g.font = '10px -apple-system, sans-serif';
  g.textBaseline = 'top';
  g.textAlign = 'left';
  for (let db = 0; db > -T_RANGE; db -= 6) {
    g.fillStyle = color('--line');
    g.fillRect(0, Math.round(ty(db, H)) + 0.5, W, 1);
    if (db < 0) g.fillRect(Math.round(tx(db, W)) + 0.5, 0, 1, H);
    g.fillStyle = color('--dim');
    g.fillText(db === 0 ? '0' : String(db), 4, ty(db, H) + 2);
  }
  // Колено: от x_k до угла x_c.
  const xc = ceil - input;
  const k = 1 - 0.6 * (soft / 100);
  const xk = xc + 20 * Math.log10(k);
  g.fillStyle = color('--lim-in');
  g.fillRect(tx(xk, W), 0, tx(xc, W) - tx(xk, W), H);
  // Диагональ 1:1.
  g.strokeStyle = color('--dim');
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(0, H);
  g.lineTo(W, 0);
  g.stroke();
  // Кривая (до MIX).
  const pts: number[] = [];
  for (let x = 0; x <= W; x++) pts.push(ty(clipCurve(-T_RANGE + (x / W) * T_RANGE, input, ceil, soft), H));
  g.strokeStyle = bypass ? color('--dim') : color('--text');
  g.lineWidth = 1.5;
  g.beginPath();
  pts.forEach((y, x) => (x ? g.lineTo(x, y) : g.moveTo(x, y)));
  g.stroke();
  // Пунктир CEILING.
  const ceilHot = hot('clip.ceiling');
  dashedH(g, ty(ceil, H), W, ceilHot);
  // Живая точка: уровень источника последнего кадра (пик после INPUT − INPUT); при срезе — оранжевый участок от колена.
  const t = clipTele;
  const last = (t.n - 1 + LIM_TELE) % LIM_TELE;
  if (!bypass && live && t.n > 0) {
    const x = toDb(t.in[last]) - input;
    if (x > -T_RANGE) {
      if (t.gr[last] > 0.05 && x > xk) {
        g.strokeStyle = color('--meter-gr');
        g.lineWidth = 2.5;
        g.beginPath();
        const a = Math.max(0, Math.floor(tx(xk, W)));
        const b = Math.min(W, Math.ceil(tx(x, W)));
        for (let i = a; i <= b; i++) (i === a ? g.moveTo(i, pts[i]) : g.lineTo(i, pts[i]));
        g.stroke();
      }
      g.fillStyle = color('--text');
      g.beginPath();
      g.arc(tx(Math.min(0, x), W), ty(clipCurve(Math.min(0, x), input, ceil, soft), H), 3, 0, 2 * Math.PI);
      g.fill();
    }
  }
  // Ручка-угол.
  const c = corner(W, H);
  const cHot = hot('clip.drive') || ceilHot;
  g.lineWidth = 1.5;
  g.strokeStyle = cHot ? color('--accent') : color('--text');
  g.fillStyle = color('--panel');
  g.beginPath();
  g.arc(c.x, c.y, CORNER / 2 - 1, 0, 2 * Math.PI);
  g.fill();
  g.stroke();
  g.fillStyle = cHot ? color('--accent') : color('--text');
  g.beginPath();
  g.arc(c.x, c.y, 3, 0, 2 * Math.PI);
  g.fill();
}

/** Число CEILING справа у линии. */
function ceilLabel(g: CanvasRenderingContext2D, y: number, W: number, hotOn: boolean, below: boolean) {
  g.fillStyle = hotOn ? color('--accent') : color('--meter-thr');
  g.font = '11px -apple-system, sans-serif';
  g.textAlign = 'right';
  g.textBaseline = below ? 'top' : 'bottom';
  g.fillText(val(P.ceiling).toFixed(1), W - 6, below ? y + 3 : y - 3);
}

function drawWave(now: number, hot: (id: string) => boolean) {
  const f = fitCanvas(dCanvas, dBox);
  if (!f) return;
  const { g, W, H } = f;
  const mid = H / 2;
  const half = waveHalf(H);
  // Сетка: 0, ±0.5, ±1.
  g.fillStyle = color('--line');
  for (const a of [-1, -0.5, 0, 0.5, 1]) g.fillRect(0, Math.round(mid - a * half) + 0.5, W, 1);
  g.fillStyle = color('--dim');
  g.font = '10px -apple-system, sans-serif';
  g.textAlign = 'left';
  g.textBaseline = 'top';
  for (const a of [1, 0.5, 0, -0.5]) g.fillText(a === 0 ? '0' : a.toFixed(1), 4, mid - a * half + 2);
  const snap = freeze.on ? waveSnap : clipWave;
  const live = freeze.on || now - clipWave.at < WAVE_STALE_MS;
  const cols = Math.max(1, Math.floor(W));
  if (live) {
    const N = snap.inp.length;
    // На пиксель — отсчёт с наибольшим модулем своего отрезка (со знаком).
    const vin = new Float32Array(cols), vout = new Float32Array(cols);
    for (let x = 0; x < cols; x++) {
      const a = Math.floor((x * N) / cols), b = Math.max(a + 1, Math.floor(((x + 1) * N) / cols));
      let mi = 0, mo = 0;
      for (let j = a; j < b; j++) {
        if (Math.abs(snap.inp[j]) > Math.abs(mi)) mi = snap.inp[j];
        if (Math.abs(snap.out[j]) > Math.abs(mo)) mo = snap.out[j];
      }
      vin[x] = mi; vout[x] = mo;
    }
    const yv = (v: number) => mid - Math.max(-1, Math.min(1, v)) * half;
    // Вход после INPUT — серая заливка от нуля с тонким контуром; выше ±1 — светлая метка у края.
    g.beginPath();
    g.moveTo(0, mid);
    for (let x = 0; x < cols; x++) g.lineTo(x, yv(vin[x]));
    g.lineTo(cols, mid);
    g.closePath();
    g.fillStyle = color('--lim-in');
    g.fill();
    g.strokeStyle = color('--dim');
    g.lineWidth = 1;
    g.stroke();
    g.fillStyle = color('--lim-in-over');
    for (let x = 0; x < cols; x++) if (Math.abs(vin[x]) > 1) g.fillRect(x, vin[x] > 0 ? 0 : H - 3, 1, 3);
    if (!doc.clipBypass) {
      // Срезанное — где выход по модулю меньше входа (одного знака): оранжевая заливка ~25 %.
      g.fillStyle = color('--clip-cut');
      for (let x = 0; x < cols; x++) {
        if (Math.abs(vout[x]) < Math.abs(vin[x]) - 1e-4 && vout[x] * vin[x] >= 0) {
          const a = yv(vin[x]), b = yv(vout[x]);
          g.fillRect(x, Math.min(a, b), 1, Math.abs(b - a));
        }
      }
    }
    // Выход после клиппера и MIX — оранжевый контур.
    g.strokeStyle = color('--meter-gr');
    g.lineWidth = 1.5;
    g.beginPath();
    for (let x = 0; x < cols; x++) (x ? g.lineTo(x, yv(vout[x])) : g.moveTo(x, yv(vout[x])));
    g.stroke();
    // Канал снимка.
    g.fillStyle = color('--dim');
    g.font = '10px -apple-system, sans-serif';
    g.textAlign = 'right';
    g.textBaseline = 'bottom';
    g.fillText(snap.ch ? 'R' : 'L', W - 6, H - 4);
  }
  // Линии потолка ±C (2 px) с числом справа.
  const ceilHot = hot('clip.ceiling');
  const [y1, y2] = ceilingLines(H);
  g.fillStyle = ceilHot ? color('--accent') : color('--meter-thr');
  g.fillRect(0, y1 - 1, W, 2);
  g.fillRect(0, y2 - 1, W, 2);
  ceilLabel(g, y1, W, ceilHot, y1 < 16);
  if (freeze.on) drawPauseLabel(g, 'FREEZE');
}

function drawLevel(hot: (id: string) => boolean, live: boolean) {
  const f = fitCanvas(dCanvas, dBox);
  if (!f) return;
  const { g, W, H } = f;
  const scale = settings.limScale;
  drawDbGrid(g, W, H, scale);
  const cols = Math.max(1, Math.floor(W));
  const { inDb, outDb, grDb } = historyColumns(freeze.tele, cols, freeze.on || live);
  const yOf = (db: number) => Math.min(H, Math.max(0, (-db / scale) * H));
  const area = (data: Float32Array) => {
    g.beginPath();
    g.moveTo(0, H);
    for (let x = 0; x < cols; x++) g.lineTo(x, yOf(data[x]));
    g.lineTo(cols, H);
    g.closePath();
  };
  // Вход после INPUT — серая заливка с тонким контуром.
  area(inDb);
  g.fillStyle = color('--lim-in');
  g.fill();
  g.strokeStyle = color('--dim');
  g.lineWidth = 1;
  g.stroke();
  // Выход — оранжевая заливка ~15 % и контур 1.5 px.
  area(outDb);
  g.fillStyle = color('--clip-out-fill');
  g.fill();
  g.beginPath();
  for (let x = 0; x < cols; x++) (x ? g.lineTo(x, yOf(outDb[x])) : g.moveTo(x, yOf(outDb[x])));
  g.strokeStyle = color('--meter-gr');
  g.lineWidth = 1.5;
  g.stroke();
  if (!doc.clipBypass) {
    // GR — оранжевая заливка ~25 % от верхней кромки (без линии) и подписи пиков.
    g.fillStyle = color('--clip-cut');
    g.beginPath();
    g.moveTo(0, 0);
    for (let x = 0; x < cols; x++) { const y = Math.min(H, (grDb[x] / scale) * H); g.lineTo(x, y); g.lineTo(x + 1, y); }
    g.lineTo(cols, 0);
    g.closePath();
    g.fill();
    drawGrPeaks(g, grDb, W, H, scale, PEAK_GAP_MS);
  }
  // Линия CEILING с числом справа.
  const ceilHot = hot('clip.ceiling');
  const [y] = ceilingLines(H);
  g.fillStyle = ceilHot ? color('--accent') : color('--meter-thr');
  g.fillRect(0, y - 1, W, 2);
  ceilLabel(g, y, W, ceilHot, y < 16);
  if (freeze.on) drawPauseLabel(g, 'FREEZE');
}
