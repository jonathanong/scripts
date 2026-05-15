#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <src_dir> [<src_dir>...]" >&2
  exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "Error: rg (ripgrep) is required. Install: brew install ripgrep (macOS) or apt-get install ripgrep (Linux)" >&2
  exit 1
fi

# rg exits 0 on match, 1 on no match, 2+ on error.
# Temporarily disable errexit so we can capture the exit code.
set +e
rg -n -U --pcre2 \
    '#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]\s*(?:(?://[^\n]*|/\*[\s\S]*?\*/)\s*)*(?:pub(?:\([^)]*\))?\s+)?mod\s+\w+\s*\{' \
    "$@"
rg_exit=$?
set -e

if [ "$rg_exit" -ge 2 ]; then
  echo "Error: rg failed with exit code $rg_exit" >&2
  exit 1
fi

if [ "$rg_exit" -eq 0 ]; then
  echo
  echo "Inline #[cfg(test)] mod ... { ... } blocks are not allowed."
  echo "Use an out-of-line test module instead:"
  echo
  echo "    #[cfg(test)]"
  echo "    mod tests;"
  echo
  echo "and put the tests in src/<module>/tests.rs"
  exit 1
fi

echo "No inline #[cfg(test)] mod blocks found."
