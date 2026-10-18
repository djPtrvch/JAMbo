# Аудит веб-версии JAMbo для Swift-переноса

Ветка `swift`, база — `stage-8`. Веб-версия — эталон поведения (заморожена: только исправления).
Объём веб-кода: ~24 200 строк (src/ — 16 000, public/ — worklet’ы 4 300, scripts/ — проверки 2 200).
Самые большие файлы: src/state.ts (3 308), src/audio/engine.ts (2 095), ui/eq.ts (737), ui/patterns.ts (681),
ui/auto.ts (644), ui/sampleedit.ts (633), params.ts (565), ui/sample.ts (571).

Решение: **П** — переносим, **О** — откладываем (после паритета, отдельным ТЗ), **Н** — не переносим.
Строки, помеченные ⚠, расходятся с ТЗ или в ТЗ не упомянуты. **Решение пользователя: переносим всё, что сделано в вебе** (кроме чисто браузерного — Н); вехи сверх ТЗ — S6–S13 (раздел 6).

## 1. Функции

### Звук: источники и голос

| Функция | Где в коде | Решение | Причина |
|---|---|---|---|
| Plaits, 16 движков | public/plaits-worklet.js, public/plaits.wasm, wasm/plaits/ (jambo_voices.cc, build.sh), params.ts SYNTH_ENGINES | П (S3a, S3b) | ТЗ 4 |
| SPEECH: Formant / Phoneme / LPC, harmPoints 0 / 1/6 / 1/3, без Words | params.ts (harmPoints), engine.ts synthParams, wasm/plaits/jambo_no_words.cc | П | ТЗ 4.4 |
| Миграция SPEECH (версия формата 2) | state.ts migrateSpeech, params.ts speechHarmV1 | П (S11) | нужна для IMPORT .jambo из веба |
| ⚠ Свои движки DRUM, ANALOG, FM, WTABLE (номера 16–19) | public/jambo-synth-worklet.js (546), audio/wavetable.ts (304), engineIcons.ts | П (S3b) | решение: переносим всё, что есть в вебе; чистый JS |
| ⚠ Таблицы WTABLE: встроенные 6 и свои WAV (clm, размер кадра) | audio/wavetable.ts, library.ts kind 'table', ui/browser.ts LOAD TABLE | П (S3b; свои WAV — через библиотеку S11) | |
| Сэмплер: Start/End, Pitch, Attack/Decay, удержание длинных нот, legato | engine.ts triggerTrack, legatoCut, holdEnd | П (S2) | ТЗ 5.1 |
| Определение высоты сэмпла (YIN, только индикация) | audio/pitch.ts | П (S2) | маленький, показывается в окне сэмпла |
| Голос: Attack/Decay → Level → фильтр LP/HP + Reso → Pan; посылы | engine.ts triggerTrack, applyFilter | П (S2) | ТЗ 5.2 |
| Смена звука на держащихся нотах (retrigger, кроссфейд ~3 мс) | engine.ts retrigger, fadeVoice | П (S2/S3) | поведение веба |
| Лимит голосов (64 сэмпла, 6 голосов синта, гашение за 5 мс) | engine.ts MAX_VOICES, plaits-worklet.js | П | |

### Звук: эффекты, микшер, мастер

