// Измеритель уровня в правом краю (сбоку от миниатюр страниц и кнопок).
// Показывает выбранную дорожку, а при выбранных MIX или MST — общий выход мастера после лимитера.
// Стерео — две полосы, моно — одна; шкала в dB, пик-холд (~1,5 с), метка клиппинга сверху,
// выше 0 dB полоса красная. Снизу максимальный пик в dB, сверху интегральная громкость в LUFS (как
// в Grand Finale): оба копятся с последнего сброса; тап по числу — его сброс (отсчёт заново).
// При смене канала измерителя сбрасываются оба.
// При MST поверх полос — регулятор громкости выхода (после лимитера): палец вверх-вниз двигает его,
// метр показывает оконечный сигнал уже после этой громкости.

import { masterLevels, resetLoudness, resetPeak, trackIsStereo, trackLevel, type Level } from '../audio/engine';
import { OVER_PEAK, VOL_MIN_DB, fmtVol } from '../params';
import { beginGesture, doc, endGesture, setOutVol, ui } from '../state';
import { h, setAttr, setClass, setText } from './dom';

let lufsText: HTMLElement;
let dbText: HTMLElement;
let clipMark: HTMLElement;
const bars: { root: HTMLElement; fill: HTMLElement; hold: HTMLElement }[] = [];
let volThumb: HTMLElement;
/** Палец на регуляторе громкости: пока держат — снизу его значение. */
let volDrag = false;
/** Ход пальца на всю шкалу регулятора, px. */
const VOL_TRAVEL_PX = 240;

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
  // Регулятор громкости выхода мастера (виден при MST): положение — по той же шкале dB, что и полосы.
  volThumb = h('div', 'meter-vol hidden');
  box.append(volThumb);
  let id = -1;
  let y0 = 0;
  let v0 = 0;
  box.addEventListener('pointerdown', (e) => {
    if (ui.channel !== 'master') return;
    e.preventDefault();
    box.setPointerCapture(e.pointerId);
    id = e.pointerId;
    y0 = e.clientY;
    v0 = doc.outVol;
    volDrag = true;
    beginGesture();
  });
  box.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id) return;
    setOutVol(v0 + ((y0 - e.clientY) / VOL_TRAVEL_PX) * -VOL_MIN_DB);
  });
  const up = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = -1;
    volDrag = false;
    endGesture();
  };
  box.addEventListener('pointerup', up);
  box.addEventListener('pointercancel', up);
  el.append(lufsText, clipMark, box, dbText);
  return el;
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
  const vol = ui.channel === 'master';
  setClass(volThumb, 'hidden', !vol);
  if (vol) setAttr(volThumb, 'style', `bottom:${(((doc.outVol - VOL_MIN_DB) / -VOL_MIN_DB) * 100).toFixed(1)}%`);
  setText(dbText, vol && volDrag ? `VOL\n${fmtVol(doc.outVol).replace(' dB', '')}` : `${fmtDb(lv.max)}\ndB`);
}
