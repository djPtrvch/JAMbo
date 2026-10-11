// Окно MIDI MAP (как в Drambo): плавающее, перетаскивается за заголовок, не закрывает экран.
// Открывается двойным тапом по ручке или кнопке в режиме MIDI LEARN (тап по другой цели, пока окно
// открыто, переключает окно на неё) или тапом по строке в списке маппингов меню MIDI.
// Строки: Number (ввод числом), Channel (1–16), Event type (CC / Note), Control type, Encoder (у Continuous
// relative), Range (график: концы тянут вверх-вниз, Invert); ниже блок портов: Input port и Feedback port.
// Строка с «›» открывает выбор на месте списка (стрелка назад — обратно). Движение контроллера,
// пока окно открыто, задаёт Number, Channel, Event type и Input port сразу.
// Unmap снимает маппинг, ✕ закрывает окно.

import {
  deleteMidiPreset, loadMidiPreset, midiPresets, presetModified, renameMidiPreset, saveMidiPreset, TWISTER_NAME,
  condKey, pinned,
  clashFor, clearTarget, draftMapping, learn, mappingFor, midiDevices, midiOutputs, onLearnChanged, sameTarget,
  targetLabel, updateMapping,
} from '../midi';
import { settings, type ControlType, type MidiMapping, type MidiTarget, type RelEnc } from '../settings';
import { ui } from '../state';
import { h, setAttr, svg } from './dom';
import { openInput } from './popup';

type Page = 'main' | 'port' | 'event' | 'control' | 'encoder' | 'channel' | 'range' | 'feedback' | 'cond' | 'preset';

let win: HTMLElement;
let head: HTMLElement;
let titleEl: HTMLElement;
let leftBtn: HTMLElement;
let body: HTMLElement;
let page: Page = 'main';
let target: MidiTarget | null = null;
/** Маппинг цели или черновик (пока цель не назначена). */
let cur: MidiMapping;
let onBack: (() => void) | null = null;
/** Положение окна (запоминается, пока страница открыта). */
let pos: { x: number; y: number } | null = null;
/** Набираемый номер (Number), пока поле в фокусе. */
let typing: string | null = null;

const CONTROLS: [ControlType, string][] = [
  ['momentary', 'Button momentary'], ['toggle', 'Button toggle'], ['abs', 'Continuous absolute'], ['rel', 'Continuous relative'],
];
const ENCS: [RelEnc, string, string][] = [
  ['offset', 'Offset 64', '65 up · 63 down'],
  ['twos', '2’s complement', '1 up · 127 down'],
  ['signed', 'Signed bit', '1 up · 65 down'],
];
const TITLES: Record<Page, string> = {
  main: 'MIDI map', port: 'Input port', event: 'Event type', control: 'Control type', encoder: 'Encoder',
  channel: 'Channel', range: 'Range', feedback: 'Feedback port', cond: 'Condition', preset: 'Preset',
};

/** Подпись условия: Global, Current track (T3), Clip launcher. */
const condName = (m: MidiMapping) => (m.cond === 'track' ? `Current track (T${m.track + 1})` : m.cond === 'clip' ? 'Clip launcher' : 'Global');

const pct = (n: number) => Math.round(n * 100);
const inputs = () => midiDevices().filter((d) => d.dir === 'in');

function patch(p: Partial<MidiMapping>) {
  if (target) updateMapping(target, p);
}

function build() {
  win = h('div', 'mm hidden');
  head = h('div', 'mm-head');
  leftBtn = h('div', 'mm-head-btn');
  titleEl = h('div', 'mm-title');
  const close = h('div', 'mm-head-btn mm-close', '✕');
  head.append(leftBtn, titleEl, close);
  body = h('div', 'mm-body');
  win.append(head, body);
  document.body.append(win);

  leftBtn.addEventListener('pointerup', () => {
    if (page !== 'main') { page = 'main'; render(); return; }
    if (target && mappingFor(target)) { clearTarget(target); closeMapEditor(); }
  });
  close.addEventListener('pointerup', closeMapEditor);

  // Перетаскивание за заголовок (кроме кнопок).
  let drag: { id: number; dx: number; dy: number } | null = null;
  head.addEventListener('pointerdown', (e) => {
    if ((e.target as Element).closest('.mm-head-btn')) return;
    e.preventDefault();
    head.setPointerCapture(e.pointerId);
    const r = win.getBoundingClientRect();
    drag = { id: e.pointerId, dx: e.clientX - r.left, dy: e.clientY - r.top };
  });
  head.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    pos = { x: e.clientX - drag.dx, y: e.clientY - drag.dy };
    place();
  });
  const end = () => { drag = null; };
  head.addEventListener('pointerup', end);
  head.addEventListener('pointercancel', end);

  onLearnChanged(() => { if (isOpen() && typing === null) render(); });
}