| Функция | Где в коде | Решение | Причина |
|---|---|---|---|
| ⚠ Reverb: FDN на 8 линиях, SIZE / DECAY / TONE / LOW CUT, pre-delay | public/reverb-worklet.js (369) | П 1:1 по worklet | в ТЗ 5.3 описан как новый (вместо свёртки), а в вебе он уже FDN — переносим тот же алгоритм, сравнение на слух не нужно |
| ⚠ Delay: ленточный, TIME / FEEDBACK / FILTER / SPREAD | public/delay-worklet.js (293) | П 1:1 | в ТЗ 5.3 параметры прежние (hpf, stereo); в вебе уже FILTER и SPREAD |
| ⚠ Drive: 6 типов, 4× оверсэмплинг, LOW CUT, TONE | public/drive-worklet.js (429), public/oversampler.js | П 1:1 | в ТЗ «drive-шина» — в списке «не реализованных в вебе», но она есть |
| ⚠ Sidechain: огибающая с CURVE, глубина по дорожкам, приглушение посылов | public/duck-worklet.js, engine.ts sidechain | П 1:1 | в ТЗ «новая sidechain» — в «не реализованных», но она есть |
| Переключатели SIDECHAIN SENDS (REV / DLY / DRV) | settings.ts scSends, ui/settings.ts | П | маленькие |
| MUTE TAILS | engine.ts, settings.ts muteTails | П | |
| Микшер: громкости дорожек −∞…0 dB, mute/solo с гейтами | engine.ts tracks[i].gate, state.ts | П (S2) | |
| EQ дорожек и мастера: 8 полос, bell / cut 12-24-48 / shelf / notch | audio/eq.ts (279), ui/eq.ts (737) | П (S5) | свои биквады по RBJ (ТЗ 5.2) |
| EQ: Dynamic, Mid/Side | public/eqdyn-worklet.js, audio/eq.ts | П (S7) | решение: всё из веба |
| EQ: пресеты EQ | ui/eq.ts PRESETS, localStorage | П (S7) | |
| Пресеты модулей мастера (PRESETS в окнах SAT / COMP / CLIP / LIM, как у EQ) | — (нет в вебе) | Н (S6) | решение пользователя |
| EQ: спектр до/после, спектр мастера | ui/eq.ts, AnalyserNode | П (S5) | свой FFT (Accelerate vDSP с запасным вариантом) |
| Мастер: сатуратор (DRIVE, TYPE, TONE, MIX, FOCUS), glue (+ RATIO, KNEE, SC HPF, MIX), клиппер (INPUT, CEILING, SOFTNESS, BASS), лимитер (INPUT, CEILING, LOOKAHEAD, RELEASE); без BIAS, OUTPUT, AUTO, RANGE, HOLD, LINK, MIX клиппера, UNITY, AUDIT, SCALE (48 dB) — решение пользователя | public/saturator-, glue-, clipper-, limiter-worklet.js, oversampler.js | П упрощённо (S5a) | ТЗ 5.5 |
| Bypass модулей мастера (SHIFT + кнопка) | ui/buttons.ts, engine.ts | П (S5) | |
| ⚠ Графические окна SAT / COMP / CLIP / LIM | ui/saturator.ts, comp.ts, clipper.ts, limiter.ts, masterwin.ts (~1 800 строк) | П (S6) | до S6 параметры без ручек (BIAS, KNEE, LINK…) — значения по умолчанию |
| Индикация мастера COMP / CLIP / LIM (LevelBars) | ui/dynamics.ts | П (S5) | ТЗ 1.2 |
| Измеритель справа: пик, LUFS BS.1770, громкость выхода | ui/meter.ts, engine.ts Meter | П (S5) | |
| Скоп мастера: гониометр, осциллоскоп, точки съёма | ui/scope.ts, engine.ts | П (S5) | |
| Метры в MIX у ручек | ui/knobs.ts | П (S5) | |

### Секвенсор, модуляция, сетка

