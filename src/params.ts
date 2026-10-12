// Единая таблица параметров: названия, подписи ручек, диапазоны и форматы.
// Меняем подписи и диапазоны только здесь.

/** Дорожек по умолчанию — и меньше нельзя. */
export const TRACK_COUNT = 8;
/** Дорожек самое большее (добавляются в MIX удержанием скрытой ручки). */
export const MAX_TRACKS = 12;
/** Номера последовательностей: 0..MAX_TRACKS-1 — дорожки, затем свои у каналов MIX и MST. */
export const SEQ_MIX = MAX_TRACKS;
export const SEQ_MST = MAX_TRACKS + 1;
export const SEQ_COUNT = MAX_TRACKS + 2;

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
  /**
   * Степенная шкала от нуля: значение = min + (max − min)·n^curve. Короткие времена (Attack,
   * Decay) — в нижней части ручки, длинные — вверху; ноль остаётся достижим (в отличие от exp).
   */
  curve?: number;
  /** Дуга рисуется от центра (Pan, Pitch, Invert). */
  bipolar?: boolean;
  /** Шаг значения (0.1 dB у компрессора мастера). */
  step?: number;
  /** Последняя доля хода ручки — AUTO (значение AUTO_VALUE); шкала до неё — как обычно. */
  autoTop?: number;
  /** Первая доля хода ручки — OFF (значение 0); шкала после неё — как обычно. */
  offBottom?: number;
  /** P-lock на ручку не ставится (ручки компрессора мастера). */
  noLock?: boolean;
  /** Ступенчатая ручка в процентах (1.1 некоторых движков): число пунктов, значение — середина пункта. */
  steps?: number;
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

/** Время Delay в долях такта по темпу: подпись и длительность в долях (четвертях). */
export const DELAY_DIVS: { name: string; beats: number }[] = [
  { name: '1/32', beats: 1 / 8 },
  { name: '1/16T', beats: 1 / 6 },
  { name: '1/16', beats: 1 / 4 },
  { name: '1/16D', beats: 3 / 8 },
  { name: '1/8T', beats: 1 / 3 },
  { name: '1/8', beats: 1 / 2 },
  { name: '1/8D', beats: 3 / 4 },
  { name: '1/4T', beats: 2 / 3 },
  { name: '1/4', beats: 1 },
  { name: '1/4D', beats: 3 / 2 },
  { name: '1/2', beats: 2 },
  { name: '1 bar', beats: 4 },
];

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
    // Level: на ручке — проценты (100% — максимум и значение по умолчанию); хранится 0…127, как прежде.
    smooth('level', 'Level', 0, 127, 127, (v) => `${Math.round((v / 127) * 100)}%`),
  ],
  [
    smooth('attack', 'Attack', 0, 2000, 0, ms, { curve: 3 }),
    smooth('decay', 'Decay', 0, 4000, 500, ms, { curve: 3 }),
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
    smooth('prob', 'Chance', 0, 100, 100, pct),
    stepped('ratchet', 'Ratchet', ['1', '2', '3', '4']),
    smooth('swing', 'Swing', 50, 75, 50, pct),
  ],
]);

// ---------- Синты: движки Mutable Instruments Plaits ----------

/**
 * Первые 16 (классических) движков Plaits: подпись в меню и что делают Harmonics, Timbre, Morph.
 * Номер в списке = номер движка в plaits.wasm. bank — группа в меню: 'synth' (музыкальные,
 * зелёный банк Plaits) или 'drum' (шумы и ударные, красный банк).
 * decay: у движка Morph в Plaits — затухание; здесь затуханием управляет ручка Decay, а Morph —
 * микс выходов OUT и AUX (как у модуля).
 */
/**
 * Таблица движков (одно место): короткое имя (кнопки меню), полное, банк меню, aux (11–15: ручка 1.3 —
 * OUT→AUX, затухание от Decay) и подписи ручек 1.1, 1.2, 1.3. steps — ступенчатая ручка 1.1 (пункты
 * options): значение остаётся 0..100 %, ручка встаёт на середину пункта.
 */
