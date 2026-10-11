// Меню MIDI (бутерброд → MIDI), вкладки:
// DEVICES — подключённые устройства, выбор входа, выход обратной связи (кольца энкодеров),
//   Bluetooth MIDI: CONNECT и ADVERTISE (быть видимым как Bluetooth MIDI — только в нативном приложении);
// MAPPING — MIDI LEARN, пресет Midi Fighter Twister, режим энкодеров, список маппингов;
// NOTES — канал нот и куда они идут (выбранная дорожка или канал N → дорожка N).
// В Safari на iPad Web MIDI и Web Bluetooth нет — меню объясняет это.

import {
  clearMappings, connectBluetooth, disconnectBluetooth, hasBluetooth, hasWebMidi, initMidi, midiDevices,
  onDevicesChanged, removeMapping, setLearn, sourceLabel, targetLabel, twisterPreset,
} from '../midi';
import { TRACK_COUNT } from '../params';
import { saveSettings, settings } from '../settings';
import { openMapEditor } from './mapedit';
import { h } from './dom';
import { backHeader, MENU_W, makePopup, popupButton, type Popup } from './popup';

type Tab = 'devices' | 'mapping' | 'notes';

let panel: Popup;
let body: HTMLElement;
let status = '';
let tab: Tab = 'devices';
const tabBtns = {} as Record<Tab, HTMLButtonElement>;
let onBack: () => void = () => {};

function build() {
  panel = makePopup('settings midi-menu');
  const tabs = h('div', 'settings-tabs');
  for (const [t, label] of [['devices', 'DEVICES'], ['mapping', 'MAPPING'], ['notes', 'NOTES']] as [Tab, string][]) {
    tabBtns[t] = popupButton(label, () => { tab = t; render(); });
    tabs.append(tabBtns[t]);
  }
  body = h('div', 'settings-body');
  panel.box.append(backHeader(h('div', 'project-title', 'MIDI'), () => { panel.close(); onBack(); }), tabs, body);
  onDevicesChanged(() => { if (panel.isOpen()) render(); });
}

const note = (text: string) => h('div', 'settings-note', text);
const title = (text: string) => h('div', 'source-title', text);

/** Ряд кнопок выбора одного значения. */
function choice<T>(values: T[], current: T, name: (v: T) => string, pick: (v: T) => void): HTMLElement {
  const row = h('div', 'settings-choice');
  for (const v of values) {
    const b = popupButton(name(v), () => { pick(v); render(); });
    b.classList.toggle('current', v === current);
    row.append(b);
  }
  return row;
}

/** Список устройств с выбором одного ('' — первый пункт). */
function deviceChoice(first: string, items: { id: string; name: string }[], current: string, pick: (id: string) => void): HTMLElement {
  const list = h('div', 'settings-devices');
  for (const it of [{ id: '', name: first }, ...items]) {
    const b = popupButton(it.name, () => { pick(it.id); render(); });
    b.classList.toggle('current', it.id === current);
    list.append(b);
  }
  return list;
}

function unsupported(): HTMLElement | null {
  return hasWebMidi() || hasBluetooth() ? null
    : note('Safari on iPad has no Web MIDI or Web Bluetooth, so MIDI devices can’t be used in the web version. MIDI (including Bluetooth MIDI and mapping) will work in the native iPad app.');
}

function renderDevices() {
  const ds = midiDevices();
  const ins = ds.filter((d) => d.dir === 'in' && d.kind === 'midi');
  const outs = ds.filter((d) => d.dir === 'out');
  const bt = ds.filter((d) => d.kind === 'bluetooth');
  const bleBtn = popupButton('CONNECT', () => {
    status = 'Searching for Bluetooth MIDI devices…';
    render();
    void connectBluetooth()
      .then((name) => { status = `Connected: ${name}`; render(); })
      .catch((e) => { status = e?.name === 'NotFoundError' ? 'No device chosen.' : `Could not connect: ${e?.message ?? e}`; render(); });
  });
  bleBtn.disabled = !hasBluetooth();
  // ADVERTISE — iPad сам виден другим как Bluetooth MIDI-устройство. В браузерах объявлять себя
  // по Bluetooth нельзя (Web Bluetooth умеет только искать чужие устройства) — кнопка появится
  // рабочей в нативном приложении (CoreMIDI).
  const advertise = popupButton('ADVERTISE', () => {});
  advertise.disabled = true;
  const bleRow = h('div', 'settings-choice');
  bleRow.append(bleBtn, advertise);
  const btList = h('div', 'settings-devices');
  // Тап по Bluetooth-устройству отключает его.
  for (const d of bt) {
    const b = popupButton(`${d.name}  ·  tap to disconnect`, () => disconnectBluetooth(d.id));
    b.classList.add('current');
    btList.append(b);
  }
  const u = unsupported();
  body.append(
    ...(u ? [u] : []),
    title('INPUT'),
    ins.length ? deviceChoice('ALL INPUTS', ins, settings.midiIn, (id) => saveSettings({ midiIn: id })) : note('No MIDI inputs connected.'),
    title('FEEDBACK OUTPUT'),
    outs.length ? deviceChoice('NONE', outs, settings.midiFeedback, (id) => saveSettings({ midiFeedback: id })) : note('No MIDI outputs connected.'),
    note('Knob values are sent back to this output, so encoder LED rings (Midi Fighter Twister) follow the screen.'),
    title('BLUETOOTH MIDI'),
    bleRow,
    btList,
    note('ADVERTISE makes this iPad visible to other devices as Bluetooth MIDI. Browsers can’t advertise over Bluetooth, so it will work in the native app.'),
    ...(status ? [note(status)] : []),
  );
}


