// Экран отладки (тройной тап по индикатору CPU): задержка отклика.
// MUTE/SOLO — от pointerdown на дорожке и от события, на котором сработал свайп, до установки
// гейтов (звук) и до следующего кадра (экран). PLAY — от касания кнопки до того, как первый шаг
// поставлен в звук, и до следующего кадра; плюс насколько первая нота стоит позже «сейчас» звука.

import { audioInfo, audioState } from '../audio/engine';
import { h, setText } from './dom';

const KEEP = 20;
type Row = [label: string, values: number[]];
const rows = new Map<string, number[]>();
const order: string[] = [];
let panel: HTMLElement | null = null;

function add(label: string, v: number) {
  if (!rows.has(label)) { rows.set(label, []); order.push(label); }
  const a = rows.get(label)!;
  a.push(v);
  if (a.length > KEEP) a.shift();
}

// ---------- MUTE / SOLO ----------
let down = 0;
let move = 0;
let handler = 0;
let pending = false;

/** Свайп по дорожке сработал: время pointerdown и события, на котором прошёл порог (performance.now). */
export function markSwipe(downT: number, moveT: number) { down = downT; move = moveT; handler = performance.now(); pending = true; }

/** Звук mute/solo выставлен (время вызова applyAllGates). */
export function markGate(t: number) {
  if (!pending) return;
  pending = false;
  const d = down, m = move, hd = handler;
  add('mute: pointerdown → gate', t - d);
  add('mute: swipe event → gate', t - m);
  add('mute: handler → gate', t - hd);
  requestAnimationFrame(() => {
    const f = performance.now();
    add('mute: pointerdown → frame', f - d);
    add('mute: swipe event → frame', f - m);
    render();
  });
}

// ---------- PLAY ----------
/** PLAY нажата: время события касания; вызывать после того, как первый шаг поставлен в звук. */
let playState = '—';
export function markPlay(eventT: number) {
  const t = performance.now();
  playState = audioState();
  add('play: touch → step scheduled', t - eventT);
  requestAnimationFrame(() => {
    add('play: touch → frame', performance.now() - eventT);
    render();
  });
}

/** Первая нота после PLAY: насколько позже текущего времени звука она поставлена (с). */
export function markPlayNote(aheadSec: number) {
  add('play: note after audio "now"', aheadSec * 1000);
}

const ms = (v: number) => `${v.toFixed(1)} ms`;

function line([label, v]: Row): string {
  const avg = v.reduce((a, b) => a + b, 0) / v.length;
  return `${label.padEnd(30)} last ${ms(v[v.length - 1]).padStart(9)}   avg ${ms(avg).padStart(9)}   max ${ms(Math.max(...v)).padStart(9)}`;
}

function render() {
  if (!panel) return;
  const a = audioInfo();
  const out = a.state === 'none' ? '—' : ms((a.baseLatency + a.outputLatency) * 1000);
  const lines = ['LATENCY (swipe a track, press PLAY)', `last ${KEEP} of each`, ''];
  if (order.length) lines.push(...order.map((k) => line([k, rows.get(k)!])));
  else lines.push('nothing measured yet');
  lines.push('', `audio state at last PLAY: ${playState}`, `audio output latency (base + output): ${out}`, '', 'mute: pointerdown → … includes the finger travel (24 px).', 'Tap to close.');
  setText(panel, lines.join('\n'));
}

/** Тройной тап по элементу открывает и закрывает экран отладки. */
export function attachDebug(el: HTMLElement) {
  let taps: number[] = [];
  el.addEventListener('pointerdown', () => {
    const t = performance.now();
    taps = [...taps.filter((x) => t - x < 600), t];
    if (taps.length < 3) return;
    taps = [];
    toggle();
  });
}

function toggle() {
  if (panel) { panel.remove(); panel = null; return; }
  panel = h('div', 'debug-panel');
  panel.addEventListener('pointerdown', (e) => { e.stopPropagation(); toggle(); });
  document.body.append(panel);
  render();
}
