# Handoff: JAMbo, Swift-версия — S9a (окна модулей мастера)

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план — `docs/SWIFT_AUDIT.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба: по отсчётам ≤ −60 dB или полосы ±0,5 dB; каждый эталон — в SELF-TEST. Эталоны Web Audio — настоящий код веба в headless Chromium через протокол отладки (`ios/tools/eq/golden.mjs` — образец).
- Порядок вех (решение пользователя): после S5 — S9a, окна модулей мастера; затем S6 проекты и настройки → S8 → S9 (EQ Dynamic и M/S, пресеты EQ и модулей мастера) → S10 → S11 → S12 → S7.
- Мастер упрощён (S5a): параметры и состав окон — в «Решениях» `ios/CLAUDE.md` (без BIAS, OUTPUT, RANGE, HOLD, LINK, MIX клиппера, UNITY, AUDIT; SCALE — всегда 48 dB; в окнах — BYPASS, FREEZE, ✕; RATIO компрессора — только в окне; PRESETS — S9).

## 3. Текущая задача
S9a: графические окна SAT, COMP, CLIP, LIM — по вебу (ui/saturator.ts, comp.ts, clipper.ts, limiter.ts, masterwin.ts, ~1 800 строк) с упрощениями S5a. Открываются кнопками мастера (тап без SHIFT; SAT — только кнопкой) и тапом по блокам индикации COMP | CLIP | LIM; окно закрывает сетку ручек, ручки 1.1–4.4 при MST управляют теми же параметрами. Сначала — разбивка S9a на части и план (согласовать с пользователем).

## 4. Что уже решено
- S0–S5 готовы и проверены на iPad (итог S5 — docs/SWIFT_MILESTONE_S5.md). SELF-TEST на iPad — 184/184; CoreTests — 149; CPU в отладочной сборке — 51 % в среднем, пик 57 %.
- Для окон уже есть: Core/Master/DynTele — кадры IN / GR / OUT и детектор компрессора (раз в 256 отсчётов, кольцо 2048 кадров — хватит истории окон); Core/Master/MasterScope — точки съёма; UI/MasterIndicator (LevelBars); UI/MasterButtons (тап без SHIFT — место для открытия окна); Params.masterGrid; Project.master и *Bypass.
- После проверки S5d (отличия от веба): ATTACK компрессора нового проекта — 30 мс, Rev Size — 40 %; ● MASTER — под окном при MIX; при MST окно индикации выше (строки под ним нет).

## 5. Что осталось решить
- Состав и вид каждого окна в Swift (что из веба переносится 1:1, что убрано по S5a), FREEZE, где кнопка RATIO.
- Отложено: M/S, Dynamic, пресеты — S9; запись мастера и стемов — S10; MUTE TAILS — S6; ускорение — S7.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк; тело View ≤ ~40 строк.
- Playgrounds: выражения — по шагам с явными типами (иначе «unable to type-check»); UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские. Окна закрываются квадратным ✕.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- «Пришли проект» — полный zip ветки `swift` (`git archive`) в чат. PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md, docs/ai/master-chain.md и docs/ai/master-clip-lim.md (окна модулей мастера). Предложи разбивку S9a и план.»
