// Эталон звука TEXTURE и GRANULAR (ТЗ «Texture и Granular»): код движков веб-прототипа (вкладки Texture, вариант A,
// и Granular) в OfflineAudioContext Chromium (48 кГц). Время прототипа (ctx.currentTime, тик setInterval 25 мс,
// опережение 100 мс) смоделировано: тики идут по now = 0, 0.025, … до конца рендера, все события планируются заранее.
// Выход движка — до огибающей, фильтра и мастера прототипа (T.n.out; у Granular — шина зёрен A.gbus): так он
// сравнивается с выходом голоса Swift до огибающей. Нота держится всё время (Hold).
// Результат: JSON со статистикой (RMS, пик по каналам, третьоктавные полосы 25 Гц–16 кГц, dB) и WAV для прослушивания.
// Запуск: node ios/tools/texture/proto.mjs <out-dir> [секунд] [прогонов]
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const outDir = process.argv[2] ?? '.';
const SECONDS = Number(process.argv[3] ?? 10);
/** Прогонов на случай: статистика случайного звука усредняется по мощности (RMS, полосы), пик — наибольший. */
const RUNS = Number(process.argv[4] ?? 4);
fs.mkdirSync(outDir, { recursive: true });

const CASES = [
  { name: 'tex_default', engine: 'tex', k: [0.4, 0.5, 0.3, 0.3] },
  { name: 'tex_dark', engine: 'tex', k: [0, 0.5, 0, 0] },
  { name: 'tex_bright', engine: 'tex', k: [1, 0.5, 0, 0] },
  { name: 'tex_dense', engine: 'tex', k: [0.4, 1, 0, 0] },
  { name: 'tex_tone', engine: 'tex', k: [0.4, 0.5, 1, 0] },
  { name: 'tex_motion', engine: 'tex', k: [0.4, 0.5, 0.3, 1] },
  { name: 'tex_sparse_tone', engine: 'tex', k: [0, 0, 1, 0] },
  { name: 'gran_default', engine: 'gran', k: [0.12, 0.45, 0.55, 0.2] },
  { name: 'gran_mid', engine: 'gran', k: [0.5, 0.45, 0.55, 0] },
  { name: 'gran_tiny', engine: 'gran', k: [0.12, 0, 1, 0] },
  { name: 'gran_long', engine: 'gran', k: [0.12, 1, 0.2, 0] },
  { name: 'gran_spray', engine: 'gran', k: [0.5, 0.45, 0.55, 1] },
  { name: 'gran_dense', engine: 'gran', k: [0.12, 1, 1, 0] },
];

