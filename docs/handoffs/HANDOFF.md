# Handoff: JAMbo, Swift-версия — S10 (переходы между проектами)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план и вехи — `docs/SWIFT_AUDIT.md` (раздел 6).

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба, каждый эталон — в SELF-TEST.
- Порядок вех: S10 переходы между проектами → S11 библиотека и файлы → S12 MIDI → S13 автоматизация → S14 оптимизация и релиз.
- Решения S9 для S10 (`ios/CLAUDE.md`, пункт SETTINGS): SETTINGS → MIX — CHANGE KEY (ON — гамма и нота нового проекта при переходе, OFF — остаются; по умолчанию ON) и CROSSFADER (ON — кроссфейдер управляет только темпом, в вебе — темпом и общими настройками; OFF — кроссфейдера нет, темп старого паттерна; по умолчанию ON). Сейчас они только хранятся (AppSettings.mixKey, mixCrossfader).
- Окно открытия проекта (LOAD / MIX) уже есть, MIX серая (ProjectsMenu.swift, OpenProjectPanel). LOAD и NEW останавливают игру (AppModel.loadProject) — смена проекта во время игры — через MIX.

## 3. Текущая задача
S10: переход MIX между проектами (строка PREV, кроссфейдер). Сначала свериться с вебом (docs/ai/patterns-projects.md — «Переход между проектами», «Кроссфейдер»; state.ts — switchWithTransition, updateTransition, docForSave), уточнить у пользователя состав и отличия, затем разбивка и план.

## 4. Что уже решено
- S0–S9 готовы и проверены на iPad. S9 — docs/SWIFT_MILESTONE_S9.md: формат проекта (ProjectCoding, ProjectRepair, ProjectStore), автосохранение (ProjectSession), PROJECTS, бутерброд и SETTINGS, MUTE TAILS, LICENSES, LEVEL (Track.trim), MORPH (ALL TRACKS, RETURN).
- CoreTests — 196.
- Новое поле модели проекта — добавлять в CodingKeys и init(from:) (ProjectCoding.swift); тест testCodingKeysCoverAllFields это проверяет.

## 5. Что осталось решить
- Состав S10 и отличия от веба — уточнить у пользователя (сохранение во время перехода, как в docForSave веба; что делать с CHANGE KEY OFF; кроссфейдер только для темпа).
- Место кнопки AUTO — в S13.
- Sampler.swift — 635 строк (больше ~600), разделить при случае.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Playgrounds: выражения — по шагам с явными типами; UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕; меню закрываются тапом мимо.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат, не в рабочую папку репозитория. PR — только по просьбе.
- Скриншоты пользователя могут быть от старой сборки — сверять с последним коммитом.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md. Состав S10: …»
