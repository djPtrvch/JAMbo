# Handoff: JAMbo, Swift-версия — S13 (MIDI), дальше S13d

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6); итоги вех — `docs/SWIFT_MILESTONE_Sx.md`. Поведение MIDI — `docs/ai/settings-midi-sync.md` (в ветке swift описывает Swift-версию).

## 2. Принятые решения
- Порядок вех: S13 MIDI → S14 оптимизация и App Store → S15 автоматизация.
- План S13: a — CoreMIDI, устройства, ноты (готово); b — маппинг и LEARN (готово); c — окно MIDI MAP и пресеты (готово); d — обратная связь; e — SYNC (меню, SYNC QUANTUM, MIDI-клок SEND / RECEIVE, офсеты, TempoSource; настройки Link только хранятся); f — Bluetooth MIDI (CONNECT и ADVERTISE — CABTMIDICentralViewController и CABTMIDILocalPeripheralViewController; capability Bluetooth добавляет пользователь), итог SWIFT_MILESTONE_S13.md.
- Решения пользователя в S13:
  - Нота с MIDI держится до Note Off (в вебе — один шаг).
  - TWISTER PRESET и встроенный пресет Twister убраны (пользователь сохранит свой).
  - Кнопка AUTO заменена целью ROLL (пианоролл); добавлены цели REDO, LEVEL (регулятор измерителя), XFADER (кроссфейдер MIX, закреплённая строка в MAPPING).
  - У 16 ручек два назначения: поворот (KNOB c.r) и нажатие (KNOB c.r PRESS); TURN / PRESS на полосе LEARN; KNOB PRESS = TOUCH (по умолчанию ON) — нажатие как палец (касание, двойной тап), OFF — Action из MIDI MAP.
  - GLOBAL у ручки — параметр места назначения (MidiPlace: страница и дорожка).
  - Ячейки и строки сетки — Clip launcher или Global.
  - Рамка цели в LEARN — жёлтая; условие в списке — GLOBAL / PAGE / CLIPS; в списке — устройство.
  - Темп с MIDI — целыми BPM; имена пресетов маппингов — до 40 знаков.
  - SETTINGS → RECORD → STEP SWIPE: LENGTH / PAINT.
- Ableton Link: LinkKit, -lc++ и entitlement multicast в Playgrounds невозможны — сам Link остаётся этапу 9 (спайк B0), в S13e — только меню и настройки.
- Термины (CLAUDE.md): сэмпл-лок — шаг со своим сэмплом, пресет-лок — шаг со своим пресетом синта.

## 3. Текущая задача
S13d — обратная связь: значения ручек уходят на выход (в своём диапазоне Range, только изменения), кольца Twister повторяют экран; кнопки шлют 127, когда горят (PLAY играет, REC, PATTERNS, EQ, зажатые LFO/ENV/FX/MOD, MORPH, выбранная дорожка, MUTE/SOLO/ARM, триг на STEP), иначе 0; Feedback port маппинга — Default (DEVICES → FEEDBACK OUTPUT), None или выход. Отправка — MIDISendEventList, вне колбэка, по таймеру UI.

## 4. Что уже решено
- S0–S12 готовы и проверены на iPad; S13a–c проверены на iPad. CoreTests — 278.
- Core/Midi: MidiMessage (разбор UMP MIDI 1.0), MidiSettings (вход, выход, ноты, mappings, preset, pressTouch), MidiMapping (цели, типы, энкодеры, условия, MidiPlace), MidiMapper (условия, LEARN, правка, MidiToggles), MidiPresets. Тесты — MidiTests, MidiMapTests, MidiPresetTests.
- Audio/MidiHost.swift — клиент CoreMIDI, все источники, списки устройств; сообщения — на главный поток.
- UI: AppModelMidi (разбор, ручки, PRESS, BPM, LEVEL, XFADER), AppModelMidiMap (окно, пресеты, подписи), MidiButtons (имена и действия кнопок), MidiLearnState, MidiLearnViews (полоса LEARN, метки), MidiMenu (DEVICES, MAPPING, NOTES), MidiMapWindow и MidiMapPages. withKnobPlace (AppModel.swift) — действие ручки на другом месте.
- Настройки — AppSettings.midi (UserDefaults "settings"), пресеты маппингов — UserDefaults "midiPresets".

## 5. Что осталось решить
- PLAY сэмплера на 1.4 — новая реализация (решение пользователя: прежняя не понравилась).
- Номера готовых к записи дорожек при удалении или перестановке дорожек не пересчитываются (как в вебе).
- Место кнопки AUTO — в S15.
- Sampler.swift — больше ~600 строк, разделить при случае.
- Правки микшера и мастера во время перехода MIX в файл не попадают (открыто в S10).
- Чистка неиспользуемых сэмплов (Samples, Tables) — позже, по решению пользователя.
- Задержка нот с MIDI (сообщение — через главный поток): пользователь замечал «затормаживание» при назначении; после правки LEARN (без записи на каждое сообщение) — проверить; если останется — путь MIDI → аудио мимо главного потока.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций; запись из колбэка — через кольцевые буферы, файл пишется вне колбэка. MIDI → аудио — через CoreEvent и SPSCQueue (одна очередь — один производитель).
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
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
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md. Продолжаем S13: S13d — обратная связь»
