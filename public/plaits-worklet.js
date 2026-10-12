// AudioWorklet: голоса синтезатора дорожки на движках Mutable Instruments Plaits (plaits.wasm).
// Один узел = одна дорожка; у узла SLOTS моно-выходов — по одному на голос, дальше каждый голос
// идёт через свою цепочку Web Audio (огибающая, Level, фильтр, Pan, посылы).
//
// Сообщения из основного потока (массив событий):
//   { type: 'note', slot, frame, end, engine, note, harmonics, timbre, morph, aux, accent }
//     — в кадре frame голос запускается (триггер), после кадра end молчит и не считается;
//   { type: 'mod', slot, note, harmonics, timbre, morph, aux } — модуляция звучащего голоса (сразу).
// Голос, который затих сам (ударные, STRING, MODAL), перестаёт считаться раньше end.
// Plaits рассчитан на 48 кГц: при другой частоте дискретизации нота сдвигается, чтобы высота
// совпадала.
// Раз в ~0,5 с узел присылает { cpu: доля времени, ушедшая на расчёт голосов }.
//
// Движок DRUM (номер 16) — свой, считается здесь же, не в plaits.wasm: синус с экспоненциальной
// огибающей высоты (свип) + шум через полосовой фильтр (SVF) + клик → мягкий клиппер. Ручки:
// harmonics — SWEEP (0..+48 полутонов над нотой, время свипа = clamp(0.08·decay, 6, 80 мс)),
// timbre — TONE (синус → синус + шум поровну → шум; до 50 % добавляется обертон 1.6),
// morph — DRIVE (клик до 1.0, tanh с запасом 1 → 12, с компенсацией громкости). Огибающая —
// экспонента с постоянной времени Decay (событие несёт decay в мс). При ретриге фаза синуса = 0.

const BLOCK = 24;
/** Тишина дольше этого (кадров) после атаки — голос больше не считается. */
const SILENCE = 4800;
const QUIET = 1e-5;

const DRUM = 16;
/** Обертон мембраны (отношение частот) и Q полосового фильтра шума. */
const DRUM_RATIO = 1.6;
const DRUM_Q = 1.2;
/** Длительность клика, с. */
const DRUM_CLICK = 0.002;
/** Уровень синуса (пик) и шума (RMS) до клиппера: запас под клик и насыщение. */
const DRUM_SINE = 0.7;
const DRUM_NOISE_RMS = 0.45;
/** Общий множитель после клиппера: пик не выше 0 dBFS. */
const DRUM_OUT = 0.85;

/** Голос DRUM: состояние слота. */
class DrumVoice {
  constructor() {
    this.p1 = 0; this.p2 = 0; this.t = 0; this.ic1 = 0; this.ic2 = 0; this.rnd = 22222;
    this.note = 48; this.sweep = 0.5; this.tone = 0.5; this.drive = 0.5; this.decay = 500;
  }

  set(ev) {
    this.note = ev.note; this.sweep = ev.harmonics; this.tone = ev.timbre; this.drive = ev.morph; this.decay = ev.decay ?? this.decay;
  }

  trigger() { this.p1 = 0; this.p2 = 0; this.t = 0; }

  render(out, pos, n) {
    const sr = sampleRate;
    const f0 = 440 * Math.pow(2, (this.note - 69) / 12);
    const tau = Math.max(0.001, this.decay / 1000);
    const tauSweep = Math.min(0.08, Math.max(0.006, 0.08 * this.decay / 1000));
    const semis = 48 * this.sweep;
    // TONE: синус ↔ шум равной мощности; до 50 % растёт доля обертона 1.6.
    const x = this.tone;
    const gs = Math.cos(x * Math.PI / 2), gn = Math.sin(x * Math.PI / 2);
    const h2 = Math.min(1, x * 2) * 0.5;
    const hNorm = 1 / Math.sqrt(1 + h2 * h2); // мощность синуса с обертоном — как у чистого
    // Полосовой фильтр шума (TPT SVF): центр нота × 4, Q 1.2; уровень шума — к RMS DRUM_NOISE_RMS
    // по эквивалентной полосе фильтра (белый шум ±1 — RMS 1/√3).
    const fc = Math.min(f0 * 4, sr * 0.45);
    const g = Math.tan(Math.PI * fc / sr), k = 1 / DRUM_Q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const enbw = Math.PI / 2 * fc / DRUM_Q;
    const nGain = DRUM_NOISE_RMS / ((1 / Math.sqrt(3)) * Math.sqrt(Math.min(1, enbw / (sr / 2))));
    // DRIVE: клик и насыщение tanh (запас 1 → 12), компенсация — пик DRUM_SINE остаётся на месте.
    const dg = 1 + 11 * this.drive;
    const comp = DRUM_SINE / Math.tanh(dg * DRUM_SINE);
    const click = this.drive;
    const clickLen = DRUM_CLICK * sr;
    const dEnv = Math.exp(-1 / (tau * sr));
    const dSweep = Math.exp(-1 / (tauSweep * sr));
    let env = Math.exp(-this.t / (tau * sr));
    let sw = Math.exp(-this.t / (tauSweep * sr));
    let { p1, p2, ic1, ic2, rnd, t } = this;
    for (let i = 0; i < n; i++) {
      const f = f0 * Math.pow(2, semis * sw / 12);
      p1 += f / sr; if (p1 >= 1) p1 -= 1;
      p2 += f * DRUM_RATIO / sr; if (p2 >= 1) p2 -= 1;
      const tonal = (Math.sin(2 * Math.PI * p1) + h2 * Math.sin(2 * Math.PI * p2)) * hNorm;
      rnd ^= rnd << 13; rnd ^= rnd >>> 17; rnd ^= rnd << 5;
      const wn = (rnd | 0) / 2147483648;
      const v3 = wn - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
      ic1 = 2 * v1 - ic1; ic2 = 2 * v2 - ic2;
      const noise = k * v1 * nGain;
      let y = env * (gs * DRUM_SINE * tonal + gn * noise);
      if (t < clickLen) y += click * (1 - t / clickLen);
      out[pos + i] = DRUM_OUT * comp * Math.tanh(dg * y);
      env *= dEnv; sw *= dSweep; t++;
    }
    if (Math.abs(ic1) < 1e-20) ic1 = 0;
    if (Math.abs(ic2) < 1e-20) ic2 = 0;
    Object.assign(this, { p1, p2, ic1, ic2, rnd, t });
  }
}

class PlaitsProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const { bytes, slots } = options.processorOptions;
    const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), {});
    this.w = instance.exports;
    if (this.w._initialize) this.w._initialize();
    this.w.init();
    this.slots = slots;
    this.pending = Array.from({ length: slots }, () => []);
    this.end = new Float64Array(slots);
    this.start0 = new Float64Array(slots);
    this.quiet = new Float64Array(slots);
    this.engine = new Int32Array(slots);
    this.drums = Array.from({ length: slots }, () => new DrumVoice());
    this.noteShift = 12 * Math.log2(48000 / sampleRate);
    this.busy = 0;
    this.frames = 0;
    this.port.onmessage = (e) => {
      for (const ev of e.data) {
        if (ev.type === 'note') {
          const q = this.pending[ev.slot];
          q.push(ev);
          q.sort((a, b) => a.frame - b.frame);
        } else if (ev.type === 'mod') {
          if (this.engine[ev.slot] === DRUM) { this.drums[ev.slot].set(ev); continue; }
          this.w.set(ev.slot, this.engine[ev.slot], ev.note + this.noteShift, ev.harmonics, ev.timbre, ev.morph, 0.8, ev.aux);
        }
      }
    };
  }

  start(slot, ev) {
    this.engine[slot] = ev.engine;
    this.end[slot] = ev.end;
    this.start0[slot] = ev.frame;
    this.quiet[slot] = 0;
    if (ev.engine === DRUM) {
      this.drums[slot].set(ev);
      this.drums[slot].trigger();
      return;
    }
    this.w.set(slot, ev.engine, ev.note + this.noteShift, ev.harmonics, ev.timbre, ev.morph, ev.accent, ev.aux);
    this.w.trigger(slot);
  }

  process(_inputs, outputs) {
    const t0 = Date.now();
    const frames = outputs[0][0].length;
    for (let s = 0; s < this.slots; s++) {
      const out = outputs[s][0];
      const q = this.pending[s];
      let pos = 0;
      while (pos < frames) {
        const now = currentFrame + pos;
        // Запуск ноты ровно в её кадре (запоздавшая — сразу).
        while (q.length && q[0].frame <= now) this.start(s, q.shift());
        let n = Math.min(BLOCK, frames - pos);
        if (q.length) n = Math.min(n, q[0].frame - now);
        if (now >= this.end[s]) {
          out.fill(0, pos, pos + n);
        } else {
          let buf;
          if (this.engine[s] === DRUM) {
            this.drums[s].render(out, pos, n);
            buf = out.subarray(pos, pos + n);
          } else {
            const ptr = this.w.render(s, n);
            buf = new Float32Array(this.w.memory.buffer, ptr, n);
            out.set(buf, pos);
            // Триггер — короткий импульс: гейт держится один блок.
            this.w.release(s);
          }
          let peak = 0;
          for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(buf[i]));
          this.quiet[s] = peak < QUIET ? this.quiet[s] + n : 0;
          if (this.quiet[s] > SILENCE && now - this.start0[s] > SILENCE) this.end[s] = now;
        }
        pos += n;
      }
    }
    // Нагрузка: время расчёта к длительности звука (Date — миллисекунды, в среднем точно).
    this.busy += Date.now() - t0;
    this.frames += frames;
    if (this.frames >= sampleRate / 2) {
      this.port.postMessage({ cpu: this.busy / (this.frames / sampleRate * 1000) });
      this.busy = 0;
      this.frames = 0;
    }
    return true;
  }
}

registerProcessor('plaits', PlaitsProcessor);
