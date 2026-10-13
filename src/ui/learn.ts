// MIDI LEARN (меню MIDI → MAPPING → LEARN): полоса внизу экрана, поверх пианоролла. Тап по ручке или кнопке выбирает
// цель (обычное действие не выполняется), затем движение контроллера (CC или нота) назначает его.
// Цель — голубая рамка, уже назначенные — полупрозрачная жёлтая заливка с типом маппинга (N или CC). Двойной тап по цели — окно настройки
// маппинга (ui/mapedit.ts). UNMAP снимает маппинг цели, DONE — выход из режима.

import { clearTarget, learn, isMapped, mappingFor, onLearnChanged, setLearn, sourceLabel, targetFromAttr, targetLabel, learnTarget, runAction } from '../midi';
import { settings } from '../settings';
import { DOUBLE_TAP_MS, h, setClass, setText } from './dom';
import { isOpen, openMapEditor } from './mapedit';

let bar: HTMLElement;
let text: HTMLElement;
let clearBtn: HTMLElement;
let marked: HTMLElement[] = [];
const rel = new WeakSet<HTMLElement>();
/** Касания, начатые на цели в режиме LEARN, — их отпускание тоже не доходит до кнопки. */
const blocked = new Set<number>();
/** Последний тап по цели (двойной тап — окно настройки). */
const lastTap = { key: '', at: -1e9 };

function describe() {
  if (!learn.target) return 'MIDI LEARN · Tap a knob or button on screen, double-tap to edit';
  const t = targetLabel(learn.target);
  const m = settings.mappings.filter((x) => JSON.stringify(x.target) === JSON.stringify(learn.target));
  if (!m.length) return `${t} · Move a control on your MIDI device`;
  return `${t}  ←  ${m.map((x) => sourceLabel(x.src)).join(', ')}${learn.last ? '' : ' · Move a control to remap'}`;
}

function update() {
  setClass(bar, 'hidden', !learn.on);
  setText(text, describe());
  setClass(clearBtn, 'disabled', !learn.target || !isMapped(learn.target));
}

export function buildLearnBar(): HTMLElement {
  bar = h('div', 'learn-bar hidden');
  text = h('div', 'learn-text');
  clearBtn = h('div', 'btn learn-btn', 'UNMAP');
  const done = h('div', 'btn learn-btn', 'DONE');
  clearBtn.addEventListener('pointerdown', (e) => { e.preventDefault(); if (learn.target) { clearTarget(learn.target); update(); } });
  done.addEventListener('pointerdown', (e) => { e.preventDefault(); setLearn(false); });
  bar.append(text, clearBtn, done);
  onLearnChanged(update);

  // Перехват касаний раньше элементов: в режиме LEARN тап по цели только выбирает её.
  window.addEventListener('pointerdown', (e) => {
    if (!learn.on) return;
    const el = (e.target as Element).closest<HTMLElement>('[data-midi]');
    const t = el && targetFromAttr(el.dataset.midi!);
    if (!t) return;
    e.preventDefault();
    e.stopPropagation();
    blocked.add(e.pointerId);
    const now = performance.now();
    if (el.dataset.midi === lastTap.key && now - lastTap.at < DOUBLE_TAP_MS) {
      lastTap.at = -1e9;
      openMapEditor(t);
      return;
    }
    lastTap.key = el.dataset.midi!;
    lastTap.at = now;
    learnTarget(t);
    // PATTERNS ещё и переключает сетку паттернов — так в LEARN можно добраться до её ячеек и строк.
    if (t.kind === 'button' && t.name === 'PATTERNS') runAction('PATTERNS');
    // Окно MIDI MAP открыто — переходит на новую цель.
    if (isOpen()) openMapEditor(t);
  }, true);
  const release = (e: PointerEvent) => {
    if (blocked.delete(e.pointerId)) e.stopPropagation();
  };
  window.addEventListener('pointerup', release, true);
  window.addEventListener('pointercancel', release, true);
  return bar;
}

/** Подсветка цели и назначенных элементов (каждый кадр, только в режиме LEARN). */
export function renderLearn() {
  if (!learn.on) {
    if (marked.length) {
      for (const el of marked) { setClass(el, 'midi-target', false); setClass(el, 'midi-mapped', false); delete el.dataset.midiType; }
      marked = [];
    }
    return;
  }
  marked = [...document.querySelectorAll<HTMLElement>('[data-midi]')];
  for (const el of marked) {
    const t = targetFromAttr(el.dataset.midi!);
    if (!t) continue;
    setClass(el, 'midi-target', JSON.stringify(t) === JSON.stringify(learn.target));
    // Назначенные — полупрозрачная жёлтая заливка, тип маппинга и номер: «CC 20», «N 36».
    const m = mappingFor(t);
    setClass(el, 'midi-mapped', !!m);
    if (m) el.dataset.midiType = `${m.src.type === 'cc' ? 'CC' : 'N'} ${m.src.num}`; else delete el.dataset.midiType;
    // Метка ставится в угол элемента: ему нужен свой контекст позиционирования.
    if (m && !rel.has(el)) { rel.add(el); if (getComputedStyle(el).position === 'static') el.classList.add('midi-rel'); }
  }
}
