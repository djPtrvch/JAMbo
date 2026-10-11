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
import { saveSettings, settings, type MidiMapping, type MidiSource, type MidiTarget } from './settings';

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

/** Действие кнопки для MIDI: нажатие и отпускание (у кнопок на удержание). */
export interface MidiAction { label: string; press: () => void; release?: () => void }
const actions = new Map<string, MidiAction>();
const order: string[] = [];

/** Интерфейс регистрирует кнопку; элемент помечается data-midi для MIDI LEARN. */
export function registerAction(name: string, action: MidiAction, el?: HTMLElement) {
  if (!actions.has(name)) order.push(name);
  actions.set(name, action);
  if (el) el.dataset.midi = `btn:${name}`;
}

/** Ручка сетки (позиция 0–15) для MIDI LEARN. */
export function markKnob(el: HTMLElement, slot: number) {
  el.dataset.midi = `knob:${slot}`;
}

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

const sameTarget = (a: MidiTarget, b: MidiTarget) => a.kind === b.kind
  && (a.kind === 'knob' ? a.slot === (b as typeof a).slot : a.name === (b as typeof a).name);
const sameSource = (a: MidiSource, b: MidiSource) => a.type === b.type && a.ch === b.ch && a.num === b.num;

/** Есть ли маппинг на цель (подсветка в режиме LEARN). */
export const isMapped = (t: MidiTarget) => settings.mappings.some((m) => sameTarget(m.target, t));

// ---------- MIDI LEARN ----------

export const learn = { on: false, target: null as MidiTarget | null, last: '' };
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

/** Новый маппинг: источник занимает цель (старые маппинги этого источника и этой цели убираются). */
export function addMapping(m: MidiMapping) {
  const rest = settings.mappings.filter((x) => !sameSource(x.src, m.src) && !sameTarget(x.target, m.target));
  saveSettings({ mappings: [...rest, m] });
  sent.clear();
}

export function removeMapping(k: number) {
  saveSettings({ mappings: settings.mappings.filter((_, i) => i !== k) });
}

/** Все маппинги цели (двойной тап в режиме LEARN — снять). */
export function clearTarget(t: MidiTarget) {
  saveSettings({ mappings: settings.mappings.filter((m) => !sameTarget(m.target, t)) });
}

export function clearMappings() {
  saveSettings({ mappings: [] });
}

/** Midi Fighter Twister (заводские настройки): энкодеры — CC 0–15 на канале 1, ряд за рядом, как сетка. */
export function twisterPreset() {
  const knobs: MidiMapping[] = Array.from({ length: 16 }, (_, slot) => ({ src: { type: 'cc', ch: 0, num: slot }, target: { kind: 'knob', slot } }));
  const rest = settings.mappings.filter((m) => m.target.kind !== 'knob' && !knobs.some((k) => sameSource(k.src, m.src)));
  saveSettings({ mappings: [...knobs, ...rest], knobMode: 'abs' });
  sent.clear();
}

// ---------- Ручки ----------

/** Поворот энкодера — одна запись в UNDO, пока он крутится (пауза 300 мс завершает жест). */
let gestureTimer = 0;
function touchGesture() {
  if (!gestureTimer) beginGesture();
  clearTimeout(gestureTimer);
  gestureTimer = window.setTimeout(() => { gestureTimer = 0; endGesture(); }, 300);
}

/** CC на ручку: как палец — с удержанием шага p-lock, с удержанием LFO/ENV — назначение. */
function knobInput(slot: number, value: number) {
  const mode = gridMode();
  const p = gridFor(mode)[slot];
  if (!p) return;
  const rel = settings.knobMode === 'abs' ? null
    : settings.knobMode === 'rel64' ? value - 64 : value < 64 ? value : value - 128;
  const held = firstHeldStep();
  const lfo = mode === 'track' || mode === 'fx' ? heldLfo() : null;
  touchGesture();
  if (held === null && lfo) {
    const a = assignFor(mode, p);
    const cur = a && a.lfo === lfo ? a.amount : 0;
    const v = rel === null ? (value / 127) * 2 - 1 : cur + rel / 64;
    setLfoAmount(p, lfo, Math.min(1, Math.max(-1, v)), mode);
    return;
  }
  const base = held !== null ? lockValue(held, p) ?? paramValue(mode, p) : paramValue(mode, p);
  const n = rel === null ? value / 127 : Math.min(1, Math.max(0, toNorm(p, base) + rel / 128));
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

/** Разбор MIDI-сообщения: маппинги и LEARN, остальные ноты — играют дорожку. */
function handle(status: number, d1: number, d2: number) {
  const type = status & 0xf0;
  const ch = status & 0x0f;
  const isCc = type === 0xb0;
  const isOn = type === 0x90 && d2 > 0;
  const isOff = type === 0x80 || (type === 0x90 && d2 === 0);
  if (!isCc && !isOn && !isOff) return;
  const src: MidiSource = { type: isCc ? 'cc' : 'note', ch, num: d1 };

  if (learn.on && (isCc || isOn)) {
    learn.last = sourceLabel(src);
    if (learn.target) addMapping({ src, target: learn.target });
    learnChanged();
    return;
  }

  const maps = settings.mappings.filter((m) => sameSource(m.src, src));
  if (maps.length) {
    for (const m of maps) {
      if (m.target.kind === 'knob') { if (isCc) knobInput(m.target.slot, d2); }
      else buttonInput(m.target.name, isCc ? d2 >= 64 : isOn);
    }
    return;
  }
  if (!isOn) return;
  if (settings.noteChannel && ch !== settings.noteChannel - 1) return;
  onNote(d1, d2, settings.noteRoute === 'channel' ? ch : null);
}

// ---------- Обратная связь ----------

/** Последние отправленные значения (по источнику) — шлём только изменения. */
const sent = new Map<string, number>();
let lastFeedback = 0;

/** Значения ручек — на выход обратной связи (кольца энкодеров). Вызывается каждый кадр. */
export function sendFeedback(now: number) {
  if (!access || !settings.midiFeedback || now - lastFeedback < 30) return;
  lastFeedback = now;
  const out = access.outputs.get(settings.midiFeedback);
  if (!out || out.state !== 'connected') return;
  const mode = gridMode();
  const grid = gridFor(mode);
  const held = firstHeldStep();
  for (const m of settings.mappings) {
    if (m.target.kind !== 'knob' || m.src.type !== 'cc') continue;
    const p = grid[m.target.slot];
    const v = p ? Math.round(toNorm(p, (held !== null ? lockValue(held, p) : undefined) ?? paramValue(mode, p)) * 127) : 0;
    const key = `${m.src.ch}:${m.src.num}`;
    if (sent.get(key) === v) continue;
    sent.set(key, v);
    out.send([0xb0 | m.src.ch, m.src.num, v]);
  }
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
        if (d && d.length >= 3) handle(d[0], d[1], d[2]);
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
function parseBle(b: Uint8Array) {
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
    handle(status, b[i], two ? b[i + 1] : 0);
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
    if (v) parseBle(new Uint8Array(v.buffer, v.byteOffset, v.byteLength));
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
