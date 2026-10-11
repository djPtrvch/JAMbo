// Настройки приложения (меню «бутерброд» → SETTINGS), хранятся в браузере отдельно от проектов.
// AUDIO ENGINE: частота дискретизации и размер буфера (подсказка задержки для Web Audio);
// BACKGROUND: звук продолжает играть, когда Safari свёрнут или экран заблокирован;
// OUTPUT: выход и вход аудиоинтерфейса. Там же — настройки MIDI (меню MIDI): входы, обратная
// связь, режим энкодеров, ноты и MIDI-маппинги.

/** 0 — как у устройства. */
export const SAMPLE_RATES = [0, 44100, 48000];
/** Размер буфера в сэмплах (0 — как решит браузер: минимальная задержка). */
export const BUFFER_SIZES = [0, 128, 256, 512, 1024];

/** Источник MIDI: CC или нота на канале (0–15). */
export interface MidiSource { type: 'cc' | 'note'; ch: number; num: number }
/** Цель: ручка сетки 4×4 по позиции (0–15, ряд за рядом) или кнопка интерфейса по имени. */
export type MidiTarget = { kind: 'knob'; slot: number } | { kind: 'button'; name: string };
export interface MidiMapping { src: MidiSource; target: MidiTarget }
/** Как энкодер шлёт CC: абсолютно 0–127 или относительно (64 ± шаг; дополнительный код). */
export type KnobMode = 'abs' | 'rel64' | 'rel2c';

export interface Settings {
  sampleRate: number;
  bufferSize: number;
  background: boolean;
  /** Идентификаторы устройств ('' — по умолчанию). */
  outputId: string;
  inputId: string;
  /** MIDI: вход ('' — все), выход обратной связи ('' — нет), режим энкодеров, ноты, маппинги. */
  midiIn: string;
  midiFeedback: string;
  knobMode: KnobMode;
  /** Канал нот: 0 — любой, 1–16. */
  noteChannel: number;
  /** Куда идут ноты: выбранная дорожка или канал N → дорожка N. */
  noteRoute: 'selected' | 'channel';
  mappings: MidiMapping[];
}

const KEY = 'jambo.settings';
const DEFAULTS: Settings = {
  sampleRate: 0, bufferSize: 0, background: true, outputId: '', inputId: '',
  midiIn: '', midiFeedback: '', knobMode: 'abs', noteChannel: 0, noteRoute: 'selected', mappings: [],
};

function load(): Settings {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') }; } catch { return { ...DEFAULTS }; }
}

export const settings: Settings = load();

export function saveSettings(patch: Partial<Settings>) {
  Object.assign(settings, patch);
  try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* хранилище недоступно */ }
}
