// MIDI (бутерброд → MIDI): подключённые устройства и подключение Bluetooth MIDI.
// USB и уже сопряжённые устройства — через Web MIDI, Bluetooth MIDI — через Web Bluetooth
// (BLE MIDI: сервис 03b80e5a-…, характеристика 7772e5db-…). Ноты с входов играют выбранную
// дорожку, как пианоролл (и записываются с REC).
// В Safari на iPad ни Web MIDI, ни Web Bluetooth нет — меню об этом говорит; MIDI появится
// в нативном приложении.
//
// MIDI-маппинг: CC или нота → ручка сетки 4×4 (по позиции: ручка показывает параметр текущего
// режима — дорожки, FX, MOD, MIX, MST) или кнопка интерфейса. MIDI LEARN: тап по ручке или кнопке,
// затем движение контроллера. Значения ручек уходят на выход обратной связи (кольца энкодеров
// Midi Fighter Twister). Маппинги и настройки — в settings.ts (общие для всех проектов).

import { toNorm } from './params';
import {
  assignFor, beginGesture, endGesture, firstHeldStep, gridFor, gridMode, heldLfo, lockValue, paramValue,
  setLfoAmount, setLockNorm, setParamNorm,
} from './state';
import { fullMapping, saveSettings, settings, type MidiMapping, type MidiSource, type MidiTarget } from './settings';

// Web Bluetooth нет в стандартных типах TypeScript — только то, что здесь нужно.
interface BleCharacteristic extends EventTarget { value: DataView | null; startNotifications(): Promise<unknown> }
interface BluetoothDevice extends EventTarget {
  id: string;
  name?: string;
  gatt?: {
    connect(): Promise<{ getPrimaryService(s: string): Promise<{ getCharacteristic(c: string): Promise<BleCharacteristic> }> }>;
    disconnect(): void;
  };
}
interface Bluetooth { requestDevice(o: { filters: { services: string[] }[] }): Promise<BluetoothDevice> }

const BLE_MIDI_SERVICE = '03b80e5a-ede8-4b33-a751-6ce34ec4c700';
const BLE_MIDI_CHAR = '7772e5db-3868-4112-a1a9-f2669d106bf3';

export interface MidiDevice { id: string; name: string; kind: 'midi' | 'bluetooth'; dir: 'in' | 'out' }

/** Нота с входа; track — дорожка (null — выбранная). */
type NoteHandler = (note: number, velocity: number, track: number | null) => void;
let onNote: NoteHandler = () => {};
let access: MIDIAccess | null = null;
const ble: { id: string; name: string; device: BluetoothDevice }[] = [];
let listeners: (() => void)[] = [];

export const hasWebMidi = () => typeof navigator.requestMIDIAccess === 'function';
export const hasBluetooth = () => 'bluetooth' in navigator;

/** Кто играет входящие ноты (задаёт интерфейс). */
export function setNoteHandler(fn: NoteHandler) {
  onNote = fn;
}

/** Подписка на изменения списка устройств. */
export function onDevicesChanged(fn: () => void) {
  listeners.push(fn);
  return () => { listeners = listeners.filter((l) => l !== fn); };
}
const changed = () => listeners.forEach((l) => l());

// ---------- Кнопки (действия интерфейса) ----------

/**
 * Действие кнопки для MIDI: нажатие и отпускание (у кнопок на удержание);
 * state — горит ли кнопка (для обратной связи: подсветка кнопки контроллера).
 */
export interface MidiAction { label: string; press: () => void; release?: () => void; state?: () => boolean }
const actions = new Map<string, MidiAction>();

/** Интерфейс регистрирует кнопку; элемент помечается data-midi для MIDI LEARN. */
export function registerAction(name: string, action: MidiAction, el?: HTMLElement) {
  actions.set(name, action);
  if (el) el.dataset.midi = `btn:${name}`;
}

/** Ручка сетки (позиция 0–15) для MIDI LEARN. */
export function markKnob(el: HTMLElement, slot: number) {
  el.dataset.midi = `knob:${slot}`;
}

