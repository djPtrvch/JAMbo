// Проекты: текущий проект, автосохранение, создание, открытие (с переходом во время игры),
// сохранение, копия, переименование, удаление, экспорт и импорт файлом .jambo.
//
// SAVE записывает документ в текущий проект. Автосохранение пишет не в проект, а в отдельную
// запись Autosave (с датой и временем) — после перезагрузки открывается она, но SAVE по-прежнему
// сохраняет в тот проект, из которого она сделана. Всё хранится в браузере (storage.ts).

import { ensureSamples, sampleRecords } from './audio/engine';
import { docForSave, loadDoc, makeDoc, normalizeDoc, sampleKeys, switchWithTransition, ui, type Doc } from './state';
import {
  deleteProject, getProject, listProjects, newId, packProject, putProject, putSample, unpackProject,
  type ProjectInfo, type ProjectRecord,
} from './storage';

const CURRENT = 'jambo.current';
const AUTOSAVE_ID = 'autosave';
const AUTOSAVE_MS = 1500;

export const project = { id: '', name: '', ready: false };
/** Последнее, что записано автосохранением и кнопкой SAVE (для пометки «не сохранено»). */
let lastAuto = '';
let lastSaved = '';
let projectsCache: ProjectInfo[] = [];

export const projects = () => projectsCache;
export const isAutosave = (id: string) => id === AUTOSAVE_ID;
/** Текущий документ отличается от сохранённого кнопкой SAVE. */
export const unsaved = () => project.ready && JSON.stringify(docForSave()) !== lastSaved;

async function refreshList() {
  projectsCache = await listProjects();
}

function remember(id: string) {
  try { localStorage.setItem(CURRENT, id); } catch { /* хранилище недоступно */ }
}

/** Кнопка SAVE: записать документ в текущий проект. */
export async function saveProject() {
  if (!project.id) return;
  const json = JSON.stringify(docForSave());
  await putProject({ id: project.id, name: project.name, updated: Date.now(), doc: JSON.parse(json) });
  lastSaved = json;
  remember(project.id);
  await refreshList();
}

/** Автосохранение: при изменениях — в отдельную запись Autosave (с проектом, из которого она). */
async function autosave() {
  if (!project.ready) return;
  const json = JSON.stringify(docForSave());
  if (json === lastAuto) return;
  lastAuto = json;
  await putProject({
    id: AUTOSAVE_ID, name: 'Autosave', updated: Date.now(), doc: JSON.parse(json), projectId: project.id, projectName: project.name,
  });
  await refreshList();
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

/** Открыть запись: проект — как есть, Autosave — в проект, из которого она сделана. */
async function openRecord(rec: ProjectRecord) {
  project.ready = false;
  const auto = rec.id === AUTOSAVE_ID;
  project.id = auto ? rec.projectId ?? newId() : rec.id;
  project.name = auto ? rec.projectName ?? nextName() : rec.name;
  remember(project.id);
  await show(normalizeDoc(rec.doc));
  const json = JSON.stringify(docForSave());
  lastAuto = json;
  // У Autosave «сохранено» — то, что лежит в самом проекте.
  const saved = auto ? await getProject(project.id) : rec;
  lastSaved = saved ? JSON.stringify(normalizeDoc(saved.doc)) : '';
  if (!auto) lastSaved = json;
  project.ready = true;
}

/** При запуске: открыть автосохранение (последнюю работу), иначе последний проект, иначе новый. */
export async function initProjects() {
  try {
    await refreshList();
    let id: string | null = null;
    try { id = localStorage.getItem(CURRENT); } catch { /* нет хранилища */ }
    const rec = (await getProject(AUTOSAVE_ID)) ?? (id ? await getProject(id) : undefined);
    if (rec) await openRecord(rec);
    else {
      project.id = newId();
      project.name = nextName();
      project.ready = true;
    }
  } catch (e) {
    console.error('projects', e);
    project.ready = true;
  }
  setInterval(() => { void autosave().catch((e) => console.error('autosave', e)); }, AUTOSAVE_MS);
}

/** Открыть сохранённый проект или Autosave из списка. */
export async function openProject(id: string) {
  if (id === project.id) return;
  const rec = await getProject(id);
  if (rec) await openRecord(rec);
}

/** Новый пустой проект (в список попадёт после SAVE). */
export async function newProject() {
  project.ready = false;
  project.id = newId();
  project.name = nextName();
  await show(makeDoc());
  lastSaved = '';
  project.ready = true;
}

/** Проект с таким именем (кроме текущего) — для вопроса о перезаписи в SAVE AS. */
export function projectNamed(name: string): ProjectInfo | undefined {
  const n = name.trim().slice(0, 24);
  return projectsCache.find((p) => p.name === n && p.id !== project.id && !isAutosave(p.id));
}

/**
 * Копия текущего проекта под новым именем (дальше работаем в копии). replace — проект с тем же
 * именем, который перезаписывается (после подтверждения).
 */
export async function saveAs(name: string, replace?: ProjectInfo) {
  project.id = replace ? replace.id : newId();
  project.name = name.trim().slice(0, 24) || nextName();
  await saveProject();
}

/** RENAME: новое имя текущего проекта (у сохранённого — сразу и в списке). */
export async function renameProject(name: string) {
  const n = name.trim().slice(0, 24);
  if (!n) return;
  project.name = n;
  const rec = await getProject(project.id);
  if (rec) await putProject({ ...rec, name: n });
  await refreshList();
}

/** Удалить запись из списка (свайп влево и корзина). Текущая работа на экране остаётся. */
export async function deleteById(id: string) {
  await deleteProject(id);
  if (id === project.id) lastSaved = '';
  await refreshList();
}

/** Экспорт: файл .jambo со всеми сэмплами проекта (в Safari — загрузка в «Файлы»). */
export async function exportProject() {
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

/** Импорт файла .jambo: сохраняется как новый проект и сразу открывается. */
export async function importProject(file: File) {
  const { name, doc: raw, samples } = await unpackProject(file);
  for (const s of samples) await putSample(s);
  const rec: ProjectRecord = {
    id: newId(),
    name: projectsCache.some((p) => p.name === name) ? `${name} (imported)` : name,
    updated: Date.now(),
    doc: raw,
  };
  await putProject(rec);
  await refreshList();
  await openRecord(rec);
}
