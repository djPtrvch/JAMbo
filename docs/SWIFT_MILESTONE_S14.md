# S14 — правки интерфейса, оптимизация, App Store

Порядок (решение пользователя): сначала правки интерфейса (S14v), затем оптимизация, проверка S13e и App Store.

## S14v — правки интерфейса (готово, проверено на iPad)
- Дорожки (TrackRow): mute — красная рамка поверх жёлтой рамки выбора и красная заливка 35 %, solo — жёлтая заливка, как в вебе. Имена невыбранных дорожек — 12 pt, semibold, разрядка 0,7, цвет текста (как MIX и MST); выбранная — 15 pt, heavy.
- Кнопки мастера (MasterButtons): рамка цветом модуля, пока модуль работает (bypass выключен); bypass включён — рамки нет; с SHIFT включённый bypass залит цветом модуля.
- Меню звука (SoundMenu): на всю левую колонку (от верха окна сэмпла до низа кнопок LFO); кнопки движков высотой 40, как LOAD; группа LOAD · SAVE — внизу.
- REC (TopBar): SHIFT + тап — запись мастера, как ● MASTER при MIX (общее состояние stemArmed / stemRecording): готова — точка крупнее (20 pt), пишет — мигает, как точка на MST (MasterRecDot).
- Меню ROOT: шириной от левого края ROOT до правого края REDO (ChoiceState.width). Квинтовый круг пробовали и убрали.
- Сетка паттернов (PatternGrid): ячейка — свайп вверх — меню, удержание 0,35 с и перенос — копия клипа, свайп вниз — ничего (клип тянется только после удержания); строка — быстрый свайп вверх (до 0,28 с) — меню строки, удержание и перенос — строка целиком (колонка строк и клипы всех дорожек) едет за пальцем, строки между ней и пальцем сдвигаются (анимация 0,2 с), на отпускании — Project.moveRow без анимации; прочее движение по колонке строк — прокрутка окна строк.
- COPY / PASTE дорожки (Project.pasteTrack): только настройки — звук, ручки, назначения LFO/ENV, EQ, папка, громкость; имя, клипы, ход игры, mute, solo и id — свои (в вебе — целиком). При переходе MIX, если дорожка играет клип PREV, вставленный звук становится её home.
- SAVE сэмпла в библиотеку: имена сравниваются без расширения аудиофайла и без учёта регистра (Library.bare) — «kick.wav» из IMPORT и «Kick» — одно имя, вопрос OVERWRITE / SAVE AS… / CANCEL.
- Пианоролл: цвета окна EQ — фон theme.panel, линии theme.grid / gridStrong (такты — 2 px), корневая строка — белая подсветка 10 %, подпись белая жирная, остальные — dim; диезы чуть темнее. VEL включён по умолчанию, число velocity — чёрное.
- Меню страницы (двойной тап по миниатюре): шириной 228 (обводка миниатюр с её линией), скругление 9; ставится по рамке колонки миниатюр (pagesFrame): помещается под страницей — под ней (на нижней линии обводки), иначе — от верха колонки на 4 px выше, закрывая обводку.
- SPEED клипа (меню страницы, внизу): 2, 1, 1/2, 1/4, 1/8, 1/16 — Clip.rate (степень двойки: 1, nil, −1…−4; в файле проекта, копируется с клипом; UNDO); у MIX и MST нет. Колбэк: SeqData.clipRate, tickLen — проход в тиках (×2 — вдвое меньше с округлением вверх, медленнее — в 2…16 раз больше); ×2 — два шага за тик (второй — через полшага), медленнее — шаг раз в 2…16 тиков (между шагами p-lock FX и LFO/ENV держатся). Длина нот, свинг, рэтчеты — по длине шага со скоростью. Запуск клипов, строки и стемы — по tickLen; запись с REC — Clip.localStep; полоса хода — Clip.passTicks. При ×2 p-lock FX и LFO/ENV пары — от первого шага, подсветка — каждого второго.

## S14w — превью-иконки движков и правки после них (готово, проверено на iPad)
- Иконки движков 16–24 — перенос docs/icons/prototype/engine-previews-prototype.html (KICK, SNARE, PERC, HAT, CLAP — секция «final mix», ANALOG, FM, WTABLE, SUB — V3): колонки, как в превью сэмпла (72 колонки по 6 точек, min..max с осью). Core/Icons: IconElement.rects (колонки одним путём) и ink (основной или серый), EngineIconsColumns — общий язык (gen, lane mirror/thin/ext, ось, шум, формы, morph). KICK, SNARE, PERC — два прохода генератора: белый удар (k = 9) и серый хвост от Decay; SNARE — шум медленный и ×0,75. WTABLE — кадр таблицы дорожки (EngineIcons.tableFrame). Иконка — чистая функция ручек 1.1–1.4 и Decay: фаза волн синтов постоянная (T = 1,3). Theme.icon2 — #6c6c72 (тёмная), #9b9aa0 (светлая). Подробно — docs/icons/ENGINE_ICONS_SPEC.md.
- Решения пользователя (отличия от прототипа): HAT — сплошные линии без градиента к верху; подсветки удара (hx) в окне нет — иконки ударных не пульсируют в такт (hx остался в EngineIcons.elements для сверки).
- Окно синта (SynthWindow): ручки сглажены ~90 мс (IconMotion; кадры TimelineView идут, только пока значения не дошли); ступенчатые ручки — пункт i из s как i / (s − 1). Иконка до 144 pt, сдвинута на 3 pt вниз, ручки «подпись · значение» — на 14 pt ниже иконки.
- Заголовок окна звука (SoundTitle) — один стиль у движков и сэмплов: имя заглавными жёлтым (accentText), 13 pt bold, как в меню звука; у WTABLE — « — Basic» (имя таблицы с заглавной) цветом текста; у сэмпла — « — нота · ST/M». Жёлтая строка полного имени под иконкой убрана.
- Окно ICONS (раздел APP бутерброда, только DEBUG) — все движки на четырёх наборах ручек, тёмная и светлая темы.
- UNDO / REDO — значки arrow.turn.up.left / right (в стиле repeat у LOOP ROW).
- Октава клавиатуры у каждой дорожки своя (AppModel.octaves, не в проекте; по умолчанию у всех C2); ноты маркеров нарезки — от октавы своей дорожки (SoundSnapshot octaves).
- MIDI MAP: Apply to all pages (MidiSettings.applyKnobsToAllPages) — у назначенной ручки в условии Current page: маппинги 16 ручек страницы копируются на TRACK, FX, MOD, MIX, MST (копия заменяет ручку и забирает источник в своём условии; дальше страницы правятся отдельно).
- MIDI, обратная связь (исправление): маппинг источника выбирается как при управлении — самое точное условие с любого входа. Раньше маппинги с разным Input port (Any и порт) спорили по порядку в списке: на MIX, MOD, FX, MST GLOBAL ручки слал значение дорожки.
- Проверка: ios/tools/icons/golden.mjs — эталон из прототипа (заливки функций draw на записывающем canvas; у HAT отрезки склеиваются) → engine_previews_golden.json (прежний эталон веба engine_icons_golden.json удалён); ios/tools/icons/snapshot.mjs — PNG «прототип | Swift» в обеих темах.

