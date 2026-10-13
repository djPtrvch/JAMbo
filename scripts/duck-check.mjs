// Офлайн-проверка огибающей sidechain (public/duck-worklet.js) в Node.
// Запуск: node scripts/duck-check.mjs
// Громкость приглушаемой дорожки = 1 − amount·e (здесь amount = 1).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SR = 48000;
const BLOCK = 128;
const ctx = {};
Object.assign(globalThis, {
  sampleRate: SR, currentFrame: 0,
  AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {}, onmessage: null }; } },
  registerProcessor(name, cls) { ctx.Proc = cls; },
});
const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'duck-')), 'w.mjs');
fs.writeFileSync(f, fs.readFileSync(new URL('../public/duck-worklet.js', import.meta.url), 'utf8'));
await import(pathToFileURL(f).href);

/** Рендер frames отсчётов; msgs — [{ at: кадр отправки, data }] (приходят перед блоком, где at). */
function render(frames, msgs = []) {
  const node = new ctx.Proc();
  const e = new Float32Array(frames);
  const out = [new Float32Array(BLOCK)];
  const list = [...msgs].sort((a, b) => a.at - b.at);
  for (let b = 0; b * BLOCK < frames; b++) {
    globalThis.currentFrame = b * BLOCK;
    while (list.length && list[0].at < (b + 1) * BLOCK) node.port.onmessage({ data: list.shift().data });
    node.process([], [out]);
    e.set(out[0].subarray(0, Math.min(BLOCK, frames - b * BLOCK)), b * BLOCK);
  }
  return e;
}
const trig = (frame, o = {}) => ({ at: Math.max(0, frame - 2048), data: { type: 'trig', frame, attack: 5, release: 150, curve: 50, ...o } });
const db = (g) => 20 * Math.log10(Math.max(1e-9, g));
const log = (s) => console.log(s);
const ms = (x) => Math.round((x / 1000) * SR);

// 1. Один триг: пик и возврат.
{
  const F = 4800;
  const e = render(SR, [trig(F, { attack: 5, release: 150 })]);
  let mn = 1; for (const v of e) mn = Math.min(mn, 1 - v);
  const end = F + ms(5) + ms(150);
  log(`Один триг (ATTACK 5 мс, RELEASE 150 мс): громкость в пике ${db(mn).toFixed(1)} dB; через ATTACK + RELEASE ${db(1 - e[end + 1]).toFixed(2)} dB (e = ${e[end + 1]})`);
}
// 2. Форма возврата: RELEASE 200 мс, через 100 мс после конца attack.
for (const curve of [50, 100, 0]) {
  const F = 4800;
  const e = render(SR, [trig(F, { attack: 1, release: 200, curve })]);
  const g = 1 - e[F + ms(1) + ms(100)];
  log(`CURVE ${curve}: громкость через 100 мс возврата ${g.toFixed(3)} (${db(g).toFixed(2)} dB)`);
}
// 3. ATTACK 5 мс — e на 2,5 мс; ATTACK 0,1 мс — длина нарастания.
{
  const F = 4800;
  const e = render(SR / 4, [trig(F, { attack: 5 })]);
  const e2 = render(SR / 4, [trig(F, { attack: 0.1 })]);
  let n = 0; for (let i = F; i < F + 1000 && e2[i] < 0.999; i++) n++;
  log(`ATTACK 5 мс: e на 2,5 мс = ${e[F + ms(2.5)].toFixed(3)}; ATTACK 0,1 мс: нарастание ${n + 1} отсчётов (${((n + 1) / SR * 1000).toFixed(2)} мс)`);
}
// 4. Повторный триг на середине спада (e ≈ 0.25), ATTACK 1 мс: наибольшее изменение громкости между отсчётами.
{
  const F = 4800, R = ms(200);
  const second = F + ms(1) + R / 2;
  const e = render(SR, [trig(F, { attack: 1, release: 200 }), trig(second, { attack: 1, release: 200 })]);
  let mx = 0; for (let i = F + ms(1) + 10; i < SR - 1; i++) mx = Math.max(mx, Math.abs(e[i + 1] - e[i]));
  let mx0 = 0; for (let i = second - 5; i < second + ms(1) + 5; i++) mx0 = Math.max(mx0, Math.abs(e[i + 1] - e[i]));
  log(`Повторный триг при e = ${e[second - 1].toFixed(3)}: нарастание с ${e[second].toFixed(3)}; наибольшее изменение громкости за отсчёт ${mx0.toFixed(4)} (на всём хвосте ${mx.toFixed(4)})`);
}
// 5. Точность: 4 трига 16-ми при 120 BPM (125 мс) — первый отсчёт подъёма против запланированного кадра.
{
  const frames = [10007, 10007 + 6000, 10007 + 12000, 10007 + 18000];
  const e = render(SR, frames.map((fr) => trig(fr, { attack: 1, release: 50 })));
  const off = frames.map((fr) => { let i = fr - 50; while (i < fr + 50 && !(e[i] > e[i - 1] + 1e-6)) i++; return i - fr; });
  log(`4 трига (16-е, 120 BPM): сдвиг подъёма от кадра ${off.join(', ')} отсчётов (подъём виден в отсчёте трига)`);
}
// 6. flush: два трига в очереди, flush после первого — второго нет, возврат доходит до 0.
{
  const F = 4800;
  // Оба трига уже в очереди (присланы заранее), flush — после начала первого.
  const second = { ...trig(F + ms(300)), at: 100 };
  const e = render(SR, [trig(F, { release: 100 }), second, { at: F + 600, data: { type: 'flush' } }]);
  let after = 0; for (let i = F + ms(300); i < SR; i++) after = Math.max(after, e[i]);
  log(`flush: после стопа e не выше ${after} (второй триг отменён); первый возврат до 0 — e через 110 мс ${e[F + ms(110)]}`);
}
// 7. Нагрузка: покой и непрерывные триги (16-е).
{
  const sec = 30;
  let t0 = performance.now(); render(SR * sec); const idle = (performance.now() - t0) / (sec * 10);
  const msgs = []; for (let k = 0; k < sec * 8; k++) msgs.push(trig(4800 + k * 6000, { release: 200 }));
  t0 = performance.now(); render(SR * sec, msgs); const busy = (performance.now() - t0) / (sec * 10);
  log(`Нагрузка: покой ${idle.toFixed(3)} %, триги 16-ми с RELEASE 200 мс ${busy.toFixed(3)} % одного ядра`);
}
