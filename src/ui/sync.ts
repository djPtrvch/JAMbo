// Меню SYNC (бутерброд → SYNC): SYNC QUANTUM (такты); MIDI CLOCK — вкл./выкл., CLOCK SOURCE (SEND — отдаём,
// RECEIVE — принимаем), выход клока, SYNC START/STOP, MIDI OFFSET; ABLETON LINK — вкл./выкл., IN-APP NOTIFICATIONS,
// SYNC START/STOP, LINK OFFSET. OFFSET — стрелки ◀ ▶ по 1 ms (удержание — повтор), −200…+200 ms.
// Настройки — в браузере, общие для проектов. Web MIDI в Safari нет, Link — только в нативном приложении (этап 10).

import { hasWebMidi, initMidi, midiOutputs, onDevicesChanged } from '../midi';
import { saveSettings, settings, type SyncSettings } from '../settings';
import { notify } from '../sync';
import { h } from './dom';
import { backHeader, makePopup, openMenuPanel, popupButton, type Popup } from './popup';

let panel: Popup;
let body: HTMLElement;
let onBack: () => void = () => {};

const note = (text: string) => h('div', 'settings-note', text);
const title = (text: string) => h('div', 'source-title', text);
const set = (patch: Partial<SyncSettings>) => saveSettings({ sync: { ...settings.sync, ...patch } });

function choice<T>(label: string, values: T[], current: T, name: (v: T) => string, pick: (v: T) => void): HTMLElement {
  const row = h('div', 'settings-row');
  const btns = h('div', 'settings-choice');
  for (const v of values) {
    const b = popupButton(name(v), () => { pick(v); render(); });
    b.classList.toggle('current', v === current);
    btns.append(b);
  }
  row.append(title(label), btns);
  return row;
}
/** OFFSET: ◀ значение ▶, шаг 1 ms (удержание стрелки — повтор), −200…+200 ms. */
function offset(label: string, get: () => number, put: (v: number) => void): HTMLElement {
  const row = h('div', 'settings-row');
  const line = h('div', 'sync-offset');
  const value = h('div', 'sync-offset-value', '');
  const show = () => { const v = get(); value.textContent = `${v > 0 ? '+' : ''}${v} ms`; };
  const arrow = (txt: string, d: number) => {
    const b = popupButton(txt, () => {});
    let timer = 0;
    const step = () => { put(Math.max(-200, Math.min(200, get() + d))); show(); };
    const stop = () => { clearTimeout(timer); clearInterval(timer); };
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      step();
      timer = window.setTimeout(() => { timer = window.setInterval(step, 50); }, 350);
    });
    b.addEventListener('pointerup', stop);
    b.addEventListener('pointercancel', stop);
    b.addEventListener('pointerleave', stop);
    return b;
  };
  show();
  line.append(arrow('◀', -1), value, arrow('▶', 1));
  row.append(title(label), line);
  return row;
}
const onOff = (label: string, cur: boolean, pick: (v: boolean) => void) => choice(label, [false, true], cur, (v) => (v ? 'ON' : 'OFF'), pick);

function build() {
  panel = makePopup('settings sync-menu');
  body = h('div', 'settings-body');
  panel.box.append(backHeader(h('div', 'project-title', 'Sync'), () => { panel.close(); onBack(); }), body);
  onDevicesChanged(() => { if (panel.isOpen()) render(); });
}

function render() {
  const s = settings.sync;
  body.replaceChildren();
  // Общее.
  body.append(
    h('div', 'menu-head', 'GENERAL'),
    choice('SYNC QUANTUM', [1, 2, 4, 8] as SyncSettings['quantum'][], s.quantum, (v) => `${v} BAR${v > 1 ? 'S' : ''}`, (v) => set({ quantum: v })),
    note('Phrase length in bars for lining up the start with other devices (Ableton Link).'),
  );
  // MIDI-клок.
  body.append(
    h('div', 'menu-head', 'MIDI CLOCK'),
    onOff('MIDI CLOCK SYNC', s.clock, (v) => { set({ clock: v }); if (v) void initMidi().then(render); }),
    choice('CLOCK SOURCE', ['send', 'receive'] as const, s.source, (v) => (v === 'send' ? 'SEND' : 'RECEIVE'), (v) => set({ source: v })),
  );
  if (s.source === 'send') {
    const outs = midiOutputs();
    const list = h('div', 'settings-devices');
    for (const it of [{ id: '', name: 'ALL OUTPUTS' }, ...outs]) {
      const b = popupButton(it.name, () => { set({ clockOut: it.id }); render(); });
      b.classList.toggle('current', it.id === s.clockOut);
      list.append(b);
    }
    body.append(title('CLOCK OUTPUT'), list);
  } else body.append(note('The clock is received from the MIDI input chosen in MIDI → DEVICES. The project tempo follows it; without clock for 0.5 s the own tempo returns.'));
  body.append(
    onOff('SYNC START/STOP', s.midiStartStop, (v) => set({ midiStartStop: v })),
    offset('MIDI OFFSET', () => settings.sync.midiOffset, (v) => set({ midiOffset: v })),
    note(s.source === 'send' ? 'ON: PLAY sends MIDI Start, stop sends MIDI Stop. The clock runs all the time while MIDI clock sync is on. MIDI OFFSET moves the sent clock later (+) or earlier (−) to line up with the other device.'
      : 'ON: MIDI Start starts playback on the next clock tick, Continue resumes, Stop stops. MIDI OFFSET moves own steps later (+) or earlier (−) than the clock.'),
  );
  if (!hasWebMidi()) body.append(note('This browser has no Web MIDI (Safari on iPad) — MIDI clock will work in the native app.'));
  // Ableton Link.
  body.append(
    h('div', 'menu-head', 'ABLETON LINK'),
    onOff('ABLETON LINK', s.link, (v) => { set({ link: v }); if (v) notify('Ableton Link: on'); }),
    onOff('IN-APP NOTIFICATIONS', s.linkNotify, (v) => { set({ linkNotify: v }); if (v) notify('Notifications on'); }),
    onOff('SYNC START/STOP', s.linkStartStop, (v) => set({ linkStartStop: v })),
    offset('LINK OFFSET', () => settings.sync.linkOffset, (v) => set({ linkOffset: v })),
    note('Ableton Link works in the native app; in the browser these settings are only stored. Notifications show a line at the top when a device joins or leaves the session.'),
  );
}

export function openSync(anchor: Element, back: () => void) {
  onBack = back;
  if (!panel) build();
  render();
  openMenuPanel(panel, anchor);
}