/** Код страницы: движки прототипа без интерфейса, время — параметр now. */
function pageCode() {
  const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const rnd = () => Math.random() * 2 - 1;
  const BASE = 220, RATIOS = [1, 2, 3, 4];
  const W_DARK = [1, .25, .08, .02], W_BRIGHT = [.55, .85, .9, .8];
  const M = { size: v => 0.005 * Math.pow(100, v), density: v => 2 * Math.pow(40, v) };

  function makeDemo() {
    const sr = 44100, len = sr * 6, d = new Float32Array(len);
    const notes = [220, 261.63, 329.63, 440, 392, 329.63, 293.66, 261.63], nl = Math.floor(sr * 0.4);
    notes.forEach((f, ni) => {
      const s0 = ni * nl, total = Math.floor(nl * 1.6);
      for (let i = 0; i < total && s0 + i < len; i++) {
        const t = i / sr; let v = 0;
        for (let k = 1; k <= 8; k++) v += Math.sin(2 * Math.PI * f * k * t) / k * Math.exp(-t * (2.5 + k * 1.4));
        if (i < 400) v += rnd() * 0.4 * (1 - i / 400);
        d[s0 + i] += v * 0.5;
      }
    });
    const p0 = Math.floor(sr * 3.4), plen = len - p0, chord = [110, 164.81, 220, 329.63];
    for (let i = 0; i < plen; i++) {
      const t = i / sr, x = i / plen, env = Math.pow(Math.sin(Math.PI * x), 1.5), vib = 1 + 0.004 * Math.sin(2 * Math.PI * 5 * t);
      let v = 0;
      for (let c = 0; c < chord.length; c++) for (let k = 1; k <= 5; k++) v += Math.sin(2 * Math.PI * chord[c] * vib * k * t) / (k * k);
      d[p0 + i] += v * 0.12 * env + rnd() * 0.03 * env;
    }
    let pk = 0; for (let i = 0; i < len; i++) pk = Math.max(pk, Math.abs(d[i]));
    const g = 0.85 / (pk || 1); for (let i = 0; i < len; i++) d[i] *= g;
    return d;
  }

  async function renderTex(k, seconds, semi) {
    const sr = 48000, ctx = new OfflineAudioContext(2, sr * seconds, sr);
    const P = { color: k[0], density: k[1], tone: k[2], motion: k[3] };
    const T = { semi, next: 0, ends: [], mod: { c: 0, d: 0, cT: 0, dT: 0, pit: [0, 0, 0, 0], pitT: [0, 0, 0, 0], hold: 0, tc: 0.1 } };
    const out = ctx.createGain();
    const ev = ctx.createGain(); ev.channelCount = 2; ev.channelCountMode = 'explicit';
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = -3;
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.Q.value = -3;
    const mk = ctx.createGain(), dry = ctx.createGain(), wet = ctx.createGain();
    ev.connect(lp); lp.connect(hp); hp.connect(mk); mk.connect(dry); dry.connect(out);
    const bank = RATIOS.map(r => {
      const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = BASE * r; f.Q.value = 10;
      const g = ctx.createGain(); g.gain.value = 0;
      ev.connect(f); f.connect(g); g.connect(wet);
      return { f, g };
    });
    wet.connect(out);
    const nb = ctx.createBuffer(1, sr * 3, sr), nd = nb.getChannelData(0);
    for (let i = 0; i < nd.length; i++) nd[i] = rnd();
    const ns = ctx.createBufferSource(); ns.buffer = nb; ns.loop = true;
    const cont = ctx.createGain(); cont.gain.value = 0;
    ns.connect(cont); cont.connect(ev); ns.start();
    out.connect(ctx.destination);
    function apply(now, tc) {
      const m = T.mod, fMax = sr * 0.45;
      const c = clamp(P.color + m.c, 0, 1), d = clamp(P.density + m.d, 0, 1), tone = P.tone;
      const lpHz = Math.min(250 * Math.pow(72, smooth(0, .55, c)), fMax);
      const hpHz = 30 * Math.pow(200, smooth(.55, 1, c));
      lp.frequency.setTargetAtTime(lpHz, now, tc);
      hp.frequency.setTargetAtTime(hpHz, now, tc);
      mk.gain.setTargetAtTime(clamp(0.2 / (0.577 * Math.sqrt(Math.max(300, lpHz - hpHz) / (sr * 0.5))), 0.5, 6) * (5.5 - 3.8 * d), now, tc);
      cont.gain.setTargetAtTime(smooth(.65, 1, d) * 0.9, now, tc);
      const Q = 2 + tone * tone * 98, f0 = BASE * Math.pow(2, T.semi / 12), bright = smooth(0, 1, c);
      const ws = W_DARK.map((a, i) => lerp(a, W_BRIGHT[i], bright));
      let S = 0; for (let i = 0; i < 4; i++) S += ws[i] * ws[i] * RATIOS[i];
      const boost = 1 + 5 * Math.pow(1 - d, 1.5);
      dry.gain.setTargetAtTime(Math.cos(tone * Math.PI / 2), now, tc);
      wet.gain.setTargetAtTime(Math.sin(tone * Math.PI / 2) * boost * Math.min(60, 37.5 * Math.sqrt(Q / (f0 * S))), now, tc);
      for (let i = 0; i < 4; i++) {
        const b = bank[i], fr = Math.min(f0 * RATIOS[i] * Math.pow(2, m.pit[i] * P.motion * 25 / 1200), fMax);
        b.f.frequency.setTargetAtTime(fr, now, Math.max(tc, 0.005));
        b.f.Q.setTargetAtTime(Q, now, tc);
        b.g.gain.setTargetAtTime(ws[i], now, tc);
      }
    }
    function spawn(t, len, rate) {
      const src = ctx.createBufferSource(); src.buffer = nb;
      const g = ctx.createGain(); g.gain.value = 0;
      const amp = (0.4 + Math.random() * 0.6) / Math.sqrt(Math.max(1, rate * len));
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(amp, t + 0.0004);
      g.gain.setTargetAtTime(0, t + 0.0004, len / 3);
      src.connect(g);
      const pn = ctx.createStereoPanner(); pn.pan.value = rnd() * 0.7; g.connect(pn);
      pn.connect(ev);
      src.start(t, Math.random() * (nb.duration - 0.5), len * 2 + 0.004);
      T.ends.push(t + len * 2 + 0.004);
    }
    // Начальные значения — apply(0, 0.001) (buildGraph), нота — apply(0, 0.01) (noteOn).
    apply(0, 0.001);
    apply(0, 0.01);
    for (let now = 0; now < seconds; now += 0.025) {
      const m = T.mod, mo = P.motion;
      if (mo > 0.001) {
        if (now >= m.hold) {
          const iv = lerp(0.8, 0.09, mo) * (0.6 + Math.random() * 0.8);
          m.hold = now + iv;
          m.cT = rnd() * 0.4 * mo; m.dT = rnd() * 0.5 * mo;
          for (let i = 0; i < 4; i++) m.pitT[i] = rnd();
          m.tc = lerp(iv * 0.6, 0.004, smooth(.45, 1, mo));
        }
        const kk = 1 - Math.exp(-0.025 / Math.max(0.004, m.tc));
        m.c += (m.cT - m.c) * kk; m.d += (m.dT - m.d) * kk;
        for (let i = 0; i < 4; i++) m.pit[i] += (m.pitT[i] - m.pit[i]) * kk;
        apply(now, 0.02);
      }
      const d = clamp(P.density + m.d, 0, 1), rate = 2 * Math.pow(60, d), len = 0.002 * Math.pow(60, d);
      if (T.next < now) T.next = now;
      while (T.next < now + 0.1) {
        const t = Math.max(T.next, now + 0.003);
        const count = T.ends.filter(e => e > now).length;
        if (count < 150) spawn(t, len, rate);
        T.next += Math.max(0.0005, -Math.log(1 - Math.random()) / rate);
      }
      if (T.ends.length > 4000) T.ends = T.ends.filter(e => e > now);
    }
    const buf = await ctx.startRendering();
    return [buf.getChannelData(0), buf.getChannelData(1)];
  }

  async function renderGran(k, seconds, semi) {
    const sr = 48000, ctx = new OfflineAudioContext(2, sr * seconds, sr);
    const P = { position: k[0], size: k[1], density: k[2], spray: k[3] };
    const demo = makeDemo();
    const b = ctx.createBuffer(1, demo.length, 44100); b.copyToChannel(demo, 0);
    const gbus = ctx.createGain(); gbus.gain.value = 3;
    gbus.connect(ctx.destination);
    const HANN = new Float32Array(64);
    for (let i = 0; i < 64; i++) HANN[i] = 0.5 * (1 - Math.cos(2 * Math.PI * i / 63));
    let next = 0; let ends = [];
    function spawn(t) {
      const bd = b.duration, sp = P.spray;
      const dur = Math.min(M.size(P.size), bd * 0.9);
      const rate = Math.pow(2, (semi + rnd() * sp * 3) / 12);
      let pos = (P.position + rnd() * sp * 0.35) * bd;
      pos = clamp(pos, 0, Math.max(0, bd - dur * rate - 0.001));
      const src = ctx.createBufferSource(); src.buffer = b; src.playbackRate.value = rate;
      const g = ctx.createGain(); g.gain.value = 0;
      src.connect(g);
      const pn = ctx.createStereoPanner(); pn.pan.value = clamp(rnd() * sp * 0.9, -1, 1); g.connect(pn);
      pn.connect(gbus);
      g.gain.setValueCurveAtTime(HANN, t, dur);
      src.start(t, pos, dur * rate);
      ends.push(t + dur);
    }
    for (let now = 0; now < seconds; now += 0.025) {
      const dens = M.density(P.density), dur = M.size(P.size);
      gbus.gain.setTargetAtTime(3.5 / Math.sqrt(Math.max(1, dens * dur)), now, 0.05);
      if (next < now) next = now;
      while (next < now + 0.1) {
        const count = ends.filter(e => e > now).length;
        if (count < 160) spawn(Math.max(next, now + 0.003));
        next += (1 / dens) * (1 + rnd() * P.spray * 0.8);
      }
      if (ends.length > 4000) ends = ends.filter(e => e > now);
    }
    const buf = await ctx.startRendering();
    return [buf.getChannelData(0), buf.getChannelData(1)];
  }

  window.renderCase = async (c, seconds) => {
    const [l, r] = c.engine === 'tex' ? await renderTex(c.k, seconds, 0) : await renderGran(c.k, seconds, 0);
    return { l: Array.from(l), r: Array.from(r) };
  };
}