| Функция | Где в коде | Решение | Причина |
|---|---|---|---|
| Транспорт, свинг, ratchet, chance, метроном | transport.ts (377), tempoSource.ts, tempo.ts | П (S1), sample-accurate | ТЗ 3.4 |
| TempoSource / InternalTempoSource | tempoSource.ts (84) | П (S1) | ТЗ 3.4 |
| Полоса фазы под BPM, SYNC QUANTUM | ui/topbar.ts, settings.sync.quantum | П (S1) | без MIDI-клока |
| Страницы (до 8), длина паттерна, перенос страниц, меню страниц | ui/pages.ts (313), state.ts | П (S1) | |
| P-lock, свой звук шага (soundLocks), SHIFT + двойной тап | state.ts, ui/sequencer.ts, ui/knobs.ts | П (S1/S2) | |
| ⚠ Пианоролл: гамма, 1–2 октавы, CHORD, прогрессии, VELOCITY | ui/piano.ts (272), params.ts PROGRESSIONS, SCALES | П (S1) | в ТЗ не упомянут, но без него нет ввода нот |
| ⚠ Запись нот с REC: QUANTIZE, OVERDUB, дубль — один UNDO | state.ts recordNotes, transport.ts recStep, settings.record | П (S1) | в ТЗ не упомянута |
| UNDO / REDO | state.ts edit, beginGesture (снимки JSON) | П (S1) | в Swift — снимки Codable-модели или команды (см. раздел 3) |
| MORPH и сброс MORPH + UNDO | state.ts trackEdit, trackOrig | П (S4) | |
| ⚠ Сетка паттернов: 16 строк, окно 8, стрелки ▲ ▼ (VIEW / SWITCH), LOOP ROW, повторы, START FROM ROW, AT THE END, + ADDS | ui/patterns.ts (681), state.ts, transport.ts | П (S1) | в ТЗ — 8×8; в вебе уже 16 строк |
| Клипы: гамма, нота, FX у клипа; страницы у дорожки | state.ts clipView, activateSlot | П (S1) | |
| Дорожки 8–16: ADD, COPY, PASTE, DELETE, RENAME, перестановка | state.ts, ui/knobs.ts (MIX) | П (S1/S2) | |
| Mute / solo свайпом и кнопками M S в MIX | ui/tracks.ts, ui/knobs.ts | П (S1/S2) | |
| MOD: LFO1–3, ENV (ADSR), назначение, кольца, миниатюры | state.ts, ui/knobs.ts, ui/sample.ts renderLfo, renderEnv | П (S4) | ТЗ 6.2 |
| FX/MOD toggle (SHIFT + двойной тап) | ui/buttons.ts, settings.latch | П (S4) | |
| ⚠ Автоматизация (окно AUTO, запись с REC, LINE/SPLINE, SIMPLIFY) | automation.ts (210), ui/auto.ts (644), state.ts, engine.ts scheduleVoice | П (S13) | |
| Свои последовательности MIX и MST (p-lock громкостей) | state.ts SEQ_MIX, SEQ_MST, transport.ts | П (S5) | |

### Сэмплы, окно сэмпла, редактор

| Функция | Где в коде | Решение | Причина |
|---|---|---|---|
| Окно сэмпла: волна, Start/End, имя, нота, ST/M, иконка синта, кадр WTABLE | ui/sample.ts (571), ui/engineIcon.ts, engineIcons.ts | П (S2/S3) | |
| Меню звука: SYNTH / MI SYNTH / MI DRUMS, LOAD, SAVE, TABLE, SAMPLER | ui/sample.ts | П, LOAD — fileImporter | ТЗ 6.5 |
| Папка звуков дорожки, стрелки ◀ ▶, звук шага стрелками | state.ts folders, stepFolder | П (S2) | ТЗ 6.5: у дорожки своя папка |
| Редактор: TRIM, NORMALIZE, MONO, ▶, CLEAR | ui/sampleedit.ts | П (S2) | ТЗ 1.2 |
| ⚠ Редактор: масштаб и прокрутка, маркеры нарезки (slice) с нотами, SLICE NOTES, полоса воспроизведения | ui/sampleedit.ts, state.ts sliceMarks, engine.ts | П (S2) | |
| ⚠ REC в редакторе (вход, дорожка, мастер, 60 с) | ui/sampleedit.ts, engine.ts startCapture | П (S11) | вход — AVAudioSession, дорожка и мастер — из колбэка |
| ⚠ Запись стемов и мастера (● в MIX, RECORDINGS) | stems.ts (176), engine.ts startStem, public/stem-worklet.js | П (S11) | |
| Пресеты синта (SAVE / LOAD) | state.ts presets, library.ts | П (S3; папки — S11) | |
| Библиотека с папками, ZIP, EXPORT / IMPORT, предпрослушка, RECORDINGS | library.ts, libio.ts, zip.ts, ui/browser.ts (458) | П (S11) | файлы приложения + «Файлы» (fileImporter / fileExporter) |

### Проекты, настройки, прочее

