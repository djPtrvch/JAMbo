// Таблицы движка WTABLE: встроенные (генерируются здесь, без файлов) и свои (WAV из библиотеки).
// Таблица задаётся спектром каждого кадра (гармоники 1…1023 при кадре 2048); мипмапы по октавам
// строятся обратным FFT с обрезкой гармоник (уровень L — гармоники до 1024 >> L), в основном потоке,
// и передаются в AudioWorklet (jambo-synth-worklet.js) сообщением { type: 'table' }.
//
// Ключ таблицы дорожки (doc.tracks[i].table): '' — встроенная BASIC; 'builtin:NAME' — встроенная;
// 'wt:<ключ сэмпла>:<размер кадра>' — свой WAV (байты в хранилище сэмплов, storage.ts).

import { getSample } from '../storage';

export const TABLE_SIZE = 2048;
export const BUILTIN_FRAMES = 64;
export const MAX_FRAMES = 256;
export const MAX_TABLE_BYTES = 4 * 1024 * 1024;
export const FRAME_SIZES = [256, 512, 1024, 2048];
export const BUILTIN_TABLES = ['BASIC', 'PWM', 'ORGAN', 'FORMANT', 'DIGITAL', 'METAL'] as const;
const HARMONICS = TABLE_SIZE / 2 - 1;
/** Уровней мипмапа: гармоники 1024, 512, … 1. */
const LEVELS = 11;

export interface WtLevel { size: number; data: Float32Array }
export interface WtTable { frames: number; levels: WtLevel[] }

/** Ключ встроенной таблицы. */
export const builtinKey = (name: string) => (name === 'BASIC' ? '' : `builtin:${name}`);
/** Ключ своей таблицы: байты WAV (ключ сэмпла) и размер кадра. */
export const userTableKey = (sampleKey: string, frameSize: number) => `wt:${sampleKey}:${frameSize}`;
/** Ключ сэмпла (байты WAV) в ключе своей таблицы, иначе null. */
export function tableSampleKey(key: string): string | null {
  const m = /^wt:(s:[0-9a-f]+):\d+$/.exec(key);
  return m ? m[1] : null;
}
/** Имя таблицы для показа (свои — по имени из библиотеки, если известно). */
export function tableName(key: string, names?: Map<string, string>): string {
  if (!key) return 'BASIC';
  if (key.startsWith('builtin:')) return key.slice(8);
  return names?.get(key) ?? 'TABLE';
}

// ---------- FFT ----------

function fft(re: Float64Array, im: Float64Array, inverse = false) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      let t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }
  const sign = inverse ? 1 : -1;
  for (let len = 2; len <= n; len <<= 1) {
    const a = sign * 2 * Math.PI / len;
    const wr0 = Math.cos(a), wi0 = Math.sin(a);
    for (let i = 0; i < n; i += len) {
      let wr = 1, wi = 0;
      for (let k = 0; k < len / 2; k++) {
        const p = i + k, q = p + len / 2;
        const xr = re[q] * wr - im[q] * wi, xi = re[q] * wi + im[q] * wr;
        re[q] = re[p] - xr; im[q] = im[p] - xi;
        re[p] += xr; im[p] += xi;
        const t = wr * wr0 - wi * wi0;
        wi = wr * wi0 + wi * wr0;
        wr = t;
      }
    }
  }
}

/** Спектр кадров: для каждого кадра — re/im гармоник 1…HARMONICS (индекс n). */
interface Spectra { frames: number; re: Float64Array[]; im: Float64Array[] }

/**
 * Мипмапы по октавам из спектров кадров. perFrame — каждый кадр к пику 1.0 (встроенные таблицы:
 * громкость не скачет при движении POSITION), иначе вся таблица к пику 1.0 (свои — как в файле).
 */