/** Подпись ручки — столбец.ряд, как в описании сетки. */
export const targetLabel = (t: MidiTarget) => (t.kind === 'knob'
  ? `KNOB ${(t.slot % 4) + 1}.${Math.floor(t.slot / 4) + 1}`
  : actions.get(t.name)?.label ?? t.name);

export const sourceLabel = (s: MidiSource) => `${s.type === 'cc' ? 'CC' : 'NOTE'} ${s.num} · CH ${s.ch + 1}`;

export const targetFromAttr = (v: string): MidiTarget | null => {
  const [k, n] = v.split(':');
  if (k === 'knob') return { kind: 'knob', slot: Number(n) };
  if (k === 'btn' && actions.has(n)) return { kind: 'button', name: n };
  return null;
};

export const sameTarget = (a: MidiTarget, b: MidiTarget) => a.kind === b.kind
  && (a.kind === 'knob' ? a.slot === (b as typeof a).slot : a.name === (b as typeof a).name);
const sameSource = (a: MidiSource, b: MidiSource) => a.type === b.type && a.ch === b.ch && a.num === b.num;
/** Маппинги делят источник: тот же источник и пересекающиеся входы (любой или один и тот же). */
const clash = (a: MidiMapping, b: MidiMapping) => sameSource(a.src, b.src) && (!a.input || !b.input || a.input === b.input);
/** Маппинг, который отберёт этот источник у другой цели (окно настройки предупреждает). */
export const clashFor = (m: MidiMapping) => settings.mappings.find((x) => !sameTarget(x.target, m.target) && clash(x, m));
const targetKey = (t: MidiTarget) => (t.kind === 'knob' ? `knob:${t.slot}` : `btn:${t.name}`);

/** Есть ли маппинг на цель (подсветка в режиме LEARN). */
export const isMapped = (t: MidiTarget) => settings.mappings.some((m) => sameTarget(m.target, t));
/** Маппинг цели (у цели один источник). */
export const mappingFor = (t: MidiTarget) => settings.mappings.find((m) => sameTarget(m.target, t));

// ---------- MIDI LEARN ----------

/** on — режим LEARN; edit — открыто окно настройки маппинга (оно тоже ловит источник для своей цели). */
export const learn = { on: false, edit: false, target: null as MidiTarget | null, last: '' };
let learnListeners: (() => void)[] = [];
export function onLearnChanged(fn: () => void) { learnListeners.push(fn); }
const learnChanged = () => learnListeners.forEach((l) => l());

export function setLearn(on: boolean) {
  learn.on = on;
  learn.target = null;
  learn.last = '';
  learnChanged();
}

export function learnTarget(t: MidiTarget) {
  learn.target = t;
  learn.last = '';
  learnChanged();
}

/** Сохранить маппинги: источник ведёт только к одной цели. */
function store(list: MidiMapping[]) {
  saveSettings({ mappings: list });
  sent.clear();
  toggled.clear();
  learnChanged();
}

/** Первый свободный CC на канале 1 (для нового маппинга из окна настройки). */
function freeSource(): MidiSource {
  for (let n = 0; n < 128; n++) {
    const src: MidiSource = { type: 'cc', ch: 0, num: n };
    if (!settings.mappings.some((m) => sameSource(m.src, src))) return src;
  }
  return { type: 'cc', ch: 0, num: 0 };
}

/** Черновик маппинга цели без маппинга (окно настройки до первого изменения). */
export const draftMapping = (t: MidiTarget): MidiMapping => fullMapping({ src: freeSource(), target: t });

/**
 * Изменить маппинг цели (окно настройки, LEARN): поля patch поверх нынешнего маппинга (или нового).
 * Источник, занятый другой целью, переходит к этой.
 */
export function updateMapping(t: MidiTarget, patch: Partial<MidiMapping>) {
  const cur = mappingFor(t) ?? draftMapping(t);
  const m: MidiMapping = { ...cur, ...patch, target: t };
  store([...settings.mappings.filter((x) => !sameTarget(x.target, t) && !clash(x, m)), m]);
}

