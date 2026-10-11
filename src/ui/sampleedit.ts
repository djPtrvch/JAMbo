// Редактор сэмпла: удержание окна сэмпла открывает его на месте центра экрана (как EQ, справа
// остаётся измеритель уровня). Форма волны сэмпла выбранной дорожки (стерео — L и R) и два маркера
// обрезки: палец тянет ближайший маркер (можно оба сразу двумя пальцами), над пальцем — время.
// Внизу: имя, длина и выделение; LOAD (файл с iPad — в папку дорожки, как SAMPLE), SAVE (WAV в
// «Файлы»), TRIM (оставить выделенное), NORMALIZE (пик −0.1 dBFS), MONO (среднее L и R), CLOSE.
// TRIM, NORMALIZE и MONO сразу ставят на дорожку отредактированную копию (в папке — на месте
// исходного сэмпла); UNDO в верхней панели возвращает исходный.

import { addEditedSample, downloadSample, loadSampleFiles, sampleBuffer } from '../audio/engine';
import { synthEngine } from '../params';
import { doc, replaceSample, sampleName, toggleView, ui } from '../state';
import { h, setClass, setText } from './dom';

/** NORMALIZE: пик сэмпла, dBFS (чуть ниже 0 dB — метры не горят красным). */
const PEAK_DB = -0.1;

let panel: HTMLElement;
let plot: HTMLElement;
let canvas: HTMLCanvasElement;
let note: HTMLElement;
let nameText: HTMLElement;
let tip: HTMLElement;
let trimBtn: HTMLElement;
let normBtn: HTMLElement;
let monoBtn: HTMLElement;
let saveBtn: HTMLElement;
const tools: HTMLElement[] = [];

/** Маркеры обрезки (доля длины 0..1) для сэмпла key. */
const mark = { key: '', a: 0, b: 1 };
/** Какой палец какой маркер тянет. */
const drags = new Map<number, 'a' | 'b'>();
let busy = false;
let W = 0;
let H = 0;
/** Огибающая для текущей ширины: min/max по пикселям, по каналам. */
let env: { key: string; w: number; min: Float32Array[]; max: Float32Array[] } | null = null;

/** Сэмпл выбранной дорожки (не синт) или ''. */
function currentKey(): string {
  if (ui.channel !== 'track') return '';
  const s = doc.tracks[ui.selectedTrack].sample;
  return s && synthEngine(s) === null ? s : '';
}

const fmtTime = (s: number) => (s < 10 ? `${s.toFixed(3)} s` : `${s.toFixed(2)} s`);

function tool(label: string, fn: () => void): HTMLElement {
  const el = h('div', 'btn eq-tool', label);
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    if (!el.classList.contains('disabled') && !busy) fn();
  });
  tools.push(el);
  return el;
}

/** Каналы выделения или всего сэмпла. */
function channels(buf: AudioBuffer, from = 0, to = buf.length): Float32Array[] {
  return Array.from({ length: buf.numberOfChannels }, (_, c) => buf.getChannelData(c).slice(from, to));
}

/** Применить правку: новый сэмпл из data — на дорожку. */
async function apply(key: string, data: Float32Array[], rate: number) {
  busy = true;
  try {
    const track = ui.selectedTrack;
    const next = await addEditedSample(key, data, rate);
    replaceSample(track, key, next);
    mark.key = next;
    mark.a = 0;
    mark.b = 1;
  } catch (e) {
    console.error('sample edit', e);
    window.alert('Could not edit the sample');
  } finally {
    busy = false;
  }
}

function trim() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  void apply(key, channels(buf, Math.floor(mark.a * buf.length), Math.ceil(mark.b * buf.length)), buf.sampleRate);
}

function normalize() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf) return;
  const data = channels(buf);
  let peak = 0;
  for (const d of data) for (let i = 0; i < d.length; i++) peak = Math.max(peak, Math.abs(d[i]));
  if (peak <= 0) return;
  const g = Math.pow(10, PEAK_DB / 20) / peak;
  for (const d of data) for (let i = 0; i < d.length; i++) d[i] *= g;
  void apply(key, data, buf.sampleRate);
}

