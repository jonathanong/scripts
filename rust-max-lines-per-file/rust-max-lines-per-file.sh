#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <src_dir> [<tests_dir>]" >&2
  exit 2
fi

if ! command -v tokei >/dev/null 2>&1; then
  echo "Error: tokei is required. Install: brew install tokei (macOS) or cargo install tokei (Linux/macOS)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  exit 1
fi

SRC_MAX=200
TEST_MAX=500
fail=0

check_dir() {
  local dir="$1" max="$2"
  local json
  json=$(tokei "$dir" --files --output json)

  while IFS=$'\t' read -r lines file; do
    if [ -n "$file" ] && [ "$lines" -gt "$max" ]; then
      echo "::error file=$file::$file has $lines code lines (max $max) — split into smaller modules to bring it under $max lines"
      fail=1
    fi
  done < <(printf '%s' "$json" | jq -r '.Rust?.reports[]? | [.stats.code, .name] | @tsv')
}

check_dir "$1" "$SRC_MAX"

if [ "$#" -ge 2 ]; then
  check_dir "$2" "$TEST_MAX"
fi

if [ "$fail" -eq 0 ]; then
  echo "All Rust files within line limits."
fi

exit $fail
