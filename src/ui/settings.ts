// Меню «бутерброд»: PROJECTS (проекты, ui/projects.ts), SETTINGS и MIDI (ui/midi.ts);
// во вложенных меню стрелка назад возвращает сюда.
// SETTINGS — разделы списком (прокрутка): AUDIO ENGINE (частота дискретизации, размер буфера), RECORD (квантизация, овердаб, запись автоматизации), SAMPLER (ноты маркеров нарезки), BACKGROUND (звук в фоне)
// OUTPUT (выход и вход аудиоинтерфейса), SIDECHAIN (приглушение посылов эффектов, на пробу) и SCALE (шкала окон мастера).

import { applyOutput, applySidechainSends, audioInfo, canChooseOutput, restartAudio } from '../audio/engine';
import { BUFFER_SIZES, SAMPLE_RATES, saveSettings, settings } from '../settings';
import { h, setText } from './dom';
import { setTheme } from './theme';
import { backHeader, makePopup, openMenuPanel, popupButton, toggleRow, type Popup } from './popup';
import { openMidi } from './midi';
import { openSync } from './sync';
import { openProjectMenu } from './projects';


let main: Popup;
let panel: Popup;
let body: HTMLElement;
let anchorEl: Element;
let infoTimer = 0;

/** Тап по бутерброду: PROJECTS или SETTINGS. */
export function openMainMenu(anchor: Element) {
  anchorEl = anchor;
  if (!main) {
    main = makePopup('main-menu');
    const back = () => openMainMenu(anchorEl);
    // Пункты разделены: у каждого свой подзаголовок и отступ сверху.
    const section = (title: string, btn: HTMLElement) => {
      const el = h('div', 'main-menu-section');
      el.append(h('div', 'menu-head', title), btn);
      return el;
    };
    main.box.append(
      section('PROJECT', popupButton('PROJECTS', () => { main.close(); openProjectMenu(anchorEl, back); })),
      section('APP', popupButton('SETTINGS', () => { main.close(); openSettings(anchorEl); })),
      section('CONTROLLERS', popupButton('MIDI', () => { main.close(); openMidi(anchorEl, back); })),
      section('SYNC', popupButton('SYNC', () => { main.close(); openSync(anchorEl, back); })),
    );
  }
  openMenuPanel(main, anchor);
}

function buildPanel() {
  panel = makePopup('settings');
  body = h('div', 'settings-body');
  // Оформление — первым; дальше разделы списком (прокрутка пальцем), без вкладок.
  appearance = h('div', 'settings-choice');
  panel.box.append(
    backHeader(h('div', 'project-title', 'Settings'), () => { panel.close(); openMainMenu(anchorEl); }),
    h('div', 'source-title', 'APPEARANCE'), appearance, body,
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
  // Запрошена одна частота, а браузер дал другую — дописывается запрошенная.
  const req = settings.sampleRate && settings.sampleRate !== a.sampleRate ? ` (${settings.sampleRate / 1000} kHz requested)` : '';
  return `Now: ${a.sampleRate} Hz${req} · ${a.state} · base latency ${ms(a.baseLatency)} · output latency ${ms(a.outputLatency)}`;
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
    toggleRow('MUTE TAILS', settings.muteTails, (v) => saveSettings({ muteTails: v })),
    note('OFF: muting a track cuts its sound and sends at once; Reverb and Delay tails ring out. ON: if the muted track is the only one sending to Delay, the Delay repeats are cut too.'),
  );
}

/** SIDECHAIN (на пробу): приглушать ли вход посылов Reverb, Delay, Drive тем же sidechain, что и выход дорожки. */
function renderSidechain() {
  const row = (label: string, key: 'rev' | 'dly' | 'drv') => toggleRow(label, settings.scSends[key], (v) => {
    saveSettings({ scSends: { ...settings.scSends, [key]: v } });
    applySidechainSends();
  });
  body.append(
    h('div', 'source-title', 'SIDECHAIN SENDS'),
    row('REVERB', 'rev'),
    row('DELAY', 'dly'),
    row('DRIVE', 'drv'),
    note('ON: the send level of the effect ducks with the sidechain. Effect tails keep playing. OFF: the send is not ducked.'),
  );
}

/** RECORD: квантизация записи нот, овердаб, запись автоматизации (при REC). */
function renderRecord() {
  const set = (patch: Partial<typeof settings.record>) => saveSettings({ record: { ...settings.record, ...patch } });
  body.append(
    toggleRow('QUANTIZE', settings.record.quantize, (v) => set({ quantize: v })),
    note('ON: a note played with REC lands on the nearest step. OFF: on the step where it was played.'),
    toggleRow('OVERDUB', settings.record.overdub, (v) => set({ overdub: v })),
    note('ON: new notes are added to the pattern. OFF: steps the recording passes over are cleared, only the new notes stay.'),
    toggleRow('AUTOMATION RECORDING', settings.record.autoRec, (v) => set({ autoRec: v })),
    note('ON: with REC and PLAY, turning a track knob records automation. OFF: only notes are recorded.'),
  );
}

/** SAMPLER: ноты маркеров нарезки в редакторе сэмпла — по хроматической клавиатуре или по гамме. */
function renderSampler() {
  body.append(
    choice('SLICE NOTES', ['chromatic', 'scale'] as const, settings.sliceMap, (v) => v.toUpperCase(), (v) => saveSettings({ sliceMap: v })),
    note('Markers in the sample editor play their slice from a piano key. CHROMATIC: markers go up by semitone from C3 (C3, C#3, D3…). SCALE: markers follow the notes of the selected scale from its root note in octave 3; the marker notes change with the scale.'),
  );
}

/** SCALE окон модулей мастера (компрессор, клиппер, лимитер, сатуратор): низ шкалы дисплеев и стержней IN/OUT. */
function renderScale() {
  body.append(
    choice('MASTER WINDOWS SCALE', [48, 32, 16] as const, settings.limScale, (v) => `${v} dB`, (v) => saveSettings({ limScale: v })),
    note('Range of the level displays and IN / OUT bars in the compressor, clipper and limiter windows (bottom of the scale, top is 0 dBFS), the saturator WAVE (−SCALE in the middle) and its SPECTRUM (down to −2 × SCALE).'),
  );
}

function renderBackground() {
  const b = toggleRow('BACKGROUND AUDIO', settings.background, (v) => saveSettings({ background: v }), render);
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
  body.replaceChildren();
  // Разделы списком: заголовок раздела и черта между разделами.
  const sections: [string, () => void][] = [
    ['AUDIO ENGINE', renderEngine], ['RECORD', renderRecord], ['SAMPLER', renderSampler], ['BACKGROUND', renderBackground],
    ['OUTPUT', renderOutput], ['SIDECHAIN', renderSidechain], ['SCALE', renderScale],
  ];
  for (const [title, fn] of sections) {
    body.append(h('div', 'menu-head settings-head', title));
    fn();
  }
}
