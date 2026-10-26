# Handoff: JAMbo, Swift-версия — S15 аранжировщик готов (S15a–g, проверено на iPad); S14c готов; идёт S14d — выбор входа клока в SYNC

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6); итоги вех — `docs/SWIFT_MILESTONE_Sx.md`. Поведение аранжировщика — `docs/ai/arranger.md`; MIDI — `docs/ai/settings-midi-sync.md` (в ветке swift описывают Swift-версию).

## 2. Принятые решения
- S15 — аранжировщик (готов, проверен на iPad; затем — решение пользователя — снова S14, с S14c). Спецификация — docs/ai/arranger.md, итог — docs/SWIFT_MILESTONE_S15.md. План:
  - S15a — данные, S15b — игра в колбэке, S15c — экран, S15d — секции, петля, INSERT (готово; несколько кругов правок по iPad — проверены пользователем).
  - S15e — перенос из сетки (готово): e1 — TO ARRANGE в меню строки (END / CURSOR; длина строки — самый длинный клип × REPEATS, LOOP ROW — один проход; короткие клипы и пустые ячейки повторяются до длины строки; секция — имя строки); e2 — журнал запусков за 32 такта и SEND TO ARRANGE в бутерброде сетки (END / CURSOR); e3 — запись аранжировки REC + PLAY + AUTO (всё, что играет в сетке, с курсора; одна запись UNDO в конце).
  - S15f — автоматизация на таймлайне (решения пользователя: в этой вехе, до REF; все 16 ручек сетки; кривая на таймлайне дорожки, не в паттерне; отдельной кнопки записи нет — AUTO показывает строки кривых, REC + PLAY + AUTO пишет и запуски клипов, и повороты ручек, у AUTO — красная обводка; рука перебивает кривую, кривая не меняется; отображение на ручке — как в вебе: дуга и стрелка по кривой, жёлтая риска; магнит — точки на линиях сетки таймлайна). Готово: f1 — данные и воспроизведение, f2 — строки кривых под выбранной дорожкой (тап — точка, сдвиг — двигать, двойной тап — удалить; «+» — ручки; CLEAR / DELETE), f3 — запись поворотов ручек.
  - S15g — REF (готово, проверено): строка REF сверху (дорожки на строку ниже), A/B слева от линейки, громкость REF — регулятор измерителя в положении B, референс мимо мастера и громкости выхода, играет только с таймлайна, темп файла определяется сам (показывается в заголовке, темп проекта не меняет); заголовок REF — две строки; меню REF (LOAD, DELETE) по двойному тапу; сдвиг волны без магнита. Заголовки дорожек и список окна AUTO — до левого края SCALE.
- Решения пользователя — круг S15f′ (подробно — docs/ai/arranger.md, SWIFT_MILESTONE_S15.md «S15f′»):
  - Раскладка в одном масштабе: строка кнопок высотой с верхнюю миниатюру паттернов (строка папки ◀ ▶ — над превью, верхние строки EQ и окон мастера — той же высоты); окно аранжировщика — линейка и 8 строк через чёрные зазоры 6 pt; низ экрана — 3 строки и 2 зазора (верх — верх шестой дорожки), клавиатура — на остаток.
  - Строка кнопок аранжировщика: слева (по ширине превью) магнит, TRIM, курсор в начало, LOOP; справа (по ширине миниатюр) AUTO, окно ручек, STEPS (значок), REF; под ними — ровный фон. INSERT и A/B убраны (место A/B пользователь скажет позже); GRID — в SETTINGS → ARRANGE, по умолчанию 1/4.
  - STEPS (по умолчанию горит) — строка дорожек, секвенсор, клавиатура поверх дорожек 6–8; окно ручек — поверх линейки и дорожек 1–5 (обычный масштаб, чёрная полоса снизу); AUTO — окно автоматизации на месте STEPS; дорожки не сжимаются, прокрутка. Пианоролл — вместо аранжировщика (поверх — пробовали, возвращено).
  - Окно AUTO: слева список кривых строками и «+» пунктиром (меню ручек), справа — кривая выбранной строки под таймлайном; строк кривых под дорожкой нет.
  - Дорожки: EXPANDED — строка 1/8 окна, COMPACT — все в окно, масштаба по вертикали нет; заголовки без метров, M над S по высоте строки. Выделение рамкой (удержание по пустому) — группа: перенос, DUPLICATE, DELETE.
  - Секции без цвета: тонкие жёлтые линии, имя по центру, края тянутся, сама не двигается. Плейхед тянется, во всю высоту линейки, едет плавно; слева от линейки — время плейхеда / длительность.
  - Палитра — без #B8902A, квадраты; клавиатура по умолчанию — одна октава.
