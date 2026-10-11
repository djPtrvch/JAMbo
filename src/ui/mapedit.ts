// Окно настройки MIDI-маппинга: двойной тап по ручке или кнопке в режиме MIDI LEARN
// (или тап по строке в списке маппингов меню MIDI).
// TYPE (CC / NOTE), CHANNEL, NUMBER — источник (меняются вертикальным движением; движение
// контроллера, пока окно открыто, задаёт их сразу); CONTROL TYPE — MOMENTARY, TOGGLE (кнопки),
// ABSOLUTE, RELATIVE (ручки; у RELATIVE — кодировка энкодера); RANGE — диапазон ручки
// (тап открывает график: концы линии тянут вверх-вниз, INVERT переворачивает); FEEDBACK PORT —
// куда слать значение для колец и подсветки контроллера.

import {
  clearTarget, draftMapping, learn, mappingFor, midiOutputs, onLearnChanged, sameTarget, sourceLabel, targetLabel,
  updateMapping,
} from '../midi';
import { settings, type ControlType, type MidiMapping, type MidiSource, type MidiTarget, type RelEnc } from '../settings';
import { dragField } from './controls';
import { h, setAttr, setClass, setText, svg } from './dom';
import { backHeader, makePopup, popupButton, type Popup } from './popup';

let panel: Popup;
let target: MidiTarget | null = null;
/** Маппинг цели или черновик (пока цель не назначена). */
let cur: MidiMapping;
/** Источник, который сейчас тянут (применяется, когда палец отпущен: иначе по дороге «отберёт» чужие). */
let src: MidiSource | null = null;
let onBack: (() => void) | null = null;

let header: HTMLElement;
let status: HTMLElement;
let controlRow: HTMLElement;
let encSection: HTMLElement;
let encRow: HTMLElement;
let rangeSection: HTMLElement;
let rangeField: HTMLElement;
let curve: HTMLElement;
let curveLine: SVGLineElement;
let curveDots: SVGCircleElement[];
let portList: HTMLElement;
let curveOpen = false;

const CONTROLS: [ControlType, string][] = [['momentary', 'MOMENTARY'], ['toggle', 'TOGGLE'], ['abs', 'ABSOLUTE'], ['rel', 'RELATIVE']];
const ENCS: [RelEnc, string, string][] = [
  ['offset', 'OFFSET 64', '65 = up, 63 = down (Twister ENC 3FH/41H)'],
  ['twos', '2’S COMP', '1 = up, 127 = down'],
  ['signed', 'SIGNED BIT', '1 = up, 65 = down'],
];

const shownSrc = () => src ?? cur.src;
const pct = (n: number) => `${Math.round(n * 100)}%`;

function setSrc(patch: Partial<MidiSource>) {
  src = { ...shownSrc(), ...patch };
}

/** Отпустили поле TYPE/CHANNEL/NUMBER — источник записывается. */
function commitSrc() {
  if (!target || !src) return;
  const s = src;
  src = null;
  updateMapping(target, { src: s });
}

function patch(p: Partial<MidiMapping>) {
  if (target) updateMapping(target, p);
}

function srcField(label: string, get: () => number, set: (v: number) => void, show: () => string, onTap?: () => void) {
  const f = dragField(label, get, set, show, 12, onTap);
  f.classList.add('eq-field', 'map-field');
  f.addEventListener('pointerup', commitSrc);
  f.addEventListener('pointercancel', commitSrc);
  return f;
}

