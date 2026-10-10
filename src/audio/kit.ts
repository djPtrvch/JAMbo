// Встроенный набор сэмплов: звуки генерируются в коде при старте (без файлов и сети).
// Каждый сэмпл — моно, исходная высота соответствует ноте C3 (SAMPLE_ROOT).

type Samples = Float32Array<ArrayBuffer>;
type Gen = (sr: number) => Samples;

const noise = () => Math.random() * 2 - 1;

/** Простой однополюсный фильтр верхних частот на месте. */
function highpass(x: Float32Array, sr: number, hz: number) {
  const a = Math.exp((-2 * Math.PI * hz) / sr);
  let prevX = 0;
  let prevY = 0;
  for (let i = 0; i < x.length; i++) {
    const y = a * (prevY + x[i] - prevX);
    prevX = x[i];
    prevY = y;
    x[i] = y;
  }
}

/** Однополюсный фильтр нижних частот на месте. */
function lowpass(x: Float32Array, sr: number, hz: number) {
  const a = Math.exp((-2 * Math.PI * hz) / sr);
  let y = 0;
  for (let i = 0; i < x.length; i++) {
    y = (1 - a) * x[i] + a * y;
    x[i] = y;
  }
}

function normalize(x: Samples, peak = 0.9): Samples {
  let m = 0;
  for (const v of x) m = Math.max(m, Math.abs(v));
  if (m > 0) for (let i = 0; i < x.length; i++) x[i] *= peak / m;
  return x;
}

const len = (sr: number, sec: number): Samples => new Float32Array(Math.round(sr * sec));

const kick: Gen = (sr) => {
  const x = len(sr, 0.7);
  let ph = 0;
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    ph += (2 * Math.PI * (45 + 120 * Math.exp(-t * 28))) / sr;
    x[i] = Math.sin(ph) * Math.exp(-t * 5.5) + (t < 0.004 ? noise() * 0.4 * (1 - t / 0.004) : 0);
  }
  return normalize(x);
};

const snare: Gen = (sr) => {
  const x = len(sr, 0.4);
  const n = len(sr, 0.4);
  for (let i = 0; i < n.length; i++) n[i] = noise() * Math.exp((-i / sr) * 14);
  highpass(n, sr, 1200);
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    x[i] = 0.55 * Math.sin(2 * Math.PI * 185 * t) * Math.exp(-t * 22) + 0.8 * n[i];
  }
  return normalize(x);
};

const clap: Gen = (sr) => {
  const x = len(sr, 0.45);
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    let env = 0;
    for (const d of [0, 0.011, 0.022]) if (t >= d) env = Math.max(env, Math.exp(-(t - d) * 160));
    if (t >= 0.03) env = Math.max(env, 0.6 * Math.exp(-(t - 0.03) * 11));
    x[i] = noise() * env;
  }
  highpass(x, sr, 900);
  lowpass(x, sr, 5000);
  return normalize(x);
};

/** Металлический шум хэта: сумма прямоугольников + шум, обрезанные снизу. */
function hat(sr: number, sec: number, decay: number): Samples {
  const x = len(sr, sec);
  const freqs = [205, 304, 369, 522, 540, 800];
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    let m = 0;
    for (const f of freqs) m += Math.sin(2 * Math.PI * f * 8 * t) > 0 ? 1 : -1;
    x[i] = (m / freqs.length * 0.6 + noise() * 0.5) * Math.exp(-t * decay);
  }
  highpass(x, sr, 7000);
  highpass(x, sr, 6000);
  return normalize(x, 0.8);
}

const closedHat: Gen = (sr) => hat(sr, 0.12, 45);
const openHat: Gen = (sr) => hat(sr, 0.7, 5.5);

const tom: Gen = (sr) => {
  const x = len(sr, 0.6);
  let ph = 0;
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    ph += (2 * Math.PI * (110 + 110 * Math.exp(-t * 12))) / sr;
    x[i] = Math.sin(ph) * Math.exp(-t * 7);
  }
  return normalize(x);
};

const perc: Gen = (sr) => {
  const x = len(sr, 0.3);
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    const mod = Math.sin(2 * Math.PI * 840 * t) * 4 * Math.exp(-t * 30);
    x[i] = Math.sin(2 * Math.PI * 600 * t + mod) * Math.exp(-t * 18);
  }
  return normalize(x);
};

/** Басовая нота C3: пила с мягким фильтром и затуханием. */
const bass: Gen = (sr) => {
  const x = len(sr, 1.4);
  const f = 130.81;
  for (let i = 0; i < x.length; i++) {
    const t = i / sr;
    const saw = 2 * ((f * t) % 1) - 1;
    x[i] = (saw * 0.7 + Math.sin(2 * Math.PI * f * t) * 0.6) * Math.exp(-t * 2.2) * Math.min(1, t / 0.004);
  }
  lowpass(x, sr, 900);
  lowpass(x, sr, 1400);
  return normalize(x);
};

const GENERATORS: Record<string, Gen> = {
  kick, snare, clap, hat: closedHat, openhat: openHat, tom, perc, bass,
};

/** Создать буферы встроенного набора: ключ 'kit:<id>' → AudioBuffer. */
export function buildKit(ctx: BaseAudioContext): Map<string, AudioBuffer> {
  const out = new Map<string, AudioBuffer>();
  for (const [id, gen] of Object.entries(GENERATORS)) {
    const data = gen(ctx.sampleRate);
    const buf = ctx.createBuffer(1, data.length, ctx.sampleRate);
    buf.copyToChannel(data, 0);
    out.set(`kit:${id}`, buf);
  }
  return out;
}
