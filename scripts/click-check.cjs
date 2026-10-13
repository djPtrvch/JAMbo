// Поиск щелчков и треска: приложение в Chromium (vite dev), выход записывается AudioWorklet-отводом
// перед destination, детектор ищет одиночные скачки второй разности сигнала (в 6 раз выше 97-го
// перцентиля окна ±4096 отсчётов) и размечает их: начало ноты по сетке, живая нота, отпускание, вне событий.
// Запуск: npx vite --port 5199, затем node scripts/click-check.cjs 5199 [engines|fx|SAMPLE|ONSET|имя сценария].
// Нужен playwright (глобально или в node_modules) и Chromium.
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const PORT = process.argv[2] || '5199';
const ONLY = process.argv[3] || '';

const init = () => {
  const mod = `class Rec extends AudioWorkletProcessor {
    constructor(){ super(); this.on=false; this.L=new Float32Array(4096); this.R=new Float32Array(4096); this.n=0;
      this.port.onmessage=(e)=>{ this.on=e.data; this.n=0; }; }
    process(inp){ const a=inp[0]; if(this.on && a && a[0]){ const l=a[0], r=a[1]||a[0];
      this.L.set(l,this.n); this.R.set(r,this.n); this.n+=l.length;
      if(this.n>=4096){ this.port.postMessage([this.L.slice(),this.R.slice()]); this.n=0; } } return true; } }
    registerProcessor('rec-tap', Rec);`;
  const url = URL.createObjectURL(new Blob([mod], { type: 'application/javascript' }));
  window.__rec = { L: [], R: [], node: null, pending: [] };
  const orig = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    if (dest instanceof AudioDestinationNode && !this.__tap) {
      const ctx = this.context, src = this;
      if (!ctx.__recReady) {
        ctx.__recReady = ctx.audioWorklet.addModule(url).then(() => {
          const n = new AudioWorkletNode(ctx, 'rec-tap', { numberOfInputs: 1, numberOfOutputs: 1, channelCount: 2, channelCountMode: 'explicit' });
          n.__tap = true;
          n.port.onmessage = (e) => { window.__rec.L.push(e.data[0]); window.__rec.R.push(e.data[1]); };
          orig.call(n, ctx.destination);
          window.__rec.node = n;
          return n;
        });
      }
      ctx.__recReady.then((n) => orig.call(src, n));
    }
    return orig.call(this, dest, ...rest);
  };
};