- Решения пользователя по экрану аранжировщика (предыдущий круг; часть заменена кругом S15f′ выше): линейка и левые углы таймлайна прямые; заголовки дорожек вплотную к таймлайну, их правые углы прямые; цвет дорожки — только у блоков (заголовок как строка дорожек); в палитре дорожки — квадратик «нет цвета» (перечёркнутый круг) вместо DEFAULT, у секции «нет цвета» нет; секция создаётся только из выделенного диапазона (двойной тап по пустому месту строки секций — ничего); в окне секции нет CURSOR HERE; маркер плейхеда — жёлтый пятиугольник во всю высоту строки секций; измеритель справа тянется до низа окна (STEPS); TO ARRANGE в меню строки — с отступом от остальных кнопок.
- Порядок вех: S13 MIDI → S14 оптимизация и App Store (на паузе) → S15 аранжировщик (с автоматизацией на таймлайне) → S16 автоматизация в паттернах (нужна ли — открыто).
- План S14 (подтверждён пользователем; порядок — его решение: сначала правки интерфейса, затем оптимизация, проверка S13e, App Store):
  - S14v — правки интерфейса (готово, проверено на iPad).
  - S14a — замеры (готово, проверено на iPad): DIAGNOSTICS — время колбэка по разделам (Seq, Samples, Synth, EQ, Mix, FX, Master, Meters, Audio: avg · peak · worst с RESET), кадры интерфейса (UI, UI total), Drain; тест Core «тяжёлый проект».
  - S14w — превью-иконки движков из прототипа, заголовок окна звука, октава клавиатуры по дорожкам, MIDI MAP Apply to all pages, исправлена обратная связь MIDI на MIX/MOD/FX/MST (готово, проверено на iPad; подробно — SWIFT_MILESTONE_S14.md).
  - S14b — оптимизация звука (готово, проверено на iPad): Audio на проекте пользователя 78 → 43 % в среднем, худший блок 110 → 66 %; щелчков и изменений звука нет.
  - S14c — интерфейс и MIDI (готово, проверено на iPad; итог — SWIFT_MILESTONE_S14.md): лишние перерисовки (наблюдаемое состояние, таймеры); задержка нот с MIDI — сначала спросить пользователя, осталась ли; если да — путь MIDI → звук мимо главного потока; разделить Sampler.swift.
  - S14d — проверка S13e на iPad: RECEIVE и SYNC START/STOP (выкл. — свой PLAY и STOP независимы) и SEND (Digitakt по USB) пользователь проверил — работает; описание Swift-версии — docs/ai/settings-midi-sync.md (готово); решение пользователя — в SYNC выбор устройства, с которого принимается клок (RECEIVE).
  - S14e — App Store: Ableton Link — по лицензии Ableton (решение пользователя): для App Store — бесплатная лицензия Ableton (запрос — пользователь, link-devs@ableton.com; руководство Link, проверка интеграции); LinkKit (C++) в Playgrounds не подключить — сборка в Xcode на Mac (этап 9, спайк B0); до этого раздел ABLETON LINK неактивен. Privacy manifest PrivacyInfo.xcprivacy (UserDefaults, mach_absolute_time) — через Resources, проверить пробной загрузкой. Значок — только в Playgrounds (сейчас .placeholder). App Store Connect — пользователь: Team ID, версия, шифрование (ответ при каждой загрузке), политика конфиденциальности (URL), возрастной рейтинг, скриншоты iPad 13", TestFlight.
  - Итог — docs/SWIFT_MILESTONE_S14.md (создан; в конце вехи обновить).
