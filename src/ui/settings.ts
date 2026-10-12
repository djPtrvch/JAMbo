// Меню «бутерброд»: PROJECTS (проекты, ui/projects.ts), SETTINGS и MIDI (ui/midi.ts);
// во вложенных меню стрелка назад возвращает сюда.
// SETTINGS — вкладки AUDIO ENGINE (частота дискретизации, размер буфера), BACKGROUND (звук в фоне)
// и OUTPUT (выход и вход аудиоинтерфейса).

import { applyOutput, audioInfo, canChooseOutput, restartAudio } from '../audio/engine';
import { BUFFER_SIZES, SAMPLE_RATES, saveSettings, settings } from '../settings';
import { h, setText } from './dom';
import { setTheme } from './theme';
import { backHeader, makePopup, openMenuPanel, popupButton, type Popup } from './popup';
import { openMidi } from './midi';
import { openProjectMenu } from './projects';

type Tab = 'engine' | 'background' | 'output';

let main: Popup;
let panel: Popup;
let body: HTMLElement;
let tab: Tab = 'engine';
const tabBtns: Record<Tab, HTMLButtonElement> = {} as Record<Tab, HTMLButtonElement>;
let anchorEl: Element;
let infoTimer = 0;

/** Тап по бутерброду: PROJECTS или SETTINGS. */
export function openMainMenu(anchor: Element) {
  anchorEl = anchor;
  if (!main) {
    main = makePopup('main-menu');
    const back = () => openMainMenu(anchorEl);
    main.box.append(
      popupButton('PROJECTS', () => { main.close(); openProjectMenu(anchorEl, back); }),
      popupButton('SETTINGS', () => { main.close(); openSettings(anchorEl); }),
      popupButton('MIDI', () => { main.close(); openMidi(anchorEl, back); }),
    );
  }
  openMenuPanel(main, anchor);
}

function buildPanel() {
  panel = makePopup('settings');
  const tabs = h('div', 'settings-tabs');
  const names: [Tab, string][] = [['engine', 'AUDIO ENGINE'], ['background', 'BACKGROUND'], ['output', 'OUTPUT']];
  for (const [t, label] of names) {
    tabBtns[t] = popupButton(label, () => { tab = t; render(); });
    tabs.append(tabBtns[t]);
  }
  body = h('div', 'settings-body');
  // Оформление — над вкладками: как в системе, светлое, тёмное.
  appearance = h('div', 'settings-choice');
  panel.box.append(
    backHeader(h('div', 'project-title', 'Settings'), () => { panel.close(); openMainMenu(anchorEl); }),
    h('div', 'source-title', 'APPEARANCE'), appearance, tabs, body,
  );
}

export function openSettings(anchor: Element) {
  if (!panel) buildPanel();
  render();
  openMenuPanel(panel, anchor);
  clearInterval(infoTimer);
  // Фактические параметры звука обновляются, пока окно открыто.
  infoTimer = window.setInterval(() => {
    if (!panel.isOpen()) { clearInterval(infoTimer); return; }
    const el = body.querySelector('.settings-info');
    if (el) setText(el as HTMLElement, engineInfo());
  }, 500);
}

/** Ряд кнопок выбора одного значения. */
function choice<T>(label: string, values: T[], current: T, name: (v: T) => string, pick: (v: T) => void): HTMLElement {
  const row = h('div', 'settings-row');
  const btns = h('div', 'settings-choice');
  for (const v of values) {
    const b = popupButton(name(v), () => { pick(v); render(); });
    b.classList.toggle('current', v === current);
    btns.append(b);
  }
  row.append(h('div', 'source-title', label), btns);
  return row;
}

const note = (text: string) => h('div', 'settings-note', text);

function engineInfo(): string {
  const a = audioInfo();
  if (a.state === 'none') return 'Audio not started yet — tap the screen.';
  const ms = (s: number) => `${(s * 1000).toFixed(1)} ms`;
  return `Now: ${a.sampleRate} Hz · ${a.state} · base latency ${ms(a.baseLatency)} · output latency ${ms(a.outputLatency)}`;
}

