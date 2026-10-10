// Единая таблица параметров: названия, подписи ручек, диапазоны и форматы.
// Меняем подписи и диапазоны только здесь.

export type KnobKind = 'smooth' | 'stepped';

export interface ParamDef {
  id: string;
  label: string;
  /** Подпись для MI-движков (появится позже). */
  alt?: string;
  kind: KnobKind;
  min: number;
  max: number;
  def: number;
  /** Экспоненциальная шкала (частоты, Гц). */
  exp?: boolean;
  /** Дуга рисуется от центра (Pan, Pitch, Invert). */
  bipolar?: boolean;
  /** Подписи ступеней для ступенчатых ручек (значение = индекс). */
  options?: string[];
  format: (v: number) => string;
}

/** Ячейка сетки 4×4: параметр или неактивная (серая) ручка. */
export type Slot = ParamDef | null;

const pct = (v: number) => `${Math.round(v)}%`;
const ms = (v: number) => (v >= 1000 ? `${(v / 1000).toFixed(2)}s` : `${Math.round(v)}ms`);
const hz = (v: number) => (v >= 1000 ? `${(v / 1000).toFixed(1)}k` : v >= 100 ? `${Math.round(v)}` : `${v.toFixed(1)}`);
const lfoHz = (v: number) => (v < 1 ? `${v.toFixed(2)}Hz` : `${v.toFixed(1)}Hz`);
/** Двухполярный фильтр: влево от центра — low pass, вправо — high pass, в центре выключен. */
export function filterFreq(v: number): { type: 'off' | 'lp' | 'hp'; hz: number } {
  if (Math.abs(v) < 0.5) return { type: 'off', hz: 0 };
  if (v < 0) return { type: 'lp', hz: 20000 * Math.pow(30 / 20000, -v / 100) };
  return { type: 'hp', hz: 20 * Math.pow(10000 / 20, v / 100) };
}
const filterFormat = (v: number) => {
  const f = filterFreq(v);
  return f.type === 'off' ? 'OFF' : `${f.type === 'lp' ? 'LP' : 'HP'} ${hz(f.hz)}`;
};
const opt = (options: string[]) => (v: number) => options[Math.round(v)] ?? '';

function smooth(id: string, label: string, min: number, max: number, def: number, format: (v: number) => string, extra: Partial<ParamDef> = {}): ParamDef {
  return { id, label, kind: 'smooth', min, max, def, format, ...extra };
}

function stepped(id: string, label: string, options: string[], def = 0): ParamDef {
  return { id, label, kind: 'stepped', min: 0, max: options.length - 1, def, options, format: opt(options) };
}

/** Колонки → сетка 4×4 в порядке отображения (ряд за рядом). */
function grid(columns: Slot[][]): Slot[] {
  const out: Slot[] = [];
  for (let row = 0; row < 4; row++) for (let col = 0; col < 4; col++) out.push(columns[col][row] ?? null);
  return out;
}

// ---------- Основная сетка дорожки ----------

export const TRACK_GRID: Slot[] = grid([
  [
    smooth('pitch', 'Pitch', -24, 24, 0, (v) => `${v > 0 ? '+' : ''}${v.toFixed(1)}st`, { alt: 'Harmonics', bipolar: true }),
    smooth('start', 'Start', 0, 100, 0, pct, { alt: 'Timbre' }),
    smooth('end', 'End', 0, 100, 100, pct, { alt: 'Morph' }),
    smooth('level', 'Level', 0, 127, 100, (v) => `${Math.round(v)}`),
  ],
  [
    smooth('attack', 'Attack', 0, 2000, 0, ms),
    smooth('decay', 'Decay', 0, 4000, 500, ms),
    smooth('filter', 'Filter', -100, 100, 0, filterFormat, { bipolar: true }),
    smooth('reso', 'Resonance', 0, 100, 0, pct),
  ],
  [
    smooth('reverb', 'Reverb', 0, 100, 0, pct),
    smooth('delay', 'Delay', 0, 100, 0, pct),
    smooth('drive', 'Drive', 0, 100, 0, pct),
    smooth('sidechain', 'Sidechain', 0, 100, 0, pct),
  ],
  [
    smooth('pan', 'Pan', -64, 63, 0, (v) => { const r = Math.round(v); return r === 0 ? 'C' : r < 0 ? `L${-r}` : `R${r}`; }, { bipolar: true }),
    smooth('prob', 'Probability', 0, 100, 100, pct),
    stepped('ratchet', 'Ratchet', ['1', '2', '3', '4']),
    smooth('swing', 'Swing', 50, 75, 50, pct),
  ],
]);

// ---------- MOD: LFO1, LFO2, LFO3 и огибающая ENV (по дорожкам) ----------

export const LFO_WAVES = ['Sine', 'Triangle', 'Saw', 'Square', 'Random'];

function lfoColumn(n: 1 | 2 | 3): Slot[] {
  return [
    stepped(`lfo${n}.wave`, `LFO${n} Wave`, LFO_WAVES),
    smooth(`lfo${n}.speed`, `LFO${n} Speed`, 0.05, 20, 1, lfoHz, { exp: true }),
    smooth(`lfo${n}.depth`, `LFO${n} Depth`, 0, 100, 100, pct),
    smooth(`lfo${n}.invert`, `LFO${n} Invert`, 0, 1, 0, (v) => { const p = Math.round((1 - 2 * v) * 100); return p === 0 ? 'flat' : `${p > 0 ? '+' : ''}${p}%`; }),
  ];
}