function build() {
  panel = makePopup('settings midi-edit');
  header = h('div', 'menu-header');
  status = h('div', 'settings-note');
  const fields = h('div', 'map-fields');
  fields.append(
    srcField('TYPE', () => (shownSrc().type === 'cc' ? 0 : 1), (v) => setSrc({ type: v % 2 ? 'note' : 'cc' }),
      () => (target ? (shownSrc().type === 'cc' ? 'CC' : 'NOTE') : ''),
      () => { setSrc({ type: shownSrc().type === 'cc' ? 'note' : 'cc' }); commitSrc(); }),
    srcField('CHANNEL', () => shownSrc().ch, (v) => setSrc({ ch: Math.min(15, Math.max(0, v)) }), () => (target ? String(shownSrc().ch + 1) : '')),
    srcField('NUMBER', () => shownSrc().num, (v) => setSrc({ num: Math.min(127, Math.max(0, v)) }), () => (target ? String(shownSrc().num) : '')),
  );
  controlRow = h('div', 'settings-choice map-controls');
  encRow = h('div', 'settings-choice');
  encSection = h('div', 'settings-row');
  encSection.append(h('div', 'source-title', 'ENCODER'), encRow, h('div', 'settings-note map-enc-note'));

  // Диапазон: поле (тап — график) и сам график.
  rangeField = h('div', 'field eq-field map-field map-range');
  rangeField.append(h('div', 'field-label', 'RANGE'), h('div', 'field-value'));
  rangeField.addEventListener('pointerup', () => { curveOpen = !curveOpen; render(); place(); });
  curve = h('div', 'map-curve');
  const box = svg('svg', { viewBox: '0 0 240 130', class: 'map-curve-svg' });
  box.append(
    svg('rect', { x: 20, y: 10, width: 200, height: 100, class: 'map-curve-frame' }),
    svg('text', { x: 20, y: 126, class: 'map-curve-text' }), svg('text', { x: 220, y: 126, class: 'map-curve-text end' }),
  );
  (box.children[1] as SVGTextElement).textContent = '0';
  (box.children[2] as SVGTextElement).textContent = '127';
  curveLine = svg('line', { class: 'map-curve-line' });
  curveDots = [svg('circle', { r: 7, class: 'map-curve-dot' }), svg('circle', { r: 7, class: 'map-curve-dot' })];
  box.append(curveLine, ...curveDots);
  // Конец линии ближе к пальцу (по горизонтали) тянется вертикально: левый — MIN, правый — MAX.
  let end: 'min' | 'max' | null = null;
  const at = (e: PointerEvent) => {
    const r = box.getBoundingClientRect();
    return { x: (e.clientX - r.left) / r.width * 240, y: (e.clientY - r.top) / r.height * 130 };
  };
  const drag = (e: PointerEvent) => {
    if (!end) return;
    const n = Math.round(Math.min(1, Math.max(0, (110 - at(e).y) / 100)) * 100) / 100;
    patch({ [end]: n });
  };
  box.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    box.setPointerCapture(e.pointerId);
    end = at(e).x < 120 ? 'min' : 'max';
    drag(e);
  });
  box.addEventListener('pointermove', drag);
  box.addEventListener('pointerup', () => { end = null; });
  box.addEventListener('pointercancel', () => { end = null; });
  const curveBtns = h('div', 'settings-choice');
  curveBtns.append(
    popupButton('INVERT', () => patch({ min: cur.max, max: cur.min })),
    popupButton('RESET', () => patch({ min: 0, max: 1 })),
  );
  curve.append(box, curveBtns);
  rangeSection = h('div', 'settings-row');
  rangeSection.append(rangeField, curve);

  portList = h('div', 'settings-devices');
  const del = popupButton('DELETE MAPPING', () => { if (target) clearTarget(target); });
  del.classList.add('map-delete');
  // Две колонки: слева источник и тип управления, справа диапазон, порт и удаление.
  const left = h('div', 'map-col');
  left.append(status, fields, h('div', 'source-title', 'CONTROL TYPE'), controlRow, encSection);
  const right = h('div', 'map-col');
  right.append(rangeSection, h('div', 'source-title', 'FEEDBACK PORT'), portList, del);
  const cols = h('div', 'map-cols');
  cols.append(left, right);
  panel.box.append(header, cols);
  panel.onClose = () => {
    learn.edit = false;
    if (!learn.on) learn.target = null;
    target = null;
    curveOpen = false;
  };
  onLearnChanged(() => { if (panel.isOpen()) render(); });
}

