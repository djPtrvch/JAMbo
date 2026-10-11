// Измеритель уровня в правом краю (сбоку от миниатюр страниц и кнопок).
// Показывает выбранную дорожку, а при выбранных MIX или MST — общий выход мастера после лимитера.
// Стерео — две полосы, моно — одна; шкала в dB, пик-холд (~1,5 с), метка клиппинга сверху,
// выше 0 dB полоса красная. Снизу максимальный пик в dB, сверху интегральная громкость в LUFS (как
// в Grand Finale): оба копятся с последнего сброса; тап по числу — его сброс (отсчёт заново).
// При смене канала измерителя сбрасываются оба.

import { masterLevels, resetLoudness, resetPeak, trackIsStereo, trackLevel, type Level } from '../audio/engine';
import { OVER_PEAK } from '../params';
import { beginGesture, endGesture, setMorphAmount, ui } from '../state';
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
  lufsText = h('div', 'meter-text meter-lufs');
  lufsText.addEventListener('pointerdown', (e) => { e.preventDefault(); resetLoudness(source()); });
  dbText = h('div', 'meter-text meter-lufs');
  dbText.addEventListener('pointerdown', (e) => { e.preventDefault(); resetPeak(source()); });
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
  // Кроссфейдер MORPH: пока режим включён, стоит на месте измерителя. Вверху — все изменения
  // MORPH, опускание плавно возвращает исходные значения; внизу режим выключается.
  morphEl = h('div', 'morph-fader hidden');
  const track = h('div', 'xf-track mf-track');
  morphFill = h('div', 'xf-fill mf-fill');
  morphThumb = h('div', 'xf-thumb mf-thumb');
  track.append(morphFill, morphThumb);
  morphEl.append(h('div', 'mf-label', 'MRPH'), track, h('div', 'mf-label', 'OFF'));
  let id = -1;
  const setFrom = (y: number) => {
    const r = track.getBoundingClientRect();
    setMorphAmount(1 - (y - r.top) / r.height);
  };
  morphEl.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    morphEl.setPointerCapture(e.pointerId);
    id = e.pointerId;
    beginGesture();
    setFrom(e.clientY);
  });
  morphEl.addEventListener('pointermove', (e) => { if (e.pointerId === id && ui.morph) setFrom(e.clientY); });
  const up = (e: PointerEvent) => { if (e.pointerId === id) { id = -1; endGesture(); } };
  morphEl.addEventListener('pointerup', up);
  morphEl.addEventListener('pointercancel', up);
  meterParts = [lufsText, clipMark, box, dbText];
  el.append(lufsText, clipMark, box, dbText, morphEl);
  return el;
}

let morphEl: HTMLElement;
let morphFill: HTMLElement;
let morphThumb: HTMLElement;
let meterParts: HTMLElement[] = [];

/** MORPH включён — вместо измерителя кроссфейдер. */
function renderMorphFader(): boolean {
  setClass(morphEl, 'hidden', !ui.morph);
  for (const e of meterParts) setClass(e, 'hidden', ui.morph);
  if (!ui.morph) return false;
  const pct = `${(ui.morphAmt * 100).toFixed(1)}%`;
  setAttr(morphThumb, 'style', `bottom:${pct}`);
  setAttr(morphFill, 'style', `height:${pct}`);
  return true;
}

/** Что показывает измеритель: дорожка или выход мастера (при MIX и MST). */
const source = (): number | 'master' => (ui.channel === 'track' ? ui.selectedTrack : 'master');
let shown: number | 'master' | null = null;

/** Уровень показанного канала; при смене канала интегральная громкость считается заново. */
function measure(now: number): Level {
  const src = source();
  if (src !== shown) { shown = src; resetLoudness(src); resetPeak(src); }
  return src === 'master' ? masterLevels(now).out : trackLevel(src, now);
}

/** Измеритель скрыт (сетка паттернов) — громкость всё равно копится. */
export function tickMeter(now: number) {
  measure(now);
}

export function renderMeter(now: number) {
  const master = ui.channel !== 'track';
  const lv: Level = measure(now);
  if (renderMorphFader()) return;
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
  setText(lufsText, `LUFS\n${fmtLufs(lv.lufsI)}`);
  setText(dbText, `${fmtDb(lv.max)}\ndB`);
}
