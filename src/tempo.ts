// Текущий источник такта приложения (в веб-версии — всегда свой: темп проекта или внешний MIDI-клок).
// Интерфейс TempoSource и InternalTempoSource — tempoSource.ts; LinkTempoSource — только в нативном приложении.

import { doc, setBpm } from './state';
import { InternalTempoSource } from './tempoSource';

export { QUANTUM_BEATS, STEPS_PER_BEAT, isBarStart, nextBarAt, InternalTempoSource, type TempoSource } from './tempoSource';

export const tempoSource = new InternalTempoSource(() => doc.bpm, setBpm);
export const tempo = () => tempoSource.tempo();
