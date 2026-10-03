#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
  echo "Usage: $0 [--socket PATH --pane %ID --worktree PATH] <name>"
  exit 0
fi

# shellcheck source=tmux-target.sh
source "$(cd -- "$(dirname -- "$0")" && pwd -P)/tmux-target.sh"
if tmux_target_parse "$PWD" "$@"; then
  tmux_command=${TMUX_TARGET_BIN:-tmux}
  "$tmux_command" -S "$tmux_target_socket" rename-window -t "$tmux_target_pane" -- "$tmux_target_name"
  "$tmux_command" -S "$tmux_target_socket" select-pane -t "$tmux_target_pane" -T "$tmux_target_name"
else
  cmd_status=$?
  if [ "$cmd_status" -eq 3 ]; then exit 0; fi
  exit "$cmd_status"
fi