export function removeMapping(k: number) {
  store(settings.mappings.filter((_, i) => i !== k));
}

/** Снять маппинг цели (CLEAR в полосе LEARN, DELETE в окне настройки). */
export function clearTarget(t: MidiTarget) {
  store(settings.mappings.filter((m) => !sameTarget(m.target, t)));
}

export function clearMappings() {
  store([]);
}

/** Midi Fighter Twister (заводские настройки): энкодеры — CC 0–15 на канале 1, ряд за рядом, как сетка. */
export function twisterPreset() {
  const knobs = Array.from({ length: 16 }, (_, slot) => fullMapping({ src: { type: 'cc', ch: 0, num: slot }, target: { kind: 'knob', slot }, control: 'abs' }));
  store([...knobs, ...settings.mappings.filter((m) => m.target.kind !== 'knob' && !knobs.some((k) => sameSource(k.src, m.src)))]);
}

// ---------- Ручки ----------

/** Поворот энкодера — одна запись в UNDO, пока он крутится (пауза 300 мс завершает жест). */
let gestureTimer = 0;
function touchGesture() {
  if (!gestureTimer) beginGesture();
  clearTimeout(gestureTimer);
  gestureTimer = window.setTimeout(() => { gestureTimer = 0; endGesture(); }, 300);
}

/** Шаг энкодера (RELATIVE) из значения CC. */
function relStep(enc: MidiMapping['enc'], v: number): number {
  if (enc === 'offset') return v - 64;
  if (enc === 'twos') return v < 64 ? v : v - 128;
  return v & 64 ? -(v & 63) : v & 63;
}

/** Состояние TOGGLE по цели (включено ли). */
const toggled = new Map<string, boolean>();

/**
 * Значение на ручку: как палец — с удержанием шага p-lock, с удержанием LFO/ENV — назначение.
 * at — положение 0–1 внутри диапазона (ABSOLUTE и кнопки), step — шаг энкодера (RELATIVE).
 */
function knobInput(m: MidiMapping, slot: number, at: number | null, step: number) {
  const mode = gridMode();
  const p = gridFor(mode)[slot];
  if (!p) return;
  const held = firstHeldStep();
  const lfo = mode === 'track' || mode === 'fx' ? heldLfo() : null;
  const lo = Math.min(m.min, m.max);
  const hi = Math.max(m.min, m.max);
  // Инвертированный диапазон — энкодер крутит в обратную сторону.
  const dir = m.max >= m.min ? 1 : -1;
  touchGesture();
  if (held === null && lfo) {
    // Степень назначения −1…1: диапазон 0–1 растягивается на неё.
    const a = assignFor(mode, p);
    const cur = (((a && a.lfo === lfo ? a.amount : 0) + 1) / 2);
    const n = at !== null ? m.min + at * (m.max - m.min) : Math.min(hi, Math.max(lo, cur + (dir * step) / 128));
    setLfoAmount(p, lfo, n * 2 - 1, mode);
    return;
  }
  const base = held !== null ? lockValue(held, p) ?? paramValue(mode, p) : paramValue(mode, p);
  const n = at !== null ? m.min + at * (m.max - m.min) : Math.min(hi, Math.max(lo, toNorm(p, base) + (dir * step) / 128));
  if (held !== null) setLockNorm(p, n);
  else setParamNorm(mode, p, n);
}

// ---------- Разбор сообщений ----------

/** Нажатые MIDI-кнопки (чтобы отпускание пришло той же кнопке). */
const down = new Set<string>();

function buttonInput(name: string, on: boolean) {
  const a = actions.get(name);
  if (!a) return;
  if (on && !down.has(name)) { down.add(name); a.press(); }
  else if (!on && down.has(name)) { down.delete(name); a.release?.(); }
}

