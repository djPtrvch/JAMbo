// Настройки приложения (меню «бутерброд» → SETTINGS), хранятся в браузере отдельно от проектов.
// AUDIO ENGINE: частота дискретизации и размер буфера (подсказка задержки для Web Audio);
// BACKGROUND: звук продолжает играть, когда Safari свёрнут или экран заблокирован;
// OUTPUT: выход и вход аудиоинтерфейса. Там же — настройки MIDI (меню MIDI): входы, обратная
// связь, ноты и MIDI-маппинги (у каждого — тип управления, диапазон и порт обратной связи).

/** 0 — как у устройства. */
export const SAMPLE_RATES = [0, 44100, 48000];
/** Размер буфера в сэмплах (0 — как решит браузер: минимальная задержка). */
export const BUFFER_SIZES = [0, 128, 256, 512, 1024];

/** Источник MIDI: CC или нота на канале (0–15). */
export interface MidiSource { type: 'cc' | 'note'; ch: number; num: number }
/** Цель: ручка сетки 4×4 по позиции (0–15, ряд за рядом) или кнопка интерфейса по имени. */
export type MidiTarget = { kind: 'knob'; slot: number } | { kind: 'button'; name: string };
/**
 * Тип управления: кнопка (MOMENTARY — пока нажата, TOGGLE — нажатие включает, следующее выключает),
 * ABSOLUTE — значение 0–127, RELATIVE — энкодер шлёт шаги (см. RelEnc).
 */
export type ControlType = 'momentary' | 'toggle' | 'abs' | 'rel';
/** Как энкодер кодирует шаг: OFFSET (64 ± n: 65 вверх, 63 вниз), 2'S (1 вверх, 127 вниз), SIGNED (1 вверх, 65 вниз). */
export type RelEnc = 'offset' | 'twos' | 'signed';
export type MidiCond = 'global' | 'track' | 'clip';
export interface MidiMapping {
  src: MidiSource;
  target: MidiTarget;
  control: ControlType;
  enc: RelEnc;
  /** Диапазон ручки 0–1: min — при 0, max — при 127 (min > max — инвертировано). */
  min: number;
  max: number;
  /** Вход, с которого слушать: '' — любой, иначе id входа (Web MIDI или Bluetooth). */
  input: string;
  /**
   * Когда маппинг работает: 'global' — всегда (на всех дорожках и вкладках); 'track' — только
   * пока выбрана дорожка track (у каждой дорожки свои маппинги); 'clip' — только пока открыта
   * сетка паттернов. Если источник назначен в нескольких условиях, действует самое точное:
   * clip, затем track, затем global.
   */
  cond: MidiCond;
  /** Дорожка условия 'track'. */
  track: number;
  /** Порт обратной связи: '' — по умолчанию (DEVICES → FEEDBACK OUTPUT), 'none' — нет, иначе id выхода. */
  port: string;
}

export interface Settings {
  sampleRate: number;
  bufferSize: number;
  background: boolean;
  /** MUTE TAILS: mute дорожки — единственного источника посыла Delay — гасит и его повторы. */
  muteTails: boolean;
  /** Идентификаторы устройств ('' — по умолчанию). */
  outputId: string;
  inputId: string;
  /** MIDI: вход ('' — все), выход обратной связи по умолчанию ('' — нет), ноты, маппинги. */
  midiIn: string;
  midiFeedback: string;
  /** Канал нот: 0 — любой, 1–16. */
  noteChannel: number;
  /** Куда идут ноты: выбранная дорожка или канал N → дорожка N. */
  noteRoute: 'selected' | 'channel';
  mappings: MidiMapping[];
  /** Имя пресета маппингов, загруженного последним ('' — нет). */
  midiPreset: string;
  /** Оформление: как в системе (светлое или тёмное по настройке iPad), светлое или тёмное. */
  theme: 'system' | 'light' | 'dark';
}

const KEY = 'jambo.settings';
const DEFAULTS: Settings = {
  sampleRate: 0, bufferSize: 0, background: true, muteTails: false, outputId: '', inputId: '',
  midiIn: '', midiFeedback: '', noteChannel: 0, noteRoute: 'selected', mappings: [], midiPreset: '', theme: 'system',
};

/** Маппинг с недостающими полями (старые настройки: общий режим энкодеров knobMode). */
export function fullMapping(m: Partial<MidiMapping> & Pick<MidiMapping, 'src' | 'target'>, knobMode = 'abs'): MidiMapping {
  const knob = m.target.kind === 'knob';
  return {
    control: knob ? (knobMode === 'abs' ? 'abs' : 'rel') : 'momentary',
    enc: knobMode === 'rel2c' ? 'twos' : 'offset',
    min: 0, max: 1, port: '', input: '', cond: 'global', track: 0,
    ...m,
  };
}

function load(): Settings {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? '{}');
    const s: Settings = { ...DEFAULTS, ...raw };
    s.mappings = (s.mappings ?? []).map((m) => fullMapping(m, raw.knobMode));
    delete (s as Partial<Settings> & { knobMode?: string }).knobMode;
    return s;
  } catch { return { ...DEFAULTS }; }
}

export const settings: Settings = load();

export function saveSettings(patch: Partial<Settings>) {
  Object.assign(settings, patch);
  try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* хранилище недоступно */ }
}
