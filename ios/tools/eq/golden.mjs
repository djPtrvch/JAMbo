// Эталоны EQ для Swift-версии (S5b): настоящий EqChain веба (src/audio/eq.ts — BiquadFilterNode, кроссфейд цепочек,
// setTargetAtTime) в OfflineAudioContext Chromium (headless, 48 кГц). eq.ts собирается rolldown в IIFE, страница
// рендерит случаи; результат забирается по протоколу отладки (Runtime.evaluate, WebSocket Node 22). Как в вебе, EqChain создаётся пустым и первый update()
// вводит полосы кроссфейдом 40 мс; события — update() в кадре, кратном 128 (suspend / resume).
// Входы — как input() в ios/tools/master/golden.mjs (drums, loud) и noise (белый шум, L и R — свои зёрна).
// Выход: ios/JAMbo.swiftpm/Resources/golden/eq_<имя>.i16 (стерео L,R по очереди, Int16 = round(x·32767)) и eq_cases.json.
// Запуск: node ios/tools/eq/golden.mjs (Chromium — /opt/pw-browsers или переменная CHROME).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const outDir = path.join(root, 'ios/JAMbo.swiftpm/Resources/golden');
const chrome = process.env.CHROME ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const F = 48000;

/** Полоса: тип (индекс EQ_TYPES: 0 Bell, 1 Low Shelf, 2 High Shelf, 3 Low Cut, 4 High Cut, 5 Notch), частота, усиление, Q, крутизна. */
const band = (type, freq, gain, q, slope = 0, on = true) => ({ on, type, freq, gain, q, slope });
const eq = (...bands) => ({ on: true, bands: Array.from({ length: 8 }, (_, k) => bands[k] ?? null) });

const CASES = [
  { name: 'bell_boost', frames: F / 2, input: 'noise', eq: eq(band(0, 1000, 9, 2)) },
  { name: 'bell_cut_wide', frames: F / 2, input: 'drums', eq: eq(band(0, 200, -12, 0.5)) },
  { name: 'bell_narrow', frames: F / 2, input: 'noise', eq: eq(band(0, 3150, 18, 18)) },
  { name: 'low_shelf', frames: F / 2, input: 'drums', eq: eq(band(1, 120, 6, 1)) },
  { name: 'high_shelf', frames: F / 2, input: 'noise', eq: eq(band(2, 6000, -8, 1)) },
  { name: 'low_cut_12', frames: F / 2, input: 'drums', eq: eq(band(3, 300, 0, 1, 0)) },
  { name: 'low_cut_48', frames: F / 2, input: 'drums', eq: eq(band(3, 100, 0, 0.7, 2)) },
  { name: 'high_cut_24', frames: F / 2, input: 'noise', eq: eq(band(4, 2000, 0, 1.5, 1)) },
  { name: 'high_cut_48', frames: F / 2, input: 'noise', eq: eq(band(4, 8000, 0, 0.3, 2)) },
  { name: 'notch', frames: F / 2, input: 'loud', eq: eq(band(5, 1000, 0, 4)) },
  { name: 'combo', frames: F / 2, input: 'drums',
    eq: eq(band(3, 40, 0, 1, 1), band(0, 90, 4, 1.2), null, band(0, 400, -3, 3), band(2, 9000, 3, 1), band(0, 2500, 9, 1, 0, false), band(4, 16000, 0, 1)) },
  { name: 'moves', frames: F, input: 'noise', eq: eq(band(0, 500, 6, 1), band(3, 60, 0, 1, 0)),
    events: [
      { frame: 12032, eq: eq(band(0, 4000, -6, 1), band(3, 60, 0, 1, 0)) },
      { frame: 24064, eq: eq(band(0, 4000, -6, 6), band(3, 400, 0, 2, 0)) },
      { frame: 36096, eq: eq(band(0, 150, 12, 0.3), band(3, 30, 0, 0.5, 0)) },
    ] },
  { name: 'switch', frames: F, input: 'drums', eq: eq(band(0, 1000, 6, 1)),
    events: [
      { frame: 9984, eq: eq(band(0, 1000, 6, 1), band(4, 3000, 0, 1, 1)) },
      { frame: 19968, eq: eq(band(1, 1000, 6, 1), band(4, 3000, 0, 1, 2)) },
      { frame: 29952, eq: eq(band(1, 1000, 6, 1, 0, false), band(4, 3000, 0, 1, 2)) },
      { frame: 39936, eq: { ...eq(band(1, 1000, 6, 1), band(4, 3000, 0, 1, 2)), on: false } },
    ] },
];