/** Сообщение по маппингу. value — CC или скорость ноты; on — нажатие (CC ≥ 64, Note On). */
function apply(m: MidiMapping, isCc: boolean, value: number, on: boolean) {
  const t = m.target;
  const key = targetKey(t);
  // Кнопочные типы: MOMENTARY — пока нажата; TOGGLE — нажатие переключает (отпускание не важно).
  const button = m.control === 'momentary' || m.control === 'toggle' || !isCc;
  let state = on;
  if (button && m.control === 'toggle') {
    if (!on) return;
    state = !toggled.get(key);
    toggled.set(key, state);
  }
  if (t.kind === 'button') {
    // У кнопок ABSOLUTE и RELATIVE ведут себя как MOMENTARY.
    if (button || m.control === 'abs') buttonInput(t.name, state);
    else if (relStep(m.enc, value) > 0) { buttonInput(t.name, true); buttonInput(t.name, false); }
    return;
  }
  if (button) knobInput(m, t.slot, state ? 1 : 0, 0);
  else if (m.control === 'abs') knobInput(m, t.slot, value / 127, 0);
  else knobInput(m, t.slot, null, relStep(m.enc, value));
}

/** Разбор MIDI-сообщения: маппинги и LEARN, остальные ноты — играют дорожку. */
function handle(status: number, d1: number, d2: number, input: string) {
  const type = status & 0xf0;
  const ch = status & 0x0f;
  const isCc = type === 0xb0;
  const isOn = type === 0x90 && d2 > 0;
  const isOff = type === 0x80 || (type === 0x90 && d2 === 0);
  if (!isCc && !isOn && !isOff) return;
  const src: MidiSource = { type: isCc ? 'cc' : 'note', ch, num: d1 };

  if ((learn.on || learn.edit) && (isCc || isOn)) {
    learn.last = sourceLabel(src);
    // Новый источник цели; тип управления, диапазон и порт остаются (у новой — по виду сообщения).
    if (learn.target) {
      const had = mappingFor(learn.target);
      // Вход — тот, с которого пришло сообщение (как Port в Drambo).
      updateMapping(learn.target, had ? { src, input } : { src, input, control: learn.target.kind === 'knob' && isCc ? 'abs' : 'momentary' });
    }
    learnChanged();
    return;
  }

  const maps = settings.mappings.filter((m) => sameSource(m.src, src) && (!m.input || m.input === input));
  if (maps.length) {
    for (const m of maps) apply(m, isCc, d2, isCc ? d2 >= 64 : isOn);
    return;
  }
  if (!isOn) return;
  if (settings.noteChannel && ch !== settings.noteChannel - 1) return;
  onNote(d1, d2, settings.noteRoute === 'channel' ? ch : null);
}

// ---------- Обратная связь ----------

/** Последние отправленные значения (по порту и источнику) — шлём только изменения. */
const sent = new Map<string, number>();
let lastFeedback = 0;

/** Выход обратной связи маппинга (null — нет). */
function feedbackOut(m: MidiMapping): MIDIOutput | null {
  const id = m.port === 'none' ? '' : m.port || settings.midiFeedback;
  const out = id ? access?.outputs.get(id) : undefined;
  return out && out.state === 'connected' ? out : null;
}

/**
 * Значения ручек и состояние кнопок — на выходы обратной связи (кольца и подсветка энкодеров).
 * Ручка — в своём диапазоне 0–127; кнопка — 127 (горит) или 0. Вызывается каждый кадр.
 */
export function sendFeedback(now: number) {
  if (!access || now - lastFeedback < 30) return;
  lastFeedback = now;
  const mode = gridMode();
  const grid = gridFor(mode);
  const held = firstHeldStep();
  for (const m of settings.mappings) {
    const out = feedbackOut(m);
    if (!out) continue;
    let v: number;
    if (m.target.kind === 'knob') {
      const p = grid[m.target.slot];
      const n = p ? toNorm(p, (held !== null ? lockValue(held, p) : undefined) ?? paramValue(mode, p)) : 0;
      const span = m.max - m.min;
      v = span ? Math.round(Math.min(1, Math.max(0, (n - m.min) / span)) * 127) : 0;
    } else {
      v = actions.get(m.target.name)?.state?.() ? 127 : 0;
    }
    const key = `${out.id}:${m.src.type}:${m.src.ch}:${m.src.num}`;
    if (sent.get(key) === v) continue;
    sent.set(key, v);
    out.send(m.src.type === 'cc' ? [0xb0 | m.src.ch, m.src.num, v] : [0x90 | m.src.ch, m.src.num, v]);
  }
}