## S14x — EQ, окна мастера, звук у клипа, IMPORT строк (готово, на iPad не проверено)
- EQ: окно DYN перетаскивается за заголовок (полоски справа; сдвиг сбрасывается при открытии); ввод числом — двойным тапом по FREQ, GAIN, Q, THRESHOLD, RANGE (EqField.double; сброса Q двойным тапом нет); в PRESETS — только имена; строка EQ — 8 равных столбцов до правого края; COMPARE у каждой дорожки свой (AppModel.eqCompares: id дорожки → id сравниваемой).
- Окна мастера: ввод числом — двойным тапом (MasterField); тап по TYPE и RATIO срабатывает, если второго тапа не было за 0,33 с.
- ADD TRACK: пустой клип новой дорожки сразу запускается — при игре с ближайшей границы (играющая строка или ячейка, которую играет больше всего дорожек), без игры — со стартом.
- MIX при CROSSFADER OFF во время игры: держатся модули мастера (параметры, BYPASS) и EQ мастера старого проекта (AppModel.globalsHold — настройки нового, MixGlobals.holdMaster), громкости и выход — сразу нового; остановка — мастер нового (правки громкостей остаются). Autosave — мастер нового проекта (autosavedProject); SAVE, SAVE AS, EXPORT и пометка unsaved — звучащий (savedProject): сохранённые проекты сами не меняются.
- Гамма и нота — у клипа: правка гаммы не трогает клипы PREV; ноты маркеров нарезки — в гамме и ноте клипа, который играет звук (Project.clipKey).
- Звук у клипа: Clip.src у любого клипа (не только PREV). Track.moveSlot — звук прежнего клипа обратно в его src, у нового клипа со своим звуком он — звук дорожки, свой — в home; правки идут в звук активного клипа; clipCopy — копия с текущим звуком; COPY, PASTE, перетаскивание, DUPLICATE строки, COPY PLAYING — со звуком (у PREV — только паттерн).
- Колбэк: два звука на дорожку — активного клипа и следующего (SoundData.altSlot; AppModel.nextSlots — ожидающий клип, ожидающая строка, следующая строка, без игры — строка старта; снимок публикуется, когда next меняется); запущенный клип остаётся на втором звуке (keepAlt), без переключения посреди игры. Запуск, которого интерфейс не ждал, звучит прежним звуком до нового снимка (кадр).
- IMPORT (окно LOAD / MIX): строки проекта с тригами (Project.importRows) — в свободные строки после последней заполненной (первая не занимается; при одной строке — новая), сколько поместится; столбец к столбцу; звук столбца другой — клип несёт свой; недостающие дорожки (до 16) — со звуком дорожки другого проекта; гамма, нота, FX клипа — свои (нет — другого проекта); имена и ноты сэмплов — из другого проекта; UNDO; игра не останавливается; ничего не встало — сообщение.
- CoreTests — 317 (ImportRowsTests, testClipKeyPerClip, testHoldMasterOnly; testSnapshotSoundBySlot — по next и keepAlt).

## S14y — правки интерфейса (готово, на iPad не проверено)
- BPM: ввод числом — двойным тапом (BpmField; удержания нет).
- OVERDUB — в меню клавиатуры (бутерброд под CHORD, после KEY VELOCITY); в SETTINGS → RECORD его нет.
- Миниатюры LFO/ENV в окне сэмпла — пока держат MOD (modPreview = modMode), без 1,5 с после поворота.
- Ступенчатые ручки с пунктами движков (ParamDef.steps): toNorm — i / (s − 1), fromNorm — ближайший пункт; значение — середина пункта, как раньше (звук и ModEngine не меняются).
- Имена пресетов EQ и модулей мастера: SAVE с занятым именем (без учёта регистра) — OVERWRITE (замена на месте) / SAVE AS… / CANCEL, RENAME на занятое — RENAME… / CANCEL (NameClashAlert; EqPresetBook.index, MasterPresetBook.index, save(over:)).
- UNDO мастера: поворот энкодера MIDI — новая запись при смене энкодера (midiGesture(key)); жест поля или дисплея мастера, отменённый системой, закрывает запись UNDO (GestureCancelGuard, через 60 мс после конца касания).
- Перестановка дорожек при игре: CoreEvent.moveTrack → Launcher.move (активная ячейка, остановка, ожидание, начало прохода), LiveState.moveTrack; UNDO / REDO перестановки — followTrackOrder. Раньше сдвинутая дорожка играла ход чужой и вступала на границе (LaunchTests.testMoveTrackKeepsPlaying).
- WTABLE в окне синта: встроенные — по таблице показа WtDisplay (256 кадров × 256, до 127 гармоник, WavetableStore.display — в фоне); фронт PWM идёт плавно (EngineIconTests.testDisplayPwmEdgeMovesSmoothly).
- MIDI OFFSET: палец по значению вправо-влево — 1 ms на 3 px (SyncOffsetRow).
- Пианоролл с VEL: палец по ноте вверх-вниз — velocity, вбок (что первым сдвинулось больше 4 px) — перетаскивание, как без VEL.
- CoreTests — 319.

