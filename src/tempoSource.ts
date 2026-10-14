// Источник такта (TempoSource) — интерфейс и свой источник, без зависимостей (проверка в Node: scripts/tempo-check.mjs): темп и фаза, по которым секвенсор ставит шаги. Сейчас один источник —
// InternalTempoSource (свой темп проекта или внешний MIDI-клок, sync.ts); в нативном приложении к нему добавится
// LinkTempoSource (Ableton Link, этап 9 — в веб-версии его нет). Время — секунды часов планировщика
// (в браузере performance.now() / 1000; в нативном — время хоста), доля — четверть, шаг — 1/4 доли.

/** Долей в такте: квант (quantum) для запуска паттернов и строк — граница такта. */
export const QUANTUM_BEATS = 4;
/** Шагов секвенсора (1/16) в доле. */
export const STEPS_PER_BEAT = 4;

export interface TempoSource {
  kind: 'internal' | 'link';
  /** Текущий темп, BPM. */
  tempo(): number;
  /** Запрос смены темпа. */
  setTempo(bpm: number): void;
  /** Доля (от начала игры) в момент time, с. */
  beatAt(time: number): number;
  /** Момент, с, для доли beat. */
  timeAt(beat: number): number;
  isPlaying(): boolean;
  /** Старт (доля 0 — в момент at, с; по умолчанию сейчас) и остановка. */
  requestStart(at?: number): void;
  requestStop(at?: number): void;
  /** Подписка на смену темпа и состояния; возвращает отписку. */
  onChange(cb: () => void): () => void;
}

/** Граница такта: доля beat — начало такта (кратна QUANTUM_BEATS). */
export const isBarStart = (beat: number) => Math.abs(beat / QUANTUM_BEATS - Math.round(beat / QUANTUM_BEATS)) < 1e-9;
/** Ближайшая граница такта не раньше beat. */
export const nextBarAt = (beat: number) => Math.ceil(beat / QUANTUM_BEATS - 1e-9) * QUANTUM_BEATS;

/**
 * Свой источник: темп (BPM проекта или внешнего MIDI-клока) и точка отсчёта — доля b0 в момент t0.
 * Смена темпа не сдвигает долю: точка переносится на долю, с которой действует новый темп (retempo).
 * PLAY стартует сразу (как прежде).
 */
export class InternalTempoSource implements TempoSource {
  readonly kind = 'internal' as const;
  private t0 = 0;
  private b0 = 0;
  /** Темп, по которому считается текущая точка отсчёта. */
  private bpm: number;
  private playing = false;
  private listeners = new Set<() => void>();
  /** Темп внешнего клока (MIDI) — точнее целого BPM проекта; null — свой темп. */
  external: () => number | null = () => null;
  /** Старт и остановка транспорта (подключает transport.ts). */
  starter: (on: boolean, at?: number) => void = () => {};

  private bpmOf: () => number;
  private setBpmOf: (bpm: number) => void;
  constructor(bpmOf: () => number, setBpmOf: (bpm: number) => void) { this.bpmOf = bpmOf; this.setBpmOf = setBpmOf; this.bpm = bpmOf(); }

  tempo(): number { return this.external() ?? this.bpmOf(); }
  setTempo(bpm: number) { this.setBpmOf(bpm); this.emit(); }
  beatAt(time: number): number { return this.b0 + ((time - this.t0) * this.bpm) / 60; }
  timeAt(beat: number): number { return this.t0 + ((beat - this.b0) * 60) / this.bpm; }
  isPlaying() { return this.playing; }
  requestStart(at?: number) { this.starter(true, at); }
  requestStop(at?: number) { this.starter(false, at); }
  onChange(cb: () => void) { this.listeners.add(cb); return () => { this.listeners.delete(cb); }; }

  /** Транспорт стартовал: доля 0 — в момент at, с. */
  started(at: number) { this.t0 = at; this.b0 = 0; this.bpm = this.tempo(); this.playing = true; this.emit(); }
  stopped() { this.playing = false; this.emit(); }
  /**
   * Темп сменился (проект, кроссфейдер, MIDI-клок): с доли beat (следующий шаг) действует новый темп; момент этой
   * доли считается по прежнему — доля не прыгает. true — темп был другим.
   */
  retempo(beat: number): boolean {
    const bpm = this.tempo();
    if (bpm === this.bpm) return false;
    this.t0 = this.timeAt(beat);
    this.b0 = beat;
    this.bpm = bpm;
    this.emit();
    return true;
  }
  /** Сдвиг фазы на dt, с (подстройка к внешнему клоку; вкладка была в фоне — без догона пропущенных шагов). */
  shift(dt: number) { this.t0 += dt; }
  private emit() { this.listeners.forEach((l) => l()); }
}
