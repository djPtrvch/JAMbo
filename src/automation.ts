// Автоматизация параметров (этап 6): кривые паттерна по шагам секвенсора.
// Здесь — только данные и математика (без состояния и интерфейса): вычисление кривой
// (монотонный кубический сплайн Фритча — Карлсона, прямая, ступенька), упрощение записи
// (Рамер — Дуглас — Пекер) и правка списка точек.

import { PARAM_BY_ID, type ParamDef } from './params';

/** Тип сегмента — от этой точки к следующей. */
export type SegType = 'linear' | 'smooth' | 'hold';
export const SEG_TYPES: SegType[] = ['linear', 'smooth', 'hold'];

/** Точка: x — позиция в шагах секвенсора (дробная, от начала паттерна), y — положение ручки 0..1. */
export interface AutoPoint { x: number; y: number; type: SegType }
/** curve: 'line' — все сегменты прямые (smooth рисуется прямой), 'spline' (нет поля — тоже) — сплайны разрешены. */
export interface Automation { param: string; points: AutoPoint[]; curve?: 'line' | 'spline' }

/** Точек в одной автоматизации не больше. */
export const AUTO_MAX_POINTS = 512;
/** Допуск упрощения записи по умолчанию (доля диапазона). */
export const SIMPLIFY_DEF = 0.01;

/** Параметры, которые можно автоматизировать: ручки сетки дорожки и 1.1–1.3 движков. */
export const AUTO_PARAMS = new Set([
  'pitch', 'start', 'end', 'level', 'attack', 'decay', 'filter', 'reso', 'reverb', 'delay', 'drive', 'sidechain',
  'pan', 'prob', 'ratchet', 'swing', 'harm', 'timbre', 'morph',
]);

/** Ступенчатый параметр (у него только сегменты hold). paramDef — ячейка сетки (у 1.1 движков — своя). */
export const isStepped = (p: ParamDef | undefined) => !!p && (p.kind === 'stepped' || !!p.steps || !!p.options);

/** Тип сегмента с учётом параметра: у ступенчатых — всегда hold. */
export const segType = (p: ParamDef | undefined, t: SegType): SegType => (isStepped(p) ? 'hold' : t);

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);

/** Наклон секущей сегмента i (от точки i к i + 1). */
function secant(pts: AutoPoint[], i: number): number {
  const h = pts[i + 1].x - pts[i].x;
  return h > 1e-9 ? (pts[i + 1].y - pts[i].y) / h : 0;
}

/**
 * Наклон в точке i для монотонной кубической интерполяции (Фритч — Карлсон, PCHIP): зависит только
 * от соседних секущих, поэтому считается на месте; кривая между точками не выходит за их значения
 * (без выбросов за 0..1).
 */
function slopeAt(pts: AutoPoint[], i: number): number {
  const n = pts.length;
  if (n < 2) return 0;
  if (i === 0 || i === n - 1) {
    // Концы: секущая крайнего сегмента (не больше трёх её наклонов — условие монотонности выполнено).
    return secant(pts, i === 0 ? 0 : n - 2);
  }
  const d0 = secant(pts, i - 1);
  const d1 = secant(pts, i);
  if (d0 * d1 <= 0) return 0;
  // Взвешенное гармоническое среднее (PCHIP).
  const h0 = pts[i].x - pts[i - 1].x;
  const h1 = pts[i + 1].x - pts[i].x;
  const w1 = 2 * h1 + h0;
  const w2 = h1 + 2 * h0;
  return (w1 + w2) / (w1 / d0 + w2 / d1);
}

/** Индекс сегмента: последняя точка с x ≤ pos (−1 — до первой точки). */
function segIndex(pts: AutoPoint[], x: number): number {
  let lo = 0;
  let hi = pts.length - 1;
  if (x < pts[0].x) return -1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (pts[mid].x <= x) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/**
 * Значение кривой 0..1 в позиции x (шаги). Кривая действует только от первой точки до последней
 * (до первой и с последней — null: значение ручки; так новые страницы дорожки без точек — без
 * автоматизации); у одной точки — её значение везде. stepped — ступенчатый параметр (все сегменты —
 * hold); line — режим LINE (smooth — прямая).
 */
export function evalAuto(pts: AutoPoint[], x: number, stepped = false, line = false): number | null {
  const n = pts.length;
  if (!n) return null;
  if (n === 1) return pts[0].y;
  if (x < pts[0].x || x >= pts[n - 1].x) return null;
  const i = segIndex(pts, x);
  const a = pts[i];
  const b = pts[i + 1];
  const t = stepped ? 'hold' : line && a.type === 'smooth' ? 'linear' : a.type;
  if (t === 'hold') return a.y;
  const h = b.x - a.x;
  if (h <= 1e-9) return b.y;
  const u = (x - a.x) / h;
  if (t === 'linear') return a.y + (b.y - a.y) * u;
  const m0 = slopeAt(pts, i);
  const m1 = slopeAt(pts, i + 1);
  const u2 = u * u;
  const u3 = u2 * u;
  const y = (2 * u3 - 3 * u2 + 1) * a.y + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * b.y + (u3 - u2) * h * m1;
  return clamp01(y);
}

/** Точки как ломаная (для отрисовки и упрощения): n отсчётов на шаг. */
export function sampleAuto(pts: AutoPoint[], from: number, to: number, count: number, stepped = false): Float32Array {
  const out = new Float32Array(count);
  for (let k = 0; k < count; k++) out[k] = evalAuto(pts, from + ((to - from) * k) / Math.max(1, count - 1), stepped) ?? 0;
  return out;
}

/** Упрощение ломаной (Рамер — Дуглас — Пекер): оставляет точки, отклонение которых больше tol (по y). */
export function simplify(pts: AutoPoint[], tol: number): AutoPoint[] {
  // Допуск 0 (SIMPLIFY 0 %) — все точки остаются, и на прямых участках тоже.
  if (pts.length <= 2 || tol <= 0) return pts.map((p) => ({ ...p }));
  const keep = new Uint8Array(pts.length);
  keep[0] = 1;
  keep[pts.length - 1] = 1;
  const stack: [number, number][] = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    const pa = pts[a];
    const pb = pts[b];
    const dx = pb.x - pa.x;
    let worst = -1;
    let wd = tol;
    for (let i = a + 1; i < b; i++) {
      // Отклонение по вертикали от хорды (кривая — функция x).
      const y = dx > 1e-9 ? pa.y + ((pb.y - pa.y) * (pts[i].x - pa.x)) / dx : pa.y;
      const d = Math.abs(pts[i].y - y);
      if (d > wd) { wd = d; worst = i; }
    }
    if (worst >= 0) {
      keep[worst] = 1;
      stack.push([a, worst], [worst, b]);
    }
  }
  return pts.filter((_, i) => keep[i]).map((p) => ({ ...p }));
}