| Функция | Где в коде | Решение | Причина |
|---|---|---|---|
| Проекты: NEW, SAVE, SAVE AS, RENAME, DELETE, список, Autosave | project.ts, storage.ts (IndexedDB), ui/projects.ts | П (S9), JSON + FileManager | ТЗ 6.3 |
| EXPORT / IMPORT .jambo | project.ts, libio.ts | П (S11) | перенос проектов из веба на iPad |
| Переход MIX между проектами (PREV, кроссфейдер) | state.ts, ui/patterns.ts | П (S10) | |
| Темы SYSTEM / LIGHT / DARK | ui/theme.ts, style.css токены | П (S1) | |
| SETTINGS: SAMPLE RATE, BUFFER SIZE | settings.ts, ui/settings.ts | Н | всегда 48 кГц (ТЗ 3.1), буфер — система |
| SETTINGS: OUTPUT / вход, BACKGROUND AUDIO | settings.ts, ui/settings.ts | П, если Playgrounds даст (вход — S11, фон — capability «Background Modes: Audio» в S0 проверить) | |
| SETTINGS: RECORD, SAMPLER (SLICE NOTES), SIDECHAIN, SCALE | ui/settings.ts | П вместе со своими функциями | |
| MIDI: устройства, маппинг, LEARN, MIDI MAP, Twister, ноты | midi.ts (582), ui/midi.ts, ui/learn.ts, ui/mapedit.ts | П (S12, CoreMIDI) | |
| SYNC: MIDI-клок SEND / RECEIVE, офсеты, настройки Link | sync.ts, ui/sync.ts | П (S12) | Link — этап 9 по CLAUDE.md |
| Экран отладки (задержки) | ui/debug.ts | Н | специфика браузера; CPU-индикатор остаётся |
| PWA, HTML-аудиоэлемент для Safari, скрытие при неверном масштабе | main.ts | Н | ТЗ 1.2 |
| Прокрутка меню своей полосой | ui/scrollbar.ts | Н | в SwiftUI ScrollView |

## 2. Мёртвый код и дубли

Поиск: экспортируемые имена из `src/`, которых нет ни в других модулях, ни в `scripts/` (grep по слову). В Swift не переносим.

**Не используется нигде (мёртвый код):**

| Где | Что |
|---|---|
| src/audio/engine.ts | `loadStepSample`, `downloadSample`; `loadSampleFiles` — только в scripts/click-check.cjs |
| src/state.ts | прежняя библиотека пресетов: `savePreset`, `loadPreset`, `renamePreset`, `duplicatePreset`, `deletePreset`, `itemName` (заменена библиотекой library.ts); `resetEq` (кнопки RESET больше нет); `modName`; `autoRecording` |
| src/automation.ts | `SEG_TYPES`, `SIMPLIFY_DEF`, `sampleAuto` |
| src/transport.ts | `playPage` |
| src/stems.ts | `stopRequested` |
| src/midi.ts | `midiAction` |
| src/engineIcons.ts | `ICON_IDS` |

**Лишний `export`** (используется только внутри файла) — около 60 имён: типы `TrackData`, `Pattern`, `Scene`, `Ui`, `Runtime` и др. в state.ts, `closeXxxWindow` во всех окнах мастера, константы params.ts. На перенос не влияет: в Swift видимость задаём заново (`internal`/`private`).

**Дубли:**

| Что | Где | В Swift |
|---|---|---|
| Биквад (расчёт коэффициентов и шаг фильтра) — четыре своих реализации | clipper-worklet.js:92, saturator-worklet.js:161, delay-worklet.js:55, reverb-worklet.js:70 | один `Biquad` в Core/DSP |
| Таблица антипроизводной + кубический Эрмит + ADAA (`makeTable`, `ADAA_EPS`, `SHAPE`) — почти один и тот же код | drive-worklet.js:55–110, saturator-worklet.js:29–110 | один `ADAAShaper` |
| tanh-сатурация с компенсацией | delay-worklet.js:264, jambo-synth-worklet.js:266, drive/saturator | общая функция |
| Окна модулей мастера (строка полей, рамка «hot», FREEZE, ввод числом) | ui/comp.ts, clipper.ts, limiter.ts, saturator.ts — уже на общей основе masterwin.ts, но раскладка строки и холсты повторяются | один вид `MasterWindow` с описанием полей |
| Метры: `Meter` (engine.ts:1786), стержни LevelBars, полосы MIX — три расчёта пика/пик-холда | engine.ts, ui/meter.ts, ui/dynamics.ts (LevelBars), ui/sample.ts | один `PeakMeter` (пик считает аудиопоток) |
| Проверка «какое окно открыто» — длинное `ui.eqView \|\| ui.limView \|\| …` повторяется | main.ts:188, 192 и окна | одно перечисление `centerView` |
| state.ts 3308 строк, engine.ts 2095 — смешаны данные, UNDO, миграции, сэмплы, MIDI-ноты | — | разбить по ТЗ (файлы до ~600 строк) |


