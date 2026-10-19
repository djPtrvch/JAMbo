// Эталон импорта проекта веба для Swift-версии (S11a): настоящие makeDoc / normalizeDoc (src/state.ts) и packProject
// (src/storage.ts) веба, собранные rolldown для Node. Проект — с клипами (слоты), пустым активным клипом, папкой
// с пресетом, своей таблицей WTABLE, EQ, MIX / MST, мастером, автоматизацией (не переносится); сэмплы — маленькие WAV,
// ключи — sampleKey веба по их байтам.
// Выход: ios/tools/webproject/web_project.jambo. Запуск: node ios/tools/webproject/golden.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'jambo-webproject-'));

// Окружение браузера, которое трогают модули при загрузке.
globalThis.localStorage = { getItem: () => null, setItem: () => {}, removeItem: () => {} };
globalThis.window = globalThis;

const entry = path.join(tmp, 'entry.ts');
fs.writeFileSync(entry, [
  `export { makeDoc, normalizeDoc, emptyPage } from ${JSON.stringify(path.join(root, 'src/state.ts'))};`,
  `export { packProject, sampleKey } from ${JSON.stringify(path.join(root, 'src/storage.ts'))};`,
  `export { AUTO_VALUE } from ${JSON.stringify(path.join(root, 'src/params.ts'))};`,
].join('\n'));
const bundle = path.join(tmp, 'web.mjs');
execFileSync(path.join(root, 'node_modules/.bin/rolldown'), [entry, '--format', 'esm', '--platform', 'node', '--file', bundle],
  { stdio: 'inherit' });
const W = await import(pathToFileURL(bundle).href);

/** WAV 16 бит моно 48 кГц: синус freq Гц, n отсчётов. */
function wav(freq, n) {
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(48000, 24); buf.writeUInt32LE(96000, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.sin((2 * Math.PI * freq * i) / 48000) * 16000), 44 + i * 2);
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

const kickBytes = wav(60, 4800);
const snareBytes = wav(200, 2400);
const tableBytes = wav(23.4375, 2048 * 4);
const kick = await W.sampleKey(kickBytes);
const snare = await W.sampleKey(snareBytes);
const table = await W.sampleKey(tableBytes);

const d = W.makeDoc();
d.bpm = 97;
d.scale = 2;
d.root = 5;
// Девять дорожек (больше 8 по умолчанию).
const extra = JSON.parse(JSON.stringify(d.tracks[7]));
extra.name = '9';
d.tracks.push(extra);
d.eqs.push({ on: true, bands: Array(8).fill(null) });
d.folders.push({ items: [], index: -1 });

const t0 = d.tracks[0];
t0.name = 'KICK';
t0.sample = kick;
t0.params.filter = 40;
t0.assigns = { filter: { lfo: 2, amount: -0.5 } };
t0.pages = [W.emptyPage(), W.emptyPage()];
t0.pages[0][3] = { on: true, len: 2, notes: [60, 64], locks: { filter: 30 }, sound: snare, soundLocks: ['decay'] };
t0.pages[1][0] = { on: true, len: 1, notes: [48], locks: {} };
t0.length = 20;
t0.playFrom = 0;
t0.playTo = 1;
t0.scale = 4;
t0.root = 7;
t0.fx = { ...d.fx, 'rev.size': 70 };
t0.slot = 2;
t0.slots[0] = { playFrom: 1, playTo: 1, scale: 1, root: 3, fx: { ...d.fx, 'dly.time': 9 } };
t0.slots[5] = { playFrom: 0, playTo: 0 };
t0.mute = true;
t0.slices = { [kick]: [{ at: 0.5, note: 62 }, { at: 0.75 }] };
t0.auto = [{ param: 'filter', points: [{ x: 0, y: 0.2 }, { x: 16, y: 0.8 }] }];

const t1 = d.tracks[1];
t1.sample = 'mi:3';
t1.blank = true;
t1.stopped = true;
t1.slot = 1;
t1.slots[0] = { playFrom: 0, playTo: 0 };
t1.table = 'builtin:ORGAN';
t1.solo = true;

const t2 = d.tracks[2];
t2.sample = 'mi:19';
t2.table = `wt:${table}:2048`;

d.mixer['mix.vol1'] = -6;
d.mixer['mix.vol2'] = -60;
d.eqs[0].bands[1] = { on: true, type: 0, freq: 300, gain: -4, q: 2, slope: 0, ms: 1, dyn: 2, thr: -30, range: -6 };
d.masterEq.bands[0] = { on: true, type: 3, freq: 40, gain: 0, q: 0.71, slope: 1 };
d.folders[0] = {
  items: [{ sample: kick }, { preset: { name: 'Bell', sound: 'mi:2', params: { harm: 30 }, fmt: 2 } }, { sample: snare }],
  index: 2,
};
d.chanSeqs[0].pages[0][0] = { on: false, len: 1, notes: [], locks: { 'mix.vol1': -12 } };
d.chanSeqs[1].pages[0][4] = { on: false, len: 1, notes: [], locks: { 'lim.ceiling': -3 } };
d.master['cmp.release'] = W.AUTO_VALUE;
d.master['lim.ceiling'] = -2;
d.satBypass = true;
d.outVol = -60;
d.fxAssigns = { 'rev.size': { lfo: 1, amount: 0.3, track: 2 } };
d.scenes[1] = { name: 'DROP', repeats: 4 };
d.rows = 3;
d.arrStart = 1;
d.arrEnd = 'stop';
d.plusMode = 'empty';
d.rowLoop = false;
d.arrowMode = 'switch';
d.files = { [kick]: 'kick.wav', [snare]: 'snare.wav' };
d.roots = { [kick]: 36 };

const doc = W.normalizeDoc(JSON.parse(JSON.stringify(d)));
const samples = [
  { key: kick, name: 'kick.wav', bytes: kickBytes },
  { key: snare, name: 'snare.wav', bytes: snareBytes },
  { key: table, name: 'table.wav', bytes: tableBytes },
];
const blob = W.packProject('Web Jam', doc, samples);
const out = path.join(here, 'web_project.jambo');
fs.writeFileSync(out, Buffer.from(await blob.arrayBuffer()));
fs.rmSync(tmp, { recursive: true, force: true });
console.log(`${out}: ${fs.statSync(out).size} bytes; kick ${kick}, snare ${snare}, table ${table}`);
