# Веха S0 — каркас

## Сделано
- `ios/JAMbo.swiftpm` — App Project для Swift Playgrounds: iPadOS 18, iPad, альбомная ориентация, Swift 5; цели AppModule (Core/, Audio/, UI/, Resources/).
- Core (Foundation + Synchronization): AtomicFloat, SPSCQueue (без блокировок и выделений после создания), CPUMeter, CoreEvent, TestTone, AudioCore.render — единственная точка расчёта звука.
- Audio: AudioHost — AVAudioSession (.playback, 48 кГц, буфер 256), AVAudioEngine с одним AVAudioSourceNode 48 кГц стерео, замер времени колбэка, перезапуск после прерывания и смены конфигурации, пауза в фоне.
- UI: верхняя панель (бутерброд, TONE, CPU), меню (APPEARANCE SYSTEM / LIGHT / DARK, DIAGNOSTICS), окно DIAGNOSTICS со строкой «Now:» и ✕; цвета — токены веба (тёмная и светлая темы).
- `ios/CoreTests` — Linux-пакет (Sources/Core → JAMbo.swiftpm/Core), 7 тестов XCTest.
- `ios/tools/install-swift-linux.sh`, `swift-env.sh` — Swift 6.0.3 в облаке (из пакетов Ubuntu; swift.org и swiftly заблокированы сетью облака).
- ios/CLAUDE.md, раздел «Swift-версия» в корневом CLAUDE.md, решения аудита (docs/SWIFT_AUDIT.md: переносим всё из веба, вехи S8–S12).

## Проверено
- Linux (Swift 6.0.3, режим Swift 5): `swift test` — 7 из 7, без предупреждений: очередь (порядок, переполнение, кольцо, два потока — 200 000 элементов), AtomicFloat, тест-тон (−12,00 dB, 440 Гц, без скачков на включении и выключении, тишина через 200 мс), CPUMeter.
- UI и Audio в облаке не собираются (нет SwiftUI и AVFoundation) — **проверка на iPad: открыть проект, собрать, нажать TONE — звучит 440 Гц; DIAGNOSTICS — строка «Now:» (48.0 kHz, buffer 256), CPU.**

## Первый запуск на iPad (iPadOS 26.6.2, Playgrounds 4.7)
- Собралось, но при запуске — «Loading… Crashed / Loading failed due to an error», без подробностей. Звук теперь запускается первым нажатием TONE (а не при старте), в консоль (Show Console) пишутся отметки запуска «JAMbo: …» — по ним видно, где остановилось.

## Открыто
- Сборка на iPad не проверена. Если Playgrounds не примет Package.swift (версия swift-tools, `.iOS("18.0")`, `swiftLanguageVersions`), создать в Playgrounds новое приложение «JAMbo» и перенести в него папки Core, Audio, UI, Resources — Package.swift останется тем, что создал Playgrounds.
- Есть ли в редакторе capabilities Playgrounds «Background Modes → Audio» — посмотреть; если есть, вернуть BACKGROUND AUDIO.
- Нужна ли iPadOS 18 на устройстве — да (Synchronization); если Playgrounds не даст 18 — запасной вариант os_unfair_lock с tryLock (ТЗ 0.2).
