// Сетка ручек 4×4: вертикальное управление пальцем, мультитач,
// p-lock (жёлтый), назначение LFO и анимированные белые кольца.

import { fromNorm, toNorm, type ParamDef } from '../params';
import {
  addTrack, audible, toggleArm, toggleMute, toggleSolo, assignFor, clearTrackLocks, canAddTrack, canDeleteTrack, copyTrack, deleteTrack, hasTrackClip, moveTrack, pasteTrack, curSeq, fxModNorm, liveLocks, seqIndex,
  beginGesture, clearLfoAssign, clearLock, doc, endGesture, firstHeldStep, gridFor, gridMode, heldLfo,
  lockValue, modulatedNorm, paramValue, type Mod, setLfoAmount, setLockNorm, setParamNorm, ui, type GridMode,
} from '../state';
import { markKnob, registerAction } from '../midi';
import { MAX_TRACKS, OVER_PEAK } from '../params';
import { trackDuckDb, trackIsStereo, trackLevel } from '../audio/engine';
import { levelFrac } from './meter';
import { openRename } from './tracks';
import { makePopup, popupButton, type Popup } from './popup';
import { DOUBLE_TAP_MS, h, setAttr, setClass, setText, svg } from './dom';

/** Сколько пикселей вертикального хода = полный оборот ручки. */
const TRAVEL_PX = 240;
/** Мёртвая зона, чтобы тап не сдвигал значение. */
const DEAD_PX = 4;

// Геометрия дуги: от −135° до +135°.
const START = -135;
const SWEEP = 270;
const R_VALUE = 36;
const R_LOCK = 28;
const R_LFO = 45;

function polar(r: number, deg: number) {
  const a = ((deg - 90) * Math.PI) / 180;
  return [50 + r * Math.cos(a), 50 + r * Math.sin(a)];
}

function arc(r: number, n0: number, n1: number): string {
  if (Math.abs(n1 - n0) < 0.002) return '';
  const a0 = START + SWEEP * Math.min(n0, n1);
  const a1 = START + SWEEP * Math.max(n0, n1);
  const [x0, y0] = polar(r, a0);
  const [x1, y1] = polar(r, a1);
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

interface KnobView {
  root: HTMLElement;
  label: HTMLElement;
  value: HTMLElement;
  valueArc: SVGPathElement;
  lfoArc: SVGPathElement;
  rangeArc: SVGPathElement;
  lockArc: SVGPathElement;
  pointer: SVGLineElement;
  meter: KnobMeter;
  /** MIX: справа от ручки громкости — M (mute), S (solo), ● (запись). */
  msr: HTMLElement;
  msrBtns: HTMLElement[];
}

/** Кнопки M, S, ● у ручки громкости дорожки slot (в MIX); с MIDI — MUTE n, SOLO n, ARM n. */
function buildMsr(slot: number): { msr: HTMLElement; msrBtns: HTMLElement[] } {
  const msr = h('div', 'knob-msr hidden');
  const defs: [string, string, string, () => void, () => boolean][] = [
    ['M', 'MUTE', 'msr-mute', () => toggleMute(slot), () => !!doc.tracks[slot]?.mute],
    ['S', 'SOLO', 'msr-solo', () => toggleSolo(slot), () => !!doc.tracks[slot]?.solo],
    ['', 'ARM', 'msr-arm', () => toggleArm(slot), () => !!doc.tracks[slot]?.arm],
  ];
  const msrBtns = defs.map(([text, name, cls, fn, state]) => {
    const b = h('div', `btn msr-btn ${cls}`, text);
    if (!text) b.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="6" fill="currentColor"/></svg>';
    // Своё касание: не крутит ручку и не открывает её меню.
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); fn(); });
    for (const ev of ['pointermove', 'pointerup', 'pointercancel']) b.addEventListener(ev, (e) => e.stopPropagation());
    registerAction(`${name}${slot + 1}`, { label: `${name} ${slot + 1}`, press: fn, state }, b);
    msr.append(b);
    return b;
  });
  return { msr, msrBtns };
}

/** MIX: метр дорожки слева от ручки громкости (после фейдера), в общем стиле метров. */
interface KnobMeter { root: HTMLElement; chans: HTMLElement[]; fills: HTMLElement[]; holds: HTMLElement[]; grs: HTMLElement[] }

