// Меню MIDI (бутерброд → MIDI): подключённые MIDI-устройства, подключение Bluetooth MIDI (CONNECT)
// и ADVERTISE (быть видимым как Bluetooth MIDI — только в нативном приложении).
// Входящие ноты играют выбранную дорожку (см. midi.ts). В Safari на iPad Web MIDI и Web Bluetooth
// нет — меню объясняет это.

import {
  connectBluetooth, disconnectBluetooth, hasBluetooth, hasWebMidi, initMidi, midiDevices, onDevicesChanged,
} from '../midi';
import { h, setText } from './dom';
import { backHeader, makePopup, popupButton, type Popup } from './popup';

let panel: Popup;
let list: HTMLElement;
let status: HTMLElement;
let bleBtn: HTMLButtonElement;
let onBack: () => void = () => {};

function build() {
  panel = makePopup('settings midi-menu');
  list = h('div', 'settings-devices');
  status = h('div', 'settings-note');
  bleBtn = popupButton('CONNECT', () => {
    setText(status, 'Searching for Bluetooth MIDI devices…');
    void connectBluetooth()
      .then((name) => setText(status, `Connected: ${name}`))
      .catch((e) => setText(status, e?.name === 'NotFoundError' ? 'No device chosen.' : `Could not connect: ${e?.message ?? e}`));
  });
  // ADVERTISE — iPad сам виден другим как Bluetooth MIDI-устройство. В браузерах объявлять себя
  // по Bluetooth нельзя (Web Bluetooth умеет только искать чужие устройства) — кнопка появится
  // рабочей в нативном приложении (CoreMIDI).
  const advertise = popupButton('ADVERTISE', () => {});
  advertise.disabled = true;
  const bleRow = h('div', 'settings-choice');
  bleRow.append(bleBtn, advertise);
  panel.box.append(
    backHeader(h('div', 'project-title', 'MIDI'), () => { panel.close(); onBack(); }),
    h('div', 'source-title', 'CONNECTED DEVICES'),
    list,
    h('div', 'source-title', 'BLUETOOTH MIDI'),
    bleRow,
    h('div', 'settings-note', 'ADVERTISE makes this iPad visible to other devices as Bluetooth MIDI. Browsers can’t advertise over Bluetooth, so it will work in the native app.'),
    status,
  );
  onDevicesChanged(() => { if (panel.isOpen()) fill(); });
}

function fill() {
  const ds = midiDevices();
  list.replaceChildren(...(ds.length ? ds.map((d) => {
    const label = `${d.name}  ·  ${d.kind === 'bluetooth' ? 'BLUETOOTH' : d.dir === 'in' ? 'IN' : 'OUT'}`;
    // Тап по Bluetooth-устройству отключает его.
    const b = popupButton(d.kind === 'bluetooth' ? `${label}  ·  tap to disconnect` : label, () => {
      if (d.kind === 'bluetooth') disconnectBluetooth(d.id);
    });
    b.classList.add('current');
    return b;
  }) : [h('div', 'settings-note', 'No MIDI devices connected.')]));
}

/** Открыть меню MIDI; back — стрелка назад (главное меню бутерброда). */
export function openMidi(anchor: Element, back: () => void) {
  onBack = back;
  if (!panel) build();
  bleBtn.disabled = !hasBluetooth();
  if (!hasWebMidi() && !hasBluetooth()) {
    setText(status, 'Safari on iPad has no Web MIDI or Web Bluetooth, so MIDI devices can’t be used in the web version. MIDI (including Bluetooth MIDI) will work in the native iPad app.');
  } else {
    setText(status, hasBluetooth() ? 'Notes from MIDI inputs play the selected track.' : 'Notes from MIDI inputs play the selected track. Pair Bluetooth MIDI in the system settings — it then appears here.');
  }
  fill();
  panel.openAt(anchor, 420);
  void initMidi().then(fill);
}
