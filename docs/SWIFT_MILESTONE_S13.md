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

Правки после проверки с Digitakt по USB (S13e):
- Клок RECEIVE: пропажа клока дольше 0,5 с (отключили устройство) — шаг 0 транспорта заново привязывается к ближайшему тику (флаг anchored в ClockFollower; так же после PLAY своей кнопкой без клока и после перезапуска звука). Пропуск тиков короче 0,5 с (больше 2,5 интервала и не меньше 60 мс) — окно темпа заново, пропущенные тики досчитываются, привязка шагов прежняя. Темп клока — только после 4 тиков окна.
- MidiHost при смене настройки MIDI подключает только новые источники и отключает пропавшие; подключённые не трогает (раньше на каждое уведомление переподключались все — терялись тики, темп проседал).
- AudioHost: пачка уведомлений о смене конфигурации движка — один перезапуск через 0,3 с после последнего, только движок (сессия не настраивается заново). Задержка выхода для клока, MIDI OUT и записи нот запоминается при запуске звука и смене маршрута (с USB-аудио система отдаёт то 1, то 11 мс).
- Строка «Now:» (AUDIO ENGINE, DIAGNOSTICS): выход и вход маршрута, перезапуски движка, смены маршрута, скорость колбэка (audio speed, %).
- Digitakt в режиме USB AUDIO/MIDI: iPad переключает выход на него, но звук не идёт (и у других приложений), колбэк почти не зовут, через пару секунд выход возвращается на динамик — секвенция тормозит. Из приложения не исправить; для клока и нот — режим USB MIDI.

## S13f — Bluetooth MIDI
MIDI → DEVICES → BLUETOOTH MIDI: CONNECT (CABTMIDICentralViewController) и ADVERTISE (CABTMIDILocalPeripheralViewController) — системные окна листом с ✕ (BluetoothMidi.swift). Без capability Bluetooth (ключ NSBluetoothAlwaysUsageDescription) кнопки неактивны. Подключённое устройство появляется в списках само (msgSetupChanged).

## Проверено
S13a–d и S13f — на iPad (обратная связь — с TouchOSC по Bluetooth). S13e — на iPad: RECEIVE и SYNC START/STOP, SEND — с Digitakt по USB (режим USB MIDI). CoreTests — 291 (MidiTests, MidiMapTests, MidiPresetTests, MidiFeedbackTests и тесты клока).

## Открыто
- Описание Swift-версии клока в docs/ai/settings-midi-sync.md (было в S14d).
- Задержка нот с MIDI (через главный поток) — проверить после правки LEARN; если останется — путь MIDI → аудио мимо главного потока.
- Ableton Link — этап 9 (спайк B0).
