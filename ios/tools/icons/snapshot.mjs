// Снапшот для глаз: превью-иконки Swift (EngineIcons, выгрузка теста testDumpForSnapshot) рядом с прототипом
// (docs/icons/prototype/engine-previews-prototype.html) на тех же ручках, тёмная и светлая темы.
// Запуск: node ios/tools/icons/snapshot.mjs [out.png] — нужны Swift (ios/tools/swift-env.sh) и Playwright с Chromium.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const out = path.resolve(process.argv[2] || path.join(os.tmpdir(), 'engine-icons-snapshot.png'));
const html = fs.readFileSync(path.join(root, 'docs/icons/prototype/engine-previews-prototype.html'), 'utf8');
const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const sandbox = { module: { exports: {} }, Math, Float32Array, Array, Object, String, parseInt, parseFloat };
vm.runInNewContext(script, sandbox);
const { ENGINES } = sandbox.module.exports;
const ID = { KICK: 16, SNARE: 20, HAT: 21, CLAP: 22, PERC: 23, ANALOG: 17, FM: 18, WTABLE: 19, SUB: 24 };

// Наборы: по умолчанию, 0, 1, смешанный и у ударных — подсветка удара в середине.
const rows = [];
for (const e of ENGINES) {
  if (ID[e.name] === undefined) continue;
  const def = e.knobs.map((k) => k.def).concat([e.decay ? e.decay.def : 0.5]);
  const sets = [[def, null], [[0, 0, 0, 0, 0], null], [[1, 1, 1, 1, 1], null], [[0.25, 0.75, 0.2, 0.6, 0.3], null]];
  if (e.kind === 'drum') sets.push([def, 30]);
  rows.push({ name: e.name, engine: ID[e.name], sets });
}
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'icons-'));
const dump = path.join(tmp, 'swift.json');
fs.writeFileSync(dump + '.in', JSON.stringify(rows.flatMap((r) => r.sets.map(([v, hx]) => ({ engine: r.engine, v, hx })))));
execSync('swift test --filter testDumpForSnapshot', { cwd: path.join(root, 'ios/CoreTests'), env: { ...process.env, ICON_DUMP: dump }, stdio: 'ignore' });
const swift = JSON.parse(fs.readFileSync(dump, 'utf8'));

const page = `<!doctype html><meta charset="utf-8"><style>
body{margin:0;padding:16px;font:600 11px system-ui,sans-serif;background:#888;display:flex;gap:16px}
.th{padding:12px;border-radius:12px}.dark{background:#111;color:#ececec}.light{background:#e6e5e1;color:#161616}
.row{display:flex;align-items:center;gap:6px;margin:4px 0}.nm{width:56px}.pair{display:flex;gap:2px;padding:3px;border-radius:8px}
.cell{width:96px;height:96px;border-radius:6px;position:relative}.cell span{position:absolute;left:4px;top:2px;font-size:8px;opacity:.5}
</style><body><script>
const swift=${JSON.stringify(swift)}, rows=${JSON.stringify(rows.map((r) => ({ name: r.name, sets: r.sets })))};
const src=${JSON.stringify(script)};
const sb={module:{exports:{}}}; (new Function('module', 'document', src))(sb.module, undefined); const ENG=sb.module.exports.ENGINES;
const THEMES={dark:{bg:'#1c1c1c',icon:'#e8e8e8',gray:'#6c6c72'},light:{bg:'#f7f6f3',icon:'#161616',gray:'#9b9aa0'}};
for (const [tn,t] of Object.entries(THEMES)) {
  const col=document.createElement('div'); col.className='th '+tn; document.body.appendChild(col);
  col.insertAdjacentHTML('beforeend','<div>'+tn+' · in each pair: prototype | Swift</div>');
  let k=0;
  for (const r of rows) {
    const row=document.createElement('div'); row.className='row'; row.innerHTML='<div class="nm">'+r.name+'</div>'; col.appendChild(row);
    const eng=ENG.find(e=>e.name===r.name);
    for (const [v,hx] of r.sets) {
      const pair=document.createElement('div'); pair.className='pair'; pair.style.background=t.bg; row.appendChild(pair);
      const cv=document.createElement('canvas'); cv.width=cv.height=192; cv.className='cell'; pair.appendChild(cv);
      const g=cv.getContext('2d'); g.setTransform(3,0,0,3,0,0); g.fillStyle=t.icon; g.strokeStyle=t.icon;
      eng.draw(g,v.slice(0,4),v[4],{T:1.3,hx,reduced:true,icon:t.icon,gray:t.gray,bg:t.bg,tA:0,tB:0,tm:1}); g.globalAlpha=1;
      const sc=document.createElement('canvas'); sc.width=sc.height=192; sc.className='cell'; pair.appendChild(sc);
      const s=sc.getContext('2d'); s.setTransform(3,0,0,3,0,0);
      for (const el of swift[k].els) {
        s.globalAlpha=el.a; s.fillStyle=el.ink==='s'?t.gray:t.icon; s.beginPath();
        for (const q of el.r) s.rect(q[0],q[1],q[2],q[3]);
        el.poly.forEach((p,i)=>i?s.lineTo(p[0],p[1]):s.moveTo(p[0],p[1]));
        if (el.text) { s.font='600 '+el.text[3]+'px ui-monospace,monospace'; s.textAlign='center'; s.fillText(el.text[0],el.text[1],el.text[2]); }
        else s.fill();
      }
      k++;
    }
  }
}
</script>`;
const pageFile = path.join(tmp, 'snapshot.html');
fs.writeFileSync(pageFile, page);
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'x'));
const { chromium } = require('playwright');
const browser = await chromium.launch();
const p = await browser.newPage({ viewport: { width: 2400, height: 1000 } });
p.on('pageerror', (e) => console.error(e.message));
await p.goto('file://' + pageFile);
await p.screenshot({ path: out, fullPage: true });
await browser.close();
console.log(out);