/** Огибающая ENV (источник модуляции, запускается каждым тригом дорожки). */
function envColumn(): Slot[] {
  return [
    smooth('env.attack', 'ENV Attack', 1, 4000, 10, ms, { exp: true }),
    smooth('env.decay', 'ENV Decay', 1, 4000, 300, ms, { exp: true }),
    smooth('env.sustain', 'ENV Sustain', 0, 100, 50, pct),
    smooth('env.release', 'ENV Release', 1, 4000, 300, ms, { exp: true }),
  ];
}

export const MOD_GRID: Slot[] = grid([lfoColumn(1), lfoColumn(2), lfoColumn(3), envColumn()]);

// ---------- FX: общие параметры (не по дорожкам) ----------

export const FX_GRID: Slot[] = grid([
  [
    smooth('rev.size', 'Rev Size', 0, 100, 50, pct),
    smooth('rev.decay', 'Rev Decay', 0.1, 20, 2, (v) => `${v.toFixed(1)}s`, { exp: true }),
    smooth('rev.hpf', 'Rev HPF', 20, 2000, 20, hz, { exp: true }),
    smooth('rev.predelay', 'Rev Predelay', 0, 200, 0, ms),
  ],
  [
    smooth('dly.feedback', 'Dly Feedback', 0, 100, 40, pct),
    smooth('dly.time', 'Dly Time', 10, 2000, 375, ms, { exp: true }),
    smooth('dly.hpf', 'Dly HPF', 20, 2000, 20, hz, { exp: true }),
    smooth('dly.stereo', 'Dly Stereo', 0, 100, 0, pct),
  ],
  [
    stepped('od.type', 'OD Type', ['Soft', 'Hard', 'Tube', 'Fuzz']),
    smooth('od.tone', 'OD Tone', 0, 100, 50, pct),
  ],
  [
    smooth('sc.attack', 'SC Attack', 0.1, 100, 5, ms, { exp: true }),
    smooth('sc.release', 'SC Release', 10, 1000, 150, ms, { exp: true }),
    stepped('sc.source', 'SC Source', ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8']),
  ],
]);

// ---------- Верхняя панель ----------

export const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
export const SCALES: { name: string; steps: number[] }[] = [
  { name: 'Major', steps: [0, 2, 4, 5, 7, 9, 11] },
  { name: 'Minor', steps: [0, 2, 3, 5, 7, 8, 10] },
  { name: 'Dorian', steps: [0, 2, 3, 5, 7, 9, 10] },
  { name: 'Phrygian', steps: [0, 1, 3, 5, 7, 8, 10] },
  { name: 'Lydian', steps: [0, 2, 4, 6, 7, 9, 11] },
  { name: 'Mixolydian', steps: [0, 2, 4, 5, 7, 9, 10] },
  { name: 'Locrian', steps: [0, 1, 3, 5, 6, 8, 10] },
  { name: 'Harm Minor', steps: [0, 2, 3, 5, 7, 8, 11] },
  { name: 'Pent Major', steps: [0, 2, 4, 7, 9] },
  { name: 'Pent Minor', steps: [0, 3, 5, 7, 10] },
  { name: 'Chromatic', steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] },
];

/** Аккордовые прогрессии: ступени гаммы (0 = I). */
export const PROGRESSIONS: { name: string; degrees: number[] }[] = [
  { name: 'I–V–vi–IV', degrees: [0, 4, 5, 3] },
  { name: 'I–vi–IV–V', degrees: [0, 5, 3, 4] },
  { name: 'vi–IV–I–V', degrees: [5, 3, 0, 4] },
  { name: 'ii–V–I', degrees: [1, 4, 0] },
  { name: 'I–IV–V–IV', degrees: [0, 3, 4, 3] },
  { name: 'i–VII–VI–VII', degrees: [0, 6, 5, 6] },
  { name: 'Canon', degrees: [0, 4, 5, 2, 3, 0, 3, 4] },
];

/** Октава пианоролла (C4 = MIDI 60). */
export const OCTAVE_MIN = 0;
export const OCTAVE_MAX = 7;
export const OCTAVE_DEF = 3;

export const noteName = (midi: number) => `${NOTE_NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
export const BPM_MIN = 40;
export const BPM_MAX = 240;

// ---------- Общие константы ----------

export const TRACK_COUNT = 8;
export const STEPS_PER_PAGE = 16;
export const MAX_PAGES = 8;
/** Ячеек в столбце сетки паттернов. */
export const PATTERN_SLOTS = 8;

export const ALL_PARAMS: ParamDef[] = [...TRACK_GRID, ...MOD_GRID, ...FX_GRID].filter((p): p is ParamDef => p !== null);
export const PARAM_BY_ID: Record<string, ParamDef> = Object.fromEntries(ALL_PARAMS.map((p) => [p.id, p]));

/** Значение параметра → 0..1 (положение ручки). */
export function toNorm(p: ParamDef, v: number): number {
  if (p.exp) return Math.log(v / p.min) / Math.log(p.max / p.min);
  return (v - p.min) / (p.max - p.min);
}

/** 0..1 → значение параметра (ступенчатые округляются). */
export function fromNorm(p: ParamDef, n: number): number {
  n = Math.min(1, Math.max(0, n));
  if (p.kind === 'stepped') return Math.round(n * (p.max - p.min)) + p.min;
  if (p.exp) return p.min * Math.pow(p.max / p.min, n);
  return p.min + n * (p.max - p.min);
}