function renderEngine() {
  const restart = () => { void restartAudio(); };
  body.append(
    choice('SAMPLE RATE', SAMPLE_RATES, settings.sampleRate, (v) => (v ? `${v / 1000} kHz` : 'AUTO'), (v) => {
      saveSettings({ sampleRate: v });
      restart();
    }),
    choice('BUFFER SIZE', BUFFER_SIZES, settings.bufferSize, (v) => (v ? String(v) : 'AUTO'), (v) => {
      saveSettings({ bufferSize: v });
      restart();
    }),
    note('Changing these restarts the audio engine. Safari may round the buffer size to what the device supports; the actual latency is shown below.'),
    h('div', 'settings-info', engineInfo()),
    choice('MUTE TAILS', [false, true], settings.muteTails, (v) => (v ? 'ON' : 'OFF'), (v) => saveSettings({ muteTails: v })),
    note('OFF: muting a track cuts its sound and sends at once; Reverb and Delay tails ring out (as in Ableton). ON: if the muted track is the only one sending to Delay, the Delay repeats are cut too.'),
  );
}

function renderBackground() {
  const b = popupButton(`BACKGROUND AUDIO: ${settings.background ? 'ON' : 'OFF'}`, () => {
    saveSettings({ background: !settings.background });
    render();
  });
  b.classList.toggle('current', settings.background);
  body.append(
    b,
    note(settings.background
      ? 'Audio keeps playing when Safari is in the background or the screen is locked.'
      : 'Audio stops when Safari goes to the background and resumes when you come back.'),
  );
}

async function devices(kind: MediaDeviceKind): Promise<MediaDeviceInfo[]> {
  try {
    return (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === kind);
  } catch { return []; }
}

function deviceList(label: string, kind: MediaDeviceKind, current: string, enabled: boolean, pick: (id: string) => void): HTMLElement {
  const row = h('div', 'settings-row');
  const list = h('div', 'settings-devices');
  row.append(h('div', 'source-title', label), list);
  void devices(kind).then((ds) => {
    const items: { id: string; name: string }[] = [{ id: '', name: 'Default' }];
    ds.forEach((d, i) => { if (d.deviceId !== 'default') items.push({ id: d.deviceId, name: d.label || `${kind === 'audiooutput' ? 'Output' : 'Input'} ${i + 1}` }); });
    for (const it of items) {
      const b = popupButton(it.name, () => { pick(it.id); render(); });
      b.disabled = !enabled;
      b.classList.toggle('current', it.id === current);
      list.append(b);
    }
  });
  return row;
}

function renderOutput() {
  const out = canChooseOutput();
  body.append(
    deviceList('OUTPUT', 'audiooutput', settings.outputId, out, (id) => { saveSettings({ outputId: id }); void applyOutput(); }),
    note(out ? 'Sound goes to the chosen output.' : 'This browser plays through the system output: on iPad choose the audio interface in Control Center (AirPlay icon).'),
    deviceList('INPUT', 'audioinput', settings.inputId, true, (id) => saveSettings({ inputId: id })),
    note('Device names appear after access is allowed. The input is not used by the app yet (no recording).'),
    popupButton('ALLOW ACCESS', () => {
      void navigator.mediaDevices?.getUserMedia({ audio: true })
        .then((s) => { s.getTracks().forEach((t) => t.stop()); render(); })
        .catch(() => window.alert('Access was not allowed'));
    }),
  );
}

let appearance: HTMLElement;

function render() {
  appearance.replaceChildren(...(['system', 'light', 'dark'] as const).map((t) => {
    const b = popupButton(t === 'system' ? 'SYSTEM' : t.toUpperCase(), () => { setTheme(t); render(); });
    b.classList.toggle('current', settings.theme === t);
    return b;
  }));
  for (const t of Object.keys(tabBtns) as Tab[]) tabBtns[t].classList.toggle('current', t === tab);
  body.replaceChildren();
  if (tab === 'engine') renderEngine();
  else if (tab === 'background') renderBackground();
  else renderOutput();
}