export interface SynthEngine {
  name: string; full: string; bank: 'synth' | 'drum'; decay: boolean;
  harm: string; timbre: string; morph: string; options?: string[];
}
export const SYNTH_ENGINES: SynthEngine[] = [
  { name: 'VA', full: 'Pair of classic waves', bank: 'synth', decay: false, harm: 'detune', timbre: 'pulse width', morph: 'triangle→saw' },
  { name: 'WAVESHAPE', full: 'Waveshaper', bank: 'synth', decay: false, harm: 'shaper waveform', timbre: 'fold depth', morph: 'asymmetry' },
  { name: 'FM', full: 'Two-operator FM', bank: 'synth', decay: false, harm: 'frequency ratio', timbre: 'mod index', morph: 'feedback' },
  { name: 'GRAIN', full: 'Granular formant', bank: 'synth', decay: false, harm: 'formant ratio', timbre: 'formant freq', morph: 'formant width' },
  { name: 'ADDITIVE', full: 'Harmonic', bank: 'synth', decay: false, harm: 'bumps', timbre: 'main harmonic', morph: 'bump shape' },
  { name: 'WAVETABLE', full: 'Wavetable', bank: 'synth', decay: false, harm: 'bank', timbre: 'row', morph: 'column', options: ['A', 'B', 'C', 'D'] },
  { name: 'CHORDS', full: 'Chords', bank: 'synth', decay: false, harm: 'chord type', timbre: 'inversion', morph: 'waveform',
    options: ['oct', '5', 'sus4', 'm', 'm7', 'm9', 'm11', '6/9', 'M9', 'M7', 'M'] },
  { name: 'SPEECH', full: 'Vowel & speech', bank: 'synth', decay: false, harm: 'mode', timbre: 'species', morph: 'phoneme / word',
    options: ['Formant', 'SAM', 'LPC', 'Words'] },
  { name: 'SWARM', full: 'Granular cloud', bank: 'drum', decay: false, harm: 'pitch spread', timbre: 'density', morph: 'grain length' },
  { name: 'NOISE', full: 'Filtered noise', bank: 'drum', decay: false, harm: 'LP→BP→HP', timbre: 'clock freq', morph: 'resonance' },
  { name: 'PARTICLE', full: 'Particle noise', bank: 'drum', decay: false, harm: 'freq spread', timbre: 'density', morph: 'all-pass→band-pass' },
  { name: 'STRING', full: 'Inharmonic string', bank: 'drum', decay: true, harm: 'material (inharmonicity)', timbre: 'excitation brightness', morph: 'OUT→AUX' },
  { name: 'MODAL', full: 'Modal resonator', bank: 'drum', decay: true, harm: 'material', timbre: 'brightness & dust', morph: 'OUT→AUX' },
  { name: 'KICK', full: 'Analog bass drum', bank: 'drum', decay: true, harm: 'attack & overdrive', timbre: 'brightness', morph: 'OUT→AUX' },
  { name: 'SNARE', full: 'Analog snare', bank: 'drum', decay: true, harm: 'harmonics↔noise', timbre: 'mode balance', morph: 'OUT→AUX' },
  { name: 'HI-HAT', full: 'Analog hi-hat', bank: 'drum', decay: true, harm: 'metal↔noise', timbre: 'HPF cutoff', morph: 'OUT→AUX' },
  // Свой движок (не Plaits, считается в том же AudioWorklet): синус со свипом высоты + шум через
  // полосовой фильтр + клик → мягкий клиппер; затухает сам (Decay).
  { name: 'DRUM', full: 'Drum', bank: 'drum', decay: true, harm: 'sweep', timbre: 'tone', morph: 'drive' },
];
/** Номер движка DRUM (не Plaits: ручка 1.3 — Drive, а не OUT→AUX). */
export const DRUM_ENGINE = 16;

/** Параметры звука, которые сохраняются в пресете синта (вместе с движком). */
export const PRESET_PARAMS = ['harm', 'timbre', 'morph', 'level', 'attack', 'decay', 'filter', 'reso'];

/** Ключ звука дорожки: 'mi:<n>' — движок Plaits n; иначе сэмпл ('file:<n>' или '' — нет). */
export const synthKey = (engine: number) => `mi:${engine}`;
/** Номер движка из ключа звука; неизвестный номер (движок убран) — null. */
export const synthEngine = (key: string): number | null => {
  if (!key.startsWith('mi:')) return null;
  const n = Number(key.slice(3));
  return n >= 0 && n < SYNTH_ENGINES.length ? n : null;
};

