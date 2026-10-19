# S13 — MIDI

## S13a — CoreMIDI, устройства, ноты
MidiHost (Audio): клиент CoreMIDI, вход со всех источников, списки входов и выходов (обновляются по msgSetupChanged), сообщения — на главный поток. MidiMessage — разбор UMP MIDI 1.0. Нота с MIDI держится до Note Off (в вебе — один шаг). NOTES: канал нот, SELECTED TRACK или канал N → дорожка N.

## S13b — маппинг и LEARN
MidiMapping (цели, типы, энкодеры, условия GLOBAL / PAGE / CLIPS, MidiPlace), MidiMapper. У 16 ручек два назначения — поворот и нажатие (TURN / PRESS на полосе LEARN); KNOB PRESS = TOUCH (по умолчанию ON). Цели ROLL (вместо AUTO), REDO, LEVEL, XFADER. Рамка цели в LEARN — жёлтая. Темп с MIDI — целыми BPM.

## S13c — окно MIDI MAP и пресеты
MidiMapWindow, MidiMapPages; пресеты маппингов — UserDefaults "midiPresets", имена до 40 знаков; встроенного пресета Twister нет (решение пользователя).

## S13d — обратная связь
MidiFeedback: каждый кадр (60 Гц; в вебе 30 мс), только изменения; фейдеру ABSOLUTE, который двигают, — без эха 0,3 с; PRESS обратную связь не шлёт. Тип Button latch (127 — вкл., 0 — выкл.). DONE на полосе LEARN закрывает и MIDI MAP.

## S13e — SYNC
Меню SYNC (GENERAL, MIDI CLOCK, ABLETON LINK — только хранится), SyncSettings, полоса фазы по SYNC QUANTUM. Клок SEND — ClockPlan (тики, Start, Stop по сетке шагов), метки времени CoreMIDI, MIDI OFFSET. Клок RECEIVE — ClockFollower (темп по 48 тикам, Start / Continue / Stop, пропадание 0,5 с), старт в кадре тика, поправка фазы шага на 25 %.

## S13f — Bluetooth MIDI
MIDI → DEVICES → BLUETOOTH MIDI: CONNECT (CABTMIDICentralViewController) и ADVERTISE (CABTMIDILocalPeripheralViewController) — системные окна листом с ✕ (BluetoothMidi.swift). Без capability Bluetooth (ключ NSBluetoothAlwaysUsageDescription) кнопки неактивны. Подключённое устройство появляется в списках само (msgSetupChanged).

## Проверено
S13a–d и S13f — на iPad (обратная связь — с TouchOSC по Bluetooth). CoreTests — 291 (MidiTests, MidiMapTests, MidiPresetTests, MidiFeedbackTests и тесты клока).

## Открыто
- S13e — проверить на iPad (клок с внешним устройством); перенесено в S14.
- Задержка нот с MIDI (через главный поток) — проверить после правки LEARN; если останется — путь MIDI → аудио мимо главного потока.
- Ableton Link — этап 9 (спайк B0).
