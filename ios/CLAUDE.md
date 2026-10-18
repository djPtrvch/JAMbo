# JAMbo для iPad — Swift-версия (Swift Playgrounds)

Нативное приложение, App Project для Swift Playgrounds: `ios/JAMbo.swiftpm`, ветка `swift`. Поведение — как в веб-версии (корневой CLAUDE.md — эталон; веб заморожен, только исправления). Решение пользователя: переносим всё, что сделано в вебе (кроме чисто браузерного). Аудит и план вех — docs/SWIFT_AUDIT.md; что сделано и как устроено — docs/SWIFT_MILESTONE_Sx.md (см. «Где искать»).

## Структура
- `JAMbo.swiftpm/Core/` — DSP и модель, только Foundation и Synchronization (Accelerate — только под `#if canImport(Accelerate)` с обычной реализацией рядом). Util/ (атомарные значения, очереди, CPU), Engine/ (AudioCore — весь звук), Model/ (Params, Project, правки, UNDO), Sequencer/, Sampler/, Synth/, Plaits/, Jambo/, FX/, Mod/, Master/, EQ/, Icons/.
- `JAMbo.swiftpm/Audio/` — AVAudioSession (48 кГц, буфер 256), один AVAudioSourceNode → `AudioCore.render`; хранилище сэмплов.
- `JAMbo.swiftpm/UI/` — SwiftUI. `JAMbo.swiftpm/Resources/` — таблицы Plaits, эталоны самотеста, лицензии.
- `CoreTests/` — сборка и тесты Core на Linux и Mac (`Sources/Core` — ссылка на `JAMbo.swiftpm/Core`).
- `tools/` — install-swift-linux.sh, swift-env.sh; генераторы эталонов (plaits, jambo, fx, master, eq, icons).