/** Колонка 1 для синта: Harmonics, Timbre, Morph, Level (вместо Pitch, Start, End, Level). */
export const SYNTH_GRID: Slot[] = TRACK_GRID.map((p, i) => {
  if (i === 0) return smooth('harm', 'Harmonics', 0, 100, 50, pct);
  if (i === 4) return smooth('timbre', 'Timbre', 0, 100, 50, pct);
  if (i === 8) return smooth('morph', 'Morph', 0, 100, 50, pct);
  return p;
});

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
/** Колонка 1 движка: подписи 1.1–1.3 из таблицы, у WAVETABLE, CHORDS, SPEECH 1.1 ступенчатая. */
const ENGINE_GRIDS: Slot[][] = SYNTH_ENGINES.map((e) => SYNTH_GRID.map((p, i) => {
  if (!p || (i !== 0 && i !== 4 && i !== 8)) return p;
  const label = cap(i === 0 ? e.harm : i === 4 ? e.timbre : e.morph);
  if (i === 0 && e.options) {
    const o = e.options;
    return { ...p, label, kind: 'stepped', steps: o.length, format: (v: number) => o[stepIndex(v / 100, o.length)] };
  }
  return { ...p, label };
}));
export const synthGrid = (engine: number): Slot[] => ENGINE_GRIDS[engine] ?? SYNTH_GRID;
/** Пункт ступенчатой ручки по положению 0..1. */
export const stepIndex = (n: number, steps: number) => Math.min(steps - 1, Math.max(0, Math.floor(n * steps)));

// ---------- MOD: LFO1, LFO2, LFO3 и огибающая ENV (по дорожкам) ----------

export const LFO_WAVES = ['Sine', 'Triangle', 'Saw', 'Square', 'Random'];

function lfoColumn(n: 1 | 2 | 3): Slot[] {
  return [
    stepped(`lfo${n}.wave`, `LFO${n} Wave`, LFO_WAVES),
    smooth(`lfo${n}.speed`, `LFO${n} Speed`, 0.05, 20, 1, lfoHz, { exp: true }),
    smooth(`lfo${n}.invert`, `LFO${n} Invert`, 0, 1, 0, (v) => { const p = Math.round((1 - 2 * v) * 100); return p === 0 ? 'flat' : `${p > 0 ? '+' : ''}${p}%`; }),
    // Полярность: 0 — биполярная (−1…+1 вокруг значения ручки), 1 — однополярная (0…+1, только вверх), между — плавно.
    smooth(`lfo${n}.polar`, `LFO${n} Polarity`, 0, 1, 0, (v) => (v < 0.005 ? 'BI' : v > 0.995 ? 'UNI' : `UNI ${Math.round(v * 100)}%`)),
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
    smooth('rev.size', 'Rev Size', 0, 100, 30, pct),
    smooth('rev.decay', 'Rev Decay', 0.1, 20, 2, (v) => `${v.toFixed(1)}s`, { exp: true }),
    smooth('rev.hpf', 'Rev HPF', 20, 2000, 20, hz, { exp: true }),
    smooth('rev.predelay', 'Rev Predelay', 0, 200, 0, ms),
  ],
  [
    smooth('dly.feedback', 'Dly Feedback', 0, 100, 40, pct),
    stepped('dly.time', 'Dly Time', DELAY_DIVS.map((d) => d.name), DELAY_DIVS.findIndex((d) => d.name === '1/8')),
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
    stepped('sc.source', 'SC Source', Array.from({ length: MAX_TRACKS }, (_, i) => `${i + 1}`)),
  ],
]);

// ---------- Микшер: 16 ручек = громкости дорожек (несуществующие — серые) ----------

/** Громкость дорожки в dB: от тишины (−∞ на минимуме) до 0 dB. */
export const VOL_MIN_DB = -60;
/** Громкость дорожки по умолчанию (поднять можно до 0 dB). */
export const VOL_DEF_DB = -10;
const volDb = (v: number) => (v <= VOL_MIN_DB + 0.05 ? '−∞ dB' : `${v.toFixed(1)} dB`);
/** Порог «0 dB» для всех метров проекта: пик от −0.01 dBFS и выше — красная индикация. */
export const OVER_PEAK = 0.999;

/** Громкость дорожки (dB) → усиление. */
export const volGain = (db: number) => (db <= VOL_MIN_DB + 0.05 ? 0 : Math.pow(10, db / 20));
export const fmtVol = volDb;

/** Ручек громкости в микшере (до 16 дорожек). */
export const MIX_SLOTS = 16;

export const MIX_GRID: Slot[] = Array.from({ length: MIX_SLOTS }, (_, i) =>
  i < MAX_TRACKS ? smooth(`mix.vol${i + 1}`, `${i + 1}`, VOL_MIN_DB, 0, VOL_DEF_DB, volDb) : null);

// ---------- Мастер: компрессор (колонка 3) и лимитер (колонка 4), Ratio — отдельной кнопкой ----------


