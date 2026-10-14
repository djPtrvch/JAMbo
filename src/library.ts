// Библиотека сэмплов и пресетов (браузер ui/browser.ts): дерево папок, в каждой — папки, сэмплы и
// пресеты синта. Хранится в браузере (localStorage — дерево, IndexedDB — байты сэмплов по ключу
// от содержимого, см. storage.ts), общая для всех проектов. Файлы с iPad и iCloud Drive попадают
// сюда через IMPORT (окно «Файлы»), обратно — через EXPORT.
// Системная папка RECORDINGS — для стемов дорожек (запись появится позже); её нельзя удалить
// или переименовать.

import { migratePreset } from './params';
import type { Preset } from './state';

export interface LibNode {
  id: string;
  /** Родительская папка ('root' — корень). */
  parent: string;
  kind: 'folder' | 'sample' | 'preset' | 'table';
  name: string;
  /** Сэмпл: ключ в хранилище сэмплов; таблица WTABLE: ключ таблицы ('wt:<ключ сэмпла>:<размер кадра>'). */
  key?: string;
  /** Пресет синта. */
  preset?: Preset;
  /** Системная папка (RECORDINGS): не удаляется и не переименовывается. */
  system?: boolean;
  updated: number;
}

export const ROOT = 'root';
export const RECORDINGS = 'recordings';
const KEY = 'jambo.library';
const OLD_PRESETS = 'jambo.presets';

let nodes: LibNode[] = load();

function load(): LibNode[] {
  let list: LibNode[] = [];
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? 'null');
    if (Array.isArray(raw)) list = raw;
    else {
      // Первый запуск: пресеты прежней библиотеки — в папку Presets.
      const old = JSON.parse(localStorage.getItem(OLD_PRESETS) ?? '[]') as Preset[];
      if (Array.isArray(old) && old.length) {
        const f: LibNode = { id: newId(), parent: ROOT, kind: 'folder', name: 'Presets', updated: Date.now() };
        list.push(f, ...old.map((p): LibNode => ({ id: newId(), parent: f.id, kind: 'preset', name: p.name, preset: p, updated: Date.now() })));
      }
    }
  } catch { /* хранилище недоступно */ }
  // Пресеты прежнего формата (без fmt) — один раз к текущему (SPEECH: три пункта вместо четырёх).
  let migrated = false;
  for (const n of list) if (n.kind === 'preset' && n.preset && migratePreset(n.preset)) migrated = true;
  if (migrated) { try { localStorage.setItem(KEY, JSON.stringify(list)); } catch { /* хранилище недоступно */ } }
  if (!list.some((n) => n.id === RECORDINGS)) {
    list.unshift({ id: RECORDINGS, parent: ROOT, kind: 'folder', name: 'RECORDINGS', system: true, updated: Date.now() });
  }
  return list;
}

function store() {
  try { localStorage.setItem(KEY, JSON.stringify(nodes)); } catch { /* хранилище недоступно */ }
  listeners.forEach((l) => l());
}

let listeners: (() => void)[] = [];
export function onLibraryChanged(fn: () => void) { listeners.push(fn); }