## Проверка
- Облако: `ios/tools/install-swift-linux.sh` (один раз), затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`. UI и Audio на Linux не собираются — их проверяет только сборка на iPad.
- iPad: GitHub → ветка `swift` → Download ZIP (или архив из чата) → «Файлы» → распаковать → `ios/JAMbo.swiftpm` открыть в Swift Playgrounds.
- «Пришли проект» / «пришли файл проекта» — полный zip ветки `swift` (`git archive`, как Download ZIP GitHub) в чат.
- Package.swift — в виде, который создаёт Playgrounds; правится только через Playgrounds. Значок — только `.placeholder(icon: …)`. Устройство: iPadOS 26.6.2, Playgrounds 4.7.

## Правила кода
- Swift 5 (не режим Swift 6), минимальная iPadOS 18. Только Swift и фреймворки Apple: без C/C++/Objective-C целей, сторонних пакетов, unsafeFlags, своих entitlements и ключей Info.plist. Атомарные значения — Synchronization (запасной вариант — os_unfair_lock с tryLock).
- Файл не длиннее ~600 строк; тело View короче ~40 строк.
- Компилятор Playgrounds медленный («unable to type-check in reasonable time»): выражения — по шагам с явными типами, числовые константы — готовым числом, массивы-литералы ≤ ~100 элементов (данные — из Resources).
- Имена своих типов не совпадают с типами SwiftUI и Foundation (Scene, View, Text, Color, Path…): Core и UI — один модуль.
- Колбэк (AudioCore.render и всё, что он зовёт): без выделения памяти, блокировок, ARC-объектов, созданных в колбэке, Objective-C, print и растущих Swift-коллекций; final-классы, UnsafeMutablePointer, @inline(__always) на горячих функциях; денормалы в обратных связях гасить вручную. Каждый новый вызов в колбэке проверять по этому списку.
- Playgrounds собирает отладочную версию (без оптимизации). В горячих циклах DSP: без вызовов функций из других файлов на каждом отсчёте (встраивание — только внутри файла), состояние класса — в локальных переменных на блок, циклы while, без обобщённых преобразований чисел, глобальные константы других файлов — в локальную переменную, enum с raw value не сравнивать в цикле. Проверка — сверка с эталонами.
- UI → аудио: CoreEvent через SPSCQueue и AtomicFloat; аудио → UI: атомарные значения и кольцевые буферы, UI читает по таймеру. Экземпляры движков и буферы создаются вне колбэка.
- DSP — сверка с эталонами веба (по отсчётам ≤ −60 dB или третьоктавные полосы ±0,5 dB), каждый эталон — в SELF-TEST. Эталоны Web Audio (узлы браузера) — настоящий код веба в headless Chromium через протокол отладки (образец — tools/eq/golden.mjs).
- UI: ручки, шаги, сетки, метры, спектры — Canvas; состояние — @Observable; без перерисовки всего экрана каждый кадр. Вид с индексом читает данные с проверкой границ. Общий DragGesture от 0 px на контейнере перехватывает кнопки внутри — кнопки и меню держать вне него. Пока открыто меню поверх поля с жестами, поле касаний не принимает.
- Меню: низ не ниже верха кнопок дорожек; что не помещается — прокрутка пальцем (MenuScroll) с тонкой полосой справа.
- Надписи — на английском, комментарии и документы — по-русски. Окна закрываются квадратным ✕. В переносе из Plaits — строка лицензии MIT (Emilie Gillet), тексты — Resources/licenses.
- Swift-файлы из bash через heredoc в кавычках ('EOF') — с одинарной обратной косой: `\(x)`.
- Каждая веха — docs/SWIFT_MILESTONE_Sx.md: что сделано, что проверено, что открыто, подробности устройства.

## Решения
- Частота: всё считается на 48 кГц (если устройство даёт другую, приводит системный микшер).
- Plaits: a0 = (440/8)/48000, без сдвига ноты; эталоны — wasm веба со сдвигом ноты −0,0461 полутона. SPEECH: Formant, Phoneme, LPC, без Words.
- FX — 1:1 по worklet’ам веба.
- Мастер (S5a, отличие от веба): упрощён — сатуратор DRIVE, TYPE, TONE, MIX, FOCUS; компрессор THRESHOLD, ATTACK, RELEASE, MAKEUP, RATIO, KNEE, SC HPF, MIX; клиппер INPUT, CEILING, SOFTNESS, BASS; лимитер INPUT, CEILING, LOOKAHEAD, RELEASE. Без BIAS, OUTPUT, RANGE, HOLD, LINK, MIX клиппера, UNITY, AUDIT; SCALE — всегда 48 dB. Убранные параметры — на значениях по умолчанию (звук как в вебе). PRESETS модулей мастера — с S6 (решение пользователя): у каждого модуля свой список, общий для проектов (UserDefaults); SAVE, тап — загрузить (UNDO), свайп влево — карандаш на сером (RENAME) и корзина на красном (DELETE), как в списках iPad; так же — пресеты EQ (S7). Окна (S6, отличия от веба): пауза дисплея везде FREEZE (в вебе у LIM — HOLD); ввод числом — системное окно, как у EQ; у CLIP шкала TRANSFER — та же, что у дисплея LEVEL (0…−48 dB, сетка 6 dB), как у COMP; у CLIP один дисплей — LEVEL с GR (без WAVE и кнопки VIEW); у SAT — TRANSFER и SPECTRUM (без WAVE и BIAS); поля — как в EQ, без жёлтой подсветки полей, линий и ручек; FREEZE — двойной тап по дисплею. Кнопки мастера при MST — по цепочке: COMP, CLIP сверху, SAT, LIM снизу (в вебе CLIP, LIM / SAT, COMP).
- Клипы (S1d, отличие от веба): у каждого клипа свой паттерн; копии независимы. Подробно — SWIFT_MILESTONE_S1.md.
- Секвенсор и пианоролл (перед S4, отличие от веба): точка p-lock на шаге, 16 × N шагов в ряд, копия шага, 1 OCTAVE и др. Подробно — SWIFT_MILESTONE_S1.md.
- EQ (S5b, отличия от веба): тап по имени у EQ дорожки — меню COMPARE (спектр другой дорожки после её EQ, прозрачнее, «vs имя»), у мастера — спектр выхода; строка EQ — имя под бутербродом, TYPE с края поля BPM; ввод частоты — только удержанием FREQ; двойной тап по точке — удалить, вкл./выкл. — ON/OFF в меню удержания. Подробно — SWIFT_MILESTONE_S5.md.
- Метры и скоп (S5c, отличия от веба): на измерителе справа заглушённая дорожка — серая; кнопки скопа COMP, CLIP, LIM по умолчанию выключены. Подробно — SWIFT_MILESTONE_S5.md.
- Значения по умолчанию (после проверки S5d, отличие от веба): ATTACK компрессора мастера — 30 мс (в вебе 10), Rev Size — 40 % (в вебе 50); эталоны считаются от значений веба. ● MASTER (запись мастера) — под окном при MIX, на месте стрелок папки; окно при MIX — размером с окно дорожки (при MST строки нет — окно индикации выше).
- Dynamic EQ (S7b, отличие от веба): в кольце источников (дорожки слушают друг друга) задержка — один блок (256 отсчётов; в вебе — 128). Подробно — SWIFT_MILESTONE_S7.md.
- Фон: при уходе в фон звук останавливается (если редактор capabilities даст Background Modes → Audio — вернуть BACKGROUND AUDIO).

## Вехи
S0 каркас → S1 секвенсор и экран → S2 сэмплер и редактор → S3 Plaits и свои движки, SELF-TEST → S4 FX, MOD, MORPH → S5 мастер, EQ, метры, скоп → S6 окна модулей мастера (S0–S6 готовы, проверены на iPad) → **S7 EQ Dynamic и M/S, пресеты EQ (дальше)** → S8 пианоролл → S9 проекты и настройки → S10 переходы между проектами → S11 библиотека, импорт и экспорт, стемы, REC → S12 MIDI → S13 автоматизация → S14 оптимизация и App Store. Подробно — docs/SWIFT_AUDIT.md, раздел 6 (там же — соответствие прежним номерам).

## Текущая веха (S7)
- S7a–S7d сделаны (итог — docs/SWIFT_MILESTONE_S7.md), ждут проверки на iPad. Дальше — S8 пианоролл (новое, состав уточнить).

## Где искать
| Задача касается… | Файл |
|---|---|
| каркаса, AudioHost, CPU, тест-тона | docs/SWIFT_MILESTONE_S0.md |
| секвенсора, ручек и p-lock, страниц, UNDO, пианоролла, записи, сетки паттернов, клипов | docs/SWIFT_MILESTONE_S1.md |
| сэмплера, микшера, окна сэмпла, редактора, загрузки файлов, MIX | docs/SWIFT_MILESTONE_S2.md |
| Plaits, голосов синта, своих движков, WTABLE, иконок, SELF-TEST | docs/SWIFT_MILESTONE_S3.md |
| FX, посылов, Sidechain, MOD, MORPH | docs/SWIFT_MILESTONE_S4.md |
| мастера, EQ, спектров, метров, скопа | docs/SWIFT_MILESTONE_S5.md |
| окон модулей мастера, пресетов модулей | docs/SWIFT_MILESTONE_S6.md |
| EQ Dynamic и M/S, пресетов EQ | docs/SWIFT_MILESTONE_S7.md |