/**
 * Привязка записи к сетке X: q шагов (0 — без привязки). Точка на каждом узле сетки от первого до
 * последнего отсчёта (округлённых к узлу), значение — записанная ломаная в этом месте (у ступенчатых —
 * последнее значение до узла). x — в пределах 0…span.
 */
export function resampleGrid(raw: AutoPoint[], q: number, stepped: boolean, span: number): AutoPoint[] {
  if (!q || !raw.length) return raw.map((p) => ({ ...p }));
  const k0 = Math.max(0, Math.round(raw[0].x / q));
  const k1 = Math.min(Math.floor(span / q + 1e-6), Math.round(raw[raw.length - 1].x / q));
  const out: AutoPoint[] = [];
  let j = 0;
  for (let k = k0; k <= k1; k++) {
    const x = k * q;
    while (j < raw.length - 1 && raw[j + 1].x <= x) j++;
    const a = raw[j];
    const b = raw[Math.min(j + 1, raw.length - 1)];
    let y = a.y;
    if (x <= raw[0].x) y = raw[0].y;
    else if (!stepped && b.x > a.x && x < b.x) y = a.y + ((b.y - a.y) * (x - a.x)) / (b.x - a.x);
    else if (x >= b.x) y = b.y;
    out.push({ x, y, type: a.type });
  }
  return out;
}

/** Параметр автоматизации (для формата значения и ступенчатости). */
export const autoParam = (id: string, grid?: (ParamDef | null)[]): ParamDef | undefined =>
  grid?.find((p) => p?.id === id) ?? PARAM_BY_ID[id];

/** Вставить точку, сохраняя порядок по x (одинаковых x не бывает); индекс новой точки или −1. */
export function insertPoint(pts: AutoPoint[], p: AutoPoint): number {
  if (pts.length >= AUTO_MAX_POINTS) return -1;
  let i = 0;
  while (i < pts.length && pts[i].x < p.x) i++;
  if (i < pts.length && Math.abs(pts[i].x - p.x) < 1e-6) { pts[i].y = p.y; return i; }
  pts.splice(i, 0, p);
  return i;
}

/**
 * Записанный участок [x0, x1] заменяет точки в этом диапазоне; на границах — точки со старым значением
 * кривой, чтобы она не прыгала (на расстоянии gap — при привязке X это шаг сетки). rec — записанные точки (по возрастанию x).
 */
export function spliceRecording(pts: AutoPoint[], rec: AutoPoint[], stepped: boolean, gap = 0.02): AutoPoint[] {
  if (!rec.length) return pts;
  const x0 = rec[0].x;
  const x1 = rec[rec.length - 1].x;
  const out: AutoPoint[] = [];
  const before = pts.filter((p) => p.x < x0 - 1e-6);
  const after = pts.filter((p) => p.x > x1 + 1e-6);
  const y0 = evalAuto(pts, x0 - gap, stepped);
  const y1 = evalAuto(pts, x1 + gap, stepped);
  out.push(...before);
  // Граница слева: старое значение кривой чуть раньше записи (кривая не прыгает до начала записи).
  if (y0 !== null && before.length && x0 - gap > before[before.length - 1].x + 1e-6) out.push({ x: x0 - gap, y: y0, type: 'linear' });
  out.push(...rec);
  // Граница справа: дальше кривая идёт, как шла (тип старого сегмента, который покрывал x1).
  const old = pts.filter((p) => p.x <= x1).pop();
  if (y1 !== null && after.length && x1 + gap < after[0].x - 1e-6) out.push({ x: x1 + gap, y: y1, type: old?.type ?? 'smooth' });
  out.push(...after);
  return out.slice(0, AUTO_MAX_POINTS);
}