## S14z — MIX и перестановка без пауз, громкости MIX, MORPH ALL TRACKS, имена строк IMPORT (готово, на iPad не проверено)
- Голоса не гаснут при смене снимка звука: перестановка — голоса сэмплера переезжают на новое место дорожки (Sampler.adopt по id), держащиеся ноты синта (голоса синта привязаны к месту) заводятся заново на новом месте (moveSynthNotes); переход MIX — SoundData.rebind (AppModel.rebindNext на первом снимке после startMix): голоса остаются на своих местах и берут новые id. Удалённая дорожка и убранный сэмпл — голоса гаснут, как раньше.
- MIX без кроссфейдера: Project.mixed(clipVolumes:) — у клипа PREV TrackSound.vol (громкость старой дорожки); в снимке громкость у каждого из двух звуков дорожки (gain[t], gain[t + maxTracks]) — клипа, который им звучит (Track.vol(slot:)); MixGlobals.holdMaster держит и outVol. moveSlot и clipCopy сохраняют vol клипа.
- MORPH: SHIFT + двойной тап — settings.morphAll (ALL TRACKS) вкл./выкл.; нажатия с SHIFT режим MORPH не переключают; пока ALL TRACKS включён — чёрная линия контура внутри кнопки (как toggle FX и MOD).
- IMPORT строк: строки называются именем проекта (Project.importedRowName: несколько — «имя 2», до 12 знаков).
- CoreTests — 323 (testVoiceSurvivesMoveAndRebind, testSynthNoteMovesWithTrack, testClipVolumes, testRowNamesFromProject).

## S14za — правки пользователя (готово, на iPad проверено частично)
- Duck вместо Sidechain в подписях: ручка 3.4 Duck, FX Duck Attack / Release / Source / Curve, вкладка SETTINGS → DUCK (DUCK SENDS), SELF-TEST — DUCK; ключи sc.* и sidechain прежние. SC HPF компрессора мастера — не Duck, не менялся.
- Delay: Dly Spread — 2.3, Dly Filter — 2.4; Params.fxIds — отдельный список в прежнем порядке (номера FxRack не зависят от сетки), fxCount 18. Dly Sync (скрытый FX dly.sync, по умолчанию 1): SHIFT + тап по Dly Time — по темпу или 10…2000 мс (Params.dlyFreeMs, ручка Params.dlyTimeFree — плавная, тот же ключ dly.time 0…11); время при переключении сохраняется.
- LFO по темпу: lfoN.sync у звука дорожки (SoundData.lfoSync), SHIFT + тап по Speed; пункт — по месту на ходе ручки (Params.lfoDivs, 14 пунктов), ModEngine.begin(bpm:). SHIFT + тап срабатывает при отпускании; SHIFT + двойной тап по-прежнему снимает p-lock.
- SAVE нового проекта: окно имени со случайным свободным именем (ProjectSession.randomName, прилагательное + существительное, ≤ 24).
- Клавиатура: Scales.topOctave — октава не выше той, где верхняя нота (с CHORD — верх аккорда) ≤ 127; проверено тестом: ноты клавиш всех гамм, тоник и октав доходят до снимка секвенсора без изменений.
- MORPH: ALL TRACKS по умолчанию ON; чёрная линия внутри кнопки — пока ALL TRACKS выключен.
- Свои значения по умолчанию (KnobDefaults, UserDefaults): SHIFT + удержание ручки 0,6 с — запомнить (SAVED), двойной тап — сброс (ещё раз — к заводскому); области sampler, synthN, mod, fx, mst; действуют в NEW и ADD TRACK; SETTINGS → DEFAULTS — FORGET ALL.
- Окно при MIX (MixOverview): без заголовка, уровень дорожек одной полосой на 16 местах, без приглушения Duck.
- Иконки движков: волны ANALOG, FM, WTABLE, SUB — сплошная фигура от оси до сигнала по 433 точкам (IconElement.wave, waveBot), огибающие ударных — сглаженный контур (contour), штрихи и ось — скруглённые; rects — для сверки с прототипом. Окно ICONS убрано (IconGallery удалён).
- WTABLE: таблица показа с окном Ланцоша (σ-фактор) — без звона Гиббса верх PWM не дёргается (было ±1,8 из 64, стало ±0,2); при смене дорожки иконка сразу на её значениях (IconMotion.follow).
- Нота сэмпла: окна YIN — в громкой части (не тише 10 % пика, до 1,5 с), короткие удары — окном 1024. Проверка на синтетике: шум и металл 808 — 0 ложных из 64; тоны E1…E7 — 0 неверных из 300, 6 пропусков (E1, G1 со спадом 30 мс). По спектру ноту не угадываем — решение пользователя: точность важнее.
- CoreTests — 331 (TempoSyncTests, ScaleRecordTests, KnobDefaultsTests, testPitchShortPercussion).
- На iPad проверено: превью MIX, иконки, WTABLE PWM, нота конги; остальное — нет.

## S14zb — RATE сэмпла и таймстретч (готово, на iPad проверено частично)
- Ручка 1.4 сэмплера — RATE (VoiceParam.rate, 17-й параметр голоса; NoteLocks — 17 значений); режимы Rate Pitch / Rate Stretch — SHIFT + одиночный тап (Params.rateModeId); алгоритм — Settings.stretchBeat (SETTINGS → SAMPLER → STRETCH, общий для проектов, по умолчанию NORMAL); SoundData.rateMode: 0 — Pitch, 1 — NORMAL, 2 — BEAT. Поведение — docs/ai/sound-sampler.md.
- Общий движок: голос ведёт указатель времени (скорость — темп проекта к темпу файла и RATE) и высоту (нота, Pitch); алгоритм заполняет кусочек в 32 отсчёта. NORMAL — Core/Sampler/StretchPV.swift (Vocoder; БПФ — PvFFT.swift: vDSP на iPad, своё на Linux; atan2 и sincos — vForce), атаки — Onsets.swift (SampleData.onsets, один раз на сэмпл); BEAT — Stretch.swift (Stretcher). Темп файла — TempoDetect.loopBpm. Подготовка к варпингу: карта времени будет вести тот же указатель.
- Проверено: RateTests, PvFFTTests; все 443 теста Core проходят. Замер (Linux, отладочная сборка, без Accelerate): 16 голосов NORMAL ≈ 4× от 16 голосов Pitch, BEAT ≈ 1,8×. iPad (отладочная сборка): 3 голоса Rate Stretch NORMAL — Samples 15 % в среднем, 24 % в пике; звук в целом 41,7 % / 56,6 % худший блок.
- Открыто: звук на лупах, ударных и тональном материале; нагрузка — сделано: NORMAL — циклы кадра на vDSP (PvVec.swift), кадры голосов разнесены по блокам (тест VocoderLoadTests); BEAT — зёрна кусками и поиск зерна на vDSP, кубическое чтение PvCubic общее; замер на iPad, Samples (среднее / пик): Pitch 8,7 / 12,3 %, NORMAL 11,6 / 16,0 %, BEAT 15,6 / 23,8 → 10,0 / 14,0 %; эталона веба нет — в SELF-TEST не добавлено.

