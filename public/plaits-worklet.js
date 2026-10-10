// AudioWorklet: голоса синтезатора дорожки на движках Mutable Instruments Plaits (plaits.wasm).
// Один узел = одна дорожка; у узла SLOTS моно-выходов — по одному на голос, дальше каждый голос
// идёт через свою цепочку Web Audio (огибающая, Level, фильтр, Pan, посылы).
//
// Сообщения из основного потока (массив событий):
//   { type: 'note', slot, frame, end, engine, note, harmonics, timbre, morph, accent }
//     — в кадре frame голос запускается (триггер), после кадра end молчит и не считается;
//   { type: 'mod', slot, note, harmonics, timbre, morph } — модуляция звучащего голоса (сразу).
// Plaits рассчитан на 48 кГц: при другой частоте дискретизации нота сдвигается, чтобы высота
// совпадала.

const BLOCK = 24;

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
    this.engine = new Int32Array(slots);
    this.noteShift = 12 * Math.log2(48000 / sampleRate);
    this.port.onmessage = (e) => {
      for (const ev of e.data) {
        if (ev.type === 'note') {
          const q = this.pending[ev.slot];
          q.push(ev);
          q.sort((a, b) => a.frame - b.frame);
        } else if (ev.type === 'mod') {
          this.w.set(ev.slot, this.engine[ev.slot], ev.note + this.noteShift, ev.harmonics, ev.timbre, ev.morph, 0.8);
        }
      }
    };
  }

  start(slot, ev) {
    this.engine[slot] = ev.engine;
    this.end[slot] = ev.end;
    this.w.set(slot, ev.engine, ev.note + this.noteShift, ev.harmonics, ev.timbre, ev.morph, ev.accent);
    this.w.trigger(slot);
  }

  process(_inputs, outputs) {
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
          const ptr = this.w.render(s, n);
          out.set(new Float32Array(this.w.memory.buffer, ptr, n), pos);
          // Триггер — короткий импульс: гейт держится один блок.
          this.w.release(s);
        }
        pos += n;
      }
    }
    return true;
  }
}

registerProcessor('plaits', PlaitsProcessor);
