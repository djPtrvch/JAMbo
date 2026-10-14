// Живая иконка движка — крупно в окне сэмпла слева. Значения — как на ручках:
// база дорожки, p-lock (зажатый шаг — его значения, при игре — играющего шага), поверх LFO/ENV.
// Иконка одного цвета: белая в тёмной теме, чёрная в светлой (без подсветки частей).
// Перерисовка — в общем кадре (requestAnimationFrame); SVG пересобирается, только когда изменились значения.

import { scTrigAgoMs } from '../audio/engine';
import { fxIconSvg, iconSvg, scCurve, scPoint, type FxIconValues, type IconParam, type IconValues } from '../engineIcons';
import { PARAM_BY_ID, TRACK_GRID, stepIndex, synthEngine, synthGrid, toNorm, type ParamDef } from '../params';
import {
  baseValue, doc, firstHeldStep, fxAlpha, fxModNorm, heldStepSound, liveFx, liveLocks, modulatedNorm, seqAt, ui,
  type FxKind,
} from '../state';

/** Ручки сетки: 1.1, 1.2, 1.3 и Decay 2.2. */
const SLOTS: [IconParam, number][] = [['h', 0], ['t', 4], ['m', 8], ['d', 5]];

export interface IconView { el: HTMLElement; key: string; size: number }

export const iconView = (el: HTMLElement, size: number): IconView => ({ el, key: '', size });

/** Звук и значения иконки дорожки i (null — звука нет). */
function iconFor(i: number, now: number): { id: string; v: IconValues } | null {
  const t = doc.tracks[i];
  const selected = ui.channel === 'track' && i === ui.selectedTrack;
  const sound = (selected ? heldStepSound() : null) ?? t.sample;
  if (!sound) return null;
  const engine = synthEngine(sound);
  const grid = engine !== null ? synthGrid(engine) : TRACK_GRID;
  const held = selected ? firstHeldStep() : null;
  const seq = seqAt(i);
  const locks = held !== null ? seq.pages[Math.floor(held / 16)]?.[held % 16]?.locks : liveLocks(i, now) ?? undefined;
  const v: IconValues = { h: 0.5, t: 0.5, m: 0.5, d: 0.5 };
  for (const [k, slot] of SLOTS) {
    const p = grid[slot] as ParamDef;
    let n = modulatedNorm(i, p, baseValue(i, p.id, locks ?? {}));
    // Ступенчатая ручка — скачком по пункту.
    if (p.steps) n = (stepIndex(n, p.steps) + 0.5) / p.steps;
    v[k] = n;
  }
  return { id: engine !== null ? String(engine) : 's', v };
}

export function renderIcon(view: IconView, track: number, now: number) {
  const icon = iconFor(track, now);
  const key = icon ? `${icon.id}|${icon.v.h.toFixed(3)}|${icon.v.t.toFixed(3)}|${icon.v.m.toFixed(3)}|${icon.v.d!.toFixed(3)}` : '';
  if (key === view.key) return;
  view.key = key;
  view.el.innerHTML = icon ? iconSvg(icon.id, icon.v, view.size) : '';
}

// ---------- Иконка эффекта (ручки 3.1–3.4 и FX) ----------
// Значения — как у иконки движка: посыл дорожки (база, p-lock зажатого или играющего шага, LFO/ENV) и общие FX
// (с p-lock и LFO/ENV); показанные значения плавно догоняют цель (~80 мс), ступенчатые — скачком.

/** Посыл дорожки и общие параметры каждого эффекта: [mix, a, b, c] (+ ступенчатый — в type). */
const FX_PARAMS: Record<FxKind, { mix: string; a: string; b: string; c: string; type?: string }> = {
  rev: { mix: 'reverb', a: 'rev.size', b: 'rev.decay', c: 'rev.predelay' },
  dly: { mix: 'delay', a: 'dly.feedback', b: 'dly.time', c: 'dly.spread' },
  drv: { mix: 'drive', a: 'od.drive', b: 'od.lowcut', c: 'od.tone', type: 'od.type' },
  sc: { mix: 'sidechain', a: 'sc.attack', b: 'sc.attack', c: 'sc.release', type: 'sc.curve' },
};
/** Подпись: посыл дорожки и параметры FX по имени эффекта. */
const TRACK_LABEL: Record<FxKind, string> = { rev: 'Reverb mix', dly: 'Delay mix', drv: 'Drive mix', sc: 'Sidechain' };
const FX_LABEL: Record<string, string> = {
  'rev.size': 'Reverb size', 'rev.decay': 'Reverb decay', 'rev.tone': 'Reverb tone', 'rev.hpf': 'Reverb low cut',
  'dly.time': 'Delay time', 'dly.feedback': 'Delay feedback', 'dly.filter': 'Delay filter', 'dly.spread': 'Delay spread',
  'od.drive': 'Drive amount', 'od.type': 'Drive type', 'od.tone': 'Drive tone', 'od.lowcut': 'Drive low cut',
  'sc.attack': 'SC attack', 'sc.release': 'SC release', 'sc.source': 'SC source', 'sc.curve': 'SC curve',
};
const SMOOTH_MS = 80;
const STEPPED = new Set(['dly.time', 'od.type']);

