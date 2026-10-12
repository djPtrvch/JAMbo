// Экран отладки (тройной тап по индикатору CPU): задержка mute/solo — от pointerdown на дорожке
// и от события, на котором сработал свайп, до вызова applyAllGates (звук) и до следующего кадра (экран).

import { audioInfo } from '../audio/engine';
import { h, setText } from './dom';

const KEEP = 20;
interface Sample { gate: number; frame: number; gateMove: number; frameMove: number; handler: number }
const samples: Sample[] = [];
let down = 0;
let move = 0;
let handler = 0;
let pending = false;
let panel: HTMLElement | null = null;

/** Свайп по дорожке сработал: время pointerdown и события, на котором прошёл порог (performance.now). */
export function markSwipe(downT: number, moveT: number) { down = downT; move = moveT; handler = performance.now(); pending = true; }

/** Звук mute/solo выставлен (время вызова applyAllGates). */
export function markGate(t: number) {
  if (!pending) return;
  pending = false;
  const s: Sample = { gate: t - down, gateMove: t - move, handler: t - handler, frame: 0, frameMove: 0 };
  requestAnimationFrame(() => {
    const f = performance.now();
    s.frame = f - down;
    s.frameMove = f - move;
    samples.push(s);
    if (samples.length > KEEP) samples.shift();
    render();
  });
}

const ms = (v: number) => `${v.toFixed(1)} ms`;

function row(label: string, pick: (s: Sample) => number): string {
  const v = samples.map(pick);
  const last = v[v.length - 1];
  const avg = v.reduce((a, b) => a + b, 0) / v.length;
  return `${label.padEnd(22)} last ${ms(last).padStart(9)}   avg ${ms(avg).padStart(9)}   max ${ms(Math.max(...v)).padStart(9)}`;
}

function render() {
  if (!panel) return;
  const a = audioInfo();
  const out = a.state === 'none' ? '—' : ms((a.baseLatency + a.outputLatency) * 1000);
  const lines = [
    'MUTE / SOLO LATENCY (swipe a track)',
    `samples: ${samples.length} (last ${KEEP})`,
    '',
  ];
  if (samples.length) {
    lines.push(
      row('pointerdown → gate', (s) => s.gate),
      row('pointerdown → frame', (s) => s.frame),
      row('swipe event → gate', (s) => s.gateMove),
      row('swipe event → frame', (s) => s.frameMove),
      row('handler → gate', (s) => s.handler),
    );
  } else lines.push('no swipes yet');
  lines.push('', `audio output latency (base + output): ${out}`, '', 'pointerdown → … includes the finger travel (24 px).', 'Tap to close.');
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
