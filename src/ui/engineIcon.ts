// Живые иконки движков: в плитке дорожки и крупно в окне сэмпла. Значения — как на ручках:
// база дорожки, p-lock (зажатый шаг — его значения, при игре — играющего шага), поверх LFO/ENV.
// Пока палец держит ручку 1.1–1.3 или Decay выбранной дорожки, связанная часть иконки оранжевая.
// Перерисовка — в общем кадре (requestAnimationFrame); SVG пересобирается, только когда изменились
// значения или подсветка.

import { iconSvg, type IconParam, type IconValues } from '../engineIcons';
import { TRACK_GRID, stepIndex, synthEngine, synthGrid, type ParamDef } from '../params';
import { doc, firstHeldStep, heldStepSound, liveLocks, modulatedNorm, seqAt, ui } from '../state';
import { heldIconParam } from './knobs';

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
    let n = modulatedNorm(i, p, locks?.[p.id] ?? t.params[p.id]);
    // Ступенчатая ручка — скачком по пункту.
    if (p.steps) n = (stepIndex(n, p.steps) + 0.5) / p.steps;
    v[k] = n;
  }
  return { id: engine !== null ? String(engine) : 's', v };
}

export function renderIcon(view: IconView, track: number, now: number) {
  const icon = iconFor(track, now);
  const hl = icon && ui.channel === 'track' && track === ui.selectedTrack ? heldIconParam() : null;
  const key = icon ? `${icon.id}|${icon.v.h.toFixed(3)}|${icon.v.t.toFixed(3)}|${icon.v.m.toFixed(3)}|${icon.v.d!.toFixed(3)}|${hl ?? ''}` : '';
  if (key === view.key) return;
  view.key = key;
  view.el.innerHTML = icon ? iconSvg(icon.id, icon.v, hl, view.size) : '';
}
