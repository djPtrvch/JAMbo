// Проекты: текущий проект, автосохранение, создание, открытие (с переходом во время игры),
// копия, переименование, удаление, экспорт и импорт файлом .jambo.
// Документ (doc) и сэмплы хранятся в браузере (storage.ts); последний открытый проект
// открывается после перезагрузки.

import { ensureSamples, sampleRecords } from './audio/engine';
import {
  docForSave, inTransition, loadDoc, makeDoc, normalizeDoc, sampleKeys, switchWithTransition, ui, type Doc,
} from './state';
import {
  deleteProject, getProject, listProjects, newId, packProject, putProject, putSample, unpackProject, type ProjectInfo,
} from './storage';

const CURRENT = 'jambo.current';
const AUTOSAVE_MS = 1500;

export const project = { id: '', name: '', ready: false };
let lastSaved = '';
let projectsCache: ProjectInfo[] = [];

export const projects = () => projectsCache;

async function refreshList() {
  projectsCache = await listProjects();
}

function remember(id: string) {
  try { localStorage.setItem(CURRENT, id); } catch { /* хранилище недоступно */ }
}

/** Сохранить текущий проект сейчас (если что-то изменилось). */
export async function saveNow(force = false) {
  if (!project.ready || !project.id) return;
  const json = JSON.stringify(docForSave());
  if (!force && json === lastSaved) return;
  lastSaved = json;
  await putProject({ id: project.id, name: project.name, updated: Date.now(), doc: JSON.parse(json) });
  await refreshList();
}

/** Автосохранение: проверка изменений раз в AUTOSAVE_MS. */
function startAutosave() {
  setInterval(() => { void saveNow().catch((e) => console.error('autosave', e)); }, AUTOSAVE_MS);
}

function nextName(base = 'Project'): string {
  const names = new Set(projectsCache.map((p) => p.name));
  let n = 1;
  while (names.has(`${base} ${n}`)) n++;
  return `${base} ${n}`;
}

/** Показать документ d: во время игры — переходом, иначе — сразу. */
async function show(d: Doc) {
  await ensureSamples(sampleKeys(d));
  if (ui.playing) switchWithTransition(d);
  else loadDoc(d);
}

/** При запуске: открыть последний проект или создать первый. */
export async function initProjects() {
  try {
    await refreshList();
    let id: string | null = null;
    try { id = localStorage.getItem(CURRENT); } catch { /* нет хранилища */ }
    const rec = id ? await getProject(id) : undefined;
    if (rec) {
      project.id = rec.id;
      project.name = rec.name;
      const d = normalizeDoc(rec.doc);
      await show(d);
      lastSaved = JSON.stringify(docForSave());
    } else {
      project.id = newId();
      project.name = nextName();
      remember(project.id);
    }
    project.ready = true;
    await saveNow(true);
  } catch (e) {
    console.error('projects', e);
  }
  startAutosave();
}

/** Открыть сохранённый проект. */
export async function openProject(id: string) {
  if (id === project.id) return;
  await saveNow();
  const rec = await getProject(id);
  if (!rec) return;
  project.ready = false;
  project.id = rec.id;
  project.name = rec.name;
  remember(rec.id);
  await show(normalizeDoc(rec.doc));
  lastSaved = '';
  project.ready = true;
  await saveNow(true);
}

/** Новый пустой проект. */
export async function newProject() {
  await saveNow();
  project.ready = false;
  project.id = newId();
  project.name = nextName();
  remember(project.id);
  await show(makeDoc());
  project.ready = true;
  await saveNow(true);
}

/** Копия текущего проекта под новым именем (дальше работаем в копии). */
export async function saveAs(name: string) {
  await saveNow();
  project.id = newId();
  project.name = name.trim().slice(0, 24) || nextName();
  remember(project.id);
  await saveNow(true);
}

export async function renameProject(name: string) {
  const n = name.trim().slice(0, 24);
  if (!n) return;
  project.name = n;
  await saveNow(true);
}

/** Удалить текущий проект и открыть другой (или новый). */
export async function deleteCurrent() {
  await deleteProject(project.id);
  await refreshList();
  project.id = '';
  const other = projectsCache[0];
  if (other) {
    project.ready = false;
    const rec = await getProject(other.id);
    project.id = other.id;
    project.name = other.name;
    remember(other.id);
    if (rec) await show(normalizeDoc(rec.doc));
    lastSaved = '';
    project.ready = true;
  } else {
    await newProject();
  }
}

/** Экспорт: файл .jambo со всеми сэмплами проекта (в Safari — загрузка в «Файлы»). */
export async function exportProject() {
  await saveNow();
  const d = docForSave();
  const blob = packProject(project.name, d, await sampleRecords(sampleKeys(d)));
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${project.name.replace(/[^\w\- ]+/g, '_') || 'project'}.jambo`;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

/** Импорт файла .jambo: новый проект со своими сэмплами, сразу открывается. */
export async function importProject(file: File) {
  const { name, doc: raw, samples } = await unpackProject(file);
  for (const s of samples) await putSample(s);
  await saveNow();
  project.ready = false;
  project.id = newId();
  project.name = projectsCache.some((p) => p.name === name) ? `${name} (imported)` : name;
  remember(project.id);
  await show(normalizeDoc(raw));
  lastSaved = '';
  project.ready = true;
  await saveNow(true);
}

export const transitionActive = inTransition;