function buildMips(sp: Spectra, perFrame = false): WtTable {
  const levels: WtLevel[] = [];
  const peaks = new Float64Array(sp.frames);
  for (let L = 0; L < LEVELS; L++) {
    const h = 1024 >> L;
    // Размер уровня: с запасом для линейной интерполяции (не меньше 4 отсчётов на старшую гармонику).
    const size = Math.min(TABLE_SIZE, Math.max(256, 4 * h));
    const lim = Math.min(h, size / 2 - 1, HARMONICS);
    const data = new Float32Array(sp.frames * size);
    const re = new Float64Array(size), im = new Float64Array(size);
    for (let f = 0; f < sp.frames; f++) {
      re.fill(0); im.fill(0);
      for (let n = 1; n <= lim; n++) {
        re[n] = sp.re[f][n]; im[n] = sp.im[f][n];
        re[size - n] = sp.re[f][n]; im[size - n] = -sp.im[f][n];
      }
      fft(re, im, true);
      for (let j = 0; j < size; j++) {
        data[f * size + j] = re[j];
        if (L === 0) peaks[f] = Math.max(peaks[f], Math.abs(re[j]));
      }
    }
    levels.push({ size, data });
  }
  const all = Math.max(...peaks);
  for (const l of levels) {
    for (let f = 0; f < sp.frames; f++) {
      const pk = perFrame ? peaks[f] : all;
      const g = pk > 0 ? 1 / pk : 1;
      for (let j = f * l.size; j < (f + 1) * l.size; j++) l.data[j] *= g;
    }
  }
  return { frames: sp.frames, levels };
}

/** Спектры из амплитуд (синусная фаза или своя) по функции amp(кадр 0..1, гармоника). */
function spectraFrom(frames: number, amp: (t: number, n: number) => number, phase: (t: number, n: number) => number = () => 0): Spectra {
  const re: Float64Array[] = [], im: Float64Array[] = [];
  for (let f = 0; f < frames; f++) {
    const t = frames > 1 ? f / (frames - 1) : 0;
    const r = new Float64Array(HARMONICS + 1), i = new Float64Array(HARMONICS + 1);
    for (let n = 1; n <= HARMONICS; n++) {
      const a = amp(t, n);
      if (!a) continue;
      // a·sin(nx + φ): коэффициент обратного FFT — (a/2)·e^{i(φ − π/2)}.
      const ph = phase(t, n) - Math.PI / 2;
      r[n] = a / 2 * Math.cos(ph); i[n] = a / 2 * Math.sin(ph);
    }
    re.push(r); im.push(i);
  }
  return { frames, re, im };
}

/** Детерминированный «случайный» генератор (одинаковые таблицы при каждом запуске). */
function rng(seed: number) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

const lerp = (a: number, b: number, u: number) => a + (b - a) * u;

