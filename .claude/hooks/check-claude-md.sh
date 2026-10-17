#!/bin/bash
# Контроль размера CLAUDE.md в корне проекта (хук PostToolUse для Edit|Write).
# < 120 строк — молча; 120–149 — предупреждение; ≥ 150 — ошибка (код 2): файл надо сократить.
# Только bash и стандартные утилиты macOS (sed, awk, tr), без jq.

SOFT=120
HARD=150

input=$(cat)
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
target="$project/CLAUDE.md"

# Путь изменённого файла из JSON события (tool_input.file_path).
file=$(printf '%s' "$input" | tr '\n' ' ' \
  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Только CLAUDE.md в корне проекта.
[ "$file" = "$target" ] || exit 0
[ -f "$target" ] || exit 0

# awk учитывает и последнюю строку без перевода строки (wc -l — нет).
lines=$(awk 'END { print NR }' "$target")

if [ "$lines" -ge "$HARD" ]; then
  echo "CLAUDE.md: $lines строк — предел $HARD. Дальнейшие изменения остановлены: сократите CLAUDE.md, вынесите редкие правила в docs/ai/ или docs/specs/ (путь, причину и текст — предложить пользователю и получить подтверждение)." >&2
  exit 2
fi

if [ "$lines" -ge "$SOFT" ]; then
  msg="CLAUDE.md: $lines строк (мягкий порог $SOFT, предел $HARD). Предложите вынести редкие правила в docs/ai/ или docs/specs/."
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$msg" "$msg"
fi
exit 0
