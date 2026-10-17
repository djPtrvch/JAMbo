#!/usr/bin/env bash
# Архив проекта для iPad: ios/JAMbo.swiftpm → ios/JAMbo.swiftpm.zip (распаковать в «Файлах», открыть в Swift Playgrounds).
# Пересобирать в каждом коммите, который меняет ios/JAMbo.swiftpm.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f JAMbo.swiftpm.zip
zip -qr -X JAMbo.swiftpm.zip JAMbo.swiftpm -x '*/.DS_Store' '*/.build/*' '*/.swiftpm/*'
ls -lh JAMbo.swiftpm.zip
