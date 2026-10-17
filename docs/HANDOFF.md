# Handoff: JAMbo, перенос Plaits на Swift (S3a)

## 1. Контекст проекта
JAMbo — грувбокс для iPad. Веб-версия (TypeScript, `src/`, `public/`) — эталон поведения, она заморожена. Сейчас идёт нативный перенос в `ios/JAMbo.swiftpm`, ветка `swift`. Сначала нужно прочитать `CLAUDE.md`, `ios/CLAUDE.md` и `docs/ai/synth-engines.md`.

## 2. Принятые решения
- Первая попытка S3a откачена до конца S2. Движки переносятся с нуля по оригинальным исходникам: `wasm/plaits/.src` (eurorack `08460a6`, stmlib `e3bd7c9`).
- План: таблицы и эталоны → 8 движков (VA, WAVESHAPE, FM, GRAIN, ADDITIVE, WAVETABLE, CHORDS, SPEECH) с тестами → голоса синта в звуке → меню MI SYNTH и окно синта с иконкой → SELF-TEST.
- Критерий совпадения с эталоном: по отсчётам ≤ −60 dB ИЛИ третьоктавные полосы 20 Hz–20 kHz в пределах ±0,5 dB.

## 3. Текущая задача
Задача #37: перенос stmlib и 8 движков с тестами по эталонам в `ios/CoreTests`.

## 4. Что уже сделано
- Коммит `c071705`: экспорт таблиц и эталоны (`ios/tools/plaits/`, `Resources/plaits`, `Resources/golden`, 48 случаев).
- Следующий коммит: `Core/Plaits/stmlib/` (StmlibDSP, StmlibFilter) и `Core/Plaits/dsp/` (PlaitsResources, PlaitsEngine). Код собирается, тестов на него ещё нет.

## 5. Что осталось решить
- a0 решён (вариант A): (440/8)/48000 без сдвига ноты, как в `ios/CLAUDE.md`; kCorrectedSampleRate оставлен для LPC в SPEECH.
- Сделано (задача #37 закрыта): 8 движков (VA, WAVESHAPE, FM, GRAIN, ADDITIVE, WAVETABLE, CHORDS, SPEECH) с тестами по эталонам (ios/CLAUDE.md, раздел S3a).
- Дальше: обёртка голоса по образцу `jambo_voices.cc`, задача #38.
- После движков: #39 (жёлтая точка p-lock и рамка шага в секвенсоре) и #40 (плавная перетяжка миниатюр страниц).

## 6. Важные ограничения
- Ответы на русском, надписи в интерфейсе на английском, комментарии на русском.
- Swift 5, iPadOS 18. Core — только Foundation, тесты запускаются на Linux.
- В аудиоколбэке нет выделений памяти и блокировок. Файлы не длиннее ~600 строк.
- В каждом файле Plaits — шапка «Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet».
- Мелкие коммиты, `git push -u origin swift`, без идентификаторов модели. Не добавлять функций сверх документации.
- Если пользователь говорит «Стоп» — сразу остановиться.

## 7. Первый запрос для нового чата
«Прочитай CLAUDE.md, ios/CLAUDE.md и docs/ai/synth-engines.md. Продолжаем S3a, задача #37: сначала спроси меня про a0, затем перенеси движок VA (0) с тестом по эталону.»