/** Открыть страницу в headless Chromium и дождаться renderAll() (протокол отладки). */
async function renderInChrome(url) {
  const proc = spawn(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu', '--allow-file-access-from-files',
    '--remote-debugging-port=0', `--user-data-dir=${path.join(tmp, 'profile')}`, url], { stdio: ['ignore', 'ignore', 'pipe'] });
  try {
    const ws = await new Promise((resolve, reject) => {
      let err = '';
      proc.stderr.on('data', (d) => {
        err += d;
        const m = err.match(/DevTools listening on (ws:\/\/\S+)/);
        if (m) resolve(m[1]);
      });
      proc.on('exit', () => reject(new Error(`chrome exited: ${err.slice(0, 300)}`)));
    });
    const port = new URL(ws).port;
    let target;
    for (let k = 0; k < 50 && !target; k++) {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === 'page' && t.url.startsWith('file:'));
      if (!target) await new Promise((r) => setTimeout(r, 100));
    }
    const sock = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((r) => sock.addEventListener('open', r, { once: true }));
    // Страница могла ещё не загрузиться (контекст сменился — повтор): ждём renderAll.
    let id = 0;
    let msg;
    for (let k = 0; k < 10; k++) {
      const n = ++id;
      const reply = new Promise((resolve) => sock.addEventListener('message', (e) => {
        const m = JSON.parse(e.data);
        if (m.id === n) resolve(m);
      }));
      sock.send(JSON.stringify({ id: n, method: 'Runtime.evaluate', params: {
        expression: 'new Promise((r) => { const w = () => (typeof renderAll === "function" ? r(renderAll()) : setTimeout(w, 50)); w(); })',
        awaitPromise: true, returnByValue: true } }));
      msg = await reply;
      if (!msg.error) break;
      await new Promise((r) => setTimeout(r, 200));
    }
    sock.close();
    const v = msg.result?.result?.value;
    if (typeof v !== 'string') throw new Error(`render failed: ${JSON.stringify(msg).slice(0, 300)}`);
    return v;
  } finally {
    proc.kill();
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'eq-'));
execFileSync(path.join(root, 'node_modules/.bin/rolldown'), [path.join(root, 'src/audio/eq.ts'), '--format', 'iife', '--name', 'EQ',
  '-o', path.join(tmp, 'eq.js')], { stdio: 'ignore' });

// Страница: входы (как input() мастера + noise), рендер каждого случая; renderAll() — JSON { имя: base64 Int16 }.
const page = `<!doctype html><html><body><script src="eq.js"></script><script>
const SR = 48000;
const CASES = ${JSON.stringify(CASES)};
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function input(kind, frames) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  if (kind === 'noise') {
    const a = mulberry32(3), b = mulberry32(4);
    for (let i = 0; i < frames; i++) { L[i] = (a() * 2 - 1) * 0.3; R[i] = (b() * 2 - 1) * 0.3; }
  } else if (kind === 'drums') {
    const rnd = mulberry32(5);
    for (let i = 0; i < frames; i++) {
      const t = (i % 12000) / SR;
      const th = ((i + 6000) % 12000) / SR;
      const kick = 0.9 * Math.exp(-t / 0.12) * Math.sin(2 * Math.PI * (55 * t + 40 * 0.03 * (1 - Math.exp(-t / 0.03))));
      const hat = 0.4 * Math.exp(-th / 0.015) * (rnd() * 2 - 1);
      L[i] = kick + hat;
      R[i] = kick + hat + 0.2 * Math.sin((2 * Math.PI * 220 * i) / SR);
    }
  } else if (kind === 'loud') {
    for (let i = 0; i < frames; i++) {
      const v = i < 24000 ? Math.sin((2 * Math.PI * 1000 * i) / SR) : 0.708 * Math.sin((2 * Math.PI * 5000 * i) / SR);
      L[i] = v; R[i] = 0.9 * v;
    }
  }
  return [L, R];
}
async function render(c) {
  const ctx = new OfflineAudioContext(2, c.frames, SR);
  const [L, R] = input(c.input, c.frames);
  const buf = ctx.createBuffer(2, c.frames, SR);
  buf.copyToChannel(L, 0);
  buf.copyToChannel(R, 1);
  const src = ctx.createBufferSource();
  src.buffer = buf;
  const chain = new EQ.EqChain(ctx);
  src.connect(chain.input);
  chain.output.connect(ctx.destination);
  chain.update(c.eq);
  for (const e of c.events || []) {
    ctx.suspend(e.frame / SR).then(() => { chain.update(e.eq); ctx.resume(); });
  }
  src.start(0);
  const out = await ctx.startRendering();
  const a = out.getChannelData(0), b = out.getChannelData(1);
  const res = new Int16Array(c.frames * 2);
  for (let i = 0; i < c.frames; i++) {
    res[2 * i] = Math.max(-32767, Math.min(32767, Math.round(a[i] * 32767)));
    res[2 * i + 1] = Math.max(-32767, Math.min(32767, Math.round(b[i] * 32767)));
  }
  let s = '';
  const u8 = new Uint8Array(res.buffer);
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
  return btoa(s);
}
async function renderAll() {
  const all = {};
  for (const c of CASES) all[c.name] = await render(c);
  return JSON.stringify(all);
}
</script></body></html>`;
fs.writeFileSync(path.join(tmp, 'index.html'), page);
const results = JSON.parse(await renderInChrome(`file://${path.join(tmp, 'index.html')}`));
fs.rmSync(tmp, { recursive: true });

const cases = [];
for (const c of CASES) {
  const file = `eq_${c.name}.i16`;
  fs.writeFileSync(path.join(outDir, file), Buffer.from(results[c.name], 'base64'));
  const { name, ...rest } = c;
  cases.push({ file, ...rest, events: c.events ?? [] });
}
fs.writeFileSync(path.join(outDir, 'eq_cases.json'), JSON.stringify({ cases }, null, 1));
console.log(`eq golden: ${cases.length} cases → ${outDir}`);
