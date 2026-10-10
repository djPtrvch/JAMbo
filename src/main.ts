import './style.css';
import { advanceLfos, selTrack } from './state';
import { updateTransport } from './transport';
import { buildLeftButtons, buildRightButtons, renderButtons } from './ui/buttons';
import { h, setText } from './ui/dom';
import { buildKnobGrid, renderKnobs } from './ui/knobs';
import { buildPages, renderPages } from './ui/pages';
import { buildSequencer, renderSequencer } from './ui/sequencer';
import { buildTopbar, renderTopbar } from './ui/topbar';
import { buildTracks, renderTracks } from './ui/tracks';

const app = document.getElementById('app')!;

// Окно сэмпла — пока заглушка.
const sample = h('div', 'sample');
const sampleName = h('div', 'sample-name');
sample.append(h('div', 'sample-title', 'SAMPLE'), sampleName);

const left = h('div', 'side left');
left.append(sample, buildLeftButtons());

const right = h('div', 'side right');
right.append(buildPages(), h('div', 'spacer'), buildRightButtons());

const main = h('div', 'main');
main.append(left, buildKnobGrid(), right);

app.append(buildTopbar(), main, buildTracks(), buildSequencer());

// Блокируем системные жесты Safari (лупа, выделение, контекстное меню).
document.addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('gesturestart', (e) => e.preventDefault());

let last = performance.now();
function frame(now: number) {
  advanceLfos(Math.min(0.1, (now - last) / 1000));
  last = now;
  updateTransport(now);
  setText(sampleName, `${selTrack().name} — пусто`);
  renderTopbar();
  renderKnobs();
  renderTracks(now);
  renderSequencer();
  renderPages();
  renderButtons();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