function buildKnobMeter(): KnobMeter {
  const root = h('div', 'knob-meter hidden');
  const m: KnobMeter = { root, chans: [], fills: [], holds: [], grs: [] };
  for (let ch = 0; ch < 2; ch++) {
    const bar = h('div', 'vbar yellow');
    const fill = h('div', 'vbar-fill');
    const gr = h('div', 'vbar-gr hidden');
    const hold = h('div', 'vbar-hold');
    bar.append(fill, gr, hold);
    root.append(bar);
    m.chans.push(bar); m.fills.push(fill); m.grs.push(gr); m.holds.push(hold);
  }
  return m;
}

const pct = (v: number) => `${(Math.min(1, Math.max(0, v)) * 100).toFixed(1)}%`;

/** Стерео — две полосы, моно — одна; выше 0 dB — красная; заглушённая — серая; sidechain — оранжевым сверху. */
function renderKnobMeter(m: KnobMeter, track: number, now: number) {
  const lv = trackLevel(track, now);
  const stereo = trackIsStereo(track);
  const peaks = stereo ? [lv.l, lv.r] : [Math.max(lv.l, lv.r)];
  const holds = stereo ? [lv.holdL, lv.holdR] : [Math.max(lv.holdL, lv.holdR)];
  const duck = trackDuckDb(track);
  m.chans.forEach((c, i) => setClass(c, 'hidden', i >= peaks.length));
  peaks.forEach((p, i) => {
    setAttr(m.fills[i], 'style', `height:${pct(levelFrac(p))}`);
    setClass(m.fills[i], 'over', p >= OVER_PEAK);
    setClass(m.holds[i], 'hidden', levelFrac(holds[i]) <= 0.01);
    setAttr(m.holds[i], 'style', `bottom:${pct(levelFrac(holds[i]))}`);
    setClass(m.grs[i], 'hidden', duck > -0.1);
    if (duck <= -0.1) setAttr(m.grs[i], 'style', `height:${pct(-duck / 24)}`);
  });
  setClass(m.root, 'muted', !audible(track));
}

interface Gesture {
  slot: number;
  mode: GridMode;
  param: ParamDef;
  startY: number;
  lastY: number;
  moved: boolean;
  /** Накопитель положения ручки (0..1, для LFO −1..1). */
  acc: number;
  kind: 'base' | 'lock' | 'lfo';
  lfo: Mod;
  consumed: boolean;
  holdTimer?: number;
  /** MIX: ручку громкости подняли удержанием и перетаскивают (перестановка дорожек). */
  drag?: TrackDrag;
}

interface TrackDrag {
  from: number;
  /** Место, куда встанет дорожка, если отпустить сейчас. */
  to: number;
  x0: number;
  y0: number;
  /** Центры ручек дорожек (без сдвигов) — по ним выбирается место и сдвигаются соседи. */
  centers: { x: number; y: number }[];
}

const views: KnobView[] = [];
const gestures = new Map<number, Gesture>();
const lastTap: number[] = Array(16).fill(-1e9);

function buildKnob(slot: number): KnobView {
  const root = h('div', 'knob');
  const box = svg('svg', { viewBox: '0 0 100 100', class: 'knob-svg' });
  box.append(svg('path', { d: arc(R_VALUE, 0, 1), class: 'k-track' }));
  const rangeArc = svg('path', { class: 'k-range' });
  const valueArc = svg('path', { class: 'k-value' });
  const lockArc = svg('path', { class: 'k-lock' });
  const lfoArc = svg('path', { class: 'k-lfo' });
  box.append(svg('circle', { cx: 50, cy: 50, r: 24, class: 'k-cap' }));
  const pointer = svg('line', { x1: 50, y1: 29, x2: 50, y2: 22, class: 'k-pointer' });
  box.append(rangeArc, valueArc, lockArc, lfoArc, pointer);
  const value = h('div', 'knob-value');
  const label = h('div', 'knob-label');
  const dial = h('div', 'knob-dial');
  const meter = buildKnobMeter();
  const { msr, msrBtns } = buildMsr(slot);
  dial.append(meter.root, box, value, msr);
  root.append(dial, label);

  markKnob(root, slot);
  root.addEventListener('pointerdown', (e) => onDown(slot, e));
  root.addEventListener('pointermove', (e) => onMove(e));
  root.addEventListener('pointerup', (e) => onUp(e));
  root.addEventListener('pointercancel', (e) => onUp(e));
  return { root, label, value, valueArc, lfoArc, rangeArc, lockArc, pointer, meter, msr, msrBtns };
}

export function buildKnobGrid(): HTMLElement {
  const el = h('div', 'knob-grid');
  for (let i = 0; i < 16; i++) {
    const v = buildKnob(i);
    views.push(v);
    el.append(v.root);
  }
  return el;
}

