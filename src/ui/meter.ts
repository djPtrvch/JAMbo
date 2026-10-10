// Измеритель уровня в правом краю (сбоку от миниатюр страниц и кнопок).
// Показывает выбранную дорожку, а при выбранных MIX или MST — общий уровень микса.
// Стерео — две полосы, моно — одна; перегрузка — красная полоса. Снизу пик в dB, сверху LUFS.

import { masterLevels, trackIsStereo, trackLevel, type Level } from '../audio/engine';
import { ui } from '../state';
import { h, setAttr, setClass, setText } from './dom';

let lufsText: HTMLElement;
let dbText: HTMLElement;
const bars: { root: HTMLElement; fill: HTMLElement }[] = [];

/** Пик 0..1+ → доля высоты полосы (шкала −60…0 dBFS). */
export function levelFrac(peak: number): number {
  if (peak <= 0) return 0;
  const db = 20 * Math.log10(peak);
  return Math.min(1, Math.max(0, (db + 60) / 60));
}

export const fmtDb = (peak: number) => (peak > 0.001 ? `${(20 * Math.log10(peak)).toFixed(1)}` : '−∞');
export const fmtLufs = (l: number) => (Number.isFinite(l) ? l.toFixed(1) : '−∞');

export function buildMeter(): HTMLElement {
  const el = h('div', 'meter');
  lufsText = h('div', 'meter-text');
  dbText = h('div', 'meter-text');
  const box = h('div', 'meter-bars');
  for (let i = 0; i < 2; i++) {
    const root = h('div', 'meter-bar');
    const fill = h('div', 'meter-fill');
    root.append(fill);
    bars.push({ root, fill });
    box.append(root);
  }
  el.append(lufsText, box, dbText);
  return el;
}

export function renderMeter(now: number) {
  const master = ui.channel !== 'track';
  const lv: Level = master ? masterLevels(now).out : trackLevel(ui.selectedTrack, now);
  const stereo = master || trackIsStereo(ui.selectedTrack);
  const peaks = stereo ? [lv.l, lv.r] : [Math.max(lv.l, lv.r)];
  bars.forEach((b, i) => {
    setClass(b.root, 'hidden', i >= peaks.length);
    if (i >= peaks.length) return;
    setAttr(b.fill, 'style', `height:${(levelFrac(peaks[i]) * 100).toFixed(1)}%`);
    setClass(b.fill, 'clip', lv.clip);
  });
  setText(lufsText, `LUFS\n${fmtLufs(lv.lufs)}`);
  setText(dbText, `${fmtDb(Math.max(lv.l, lv.r))}\ndB`);
}
