// Общая основа окон модулей мастера (этап 7: лимитер, компрессор): подсветка изменённых параметров,
// ввод числом внутри окна, история телеметрии по столбцам, сетка dB, подписи пиков GR, FREEZE (снимок).

import { LIM_TELE, limTeleRate, type Tele } from '../audio/engine';
import { type ParamDef, toNorm } from '../params';
import { beginGesture, endGesture, paramValue, setParamNorm } from '../state';
import { dragField } from './controls';
import { openInput } from './popup';
import { color } from './theme';

/** Окно дисплея уровня, с. */
export const WINDOW_S = 4;
/** Рамка у параметра после изменения, ms. */
export const HOT_MS = 400;
/** Зона касания линии (CEILING, THRESHOLD), px (±). */
export const LINE_HIT = 22;
/** Шкалы дисплея (кнопка SCALE, общая у окон — settings.limScale). */
export const SCALES = [48, 32, 16] as const;

export const mval = (p: ParamDef) => paramValue('master', p);
export const msetVal = (p: ParamDef, v: number) => setParamNorm('master', p, toNorm(p, Math.min(p.max, Math.max(p.min, v))));
export const mfmt = (p: ParamDef) => p.format(mval(p)).replace('\n', ' ');
export const num = (t: string) => { const v = parseFloat(t.trim().replace(',', '.')); return Number.isFinite(v) ? v : null; };
export const toDb = (x: number) => 20 * Math.log10(Math.max(x, 1e-6));

/**
 * Подсветка: параметр меняли последние HOT_MS (палец, ручка, Twister, UNDO) или его держит палец в окне.
 * ids — какие параметры следить; extra — id, у которых внешние изменения не подсвечиваются (RATIO).
 */
export class HotTracker {
  private changedAt = new Map<string, number>();
  private last = new Map<string, number>();
  private holding = new Map<number, string>();
  /** Изменения, сделанные в окне (для параметров, подсвечиваемых только окном). */
  private local = new Set<string>();
  constructor(private params: ParamDef[], private onlyLocal: string[] = []) {}
  hold(pointer: number, id: string) { this.holding.set(pointer, id); this.local.add(id); }
  release(pointer: number) { this.holding.delete(pointer); }
  /** Изменение из окна (поле, тап): засчитать подсветку и для «только окно». */
  touch(id: string) { this.local.add(id); }
  update(now: number, fieldHeld: Iterable<string> = []) {
    const fh = [...fieldHeld];
    for (const id of fh) this.local.add(id);
    for (const p of this.params) {
      const v = mval(p);
      const was = this.last.get(p.id);
      if (was !== undefined && was !== v && (!this.onlyLocal.includes(p.id) || this.local.has(p.id))) this.changedAt.set(p.id, now);
      this.last.set(p.id, v);
    }
    this.held = new Set([...this.holding.values(), ...fh]);
    // «Только окно»: метка сбрасывается, когда палец отпущен (следующее внешнее изменение не подсвечивается).
    for (const id of this.local) if (!this.held.has(id) && now - (this.changedAt.get(id) ?? -1e9) >= HOT_MS) this.local.delete(id);
  }
  private held = new Set<string>();
  hot(id: string, now: number) { return this.held.has(id) || now - (this.changedAt.get(id) ?? -1e9) < HOT_MS; }
}

/** Ввод числом: окно — внутри окна модуля, вверху (под строкой), над элементом el. */
export function numInputIn(panel: HTMLElement, anchor: HTMLElement, el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string, set?: (v: number) => void) {
  const r = el.getBoundingClientRect();
  const pr = panel.getBoundingClientRect();
  anchor.style.left = `${r.left + r.width / 2 - pr.left}px`;
  anchor.style.top = '56px';
  openInput(anchor, init, (t) => {
    const v = parse(t);
    if (v === null) return;
    beginGesture();
    if (set) set(v); else msetVal(p, v);
    endGesture();
  }, true);
}

/** Делений поля на весь ход (240 px — как у ручек сетки). */
const FIELD_UNITS = 200;
const FIELD_PX = 1.2;
/**
 * Поле окна модуля по положению параметра (0..1): вертикальный ход 240 px на весь диапазон, удержание — ввод числом
 * (input — окно ввода внутри окна модуля), тап без движения — onTap.
 */