function mono() {
  const key = currentKey();
  const buf = sampleBuffer(key);
  if (!buf || buf.numberOfChannels < 2) return;
  const data = channels(buf);
  const out = new Float32Array(buf.length);
  for (const d of data) for (let i = 0; i < d.length; i++) out[i] += d[i] / data.length;
  void apply(key, [out], buf.sampleRate);
}

// ---------- Маркеры ----------

function frac(e: PointerEvent): number {
  const r = canvas.getBoundingClientRect();
  return Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
}

function down(e: PointerEvent) {
  if (!currentKey()) return;
  e.preventDefault();
  canvas.setPointerCapture(e.pointerId);
  const x = frac(e);
  const used = new Set(drags.values());
  // Ближайший свободный маркер (второй палец берёт другой).
  let m: 'a' | 'b' = Math.abs(x - mark.a) <= Math.abs(x - mark.b) ? 'a' : 'b';
  if (used.has(m)) m = m === 'a' ? 'b' : 'a';
  if (used.has(m)) return;
  drags.set(e.pointerId, m);
  move(e);
}

function move(e: PointerEvent) {
  const m = drags.get(e.pointerId);
  if (!m) return;
  const buf = sampleBuffer(currentKey());
  // Между маркерами — не меньше 64 сэмплов.
  const gap = buf ? Math.min(0.5, 64 / buf.length) : 0.001;
  const x = frac(e);
  if (m === 'a') mark.a = Math.min(x, mark.b - gap);
  else mark.b = Math.max(x, mark.a + gap);
  mark.a = Math.max(0, mark.a);
  mark.b = Math.min(1, mark.b);
  // Подсказка над пальцем: время маркера.
  if (buf) {
    const r = plot.getBoundingClientRect();
    tip.style.left = `${Math.min(W - 50, Math.max(50, e.clientX - r.left))}px`;
    tip.style.top = `${Math.max(4, e.clientY - r.top - 70)}px`;
    setText(tip, `${m === 'a' ? 'START' : 'END'}\n${fmtTime((m === 'a' ? mark.a : mark.b) * buf.duration)}`);
  }
  setClass(tip, 'hidden', !buf);
}

function up(e: PointerEvent) {
  drags.delete(e.pointerId);
  if (!drags.size) setClass(tip, 'hidden', true);
}

// ---------- Построение ----------

export function buildSampleEditor(): HTMLElement {
  panel = h('div', 'eq-panel sedit hidden');
  plot = h('div', 'eq-plot');
  canvas = document.createElement('canvas');
  canvas.className = 'eq-canvas';
  note = h('div', 'sedit-note hidden');
  tip = h('div', 'eq-tip hidden');
  plot.append(canvas, note, tip);
  canvas.addEventListener('pointerdown', down);
  canvas.addEventListener('pointermove', move);
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);

  const bar = h('div', 'eq-bar');
  nameText = h('div', 'eq-name sedit-name');
  // LOAD — поле выбора файла прозрачно поверх кнопки (на iOS выбор файла — только прямым тапом).
  const load = h('div', 'btn eq-tool sample-pick', 'LOAD');
  const input = h('input', 'sample-file');
  input.type = 'file';
  input.multiple = true;
  input.accept = 'audio/*,.wav,.wave,.aif,.aiff,.mp3,.m4a,.aac,.caf,.flac,.ogg';
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? []);
    input.value = '';
    if (files.length && ui.channel === 'track') void loadSampleFiles(files).catch(() => window.alert('Could not open the file as audio'));
  });
  load.append(input);
  trimBtn = tool('TRIM', trim);
  normBtn = tool('NORMALIZE', normalize);
  monoBtn = tool('MONO', mono);
  saveBtn = tool('SAVE', () => downloadSample(currentKey()));
  const close = tool('CLOSE', () => toggleView('sample'));
  // LOAD и SAVE рядом, за ними правки.
  bar.append(nameText, h('div', 'sedit-space'), load, saveBtn, trimBtn, normBtn, monoBtn, close);
  panel.append(plot, bar);
  return panel;
}

/** Удержание окна сэмпла: открыть редактор. */
export function openSampleEditor() {
  if (!ui.sampleView) toggleView('sample');
}

