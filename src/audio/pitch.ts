// Определение высоты сэмпла при загрузке (алгоритм YIN по нескольким окнам).
// Результат — ближайшая MIDI-нота: сэмпл звучит в исходной высоте на этой ноте пианоролла.
// Для шумных и ударных звуков без ясной высоты возвращает null (тогда сэмпл привязан к C3).

const MIN_HZ = 40;
const MAX_HZ = 1500;
const WINDOW = 2048;
const THRESHOLD = 0.15;

/** Моно-сигнал с прореживанием до ~22 кГц (для скорости). */
function mono(buf: AudioBuffer): { data: Float32Array; rate: number } {
  const step = buf.sampleRate > 30000 ? 2 : 1;
  const n = Math.floor(buf.length / step);
  const data = new Float32Array(n);
  for (let ch = 0; ch < buf.numberOfChannels; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < n; i++) data[i] += d[i * step] / buf.numberOfChannels;
  }
  return { data, rate: buf.sampleRate / step };
}

/** Частота основного тона в окне [start, start+WINDOW) или null. */
function yin(x: Float32Array, start: number, rate: number): number | null {
  const minTau = Math.floor(rate / MAX_HZ);
  const maxTau = Math.min(Math.floor(rate / MIN_HZ), WINDOW - 1);
  const d = new Float32Array(maxTau + 1);
  for (let tau = 1; tau <= maxTau; tau++) {
    let s = 0;
    for (let i = 0; i < WINDOW - maxTau; i++) {
      const diff = x[start + i] - x[start + i + tau];
      s += diff * diff;
    }
    d[tau] = s;
  }
  // Нормированная разность: первый провал ниже порога.
  let sum = 0;
  for (let tau = 1; tau <= maxTau; tau++) {
    sum += d[tau];
    const cmnd = sum > 0 ? (d[tau] * tau) / sum : 1;
    if (tau >= minTau && cmnd < THRESHOLD) {
      // Спуск до локального минимума и параболическое уточнение.
      let t = tau;
      while (t + 1 <= maxTau && d[t + 1] < d[t]) t++;
      const a = d[t - 1] ?? d[t];
      const b = d[t];
      const c = d[t + 1] ?? d[t];
      const shift = (a - c) / (2 * (a - 2 * b + c) || 1);
      return rate / (t + (Number.isFinite(shift) ? shift : 0));
    }
  }
  return null;
}

/** MIDI-нота сэмпла или null, если высота не определяется. */
export function detectRoot(buf: AudioBuffer): number | null {
  const { data, rate } = mono(buf);
  if (data.length < WINDOW * 2) return null;
  // Начинаем после пика атаки, берём до 8 окон из первых ~1.5 с.
  let peakAt = 0;
  let peak = 0;
  const scan = Math.min(data.length, Math.floor(rate * 0.3));
  for (let i = 0; i < scan; i++) if (Math.abs(data[i]) > peak) { peak = Math.abs(data[i]); peakAt = i; }
  if (peak < 1e-4) return null;
  const from = Math.min(peakAt + Math.floor(rate * 0.02), data.length - WINDOW * 2);
  const to = Math.min(data.length - WINDOW * 2, from + Math.floor(rate * 1.5));
  const notes: number[] = [];
  for (let k = 0; k < 8; k++) {
    const start = Math.floor(from + ((to - from) * k) / 8);
    // Пропускаем почти тихие окна.
    let e = 0;
    for (let i = 0; i < WINDOW; i++) e = Math.max(e, Math.abs(data[start + i]));
    if (e < peak * 0.05) continue;
    const hz = yin(data, start, rate);
    if (hz) notes.push(Math.round(69 + 12 * Math.log2(hz / 440)));
  }
  if (notes.length < 3) return null;
  // Самая частая нота; если согласия нет — высоты нет.
  const count = new Map<number, number>();
  for (const n of notes) count.set(n, (count.get(n) ?? 0) + 1);
  const [best, votes] = [...count.entries()].sort((a, b) => b[1] - a[1])[0];
  return votes >= Math.ceil(notes.length / 2) ? Math.min(108, Math.max(12, best)) : null;
}