- План S13: a — CoreMIDI, устройства, ноты (готово); b — маппинг и LEARN (готово); c — окно MIDI MAP и пресеты (готово); d — обратная связь (готово); e — SYNC (меню, SYNC QUANTUM, MIDI-клок SEND / RECEIVE, офсеты, TempoSource; настройки Link только хранятся; готово, проверено на iPad); f — Bluetooth MIDI (CONNECT и ADVERTISE — CABTMIDICentralViewController и CABTMIDILocalPeripheralViewController; capability Bluetooth Always в Package.swift; готово, проверено на iPad). Итог — SWIFT_MILESTONE_S13.md.
- Решения пользователя в S13:
  - Нота с MIDI держится до Note Off (в вебе — один шаг).
  - TWISTER PRESET и встроенный пресет Twister убраны (пользователь сохранит свой).
  - Кнопка AUTO заменена целью ROLL (пианоролл); добавлены цели REDO, LEVEL (регулятор измерителя), XFADER (кроссфейдер MIX, закреплённая строка в MAPPING).
  - У 16 ручек два назначения: поворот (KNOB c.r) и нажатие (KNOB c.r PRESS); TURN / PRESS на полосе LEARN; KNOB PRESS = TOUCH (по умолчанию ON) — нажатие как палец (касание, двойной тап), OFF — Action из MIDI MAP.
  - GLOBAL у ручки — параметр места назначения (MidiPlace: страница и дорожка).
  - Ячейки и строки сетки — Clip launcher или Global.
  - Рамка цели в LEARN — жёлтая; условие в списке — GLOBAL / PAGE / CLIPS; в списке — устройство.
  - Темп с MIDI — целыми BPM; имена пресетов маппингов — до 40 знаков.
  - Тип Button latch — переключатель на контроллере (127 — вкл., 0 — выкл.; TouchOSC toggle); LEARN ставит momentary.
  - Обратная связь — каждый кадр (60 Гц; в вебе 30 мс), фейдеру ABSOLUTE, который двигают, — без эха 0,3 с; нажатие ручки (PRESS) обратную связь не шлёт (у Twister этот источник — цвет подсветки).
  - DONE на полосе LEARN закрывает и окно MIDI MAP.
  - SETTINGS → RECORD → STEP SWIPE: LENGTH / PAINT.
- Ableton Link: LinkKit, -lc++ и entitlement multicast в Playgrounds невозможны — сам Link остаётся этапу 9 (спайк B0), в S13e — только меню и настройки.
- Термины (CLAUDE.md): сэмпл-лок — шаг со своим сэмплом, пресет-лок — шаг со своим пресетом синта.


## 3. Текущая задача
S14d — в меню SYNC выбор устройства, с которого принимается клок при RECEIVE (решение пользователя); описание — в docs/ai/settings-midi-sync.md (текст — предложить пользователю). Затем S14e (App Store).

