// Меню «бутерброд»: текущий проект, действия NEW, SAVE AS, RENAME, DELETE, EXPORT, IMPORT
// и список сохранённых проектов (тап — открыть; во время игры — переходом через сетку паттернов).

import {
  deleteCurrent, exportProject, importProject, newProject, openProject, project, projects, renameProject, saveAs,
} from '../project';
import { h, setText } from './dom';
import { makePopup, openInput, popupButton, type Popup } from './popup';

let menu: Popup;
let title: HTMLElement;
let list: HTMLElement;
let deleteBtn: HTMLButtonElement;
let deleteArmed = 0;

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
  deleteBtn = act('DELETE', () => {
    // Удаление — двумя тапами: первый спрашивает SURE?
    if (performance.now() - deleteArmed > 3000) {
      deleteArmed = performance.now();
      setText(deleteBtn, 'SURE?');
      return;
    }
    deleteArmed = 0;
    menu.close();
    void deleteCurrent().catch(fail('Delete'));
  });
  actions.append(
    act('NEW', () => { menu.close(); void newProject().catch(fail('New project')); }),
    act('SAVE AS', () => { menu.close(); openInput(title, `${project.name} copy`, (n) => void saveAs(n).catch(fail('Save'))); }),
    act('RENAME', () => { menu.close(); openInput(title, project.name, (n) => void renameProject(n).catch(fail('Rename'))); }),
    deleteBtn,
    act('EXPORT', () => { menu.close(); void exportProject().catch(fail('Export')); }),
    importBtn,
  );
  list = h('div', 'project-list');
  menu.box.append(title, actions, h('div', 'source-title', 'PROJECTS'), list);
}

export function openProjectMenu(anchor: Element) {
  if (!menu) buildMenu();
  deleteArmed = 0;
  setText(deleteBtn, 'DELETE');
  setText(title, project.name || '—');
  list.replaceChildren(...projects().map((p) => {
    const date = new Date(p.updated).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
    const b = popupButton(`${p.name}\n${date}`, () => {
      menu.close();
      void openProject(p.id).catch(fail('Open'));
    });
    b.classList.toggle('current', p.id === project.id);
    return b;
  }));
  menu.openAt(anchor, 340);
  // Окно — от верхней панели вниз, чтобы список помещался.
  menu.box.style.maxHeight = `${window.innerHeight - menu.box.getBoundingClientRect().top - 12}px`;
}