/** Окно в пределах экрана; без перетаскивания — по центру над полосой LEARN. */
function place() {
  const W = window.innerWidth;
  const H = window.innerHeight;
  const w = win.offsetWidth;
  const hh = win.offsetHeight;
  const p = pos ?? { x: (W - w) / 2, y: Math.max(8, (H - 64 - hh) / 2) };
  win.style.left = `${Math.min(W - w - 8, Math.max(8, p.x))}px`;
  win.style.top = `${Math.min(H - 52, Math.max(8, p.y))}px`;
}

/** Строка списка: подпись, значение и «›» (тап — страница выбора). */
function row(label: string, value: string, go?: Page): HTMLElement {
  const el = h('div', 'mm-row');
  el.append(h('div', 'mm-label', label), h('div', 'mm-value', value));
  if (go) {
    el.append(h('div', 'mm-chev', '›'));
    el.addEventListener('pointerup', () => { page = go; render(); });
  }
  return el;
}

/** Страница выбора: строки с галочкой у текущего (или сетка cols столбцов). */
function options<T>(items: [T, string, string?][], current: T, pick: (v: T) => void, cols = 1): HTMLElement {
  const list = h('div', cols > 1 ? 'mm-grid' : 'mm-list');
  list.style.setProperty('--cols', String(cols));
  for (const [v, name, hint] of items) {
    const el = h('div', `mm-row mm-opt${v === current ? ' current' : ''}`);
    el.append(h('div', 'mm-label', name));
    if (hint) el.append(h('div', 'mm-value', hint));
    if (cols === 1) el.append(h('div', 'mm-check', v === current ? '✓' : ''));
    el.addEventListener('pointerup', () => { pick(v); page = 'main'; render(); });
    list.append(el);
  }
  return list;
}

/** Number: поле ввода числом (0–127); Enter или уход из поля — записать, × — очистить. */
function numberRow(): HTMLElement {
  const el = h('div', 'mm-row');
  const input = h('input', 'mm-number');
  input.type = 'text';
  input.inputMode = 'numeric';
  input.value = typing ?? String(cur.src.num);
  const clear = h('div', 'mm-clear', '×');
  const warn = h('div', 'mm-warn');
  // Номер, занятый другой целью, перейдёт сюда — предупреждаем заранее.
  const check = () => {
    const n = Number(input.value);
    const c = input.value !== '' && n <= 127 ? clashFor({ ...cur, src: { ...cur.src, num: n } }) : undefined;
    warn.textContent = c ? `used by ${targetLabel(c.target)}` : '';
  };
  const commit = () => {
    const n = Number(input.value);
    typing = null;
    if (input.value !== '' && n <= 127 && n !== cur.src.num) patch({ src: { ...cur.src, num: n } });
    else render();
  };
  input.addEventListener('input', () => { input.value = input.value.replace(/\D/g, '').slice(0, 3); typing = input.value; check(); });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') input.blur(); });
  input.addEventListener('blur', commit);
  clear.addEventListener('pointerdown', (e) => { e.preventDefault(); input.value = ''; typing = ''; input.focus(); check(); });
  el.append(h('div', 'mm-label', 'Number'), input, warn, clear);
  check();
  return el;
}