## S14zc — WARP, варпинг сэмпла (готово, проверено на iPad)
- Поведение — docs/ai/sound-sampler.md («WARP»). Решения пользователя: и автоматическая расстановка (AUTO WARP), и ручная правка; режим WARP в редакторе; действует только в Rate Stretch; куски нарезки — по той же карте; ▶ в режиме WARP — по карте в темпе проекта.
- Core: Model/Warp.swift — WarpMark (доля длины at, доля beat), WarpInfo (свой BPM файла, метки), WarpMap (отсчёт ↔ доля; за крайними метками — по BPM файла; auto — метка начала на долю 0 и атаки на сетку); Track.warps (по ключу сэмпла, в проекте и в звуке клипа TrackSound.warps); правка — addWarp, moveWarp, placeWarp (верхний флажок), warpStart, deleteWarp, clearWarp, setWarpBpm, autoWarp.
- Колбэк: Sampler/SoundWarp.swift — таблицы меток в снимке звука (eWarpStart/eWarpCount, warpU/warpP; с метками — и у дорожки в PTCH), голос копирует их (warpCap 1024); указатель голоса — в отсчётах темпа файла (uPos), отсчёт сэмпла и скорость куска 32 — по карте (warpChunk); NORMAL и BEAT без изменений. ▶ WARP — событие warpPreview: нота дорожки в Rate Stretch (SoundData.stretchAlgo), RATE 100 %, весь сэмпл; стоп — затухание 5 мс; конец — .end(previewVoice).
- UI: SampleEditorWarp.swift (WarpView — доли на экране, WarpPeakCache — форма волны по карте через SampleEdit.peaks(bounds:), WarpBar, EditorWarpDraw), AppModelWarp.swift; SampleEditor — жесты меток (снизу — доля, сверху — место в сэмпле, START, выделение), в режиме нарезки — метки варпинга снизу для ориентира и прилипание маркеров нарезки. Строка редактора — от левого края SCALE (AppModelCapture.scaleFrame).
- Проверено: WarpTests (карта, AUTO WARP, правка и хранение, удар на долю в NORMAL и BEAT, ▶ WARP у дорожки в Rate Pitch, метка начала); все 450 тестов Core проходят; на iPad — пользователь.

## S14zd — p-lock с нотой в пианоролле (готово, на iPad не проверено)
- Решение пользователя: p-lock привязаны к шагу и едут с нотой, которую тянут в пианоролле (прежнее решение S8 — оставались на шаге). Правило — ios/CLAUDE.md («Пианоролл»).
- Core: Track.rollCarry (в начале перетаскивания: нота одна на шаге — p-lock, свой звук шага, p-lock пресета; StepCarry с шагом, где они лежат) и moveRollNote(carry:) — уходят со шага, когда он пустеет, встают на пустой шаг (без трига, своих p-lock и звука); у аккорда и шага со своими p-lock — их p-lock. UI: RollTouches хранит carry на жест, AppModel.rollMove передаёт его. UNDO — одним шагом на жест.
- Проверено: RollEditsTests.testMoveCarriesLocks; все 451 тест Core проходят.

## S14ze — CUT и выключатель WARP (готово, проверено на iPad)
- Поведение — docs/ai/sound-sampler.md («Редактор сэмпла», «WARP»). Решения пользователя: выделение — маркеры обрезки, кнопка CUT рядом с TRIM; на стыке — кроссфейд 5 мс; маркеры нарезки и метки WARP после вырезанного сдвигаются, внутри — удаляются; удержание WARP — вкл./выкл. варпинга без удаления меток.
- Core: Sampler/SampleCut.swift — SampleEdit.cutRange (кадры как у TRIM), cut (левая часть продолжается в вырезанное и гаснет, правая нарастает — длина и места меток точные), cutPlace; Track.carryCut — маркеры и метки к копии (метки WARP — и по долям, на длину вырезанного по карте; с метками BPM файла закрепляется). Model/Warp.swift — WarpInfo.off (nil — включён; в прежних файлах поля нет), isOff, Track.setWarpOff; SoundWarp.putWarp — выключенный варпинг в снимок не идёт.
- UI: AppModel.cutSample (applyEdit с carry), toggleWarpOff; HoldToolButton (тап и удержание 0,5 с — LongPressGesture.exclusively(before: TapGesture); strike — зачёркнуто), EditorWarpDraw.flags(off:) — метки серые.
- Проверено: SampleCutTests (стык и кроссфейд, края, перенос маркеров и меток), WarpTests.testWarpOffKeepsMarks (звук как без меток, метки остаются, кодирование); все 478 тестов Core проходят; на iPad — пользователь.

## S14zf — облегчение сборки под Playgrounds (готово, проверено на iPad)
- Решение пользователя: стабильная сборка с первого раза без перезагрузок — запас по объёму, функции, вид и звук не меняются. Скилл .claude/skills/swift-build-size.
- SELF-TEST вынесен из приложения (8896717): сверки с эталонами — только в тестах Core (ios/CoreTests/golden, Tests/CoreTests/Golden); 1,903 → 1,862 млн инструкций IR. CUT и WARP (98f01e7) — 1,868: на iPad не собралось (порог плавает около 1,86).
- Замер размера кода (926d472): шаг workflow «Code size by type and function» — байты машинного кода по видам функций, типам и функциям (nm, otool); CALIBRATION — и в конце лога.
- Theme — неизменяемый final class вместо структуры из 23 цветов (e42dd98): тема лежит почти в каждом виде (@Environment), копия структуры давала каждому виду функции копирования всех цветов (14 % кода); 1,868 → 1,621 млн. ParamDef и EditorColors — так же (c2b80e1): 1,609 млн, пик памяти компилятора 1 524 → 1 459 МБ; на iPad — с первого раза.

