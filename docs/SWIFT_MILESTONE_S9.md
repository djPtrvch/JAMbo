# Веха S9 — проекты и настройки (готова)

Решения — в ios/CLAUDE.md («Решения»: свайп влево, SETTINGS).

### S9a (формат проекта)
- ProjectCoding: недостающее поле — значение по умолчанию, неизвестное — пропускается, не того типа — по умолчанию; новое поле модели — добавить в CodingKeys (тест testCodingKeysCoverAllFields).
- ProjectRepair (как normalizeDoc веба): дорожек 8…16, клипов 16, на странице 16 шагов, длина и играющие страницы в пределах, новые параметры дорожек, FX и мастера — по умолчанию; lens и vels, не совпадающие с notes, снимаются; источник Dynamic EQ без дорожки — OFF. sampleKeys — сэмплы проекта (без «mi:», «builtin:»).
- ProjectStore: Application Support/Projects/<id>.json, ProjectFile (format jambo-swift, version 1, info, doc), запись атомарная, −∞ — строкой. Сэмплы — Samples/<ключ>.caf, при удалении проектов не удаляются (чистка — с библиотекой, S11).

### S9b (автосохранение)
- ProjectSession: id и имя проекта, saved (SAVE), lastAuto (Autosave); unsaved — проект ≠ saved.
- Autosave — через 1,5 с после первого изменения (как интервал веба) и сразу при уходе в фон (с ожиданием записи); запись — в очереди jambo.save. При запуске — Autosave, иначе последний проект (UserDefaults currentProject), иначе новый «Project N». Сэмплы — с диска по ключу в фоне; нет файла — дорожка без звука.

### S9c (PROJECTS)
- NEW, SAVE, SAVE AS (с вопросом о перезаписи); переименование — карандашом в списке; имя до 24 знаков. Список: имя, дата, «120 · C Min»; текущий — жёлтым фоном, Autosave — жёлтым текстом; свайп влево — карандаш и корзина (SwipeRow, общий с пресетами мастера и EQ; строка сужается), у Autosave — только корзина. Тап — окно LOAD / MIX (MIX серая до S10).
- Отличия от веба: LOAD и NEW останавливают игру (во время игры — MIX, S10); после SAVE, SAVE AS и переименования Autosave пишется заново (с новым id и именем). Удалённый Autosave появляется при следующем изменении.

### S9d (бутерброд и SETTINGS)
- Бутерброд: PROJECT (PROJECTS), APP (SETTINGS, DIAGNOSTICS, SELF-TEST, LICENSES); CONTROLLERS и SYNC — S12. Ширина — от бутерброда до правого края SCALE, высота — до строки дорожек; тап мимо меню закрывает его.
- SETTINGS: вкладки RECORD (QUANTIZE, OVERDUB), SAMPLER (SLICE NOTES), SIDECHAIN (SENDS, MUTE TAILS) / MIX, MORPH, LEVEL / AUDIO ENGINE («Now:»), OUTPUT (AVRoutePickerView, текущий выход), APPEARANCE (тема). При запуске открыта RECORD.
- MUTE TAILS в звуке (cutDelayTail веба): заглушили единственный слышимый источник Delay — обратная связь Delay 0 на 100 мс (FxRack.tailLeft; сглаживание FxDelay 20 мс).

### S9e
- Окна APP (AppWindow): DIAGNOSTICS, SELF-TEST (отдельно), LICENSES (Resources/licenses: Plaits и stmlib, MIT).

### S9f (MIX, MORPH, LEVEL — новое, решения пользователя)
- AppSettings: levelRelative, morphAll, morphReturn, mixKey, mixCrossfader (общие для проектов).
- LEVEL: ABSOLUTE — регулятор справа у дорожки = громкость MIX; RELATIVE — Track.trim (dB вниз от MIX, в проекте): регулятор на итоговой громкости, не выше MIX, следует за ней; в звуке — множитель SoundData.trim к громкости и к p-lock громкости MIX; при ABSOLUTE не действует.
- MORPH (MorphModes.swift): ALL TRACKS — Project.morphShift: та же ручка у остальных дорожек (сетка звука и MOD) — сдвиг на ту же долю хода от morphOrig; RETURN — MorphReturn (0, 1, 2, 4, 8 долей), возврат по кадрам (AppModel.morphGlide, applyMorphReturn), в конце — undoMorph и одна запись UNDO; включили MORPH или нажали UNDO во время возврата — возврат останавливается.
- MIX: CHANGE KEY и CROSSFADER только хранятся — действуют с переходами S10.
- Строка дорожек: у выбранной — жёлтая рамка всегда (и у заглушённой; mute — красная M); имена дорожек, MIX и MST — выбранная heavy, остальные semibold.

## Проверено
- CoreTests — 196 (ProjectFileTests, ProjectSessionTests, ProjectActionsTests, MorphModesTests, testMuteTailsCutsDelayRepeats).
- iPad: проекты, автосохранение, PROJECTS, SETTINGS, MUTE TAILS, LEVEL, MORPH, строка дорожек.

## Открыто
- EXPORT, IMPORT, вход аудиоинтерфейса — S11; MIX между проектами (и действие CHANGE KEY, CROSSFADER) — S10; AUTOMATION RECORDING — S13.
- Sampler.swift — 635 строк (больше ~600).