/** Range: график (вход 0–127 → значение), концы тянут вверх-вниз; Invert и Reset. */
function rangePage(): HTMLElement {
  const wrap = h('div', 'mm-range');
  const box = svg('svg', { viewBox: '0 0 240 130', class: 'mm-curve' });
  const y = (n: number) => 110 - n * 100;
  box.append(svg('rect', { x: 20, y: 10, width: 200, height: 100, class: 'map-curve-frame' }));
  const t0 = svg('text', { x: 20, y: 126, class: 'map-curve-text' });
  t0.textContent = '0';
  const t1 = svg('text', { x: 220, y: 126, class: 'map-curve-text end' });
  t1.textContent = '127';
  const line = svg('line', { x1: 20, x2: 220, class: 'map-curve-line' });
  const dots = [svg('circle', { cx: 20, r: 7, class: 'map-curve-dot' }), svg('circle', { cx: 220, r: 7, class: 'map-curve-dot' })];
  box.append(t0, t1, line, ...dots);
  const vals = h('div', 'mm-range-vals');
  const show = () => {
    setAttr(line, 'y1', y(cur.min)); setAttr(line, 'y2', y(cur.max));
    setAttr(dots[0], 'cy', y(cur.min)); setAttr(dots[1], 'cy', y(cur.max));
    vals.textContent = `Min ${pct(cur.min)}% · Max ${pct(cur.max)}%${cur.min > cur.max ? ' · inverted' : ''}`;
  };
  // Конец ближе к пальцу по горизонтали: левый — Min, правый — Max.
  let end: 'min' | 'max' | null = null;
  const at = (e: PointerEvent) => {
    const r = box.getBoundingClientRect();
    return { x: ((e.clientX - r.left) / r.width) * 240, y: ((e.clientY - r.top) / r.height) * 130 };
  };
  const move = (e: PointerEvent) => {
    if (!end || !target) return;
    const n = Math.round(Math.min(1, Math.max(0, (110 - at(e).y) / 100)) * 100) / 100;
    updateMapping(target, { [end]: n });
    cur = mappingFor(target)!;
    show();
  };
  box.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    box.setPointerCapture(e.pointerId);
    end = at(e).x < 120 ? 'min' : 'max';
    move(e);
  });
  box.addEventListener('pointermove', move);
  box.addEventListener('pointerup', () => { end = null; });
  box.addEventListener('pointercancel', () => { end = null; });
  show();
  const btns = h('div', 'mm-btns');
  const invert = h('div', 'mm-btn', 'Invert');
  invert.addEventListener('pointerup', () => patch({ min: cur.max, max: cur.min }));
  const reset = h('div', 'mm-btn', 'Reset');
  reset.addEventListener('pointerup', () => patch({ min: 0, max: 1 }));
  btns.append(invert, reset);
  wrap.append(box, vals, btns);
  return wrap;
}

