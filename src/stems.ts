// Запись стемов: кнопка ● у ручки громкости дорожки в MIX (и ARM n с MIDI) включает запись выхода
// дорожки, повторное нажатие — останавливает; стем (WAV 24 бит) ложится в папку RECORDINGS библиотеки,
// во вложенную папку «проект дд.мм.гггг» (одна на проект и день), с именем «дорожка чч-мм-сс». Пока идёт запись, на дорожке мигает красная точка.

import { isStemRecording, startStem, stopStem } from './audio/engine';
import { addSample, children, createFolder, RECORDINGS } from './library';
import { project } from './project';
import { doc } from './state';

export const stemRecording = (i: number) => isStemRecording(i);

export function toggleStem(i: number) {
  const t = doc.tracks[i];
  if (!t) return;
  if (!isStemRecording(i)) { void startStem(i); return; }
  const d = new Date();
  const two = (x: number) => String(x).padStart(2, '0');
  const name = `${t.name} ${two(d.getHours())}-${two(d.getMinutes())}-${two(d.getSeconds())}`;
  const folder = `${project.name || 'Project'} ${two(d.getDate())}.${two(d.getMonth() + 1)}.${d.getFullYear()}`;
  void stopStem(i, name).then((key) => { if (key) addSample(recordingsFolder(folder), key, name); });
}

/** Папка проекта и дня внутри RECORDINGS (создаётся при первой записи). */
function recordingsFolder(name: string): string {
  const have = children(RECORDINGS).find((n) => n.kind === 'folder' && n.name === name);
  return (have ?? createFolder(RECORDINGS, name)).id;
}
