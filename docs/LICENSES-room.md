# Лицензии данных Room (Headphone Monitor, фаза 2)

Импульсы пространств меню SPACE `ios/JAMbo.swiftpm/Resources/RoomStudio.caf`, `RoomHome.caf`, `RoomCar.caf`,
`RoomClub.caf`, `RoomDesk.caf`, наборы HEAD `Room*Head.caf`, выровненные варианты для RAW `Room*Flat.caf`, `Room*FlatHead.caf` и `rooms.json` созданы скриптом `ios/tools/generate_rooms.py` (свои модели комнат: мнимые источники, хвост из шума). Чужих
импульсов комнат и импульсов коммерческих продуктов нет.

## HRTF — FABIAN head-related transfer function data base, v4

- Авторы: Fabian Brinkmann, Alexander Lindau, Stefan Weinzierl и др., Technische Universität Berlin.
- Источник: DepositOnce (TU Berlin), DOI 10.14279/depositonce-5718.5 (версия 4, 2020),
  https://depositonce.tu-berlin.de/items/3b423df7-a764-4ce1-9065-4e6034bba759 — файл
  `HRIRs_neutral_head_orientation_v4.zip`.
- Используются: `SOFA/FABIAN_HRIR_measured_HATO_0.sofa` (HRIR, голова прямо) и
  `SOFA/FABIAN_CTF_measured_inverted_smoothed.sofa` (обратная общая передаточная функция — диффузно-полевая
  эквализация); для HEAD — `SOFA/FABIAN_HRIR_measured_HATO_{10…50, 310…350}.sofa` из `FABIAN_HRTF_DATABASE_v4.zip`
  (та же запись, CC BY 4.0; голова повёрнута относительно корпуса на ±10…50°).
- Лицензия: Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0/ — указана в метаданных записи v4 и в самих SOFA-файлах
  (`GLOBAL_License`).
- Изменения: HRIR пересчитаны 44,1 → 48 кГц, по ним собраны прямой звук и ранние отражения виртуальных комнат,
  применены диффузно-полевая и сглаженная фронтальная эквализация; в приложении — только итоговые импульсы комнат.
- Внимание: ранние версии записи (DOI 10.14279/depositonce-5718, -5718.2 и др.) — под CC BY-NC-SA 4.0
  (некоммерческая), их не брать.
- Упоминание в приложении: SETTINGS → OUTPUT → MONITORING (строка о FABIAN HRTF, CC BY 4.0); для App Store —
  то же в описании или разделе благодарностей.

Цитирование: F. Brinkmann, A. Lindau, S. Weinzierl, S. van de Par, M. Müller-Trapet, R. Opdam, M. Vorländer,
"A High Resolution and Full-Spherical Head-Related Transfer Function Database for Different Head-Above-Torso
Orientations", J. Audio Eng. Soc. 65(10), 2017.

## Инструменты генератора

numpy, scipy (BSD), sofar (MIT) — только для сборки ассетов, в приложение не входят.