/** Встроенные таблицы: 64 кадра × 2048 отсчётов. */
function builtinSpectra(name: string): Spectra {
  const F = BUILTIN_FRAMES;
  switch (name) {
    case 'PWM':
      // Импульс: ширина 50 % → 5 %.
      return spectraFrom(F, (t, n) => (2 / (n * Math.PI)) * Math.sin(n * Math.PI * lerp(0.5, 0.05, t)), () => Math.PI / 2);
    case 'ORGAN': {
      // Дроубары (гармоники 1, 2, 3, 4, 5, 6, 8, 10, 12, 16): регистровки сменяют друг друга.
      const bars = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16];
      const regs = [
        [8, 8, 0, 0, 0, 0, 0, 0, 0, 0], [8, 8, 8, 0, 0, 0, 0, 0, 0, 0], [8, 6, 8, 4, 0, 3, 0, 0, 0, 0],
        [8, 8, 8, 8, 0, 0, 0, 0, 0, 8], [6, 8, 8, 6, 4, 4, 3, 2, 2, 4], [8, 8, 8, 8, 8, 8, 8, 8, 8, 8],
      ];
      return spectraFrom(F, (t, n) => {
        const k = bars.indexOf(n);
        if (k < 0) return 0;
        const x = t * (regs.length - 1), i = Math.min(regs.length - 2, Math.floor(x));
        return lerp(regs[i][k], regs[i + 1][k], x - i) / 8 / Math.sqrt(n);
      });
    }
    case 'FORMANT': {
      // Гласные A, E, I, O, U аддитивно: огибающая трёх формант (тон таблицы ~110 Гц).
      const V = [[800, 1150, 2900], [400, 1600, 2700], [350, 2300, 3000], [450, 800, 2830], [325, 700, 2530]];
      return spectraFrom(F, (t, n) => {
        const x = t * (V.length - 1), i = Math.min(V.length - 2, Math.floor(x)), u = x - i;
        const hz = n * 110;
        if (hz > 6000) return 0;
        let a = 0;
        for (let k = 0; k < 3; k++) {
          const fc = lerp(V[i][k], V[i + 1][k], u), bw = 60 + fc * 0.08;
          a += [1, 0.6, 0.3][k] * Math.exp(-0.5 * ((hz - fc) / bw) ** 2);
        }
        return a;
      });
    }
    case 'DIGITAL': {
      // Наборы гармоник: число гармоник растёт с кадром, фазы случайные — «цифровой» тембр.
      const r = rng(7);
      const ph = Array.from({ length: HARMONICS + 1 }, () => r() * Math.PI * 2);
      return spectraFrom(F, (t, n) => {
        const top = 1 + Math.floor(t * 63);
        if (n > top * 4) return 0;
        return (n & (1 + Math.floor(t * 7))) || n === 1 ? 1 / Math.sqrt(n) : 0;
      }, (_, n) => ph[n]);
    }
    case 'METAL': {
      // Инхармонические партиалы (моды стержня), растянутые вверх с кадром — металлический тон.
      const modes = [1, 2.756, 5.404, 8.933, 13.344, 18.64];
      return spectraFrom(F, (t, n) => {
        const base = lerp(2, 14, t);
        let a = 0;
        modes.forEach((m, k) => { if (Math.round(m * base) === n) a += 1 / (k + 1); });
        return a + (n === 1 ? 0.3 : 0);
      });
    }
    default:
      // BASIC: синус → пила (первая половина кадров) → квадрат (вторая).
      return spectraFrom(F, (t, n) => {
        const saw = 1 / n, sq = n % 2 ? 1 / n : 0;
        if (t < 0.5) { const u = t * 2; return (n === 1 ? 1 - u : 0) + u * saw; }
        const u = (t - 0.5) * 2;
        return (1 - u) * saw + u * sq;
      });
  }
}

/** Спектры кадров из отсчётов WAV (кадр frameSize → гармоники в масштабе кадра 2048). */
function wavSpectra(samples: Float32Array, frameSize: number): Spectra {
  const frames = Math.max(1, Math.min(MAX_FRAMES, Math.floor(samples.length / frameSize)));
  const re: Float64Array[] = [], im: Float64Array[] = [];
  const a = new Float64Array(frameSize), b = new Float64Array(frameSize);
  const lim = Math.min(HARMONICS, frameSize / 2 - 1);
  for (let f = 0; f < frames; f++) {
    a.fill(0); b.fill(0);
    for (let j = 0; j < frameSize; j++) a[j] = samples[f * frameSize + j] ?? 0;
    fft(a, b);
    const r = new Float64Array(HARMONICS + 1), i = new Float64Array(HARMONICS + 1);
    for (let n = 1; n <= lim; n++) { r[n] = a[n] / frameSize; i[n] = b[n] / frameSize; }
    re.push(r); im.push(i);
  }
  return { frames, re, im };
}

// ---------- WAV ----------

export interface WavTable { samples: Float32Array; clm: number | null }