/** Release компрессора мастера в AUTO (последние 8% хода ручки). */
export const AUTO_VALUE = 1e9;
export const isAuto = (v: number) => v >= AUTO_VALUE;
const cmpDb = (v: number) => `${v > 0.04 ? '+' : ''}${v.toFixed(1)} dB`;
const cmpMs = (v: number) => (isAuto(v) ? 'AUTO' : v >= 1000 ? `${(v / 1000).toFixed(1)} s` : v < 10 ? `${v.toFixed(1)} ms` : `${Math.round(v)} ms`);
const CMP = { noLock: true } as const;

export const MASTER_GRID: Slot[] = grid([
  [
    // Сатуратор мастер-шины (saturator-worklet.js): без p-lock; DRIVE 0 — прозрачен (вместо BYPASS).
    smooth('sat.drive', 'Drive', 0, 24, 0, cmpDb, { ...CMP, step: 0.1 }),
    { ...stepped('sat.type', 'Type', ['TAPE', 'TUBE', 'EDGE']), ...CMP },
    smooth('sat.tone', 'Tone', -100, 100, 0, (v) => cmpDb((v / 100) * 6), CMP),
    smooth('sat.mix', 'Mix', 0, 100, 100, (v) => `${Math.round(v)}%`, CMP),
  ],
  [
    // Компрессор мастер-шины «glue» (glue-worklet.js): все ручки плавные, без p-lock.
    smooth('cmp.threshold', 'Threshold', -40, 0, -10, cmpDb, { ...CMP, step: 0.1 }),
    smooth('cmp.attack', 'Attack', 0.1, 100, 10, cmpMs, { ...CMP, exp: true }),
    smooth('cmp.release', 'Release', 20, 2000, 400, cmpMs, { ...CMP, exp: true, autoTop: 0.08 }),
    smooth('cmp.makeup', 'Makeup', 0, 18, 0, cmpDb, { ...CMP, step: 0.1 }),
  ],
  [
    // Клиппер мастер-шины (clipper-worklet.js): все ручки плавные, без p-lock. BASS: первые 5% — OFF.
    smooth('clip.drive', 'Input', 0, 12, 0, cmpDb, { ...CMP, step: 0.1 }),
    smooth('clip.ceiling', 'Ceiling', -12, 0, -1, cmpDb, { ...CMP, step: 0.1 }),
    smooth('clip.softness', 'Softness', 0, 100, 30, (v) => `${Math.round(v)}%`, CMP),
    smooth('clip.bass', 'Bass', 20, 300, 0, (v) => (v <= 0 ? 'OFF' : `${Math.round(v)} Hz`), { ...CMP, exp: true, offBottom: 0.05 }),
  ],
  [
    // Лимитер мастер-шины (limiter-worklet.js): все ручки плавные, без p-lock.
    smooth('lim.input', 'Input', 0, 24, 0, cmpDb, { ...CMP, step: 0.1 }),
    smooth('lim.ceiling', 'Ceiling', -24, 0, -1, cmpDb, { ...CMP, step: 0.1 }),
    smooth('lim.lookahead', 'Lookahead', 0.5, 6, 3, (v) => `${v.toFixed(1)} ms`, CMP),
    smooth('lim.release', 'Release', 10, 1000, 150, cmpMs, { ...CMP, exp: true, autoTop: 0.08 }),
  ],
]);

/** Нота, на которой сэмпл звучит в исходной высоте (C3). */
export const SAMPLE_ROOT = 48;

/** Ratio компрессора мастера (кнопка RATIO перебирает по кругу). */
export const RATIOS = [2, 4, 10];

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
/** Сокращённые названия гамм (список проектов). */
export const SCALE_SHORT = ['Maj', 'Min', 'Dor', 'Phr', 'Lyd', 'Mix', 'Loc', 'HMin', 'PMaj', 'PMin', 'Chr'];

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
export const OCTAVE_DEF = 2;