// ---------- Жесты ----------

// ---------- Дорожки 9–12: удержание ручки в MIX ----------

/** Удержание скрытой ручки (или ручки добавленной дорожки) в MIX, мс. */
const TRACK_HOLD_MS = 500;
let trackMenu: Popup | null = null;

/** Окно у ручки: кнопки [надпись, действие, активна]. */
function openTrackMenu(anchor: Element, items: [string, () => void, boolean?][]) {
  if (!trackMenu) trackMenu = makePopup();
  const menu = trackMenu;
  menu.box.replaceChildren(...items.map(([label, action, on = true]) => {
    const b = popupButton(label, () => { menu.close(); action(); });
    b.disabled = !on;
    return b;
  }));
  menu.openAt(anchor, 180);
}

/** Скрытая ручка в MIX: двойной тап — ADD TRACK (дорожка добавляется в конец). */
function onHiddenDown(slot: number, e: PointerEvent) {
  if (gridMode() !== 'mix' || slot >= MAX_TRACKS || !canAddTrack()) return;
  e.preventDefault();
  const now = performance.now();
  if (now - lastTap[slot] < DOUBLE_TAP_MS) {
    lastTap[slot] = -1e9;
    openTrackMenu(views[slot].root, [['ADD TRACK', addTrack]]);
  } else lastTap[slot] = now;
}

// ---------- Перестановка дорожек в MIX: удержание ручки громкости и перетаскивание ----------

/** Место для дорожки — ближайшая к пальцу ручка существующей дорожки. */
function dropSlot(d: TrackDrag, x: number, y: number): number {
  let best = d.from;
  let bd = Infinity;
  d.centers.forEach((c, k) => {
    const dist = (c.x - x) ** 2 + (c.y - y) ** 2;
    if (dist < bd) { bd = dist; best = k; }
  });
  return best;
}

/** Поднятая ручка — за пальцем, соседи между from и to — на место соседа (анимация CSS). */
function layoutDrag(d: TrackDrag, x: number, y: number) {
  const n = d.centers.length;
  for (let k = 0; k < n; k++) {
    const r = views[k].root;
    if (k === d.from) { r.style.transform = `translate(${x - d.x0}px, ${y - d.y0}px) scale(1.12)`; continue; }
    // Новое место дорожки k после перестановки from → to.
    const p = d.from < d.to ? (k > d.from && k <= d.to ? k - 1 : k) : (k >= d.to && k < d.from ? k + 1 : k);
    const c = d.centers[k];
    const t = d.centers[p];
    r.style.transform = p === k ? '' : `translate(${t.x - c.x}px, ${t.y - c.y}px)`;
  }
}

function startDrag(g: Gesture, e: PointerEvent) {
  const n = doc.tracks.length;
  const centers = views.slice(0, n).map((v) => {
    const b = v.root.getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  });
  g.drag = { from: g.slot, to: g.slot, x0: e.clientX, y0: e.clientY, centers };
  views[g.slot].root.classList.add('knob-lifted');
  for (let k = 0; k < n; k++) if (k !== g.slot) views[k].root.classList.add('knob-shift');
}

function endDrag(d: TrackDrag, x: number, y: number) {
  const n = d.centers.length;
  for (let k = 0; k < n; k++) {
    const r = views[k].root;
    r.classList.remove('knob-lifted', 'knob-shift');
    r.style.transform = '';
  }
  if (d.to === d.from) {
    // Не сдвинули: ручка плавно возвращается на место.
    settle(d.from, x - d.x0, y - d.y0);
    return;
  }
  moveTrack(d.from, d.to);
  // Сразу перерисовать: ручки на местах показывают уже новый порядок (без мелькания старого).
  renderKnobs(performance.now());
  const c = d.centers[d.from];
  const t = d.centers[d.to];
  settle(d.to, c.x + x - d.x0 - t.x, c.y + y - d.y0 - t.y);
}

/** Ручка встаёт на место из сдвига (dx, dy) — короткая анимация. */
function settle(slot: number, dx: number, dy: number) {
  const r = views[slot].root;
  r.classList.add('knob-lifted');
  r.style.transform = `translate(${dx}px, ${dy}px) scale(1.12)`;
  void r.offsetWidth;
  r.classList.add('knob-settle');
  r.style.transform = '';
  window.setTimeout(() => r.classList.remove('knob-lifted', 'knob-settle'), 200);
}

