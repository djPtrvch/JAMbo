// Sidechain (этап 7): огибающая приглушения — один узел на проект, входа нет, выход — моно-сигнал e (0…1;
// 1 — полное приглушение). На каждой дорожке e идёт через GainNode с усилением −amount (глубина — ручка 3.4
// Sidechain) в gain её узла duck (значение 1): громкость = 1 − amount·e. У дорожки-источника глубина 0.
// Триги источника приходят заранее сообщением { type: 'trig', frame, attack, release, curve } (мс, мс, 0..100) и
// ждут в очереди (по frame); { type: 'flush' } — остановка: будущие триги отменяются (текущий возврат досчитывается).
// Триг: attack — линейно от текущего e до 1 за max(1 мс, ATTACK) (повторный триг — с текущего e, без скачка),
// затем release — (1 − u)^q за RELEASE, q = 2·4^((50 − CURVE)/50): CURVE 50 — q 2, 100 — q 0.5 (быстрый возврат
// в начале), 0 — q 8 (долго держит и быстро отпускает). После RELEASE e = 0.
// Индикация: раз в 512 отсчётов, пока e > 0.001 (и один раз при возврате к 0), узел присылает { e }; раз в ~0,5 с — { cpu }.

// ---------- Константы (одно место) ----------
const DUCK_CONST = {
  /** Наименьшая длина attack, мс. */
  minAttackMs: 1,
  /** Показатель формы возврата при CURVE 50 и диапазон (×4 в каждую сторону). */
  qBase: 2,
  qRange: 4,
  /** Индикация: период (отсчёты) и порог «есть приглушение». */
  reportFrames: 512,
  reportFloor: 0.001,
  /** Наибольшая длина очереди тригов. */
  maxQueue: 256,
};
const C = DUCK_CONST;

class DuckProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.sr = sampleRate;
    this.e = 0;
    this.stage = 0; // 0 idle, 1 attack, 2 release
    this.pos = 0; // отсчётов от начала стадии
    this.e0 = 0; // e в начале attack
    this.A = 1; // длина attack, отсчёты
    this.R = 1; // длина release, отсчёты
    this.q = 2;
    this.queue = []; // { frame, attack, release, curve } по frame
    this.sinceReport = 0;
    this.reported = 0;
    this.busy = 0;
    this.frames = 0;
    this.port.onmessage = (ev) => {
      const list = Array.isArray(ev.data) ? ev.data : [ev.data];
      for (const m of list) {
        if (!m) continue;
        if (m.type === 'flush') { this.queue.length = 0; continue; }
        if (m.type !== 'trig' || !Number.isFinite(m.frame)) continue;
        if (this.queue.length >= C.maxQueue) this.queue.shift();
        // Вставка по frame (обычно — в конец).
        let k = this.queue.length;
        while (k > 0 && this.queue[k - 1].frame > m.frame) k--;
        this.queue.splice(k, 0, { frame: m.frame, attack: +m.attack || 0, release: +m.release || 0, curve: Number.isFinite(+m.curve) ? +m.curve : 50 });
      }
    };
  }

  /** Триг: attack с текущего e. */
  start(t) {
    this.stage = 1;
    this.pos = 0;
    this.e0 = this.e;
    this.A = Math.max(1, Math.round((Math.max(C.minAttackMs, t.attack) / 1000) * this.sr));
    this.R = Math.max(1, Math.round((Math.max(0, t.release) / 1000) * this.sr));
    const c = Math.min(100, Math.max(0, t.curve));
    this.q = C.qBase * Math.pow(C.qRange, (50 - c) / 50);
  }

  process(inputs, outputs) {
    const out = outputs[0] && outputs[0][0];
    if (!out) return true;
    const n = out.length;
    const t0 = Date.now();
    const f0 = currentFrame;
    const q = this.queue;
    // Покой без тригов в этом блоке — нули, почти без расчёта.
    if (this.stage === 0 && (q.length === 0 || q[0].frame >= f0 + n)) {
      out.fill(0);
      this.report(t0, n);
      return true;
    }
    for (let i = 0; i < n; i++) {
      // Триги этого отсчёта (опоздавшие — в первом отсчёте блока).
      while (q.length && q[0].frame <= f0 + i) this.start(q.shift());
      let e = this.e;
      if (this.stage === 1) {
        this.pos++;
        e = this.e0 + (1 - this.e0) * Math.min(1, this.pos / this.A);
        if (this.pos >= this.A) { this.stage = 2; this.pos = 0; e = 1; }
      } else if (this.stage === 2) {
        this.pos++;
        const u = this.pos / this.R;
        if (u >= 1) { e = 0; this.stage = 0; } else e = Math.pow(1 - u, this.q);
      }
      if (!(e >= 0)) e = 0; // NaN
      else if (e > 1) e = 1;
      this.e = e;
      out[i] = e;
    }
    // Индикация: пока есть приглушение — раз в reportFrames; возврат к 0 — ещё раз.
    this.sinceReport += n;
    if (this.e > C.reportFloor ? this.sinceReport >= C.reportFrames : this.reported > C.reportFloor) {
      this.sinceReport = 0;
      this.reported = this.e;
      this.port.postMessage({ e: this.e > C.reportFloor ? this.e : 0 });
    }
    this.report(t0, n);
    return true;
  }

  report(t0, n) {
    this.busy += Date.now() - t0;
    this.frames += n;
    if (this.frames >= this.sr / 2) {
      this.port.postMessage({ cpu: this.busy / ((this.frames / this.sr) * 1000) });
      this.busy = 0;
      this.frames = 0;
    }
  }
}

registerProcessor('duck', DuckProcessor);
