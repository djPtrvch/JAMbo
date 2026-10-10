// Минимальный звук: только щелчок метронома. Полноценный звук — этап 3.
// В iOS Safari аудио можно запустить только из касания пользователя (unlockAudio).

let ctx: AudioContext | null = null;

export function unlockAudio() {
  if (!ctx) {
    // iOS 17+: играть даже при выключенном звонке (переключатель Mute).
    const session = (navigator as Navigator & { audioSession?: { type: string } }).audioSession;
    if (session) session.type = 'playback';
    ctx = new AudioContext();
  }
  if (ctx.state !== 'running') void ctx.resume();
}

/** Щелчок в момент time (по шкале performance.now). */
export function clickAt(time: number, accent: boolean) {
  if (!ctx || ctx.state !== 'running') return;
  const when = Math.max(ctx.currentTime, ctx.currentTime + (time - performance.now()) / 1000);
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.frequency.value = accent ? 1600 : 1000;
  gain.gain.setValueAtTime(0.0001, when);
  gain.gain.exponentialRampToValueAtTime(accent ? 0.5 : 0.3, when + 0.002);
  gain.gain.exponentialRampToValueAtTime(0.0001, when + 0.05);
  osc.connect(gain).connect(ctx.destination);
  osc.start(when);
  osc.stop(when + 0.06);
}