function onDown(slot: number, e: PointerEvent) {
  const mode = gridMode();
  const param = gridFor(mode)[slot];
  if (!param) { onHiddenDown(slot, e); return; }
  e.preventDefault();
  // SHIFT + двойной тап по ручке дорожки — снять все p-lock дорожки (отмена — UNDO); с SHIFT ручка не крутится.
  if (ui.held.shift && mode === 'track') {
    const t = performance.now();
    if (t - lastTap[slot] < DOUBLE_TAP_MS) { lastTap[slot] = -1e9; clearTrackLocks(ui.selectedTrack); } else lastTap[slot] = t;
    return;
  }
  (e.currentTarget as Element).setPointerCapture(e.pointerId);

  const lfo = heldLfo();
  const held = firstHeldStep();
  // Удержание шага — p-lock в любом режиме (дорожка, FX, MOD, MIX, MST).
  // LFO/ENV назначаются на ручки дорожки и FX.
  const canMod = mode === 'track' || mode === 'fx';
  // Ручки без p-lock (компрессор мастера) с зажатым шагом крутят само значение.
  const kind: Gesture['kind'] = held !== null && !param.noLock ? 'lock' : canMod && lfo ? 'lfo' : 'base';
  const g: Gesture = { slot, mode, param, startY: e.clientY, lastY: e.clientY, moved: false, acc: 0, kind, lfo: lfo ?? 1, consumed: false };

  // Двойной тап: только при удержании шага (снять p-lock) или LFO (снять назначение).
  const now = performance.now();
  const trackKnob = mode === 'mix' && slot < doc.tracks.length && held === null;
  if (now - lastTap[slot] < DOUBLE_TAP_MS) {
    lastTap[slot] = -1e9;
    if (kind === 'lock') clearLock(param);
    else if (kind === 'lfo') clearLfoAssign(param, g.lfo, mode);
    else if (trackKnob) {
      // MIX: двойной тап по ручке громкости — COPY, PASTE (дорожку целиком), DELETE TRACK и RENAME
      // (если дорожек больше 8; правые сдвигаются).
      openTrackMenu(views[slot].root, [
        ['COPY', () => copyTrack(slot)],
        ['PASTE', () => pasteTrack(slot), hasTrackClip()],
        ['DELETE TRACK', () => deleteTrack(slot), canDeleteTrack(slot)],
        // Переименование дорожки — поле ввода у подписи под ручкой.
        ['RENAME', () => openRename(slot, views[slot].label)],
      ]);
    }
    g.consumed = true;
  }

  if (kind === 'lock') g.acc = toNorm(param, lockValue(held!, param) ?? paramValue(mode, param));
  else if (kind === 'lfo') {
    const a = assignFor(mode, param);
    g.acc = a && a.lfo === g.lfo ? a.amount : 0;
  } else g.acc = toNorm(param, paramValue(mode, param));

  gestures.set(e.pointerId, g);
  beginGesture();

  if (trackKnob && !g.consumed) {
    // Удержание ручки громкости без движения — ручка поднимается, её тащат на место другой дорожки.
    g.holdTimer = window.setTimeout(() => {
      if (!g.moved && gestures.get(e.pointerId) === g && !g.consumed) {
        g.consumed = true;
        startDrag(g, e);
      }
    }, TRACK_HOLD_MS);
  }
}

function onMove(e: PointerEvent) {
  const g = gestures.get(e.pointerId);
  if (g?.drag) {
    g.drag.to = dropSlot(g.drag, e.clientX, e.clientY);
    layoutDrag(g.drag, e.clientX, e.clientY);
    return;
  }
  if (!g || g.consumed) return;
  if (!g.moved) {
    // Пока ждём удержания (перестановка в MIX), мёртвая зона шире — палец чуть дрожит.
    if (Math.abs(e.clientY - g.startY) < (g.holdTimer !== undefined && g.mode === 'mix' ? DEAD_PX * 2 : DEAD_PX)) return;
    g.moved = true;
    g.lastY = e.clientY;
    return;
  }
  const d = (g.lastY - e.clientY) / TRAVEL_PX;
  g.lastY = e.clientY;
  if (g.kind === 'lfo') {
    g.acc = Math.min(1, Math.max(-1, g.acc + d));
    setLfoAmount(g.param, g.lfo, g.acc, g.mode);
    return;
  }
  g.acc = Math.min(1, Math.max(0, g.acc + d));
  if (g.kind === 'lock') setLockNorm(g.param, g.acc);
  else setParamNorm(g.mode, g.param, g.acc);
}