function choice<T>(row: HTMLElement, items: [T, string][], current: T, pick: (v: T) => void) {
  row.replaceChildren(...items.map(([v, name]) => {
    const b = popupButton(name, () => pick(v));
    b.classList.toggle('current', v === current);
    return b;
  }));
}

function render() {
  if (!target) return;
  const t = target;
  const mapped = mappingFor(t);
  // Черновик держим, пока цель не назначена (номер не прыгает при каждой отрисовке).
  if (mapped) cur = mapped;
  else if (!cur || !sameTarget(cur.target, t)) cur = draftMapping(t);
  const knob = t.kind === 'knob';

  const title = h('div', 'project-title', targetLabel(t));
  header.replaceChildren(...(onBack ? backHeader(title, () => { panel.close(); onBack?.(); }).children : [title]));

  // Чужой маппинг с тем же источником перейдёт сюда.
  const s = shownSrc();
  const other = settings.mappings.find((m) => !sameTarget(m.target, t) && m.src.type === s.type && m.src.ch === s.ch && m.src.num === s.num);
  setText(status, [
    mapped ? '' : 'Not mapped yet.',
    'Move a control on your MIDI device to set TYPE, CHANNEL and NUMBER, or drag them.',
    other ? `${sourceLabel(s)} is used by ${targetLabel(other.target)} — it moves here.` : '',
  ].filter(Boolean).join(' '));

  // Кнопкам — только кнопочные типы; ручкам — все.
  choice(controlRow, knob ? CONTROLS : CONTROLS.slice(0, 2), cur.control, (c) => patch({ control: c }));
  setClass(encSection, 'hidden', !knob || cur.control !== 'rel');
  choice(encRow, ENCS.map(([e, n]) => [e, n] as [RelEnc, string]), cur.enc, (e) => patch({ enc: e }));
  setText(encSection.querySelector('.map-enc-note') as HTMLElement, ENCS.find(([e]) => e === cur.enc)![2]);

  setClass(rangeSection, 'hidden', !knob);
  setText(rangeField.querySelector('.field-value') as HTMLElement, `${pct(cur.min)} – ${pct(cur.max)}${cur.min > cur.max ? '  INVERTED' : ''}`);
  setClass(curve, 'hidden', !curveOpen);
  const y = (n: number) => 110 - n * 100;
  setAttr(curveLine, 'x1', 20); setAttr(curveLine, 'y1', y(cur.min));
  setAttr(curveLine, 'x2', 220); setAttr(curveLine, 'y2', y(cur.max));
  setAttr(curveDots[0], 'cx', 20); setAttr(curveDots[0], 'cy', y(cur.min));
  setAttr(curveDots[1], 'cx', 220); setAttr(curveDots[1], 'cy', y(cur.max));

  const outs = midiOutputs();
  const def = outs.find((o) => o.id === settings.midiFeedback)?.name ?? 'none';
  const ports: { id: string; name: string }[] = [{ id: '', name: `DEFAULT (${def})` }, { id: 'none', name: 'NONE' }, ...outs];
  portList.replaceChildren(...ports.map((p) => {
    const b = popupButton(p.name, () => patch({ port: p.id }));
    b.classList.toggle('current', p.id === cur.port);
    return b;
  }));
}

/** Открыть окно настройки маппинга цели t; back — стрелка назад (из меню MIDI). */
export function openMapEditor(t: MidiTarget, back: (() => void) | null = null) {
  if (!panel) build();
  target = t;
  src = null;
  onBack = back;
  learn.edit = true;
  learn.target = t;
  render();
  place();
}

const WIDTH = 680;
/** Над полосой LEARN, по центру экрана (не уходит за край). */
function place() {
  const W = window.innerWidth;
  panel.openRect({ left: Math.max(8, (W - WIDTH) / 2), top: 8, width: Math.min(WIDTH, W - 16), height: 0 });
  panel.box.style.height = '';
  const bh = panel.box.offsetHeight;
  panel.box.style.top = `${Math.max(8, (window.innerHeight - 64 - bh) / 2)}px`;
}