## 4. Что уже решено
- S15g (REF): Core/Engine/RefPlayer.swift (после мастера, A/B, Levels.ref), Core/Sampler/TempoDetect.swift, ArrRef и Arrangement.showRef; UI/AppModelArrangeRef.swift (RefWave, BrowserMode.ref, refBActive), ArrRefHeader, ArrRefMenu, ArrABSwitch, ArrMetrics.refRow / body / inRef. Тесты RefTests, TempoDetectTests; CoreTests — 394.
- S15 (Core): Arrange.swift, ArrangeEdits.swift (блоки, секции, rowToArrange), ArrangeJournal.swift (ArrJournal, sendToArrange), ArrangeRecorder.swift (ArrRecorder, applyRecording), ArrangeAuto.swift (ArrAutoLane, ArrAutoTarget, Track.autos, simplify, recordAuto); Sequencer/ArrangePlay.swift, ArrangeAutoPlay.swift (подстановка кривой в снимок звука на блок, autoHold); SeqData — блоки, autoFirst/autoCount/autoX/autoY, probLock. Тесты — ArrangeTests, ArrangePlayTests.
- S15f′ (UI): RootView.units / arrangeArea (раскладка), Layout.piano / pairHeight, AppModel.barH / arrLowerH / arrInset / arrKnobs / arrGroup / arrMarquee; ArrangeBar (новая строка, ArrStepsIcon), ArrangeAutoPanel.swift (ArrAutoPanel, ArrAutoList, ArrAutoAddMenu, ArrAutoLaneMenu, ArrAutoCurve, ArrAutoTouches), ArrCursorLayer и ArrTotalTime (ArrangeWindow.swift); Core — Project.moveBlocks / duplicateBlocks / deleteBlocks, setMarkerStart / setMarkerEnd, ArrPalette.removed. Тесты testBlockGroup, testSectionEdges; CoreTests — 394.
- S15 (UI): ArrangeWindow (ArrMetrics, ArrTimeline, ArrDraw), ArrangeHeaders (+ ArrAutoHeaders), ArrangeTouches, ArrangeRuler, ArrangeMenus, ArrangeBar, AppModelArrange, AppModelArrangeMarks (SEND TO ARRANGE, запись), AppModelArrangeAuto (строки кривых, запись ручек, рука); LiveState — тик, журнал, recorder, arrPosTime.
- S0–S12 готовы и проверены на iPad; S13a–d и S13f проверены на iPad (обратная связь — с TouchOSC по Bluetooth); S13e — RECEIVE и SEND проверены (SEND — с Digitakt по USB). S14v, S14a, S14b готовы и проверены на iPad. CoreTests — 394.
- Правки после проверки с Digitakt по USB (подробно — SWIFT_MILESTONE_S13.md, S13e): ClockFollower — после пропажи клока шаги заново привязываются к тикам (anchored; и после перезапуска звука), пропуск тиков — окно темпа заново с досчётом тиков, темп — после 4 тиков; MidiHost — при смене настройки MIDI подключённые источники не переподключаются; AudioHost — один перезапуск движка на пачку уведомлений (через 0,3 с), задержка выхода запоминается при запуске и смене маршрута; строка «Now:» — out, in, restarts, route changes, audio speed. Digitakt в режиме USB AUDIO/MIDI звук с iPad не принимает (и у других приложений: выход прыгает на динамик, секвенция тормозит) — из приложения не исправить, работать в режиме USB MIDI.
- S14a: Core/Util/RenderProfile (метки разделов в AudioCore, Sampler, MasterChain; включён всегда, RESET — худшее заново), UI/FrameMeter (CADisplayLink, drain), DiagnosticsView; тесты HeavyLoadTests (тяжёлый проект), SynthCostTests (цена голоса по движкам).
- S14b: синт — фильтр децимации jHalf/dHalf (пары отводов без цикла), sineD и буфер в Double, knob() без захвата и таблица битов p-lock; FX — покой Reverb и Delay в FxRack (sleep(), ниже −120 dB), Drive без пересчёта незвучащих кривых; Drive, SAT, CLIP, true peak лимитера — свёртки по 4 отвода со сдвигом указателей (fxDot, satDot, clipDot), кривые @_transparent; состояние циклов мастера — в локальных. Релизная сборка на Linux: `swift test -c release -Xswiftc -enable-testing` (Swift 6.0.3 падал на Drive.wet и Saturator.wet — позиции колец в локальных).
- Core/Midi: MidiMessage (разбор UMP MIDI 1.0), MidiSettings (вход, выход, ноты, mappings, preset, pressTouch), MidiMapping (цели, типы, энкодеры, условия, MidiPlace), MidiMapper (условия, LEARN, правка, MidiToggles), MidiPresets, MidiFeedback (действующие маппинги, значение в Range, только изменения), SyncSettings (меню SYNC). Core/Sequencer: ClockPlan (клок SEND), ClockFollower (клок RECEIVE); Sequencer.start(at:) и clockPhase, InternalTempoSource.shift. Тесты — MidiTests, MidiMapTests, MidiPresetTests, MidiFeedbackTests.
- Audio/MidiHost.swift — клиент CoreMIDI, все источники, списки устройств; сообщения — на главный поток; выходной порт и send (обратная связь).
- UI: AppModelMidi (разбор, ручки, PRESS, BPM, LEVEL, XFADER), AppModelMidiMap (окно, пресеты, подписи), MidiButtons (имена и действия кнопок), MidiLearnState, MidiLearnViews (полоса LEARN, метки), MidiMenu (DEVICES, MAPPING, NOTES), MidiMapWindow и MidiMapPages. withKnobPlace (AppModel.swift) — действие ручки на другом месте. AppModelMidiFeedback — обратная связь (из drain), Button latch, состояние кнопок (midiLit). SyncMenu (меню SYNC), AppModelSync (клок SEND и RECEIVE из drain, midiRealtime).
- Настройки — AppSettings.midi (UserDefaults "settings"), пресеты маппингов — UserDefaults "midiPresets".