/** Разбор WAV (PCM 16/24 бит или float 32, моно; у стерео — левый канал) и метки 'clm ' (Serum). */
export function parseWav(buf: ArrayBuffer): WavTable {
  const v = new DataView(buf);
  const tag = (o: number) => String.fromCharCode(v.getUint8(o), v.getUint8(o + 1), v.getUint8(o + 2), v.getUint8(o + 3));
  if (buf.byteLength < 12 || tag(0) !== 'RIFF' || tag(8) !== 'WAVE') throw new Error('not a WAV');
  let fmt = 0, ch = 1, bits = 16, data: [number, number] | null = null, clm: number | null = null;
  for (let o = 12; o + 8 <= buf.byteLength;) {
    const id = tag(o), size = v.getUint32(o + 4, true), body = o + 8;
    if (id === 'fmt ') {
      fmt = v.getUint16(body, true); ch = v.getUint16(body + 2, true); bits = v.getUint16(body + 14, true);
      // WAVE_FORMAT_EXTENSIBLE: формат — в подформате.
      if (fmt === 0xfffe && size >= 26) fmt = v.getUint16(body + 24, true);
    } else if (id === 'data') {
      data = [body, Math.min(size, buf.byteLength - body)];
    } else if (id === 'clm ') {
      const text = new TextDecoder().decode(new Uint8Array(buf, body, Math.min(size, 64)));
      const m = /<!>\s*(\d+)/.exec(text);
      if (m) clm = Number(m[1]);
    }
    o = body + size + (size & 1);
  }
  if (!data) throw new Error('no data');
  const bytes = bits / 8, step = bytes * ch;
  const n = Math.floor(data[1] / step);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const p = data[0] + i * step;
    if (fmt === 3 && bits === 32) out[i] = v.getFloat32(p, true);
    else if (bits === 16) out[i] = v.getInt16(p, true) / 32768;
    else if (bits === 24) out[i] = ((v.getUint8(p) | (v.getUint8(p + 1) << 8) | (v.getInt8(p + 2) << 16))) / 8388608;
    else if (bits === 32) out[i] = v.getInt32(p, true) / 2147483648;
    else throw new Error('unsupported WAV');
  }
  return { samples: out, clm };
}

/** Размер кадра AUTO: по метке 'clm ', иначе наибольший из 2048…256, на который длина делится. */
export function autoFrameSize(w: WavTable): number {
  if (w.clm && FRAME_SIZES.includes(w.clm)) return w.clm;
  for (const s of [2048, 1024, 512, 256]) if (w.samples.length % s === 0 && w.samples.length / s <= MAX_FRAMES) return s;
  return 2048;
}

// ---------- Кэш таблиц ----------

const cache = new Map<string, WtTable>();
const loading = new Map<string, Promise<WtTable | null>>();

/** Таблица по ключу (встроенная — генерируется, своя — из хранилища); null — не найдена. */
export function getTable(key: string): Promise<WtTable | null> {
  const ready = cache.get(key);
  if (ready) return Promise.resolve(ready);
  let p = loading.get(key);
  if (!p) {
    p = (async () => {
      let t: WtTable | null = null;
      if (!key || key.startsWith('builtin:')) {
        t = buildMips(builtinSpectra(key ? key.slice(8) : 'BASIC'), true);
      } else {
        const m = /^wt:(s:[0-9a-f]+):(\d+)$/.exec(key);
        const rec = m ? await getSample(m[1]) : undefined;
        if (rec) t = buildMips(wavSpectra(parseWav(rec.bytes).samples, Number(m![2])));
      }
      if (t) cache.set(key, t);
      loading.delete(key);
      return t;
    })();
    loading.set(key, p);
  }
  return p;
}

/** Таблица, если уже готова (для рисования кадра в окне синта). */
export const readyTable = (key: string) => cache.get(key) ?? null;

/** Число кадров WAV при размере кадра (для подсказки при выборе размера). */
export const framesFor = (w: WavTable, size: number) => Math.min(MAX_FRAMES, Math.floor(w.samples.length / size));
