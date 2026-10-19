# Handoff: JAMbo, Swift-версия — S13 (MIDI)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6); итоги вех — `docs/SWIFT_MILESTONE_Sx.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md` и в итогах вех.
- Порядок вех: S13 MIDI → S14 оптимизация и App Store → S15 автоматизация.
- S13 (SWIFT_AUDIT.md, раздел 6): MIDI на CoreMIDI — устройства, маппинг, LEARN, MIDI MAP, Twister, ноты по каналам, клок (SEND / RECEIVE), ARM n и ARM MST для записи стемов (перенесены из S11d). Поведение — docs/ai/settings-midi-sync.md (веб — эталон).
- Решения S12 (пользователь): движков Mutable Instruments нет (mi:0…mi:15 — пустой звук); ударные SNARE, HAT, CLAP, PERC и SUB — монофоничны; меню звука — DRUMS / SYNTH; KEY VELOCITY — по акселерометру; Swing — в меню клавиатуры; Level убран (громкость — MIX и регулятор справа); PLAY сэмплера убран; у SUB нет Key Reset; Reverb по умолчанию 30 % и 1,5 с.
- Термины (CLAUDE.md): сэмпл-лок — шаг со своим сэмплом, пресет-лок — шаг со своим пресетом синта.

## 3. Текущая задача
S13: MIDI. Сначала — сверить с вебом (midi.ts, ui/midi.ts, ui/learn.ts, ui/mapedit.ts, sync.ts) и docs/ai/settings-midi-sync.md, предложить пользователю план по этапам (устройства и ноты → LEARN и MIDI MAP → Twister и обратная связь → клок SEND / RECEIVE и офсеты → ARM), затем по этапу за раз.

## 4. Что уже решено
- S0–S12 готовы и проверены на iPad. CoreTests — 264.
- Движки синта (S12): JamboBank — JamboVoice (KICK, ANALOG, FM, WTABLE, SUB) и JamboDrumVoice (20–23); номера — JamboTables (`Jambo.mono`); таблица движков и колонки меню — SynthEngines; ручки — Params.synthGrids; перевод старых проектов — версия формата 4 (SynthMigration), пресеты — fmt 3.
- Монофоническая нота секвенсора ждёт своего кадра (SynthVoices, pKeep) — прежняя звучит до него; тест testNoGapBeforeSequencedNote.
- KEY VELOCITY: UI/TapSensor.swift (CoreMotion), Core/Model/TapVelocity.swift; клавиша ждёт толчка до 15 мс.
- Сэмплы — Samples/<ключ>.caf; библиотека — Library.json, RECORDINGS — системная папка.
- Новое поле модели проекта — в CodingKeys и init(from:) (ProjectCoding.swift); тест testCodingKeysCoverAllFields.

## 5. Что осталось решить
- PLAY сэмплера на 1.4 — новая реализация (решение пользователя: прежняя не понравилась).
- Номера готовых к записи дорожек при удалении или перестановке дорожек не пересчитываются (как в вебе).
- Место кнопки AUTO — в S15.
- Sampler.swift — больше ~600 строк, разделить при случае.
- Правки микшера и мастера во время перехода MIX в файл не попадают (открыто в S10).
- Чистка неиспользуемых сэмплов (Samples, Tables) — позже, по решению пользователя.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций; запись из колбэка — через кольцевые буферы, файл пишется вне колбэка. MIDI → аудио — через CoreEvent и SPSCQueue.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Имена новых типов проверять на совпадение с уже существующими (Core и UI — один модуль).
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
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md. Начинаем S13: MIDI»
