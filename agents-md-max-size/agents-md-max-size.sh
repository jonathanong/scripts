#!/usr/bin/env bash
set -euo pipefail

MAX_LINES="${1:-200}"
MAX_CHARS="${2:-12000}"

for arg in "$MAX_LINES" "$MAX_CHARS"; do
  case "$arg" in
    ''|0|*[!0-9]*)
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

# C.UTF-8 is Linux-only; en_US.UTF-8 works on both macOS and Linux
if LC_ALL=C.UTF-8 locale >/dev/null 2>&1; then
  WC_LOCALE=C.UTF-8
elif LC_ALL=en_US.UTF-8 locale >/dev/null 2>&1; then
  WC_LOCALE=en_US.UTF-8
else
  WC_LOCALE=C
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
fail=0

while IFS= read -r -d '' file; do
  full_path="$REPO_ROOT/$file"
  [ -f "$full_path" ] || continue

  lines=$(awk 'END{print NR}' "$full_path")
  chars=$(LC_ALL="$WC_LOCALE" wc -m < "$full_path" | tr -d ' ')

  if [ "$lines" -gt "$MAX_LINES" ]; then
    echo "::error file=$file::$file has $lines lines (max $MAX_LINES) — trim to keep agent context lean"
    fail=1
  fi
  if [ "$chars" -gt "$MAX_CHARS" ]; then
    echo "::error file=$file::$file has $chars characters (max $MAX_CHARS) — trim to keep agent context lean"
    fail=1
  fi
done < <(git -C "$REPO_ROOT" ls-files -z '**/AGENTS.md' '**/CLAUDE.md')

if [ "$fail" -eq 0 ]; then
  echo "All AGENTS.md / CLAUDE.md files within size limits (lines ≤ $MAX_LINES, chars ≤ $MAX_CHARS)."
fi

exit $fail
