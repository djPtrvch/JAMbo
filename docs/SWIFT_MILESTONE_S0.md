# Веха S0 — каркас

## Сделано
- `ios/JAMbo.swiftpm` — App Project для Swift Playgrounds: iPadOS 18, iPad, альбомная ориентация, Swift 5; цели AppModule (Core/, Audio/, UI/, Resources/).
- Core (Foundation): SpinLock, AtomicFloat, SPSCQueue (без выделений после создания, аудиопоток не ждёт), CPUMeter, CoreEvent, TestTone, AudioCore.render — единственная точка расчёта звука.
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
- Второй запуск — то же самое, до появления экрана. Вероятная причина — модуль Synchronization (Atomic): заменён запасным вариантом ТЗ 0.2 — SpinLock (os_unfair_lock на iPad, NSLock на Linux), аудиопоток берёт замок только tryLock; тесты 7/7.
- Третий запуск — то же; в редакторе был виден только Package.swift (46 строк): Playgrounds не смог прочитать манифест и кода не видел. Вероятно — значок `.placeholder(icon: .music)` (такого значка нет); заменён на `.sparkle`. Запасной путь — новое приложение в Playgrounds и перенос папок Core, Audio, UI, Resources (его MyApp.swift и ContentView.swift удалить).

## Итог на iPad (iPadOS 26.6.2, Playgrounds 4.7) — S0 пройдена
- Приложение собирается и запускается; TONE — тон 440 Гц звучит.
- DIAGNOSTICS: «Now: 48.0 kHz · buffer 256 · output latency 11.0 ms · running», CPU 0–1 %.
- Причина прежних падений — неверный значок в Package.swift (`.music`): Playgrounds не читал манифест.
- Строка состояния iPad видна (statusBarHidden в Playgrounds не действует) — не мешает.

## Открыто
- Synchronization убран вместе с неверным значком; виноват был значок. Вернуть Atomic (ТЗ 3.3) и проверить на iPad в начале S1 — если запустится, замки (SpinLock) уйти в запас.
- Есть ли в редакторе capabilities Playgrounds «Background Modes → Audio» — посмотреть; если есть, вернуть BACKGROUND AUDIO.

## Подробности (из ios/CLAUDE.md)

### S0 (каркас)
- AudioHost: категория .playback, 48 кГц, буфер 256 кадров; перезапуск после прерывания и смены конфигурации; при уходе в фон — пауза и деактивация сессии.
- AudioCore: события из очереди в начале блока, тест-тон (синус 440 Гц, −12 dBFS, вкл./выкл. огибающей 5 мс — без щелчка), счётчик кадров sampleTime (основа транспорта).
- CPU: время колбэка (mach_absolute_time) / длительность блока, среднее за 0,5 с; индикатор справа вверху (≥ 70 % — красный); в DIAGNOSTICS — среднее и пик блока.
- Экран: бутерброд (APPEARANCE: SYSTEM, LIGHT, DARK — хранится в UserDefaults; DIAGNOSTICS), кнопка TONE (горит жёлтым), CPU. DIAGNOSTICS: «Now:» — фактические частота, буфер, задержка выхода, состояние («(48 kHz requested)», если система дала другую), секунды звука ядра, CPU; SELF-TEST — с S3a (см. S3a).
- Тесты CoreTests (7): очередь — порядок, переполнение, кольцо, два потока (200 000 элементов); AtomicFloat; тон — тишина до включения, −12,00 dB, 440 Гц, скачок между отсчётами на включении и выключении не больше, чем у синуса, через 200 мс после выключения — 0; CPUMeter.