## 5. Что осталось решить
- Аранжировщик: кнопки возврата дорожек к таймлайну во время игры нет — нужна ли и где; инерция прокрутки; меню блоков и дорожек у нижних дорожек может уйти под окно STEPS / AUTO; подставлять ли темп референса в проект (сейчас только показывается).
- Автоматизация: кривые действуют только у дорожек на таймлайне, при игре из сетки — нет (решение пользователя). Duck, Chance, Ratchet на кривых отдельно не проверялись.
- Автоматизация в паттернах (как в вебе) — нужна ли, веха S16; на таймлайне — сделана в S15f.
- Значок и URL политики конфиденциальности — пользователь.
- На iPad проверить строку Privacy в DIAGNOSTICS (manifest должен быть в корне бандла).
- Тексты docs/ai (tracks-mixer, patterns-projects, master-chain, ui-layout, sequencer, sound-sampler), ios/CLAUDE.md («Решения») по правкам S14v — предложены пользователю, ждут подтверждения (внести в конце вехи вместе с итогом).
- PLAY сэмплера на 1.4 — новая реализация (решение пользователя: прежняя не понравилась).
- Номера готовых к записи дорожек при удалении или перестановке дорожек не пересчитываются (как в вебе).
- Sampler.swift — больше ~600 строк, разделить при случае.
- Правки микшера и мастера во время перехода MIX в файл не попадают (открыто в S10).
- Чистка неиспользуемых сэмплов (Samples, Tables) — позже, по решению пользователя.
- Задержка MIDI: ни у нот, ни у маппинга пользователь не замечает — путь MIDI → звук не меняем.

## 6. Важные ограничения
- Отладочная сборка Playgrounds (S14b): встраивается только @_transparent (@inline(__always) — обычный вызов; @_transparent нельзя на методах класса — функции файла); каждый вызов обнуляет кадр стека; rounded(.down) и обобщённый abs медленные (пол — через Int при значении ≥ 0); Double(Float) — вызов; свойство класса — проверка доступа (в цикле — локальные). Горячее место искать профилем callgrind (valgrind в облаке есть) на тестах Core, сверять по числу инструкций.
- Колбэк: без выделений, блокировок, Swift-коллекций; запись из колбэка — через кольцевые буферы, файл пишется вне колбэка. MIDI → аудио — через CoreEvent и SPSCQueue (одна очередь — один производитель).
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Имена файлов в одном модуле не повторяются и в разных папках (S15f: два ArrangeAuto.swift — «multiple producers»; файл колбэка переименован в ArrangeAutoPlay.swift).
- У обобщённого типа (ButtonPair<L, R>) нельзя статическое хранимое свойство — константы в Layout (S15f′: сборка падала).
- Шаг строк аранжировщика — ArrMetrics.pitch (строка + зазор); высоты строки кнопок и низа — только из RootView.units (не задавать вручную).
- Имена новых типов проверять на совпадение с уже существующими (Core и UI — один модуль; в S13 вид MidiPage совпал с типом Core — переименован в MidiMenuPage). Проверка: grep объявлений struct/class/enum по всему JAMbo.swiftpm, `sort | uniq -d`.
- Playgrounds: выражения — по шагам с явными типами; UI на Linux не собирается — проверка только на iPad.
- Package.swift — в виде Playgrounds; capabilities — только те, что пользователь добавил в Playgrounds; capabilities — перед appCategory.
- Жесты в прокручиваемых списках: удержание — simultaneousGesture(LongPressGesture), не onLongPressGesture.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕; меню закрываются тапом мимо.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат, не в рабочую папку репозитория. PR — только по просьбе.
- Скриншоты пользователя могут быть от старой сборки — сверять с последним коммитом.
- Звуковые ошибки (щелчки) — воспроизводить сценой пользователя в тесте Core и мерить; при сомнении — стенд-страница с AudioWorklet (как SUB Bench в S12).

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md и docs/SWIFT_MILESTONE_S14.md. Продолжаем S14d — выбор входа клока в SYNC»
