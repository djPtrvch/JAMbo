# S11 — библиотека, импорт и экспорт, стемы, REC

## S11a — EXPORT / IMPORT проекта (.jambo)
- Файл — контейнер веба (ProjectPack): 'JMB1', длина заголовка, заголовок JSON, байты сэмплов. Веб — format 'jambo', Swift — 'jambo-swift' (doc — Project, сэмплы — свои .caf); файл Swift-версии в вебе не открывается (решение пользователя).
- IMPORT проекта веба — конвертер WebProject: у каждого клипа своя копия страниц дорожки и свои playFrom, playTo, гамма, нота, FX; пустой активный клип — пустая ячейка; mixer → Track.vol, eqs → Track.eq, folders → Track.folder; MIX и MST — один клип; ключи сэмплов без 's:' (тот же SHA-256).
- Не переносятся (решения пользователя): автоматизация, миграция SPEECH. Не переносятся до библиотеки (S11b): пресеты синта в папках дорожек, свои таблицы WTABLE (BASIC). Убранные параметры мастера отбрасываются.
- IMPORT: сэмплы — в Samples/<ключ>.caf (уже лежащий не трогается), проект — новой записью («имя (imported)», если имя занято), затем окно LOAD / MIX. EXPORT: savedProject (без PREV) и его .caf — во временный файл, системное окно переносит его в «Файлы».
- Меню PROJECTS: второй ряд — EXPORT, IMPORT.
- Эталон: ios/tools/webproject/golden.mjs (настоящие normalizeDoc и packProject веба) → web_project.jambo; тесты — WebProjectTests, ProjectPackTests.
- Проверено: CoreTests 218 (облако); на iPad — EXPORT и IMPORT своего файла, IMPORT проекта веба, LOAD и MIX, отказ на чужом файле.

## S11b — библиотека
- Пресет синта (SynthPreset: движок, ручки harm, timbre, morph, level, attack, decay, filter, reso; у WTABLE — таблица); папка дорожки — сэмплы и пресеты (FolderItem; в файле — как в вебе { sample } / { preset }, прежние строки читаются). Стрелки и звук шага — с ручками пресета (p-lock шага, soundLocks).
- Библиотека (Library) — дерево в Application Support/Library.json, сэмплы — в Samples, свои таблицы WTABLE — WAV в Application Support/Tables (без пересчёта частоты). RECORDINGS — системная. Удаление сэмплы с диска не удаляет (чистка — позже, решение пользователя).
- Браузер на месте центра (LibraryBrowser): ‹, путь, NEW FOLDER, IMPORT, ✕; тап — звук дорожки (в папке только он), удержание — выбор нескольких (LOAD, CANCEL), для зажатых шагов — их звук; NAME и SAVE HERE (OVERWRITE / SAVE AS… / CANCEL). Открывается из меню звука (LOAD, SAVE пресета, TABLE) и редактора (LOAD, SAVE сэмпла).
- Отличия от веба (решения пользователя): свайп — карандаш и корзина, без EXPORT; библиотека — файл в папке приложения (папки в «Файлах» и iCloud требуют ключей Info.plist и entitlements), обмен — EXPORT / IMPORT (S11c). TABLE в меню звука — браузер LOAD TABLE (прежний список встроенных таблиц убран). LOAD выбора закрывает браузер (в вебе остаётся открытым).
- Сэмпл-локи и пресет-локи (термины — CLAUDE.md): SETTINGS → SAMPLER → CLEAR SAMPLE LOCKS (по умолчанию ON) — загрузка звуков из библиотеки на дорожку (тап и LOAD выбора) снимает её сэмпл-локи во всех клипах, шаги играют звук дорожки своей нотой; пресет-локи остаются. OFF — сэмпл-локи звучат дальше, даже если их сэмплов уже нет в папке (сэмплы шагов — в снимке звука).
- ▶: сэмпл — в снимке звука вне дорожек (extra), звучит целиком сразу на выход; пресет — нота C3 выбранной дорожкой с p-lock ручек пресета (CoreEvent.presetNote), ~0,5 с. Удержание строки — одновременным жестом (onLongPressGesture в ScrollView задерживал прокрутку).
- Свои таблицы WTABLE: ключ «wt:<ключ WAV>:<кадр>» (в вебе — с 's:'); WAV 16/24/32 бит и float, стерео — левый канал, до 256 кадров и 4 МБ; размер кадра — метка Serum или вопрос (AUTO, 256…2048); переносятся в .jambo и из веба.
- Тесты: LibraryTests, LibraryPreviewTests, UserWavetableTests, StepSoundSnapshotTests, SampleLockTests, WebProjectTests. CoreTests 231 (облако); на iPad — проверено.