export const noteName = (midi: number) => `${NOTE_NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
export const BPM_MIN = 40;
export const BPM_MAX = 240;

// ---------- Общие константы ----------

export const STEPS_PER_PAGE = 16;
export const MAX_PAGES = 8;
/** Ячеек в столбце сетки паттернов. */
export const PATTERN_SLOTS = 8;

export const ALL_PARAMS: ParamDef[] = [...TRACK_GRID, ...[SYNTH_GRID[0], SYNTH_GRID[4], SYNTH_GRID[8]], ...MOD_GRID, ...FX_GRID, ...MIX_GRID, ...MASTER_GRID].filter((p): p is ParamDef => p !== null);
export const PARAM_BY_ID: Record<string, ParamDef> = Object.fromEntries(ALL_PARAMS.map((p) => [p.id, p]));

/** Значение параметра → 0..1 (положение ручки). */
export function toNorm(p: ParamDef, v: number): number {
  if (p.offBottom) return v <= 0 ? 0 : p.offBottom + (1 - p.offBottom) * toNorm({ ...p, offBottom: undefined }, Math.max(p.min, v));
  if (p.autoTop) return isAuto(v) ? 1 : (1 - p.autoTop) * toNorm({ ...p, autoTop: undefined }, Math.min(p.max, v));
  if (p.exp) return Math.log(v / p.min) / Math.log(p.max / p.min);
  if (p.curve) return Math.pow(Math.min(1, Math.max(0, (v - p.min) / (p.max - p.min))), 1 / p.curve);
  return (v - p.min) / (p.max - p.min);
}

/** 0..1 → значение параметра (ступенчатые округляются). */
export function fromNorm(p: ParamDef, n: number): number {
  n = Math.min(1, Math.max(0, n));
  if (p.offBottom) return n < p.offBottom ? 0 : fromNorm({ ...p, offBottom: undefined }, (n - p.offBottom) / (1 - p.offBottom));
  if (p.autoTop) return n >= 1 - p.autoTop ? AUTO_VALUE : fromNorm({ ...p, autoTop: undefined }, n / (1 - p.autoTop));
  if (p.step) {
    const v = fromNorm({ ...p, step: undefined }, n);
    return Math.round(v / p.step) * p.step;
  }
  if (p.steps) return p.min + ((stepIndex(n, p.steps) + 0.5) / p.steps) * (p.max - p.min);
  if (p.kind === 'stepped') return Math.round(n * (p.max - p.min)) + p.min;
  if (p.exp) return p.min * Math.pow(p.max / p.min, n);
  if (p.curve) return p.min + Math.pow(n, p.curve) * (p.max - p.min);
  return p.min + n * (p.max - p.min);
}

// ---------- Эквалайзер (кнопка EQ) ----------

/** Типы полос EQ: подпись и тип BiquadFilterNode. */
export const EQ_TYPES: { name: string; node: BiquadFilterType }[] = [
  { name: 'Bell', node: 'peaking' },
  { name: 'Low Shelf', node: 'lowshelf' },
  { name: 'High Shelf', node: 'highshelf' },
  { name: 'Low Cut', node: 'highpass' },
  { name: 'High Cut', node: 'lowpass' },
  { name: 'Notch', node: 'notch' },
];
export const EQ_BELL = 0;
/** Порядок типов в меню и в поле TYPE: bell, low cut, high cut, затем остальные (индексы в EQ_TYPES не меняются — так они хранятся в проектах). */
export const EQ_TYPE_ORDER = [0, 3, 4, 1, 2, 5];
/** Low cut и high cut: крутизна среза выбирается. */
export const eqIsCut = (type: number) => type === 3 || type === 4;
/** Усиление не применяется к cut и notch. */
export const eqHasGain = (type: number) => type <= 2;
/** Крутизна среза, дБ/окт (каскад из 1, 2 или 4 биквадов). */
export const EQ_SLOPES = [12, 24, 48];
export const EQ_BANDS = 8;
/** Режим полосы: на оба канала, только середина (L+R)/2 или только бока (L−R)/2. */
export const EQ_MS = ['STEREO', 'MID', 'SIDE'];
/** Динамическая полоса: только у bell и shelf; источник dyn: −1 (нет) — OFF, 0 — SELF, n — дорожка n. */
export const eqDynOn = (b: { type: number; dyn?: number }) => eqHasGain(b.type) && (b.dyn ?? -1) >= 0;
export const EQ_DYN_THR_DEF = -24;
export const EQ_DYN_THR_MIN = -60;
export const EQ_DYN_RANGE_DEF = -6;
export const EQ_DYN_RANGE_MAX = 18;
export const EQ_FREQ_MIN = 20;
export const EQ_FREQ_MAX = 20000;
export const EQ_GAIN_MAX = 18;
export const EQ_Q_MIN = 0.1;
export const EQ_Q_MAX = 18;
export const EQ_Q_DEF = 1;

/** Число дорожек проекта изменилось: выбор источника sidechain — только среди существующих дорожек. */
export function setTrackCountParams(n: number) {
  const sc = PARAM_BY_ID['sc.source'];
  if (sc) sc.max = n - 1;
}
