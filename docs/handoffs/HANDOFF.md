# Handoff: JAMbo, Swift-версия — S13 (MIDI)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6); итоги вех — `docs/SWIFT_MILESTONE_Sx.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md` и в итогах вех.
- Порядок вех: S13 MIDI → S14 оптимизация и App Store → S15 автоматизация.
- S13 (SWIFT_AUDIT.md, раздел 6): MIDI на CoreMIDI — маппинг, LEARN, MIDI MAP, Twister, клок. Поведение — docs/ai/settings-midi-sync.md (эталон — веб: midi.ts, ui/midi.ts, ui/learn.ts, ui/mapedit.ts, sync.ts, ui/sync.ts). Ableton Link — отдельно (этап 9 корневого CLAUDE.md, спайк B0).
- S12 (готова): движков Mutable Instruments нет; свои — KICK, SNARE, HAT, CLAP, PERC, ANALOG, SUB, FM, WTABLE; Level убран, Velocity на 4.4; KEY VELOCITY — по толчку iPad. Подробно — SWIFT_MILESTONE_S12.md.
- Термины (CLAUDE.md): сэмпл-лок — шаг со своим сэмплом, пресет-лок — шаг со своим пресетом синта.

## 3. Текущая задача
S13: MIDI. Сначала — сверка веба с docs/ai/settings-midi-sync.md и план S13 (этапы, что переносим 1:1, что отличается на iPad: CoreMIDI вместо Web MIDI, сеть/Bluetooth MIDI, хранение маппинга), согласовать с пользователем; затем этапы небольшими коммитами.

## 4. Что уже решено
- S0–S12 готовы и проверены на iPad. CoreTests — 264.
- Velocity от MIDI-нот должен ложиться туда же, куда KEY VELOCITY (S12: TapVelocity) и velocity нот пианоролла (S8).
- Новое поле модели проекта — в CodingKeys и init(from:) (ProjectCoding.swift); тест testCodingKeysCoverAllFields. Настройки, общие для проектов, — UserDefaults (как пресеты модулей мастера).

## 5. Что осталось решить
- План и отличия S13 от веба.
- PLAY сэмплера на 1.4 — вернуться с новой реализацией (S12).
- Номера готовых к записи дорожек при удалении или перестановке дорожек не пересчитываются (как в вебе).
- Место кнопки AUTO — в S15.
- Sampler.swift — больше ~600 строк, разделить при случае.
- Правки микшера и мастера во время перехода MIX в файл не попадают (открыто в S10).
- Чистка неиспользуемых сэмплов (Samples, Tables) — позже, по решению пользователя.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций; MIDI → аудио — через SPSCQueue (CoreEvent), не из потока CoreMIDI напрямую в колбэк; клок — по меткам времени, а не по приходу в UI.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Имена новых типов проверять на совпадение с уже существующими (Core и UI — один модуль; в S11e RecButton совпал с кнопкой верхней панели).
- Playgrounds: выражения — по шагам с явными типами; UI на Linux не собирается — проверка только на iPad.
- Package.swift — в виде Playgrounds; capabilities — только те, что пользователь добавил в Playgrounds, и перед appCategory.
- Жесты в прокручиваемых списках: удержание — simultaneousGesture(LongPressGesture), не onLongPressGesture.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕; меню закрываются тапом мимо.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат, не в рабочую папку репозитория. PR — только по просьбе.
- Скриншоты пользователя могут быть от старой сборки — сверять с последним коммитом.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md. Начинаем S13: …»