## S14a — замеры (готово, замер на iPad сделан)
- Колбэк: RenderProfile (Core/Util) — метки на уровне блока (не на отсчёт), время от прошлой метки — в раздел: Seq (снимки, команды, транспорт, начало MOD и FX), Samples (голоса сэмплера, прослушивание), Synth, EQ (дорожки и мастер), Mix, FX, Master (SAT, COMP, CLIP, LIM, выход), Meters (метры, скоп, спектры, стемы). За секунду звука — средняя и наибольшая доля блока, с RESET — худшая (seqlock). Часы — DispatchTime (на Apple — mach_absolute_time), ~25 чтений на блок.
- Интерфейс: FrameMeter (UI) — CADisplayLink: fps, средний и худший кадр, пропущенные кадры (промежуток > 1,5 кадра); время drain (главный поток, 60 раз в секунду). Перерыв дольше 0,5 с (фон) — не пропуск.
- DIAGNOSTICS: строки разделов и Audio («avg · peak · worst»), UI, UI total, Drain; кнопка RESET. Замер идёт всё время (окно закрывает экран): RESET → закрыть → играть → открыть.
- Тест Core «тяжёлый проект» (HeavyLoadTests): 4 синта (ANALOG, FM) аккордами по 4 ноты, 4 стерео-сэмпла на каждом шаге с фильтром, посылы во все FX, Sidechain, EQ с динамической полосой на всех дорожках и мастере, весь мастер. Linux, доля блока 256 (avg / пик):

| Раздел | Отладочная | Релизная |
|---|---|---|
| Samples | 58 % | 6,4 % |
| Synth | 40 % | 8,3 % |
| EQ | 22 % | 6,7 % |
| FX | 29 % | 5,0 % |
| Master | 42 % | 6,0 % |
| Seq, Mix, Meters | ~3 % | ~0,5 % |
| Всего | 194 % (пик 293 %) | 33 % (пик 57 %) |

- Релизная сборка на Linux (`swift test -c release -Xswiftc -enable-testing`): Swift 6.0.3 падал при -O на Drive.wet и Saturator.wet (index_addr в цикле) — позиции колец децимации перенесены в локальные переменные; эталоны FX и мастера проходят в обеих сборках.
- iPad Pro 11" M4, Playgrounds (Debug), проект пользователя — 16 дорожек, ~9 мин звука (avg · пик за секунду · худшее с RESET): Seq 0,2 · 2,1 · 3,1 %; Samples 1,0 · 2,2 · 3,9 %; Synth 34,9 · 39,2 · 59,4 %; EQ 4,6 · 5,3 · 7,1 %; Mix 3,3 · 3,9 · 4,4 %; FX 16,6 · 16,9 · 18,1 %; Master 17,5 · 18,2 · 18,8 %; Meters 0,1 · 0,3 · 0,5 %; всего 78,3 · 82,7 · 110,1 % (выше 100 % — пропуск блока). Интерфейс: 120 fps, пропущено 165 из 12100 кадров (1,4 %), худший кадр 42,7 мс; drain 0,44 мс в среднем, худший 8,2 мс.
- Вывод для S14b: горячие места — Synth (растёт с голосами), FX и Master (почти постоянная цена: Reverb и Delay считаются и без посылов, SAT и CLIP — с оверсэмплингом).

## S14b — оптимизация звука (готово, проверено на iPad)
- Замер: профиль callgrind отладочной сборки (Linux) на тесте «тяжёлый проект» и тесте цены голоса по движкам (SynthCostTests).
- Синт: фильтр децимации (ANALOG, FM, SUB, HAT) — пары симметричных отводов без цикла (jHalf, dHalf); синус и буфер фильтра — Double со значениями Float; ручки куска — метод без захвата, бит p-lock из таблицы (без обобщённого VoiceMask(p)); состояние — в локальных.
- FX: покой Reverb и Delay — вход молчит, выход тише −120 dBFS дольше внутреннего пути (Reverb 1 с, Delay — наибольшее время + 0,5 с): не считаются, состояние с нуля, первый посыл будит. Drive: не пересчитываются незвучащие кривые (при смене TYPE их ставит process — то же значение).
- Мастер и Drive: свёртки оверсэмплеров и true peak лимитера — по 4 отвода со сдвигом указателей; кривые — функции файла с @_transparent; сатуратор — exp и компенсация только при изменении DRIVE; состояние циклов — в локальных.
- Правила отладочной сборки (найдено в S14b): встраивается только @_transparent (@inline(__always) — обычный вызов, и @_transparent нельзя на методах класса); каждый вызов функции обнуляет кадр стека (memset); rounded(.down) и обобщённый abs — медленные (пол — через Int, где значение ≥ 0); Double(Float) — вызов; обращение к свойству класса — проверка доступа.
- Эталоны синта, FX и мастера проходят (результат побитно тот же, кроме порядка сложения в фильтре децимации синта — ниже −120 dB). CoreTests — 300.
- iPad, проект пользователя (16 дорожек), avg · пик · худшее: Synth 16,9 · 20,5 · 32,3 %; FX 9,2 · 9,7 · 11,9 %; Master 8,4 · 10,0 · 11,1 %; всего 43,1 · 49,5 · 65,7 % (было 78,3 · 82,7 · 110,1 %). Интерфейс: пропущено 45 из 14356 кадров (0,3 %), худший 31,5 мс; drain 0,29 мс.

## S14c — интерфейс и MIDI (готово, проверено на iPad)
- Задержки нот с MIDI нет (проверил пользователь) — путь MIDI → звук не менялся. Sampler.swift разделён раньше (413 строк).
- Замер: DIAGNOSTICS → Main (время главного потока, % ядра) и Redraw (пересчёты видов и кадры метров в секунду; RedrawMeter) — с RESET и только пока окно закрыто (под окном SwiftUI не рисует).
- Ручки (KnobView), шаги (StepFace), дорожки (TrackFace), волна окна сэмпла (WaveShape) — equatable: правка проекта и ход игры перерисовывают только изменившееся; у волны каждый кадр — лишь полосы воспроизведения. Анимации ручек с LFO и кривой, иконки синта, миниатюр LFO, плейхеда аранжировщика — до 60 кадров в секунду.
- SYNC: при выключении RECEIVE в звук возвращается темп проекта.
- iPad, PLAY, дорожка с сэмплом: пересчёты 466 → ~250–340 в секунду (шаги 134 → 16, дорожки 128 → 35, ручки при повороте 668 → 217); Main 35–41 % — без изменений: остаток — SwiftUI и отладочная сборка (без Instruments не разобрать); Canvas с rendersAsynchronously разницы не дал — возвращено. Кадры 119–120 fps, пропущено 2–7 из ~3000.