/** Статистика: RMS, пик, третьоктавные полосы (dB, RMS по FFT-окнам 8192 с окном Ханна, усреднение мощности). */
export function stats(l, r, sr = 48000) {
  let peak = 0, sl = 0, sr2 = 0;
  for (let i = 0; i < l.length; i++) {
    peak = Math.max(peak, Math.abs(l[i]), Math.abs(r[i]));
    sl += l[i] * l[i]; sr2 += r[i] * r[i];
  }
  const N = 8192, bins = new Float64Array(N / 2);
  let frames = 0;
  const re = new Float64Array(N), im = new Float64Array(N);
  for (let s = 0; s + N <= l.length; s += N / 2) {
    for (let i = 0; i < N; i++) {
      const w = 0.5 * (1 - Math.cos(2 * Math.PI * i / (N - 1)));
      re[i] = (l[s + i] + r[s + i]) * 0.5 * w; im[i] = 0;
    }
    fft(re, im);
    for (let k = 0; k < N / 2; k++) bins[k] += re[k] * re[k] + im[k] * im[k];
    frames++;
  }
  const bands = [];
  for (let b = -16; b <= 12; b++) {
    const fc = 1000 * Math.pow(2, b / 3), lo = fc * Math.pow(2, -1 / 6), hi = fc * Math.pow(2, 1 / 6);
    let p = 0;
    for (let k = Math.ceil(lo * N / sr); k <= Math.floor(hi * N / sr) && k < N / 2; k++) p += bins[k];
    bands.push({ fc: Math.round(fc), db: 10 * Math.log10(p / Math.max(1, frames) + 1e-30) });
  }
  return { peak, rmsL: Math.sqrt(sl / l.length), rmsR: Math.sqrt(sr2 / r.length), bands };
}