// ---------- Отрисовка (каждый кадр, пока открыт) ----------

function envelope(key: string, buf: AudioBuffer, w: number) {
  if (env && env.key === key && env.w === w) return env;
  const chans = Math.min(2, buf.numberOfChannels);
  const min = Array.from({ length: chans }, () => new Float32Array(w));
  const max = Array.from({ length: chans }, () => new Float32Array(w));
  for (let c = 0; c < chans; c++) {
    const d = buf.getChannelData(c);
    for (let x = 0; x < w; x++) {
      const i0 = Math.floor((x / w) * d.length);
      const i1 = Math.max(i0 + 1, Math.floor(((x + 1) / w) * d.length));
      let lo = 0;
      let hi = 0;
      for (let i = i0; i < i1; i++) { const v = d[i]; if (v < lo) lo = v; if (v > hi) hi = v; }
      min[c][x] = lo;
      max[c][x] = hi;
    }
  }
  env = { key, w, min, max };
  return env;
}

export function renderSampleEditor() {
  setClass(panel, 'hidden', !ui.sampleView);
  if (!ui.sampleView) return;
  const key = currentKey();
  const buf = key ? sampleBuffer(key) : null;
  if (key !== mark.key) { mark.key = key; mark.a = 0; mark.b = 1; drags.clear(); }

  const full = mark.a <= 0 && mark.b >= 1;
  setClass(trimBtn, 'disabled', !buf || full);
  setClass(normBtn, 'disabled', !buf);
  setClass(monoBtn, 'disabled', !buf || buf.numberOfChannels < 2);
  setClass(saveBtn, 'disabled', !buf);
  for (const t of tools) setClass(t, 'busy', busy);

  setClass(note, 'hidden', !!buf);
  setText(note, ui.channel !== 'track' ? 'Select a track to edit its sample.'
    : key ? 'Loading…' : 'No sample on this track — LOAD a file.');
  if (buf) {
    const sel = (mark.b - mark.a) * buf.duration;
    setText(nameText, `${sampleName(key)}\n${full ? fmtTime(buf.duration) : `${fmtTime(sel)} of ${fmtTime(buf.duration)}`}${buf.numberOfChannels > 1 ? ' · ST' : ' · M'}`);
  } else setText(nameText, 'SAMPLE\nEDITOR');

  const dpr = window.devicePixelRatio || 1;
  W = plot.clientWidth;
  H = plot.clientHeight;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const g = canvas.getContext('2d')!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, W, H);
  if (!buf) return;

  // Форма волны: каналы полосами (L сверху, R снизу), центр — линия.
  const e = envelope(key, buf, Math.max(1, Math.round(W)));
  const lanes = e.min.length;
  const lh = H / lanes;
  for (let c = 0; c < lanes; c++) {
    const mid = lh * c + lh / 2;
    const amp = lh / 2 - 6;
    g.fillStyle = '#e6e8eb';
    for (let x = 0; x < e.w; x++) {
      const y0 = mid - e.max[c][x] * amp;
      const y1 = mid - e.min[c][x] * amp;
      g.fillRect(x, y0, 1, Math.max(1, y1 - y0));
    }
    g.fillStyle = '#2f3338';
    g.fillRect(0, mid, W, 1);
    if (lanes > 1) {
      g.fillStyle = '#7d838c';
      g.font = '11px -apple-system, system-ui, sans-serif';
      g.fillText(c ? 'R' : 'L', 8, lh * c + 16);
    }
  }
  // Отрезаемое — затемнено, маркеры — жёлтые линии с ручками сверху и снизу.
  const xa = mark.a * W;
  const xb = mark.b * W;
  g.fillStyle = 'rgba(17, 18, 20, 0.72)';
  g.fillRect(0, 0, xa, H);
  g.fillRect(xb, 0, W - xb, H);
  g.fillStyle = '#ffd23f';
  for (const [x, right] of [[xa, false], [xb, true]] as [number, boolean][]) {
    g.fillRect(Math.round(x) - 1, 0, 2, H);
    const hx = right ? x - 22 : x;
    g.fillRect(hx, 0, 22, 22);
    g.fillRect(hx, H - 22, 22, 22);
  }
}
