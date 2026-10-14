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
export type MidiCond = 'global' | 'page' | 'clip';
/** Страница ручек условия 'page' (что показывает сетка ручек). */
export type MidiPage = 'track' | 'fx' | 'mod' | 'mix' | 'master';
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
   * Когда маппинг работает: 'global' — всегда (на всех дорожках и вкладках); 'page' — только
   * пока сетка ручек показывает страницу page (дорожка, FX, MOD, MIX, MST); 'clip' — только пока
   * открыта сетка паттернов. Если источник назначен в нескольких условиях, действует самое точное:
   * clip, затем page, затем global.
   */
  cond: MidiCond;
  /** Страница условия 'page'. */
  page: MidiPage;
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
  /**
   * VELOCITY (меню бутерброда пианоролла): чувствительность клавиш к нажатию. На iPad сила пальца
   * браузеру не видна — velocity берётся по месту касания на клавише (верх — тихо, низ — громко),
   * у Apple Pencil — по давлению, у MIDI — из сообщения. Меняет Level ноты (при записи — p-lock Level).
   */
  velocity: boolean;
  /** Октав на пианоролле: 1 или 2 (по умолчанию 2). */
  pianoOctaves: 1 | 2;
  /** FX и MOD в режиме toggle (тап включает, следующий выключает) вместо удержания; SHIFT + двойной тап переключает. */
  latch: { fx: boolean; mod: boolean };
  /** SETTINGS → SIDECHAIN: приглушать ли вход посылов Reverb, Delay, Drive тем же sidechain, что и выход дорожки. */
  scSends: { rev: boolean; dly: boolean; drv: boolean };
  /** Окно лимитера: SCALE дисплея и стержней IN/OUT — 48, 32 или 16 dB. */
  limScale: 48 | 32 | 16;
  /** Окно клиппера: вид дисплея — форма (WAVE) или уровень во времени (LEVEL). */
  clipDisplay: 'wave' | 'level';
  /** Меню SYNC: квант (такты), MIDI-клок (вкл., отдаём или принимаем, порт выхода, старт/стоп), Ableton Link. */
  sync: SyncSettings;
}

export interface SyncSettings {
  /** SYNC QUANTUM — длина фразы для выравнивания старта, такты. */
  quantum: 1 | 2 | 4 | 8;
  /** MIDI CLOCK: синхронизация клока по MIDI. */
  clock: boolean;
  /** CLOCK SOURCE: 'send' — JAMbo ведущий (отдаёт клок), 'receive' — ведомый (принимает). */
  source: 'send' | 'receive';
  /** Выход клока ('' — все выходы). */
  clockOut: string;
  /** SYNC START/STOP по MIDI (Start, Stop, Continue). */
  midiStartStop: boolean;
  /** Ableton Link: вкл., уведомления о подключениях, SYNC START/STOP. */
  link: boolean;
  linkNotify: boolean;
  linkStartStop: boolean;
}

const KEY = 'jambo.settings';
const DEFAULTS: Settings = {
  sampleRate: 0, bufferSize: 0, background: true, muteTails: false, outputId: '', inputId: '',
  midiIn: '', midiFeedback: '', noteChannel: 0, noteRoute: 'selected', mappings: [], midiPreset: '', theme: 'system', velocity: false, pianoOctaves: 2, latch: { fx: false, mod: false },
  scSends: { rev: false, dly: false, drv: true },
  limScale: 48,
  clipDisplay: 'wave',
  sync: { quantum: 1, clock: false, source: 'send', clockOut: '', midiStartStop: true, link: false, linkNotify: true, linkStartStop: false },
};

/** Маппинг с недостающими полями (старые настройки: общий режим энкодеров knobMode). */
export function fullMapping(m: Partial<MidiMapping> & Pick<MidiMapping, 'src' | 'target'>, knobMode = 'abs'): MidiMapping {
  const knob = m.target.kind === 'knob';
  return {
    control: knob ? (knobMode === 'abs' ? 'abs' : 'rel') : 'momentary',
    enc: knobMode === 'rel2c' ? 'twos' : 'offset',
    min: 0, max: 1, port: '', input: '', cond: 'global', page: 'track',
    ...m,
    // Прежнее условие Current track (дорожка) — теперь страница дорожки.
    ...((m.cond as string) === 'track' ? { cond: 'page' as const, page: 'track' as const } : {}),
  };
}

function load(): Settings {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? '{}');
    const s: Settings = { ...DEFAULTS, ...raw };
    s.scSends = { ...DEFAULTS.scSends, ...(raw.scSends ?? {}) };
    s.sync = { ...DEFAULTS.sync, ...(raw.sync ?? {}) };
    // Кнопки RATIO компрессора больше нет (RATIO — в окне компрессора): её маппинги снимаются.
    s.mappings = (s.mappings ?? []).filter((m) => !(m.target?.kind === 'button' && m.target.name === 'RATIO')).map((m) => fullMapping(m, raw.knobMode));
    delete (s as Partial<Settings> & { knobMode?: string }).knobMode;
    return s;
  } catch { return { ...DEFAULTS }; }
}

export const settings: Settings = load();

export function saveSettings(patch: Partial<Settings>) {
  Object.assign(settings, patch);
  try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* хранилище недоступно */ }
}