## S14d — проверка SYNC (идёт)
- RECEIVE, SYNC START/STOP (выкл. — свои PLAY и STOP независимы) и SEND проверены пользователем на iPad с Digitakt по USB (режим USB MIDI). Описание Swift-версии — docs/ai/settings-midi-sync.md («MIDI-клок в Swift-версии»).
- CLOCK INPUT (решение пользователя): при RECEIVE — список ALL INPUTS / один вход (SyncSettings.clockIn, acceptsClock), сообщения реального времени фильтруются по нему до фильтра входа MIDI → DEVICES; смена входа — ClockFollower.lose и темп проекта (AppModel.setClockIn). Тест — SyncTests.testDefaultsAndCoding. На iPad не проверено.

## Правки после проверки (готово, проверено на iPad)
- Анимация FX: пока регулируют ручку FX (палец или MIDI), поверх превью окна сэмпла — картинка Reverb, Delay, Drive или Duck в поле иконок движков; огибающая фильтра; выключается SETTINGS → APPEARANCE → FX ANIMATION. Core/FX/FxPicture.swift, UI/FxPreview.swift; описание — docs/ai/fx-eq.md.
- BACKGROUND AUDIO (SETTINGS → AUDIO ENGINE): ключ UIBackgroundModes: audio в Info.plist рядом с Package.swift (additionalInfoPlistContentFilePath); работает на iPad. Перед выгрузкой в App Store — проверить, что строка в Package.swift на месте; окончательно — сборкой из TestFlight.
- EQ: у low cut, high cut и notch по вертикали — Q.
- P-lock 4-го столбца (Pan, Chance, Ratchet, Velocity; Duck, ENV) — оранжевые (на пробу).
- Одна сплошная секвенция: у короткой секвенции «+» — 16 шагов сразу за последним (7 → 23), DUPLICATE — копия шагов за последним (7 → 14). Своя длина у каждой страницы пробовалась и откачена.
- Отложено: выбор устройств MIDI-клока отдельно для приёма и отдачи.

## Правки 1.11 вечер (готово, на iPad — частично)
- WTABLE: своя таблица в окне синта — таблица показа прямо из WAV (WtDisplay.user: 256 кадров × 256, без FFT, без постоянной, к пику 1.0), не ждёт мипмапов звуковой; WavetableStore.display — ожидающие (waitingDisplay), preload строит и показ своих, prune чистит. Тест WavetableUserDisplayTests.
- Фильтр голоса — прямая форма I, скачки через сухой сигнал (docs/ai/sound-sampler.md «Фильтр голоса»; итог — SWIFT_MILESTONE_S15 «Правки 1.11 вечер»).
- Клок RECEIVE: пачки и опоздавшие тики USB — в счёт, не в темп (ClockFollower: прямая «время от номера тика», долг паузы, rejectLimit). Тесты testDelayedBurst, testTempoJump. На iPad с Digitakt: стало лучше; остаток — отключения AG06 на хабе без питания (docs/ai/settings-midi-sync.md).
- Строка «Now:» (AUDIO ENGINE): last — причина последней смены маршрута и прежний выход (AudioHost.describe).

## Правки 2.11 (решения пользователя; проверено на iPad)
- Пресеты EQ и модулей мастера: удержание строки 0,4 с и перетаскивание — порядок списка (EqPresetBook.move, MasterPresetBook.move). Свои папки библиотеки — так же (LibNode.order, Library.moveFolder, AppModel.libMoveFolder; тест LibraryFolderOrderTests).
- Жест строки списка (SwipeRow, LibRow) — один распознаватель UIKit RowGesture / RowRecognizer (HorizontalSwipe.swift): сдвиг больше 10 pt раньше удержания — вбок свайп, по вертикали жест не начинается (касание — прокрутке); без движения 0,4 с (выбор нескольких в библиотеке — 0,5 с) — удержание (HoldDrag: перетаскивание через ReorderState.hold, вид — ReorderDrag); отпустили раньше — тап. Урок: жесты SwiftUI на строке в ScrollView iOS 18 (LongPressGesture + DragGesture, simultaneousGesture) забирают касание у прокрутки; два распознавателя UIKit на одной строке (свайп и удержание) мешают друг другу — удержание ждёт, пока свайп возможен; распознаватель UIKit подключается только .gesture, не .simultaneousGesture.
- Редактор сэмпла: MONO, CUT, TRIM, NORMALIZE, CLEAR.
- CHORD по ТЗ: 6 типов по ступеням гаммы (Scales.chordKinds, chordDegrees; Chords — названия, ступени, случайная прогрессия; Track.writeProgression), подписи клавиш, окно типов по удержанию, SHIFT + CHORD — прогрессия на выбранные страницы; VARIANT и пресеты прогрессий убраны (тесты ChordTests).
- COMP и CLIP: LEVEL на всю ширину, окно TRANSFER поверх слева, полупрозрачное (волна видна). Пробовали и откатили: дисплей WAVE, кривая на весь дисплей, продление кривой до верха.
- SETTINGS → APPEARANCE → MASTER FX DISPLAY SCALE: 48 / 32 / 16 dB (AppSettings.displayScale → MasterDraw.scale).
- Окна SAT, COMP, CLIP: черта в строке полей — над правым краем TRANSFER (MasterStrip.leadFields); SAT — TRANSFER и SPECTRUM слитно.
- Кража голоса синта — самый тихий голос, τ 2,5 мс, нота через 18 мс; быстрое гашение перекрывает медленное (тест ChordStealTests). KICK: DRIVE плавно по отсчётам (KickDriveTests).
- DELETE в меню страницы — только эта страница (Track.deletePages single). SAVE DEFAULT EQ — только у мастера. Имя своей таблицы WTABLE (AppModel.tableName).
- Порядок своих папок библиотеки: первая версия откатывалась (жест строки и прокрутка мешали друг другу), вернули с RowGesture (см. выше).
- Облегчение сборки (2.11): отложенные вызовы — Later.run / Later.every вместо Task + sleep (−11 тыс. инструкций IR), кнопки меню списком в 8 меню (−4 тыс.); итог 1,633 млн (было 1,649).