function render() {
  if (!target) return;
  const t = target;
  const mapped = mappingFor(t);
  // Черновик держим, пока цель не назначена (номер не прыгает при каждой отрисовке).
  if (mapped) cur = mapped;
  else if (!cur || !sameTarget(cur.target, t)) cur = draftMapping(t);
  const knob = t.kind === 'knob';

  titleEl.textContent = page === 'main' ? targetLabel(t) : TITLES[page];
  // Unmap всегда на месте; без маппинга — серая.
  leftBtn.textContent = page === 'main' ? 'Unmap' : '‹';
  leftBtn.classList.toggle('back', page !== 'main');
  leftBtn.classList.toggle('disabled', page === 'main' && !mapped);

  const ins = inputs();
  const outs = midiOutputs();
  const name = (list: { id: string; name: string }[], id: string) => list.find((d) => d.id === id)?.name ?? 'Not connected';
  const defOut = settings.midiFeedback ? name(outs, settings.midiFeedback) : 'None';

  if (page === 'main') {
    const ctl = CONTROLS.find(([c]) => c === cur.control)![1];
    const fb = cur.port === 'none' ? 'None' : cur.port ? name(outs, cur.port) : `Default (${defOut})`;
    const section = h('div', 'mm-list');
    // Порядок: номер, канал, тип сообщения, тип управления (и кодировка энкодера), диапазон;
    // ниже отдельно — порты: вход и обратная связь.
    section.append(
      numberRow(),
      row('Channel', String(cur.src.ch + 1), 'channel'),
      row('Event type', cur.src.type === 'cc' ? 'CC' : 'Note', 'event'),
      row('Control type', ctl, 'control'),
      ...(knob && cur.control === 'rel' ? [row('Encoder', ENCS.find(([e]) => e === cur.enc)![1], 'encoder')] : []),
      ...(knob ? [row('Range', `${pct(cur.min)} – ${pct(cur.max)} %`, 'range')] : []),
      row('Condition', condName(cur), 'cond'),
    );
    const fbSection = h('div', 'mm-list');
    fbSection.append(row('Input port', cur.input ? name(ins, cur.input) : 'Any', 'port'), row('Feedback port', fb, 'feedback'));
    const status = h('div', 'mm-note', mapped
      ? 'Move a control to remap.'
      : 'Not mapped yet — move a control on your MIDI device or set the fields.');
    // В самом верху — пресет маппингов (набор под контроллер), «*» — изменён после загрузки.
    const presetSection = h('div', 'mm-list');
    presetSection.append(row('Preset', settings.midiPreset ? `${settings.midiPreset}${presetModified() ? ' *' : ''}` : 'None', 'preset'));
    body.replaceChildren(presetSection, status, section, fbSection);
  } else if (page === 'port') {
    body.replaceChildren(options<string>([['', 'Any'], ...ins.map((d): [string, string] => [d.id, d.name])], cur.input, (v) => patch({ input: v })));
  } else if (page === 'preset') {
    // Тап — загрузить (маппинги пресета заменяют все нынешние); ниже — сохранить, переименовать, удалить.
    const list = options(midiPresets().map((p): [string, string, string] => [p.name, p.name, `${p.mappings.length}`]),
      settings.midiPreset, (v) => loadMidiPreset(v));
    const own = settings.midiPreset && settings.midiPreset !== TWISTER_NAME ? settings.midiPreset : '';
    const actions = h('div', 'mm-list');
    const act = (label: string, fn: () => void, off = false) => {
      const el = row(label, '');
      el.classList.add('mm-act');
      if (off) el.classList.add('disabled');
      else el.addEventListener('pointerup', fn);
      return el;
    };
    actions.append(
      act('Save current as new…', () => openInput(win, `Controller ${midiPresets().length}`, (n) => { saveMidiPreset(n); render(); })),
      act(own ? `Save to “${own}”` : 'Save to preset', () => { saveMidiPreset(own); render(); }, !own),
      act('Rename…', () => openInput(win, own, (n) => { renameMidiPreset(own, n); render(); }), !own),
      act('Delete', () => { deleteMidiPreset(own); render(); }, !own),
    );
    body.replaceChildren(list, h('div', 'mm-note', 'Loading a preset replaces all current mappings.'), actions);
  } else if (page === 'cond') {
    // Current track — дорожка, выбранная сейчас (у каждой дорожки свои маппинги).
    const tr = ui.channel === 'track' ? ui.selectedTrack : cur.track;
    const items: [string, string, string][] = [
      ['global', 'Global', 'all tracks and views'],
      [`track:${tr}`, `Current track (T${tr + 1})`, 'only while this track is selected'],
      ['clip', 'Clip launcher', 'only while PATTERNS is open'],
    ];
    body.replaceChildren(options(items, condKey(cur), (v) => patch(v.startsWith('track:')
      ? { cond: 'track', track: Number(v.slice(6)) } : { cond: v as MidiMapping['cond'] })));
  } else if (page === 'event') {
    body.replaceChildren(options<'cc' | 'note'>([['cc', 'CC'], ['note', 'Note']], cur.src.type, (v) => patch({ src: { ...cur.src, type: v } })));
  } else if (page === 'control') {
    body.replaceChildren(options(knob ? CONTROLS : CONTROLS.slice(0, 2), cur.control, (v) => patch({ control: v })));
  } else if (page === 'encoder') {
    body.replaceChildren(options(ENCS, cur.enc, (v) => patch({ enc: v })));
  } else if (page === 'channel') {
    body.replaceChildren(options(Array.from({ length: 16 }, (_, i): [number, string] => [i, String(i + 1)]), cur.src.ch, (v) => patch({ src: { ...cur.src, ch: v } }), 4));
  } else if (page === 'range') {
    body.replaceChildren(rangePage());
  } else {
    body.replaceChildren(options<string>([['', `Default (${defOut})`], ['none', 'None'], ...outs.map((d): [string, string] => [d.id, d.name])], cur.port, (v) => patch({ port: v })));
  }
  place();
}

export const isOpen = () => !!win && !win.classList.contains('hidden');

/** Открыть окно MIDI MAP для цели t; back — после закрытия вернуться в меню MIDI. */
export function openMapEditor(t: MidiTarget, back: (() => void) | null = null, cond: string | null = null) {
  if (!win) build();
  if (!target || !sameTarget(target, t)) page = 'main';
  target = t;
  // Окно правит маппинг условия cond (из списка) или того, что действует сейчас.
  pinned.target = t;
  pinned.cond = cond;
  const m = mappingFor(t);
  pinned.cond = m ? condKey(m) : cond;
  typing = null;
  onBack = back;
  learn.edit = true;
  learn.target = t;
  win.classList.remove('hidden');
  render();
}

export function closeMapEditor() {
  if (!isOpen()) return;
  win.classList.add('hidden');
  learn.edit = false;
  if (!learn.on) learn.target = null;
  target = null;
  pinned.target = null;
  pinned.cond = null;
  const back = onBack;
  onBack = null;
  back?.();
}
