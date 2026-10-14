# JAMbo для iPad — Swift-версия (Swift Playgrounds)

Нативное приложение, App Project для Swift Playgrounds: `ios/JAMbo.swiftpm`, ветка `swift`. Поведение — как в веб-версии (корневой CLAUDE.md — эталон; веб заморожен, только исправления). Аудит и план вех — docs/SWIFT_AUDIT.md, итоги вех — docs/SWIFT_MILESTONE_Sx.md. Решение пользователя: переносим всё, что сделано в вебе (кроме чисто браузерного).

## Структура
- `JAMbo.swiftpm/Core/` — DSP и модель, только Foundation (без Accelerate, SwiftUI, AVFoundation; Accelerate — только под `#if canImport(Accelerate)` с обычной реализацией рядом). Util/ — SpinLock, AtomicFloat, AtomicCounter, SPSCQueue, CPUMeter; Engine/ — AudioCore (весь звук), события CoreEvent.
- `JAMbo.swiftpm/Audio/` — AVAudioSession (48 кГц, буфер 256) и один AVAudioSourceNode, колбэк зовёт `AudioCore.render`.
- `JAMbo.swiftpm/UI/` — SwiftUI.
- `JAMbo.swiftpm/Resources/` — таблицы Plaits (.bin), эталоны самотеста, лицензии.
- `CoreTests/` — пакет для сборки и тестов Core на Linux и Mac (`Sources/Core` — символическая ссылка на `JAMbo.swiftpm/Core`).
- `tools/` — install-swift-linux.sh (Swift 6.0.3 из пакетов Ubuntu в /opt/swiftdeb: swift.org из облака недоступен), swift-env.sh.

## Проверка в облаке
`ios/tools/install-swift-linux.sh` (один раз на контейнер), затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`. UI и Audio на Linux не собираются (нет SwiftUI и AVFoundation) — их проверяет сборка на iPad.

## Как открыть на iPad
GitHub → ветка `swift` → Code → Download ZIP → «Файлы» → распаковать → папка `ios/JAMbo.swiftpm` открывается в Swift Playgrounds (тап по ней). Package.swift — в виде, который создаёт Playgrounds; после открытия правится только через Playgrounds (ТЗ 0.3).

## Package.swift
Значок — только существующий `.placeholder(icon: …)` (с `.music` Playgrounds не читает манифест и показывает «Loading… Crashed» без кода). Устройство: iPadOS 26.6.2, Playgrounds 4.7 — S0 собирается.

## Правила кода
- Swift 5 (не режим Swift 6), минимальная iPadOS 18. Модуль Synchronization пока не используется (вернуть и проверить в S1: прежние падения были из-за значка в Package.swift); обмен UI ↔ аудио — на os_unfair_lock, аудиопоток только tryLock (занято — пропуск до следующего блока; ТЗ 0.2). Только Swift и фреймворки Apple: без C, C++, Objective-C целей, сторонних пакетов, unsafeFlags, своих entitlements и ключей Info.plist (только редактор capabilities).
- Файл не длиннее ~600 строк; большие функции разбивать. Тело SwiftUI-View короче ~40 строк, остальное — в подвиды; сложные выражения — на несколько строк с явными типами (иначе «expression too complex»).
- Массивы-литералы не больше ~100 элементов; данные — из Resources.
- Колбэк (AudioCore.render и всё, что он зовёт): без выделения памяти, блокировок, ARC-объектов, созданных в колбэке, вызовов Objective-C, print и Swift-коллекций, которые растут; только final-классы, UnsafeMutablePointer<Float>, @inline(__always) на горячих функциях; денормалы в обратных связях гасить вручную (+1e-18 или обнуление). Каждый новый вызов в колбэке проверять по этому списку.
- UI → аудио: CoreEvent через SPSCQueue (простые значения, без ссылок) и AtomicFloat; аудио → UI: атомарные значения и кольцевые буферы, UI читает по таймеру (TimelineView). Экземпляры движков и буферы создаются вне колбэка и передаются в него на границе блока.
- Ручки, шаги, сетки, метры, скоп — Canvas; состояние — @Observable; без перерисовки всего экрана каждый кадр.
- Перенос из Plaits: в каждом файле «Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet»; тексты лицензий — Resources/licenses.
- Все надписи — на английском; комментарии и документы — по-русски. Окна закрываются квадратным ✕.
- Каждая веха — файл docs/SWIFT_MILESTONE_Sx.md: что сделано, что проверено, что открыто.

## Решения
- Частота: всё считается на 48 кГц (формат узла 48000; если устройство даёт другую, приводит системный микшер).
- Plaits: a0 = (440/8)/48000, без сдвига ноты (A4 = 440 Гц, как в вебе после поправки на 47872,34 Гц). Эталоны tools/golden — wasm со сдвигом ноты −0,0461 полутона (так играет веб на 48 кГц).
- SPEECH: Formant, Phoneme, LPC (harmonics 0, 1/6, 1/3), без Words.
- FX и мастер — 1:1 по нынешним worklet’ам веба (Reverb FDN, Delay с FILTER/SPREAD, Drive 6 типов, sidechain с CURVE).
- Фон: при уходе в фон звук останавливается (фоновый звук в Playgrounds не ожидается; если редактор capabilities даст Background Modes → Audio — вернуть BACKGROUND AUDIO).

## Вехи
S0 каркас (готов) → S1 секвенсор и экран → S2 сэмплер и редактор → S3a/S3b Plaits и свои движки, SELF-TEST → S4 FX, MOD, MORPH → S5 мастер, EQ, метры, скоп → S6 проекты и настройки → S8 автоматизация → S9 окна мастера, EQ Dynamic и M/S, пресеты EQ → S10 библиотека, импорт и экспорт, стемы, REC → S11 MIDI (CoreMIDI) → S12 переходы между проектами → S7 оптимизация и App Store. Подробно — docs/SWIFT_AUDIT.md, раздел 6.

## S0 (каркас)
- AudioHost: категория .playback, 48 кГц, буфер 256 кадров; перезапуск после прерывания и смены конфигурации; при уходе в фон — пауза и деактивация сессии.
- AudioCore: события из очереди в начале блока, тест-тон (синус 440 Гц, −12 dBFS, вкл./выкл. огибающей 5 мс — без щелчка), счётчик кадров sampleTime (основа транспорта).
- CPU: время колбэка (mach_absolute_time) / длительность блока, среднее за 0,5 с; индикатор справа вверху (≥ 70 % — красный); в DIAGNOSTICS — среднее и пик блока.
- Экран: бутерброд (APPEARANCE: SYSTEM, LIGHT, DARK — хранится в UserDefaults; DIAGNOSTICS), кнопка TONE (горит жёлтым), CPU. DIAGNOSTICS: «Now:» — фактические частота, буфер, задержка выхода, состояние («(48 kHz requested)», если система дала другую), секунды звука ядра, CPU; SELF-TEST — пусто до S3a.
- Тесты CoreTests (7): очередь — порядок, переполнение, кольцо, два потока (200 000 элементов); AtomicFloat; тон — тишина до включения, −12,00 dB, 440 Гц, скачок между отсчётами на включении и выключении не больше, чем у синуса, через 200 мс после выключения — 0; CPUMeter.