function newId(): string {
  return `n${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;
}

export const node = (id: string) => nodes.find((n) => n.id === id);

/** Содержимое папки: сначала папки (RECORDINGS первой), потом сэмплы и пресеты, по имени. */
export function children(parent: string): LibNode[] {
  const rank = (n: LibNode) => (n.system ? 0 : n.kind === 'folder' ? 1 : 2);
  return nodes.filter((n) => n.parent === parent)
    .sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name, undefined, { numeric: true }));
}

/** Путь к папке: от корня до неё. */
export function path(id: string): LibNode[] {
  const out: LibNode[] = [];
  let n = node(id);
  while (n) { out.unshift(n); n = node(n.parent); }
  return out;
}

/** Имя без повтора в папке: «Name», «Name 2», … */
function uniqueName(parent: string, name: string, except?: string): string {
  const base = name.trim().slice(0, 40) || 'Untitled';
  const taken = new Set(nodes.filter((n) => n.parent === parent && n.id !== except).map((n) => n.name));
  if (!taken.has(base)) return base;
  let k = 2;
  while (taken.has(`${base} ${k}`)) k++;
  return `${base} ${k}`;
}

/** Сэмпл или пресет с таким же именем в папке (при сохранении — вопрос: перезаписать или сохранить как). */
export function sameName(parent: string, name: string): LibNode | undefined {
  const base = name.trim().slice(0, 40) || 'Untitled';
  return nodes.find((n) => n.parent === parent && n.kind !== 'folder' && n.name === base);
}

/** Свободное имя в папке («Name 2», …) — подсказка для SAVE AS. */
export const freeName = (parent: string, name: string) => uniqueName(parent, name);

/** Перезаписать сэмпл или пресет: имя и место те же, содержимое новое (сэмпл может стать пресетом и наоборот). */
export function overwrite(id: string, item: { key: string } | { preset: Preset }) {
  const n = node(id);
  if (!n || n.kind === 'folder') return;
  if ('key' in item) { n.kind = 'sample'; n.key = item.key; delete n.preset; }
  else { n.kind = 'preset'; n.preset = { ...item.preset, name: n.name }; delete n.key; }
  n.updated = Date.now();
  store();
}

export function createFolder(parent: string, name: string): LibNode {
  const n: LibNode = { id: newId(), parent, kind: 'folder', name: uniqueName(parent, name), updated: Date.now() };
  nodes.push(n);
  store();
  return n;
}

export function addSample(parent: string, key: string, name: string): LibNode {
  // Тот же сэмпл в той же папке не повторяется.
  const same = nodes.find((n) => n.parent === parent && n.kind === 'sample' && n.key === key);
  if (same) return same;
  const n: LibNode = { id: newId(), parent, kind: 'sample', name: uniqueName(parent, name), key, updated: Date.now() };
  nodes.push(n);
  store();
  return n;
}

/** Таблица WTABLE (WAV в хранилище сэмплов, key — ключ таблицы); та же в той же папке не повторяется. */
export function addTable(parent: string, key: string, name: string): LibNode {
  const same = nodes.find((n) => n.parent === parent && n.kind === 'table' && n.key === key);
  if (same) return same;
  const n: LibNode = { id: newId(), parent, kind: 'table', name: uniqueName(parent, name), key, updated: Date.now() };
  nodes.push(n);
  store();
  return n;
}

/** Имя таблицы WTABLE в библиотеке по ключу (первая найденная; нет — undefined). */
export const tableNodeName = (key: string) => nodes.find((n) => n.kind === 'table' && n.key === key)?.name;

export function addPreset(parent: string, preset: Preset): LibNode {
  const name = uniqueName(parent, preset.name);
  const n: LibNode = { id: newId(), parent, kind: 'preset', name, preset: { ...preset, name }, updated: Date.now() };
  nodes.push(n);
  store();
  return n;
}

export function rename(id: string, name: string) {
  const n = node(id);
  if (!n || n.system || !name.trim()) return;
  n.name = uniqueName(n.parent, name, id);
  if (n.preset) n.preset.name = n.name;
  n.updated = Date.now();
  store();
}

/** Удалить узел (папку — со всем содержимым). Байты сэмплов остаются в хранилище: на них могут ссылаться проекты. */
export function remove(id: string) {
  const n = node(id);
  if (!n || n.system) return;
  const gone = new Set([id]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const x of nodes) if (!gone.has(x.id) && gone.has(x.parent)) { gone.add(x.id); grew = true; }
  }
  nodes = nodes.filter((x) => !gone.has(x.id));
  store();
}

/** Сколько всего внутри папки (для подтверждения удаления). */
export const countInside = (id: string): number => nodes.filter((n) => n.parent === id).reduce((s, n) => s + 1 + (n.kind === 'folder' ? countInside(n.id) : 0), 0);