export interface FxView { el: HTMLElement; label: HTMLElement; size: number; key: string; kind: FxKind | null; shown: Record<string, number>; last: number; dot: SVGCircleElement | null }
export const fxView = (el: HTMLElement, label: HTMLElement, size: number): FxView =>
  ({ el, label, size, key: '', kind: null, shown: {}, last: 0, dot: null });

/** Значение параметра FX (0..1) с p-lock зажатого шага (в режиме FX) или играющих шагов и LFO/ENV. */
function fxNorm(id: string, fx: Record<string, number>, held: Record<string, number> | undefined): number {
  const p = PARAM_BY_ID[id];
  if (!p) return 0;
  const lock = held?.[id];
  return lock !== undefined ? fxModNorm(p, lock) : toNorm(p, fx[id] ?? p.def);
}

/**
 * Иконка эффекта в окне сэмпла: возвращает непрозрачность (0 — не видна). Расчёт и пересборка SVG — только
 * пока иконка видна; SVG пересобирается, когда изменились показанные значения.
 */
export function renderFxIcon(view: FxView, now: number): number {
  const f = ui.fxFocus;
  const alpha = ui.channel === 'track' ? fxAlpha(f, now) : 0;
  if (!f || alpha <= 0) { view.kind = null; return 0; }
  const i = ui.selectedTrack;
  const P = FX_PARAMS[f.kind];
  // Посыл дорожки — как иконка движка: зажатый шаг — его p-lock, иначе играющий шаг; поверх LFO/ENV.
  const heldIdx = firstHeldStep();
  const seq = seqAt(i);
  const locks = heldIdx !== null ? seq.pages[Math.floor(heldIdx / 16)]?.[heldIdx % 16]?.locks : liveLocks(i, now) ?? undefined;
  const mp = PARAM_BY_ID[P.mix]!;
  const fx = liveFx(now);
  // P-lock FX на зажатом шаге (режим FX) — в том же шаге.
  const fxHeld = heldIdx !== null ? locks : undefined;
  const target: Record<string, number> = {
    mix: modulatedNorm(i, mp, baseValue(i, P.mix, locks ?? {})),
    a: fxNorm(P.a, fx, fxHeld), b: fxNorm(P.b, fx, fxHeld), c: fxNorm(P.c, fx, fxHeld),
    type: P.type ? (P.type === 'od.type' ? (fxHeld?.[P.type] ?? fx[P.type] ?? 0) : fxNorm(P.type, fx, fxHeld)) : 0.5,
  };
  // Сглаживание: смена эффекта — сразу на цель; ступенчатые — скачком.
  const dt = Math.min(100, now - view.last);
  view.last = now;
  const k = view.kind === f.kind ? 1 - Math.exp(-dt / SMOOTH_MS) : 1;
  view.kind = f.kind;
  for (const key of Object.keys(target)) {
    const id = key === 'mix' ? P.mix : (P as Record<string, string | undefined>)[key];
    const cur = view.shown[key];
    const step = id !== undefined && STEPPED.has(id);
    let v = cur === undefined || step ? target[key] : cur + (target[key] - cur) * k;
    if (Math.abs(v - target[key]) < 0.002) v = target[key];
    view.shown[key] = v;
  }
  const sv = view.shown;
  // У Drive общий DRIVE и LOW CUT на иконке не показываются (mix — посыл дорожки, форма — TYPE, углы — TONE).
  const v: FxIconValues = f.kind === 'drv' ? { mix: sv.mix, a: 0, b: 0, c: sv.c, type: sv.type }
    : f.kind === 'sc' ? { mix: sv.mix, a: 0, b: sv.b, c: sv.c, type: sv.type }
    : { mix: sv.mix, a: sv.a, b: sv.b, c: sv.c };
  const key = `${f.kind}|${v.mix.toFixed(3)}|${v.a.toFixed(3)}|${v.b.toFixed(3)}|${v.c.toFixed(3)}|${(v.type ?? 0).toFixed(3)}`;
  if (key !== view.key) {
    view.key = key;
    view.el.innerHTML = fxIconSvg(f.kind, v, view.size);
    view.dot = view.el.querySelector('.sc-dot');
  }
  // Подпись: эффект и значение тронутой ручки (на дорожке — посыл, в FX — параметр).
  const p = PARAM_BY_ID[f.param];
  if (p) {
    const val = f.mode === 'track' ? baseValue(i, f.param, locks ?? {}) : (fxHeld?.[f.param] ?? fx[f.param] ?? p.def);
    const text = `${f.mode === 'track' ? TRACK_LABEL[f.kind] : FX_LABEL[f.param] ?? p.label} ${p.format(val).replace('\n', ' ')}`;
    if (view.label.textContent !== text) view.label.textContent = text;
  }
  // SIDECHAIN: точка бежит по кривой за временем от последнего трига.
  if (view.dot) {
    const cv = scCurve(v);
    const att = Math.max(1, fx['sc.attack'] ?? 5), rel = fx['sc.release'] ?? 150;
    const ago = scTrigAgoMs();
    const [x, y] = ago === null || ago >= att + rel ? scPoint(cv, 'end', 1)
      : ago < att ? scPoint(cv, 'a', ago / att) : scPoint(cv, 'r', (ago - att) / rel);
    view.dot.setAttribute('cx', x.toFixed(1));
    view.dot.setAttribute('cy', y.toFixed(1));
  }
  return alpha;
}