## Правки 4.11–7.11 — RANDOM по стилям и ролям (решения пользователя; на iPad — сборка со второго раза)
- Стили (DrumRhythm): House, Techno (с Minimal), Breaks/D&B (D&B от 150 BPM), Trap/R&B (Trap от 115 BPM), Pop, Ambient; один стиль на проект (STYLE ALL TRACKS убран), формат проекта 7 (migrateRandomStyles: Afro → House, Minimal → Techno); CLAP — рисунок SNARE; роллы хэта (p-lock Ratchet), Chance у Ambient и хэта Techno; AUTO SWING (SETTINGS → RANDOM); подписи «Breaks/D&B», «Trap/R&B» в окне стилей — в две строки с линией (InkButton split).
- Роли дорожек (MelodyRhythm.role): ARP, KEYS (CHORD), BASS (SUB, имя сэмпла, октава до C2), PAD (TEXTURE, GRANULAR, имя сэмпла), LEAD; ударные сэмплы — по имени файла (DrumRhythm.roleByName, Track.drumRoleBy; нарезанный — нарезка). Партии: бас (MelodyRhythm.bass), KEYS и PAD (ChordParts: прогрессии стиля, типы аккордов и расположение голосов по стилю), LEAD (LeadPart: мотив A A′ A B), арпеджио с фигурами (ArpRandom); BASS и LEAD — по последней прогрессии. Ансамбль — STEPS ALL TRACKS (AppModelEnsemble: партии на все дорожки по одной прогрессии).
- Нарезка (SliceRhythm.Role): KICK, SNARE (и клэп), HAT, PERC, BASS, LEAD (мелодия или аккорды), PAD; номера 0…3 — прежние LOW, MID, HIGH, LONG, 4 (CLAP одной из проб) — SNARE. Редактор сэмпла: при ролях WARP скрыт, роли — поровну; флажок берётся только за сам флажок, второй палец при масштабе флажки и метки WARP не берёт.
- Убраны: свайп ARP по CHORD (только рычажок ARPEGGIATOR), STEP SWIPE (PAINT), панда (объём сборки), Track-запись прогрессии из UI (writeRandomProgression).
- Сборка: 1,681 млн после R1–R8 (8017c55 падала в Xcode — chordPages private) → таблицы рисунков строками (DrumRhythm.pat, −2,4 тыс.), без обобщённых генераторов (Rng — без выигрыша), панда (−8 тыс.) → 1,671 млн (9a56903) — на iPad со второго раза. Урок: одно имя с разными параметрами (role(engine:) и role(name:), drumRole и drumRole(name:)) — переименовано, Playgrounds такого не собирает.
- Тесты Core: DrumRhythm (стили, темп, роллы, миграция, имена сэмплов), MelodyRhythm (роли, бас), ChordParts и StyleChords, LeadPart, ArpRandom, SliceRhythm (роли); всего 572+.

S14w — на iPad; CoreTests — 304 (новые: EngineIconTests — testPreviewsMatchPrototype, testGridFiniteInField, testEachKnobChangesIcon, testTableFrame; testApplyKnobsToAllPages, testFeedbackFollowsResolveAcrossInputs; убраны прежние тесты иконок веба). S14v — на iPad. S14a — тесты Core (HeavyLoadTests), DIAGNOSTICS на iPad. CoreTests — 298 (S14a: testHeavyProjectProfile, testProfileOffAndOn); 296 (новые: testMoveRow, testPasteTrackKeepsOwnPatterns, testClipSpeed, testQueuedClipAfterSlowClip, testSameNameIgnoresAudioExtension).

## Правки 8.11 (решения пользователя; на iPad — сборка с первого раза, fe2ca0a — 1,630 млн)
- RANDOM: LEAD в Techno — гипнотическая ячейка (полиметрия и евклидовы ритмы, HypnoticLead.swift); SHOW PART TYPE — раздел PART (BASS, LEAD, PAD) в окне CHORD с выбором типа партии; роли по имени сэмпла — новые слова; случайные партии сэмпла — по его определённой ноте; на клавишах CHORD — нота с октавой (sequencer.md, settings-midi-sync.md).
- Вылет: тап по пресету EQ — чтение project внутри edit (двойной доступ, SIGABRT); число дорожек — до правки. Других таких мест скрипт не нашёл.
- SHIFT + тап по Speed LFO — снова по темпу: после перестановки ручек строками Speed искался в прежних ячейках 4…6; теперь — по id.
- MIX: вместо LFO/ENV и FX, MOD, SHIFT, MORPH — пустое поле на группу; загрузка сэмпла из видео (LOAD, SOURCE, REF, IMPORT библиотеки); пресет коррекции AIAIAI TMA-2 Studio Wireless+; значок наушников над CPU, пока цепочка прослушивания меняет звук (ui-layout.md, sound-sampler.md, fx-eq.md).