const CONTROL_NAMES = { momentary: 'MOMENTARY', toggle: 'TOGGLE', abs: 'ABSOLUTE', rel: 'RELATIVE' };

function renderMapping() {
  const u = unsupported();
  const learnBtn = popupButton('MIDI LEARN', () => { panel.close(); setLearn(true); });
  const twister = popupButton('TWISTER PRESET', () => { twisterPreset(); render(); });
  const top = h('div', 'settings-choice');
  top.append(learnBtn, twister);
  const list = h('div', 'project-list midi-maps');
  settings.mappings.forEach((m, k) => {
    const row = h('div', 'midi-map');
    row.append(h('div', 'midi-map-src', sourceLabel(m.src)), h('div', 'midi-map-dst', `${targetLabel(m.target)}  ·  ${CONTROL_NAMES[m.control]}`));
    // Тап по строке — окно настройки маппинга (стрелка назад — сюда).
    row.addEventListener('pointerup', (e) => {
      if ((e.target as Element).closest('.midi-map-del')) return;
      panel.close();
      openMapEditor(m.target, () => openMidi(anchorEl, onBack));
    });
    const del = popupButton('✕', () => { removeMapping(k); render(); });
    del.classList.add('midi-map-del');
    row.append(del);
    list.append(row);
  });
  const clear = popupButton('CLEAR ALL', () => { clearMappings(); render(); });
  clear.disabled = settings.mappings.length === 0;
  body.append(
    ...(u ? [u] : []),
    top,
    note('MIDI LEARN: tap a knob or button on screen, then move a control; double-tap it to open MIDI MAP (port, event type, number, control type, channel, range, feedback port). Knobs are mapped by position in the 4×4 grid and follow the current mode (track, FX, MOD, MIX, MST). Hold a step to p-lock, hold LFO/ENV to set modulation. TWISTER PRESET maps CC 0–15 on channel 1 to the 16 knobs. Tap a mapping below to edit it.'),
    title(`MAPPINGS (${settings.mappings.length})`),
    settings.mappings.length ? list : note('No mappings yet.'),
    clear,
  );
}

function renderNotes() {
  const u = unsupported();
  body.append(
    ...(u ? [u] : []),
    title('NOTE CHANNEL'),
    choice(Array.from({ length: 17 }, (_, i) => i), settings.noteChannel, (c) => (c ? String(c) : 'ALL'), (c) => saveSettings({ noteChannel: c })),
    title('NOTES PLAY'),
    choice<'selected' | 'channel'>(['selected', 'channel'], settings.noteRoute, (r) => (r === 'selected' ? 'SELECTED TRACK' : `CH 1–${TRACK_COUNT} → TRACKS`), (r) => saveSettings({ noteRoute: r })),
    note(`Notes from MIDI inputs play like the piano roll (and are recorded with REC). With CH 1–${TRACK_COUNT} → TRACKS, channel N plays track N. Notes and CCs mapped to buttons don’t play.`),
  );
}

function render() {
  for (const t of Object.keys(tabBtns) as Tab[]) tabBtns[t].classList.toggle('current', t === tab);
  body.replaceChildren();
  if (tab === 'devices') renderDevices();
  else if (tab === 'mapping') renderMapping();
  else renderNotes();
}

/** Открыть меню MIDI; back — стрелка назад (главное меню бутерброда). */
let anchorEl: Element;

export function openMidi(anchor: Element, back: () => void) {
  onBack = back;
  anchorEl = anchor;
  if (!panel) build();
  status = '';
  render();
  panel.openAt(anchor, MENU_W);
  void initMidi().then(() => { if (panel.isOpen()) render(); });
}