/** Выходы MIDI (для выбора порта обратной связи). */
export function midiOutputs(): { id: string; name: string }[] {
  const out: { id: string; name: string }[] = [];
  access?.outputs.forEach((p) => { if (p.state === 'connected') out.push({ id: p.id, name: p.name ?? 'MIDI Out' }); });
  return out;
}

/** Разрешение Web MIDI и подписка на входы. */
export async function initMidi(): Promise<void> {
  if (!hasWebMidi() || access) return;
  try {
    access = await navigator.requestMIDIAccess();
  } catch { return; }
  const bind = () => {
    access!.inputs.forEach((input) => {
      // Выбранный вход ('' — все).
      input.onmidimessage = (e) => {
        if (settings.midiIn && input.id !== settings.midiIn) return;
        const d = e.data;
        if (d && d.length >= 3) handle(d[0], d[1], d[2], input.id);
      };
    });
    sent.clear();
    changed();
  };
  access.onstatechange = bind;
  bind();
}

/** Подключённые устройства: Web MIDI (входы и выходы) и подключённые здесь Bluetooth MIDI. */
export function midiDevices(): MidiDevice[] {
  const out: MidiDevice[] = [];
  access?.inputs.forEach((p) => { if (p.state === 'connected') out.push({ id: p.id, name: p.name ?? 'MIDI In', kind: 'midi', dir: 'in' }); });
  access?.outputs.forEach((p) => { if (p.state === 'connected') out.push({ id: p.id, name: p.name ?? 'MIDI Out', kind: 'midi', dir: 'out' }); });
  for (const b of ble) out.push({ id: b.id, name: b.name, kind: 'bluetooth', dir: 'in' });
  return out;
}

/**
 * Пакет BLE MIDI: заголовок, затем [метка времени][статус][данные…] (статус может повторяться
 * «бегущим» — без нового байта статуса).
 */
function parseBle(b: Uint8Array, id: string) {
  let status = 0;
  let i = 1;
  while (i < b.length) {
    // Метка времени (старший бит), за ней может идти новый статус.
    if (b[i] & 0x80) {
      i++;
      if (i < b.length && b[i] & 0x80) status = b[i++];
    }
    if (!status || status >= 0xf0) break;
    const two = (status & 0xf0) !== 0xc0 && (status & 0xf0) !== 0xd0;
    if (i + (two ? 1 : 0) >= b.length) break;
    handle(status, b[i], two ? b[i + 1] : 0, id);
    i += two ? 2 : 1;
  }
}

/** Поиск и подключение Bluetooth MIDI (системное окно выбора устройства). */
export async function connectBluetooth(): Promise<string> {
  const bt = (navigator as Navigator & { bluetooth: Bluetooth }).bluetooth;
  const device = await bt.requestDevice({ filters: [{ services: [BLE_MIDI_SERVICE] }] });
  const server = await device.gatt!.connect();
  const service = await server.getPrimaryService(BLE_MIDI_SERVICE);
  const ch = await service.getCharacteristic(BLE_MIDI_CHAR);
  ch.addEventListener('characteristicvaluechanged', () => {
    const v = ch.value;
    if (v) parseBle(new Uint8Array(v.buffer, v.byteOffset, v.byteLength), device.id);
  });
  await ch.startNotifications();
  const name = device.name || 'Bluetooth MIDI';
  ble.push({ id: device.id, name, device });
  device.addEventListener('gattserverdisconnected', () => {
    const k = ble.findIndex((b) => b.device === device);
    if (k >= 0) ble.splice(k, 1);
    changed();
  });
  changed();
  return name;
}

/** Отключить Bluetooth MIDI-устройство. */
export function disconnectBluetooth(id: string) {
  const b = ble.find((x) => x.id === id);
  b?.device.gatt?.disconnect();
}
