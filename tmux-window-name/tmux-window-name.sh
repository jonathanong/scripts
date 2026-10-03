#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
  echo "Usage: $0 [--socket PATH --pane %ID --worktree PATH] <name>"
  exit 0
fi

script_path=$0
link_hops=0
while [ -L "$script_path" ]; do
  if [ "$link_hops" -ge 40 ]; then
    printf 'tmux-window-name: symlink chain is too long; reinstall the helper or use its real path.\n' >&2
    exit 1
  fi
  link_dir=$(cd -- "$(dirname -- "$script_path")" && pwd -P) || exit 1
  link_target=$(readlink "$script_path") || exit 1
  case $link_target in
    /*) script_path=$link_target ;;
    *) script_path=$link_dir/$link_target ;;
  esac
  link_hops=$((link_hops + 1))
done
if [ ! -f "$script_path" ]; then
  printf 'tmux-window-name: script target is missing; reinstall the helper or use its real path.\n' >&2
  exit 1
fi
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd -P) || exit 1
if [ ! -f "$script_dir/tmux-target.sh" ]; then
  printf 'tmux-window-name: tmux-target.sh is missing beside the script; reinstall the helper.\n' >&2
  exit 1
fi
tmux_target_socket='' tmux_target_pane='' tmux_target_name=''
# shellcheck disable=SC1091
source "$script_dir/tmux-target.sh"
if tmux_target_parse "$PWD" "$@"; then
  tmux_command=${TMUX_TARGET_BIN:-tmux}
  "$tmux_command" -S "$tmux_target_socket" rename-window -t "$tmux_target_pane" -- "$tmux_target_name"
  "$tmux_command" -S "$tmux_target_socket" select-pane -t "$tmux_target_pane" -T "$tmux_target_name"
else
  cmd_status=$?
  if [ "$cmd_status" -eq 3 ]; then exit 0; fi
  exit "$cmd_status"
fi
