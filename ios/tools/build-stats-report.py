#!/usr/bin/env python3
# Память и объём кода компилятора по файлам (workflow swift-build-profile.yml).
# Читает JSON из -stats-output-dir: сборка по одному файлу на процесс (без пакетного режима) и WMO.
# Запуск: build-stats-report.py <папка stats по файлам> <папка stats WMO>
import json
import os
import re
import sys

TOP = 40
KEYS = [
    ('Frontend.MaxMallocUsage', 'память, МБ', 1 / 1048576),
    ('IRModule.NumIRInsts', 'инструкций IR', 1),
    ('SILModule.NumSILGenFunctions', 'функций SIL', 1),
    ('IRModule.NumIRFunctions', 'функций IR', 1),
]

def load(d):
    out = []
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        if not f.endswith('.json'):
            continue
        try:
            data = json.load(open(os.path.join(d, f)))
        except Exception:
            continue
        if 'swift-frontend' not in f:
            continue
        m = re.search(r'-([A-Za-z0-9_+]+)\.swift-', f)
        out.append((m.group(1) + '.swift' if m else f, data, f))
    return out


def main():
    per = load(sys.argv[1])
    wmo = load(sys.argv[2]) if len(sys.argv) > 2 else []
    o = ['# Память компилятора по файлам\n']
    if per:
        o.append('Процессов компилятора (по одному файлу): %d. В память каждого входит и разбор всех остальных файлов модуля.\n'
                 % len(per))
        for key, title, mul in KEYS[:2]:
            rows = sorted(per, key=lambda r: -r[1].get(key, 0))[:TOP]
            if not rows or rows[0][1].get(key, 0) == 0:
                o.append('\n(нет ключа %s)\n' % key)
                continue
            total = sum(r[1].get(key, 0) for r in per)
            o.append('\n## Файлы по «%s», топ %d (сумма %.0f)\n' % (title, TOP, total * mul))
            o.append('| %s | инстр. IR | функций SIL | файл |\n|---:|---:|---:|---|' % title)
            for name, d, _ in rows:
                o.append('| %.0f | %d | %d | %s |' % (d.get(key, 0) * mul, d.get('IRModule.NumIRInsts', 0),
                                                       d.get('SILModule.NumSILGenFunctions', 0), name))
    for name, d, f in wmo:
        o.append('\n## WMO: %s\n' % f)
        for key, title, mul in KEYS:
            if key in d:
                o.append('- %s: %.0f' % (title, d[key] * mul))
        o.append('\nСамые долгие фазы, с (wall; фазы вложены друг в друга):')
        walls = sorted(((v, k) for k, v in d.items() if k.startswith('time.swift.') and k.endswith('.wall')), reverse=True)
        for v, k in walls[:15]:
            o.append('- %s: %.1f' % (k[len('time.swift.'):-len('.wall')], v))
    print('\n'.join(o))


if __name__ == '__main__':
    main()
