# Handoff: JAMbo, Swift-версия — S3a (Plaits)

Ветка `swift`, проект `ios/JAMbo.swiftpm`. Перед работой прочитать `CLAUDE.md`, `ios/CLAUDE.md` (раздел S3a — подробности и цифры сверки), `docs/ai/synth-engines.md`.

## 1. Текущая веха
S3a — Plaits: 8 движков, голоса синта в звуке, меню MI SYNTH, окно синта, SELF-TEST. Задача #37 (перенос 8 движков с тестами) закрыта; следующая — #38 (голос синта).

## 2. Что уже сделано
- stmlib и каркас Plaits; таблицы и эталоны (48 случаев: 8 движков × 3 набора × 2 ноты) из `public/plaits.wasm`.
- Движки 0–7 перенесены 1:1 по `wasm/plaits/.src` (eurorack `08460a6`, stmlib `e3bd7c9`): VA, WAVESHAPE, FM, GRAIN, ADDITIVE, WAVETABLE, CHORDS, SPEECH; у каждого тест по 6 эталонам.
- SELF-TEST в DIAGNOSTICS (RUN SELF-TEST, таблица 48 строк). Проверено на iPad: 48/48 PASS, 12,5 с, цифры совпадают с Linux.
- CoreTests на Linux: 63 теста, все проходят (`. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`).
- Контроль размера CLAUDE.md: хук PostToolUse `.claude/hooks/check-claude-md.sh` (120 строк — предупреждение, 150 — остановка), раздел «Управление документацией» в CLAUDE.md.
- #38: голоса синта (Core/Synth/SynthVoices, 6 на дорожку), звук «mi:<n>» у дорожки и шага, меню MI SYNTH и сетка ручек движка; 10 тестов синта.

## 3. Какие файлы изменены
- `ios/JAMbo.swiftpm/Core/Plaits/`:
  - `stmlib/` — StmlibDSP, StmlibFilter;
  - `dsp/` — PlaitsEngine, PlaitsResources (a0 — поле; таблицы Formant и SAM);
  - `dsp/oscillator/` — Oscillator, VariableShape, VariableSaw, Grainlet, Z, Harmonic, Wavetable, WavetableTools, StringSynth;
  - `dsp/downsampler/Downsampler.swift`, `dsp/chords/ChordBank.swift`;
  - `dsp/speech/` — NaiveSpeechSynth, SAMSpeechSynth, LPCSpeechSynth, LPCSpeechSynthController;
  - `dsp/engine/` — 8 движков;
  - `PlaitsSelfTest.swift` — сверка с эталонами (общая для тестов и SELF-TEST).
- `ios/JAMbo.swiftpm/UI/SelfTestPanel.swift` (новый), `UI/DiagnosticsView.swift`.
- `ios/JAMbo.swiftpm/Resources/plaits/` — добавлены `naive_phonemes.u8`, `sam_phonemes.u8`, `sam_formant_amplitude.f32`.
- `ios/tools/plaits/export_tables.sh`, `export_tables.cc` — выгрузка таблиц Formant и SAM.
- `ios/CoreTests/Tests/CoreTests/PlaitsGolden.swift`, `PlaitsEngineTests.swift`.
- `ios/CLAUDE.md` — раздел S3a; этот файл перенесён из `docs/HANDOFF.md`.

## 4. Какие решения приняты
- a0 = (440/8)/48000 без сдвига ноты (вариант A). a0 — поле `PlaitsResources` (по умолчанию `plaitsA0`). Тесты и SELF-TEST ставят a0 веба (по 47872,34 Гц) и сдвигают ноту на 12·log2(47872,34/48000), считая сдвиг в Double, как JS. `kCorrectedSampleRate` оставлен для LPC.
- Критерий сверки: по отсчётам ≤ −60 dB ИЛИ третьоктавные полосы 20 Hz–20 kHz ±0,5 dB; плюс страховка — по отсчётам не хуже −40 dB, без NaN, не тишина.
- VA — только `VA_VARIANT 2`. CHORDS — без `JON_CHORDS` (11 аккордов). GRAIN — без VOSIM, как в оригинале.
- SPEECH без Words: HARMONICS ограничен group ≤ 2 (Formant 0, Phoneme 1/6, LPC 1/3); банк слов не перенесён.
- Шаблонные флаги C++ — параметры Bool встроенных функций. Деструктор ParameterInterpolator — явная запись `value` обратно.
- Колбэк не читает Swift-массивы: таблицы движков копируются в указатели в init; рабочие буферы выделяются в init.
- `StmRandom` передаётся движку в init (SPEECH); начальное состояние 0x21.
- Литералы длиннее ~100 элементов — в `Resources/plaits` через `export_tables.sh`.
- Усиления OUT/AUX движков (< 0 — лимитер) — как в `wasm/plaits/jambo_voices.cc`; сейчас таблица в `PlaitsSelfTest`, для голоса — в обёртке #38.
- SELF-TEST ищет таблицы и эталоны в bundle по имени файла (в корне или в подпапках `plaits`, `golden`).
- Архив `JAMbo.swiftpm.zip` в репозиторий не кладём. Весь проект — `https://github.com/djptrvch/jambo/archive/refs/heads/swift.zip`.

## 5. Известные ошибки и предупреждения
- `public/plaits.wasm` собран с `-O3 -ffast-math`, поэтому бит в бит совпадения нет. FM `e2_s1_n48` — −52,9 dB по отсчётам (PASS по полосам, 0,004 dB); WAVESHAPE на ноте 64 — −73…−77 dB. Проверено и не причина: порядок множителей фазы, (pm + 32)·scale в SinePM, 1/size в ParameterInterpolator.
- Ошибки оригинала, обойденные при переносе:
  - WAVETABLE: `wave_map_` выделен на 64 указателя, а пишется 256 — у нас 256.
  - LPC: за последним кадром фонем читается кадр за краем с весом 0 — у нас тот же кадр.
  - SPEECH с пустыми банками слов: отрицательный индекс кадра — ветка закрыта.
- Нагрузка CPU голосов синта в отладочной сборке Playgrounds неизвестна (в S2 отладочная сборка была в ~12 раз медленнее релизной).
- Архив `ios/JAMbo.swiftpm.zip` (3,6 МБ) остался в истории git (коммит `a478002`, откат `2d3d29c`).
- Хуки `.claude/settings.json` читаются при старте сессии.

## 6. Что не сделано
- Окно синта с иконкой движка (вместо «No sample»); удержание окна у синта не открывает редактор (как в вебе).
- Меню MI SYNTH (кнопки VA … SPEECH сейчас серые), окно синта с иконкой движка, ручки HARMONICS / TIMBRE / MORPH.
- S3b: MI DRUMS (8 движков) и свои движки DRUM, ANALOG, FM, WTABLE.
- #39: жёлтая точка p-lock и рамка шага в секвенсоре. #40: плавная перетяжка миниатюр страниц.
- `docs/SWIFT_MILESTONE_S3.md` — после завершения вехи.

## 7. Точный следующий шаг
Проверка #38 на iPad (звук, ручки, CPU), затем план окна синта с иконкой — по docs/ai/synth-engines.md и src/ui/sample.ts, src/engineIcons.ts.
