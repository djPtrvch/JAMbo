#!/usr/bin/env python3
# Отчёт по сборке JAMbo.swiftpm в Xcode (workflow swift-build-profile.yml).
# Читает лог xcodebuild с -debug-time-function-bodies и -warn-long-expression-type-checking,
# файл замеров памяти swift-frontend и пишет Markdown: самые медленные функции и выражения,
# сумма по файлам, пиковая память.
# Запуск: build-profile-report.py <лог сборки> <лог памяти> [<лог памяти WMO>] [<время WMO, с>]
import re
import sys
from collections import defaultdict

TOP = 50
func_re = re.compile(r'^\s*(\d+(?:\.\d+)?)ms\s+(\S+?\.swift):(\d+):(\d+)\s+(.*)$')
expr_re = re.compile(r'^(\S+?\.swift):(\d+):(\d+): warning: (expression|.+?) took (\d+)ms to type-check')


def short(path):
    i = path.find('JAMbo.swiftpm/')
    return path[i + len('JAMbo.swiftpm/'):] if i >= 0 else path


def read_mem(path):
    # Строки «сумма_KB макс_KB число_процессов» раз в секунду.
    total = 0
    single = 0
    procs = 0
    try:
        for line in open(path):
            p = line.split()
            if len(p) < 3:
                continue
            total = max(total, int(p[0]))
            single = max(single, int(p[1]))
            procs = max(procs, int(p[2]))
    except FileNotFoundError:
        pass
    return total, single, procs


def main():
    log = sys.argv[1]
    funcs = {}
    exprs = {}
    for line in open(log, errors='replace'):
        m = func_re.match(line)
        if m:
            ms = float(m.group(1))
            key = (short(m.group(2)), int(m.group(3)), int(m.group(4)))
            # «static method Core.(file).Params.lfoColumn@путь:строка» → «static method Params.lfoColumn».
            name = re.sub(r'@\S+$', '', m.group(5).strip())
            name = re.sub(r'\b\w+\.\(file\)\.', '', name)
            # В пакетном режиме одна функция может выводиться несколько раз — берём наибольшее.
            if key not in funcs or funcs[key][0] < ms:
                funcs[key] = (ms, name)
            continue
        m = expr_re.match(line)
        if m:
            key = (short(m.group(1)), int(m.group(2)), int(m.group(3)))
            ms = float(m.group(5))
            if key not in exprs or exprs[key][0] < ms:
                exprs[key] = (ms, m.group(4))

    per_file = defaultdict(float)
    for (f, _, _), (ms, _) in funcs.items():
        per_file[f] += ms
    total_ms = sum(per_file.values())

    out = []
    out.append('# Профиль сборки JAMbo.swiftpm\n')
    out.append('Проверка типов тел функций, всего: **%.1f с** (%d функций).\n' % (total_ms / 1000, len(funcs)))
    t, s, n = read_mem(sys.argv[2]) if len(sys.argv) > 2 else (0, 0, 0)
    out.append('Обычная сборка: пик памяти swift-frontend — сумма %.0f МБ, один процесс %.0f МБ, процессов одновременно до %d.\n'
               % (t / 1024, s / 1024, n))
    if len(sys.argv) > 3:
        t, s, n = read_mem(sys.argv[3])
        wmo = (' за %s с' % sys.argv[4]) if len(sys.argv) > 4 else ''
        out.append('WMO (весь модуль одним процессом, ближе к iPad)%s: пик памяти — сумма %.0f МБ, один процесс %.0f МБ.\n'
                   % (wmo, t / 1024, s / 1024))

    out.append('\n## Медленные выражения (warn-long-expression-type-checking)\n')
    out.append('| мс | место | что |\n|---:|---|---|')
    for (f, l, c), (ms, what) in sorted(exprs.items(), key=lambda x: -x[1][0])[:TOP]:
        out.append('| %.0f | %s:%d:%d | %s |' % (ms, f, l, c, what))

    out.append('\n## Медленные функции (debug-time-function-bodies), топ %d\n' % TOP)
    out.append('| мс | место | функция |\n|---:|---|---|')
    for (f, l, c), (ms, name) in sorted(funcs.items(), key=lambda x: -x[1][0])[:TOP]:
        out.append('| %.1f | %s:%d | %s |' % (ms, f, l, name.replace('|', '\\|')[:90]))

    out.append('\n## Файлы по сумме времени функций, топ %d\n' % TOP)
    out.append('| мс | доля | файл |\n|---:|---:|---|')
    for f, ms in sorted(per_file.items(), key=lambda x: -x[1])[:TOP]:
        out.append('| %.0f | %.1f %% | %s |' % (ms, 100 * ms / total_ms if total_ms else 0, f))

    dirs = defaultdict(float)
    for f, ms in per_file.items():
        dirs[f.split('/')[0] if '/' in f else '.'] += ms
    out.append('\n## По папкам\n')
    out.append('| мс | папка |\n|---:|---|')
    for d, ms in sorted(dirs.items(), key=lambda x: -x[1]):
        out.append('| %.0f | %s |' % (ms, d))

    print('\n'.join(out))


if __name__ == '__main__':
    main()
