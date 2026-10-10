// Измеритель уровня в правом краю (сбоку от миниатюр страниц и кнопок).
// Показывает выбранную дорожку, а при выбранных MIX или MST — общий выход мастера после лимитера.
// Стерео — две полосы, моно — одна; шкала в dB, пик-холд (~1,5 с), метка клиппинга сверху,
// выше 0 dB полоса красная. Снизу пик в dB, сверху громкость в LUFS.

import { masterLevels, trackIsStereo, trackLevel, type Level } from '../audio/engine';
import { OVER_PEAK } from '../params';
import { ui } from '../state';
import { h, setAttr, setClass, setText } from './dom';

let lufsText: HTMLElement;
let dbText: HTMLElement;
let clipMark: HTMLElement;
const bars: { root: HTMLElement; fill: HTMLElement; hold: HTMLElement }[] = [];

/** Отметки шкалы в dB. */
export const SCALE_DB = [0, -6, -12, -24, -48];

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
  clipMark = h('div', 'vbar-clip');
  const box = h('div', 'meter-bars');
  for (let i = 0; i < 2; i++) {
    const root = h('div', 'meter-bar');
    const fill = h('div', 'meter-fill');
    const hold = h('div', 'vbar-hold');
    root.append(fill, hold);
    bars.push({ root, fill, hold });
    box.append(root);
  }
  for (const db of SCALE_DB) {
    const t = h('div', 'meter-tick');
    t.style.bottom = `${((db + 60) / 60) * 100}%`;
    box.append(t);
  }
  el.append(lufsText, clipMark, box, dbText);
  return el;
}

export function renderMeter(now: number) {
  const master = ui.channel !== 'track';
  const lv: Level = master ? masterLevels(now).out : trackLevel(ui.selectedTrack, now);
  const stereo = master || trackIsStereo(ui.selectedTrack);
  const peaks = stereo ? [lv.l, lv.r] : [Math.max(lv.l, lv.r)];
  const holds = stereo ? [lv.holdL, lv.holdR] : [Math.max(lv.holdL, lv.holdR)];
  bars.forEach((b, i) => {
    setClass(b.root, 'hidden', i >= peaks.length);
    if (i >= peaks.length) return;
    setAttr(b.fill, 'style', `height:${(levelFrac(peaks[i]) * 100).toFixed(1)}%`);
    setClass(b.fill, 'clip', peaks[i] >= OVER_PEAK);
    setClass(b.hold, 'hidden', holds[i] < 0.001);
    setAttr(b.hold, 'style', `bottom:${(levelFrac(holds[i]) * 100).toFixed(1)}%`);
  });
  setClass(clipMark, 'on', lv.clip);
  setText(lufsText, `LUFS\n${fmtLufs(lv.lufs)}`);
  setText(dbText, `${fmtDb(Math.max(lv.l, lv.r))}\ndB`);
}