(async () => {
  const b = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1194, height: 790 } });
  p.on('pageerror', (e) => console.log('ERR', e.message));
  p.on('console', (m) => { if (m.type() === 'error' && !/audio device/.test(m.text())) console.log('CERR', m.text()); });
  await p.addInitScript(init);
  await p.goto(`http://localhost:${PORT}/`);
  await p.mouse.click(600, 400);
  await p.waitForTimeout(2500);
  const res = await p.evaluate(async (ONLY) => {
    const S = await import('/src/state.ts');
    const E = await import('/src/audio/engine.ts');
    const T = await import('/src/transport.ts');
    const ST = await import('/src/settings.ts');
    const P = await import('/src/params.ts');
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    window.__dump = false;
    E.unlockAudio();
    await sleep(500);
    const R = window.__rec;
    const sr = R.node.context.sampleRate;

    function detect(x) {
      const n = x.length, B = 32, nb = Math.floor(n / B);
      const bm = new Float32Array(nb), lv = new Float32Array(nb);
      for (let b = 0; b < nb; b++) {
        let m = 0, s = 0;
        for (let i = b * B; i < (b + 1) * B; i++) {
          if (i < 2) continue;
          const d = Math.abs(x[i] - 2 * x[i - 1] + x[i - 2]);
          if (d > m) m = d;
          s += x[i] * x[i];
        }
        bm[b] = m; lv[b] = Math.sqrt(s / B);
      }
      const flags = [];
      const W = 128;
      for (let b = W; b < nb - W; b++) {
        if (bm[b] < 2e-3) continue;
        const win = [];
        for (let k = b - W; k <= b + W; k++) if (Math.abs(k - b) > 3) win.push(bm[k]);
        win.sort((a, c) => c - a);
        const ref = win[Math.floor(win.length * 0.03)];
        if (bm[b] > 6 * ref) {
          // Уровень до блока (20 мс): из тишины — это начало ноты, не щелчок.
          let pre = 0; for (let k = b - 30; k < b - 1; k++) pre = Math.max(pre, lv[k]);
          flags.push({ t: +(b * B / sr).toFixed(3), d: +bm[b].toFixed(4), ref: +ref.toFixed(4), pre: +pre.toFixed(4) });
          b += 4;
        }
      }
      return flags;
    }
    const cat = (arr) => { const n = arr.reduce((a, c) => a + c.length, 0); const o = new Float32Array(n); let k = 0; for (const c of arr) { o.set(c, k); k += c.length; } return o; };

    async function record(ms, during) {
      R.L = []; R.R = [];
      R.node.port.postMessage(true);
      window.__t0 = performance.now(); window.__ev = [];
      await during(ms);
      R.node.port.postMessage(false);
      await sleep(100);
      const L = cat(R.L), Rr = cat(R.R);
      let peak = 0; for (const v of L) peak = Math.max(peak, Math.abs(v));
      let peakR = 0; for (const v of Rr) peakR = Math.max(peakR, Math.abs(v));
      window.__dbg = { peakR, sample: S.doc.tracks[0].sample, state: R.node.context.state, n: R.L.length };
      const fl = detect(L).concat(detect(Rr));
      const real = fl.filter((f) => f.pre > 1e-3);
      if (real.length && window.__dump) { const i0 = Math.round(real[0].t * sr); window.__seg = Array.from(Rr.slice(i0 - 8, i0 + 56)).map((v) => +v.toFixed(4)); }
      // Разметка флагов: начало ноты по сетке шагов, живая нота, отпускание, иначе — вне событий.
      const evs = window.__ev; const cls = { grid: 0, live: 0, release: 0, other: [] };
      for (const f of real) {
        const t = f.t * 1000;
        const near = (k) => evs.some((e) => e.k === k && t >= e.t - 8 && t <= e.t + 30);
        const gp = evs.find((e) => e.k === 'play');
        const g = gp ? ((t - gp.t) % 125 + 125) % 125 : 999;
        if (gp && t >= gp.t - 8 && (g < 30 || g > 117) && !evs.some((e) => e.k === 'stopgrid' && t > e.t)) cls.grid++;
        else if (near('live')) cls.live++;
        else if (near('rel')) cls.release++;
        else cls.other.push(f);
      }
      return { cls: { grid: cls.grid, live: cls.live, release: cls.release, other: cls.other.length, ex: cls.other.slice(0, 3) }, seg: window.__dump ? window.__seg : undefined, dbg: window.__dbg, secs: +(L.length / sr).toFixed(2), peak: +peak.toFixed(3), clicks: real.length, onsets: fl.length - real.length, ex: real.slice(0, 4) };
    }

    function reset() {
      T.setPlaying(false);
      const t = S.doc.tracks[0];
      S.doc.tracks.forEach((tr) => { tr.mute = false; tr.solo = false; tr.pages = [S.emptyPage()]; tr.length = 16; tr.playFrom = 0; tr.playTo = 0; });
      Object.assign(t.params, { attack: 5, decay: 300, reverb: 0, delay: 0, drive: 0, level: 127, filter: 0, reso: 0, pan: 0 });
      t.assigns = {};
      S.doc.bpm = 120;
    }
    function pattern(t, notes) {
      t.pages = [S.emptyPage()];
      notes.forEach((n, k) => { if (!n) return; const s = t.pages[0][k]; s.on = true; s.notes = Array.isArray(n) ? n : [n]; if (k === 4) s.len = 3; });
    }
    const PAT = [48, 0, 55, [48, 52, 55], 60, 0, 64, 59, [52, 59, 64], 0, 67, 62, 48, 55, [60, 64, 67], 72];

    const out = {};
    const engines = P.SYNTH_ENGINES.map((e, k) => [k, e.name]);
    for (const [k, name] of engines) {
      const key = 'E' + k + ' ' + name;
      if (ONLY && !key.includes(ONLY) && ONLY !== 'engines') continue;
      if (ONLY && ONLY !== 'engines' && !key.includes(ONLY)) continue;
      reset();
      S.setTrackSynth(0, k);
      const t = S.doc.tracks[0];
      t.params.harm = 50; t.params.timbre = 50; t.params.morph = 50;
      pattern(t, PAT);
      await sleep(300);
      out[key] = await record(4200, async (ms) => {
        const ev = (k) => window.__ev.push({ k, t: performance.now() - window.__t0 });
        ev('play'); T.setPlaying(true);
        await sleep(2200);
        T.setPlaying(false); ev('stopgrid');
        await sleep(200);
        // Живые ноты: зажали и отпустили.
        for (const n of [60, 64, 67, 72]) { ev('live'); E.playNow(0, [n], true); await sleep(180); ev('rel'); E.releaseLive(0, [n]); await sleep(120); }
        await sleep(ms - 2200 - 1200);
      });
      T.setPlaying(false);
      await sleep(400);
    }

    // Эффекты: синус ANALOG (WAVE 0) и длинные ноты.
    async function fxRun(name, setup, tick, every = 200) {
      if (ONLY && ONLY !== 'fx' && !name.includes(ONLY)) return;
      reset();
      S.setTrackSynth(0, 17);
      const t = S.doc.tracks[0];
      t.params.harm = 0; t.params.timbre = 0; t.params.morph = 0;
      t.params.attack = 10; t.params.decay = 1500;
      pattern(t, [48, 0, 0, 0, 55, 0, 0, 0, 52, 0, 0, 0, 60, 0, 0, 0]);
      t.pages[0][0].len = 4; t.pages[0][8].len = 4; t.pages[0][4].len = 1;
      setup(t);
      await sleep(400);
      out[name] = await record(4000, async (ms) => {
        T.setPlaying(true);
        let k = 0; const end = performance.now() + ms;
        while (performance.now() < end) { await sleep(every); if (tick) tick(t, k++); }
      });
      T.setPlaying(false);
      await sleep(300);
    }
    for (const atk of [10, 100]) for (const eng of [17, 0]) {
      const name = 'ONSET atk' + atk + ' eng' + eng;
      if (ONLY && !name.includes(ONLY)) continue;
      reset();
      S.setTrackSynth(0, eng); S.setTrackSynth(1, eng);
      for (const tr of [S.doc.tracks[0], S.doc.tracks[1]]) { Object.assign(tr.params, { harm: 0, timbre: 0, morph: 0, attack: atk, decay: 200, level: 127, filter: 0, pan: 0 }); }
      const a = S.doc.tracks[0]; a.pages = [S.emptyPage()]; a.pages[0][0].on = true; a.pages[0][0].notes = [48]; a.pages[0][0].len = 16; a.params.decay = 3000;
      const b2 = S.doc.tracks[1]; b2.pages = [S.emptyPage()]; [4, 8, 12].forEach((k) => { const st = b2.pages[0][k]; st.on = true; st.notes = [67]; });
      await sleep(300);
      out[name] = await record(2100, async (ms) => { T.setPlaying(true); await sleep(ms); });
      T.setPlaying(false); await sleep(300);
    }
    await fxRun('FX dry', () => {});
    await fxRun('FX reverb static', (t) => { t.params.reverb = 60; });
    await fxRun('FX reverb size changes', (t) => { t.params.reverb = 60; }, (t, k) => { S.doc.fx['rev.size'] = (k * 37) % 100; S.doc.fx['rev.decay'] = 1 + (k % 4); });
    await fxRun('FX delay static', (t) => { t.params.delay = 50; });
    await fxRun('FX delay time changes', (t) => { t.params.delay = 50; }, () => { S.doc.fx['dly.time'] = Math.floor(Math.random() * 8); }, 300);
    await fxRun('FX delay filter + spread changes', (t) => { t.params.delay = 50; }, (t, k) => { S.doc.fx['dly.filter'] = ((k * 53) % 200) - 100; S.doc.fx['dly.spread'] = (k * 37) % 100; S.doc.fx['dly.feedback'] = 60; }, 200);
    await fxRun('FX drive static', (t) => { t.params.drive = 60; });
    await fxRun('FX drive type changes', (t) => { t.params.drive = 60; }, (t, k) => { S.doc.fx['od.type'] = k % 6; S.doc.fx['od.drive'] = (k * 29) % 100; }, 150);
    await fxRun('FX drive + other fx edits', (t) => { t.params.drive = 60; }, (t, k) => { S.doc.fx['dly.feedback'] = 20 + (k % 5); }, 50);
    // Sidechain: дорожка 1 (синус, длинные ноты) приглушается тригами беззвучных дорожек 2 и 3 (16-е).
    const scSetup = (t) => {
      t.params.sidechain = 100;
      for (const k of [1, 2]) { S.setTrackSynth(k, 17); const u = S.doc.tracks[k]; u.params.level = 0; u.pages = [S.emptyPage()]; u.pages[0].forEach((st, j) => { if (j % (k + 1) === 0) { st.on = true; st.notes = [60]; } }); }
      S.doc.fx['sc.source'] = 1; S.doc.fx['sc.attack'] = 5; S.doc.fx['sc.release'] = 120;
    };
    await fxRun('FX sidechain static', scSetup);
    await fxRun('FX sidechain source + curve changes', scSetup, (t, k) => { S.doc.fx['sc.source'] = 1 + (k % 2); S.doc.fx['sc.curve'] = (k * 41) % 100; }, 230);
    await fxRun('FX sidechain sends toggles', (t) => { scSetup(t); t.params.drive = 60; t.params.reverb = 40; t.params.delay = 40; }, (t, k) => {
      const v = k % 2 === 0; ST.saveSettings({ scSends: { rev: v, dly: v, drv: v } }); E.applySidechainSends();
    }, 170);
    await fxRun('FX mute toggles', (t) => { t.params.reverb = 30; }, (t, k) => { S.swipeTrack(0, 'down'); }, 250);
    await fxRun('FX all sends', (t) => { t.params.reverb = 40; t.params.delay = 40; t.params.drive = 40; });

    // Сэмпл без синта: синус 220 Гц с гармониками, конец не в нуле; End 70 %.
    async function sampleRun(name, setup) {
      if (ONLY && ONLY !== 'sample' && !name.includes(ONLY)) return;
      reset();
      const n = Math.round(sr * 1.0), buf = new ArrayBuffer(44 + n * 2), dv = new DataView(buf);
      const w = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
      w(0, 'RIFF'); dv.setUint32(4, 36 + n * 2, true); w(8, 'WAVE'); w(12, 'fmt '); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
      dv.setUint32(24, sr, true); dv.setUint32(28, sr * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true); w(36, 'data'); dv.setUint32(40, n * 2, true);
      for (let i = 0; i < n; i++) { const tt = i / sr; const v = 0.5 * Math.sin(2 * Math.PI * 220 * tt) + 0.2 * Math.sin(2 * Math.PI * 440 * tt + 1); dv.setInt16(44 + i * 2, Math.round(v * 32000), true); }
      S.ui.selectedTrack = 0;
      await E.loadSampleFiles([new File([buf], 'sine.wav', { type: 'audio/wav' })]);
      await sleep(500);
      const t = S.doc.tracks[0];
      Object.assign(t.params, { attack: 5, decay: 300 });
      pattern(t, PAT);
      setup(t);
      await sleep(300);
      out[name] = await record(4000, async (ms) => { T.setPlaying(true); await sleep(ms); });
      T.setPlaying(false);
      await sleep(300);
    }
    await sampleRun('SAMPLE decay 300', () => {});
    await sampleRun('SAMPLE decay 2000', (t) => { t.params.decay = 2000; });
    await sampleRun('SAMPLE end 70%', (t) => { t.params.end = 70; t.params.decay = 4000; });
    await sampleRun('SAMPLE + reverb size changes', (t) => { t.params.reverb = 60; t.params.decay = 1500; });

    // Автоматизация (этап 6): кривые с резкими перепадами на Filter, Level, Pan и ручках движков —
    // значения идут в звук по расписанию каждые 5 мс, щелчков быть не должно.
    const AP = [{ x: 0, y: 0.15, type: 'smooth' }, { x: 3, y: 0.95, type: 'smooth' }, { x: 7, y: 0.05, type: 'linear' }, { x: 11, y: 0.8, type: 'smooth' }, { x: 16, y: 0.15, type: 'smooth' }];
    const half = AP.map((q) => ({ ...q, y: q.y * 0.5 }));
    await fxRun('AUTO filter ANALOG saw', (t) => { t.params.harm = 62.5; t.params.reso = 40; t.auto = [{ param: 'filter', points: half }]; });
    await fxRun('AUTO level + pan + sends', (t) => { t.params.reverb = 30; t.auto = [{ param: 'level', points: AP }, { param: 'pan', points: AP }, { param: 'delay', points: AP }]; });
    await fxRun('AUTO FM index + contour', (t) => { S.setTrackSynth(0, 18); t.auto = [{ param: 'timbre', points: AP }, { param: 'morph', points: AP }]; });
    await fxRun('AUTO plaits VA harm + timbre', (t) => { S.setTrackSynth(0, 0); t.auto = [{ param: 'harm', points: AP }, { param: 'timbre', points: AP }]; });
    await sampleRun('SAMPLE + AUTO filter', (t) => { t.params.decay = 1500; t.auto = [{ param: 'filter', points: half }]; });
    return out;
  }, ONLY);
  for (const [k, v] of Object.entries(res)) console.log(k.padEnd(30), JSON.stringify(v));
  await b.close();
})();
