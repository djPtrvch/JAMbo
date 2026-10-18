# Handoff: JAMbo, Swift-версия — S9 (проекты и настройки)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6, там же соответствие прежним номерам).

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба (по отсчётам ≤ −60 dB или полосы ±0,5 dB), каждый эталон — в SELF-TEST. Эталоны Web Audio — настоящий код веба в headless Chromium (`ios/tools/eq/golden.mjs`).
- Порядок вех (решение пользователя): S9 проекты и настройки → S10 переходы между проектами → S11 библиотека и файлы → S12 MIDI → S13 автоматизация → S14 оптимизация и релиз.
- Пианоролл (S8) — пункт «Пианоролл» в «Решениях» `ios/CLAUDE.md`; нижний пианоролл теперь называется клавиатурой. У ноты своя длина и velocity (Step.lens, Step.vels); velocity связана с p-lock Level шага — формат проекта S9 должен их сохранять.

## 3. Текущая задача
S9: проекты, автосохранение, настройки, LICENSES (docs/SWIFT_AUDIT.md, раздел 6). Сначала свериться с вебом (docs/ai/patterns-projects.md, docs/ai/settings-midi-sync.md), уточнить у пользователя состав и отличия, затем разбивка и план.

## 4. Что уже решено
- S0–S8 готовы и проверены на iPad. S8 — docs/SWIFT_MILESTONE_S8.md: модель нот (StepNotes.swift), звук по нотам (SeqData.split, noteLen, noteVel), Roll.swift и RollEdits.swift в Core; UI — RollWindow, RollViews, RollGestures, AppModelRoll; клавиатура — KeyboardPanel (Keyboard.swift).
- CoreTests — 177.
- Настройки, общие для проектов, уже в UserDefaults (AppSettings: клавиатура, запись, SIDECHAIN, пианоролл и др.); пресеты модулей мастера и EQ — тоже.

## 5. Что осталось решить
- Состав S9 и отличия от веба — уточнить у пользователя.
- Место кнопки AUTO — в S13.
- Отложено: импорт и экспорт — S11.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Playgrounds: выражения — по шагам с явными типами; UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат, не в рабочую папку репозитория. PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md. Состав S9: …»
