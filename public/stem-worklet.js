// Запись стема дорожки: стерео-вход копируется кусками по 4096 кадров и уходит в основной поток.
// Сообщения: { start: кадр } — писать с этого кадра, { stop: кадр } — до этого кадра (не включая);
// когда запись дошла до stop, остаток досылается, затем { done: true }. Границы — с точностью до кадра.
const CHUNK = 4096;

class StemRecorder extends AudioWorkletProcessor {
  constructor() {
    super();
    this.start = Infinity;
    this.stop = Infinity;
    this.finished = false;
    this.L = new Float32Array(CHUNK);
    this.R = new Float32Array(CHUNK);
    this.n = 0;
    this.port.onmessage = (e) => {
      if (typeof e.data.start === 'number') this.start = e.data.start;
      if (typeof e.data.stop === 'number') this.stop = e.data.stop;
    };
  }

  process(inputs) {
    if (this.finished) return false;
    const inp = inputs[0];
    const l = inp && inp[0];
    const r = inp && (inp[1] || inp[0]);
    const f0 = currentFrame;
    for (let i = 0; i < 128; i++) {
      const f = f0 + i;
      if (f < this.start || f >= this.stop) continue;
      this.L[this.n] = l ? l[i] : 0;
      this.R[this.n] = r ? r[i] : 0;
      if (++this.n === CHUNK) {
        this.port.postMessage([this.L.slice(), this.R.slice()]);
        this.n = 0;
      }
    }
    if (f0 + 128 >= this.stop) {
      if (this.n > 0) this.port.postMessage([this.L.slice(0, this.n), this.R.slice(0, this.n)]);
      this.n = 0;
      this.finished = true;
      this.port.postMessage({ done: true });
    }
    return true;
  }
}

registerProcessor('stem-rec', StemRecorder);
