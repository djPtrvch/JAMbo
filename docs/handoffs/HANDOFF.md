# Handoff: JAMbo, Swift-версия — S7 (EQ Dynamic и M/S, пресеты EQ)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6, там же соответствие прежним номерам).

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба (по отсчётам ≤ −60 dB или полосы ±0,5 dB), каждый эталон — в SELF-TEST. Эталоны Web Audio — настоящий код веба в headless Chromium (`ios/tools/eq/golden.mjs` — образец, он же для EQ).
- Порядок вех (решение пользователя): S7 EQ → S8 пианоролл (новое, состав уточнить) → S9 проекты и настройки → S10 переходы между проектами → S11 библиотека и файлы → S12 MIDI → S13 автоматизация → S14 оптимизация и релиз.
- Пресеты EQ — как пресеты модулей мастера (S6): список, общий для проектов (UserDefaults), SAVE, тап — загрузить (UNDO), свайп влево — карандаш на сером (RENAME) и корзина на красном (DELETE).

## 3. Текущая задача
S7: EQ Dynamic и Mid/Side (по вебу: public/eqdyn-worklet.js, audio/eq.ts, ui/eq.ts; поведение — docs/ai/fx-eq.md), пресеты EQ. В строке EQ кнопки M/S, DYN и PRESETS сейчас серые (UI/EqView). Сначала — разбивка S7 на части и план (согласовать с пользователем).

## 4. Что уже решено
- S0–S6 готовы и проверены на iPad (итоги — docs/SWIFT_MILESTONE_S5.md, S6.md). CoreTests — 159; SELF-TEST на iPad — 184/184.
- Для S7 уже есть: EQ в Core (Core/EQ: EqModel, EqUnit, биквады, 8 полос, эталоны eq_*), экран EQ (UI/EqView, EqPlot, EqSpectrum, AppModelEq), спектры и COMPARE; список пресетов со свайпом (UI/MasterMenus, PresetRow) и хранилище пресетов (Core/Model/MasterPresets — образец).

## 5. Что осталось решить
- Состав Dynamic EQ и M/S в Swift (что 1:1 из веба), где в строке EQ поля DYN и M/S, эталоны для новых узлов.
- Пресеты EQ: что входит (полосы, BYPASS?), общий список или по каналам.
- Отложено: проекты — S9; импорт и экспорт — S11.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Playgrounds: выражения — по шагам с явными типами; UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат. PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md, docs/SWIFT_MILESTONE_S5.md (EQ) и docs/ai/fx-eq.md (Dynamic EQ, M/S, пресеты). Предложи разбивку S7 и план.»
