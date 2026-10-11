// Меню «бутерброд»: текущий проект, действия NEW, SAVE, SAVE AS, RENAME, EXPORT, IMPORT
// и список сохранённых проектов (тап — открыть; во время игры — переходом через сетку паттернов).
// Свайп влево по проекту открывает справа корзину — тап по ней удаляет проект.
// SAVE AS с именем существующего проекта спрашивает, перезаписать ли его.

import {
  deleteById, exportProject, importProject, newProject, openProject, project, projectNamed, projects, renameProject,
  saveAs, saveProject,
} from '../project';
import { h, setText } from './dom';
import { makePopup, openInput, popupButton, type Popup } from './popup';

const TRASH_W = 72;

let menu: Popup;
let confirm: Popup;
let confirmText: HTMLElement;
let confirmYes: () => void = () => {};
let title: HTMLElement;
let list: HTMLElement;
let anchorEl: Element;

const fail = (what: string) => (e: unknown) => {
  console.error(what, e);
  window.alert(`${what} failed`);
};

function buildMenu() {
  menu = makePopup('project-menu');
  title = h('div', 'project-title');
  const actions = h('div', 'project-actions');
  const act = (label: string, fn: () => void) => popupButton(label, fn);
  // IMPORT — настоящее поле выбора файла поверх кнопки (на iOS выбор файла — только прямым тапом).
  const importBtn = h('div', 'popup-btn sample-pick', 'IMPORT');
  const input = h('input', 'sample-file');
  input.type = 'file';
  input.addEventListener('change', () => {
    const f = input.files?.[0];
    input.value = '';
    menu.close();
    if (f) void importProject(f).catch(fail('Import'));
  });
  importBtn.append(input);
  actions.append(
    act('NEW', () => { menu.close(); void newProject().catch(fail('New project')); }),
    act('SAVE', () => { void saveProject().then(() => fillList()).catch(fail('Save')); }),
    act('SAVE AS', () => { menu.close(); openInput(title, `${project.name} copy`, askSaveAs); }),
    act('RENAME', () => { menu.close(); openInput(title, project.name, (n) => void renameProject(n).catch(fail('Rename'))); }),
    act('EXPORT', () => { menu.close(); void exportProject().catch(fail('Export')); }),
    importBtn,
  );
  list = h('div', 'project-list');
  menu.box.append(title, actions, h('div', 'source-title', 'PROJECTS'), list);

  // Вопрос о перезаписи (SAVE AS с существующим именем).
  confirm = makePopup('confirm');
  confirmText = h('div', 'confirm-text');
  const row = h('div', 'confirm-row');
  row.append(
    popupButton('CANCEL', () => confirm.close()),
    popupButton('OVERWRITE', () => { confirm.close(); confirmYes(); }),
  );
  confirm.box.append(confirmText, row);
}

/** SAVE AS: если проект с таким именем есть — спросить, перезаписать ли его. */
function askSaveAs(name: string) {
  const same = projectNamed(name);
  if (!same) { void saveAs(name).catch(fail('Save')); return; }
  setText(confirmText, `“${same.name}” already exists. Overwrite it?`);
  confirmYes = () => void saveAs(name, same).catch(fail('Save'));
  confirm.openAt(anchorEl, 300);
}

/** Строка списка: свайп влево открывает корзину справа, тап — открыть проект. */
function projectRow(p: { id: string; name: string; updated: number }): HTMLElement {
  const row = h('div', 'project-row');
  const trash = h('div', 'project-trash');
  trash.innerHTML = '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  trash.addEventListener('pointerup', () => {
    void deleteById(p.id).then(() => fillList()).catch(fail('Delete'));
  });
  const date = new Date(p.updated).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  const item = h('div', 'popup-btn project-item', `${p.name}\n${date}`);
  item.classList.toggle('current', p.id === project.id);
  row.append(trash, item);

  let id = -1;
  let x0 = 0;
  let base = 0;
  let dx = 0;
  const place = (x: number) => { item.style.transform = x ? `translateX(${x}px)` : ''; };
  item.addEventListener('pointerdown', (e) => {
    id = e.pointerId;
    x0 = e.clientX;
    base = row.classList.contains('open') ? -TRASH_W : 0;
    dx = 0;
    item.classList.add('dragging');
  });
  item.addEventListener('pointermove', (e) => {
    if (e.pointerId !== id) return;
    dx = e.clientX - x0;
    if (Math.abs(dx) > 6) place(Math.max(-TRASH_W, Math.min(0, base + dx)));
  });
  const end = (e: PointerEvent, cancel: boolean) => {
    if (e.pointerId !== id) return;
    id = -1;
    item.classList.remove('dragging');
    const x = base + dx;
    if (Math.abs(dx) <= 6 && !cancel) {
      // Тап: открытая строка закрывается, закрытая — открывает проект.
      if (base) { row.classList.remove('open'); place(0); return; }
      menu.close();
      void openProject(p.id).catch(fail('Open'));
      return;
    }
    const open = x < -TRASH_W / 2;
    // Открыта может быть только одна строка.
    if (open) list.querySelectorAll('.project-row.open').forEach((r) => { if (r !== row) closeRow(r as HTMLElement); });
    row.classList.toggle('open', open);
    place(open ? -TRASH_W : 0);
  };
  item.addEventListener('pointerup', (e) => end(e, false));
  item.addEventListener('pointercancel', (e) => end(e, true));
  return row;
}

function closeRow(r: HTMLElement) {
  r.classList.remove('open');
  (r.querySelector('.project-item') as HTMLElement).style.transform = '';
}

function fillList() {
  setText(title, project.name || '—');
  list.replaceChildren(...projects().map(projectRow));
}

export function openProjectMenu(anchor: Element) {
  if (!menu) buildMenu();
  anchorEl = anchor;
  fillList();
  menu.openAt(anchor, 340);
  // Окно — от верхней панели вниз, чтобы список помещался.
  menu.box.style.maxHeight = `${window.innerHeight - menu.box.getBoundingClientRect().top - 12}px`;
}
