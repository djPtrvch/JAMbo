// Сетка ручек 4×4: вертикальное управление пальцем, мультитач,
// p-lock (жёлтый), назначение LFO и анимированные белые кольца.

import { fromNorm, toNorm, type ParamDef } from '../params';
import {
  beginGesture, clearLfoAssign, clearLock, doc, endGesture, firstHeldStep, gridFor, gridMode, heldLfo,
  lockValue, modulatedNorm, paramValue, rt, setLfoAmount, setLockNorm, setParamNorm, ui, type GridMode,
} from '../state';
import { DOUBLE_TAP_MS, h, setAttr, setClass, setText, svg } from './dom';

/** Сколько пикселей вертикального хода = полный оборот ручки. */
const TRAVEL_PX = 240;
/** Мёртвая зона, чтобы тап не сдвигал значение. */
const DEAD_PX = 4;

// Геометрия дуги: от −135° до +135°.
const START = -135;
const SWEEP = 270;
const R_VALUE = 36;
const R_LOCK = 28;
const R_LFO = 45;

function polar(r: number, deg: number) {
  const a = ((deg - 90) * Math.PI) / 180;
  return [50 + r * Math.cos(a), 50 + r * Math.sin(a)];
}

function arc(r: number, n0: number, n1: number): string {
  if (Math.abs(n1 - n0) < 0.002) return '';
  const a0 = START + SWEEP * Math.min(n0, n1);
  const a1 = START + SWEEP * Math.max(n0, n1);
  const [x0, y0] = polar(r, a0);
  const [x1, y1] = polar(r, a1);
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

interface KnobView {
  root: HTMLElement;
  label: HTMLElement;
  value: HTMLElement;
  valueArc: SVGPathElement;
  lfoArc: SVGPathElement;
  rangeArc: SVGPathElement;
  lockArc: SVGPathElement;
  pointer: SVGLineElement;
}

interface Gesture {
  slot: number;
  mode: GridMode;
  param: ParamDef;
  startY: number;
  lastY: number;
  moved: boolean;
  /** Накопитель положения ручки (0..1, для LFO −1..1). */
  acc: number;
  kind: 'base' | 'lock' | 'lfo';
  lfo: 1 | 2;
  consumed: boolean;
}

const views: KnobView[] = [];
const gestures = new Map<number, Gesture>();
const lastTap: number[] = Array(16).fill(-1e9);

function buildKnob(slot: number): KnobView {
  const root = h('div', 'knob');
  const box = svg('svg', { viewBox: '0 0 100 100', class: 'knob-svg' });
  box.append(svg('path', { d: arc(R_VALUE, 0, 1), class: 'k-track' }));
  const rangeArc = svg('path', { class: 'k-range' });
  const valueArc = svg('path', { class: 'k-value' });
  const lockArc = svg('path', { class: 'k-lock' });
  const lfoArc = svg('path', { class: 'k-lfo' });
  box.append(svg('circle', { cx: 50, cy: 50, r: 24, class: 'k-cap' }));
  const pointer = svg('line', { x1: 50, y1: 29, x2: 50, y2: 22, class: 'k-pointer' });
  box.append(rangeArc, valueArc, lockArc, lfoArc, pointer);
  const value = h('div', 'knob-value');
  const label = h('div', 'knob-label');
  const dial = h('div', 'knob-dial');
  dial.append(box, value);
  root.append(dial, label);

  root.addEventListener('pointerdown', (e) => onDown(slot, e));
  root.addEventListener('pointermove', (e) => onMove(e));
  root.addEventListener('pointerup', (e) => onUp(e));
  root.addEventListener('pointercancel', (e) => onUp(e));
  return { root, label, value, valueArc, lfoArc, rangeArc, lockArc, pointer };
}

export function buildKnobGrid(): HTMLElement {
  const el = h('div', 'knob-grid');
  for (let i = 0; i < 16; i++) {
    const v = buildKnob(i);
    views.push(v);
    el.append(v.root);
  }
  return el;
}

// ---------- Жесты ----------

function onDown(slot: number, e: PointerEvent) {
  const mode = gridMode();
  const param = gridFor(mode)[slot];
  if (!param) return;
  e.preventDefault();
  (e.currentTarget as Element).setPointerCapture(e.pointerId);

  const lfo = heldLfo();
  const held = firstHeldStep();
  const kind: Gesture['kind'] = mode === 'track' && held !== null ? 'lock' : mode === 'track' && lfo ? 'lfo' : 'base';
  const g: Gesture = { slot, mode, param, startY: e.clientY, lastY: e.clientY, moved: false, acc: 0, kind, lfo: lfo ?? 1, consumed: false };

  // Двойной тап: только при удержании шага (снять p-lock) или LFO (снять назначение).
  const now = performance.now();
  if (now - lastTap[slot] < DOUBLE_TAP_MS) {
    lastTap[slot] = -1e9;
    if (kind === 'lock') clearLock(param);
    else if (kind === 'lfo') clearLfoAssign(param, g.lfo);
    g.consumed = true;
  }

  if (kind === 'lock') g.acc = toNorm(param, lockValue(held!, param) ?? paramValue(mode, param));
  else if (kind === 'lfo') {
    const a = doc.tracks[ui.selectedTrack].assigns[param.id];
    g.acc = a && a.lfo === g.lfo ? a.amount : 0;
  } else g.acc = toNorm(param, paramValue(mode, param));

  gestures.set(e.pointerId, g);
  beginGesture();
}

function onMove(e: PointerEvent) {
  const g = gestures.get(e.pointerId);
  if (!g || g.consumed) return;
  if (!g.moved) {
    if (Math.abs(e.clientY - g.startY) < DEAD_PX) return;
    g.moved = true;
    g.lastY = e.clientY;
    return;
  }
  const d = (g.lastY - e.clientY) / TRAVEL_PX;
  g.lastY = e.clientY;
  if (g.kind === 'lfo') {
    g.acc = Math.min(1, Math.max(-1, g.acc + d));
    setLfoAmount(g.param, g.lfo, g.acc);
    return;
  }
  g.acc = Math.min(1, Math.max(0, g.acc + d));
  if (g.kind === 'lock') setLockNorm(g.param, g.acc);
  else setParamNorm(g.mode, g.param, g.acc);
}

function onUp(e: PointerEvent) {
  const g = gestures.get(e.pointerId);
  if (!g) return;
  gestures.delete(e.pointerId);
  if (!g.moved && !g.consumed) lastTap[g.slot] = performance.now();
  endGesture();
}

// ---------- Отрисовка (каждый кадр) ----------

export function renderKnobs(now: number) {
  const mode = gridMode();
  const grid = gridFor(mode);
  const ti = ui.selectedTrack;
  const track = doc.tracks[ti];
  const held = mode === 'track' ? firstHeldStep() : null;
  const pl = rt.playLocks[ti];
  const playLocks = mode === 'track' && ui.playing && now < pl.until ? pl.locks : undefined;
  const lfoHeld = mode === 'track' ? heldLfo() : null;

  views.forEach((v, slot) => {
    const p = grid[slot];
    setClass(v.root, 'inactive', !p);
    if (!p) {
      setText(v.label, '');
      setText(v.value, '');
      for (const a of [v.valueArc, v.lfoArc, v.rangeArc, v.lockArc]) setAttr(a, 'd', '');
      setAttr(v.pointer, 'transform', `rotate(${START} 50 50)`);
      return;
    }
    setText(v.label, p.label);

    const base = paramValue(mode, p);
    const baseN = toNorm(p, base);
    const origin = p.bipolar ? 0.5 : 0;
    setAttr(v.valueArc, 'd', arc(R_VALUE, origin, baseN));

    // P-lock удерживаемого шага — жёлтым.
    // Удерживаемый шаг, иначе — шаг, который сейчас играет.
    const lock = held !== null
      ? track.pages[Math.floor(held / 16)]?.[held % 16]?.locks[p.id]
      : playLocks?.[p.id];
    const locked = lock !== undefined;
    setClass(v.root, 'locked', locked);
    const shownBase = locked ? lock! : base;
    const shownN = toNorm(p, shownBase);
    setAttr(v.lockArc, 'd', locked ? arc(R_LOCK, origin, shownN) : '');

    // LFO: динамическое кольцо от базового до текущего значения.
    const assign = mode === 'track' ? track.assigns[p.id] : undefined;
    const modN = mode === 'track' ? modulatedNorm(ti, p, shownBase) : shownN;
    setAttr(v.lfoArc, 'd', assign ? arc(R_LFO, shownN, modN) : '');
    setAttr(v.lfoArc, 'class', assign ? `k-lfo lfo${assign.lfo}` : 'k-lfo');

    // Пока держим LFO — видна вся зона воздействия.
    const showRange = lfoHeld && assign && assign.lfo === lfoHeld;
    setAttr(v.rangeArc, 'd', showRange ? arc(R_LFO, Math.max(0, shownN - Math.abs(assign!.amount)), Math.min(1, shownN + Math.abs(assign!.amount))) : '');
    setAttr(v.rangeArc, 'class', showRange ? `k-range lfo${lfoHeld}` : 'k-range');

    setAttr(v.pointer, 'transform', `rotate(${(START + SWEEP * modN).toFixed(1)} 50 50)`);

    let text = p.format(fromNorm(p, modN));
    if (lfoHeld && assign && assign.lfo === lfoHeld) {
      const a = Math.round(assign.amount * 100);
      text = `L${lfoHeld} ${a > 0 ? '+' : ''}${a}%`;
    }
    setText(v.value, text);
  });
}
