// Запись стема дорожки: стерео-вход копируется кусками по 4096 кадров и уходит в основной поток.
// Сообщения: true — начать, false — закончить (остаток досылается, затем { done: true }).
const CHUNK = 4096;

class StemRecorder extends AudioWorkletProcessor {
  constructor() {
    super();
    this.on = false;
    this.L = new Float32Array(CHUNK);
    this.R = new Float32Array(CHUNK);
    this.n = 0;
    this.port.onmessage = (e) => {
      if (e.data) { this.on = true; this.n = 0; return; }
      if (this.on && this.n > 0) this.port.postMessage([this.L.slice(0, this.n), this.R.slice(0, this.n)]);
      this.on = false;
      this.n = 0;
      this.port.postMessage({ done: true });
    };
  }

  process(inputs) {
    const inp = inputs[0];
    if (!this.on) return true;
    const frames = 128;
    const l = inp && inp[0];
    const r = inp && (inp[1] || inp[0]);
    for (let i = 0; i < frames; i++) {
      this.L[this.n] = l ? l[i] : 0;
      this.R[this.n] = r ? r[i] : 0;
      if (++this.n === CHUNK) {
        this.port.postMessage([this.L.slice(), this.R.slice()]);
        this.n = 0;
      }
    }
    return true;
  }
}

registerProcessor('stem-rec', StemRecorder);
