// AudioWorklet: голоса синтезатора дорожки на движках Mutable Instruments Plaits (plaits.wasm).
// Один узел = одна дорожка; у узла SLOTS моно-выходов — по одному на голос, дальше каждый голос
// идёт через свою цепочку Web Audio (огибающая, Level, фильтр, Pan, посылы).
//
// Сообщения из основного потока (массив событий):
//   { type: 'note', slot, frame, end, engine, note, harmonics, timbre, morph, aux, accent }
//     — в кадре frame голос запускается (триггер), после кадра end молчит и не считается;
//   { type: 'mod', slot, note, harmonics, timbre, morph, aux, id?, frame? } — модуляция звучащего голоса (сразу);
//     с frame — в свой кадр (расписание автоматизации; новое расписание слота заменяет старое с этого кадра),
//     без frame — сразу и снимает расписание слота; с id — только голосу этой ноты;
//   { type: 'end', id, slot, end } — новый конец ноты id (отпустили живую ноту; у note тоже есть id);
//   { type: 'stop', slot, frame } — с кадра frame голос слота молчит (слот занял голос другого семейства
//     движков — свои движки JAMbo, jambo-synth-worklet.js).
// Голос, который затих сам (ударные, STRING, MODAL), перестаёт считаться раньше end.
// Plaits рассчитан на 48 кГц: при другой частоте дискретизации нота сдвигается, чтобы высота
// совпадала.
// Раз в ~0,5 с узел присылает { cpu: доля времени, ушедшая на расчёт голосов }.

const BLOCK = 24;
/** Тишина дольше этого (кадров) после атаки — голос больше не считается. */
const SILENCE = 4800;
const QUIET = 1e-5;
/**
 * Частота, на которую настроен Plaits: kCorrectedSampleRate в plaits/dsp/dsp.h (делитель тактовой частоты модуля,
 * 47872,34 Гц вместо 48000 — ошибка 4,6 цента). Нота сдвигается так, чтобы A4 звучала 440 Гц на частоте контекста.
 */
const PLAITS_SR = 47872.34;

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
    this.id = new Float64Array(slots);
    this.start0 = new Float64Array(slots);
    this.quiet = new Float64Array(slots);
    this.engine = new Int32Array(slots);
    this.noteShift = 12 * Math.log2(PLAITS_SR / sampleRate);
    this.busy = 0;
    this.frames = 0;
    this.mods = Array.from({ length: slots }, () => []);
    this.port.onmessage = (e) => {
      const seen = new Set();
      for (const ev of e.data) {
        if (ev.type === 'note' || ev.type === 'stop') {
          const q = this.pending[ev.slot];
          q.push(ev);
          q.sort((a, b) => a.frame - b.frame);
        } else if (ev.type === 'end') {
          // Новый конец ноты id (отпустили живую ноту): звучащей или ещё ждущей в очереди.
          if (this.id[ev.slot] === ev.id) this.end[ev.slot] = ev.end;
          for (const p of this.pending[ev.slot]) if (p.id === ev.id) p.end = ev.end;
        } else if (ev.type === 'mod') {
          // С кадром — расписание автоматизации: применяется в свой кадр (новое расписание слота заменяет
          // старое с этого кадра); без кадра — сразу, и запланированные mod слота снимаются.
          const m = this.mods[ev.slot];
          if (ev.frame === undefined) { m.length = 0; this.mod(ev); continue; }
          if (!seen.has(ev.slot)) { seen.add(ev.slot); while (m.length && m[m.length - 1].frame >= ev.frame) m.pop(); }
          m.push(ev);
        }
      }
    };
  }

  /** Модуляция звучащего голоса (у голоса другой ноты — нет: слот уже занят новой нотой). */
  mod(ev) {
    if (ev.id !== undefined && this.id[ev.slot] !== ev.id) return;
    this.w.set(ev.slot, this.engine[ev.slot], ev.note + this.noteShift, ev.harmonics, ev.timbre, ev.morph, 0.8, ev.aux);
  }

  start(slot, ev) {
    if (ev.type === 'stop') { this.end[slot] = Math.min(this.end[slot], ev.frame); return; }
    this.engine[slot] = ev.engine;
    this.end[slot] = ev.end;
    this.id[slot] = ev.id ?? 0;
    this.start0[slot] = ev.frame;
    this.quiet[slot] = 0;
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
        const m = this.mods[s];
        while (m.length && m[0].frame <= now) this.mod(m.shift());
        let n = Math.min(BLOCK, frames - pos);
        if (q.length) n = Math.min(n, q[0].frame - now);
        if (now >= this.end[s]) {
          out.fill(0, pos, pos + n);
        } else {
          const ptr = this.w.render(s, n);
          const buf = new Float32Array(this.w.memory.buffer, ptr, n);
          out.set(buf, pos);
          // Триггер — короткий импульс: гейт держится один блок.
          this.w.release(s);
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
