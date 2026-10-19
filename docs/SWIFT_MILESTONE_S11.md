# S11 — библиотека, импорт и экспорт, стемы, REC

## S11a — EXPORT / IMPORT проекта (.jambo)
- Файл — контейнер веба (ProjectPack): 'JMB1', длина заголовка, заголовок JSON, байты сэмплов. Веб — format 'jambo', Swift — 'jambo-swift' (doc — Project, сэмплы — свои .caf); файл Swift-версии в вебе не открывается (решение пользователя).
- IMPORT проекта веба — конвертер WebProject: у каждого клипа своя копия страниц дорожки и свои playFrom, playTo, гамма, нота, FX; пустой активный клип — пустая ячейка; mixer → Track.vol, eqs → Track.eq, folders → Track.folder; MIX и MST — один клип; ключи сэмплов без 's:' (тот же SHA-256).
- Не переносятся (решения пользователя): автоматизация, миграция SPEECH. Не переносятся до библиотеки (S11b): пресеты синта в папках дорожек, свои таблицы WTABLE (BASIC). Убранные параметры мастера отбрасываются.
- IMPORT: сэмплы — в Samples/<ключ>.caf (уже лежащий не трогается), проект — новой записью («имя (imported)», если имя занято), затем окно LOAD / MIX. EXPORT: savedProject (без PREV) и его .caf — во временный файл, системное окно переносит его в «Файлы».
- Меню PROJECTS: второй ряд — EXPORT, IMPORT.
- Эталон: ios/tools/webproject/golden.mjs (настоящие normalizeDoc и packProject веба) → web_project.jambo; тесты — WebProjectTests, ProjectPackTests.
- Проверено: CoreTests 218 (облако). iPad — не проверено.
