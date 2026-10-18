# Handoff: JAMbo, Swift-версия — проверка S5d и итог вехи S5

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план — `docs/SWIFT_AUDIT.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба: по отсчётам ≤ −60 dB или полосы ±0,5 dB; каждый эталон — в SELF-TEST. Эталоны Web Audio — настоящий код веба в headless Chromium через протокол отладки (`ios/tools/eq/golden.mjs` — образец).
- Разбивка S5: S5a — мастер в Core; S5b — EQ; S5c — измеритель, LUFS, метры MIX, индикация, скоп; S5d — ручки MST, кнопки мастера, громкость выхода, последовательности MIX и MST. Все части готовы в коде.
- S5d (решения пользователя): ручки MST без p-lock, как в вебе (последовательность MST есть, но ставить на неё нечего); кнопки мастера — в S5d; ATTACK компрессора нового проекта — 30 мс, Rev Size — 40 % (в вебе 10 и 50; эталоны — от значений веба); ● MASTER — под окном при MIX, на месте стрелок папки (окно при MIX размером с окно дорожки); при MST строки под окном нет — окно индикации выше, как было.

## 3. Текущая задача
Проверка S5d на iPad, исправления по итогам, затем итог вехи S5: docs/SWIFT_MILESTONE_S5.md (раздел «Итог»), ios/CLAUDE.md («Текущая веха», «Вехи»), корневой CLAUDE.md («Состояние вех»: S5 готов, дальше S6 — проекты и настройки).

## 4. Что уже решено
- S0–S4 готовы и проверены на iPad. S5a: мастер (19 эталонов). S5b: EQ (13 эталонов). S5c: измеритель, LUFS, метры MIX, индикация COMP | CLIP | LIM, скоп. SELF-TEST — 184.
- S5d (подробно — docs/SWIFT_MILESTONE_S5.md, раздел S5d):
  - Params.masterGrid; в ParamDef — step, autoTop (AUTO), offBottom (OFF), noLock.
  - UI/MasterButtons: CLIP, LIM / SAT, COMP на месте LFO1–3/ENV; с SHIFT — BYPASS (UNDO, цвет модуля); тап без SHIFT — окно (S9).
  - Project.outVol — громкость выхода последней в MasterChain (после точки LIM скопа, до гониометра и измерителя); регулятор на измерителе при MIX и MST.
  - Project.chanSeqs (MIX, MST): свои страницы и длина, с PLAY с первого шага; p-lock громкостей на шагах MIX → Sequencer.mixLockMask/mixLockGain → SamplerMix; p-lock переезжают при удалении и перестановке дорожек. В AppModel — `seq`, `editSeq`, `openPlayPos` (показанная последовательность) и `trackPlayPos` (дорожка: пианоролл, окно синта).
  - CoreTests — 149.
- Подтверждено на iPad: серый метр заглушённой дорожки на измерителе.

## 5. Что осталось решить
- Не проверено на iPad: сборка S5d, ручки MST (подписи AUTO, OFF, dB), кнопки мастера и BYPASS, регулятор выхода, p-lock MIX и миниатюры MIX, окно MIX с ● MASTER, ATTACK 30 мс и Rev Size 40 %.
- Не подтверждено с S5c: метры MIX после исправления, SELF-TEST 184/184, звук мастера и EQ на мастере, CPU.
- Отложено: окна модулей мастера, тап по блоку индикации, M/S, Dynamic, пресеты EQ и модулей — S9; запись мастера и стемов (● MASTER, ●) — S10; MUTE TAILS — S6; ускорение — S7.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк.
- Playgrounds: выражения — по шагам с явными типами (иначе «unable to type-check»); UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат. PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md и docs/SWIFT_MILESTONE_S5.md (раздел S5d). Вот итоги проверки S5d на iPad: …»