function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const a = -2 * Math.PI / len, wr = Math.cos(a), wi = Math.sin(a);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let j = 0; j < len / 2; j++) {
        const ur = re[i + j], ui = im[i + j];
        const vr = re[i + j + len / 2] * cr - im[i + j + len / 2] * ci, vi = re[i + j + len / 2] * ci + im[i + j + len / 2] * cr;
        re[i + j] = ur + vr; im[i + j] = ui + vi; re[i + j + len / 2] = ur - vr; im[i + j + len / 2] = ui - vi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}

export function wav(file, l, r, sr = 48000) {
  const n = l.length, b = Buffer.alloc(44 + n * 4);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 4, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(2, 22); b.writeUInt32LE(sr, 24);
  b.writeUInt32LE(sr * 4, 28); b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l[i])) * 32767), 44 + i * 4);
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r[i])) * 32767), 46 + i * 4);
  }
  fs.writeFileSync(file, b);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('about:blank');
  await page.evaluate(`(${pageCode.toString()})()`);
  const all = {};
  for (const c of CASES) {
    const runs = [];
    for (let k = 0; k < RUNS; k++) {
      const { l, r } = await page.evaluate(([c, s]) => window.renderCase(c, s), [c, SECONDS]);
      runs.push(stats(l, r));
      if (k === 0) wav(path.join(outDir, `proto_${c.name}.wav`), l, r);
    }
    const pw = f => Math.sqrt(runs.reduce((a, x) => a + f(x) * f(x), 0) / RUNS);
    const st = {
      peak: Math.max(...runs.map(x => x.peak)), rmsL: pw(x => x.rmsL), rmsR: pw(x => x.rmsR),
      bands: runs[0].bands.map((b, i) => ({ fc: b.fc, db: 10 * Math.log10(runs.reduce((a, x) => a + Math.pow(10, x.bands[i].db / 10), 0) / RUNS) })),
    };
    all[c.name] = { k: c.k, ...st };
    console.log(`${c.name.padEnd(16)} peak ${st.peak.toFixed(3)} rms ${((st.rmsL + st.rmsR) / 2).toFixed(4)}`);
  }
  fs.writeFileSync(path.join(outDir, 'proto.json'), JSON.stringify(all, null, 1));
  await browser.close();
}