export function paramField(label: string, p: ParamDef, input: (el: HTMLElement, p: ParamDef, parse: (t: string) => number | null, init: string) => void,
  parse: (t: string) => number | null, init: () => string, onTap?: () => void): HTMLElement {
  const f = dragField(label, () => Math.round(toNorm(p, mval(p)) * FIELD_UNITS),
    (v) => setParamNorm('master', p, Math.min(1, Math.max(0, v / FIELD_UNITS))), () => mfmt(p), FIELD_PX,
    onTap ? () => onTap() : undefined, (el) => input(el, p, parse, init()));
  f.classList.add('eq-field');
  return f;
}

/** FREEZE / HOLD: снимок кольцевого буфера телеметрии. */
export class Freeze {
  on = false;
  readonly snap: Tele = { in: new Float32Array(LIM_TELE), out: new Float32Array(LIM_TELE), gr: new Float32Array(LIM_TELE), det: new Float32Array(LIM_TELE), n: 0, at: 0 };
  constructor(private src: Tele) {}
  set(on: boolean) {
    this.on = on;
    if (!on) return;
    const s = this.snap, t = this.src;
    s.in.set(t.in); s.out.set(t.out); s.gr.set(t.gr); s.det.set(t.det);
    s.n = t.n; s.at = t.at;
  }
  get tele() { return this.on ? this.snap : this.src; }
}

/** История за WINDOW_S по столбцам: каждый пиксель — максимум своего отрезка (вход, выход — dB; GR — dB ≥ 0). */
export function historyColumns(src: Tele, cols: number, live: boolean) {
  const frames = Math.min(LIM_TELE, Math.round(WINDOW_S * limTeleRate()));
  const end = src.n;
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
  return { inDb, outDb, grDb };
}

/** Холст под размер элемента (devicePixelRatio); null — элемент не виден. */
export function fitCanvas(canvas: HTMLCanvasElement, box: HTMLElement) {
  const dpr = window.devicePixelRatio || 1;
  const W = box.clientWidth;
  const H = box.clientHeight;
  if (!W || !H) return null;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const g = canvas.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, W, H);
  return { g, W, H };
}

/** Шаг сетки dB по шкале. */
export const gridStep = (scale: number) => (scale === 48 ? 6 : scale === 32 ? 4 : 2);

/** Горизонтальная сетка dB (верх 0, низ −scale) с подписями слева. */
export function drawDbGrid(g: CanvasRenderingContext2D, W: number, H: number, scale: number, labels = true) {
  const step = gridStep(scale);
  g.font = '10px -apple-system, sans-serif';
  g.textBaseline = 'top';
  g.textAlign = 'left';
  for (let db = 0; db > -scale; db -= step) {
    const y = Math.round((-db / scale) * H) + 0.5;
    g.fillStyle = color('--line');
    g.fillRect(0, y, W, 1);
    if (labels) { g.fillStyle = color('--dim'); g.fillText(db === 0 ? '0' : String(db), 4, y + 2); }
  }
}

/** Подписи пиков GR: локальные максимумы ≥ minDb, не чаще gapMs, до max самых сильных (оранжевые). */
export function drawGrPeaks(g: CanvasRenderingContext2D, grDb: Float32Array, W: number, H: number, scale: number, gapMs: number, minDb = 1, max = 6) {
  const cols = grDb.length;
  const gapCols = Math.max(1, Math.round((gapMs / 1000 / WINDOW_S) * cols));
  const peaks: { x: number; v: number }[] = [];
  for (let x = 1; x < cols - 1; x++) {
    const v = grDb[x];
    if (v < minDb || v < grDb[x - 1] || v < grDb[x + 1]) continue;
    const last = peaks[peaks.length - 1];
    if (last && x - last.x < gapCols) { if (v > last.v) { last.x = x; last.v = v; } continue; }
    peaks.push({ x, v });
  }
  peaks.sort((a, b) => b.v - a.v);
  g.fillStyle = color('--meter-gr');
  g.font = '10px -apple-system, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'top';
  for (const p of peaks.slice(0, max)) {
    const y = Math.min(H - 12, (p.v / scale) * H + 3);
    g.fillText(`-${p.v.toFixed(1)}`, Math.min(W - 14, Math.max(14, p.x)), y);
  }
}

/** Надпись FREEZE / HOLD слева вверху. */
export function drawPauseLabel(g: CanvasRenderingContext2D, text: string) {
  g.fillStyle = color('--accent');
  g.font = '600 11px -apple-system, sans-serif';
  g.textAlign = 'left';
  g.textBaseline = 'top';
  g.fillText(text, 30, 6);
}
