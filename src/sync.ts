// Синхронизация (меню SYNC): MIDI-клок (24 тика на четверть) — отдаём (ведущий) или принимаем (ведомый), Start/Stop/
// Continue по MIDI (SYNC START/STOP); Ableton Link — настройки (сам Link — в нативном приложении, этап 10).
// Отдаём: тики 0xF8 на выбранный выход (или все), заранее на ~100 ms с метками времени Web MIDI; при PLAY — 0xFA
// в момент первого шага (сетка тиков встаёт на старт), при стопе — 0xFC; между запусками клок идёт дальше.
// Принимаем: темп — по наклону времени последних тиков (до 48), BPM проекта показывает его округлённым (без UNDO);
// шаги транспорта подтягиваются к времени своих тиков (тик 1/16 = 6 тиков клока) — фаза не уплывает; Start —
// игра с первого тика после Start, Continue — с текущего места, Stop — стоп. Клок пропал дольше 0,5 с — свой темп.

import { initMidi, midiAccess, setRealtimeHandler } from './midi';
import { settings } from './settings';
import { doc, setBpm, ui } from './state';
import { setPlaying, setSyncHooks, tempo } from './transport';

const LOOKAHEAD_MS = 100;
const CLOCK_TIMEOUT_MS = 500;
const FIT = 48;

const sending = () => settings.sync.clock && settings.sync.source === 'send';
const receiving = () => settings.sync.clock && settings.sync.source === 'receive';

// ---------- Отдаём ----------

let clockNext = 0;
let clockRunning = false;

function outputs(): MIDIOutput[] {
  const a = midiAccess();
  if (!a) return [];
  const list: MIDIOutput[] = [];
  a.outputs.forEach((o) => { if (o.state === 'connected' && (!settings.sync.clockOut || o.id === settings.sync.clockOut)) list.push(o); });
  return list;
}

function send(bytes: number[], at: number) {
  for (const o of outputs()) {
    try { o.send(bytes, at); } catch { /* порт закрылся */ }
  }
}

/** Каждый кадр: тики на ~100 ms вперёд. */
export function updateSync(now: number) {
  if (sending()) {
    if (!clockRunning || clockNext < now - 200) { clockNext = now; clockRunning = true; }
    while (clockNext < now + LOOKAHEAD_MS) {
      send([0xf8], clockNext);
      clockNext += 60000 / tempo() / 24;
    }
  } else clockRunning = false;
  // Пропал входящий клок — свой темп.
  if (rx.last && now - rx.last > CLOCK_TIMEOUT_MS) { rx.n = 0; rx.last = 0; rx.interval = 0; }
}

// ---------- Принимаем ----------

/** Последние тики (время), счёт тиков от Start, оценка интервала. */
const rx = { t: new Float64Array(FIT), n: 0, last: 0, interval: 0, count: 0, origin: 0, armed: false, running: false };

function fit() {
  // Наклон времени тиков (наименьшие квадраты) по последним FIT — интервал тика.
  const m = Math.min(rx.n, FIT);
  if (m < 4) { rx.interval = rx.n > 1 ? rx.last - rx.t[(rx.n - 2) % FIT] : 0; return; }
  let sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (let k = 0; k < m; k++) {
    const x = k;
    const y = rx.t[(rx.n - m + k) % FIT] - rx.t[(rx.n - m) % FIT];
    sx += x; sy += y; sxx += x * x; sxy += x * y;
  }
  rx.interval = (m * sxy - sx * sy) / (m * sxx - sx * sx);
}

export function onRealtime(status: number, at: number) {
  if (!receiving()) return;
  if (status === 0xf8) {
    rx.t[rx.n % FIT] = at;
    rx.n++;
    rx.last = at;
    rx.count++;
    fit();
    // BPM проекта — округлённый темп клока (без UNDO).
    const bpm = extTempo();
    if (bpm && Math.round(bpm) !== doc.bpm) setBpm(bpm);
    // Start: игра — с первого тика после Start.
    if (rx.armed) {
      rx.armed = false;
      rx.count = 0;
      rx.origin = 0;
      setPlaying(true, at, at);
    }
    return;
  }
  if (!settings.sync.midiStartStop) return;
  if (status === 0xfa) { rx.armed = true; if (ui.playing) setPlaying(false, at); }
  else if (status === 0xfb) { if (!ui.playing) setPlaying(true, at, at); }
  else if (status === 0xfc) { rx.armed = false; if (ui.playing) setPlaying(false, at); }
}

/** Темп входящего клока (BPM) или null. */
export function extTempo(): number | null {
  if (!receiving() || !rx.last || rx.interval <= 0) return null;
  return 60000 / (rx.interval * 24);
}

/** Время тика транспорта (1/16 от старта = 6 тиков клока) по входящему клоку. */
function phase(tick: number): number | null {
  if (extTempo() === null) return null;
  const clock = rx.origin + tick * 6;
  return rx.last + (clock - rx.count) * rx.interval;
}

function onPlay(on: boolean, at: number) {
  if (sending()) {
    if (on) {
      // Сетка тиков встаёт на старт: Start, затем первый тик в момент первого шага.
      clockNext = at;
      clockRunning = true;
      if (settings.sync.midiStartStop) send([0xfa], at);
    } else if (settings.sync.midiStartStop) send([0xfc], at);
  }
  // Старт своей кнопкой при входящем клоке — от ближайшего тика.
  if (on && receiving() && extTempo() !== null) rx.origin = rx.count + Math.round((at - rx.last) / rx.interval);
}

/** Подключить синхронизацию (при запуске и при смене настроек). */
export function initSync() {
  setRealtimeHandler(onRealtime);
  setSyncHooks({ tempo: extTempo, phase, onPlay });
  if (settings.sync.clock) void initMidi();
}

// ---------- Уведомления (строка вверху) ----------

let toast: HTMLElement | null = null;
let toastTimer = 0;
/** Строка вверху экрана на 2,5 с (подключения Ableton Link — в нативном приложении). */
export function notify(text: string) {
  if (!settings.sync.linkNotify) return;
  if (!toast) {
    toast = document.createElement('div');
    toast.className = 'sync-toast';
    document.body.append(toast);
  }
  toast.textContent = text;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast?.classList.remove('show'), 2500);
}
