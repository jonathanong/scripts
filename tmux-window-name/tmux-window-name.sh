#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <name>" >&2
  echo "Provide a single short label to set as the current tmux window and pane name." >&2
  exit 2
fi

name="$1"

if [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed. Install: brew install tmux (macOS) or apt-get install tmux (Linux)" >&2
  exit 1
fi

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')"

tmux rename-window -t "$window_id" "$name"
tmux select-pane -t "$TMUX_PANE" -T "$name"