## 3. Узкие места производительности веб-версии

Только наблюдения по коду (на iPad не мерили); в Swift устраняются архитектурой из ТЗ.

1. **Секвенсор живёт в requestAnimationFrame** (main.ts:167 → transport.ts:309 `updateTransport`, запас 100 ms). Шаги ставятся только пока идёт кадр: долгий кадр (открытие окна, большой UNDO) — шаги опаздывают; в фоне Safari кадры останавливает — при BACKGROUND AUDIO = ON звук идёт, но новые шаги, по-видимому, не ставятся (проверить на iPad). В Swift: секвенсор в аудиоколбэке, с точностью до отсчёта.
2. **Весь интерфейс перерисовывается каждый кадр** (main.ts:173–223: ~30 render-функций подряд, каждая сама решает, что изменилось). Нагрузка растёт с числом окон. В Swift: SwiftUI с наблюдаемым состоянием + Canvas только у анимированных элементов (кольца, метры, скоп).
3. **UNDO — снимок всего проекта JSON-строкой** (state.ts:482 `snapshot`, `edit()` — два `JSON.stringify(doc)` на каждое действие, до 200 строк в памяти). С 16 дорожками × 8 страниц × автоматизации — десятки–сотни КБ на действие; каждое нажатие шага сериализует проект. В Swift: value-типы (copy-on-write) — снимок почти бесплатный, сравнение не нужно.
4. **Граф Web Audio на голос**: у каждого голоса свои узлы (огибающая, Level, фильтр, Pan, посылы — ~34 вызова create* в engine.ts), до 48 голосов сэмпла (engine.ts:268) плюс 6 голосов синта на дорожку; модуляция — `setTargetAtTime`/`linearRamp` из основного потока раз в кадр (автоматизация — сообщениями наперёд на 60 ms). В Swift: один колбэк, голоса — структуры в заранее выделенном массиве, модуляция — в том же колбэке.
5. **Метры и спектры — AnalyserNode, опрашиваемые из кадра** (engine.ts:1786 `Meter`, 1453, 1504–1518): по 2 анализатора на дорожку и мастер, `getFloatTimeDomainData` на 1024–16384 отсчёта каждый кадр; пик между кадрами может пропасть. В Swift: пик/RMS считает аудиопоток в атомарные значения, UI только читает.
6. **Межпотоковые сообщения**: AudioWorklet ↔ главный поток — `postMessage` (17 мест в engine.ts; телеметрия мастера 187 кадров/с на модуль, WAVE клиппера ~224 КБ/с, стемы по 4096 кадров). Копирование и сборка мусора. В Swift: SPSC-кольца без выделений.
7. **13 отдельных AudioWorklet-узлов** (по узлу Plaits и JAMbo-синта на дорожку, плюс FX и мастер) — у каждого свой квант 128 и свой учёт; браузер не отчитывает нагрузку встроенных узлов (CPU-индикатор неполный). В Swift: всё в одном колбэке, CPU — точный замер времени колбэка.
8. **Plaits в WASM с `-ffast-math`**, свежий экземпляр на ноту в проверках; порт на Swift должен совпасть с golden-рендерами (см. риски).
9. **Мелочи**: `Math.max(...peak)` и `.map` в метрах каждый кадр (выделения), `innerHTML =` в 17 местах UI, `querySelectorAll` в обработчиках — в Swift не переносится.


## 4. Риски и вопросы к ТЗ

