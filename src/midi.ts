// MIDI (бутерброд → MIDI): подключённые устройства и подключение Bluetooth MIDI.
// USB и уже сопряжённые устройства — через Web MIDI, Bluetooth MIDI — через Web Bluetooth
// (BLE MIDI: сервис 03b80e5a-…, характеристика 7772e5db-…). Ноты с входов играют выбранную
// дорожку, как пианоролл (и записываются с REC).
// В Safari на iPad ни Web MIDI, ни Web Bluetooth нет — меню об этом говорит; MIDI появится
// в нативном приложении.

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

type NoteHandler = (note: number, velocity: number) => void;
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

/** Разбор MIDI-сообщения: Note On с ненулевой скоростью — нота. */
function handle(status: number, d1: number, d2: number) {
  if ((status & 0xf0) === 0x90 && d2 > 0) onNote(d1, d2);
}

/** Разрешение Web MIDI и подписка на входы. */
export async function initMidi(): Promise<void> {
  if (!hasWebMidi() || access) return;
  try {
    access = await navigator.requestMIDIAccess();
  } catch { return; }
  const bind = () => {
    access!.inputs.forEach((input) => {
      input.onmidimessage = (e) => {
        const d = e.data;
        if (d && d.length >= 3) handle(d[0], d[1], d[2]);
      };
    });
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