function onUp(e: PointerEvent) {
  const g = gestures.get(e.pointerId);
  if (!g) return;
  gestures.delete(e.pointerId);
  clearTimeout(g.holdTimer);
  if (g.drag) endDrag(g.drag, e.clientX, e.clientY);
  if (!g.moved && !g.consumed) lastTap[g.slot] = performance.now();
  endGesture();
}

/** Источники (LFO1–3, ENV), назначенные на ручки, которые сейчас держит палец (обводка их кнопок). */
export function heldKnobSources(): Set<Mod> {
  const out = new Set<Mod>();
  for (const g of gestures.values()) {
    const a = assignFor(g.mode, g.param);
    if (a) out.add(a.lfo);
  }
  return out;
}

// ---------- Отрисовка (каждый кадр) ----------

export function renderKnobs(now: number) {
  const mode = gridMode();
  const grid = gridFor(mode);
  const ti = ui.selectedTrack;
  const track = doc.tracks[ti];
  const held = firstHeldStep();
  const seq = curSeq();
  const playLocks = liveLocks(seqIndex(), now) ?? undefined;
  const lfoHeld = mode === 'track' || mode === 'fx' ? heldLfo() : null;

  views.forEach((v, slot) => {
    const p = grid[slot];
    const meter = mode === 'mix' && !!p && slot < doc.tracks.length;
    setClass(v.meter.root, 'hidden', !meter);
    if (meter) renderKnobMeter(v.meter, slot, now);
    setClass(v.msr, 'hidden', !meter);
    if (meter) {
      const t = doc.tracks[slot];
      setClass(v.msrBtns[0], 'on', t.mute);
      setClass(v.msrBtns[1], 'on', t.solo);
      setClass(v.msrBtns[2], 'on', !!t.arm);
    }
    setClass(v.root, 'inactive', !p);
    if (!p) {
      setText(v.label, '');
      setText(v.value, '');
      for (const a of [v.valueArc, v.lfoArc, v.rangeArc, v.lockArc]) setAttr(a, 'd', '');
      setAttr(v.pointer, 'transform', `rotate(${START} 50 50)`);
      return;
    }
    // В микшере подписи ручек — имена дорожек.
    setText(v.label, mode === 'mix' ? doc.tracks[slot]?.name ?? p.label : p.label);

    const base = paramValue(mode, p);
    const baseN = toNorm(p, base);
    const origin = p.bipolar ? 0.5 : 0;
    setAttr(v.valueArc, 'd', arc(R_VALUE, origin, baseN));

    // P-lock удерживаемого шага — жёлтым.
    // Удерживаемый шаг, иначе — шаг, который сейчас играет.
    const lock = held !== null
      ? seq.pages[Math.floor(held / 16)]?.[held % 16]?.locks[p.id]
      : playLocks?.[p.id];
    const locked = lock !== undefined;
    setClass(v.root, 'locked', locked);
    const shownBase = locked ? lock! : base;
    const shownN = toNorm(p, shownBase);
    setAttr(v.lockArc, 'd', locked ? arc(R_LOCK, origin, shownN) : '');

    // LFO: динамическое кольцо от базового до текущего значения.
    const assign = mode === 'track' ? track.assigns[p.id] : mode === 'fx' ? assignFor('fx', p) : undefined;
    const modN = mode === 'track' ? modulatedNorm(ti, p, shownBase) : mode === 'fx' ? fxModNorm(p, shownBase) : shownN;
    setAttr(v.lfoArc, 'd', assign ? arc(R_LFO, shownN, modN) : '');
    setAttr(v.lfoArc, 'class', assign ? `k-lfo mod${assign.lfo}` : 'k-lfo');

    // Пока держим LFO — видна вся зона воздействия.
    const showRange = lfoHeld && assign && assign.lfo === lfoHeld;
    setAttr(v.rangeArc, 'd', showRange ? arc(R_LFO, Math.max(0, shownN - Math.abs(assign!.amount)), Math.min(1, shownN + Math.abs(assign!.amount))) : '');
    setAttr(v.rangeArc, 'class', showRange ? `k-range mod${lfoHeld}` : 'k-range');

    setAttr(v.pointer, 'transform', `rotate(${(START + SWEEP * modN).toFixed(1)} 50 50)`);

    let text = p.format(fromNorm(p, modN));
    if (lfoHeld && assign && assign.lfo === lfoHeld) {
      const a = Math.round(assign.amount * 100);
      text = `${lfoHeld === 4 ? 'ENV' : `L${lfoHeld}`} ${a > 0 ? '+' : ''}${a}%`;
    }
    // Единица dB — второй строкой под числом.
    setText(v.value, text.replace(/ dB$/, '\ndB'));
  });
}
