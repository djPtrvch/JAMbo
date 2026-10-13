// Запись стемов: кнопка ● у ручки громкости дорожки в MIX (и ARM n с MIDI) включает запись выхода
// дорожки, повторное нажатие — останавливает; стем (WAV 24 бит) ложится в папку RECORDINGS библиотеки
// с именем «дорожка · время». Пока идёт запись, на дорожке мигает красная точка.

import { isStemRecording, startStem, stopStem } from './audio/engine';
import { addSample, RECORDINGS } from './library';
import { doc } from './state';

export const stemRecording = (i: number) => isStemRecording(i);

export function toggleStem(i: number) {
  const t = doc.tracks[i];
  if (!t) return;
  if (!isStemRecording(i)) { void startStem(i); return; }
  const d = new Date();
  const two = (x: number) => String(x).padStart(2, '0');
  const name = `${t.name} ${two(d.getHours())}-${two(d.getMinutes())}-${two(d.getSeconds())}`;
  void stopStem(i, name).then((key) => { if (key) addSample(RECORDINGS, key, name); });
}
