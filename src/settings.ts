// Настройки приложения (меню «бутерброд» → SETTINGS), хранятся в браузере отдельно от проектов.
// AUDIO ENGINE: частота дискретизации и размер буфера (подсказка задержки для Web Audio);
// BACKGROUND: звук продолжает играть, когда Safari свёрнут или экран заблокирован;
// OUTPUT: выход и вход аудиоинтерфейса.

/** 0 — как у устройства. */
export const SAMPLE_RATES = [0, 44100, 48000];
/** Размер буфера в сэмплах (0 — как решит браузер: минимальная задержка). */
export const BUFFER_SIZES = [0, 128, 256, 512, 1024];

export interface Settings {
  sampleRate: number;
  bufferSize: number;
  background: boolean;
  /** Идентификаторы устройств ('' — по умолчанию). */
  outputId: string;
  inputId: string;
}

const KEY = 'jambo.settings';
const DEFAULTS: Settings = { sampleRate: 0, bufferSize: 0, background: true, outputId: '', inputId: '' };

function load(): Settings {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') }; } catch { return { ...DEFAULTS }; }
}

export const settings: Settings = load();

export function saveSettings(patch: Partial<Settings>) {
  Object.assign(settings, patch);
  try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* хранилище недоступно */ }
}
