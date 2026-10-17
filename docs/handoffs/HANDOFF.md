# Handoff: JAMbo, Swift-версия — S3a (Plaits)

Ветка `swift`, проект `ios/JAMbo.swiftpm`. Перед работой прочитать `CLAUDE.md`, `ios/CLAUDE.md` (раздел S3a — подробности и цифры) и этот файл. Тесты: `ios/tools/install-swift-linux.sh` (один раз на контейнер), затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test` (74 теста). UI на Linux не собирается — проверяет пользователь на iPad (весь проект: https://github.com/djptrvch/jambo/archive/refs/heads/swift.zip).

## 1. Цель текущей задачи
Веха S3a — Plaits в Swift-версии: 8 движков MI SYNTH (VA, WAVESHAPE, FM, GRAIN, ADDITIVE, WAVETABLE, CHORDS, SPEECH) звучат на дорожках, меню MI SYNTH, окно синта с иконкой, SELF-TEST. Сейчас: проверка окна синта на iPad, затем план S3b.

## 2. Что уже реализовано
- Движки 0–7 перенесены 1:1 по `wasm/plaits/.src` (eurorack `08460a6`, stmlib `e3bd7c9`), у каждого тест по 6 эталонам (`Resources/golden`, 48 случаев).
- SELF-TEST в DIAGNOSTICS — проверено на iPad: 48/48 PASS, 12,5 с, цифры как на Linux.
- #38 голос синта — проверено на iPad: 6 голосов на дорожку, звук «mi:<n>» у дорожки и шага, меню MI SYNTH, ручки движка, пианоролл и секвенсор.
- Окно синта: MI · <движок>, живая иконка движка 0–7 (тест по эталону веба), полное имя, ручки 1.1–1.3. На iPad видна только иконка WAVESHAPE (мерцает при повороте ручек — как в вебе, оставлено); остальное не проверено.
- Контроль размера CLAUDE.md: хук PostToolUse `.claude/hooks/check-claude-md.sh` (120 строк — предупреждение, 150 — остановка), раздел «Управление документацией» в CLAUDE.md.

## 3. Изменённые файлы
- `ios/JAMbo.swiftpm/Core/Plaits/`: `stmlib/` (StmlibDSP, StmlibFilter), `dsp/` (PlaitsEngine, PlaitsResources — a0 поле, таблицы Formant и SAM), `dsp/oscillator/` (Oscillator, VariableShape, VariableSaw, Grainlet, Z, Harmonic, Wavetable, WavetableTools, StringSynth), `dsp/downsampler/`, `dsp/chords/ChordBank.swift`, `dsp/speech/` (Naive, SAM, LPC, LPC-контроллер), `dsp/engine/` (8 движков), `PlaitsSelfTest.swift`.
- `Core/Synth/`: SynthVoices (голоса), SynthEngineBank (движки голосов), SamplerSynth (связка с Sampler).
- `Core/Icons/EngineIcons.swift` — геометрия иконок 0–7.
- `Core/Model/SynthEngines.swift` (таблица движков, SynthKey, setSynth), `Core/Model/Params.swift` (synthColumn, synthGrids, grid(sound:), steps; подписи alt убраны).
- `Core/Sampler/`: SoundSnapshot (VoiceParam — 12, с harm, timbre, morph), Sampler (ноты синта — в SynthVoices), SamplerPreview (предпрослушка вынесена). `Core/Engine/AudioCore.swift` — installSynth.
- `UI/`: SoundMenu, AppModel, AppModelSound, AppModelEdits, SampleWindow, SynthWindow (новый), SelfTestPanel (новый), DiagnosticsView, Theme (токены accentText, icon).
- `Resources/plaits/`: naive_phonemes.u8, sam_phonemes.u8, sam_formant_amplitude.f32. `ios/tools/plaits/export_tables.*`, `ios/tools/icons/` (golden.mjs, engine_icons_golden.json).
- `ios/CoreTests/Tests/CoreTests/`: PlaitsGolden, PlaitsEngineTests, SynthTests, EngineIconTests.
- `.claude/hooks/check-claude-md.sh`, `.claude/settings.json`, `CLAUDE.md` (раздел «Управление документацией»), `ios/CLAUDE.md` (раздел S3a).

## 4. Принятые решения
- a0 = (440/8)/48000 без сдвига ноты; a0 — поле PlaitsResources. Тесты и SELF-TEST ставят a0 веба (47872,34) и сдвигают ноту на 12·log2(47872,34/48000) (в Double, как JS).
- Критерий сверки: по отсчётам ≤ −60 dB ИЛИ третьоктавы ±0,5 dB; страховка — по отсчётам не хуже −40 dB.
- VA — VA_VARIANT 2; CHORDS — без JON_CHORDS; GRAIN — без VOSIM; SPEECH без Words (group ≤ 2: Formant, Phoneme, LPC).
- Колбэк: без Swift-коллекций — таблицы копируются в указатели в init; движки голосов — указатели конкретных типов и switch; голоса синта ставятся один раз (AudioCore.installSynth).
- Голос синта как в вебе: Plaits — только триггер, accent 0,8; огибающая (Attack ≥ 2 мс, Decay как Release), Level, фильтр, Pan, микшер — как у сэмпла; кража слота — τ 1,5 мс, новая нота через 8 мс; тишина > 4800 отсчётов — голос замолкает. Усиления — SynthVoices.outGains/auxGains.
- Звук синта — «mi:<n>» (Track.sample, Step.sound); ручки harm, timbre, morph 0…100 (по умолчанию 50); Harmonics WAVETABLE, CHORDS, SPEECH — ступенчатая (steps, середина пункта).
- Иконки — геометрия в Core, формы 1:1 с вебом (без сглаживания — решение пользователя); тест по эталону из src/engineIcons.ts.
- Архив проекта в репозиторий не кладём. Markdown-документы: сначала путь, причина, точный текст — затем подтверждение пользователя.

## 5. Что осталось сделать
- Проверить окно синта на iPad: светлая тема, метка аккорда CHORDS (базовая линия подобрана на глаз), скачки WAVETABLE и SPEECH по пунктам.
- Нагрузка синта на iPad (индикатор CPU при аккордах) — записать в ios/CLAUDE.md.
- S3b: MI DRUMS (Plaits 8–15: у 11–15 Morph — Decay, ручка 1.3 — OUT→AUX, огибающая только с атакой), свои движки DRUM, ANALOG, FM, WTABLE, их иконки.
- Позже: посылы и FX (S4), MOD/LFO и иконка от модуляции (S4), пресеты и SAVE (S10), #39 (жёлтая точка p-lock и рамка шага), #40 (перетяжка миниатюр), docs/SWIFT_MILESTONE_S3.md в конце вехи.

## 6. Известные проблемы
- plaits.wasm собран с -O3 -ffast-math: бит в бит нет; FM e2_s1_n48 — −52,9 dB по отсчётам (PASS по полосам 0,004 dB), WAVESHAPE на ноте 64 — −73…−77 dB.
- Ошибки оригинала обойдены: WAVETABLE wave_map_ (64 указателя, пишется 256 — у нас 256), LPC — кадр за краем таблицы с весом 0, SPEECH — отрицательный индекс при пустых банках слов.
- Нагрузка синта (виртуалка, 48 голосов): релиз — 19 % ядра, отладка — 230 % (≈ 4,8 % на голос); сборка Playgrounds, возможно, отладочная.
- Хук CLAUDE.md — PostToolUse: правку не отменяет, только останавливает работу; хуки читаются при старте сессии.
- В истории git остался архив ios/JAMbo.swiftpm.zip (3,6 МБ, коммиты a478002 / 2d3d29c).

## 7. Точный первый шаг для новой сессии
Спросить пользователя о результате проверки окна синта на iPad (светлая тема, метка CHORDS, WAVETABLE и SPEECH). Если всё в порядке — показать план S3b по docs/ai/synth-engines.md, src/params.ts (SYNTH_ENGINES 8–19, synthParams) и src/audio/engine.ts (self-decay движки), код не менять до подтверждения.