1. **Эталон Plaits и a0.** plaits.wasm собран с kCorrectedSampleRate = 47872,34 и `-ffast-math`. Swift-движки по ТЗ 4.3 считают с a0 = 55/48000. Чтобы эталон совпал поотсчётно, tools/golden должен рендерить wasm с нотой, сдвинутой на 12·log2(47872,34/48000) = −0,0461 полутона (ровно так веб и играет на 48 кГц). Тогда эталон — это звук веба.
2. **Допуск −60 dB поотсчётно.** `-ffast-math` (FMA, перестановки) против Swift без fast-math: у движков с обратной связью (FM feedback, STRING, MODAL, CHORDS) и с долгими хвостами ошибки округления копятся. Возможно, допуск −60 dB не пройдёт поотсчётно, хотя на слух разницы нет. Предложение: при провале — второй критерий (спектр по третьоктавам ±0,5 dB), в таблице SELF-TEST видны оба. Решение — после первых движков S3a.
3. **Генератор случайных чисел.** Шумовые движки (NOISE, PARTICLE, SWARM, GRAIN, HI-HAT, SNARE, STRING) берут общий stmlib::Random — последовательность зависит от порядка вызовов между голосами. Для поотсчётного сравнения эталон рендерится свежим экземпляром на ноту (как scripts/speech-check.mjs), Swift — тоже.
4. **Таблица LPC-фонем SPEECH** (lpc_speech_synth_phonemes.cc): происхождение коэффициентов не указано в исходниках (этап 12 веба). Перед публикацией в App Store стоит решить так же, как с Words.
5. **Playgrounds и звук.** AVAudioSourceNode с одним колбэком — штатный путь. Режим «Swift 5» + модуль Synchronization (iPadOS 18) — проверить в S0 первым делом; запасной вариант os_unfair_lock — в ТЗ.
6. **Swift на Linux в облаке.** Попробую поставить toolchain (swiftly) в S0; если нет — проверка только самотестом на iPad.

## 5. Решение

Ответ пользователя на аудит: «Переносим все изменения, которые сделали в вебе». Все ⚠ — П: свои движки (S3b), FX и sidechain 1:1 по worklet’ам (S4), сетка 16 строк с окном 8 (S1), пианоролл и запись нот (S1), маркеры нарезки и масштаб (S2), автоматизация, окна мастера, библиотека, стемы, REC, MIDI, переходы — вехи S6–S13.

## 6. Вехи

Порядок и номера — решение пользователя (после S5). Прежние номера: S9a → S6, S9 → S7, S6 → S9, S12 → S10, S10 → S11, S11 → S12, S8 → S13, S7 → S14; S8 (пианоролл) — новая. В итогах прошлых вех (SWIFT_MILESTONE_S1…S5) номера будущих вех — прежние.

| Веха | Что |
|---|---|
| S0 | каркас .swiftpm, аудиосессия 48 кГц, тест-тон, CPU, DIAGNOSTICS, CoreTests |
| S1 | транспорт, дорожки, шаги, страницы, p-lock, сетка ручек, пианоролл, запись нот, сетка паттернов (16 строк), UNDO |
| S2 | сэмплер, микшер, фильтр, pan, окно сэмпла, редактор (с маркерами нарезки и масштабом) |
| S3a / S3b | Plaits 8 + 8, свои DRUM, ANALOG, FM, WTABLE, SELF-TEST |
| S4 | FX (reverb, delay, drive, sidechain 1:1), MOD, MORPH |
| S5 | мастер, EQ (8 полос), индикация, измеритель, LUFS, скоп |
| S6 | окна SAT / COMP / CLIP / LIM, пресеты модулей мастера |
| S7 | EQ Dynamic и Mid/Side, пресеты EQ |
| S8 | пианоролл (новое): окно нот, длина и velocity у ноты, GRID, VEL; нижний пианоролл — клавиатура |
| S9 | проекты, автосохранение, настройки, LICENSES |
| S10 | переходы между проектами (MIX, PREV, кроссфейдер) |
| S11 | библиотека с папками, импорт/экспорт (.jambo, ZIP, WAV), стемы и запись мастера, REC в редакторе |
| S12 | MIDI (CoreMIDI): маппинг, LEARN, MIDI MAP, Twister, клок |
| S13 | автоматизация (AUTO) |
| S14 | оптимизация, App Store |