## Правки 8.11, вечер (решения пользователя; на iPad — 32510f2 со второго раза, MIDI проверено)
- ANALOG: модуляция B осциллятором A — SHIFT + тап по WAVE A (вкл./выкл.), по 1.3 — SYNC → FM → RING (1.3 — AMOUNT), по WAVE B — B на октаву ниже; значения звука analog.mod, analog.oct (VoiceParam.amod, aoct — пресет-лок их переносит, p-lock шага нет). DSP — один путь Core/Jambo/JamboAnalog.swift (без модуляции — как прежде, эталоны веба совпадают), SYNC — PolyBLEP по событиям (сброс и свои скачки), режимы — кроссфейд 5 мс; значения и подписи — Core/Model/AnalogMod.swift; тесты AnalogModTests (docs/ai/synth-engines.md).
- TEXTURE по ТЗ docs/texture-engine.md: Color, Grit, Tone, Metal (MOTION, DENSITY и внутренняя модуляция убраны); старые 1.2 и 1.4 — без перевода; приёмка раздела 5 — TextureEngineTests (уровень ±34 %, CV 0,06 / 0,12, корреляция L/R 0,20 — по формуле ТЗ, в ТЗ «около 0,5»); пояснения под ручками и подсказка движка не делались (надписи английские).
- MIDI-клок: SEND CLOCK и RECEIVE CLOCK — рычажки, можно вместе (принятый клок раздаётся, стоя — точный темп входящего; на устройство-источник — по имени — не уходит); CLOCK OUTPUTS — набор выходов (SyncSettings.clockOuts; старые source и clockOut переводятся). SYNC — только клок.
- MIDI нот — только у дорожек: общий вход INPUT в MIDI → DEVICES убран (MidiSettings.input при чтении пропускается); вход нот дорожки по умолчанию NONE (TrackMidi.inOn = false); проекты до версии 8 — вход по умолчанию (ALL INPUTS, канал ALL) → NONE (Project.migrateMidiIn, версия формата 8). Проверено пользователем: «MIDI работает».
- Объём сборки (замеры [calibrate]): 1,641 млн (с модуляцией ANALOG, на iPad не собралось) → ANALOG одним путём 1,637 → «коробки» в модели: ArrBlock.pattern и Clip.src 1,599, Track.home 1,582, TrackMore (редкие поля дорожки) 1,572, ProjectMore (редкие поля проекта) 1,537. «Коробка» — массив из 0 или 1 элемента (копия при записи) вместо вложенной структуры; снаружи — прежние свойства (get/set), запись — своей encode по тем же ключам, формат файла прежний; проверка ProjectFileTests.testCodingKeysCoverAllFields знает имена коробок. 1,586 (32510f2) на iPad — со второго раза; 1,536 (c3b02fe) — собирается.
- Открыто: фильтр (предложено: SHIFT + тап по Filter — тип 12 dB / LADDER (Moog 24 dB, насыщение) / BP у всех движков и сэмплера, ручка как прежде, старые проекты без перевода; у SUB по умолчанию LADDER, GRIT — перегруз входа лестничного фильтра; переводить ли старые SUB в LADDER — спросить). GRIT у SUB на квадрате почти не слышен — свойство мгновенного насыщения (проверено моделью: и пред-подъём верхов, и резонанс перед tanh квадрат не меняют); лестничный фильтр с перегрузом квадрат меняет (верха над срезом +6…10 dB, резонанс «укрощается»). Звук ANALOG с модуляцией и нового TEXTURE пользователь ещё не оценивал.

## План (подтверждён пользователем)
- S14v — правки интерфейса (готово, проверено на iPad).
- S14a — замеры: в колбэке — время по разделам (голоса, FX, EQ, мастер, метры и запись), среднее и пик блока — в DIAGNOSTICS; тест Core «тяжёлый проект» (8 дорожек, синт аккордами, сэмплы, FX, EQ Dynamic, весь мастер) — отладочная и релизная сборка на Linux; в DIAGNOSTICS — время кадра интерфейса и пропущенные кадры; пользователь делает один замер на iPad своим тяжёлым проектом — дальше чинить по цифрам.
- S14b — оптимизация звука: только горячие места по замерам S14a, по правилам отладочной сборки Playgrounds; после каждой правки — сверка с эталонами (тесты и SELF-TEST).
- S14c — интерфейс и MIDI (готово, проверено на iPad): лишние перерисовки (наблюдаемое состояние, таймеры); задержка нот с MIDI — сначала спросить пользователя, осталась ли; если да — путь MIDI → звук мимо главного потока; разделить Sampler.swift.
- S14d — проверка S13e на iPad (меню SYNC, клок SEND / RECEIVE с внешним устройством), затем описание Swift-версии в docs/ai/settings-midi-sync.md.
- S14e — App Store: Ableton Link — по лицензии Ableton (решение пользователя): для App Store — бесплатная лицензия Ableton (запрос — пользователь, link-devs@ableton.com; руководство Link, проверка интеграции); LinkKit (C++) в Playgrounds не подключить — сборка в Xcode на Mac (этап 9, спайк B0); до этого раздел ABLETON LINK скрыт. Privacy manifest PrivacyInfo.xcprivacy (UserDefaults, mach_absolute_time) — через Resources, проверить пробной загрузкой. Значок — только в Playgrounds (сейчас .placeholder). App Store Connect — пользователь: Team ID, версия, шифрование (ответ при каждой загрузке), политика конфиденциальности (URL), возрастной рейтинг, скриншоты iPad 13", TestFlight.
- Итог — docs/SWIFT_MILESTONE_S14.md (создан; в конце вехи обновить).

## Открыто
- Объём сборки 1,671 млн (со второго раза): облегчить до ~1,63 (крупные файлы — ArrangeWindow, LibraryBrowser, PatternGrid, EqView, RootView; профиль 7.11). Звук партий RANDOM на iPad — проверить и подстроить таблицы.
- Тексты docs/ai и ios/CLAUDE.md по правкам S14v — предложены, ждут подтверждения.

## Аудит перед App Store (готово)
- Раздел ABLETON LINK скрыт; PrivacyInfo.xcprivacy (UserDefaults CA92.1, SystemBootTime 35F9.1) — в Resources, место в бандле видно в DIAGNOSTICS (строка Privacy) — проверить на iPad; TEST TONE и Tap в DIAGNOSTICS — только с DEBUG.
- PlayClock — барьеры памяти в seqlock; предпрослушка ▶ гаснет, если сэмпла нет в новом снимке; Reverb — reset() без массива, денормали в all-pass и биквадах.
- Открыто: значок и URL политики конфиденциальности (пользователь); пробная загрузка — privacy manifest и ориентация только альбомная; индикатор микрофона при .playAndRecord. Сделано: trace — только в отладочной сборке (#if DEBUG); предел распаковки ZIP — 512 МБ на файл (больше — пропускается), 2 ГБ на архив (больше — импорт отменяется), тесты testInflateLimit, testZipLimits; CoreTests — 453. Сделано также: CORRECT EQ — коррекция наушников (PhonesEq.swift, профиль Sony WH-1000XM4); SAVE DEFAULT в PRESETS модулей мастера и EQ (KnobDefaults.eqTrack / eqMaster, параметры модулей — область mst); SAVED жёлтым; предупреждение при импорте архива больше 2 ГБ и о пропущенных файлах больше 512 МБ. CoreTests — 457. IMPORT и EXPORT профилей коррекции (PhonesProfile.swift: формат AutoEQ, подгонка PhonesFit); CoreTests — 459. Проверено на iPad.
