#!/usr/bin/env bash
set -euo pipefail

MAX_LINES="${1:-200}"
MAX_CHARS="${2:-12000}"

# Validate that args are positive integers
for arg in "$MAX_LINES" "$MAX_CHARS"; do
  case "$arg" in
    ''|*[!0-9]*)
      echo "Usage: $0 [<max_lines>] [<max_chars>]" >&2
      echo "  max_lines  maximum number of lines (default: 200)" >&2
      echo "  max_chars  maximum number of characters (default: 12000)" >&2
      exit 2
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required." >&2
  echo "  macOS: brew install git" >&2
  echo "  Linux: apt-get install git" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: must be run from inside a git repository." >&2
  echo "  Action: cd into your project and try again." >&2
  exit 1
fi

fail=0

while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue

  # Get both line and character counts in a single pass
  # Use LC_ALL=C.UTF-8 to ensure consistent character counting
  read -r lines chars < <(LC_ALL=C.UTF-8 wc -lm < "$file")

  if [ "$lines" -gt "$MAX_LINES" ]; then
    echo "::error file=$file::$file has $lines lines (max $MAX_LINES) — trim to keep agent context lean"
    fail=1
  fi
  if [ "$chars" -gt "$MAX_CHARS" ]; then
    echo "::error file=$file::$file has $chars characters (max $MAX_CHARS) — trim to keep agent context lean"
    fail=1
  fi
done < <(git ls-files -z '**/AGENTS.md' '**/CLAUDE.md')

if [ "$fail" -eq 0 ]; then
  echo "All AGENTS.md / CLAUDE.md files within size limits (lines ≤ $MAX_LINES, chars ≤ $MAX_CHARS)."
fi

exit $fail
