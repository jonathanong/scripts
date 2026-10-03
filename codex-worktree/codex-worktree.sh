# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# zsh sets $0 to the sourced file; Bash supplies BASH_SOURCE instead.
# Resolve symlink chains before looking for the sibling tmux helper.
CODEX_WORKTREE_SCRIPT_DIR=$(
  script_path=${BASH_SOURCE:-$0}
  link_hops=0
  while [ -L "$script_path" ]; do
    if [ "$link_hops" -ge 40 ]; then
      printf 'codex-worktree: symlink chain is too long; source the real script path.\n' >&2
      exit 1
    fi
    link_dir=$(cd -- "$(dirname -- "$script_path")" && pwd -P) || exit 1
    link_target=$(readlink "$script_path") || exit 1
    if [[ $link_target = /* ]]; then
      script_path=$link_target
    else
      script_path=$link_dir/$link_target
    fi
    link_hops=$((link_hops + 1))
  done
  if [ ! -f "$script_path" ]; then
    printf 'codex-worktree: sourced script target is missing; source the real script path.\n' >&2
    exit 1
  fi
  cd -- "$(dirname -- "$script_path")" && pwd -P
) || return 1

codex-worktree() {
  local name base common_git_dir main_root worktrees_dir dir branch
  local target_socket='' target_pane='' target_worktree=''

  if ! command -v git >/dev/null 2>&1; then
    printf 'codex-worktree: git is required. Install: brew install git (macOS) or apt-get install git (Linux)\n' >&2
    return 1
  fi

  if ! command -v codex >/dev/null 2>&1; then
    printf 'codex-worktree: codex is required. Install: npm install -g @openai/codex\n' >&2
    return 1
  fi

  name="${1:-$(date +%Y%m%d-%H%M%S)}"
  base="${2:-origin/main}"

  case "$name" in
    ''|*[!A-Za-z0-9._-]*)
      printf 'codex-worktree: name must use only A-Z a-z 0-9 . _ - — rerun with a name matching [A-Za-z0-9._-]+\n' >&2
      return 2
      ;;
  esac

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'codex-worktree: not inside a git repo — cd into a git repository and retry\n' >&2
    return 1
  fi

  common_git_dir="$(git rev-parse --path-format=absolute --git-common-dir)" || return
  case "$common_git_dir" in
    */.git) main_root="${common_git_dir%/.git}" ;;
    *)
      printf 'codex-worktree: unsupported git common dir: %s — run from a standard .git-rooted repo\n' "$common_git_dir" >&2
      return 1
      ;;
  esac

  worktrees_dir="$main_root/.codex/worktrees"
  dir="$worktrees_dir/$name"
  branch="codex/$name"

  mkdir -p -- "$worktrees_dir" || return

  if [ -e "$dir" ]; then
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      cd -- "$dir" || return
      return 0
    fi

    rmdir -- "$dir" 2>/dev/null || {
      printf 'codex-worktree: target exists and is not an empty directory: %s — remove or rename it and retry\n' "$dir" >&2
      return 1
    }
  fi

  git -C "$main_root" fetch origin main || return

  if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
    printf 'codex-worktree: branch already exists: %s — run: git branch -D %s\n' "$branch" "$branch" >&2
    return 1
  fi

  git -C "$main_root" worktree add -b "$branch" "$dir" "$base" || return
  cd -- "$dir" || return

  # Capture the real launching terminal, never a pane inherited by a shared runner.
  tmux_target_socket='' tmux_target_pane='' tmux_target_worktree=''
  # shellcheck disable=SC1091
  source "$CODEX_WORKTREE_SCRIPT_DIR/../tmux-window-name/tmux-target.sh" || return
  if tmux_target_resolve "$dir" '' '' ''; then
    target_socket=$tmux_target_socket
    target_pane=$tmux_target_pane
    target_worktree=$tmux_target_worktree
  fi
  # Empty values clear stale dedicated bindings for the child without exporting
  # pane identities into the interactive shell or blocking ordinary Codex work.
  AGENT_TMUX_SOCKET="$target_socket" AGENT_TMUX_PANE="$target_pane" AGENT_TMUX_WORKTREE="$target_worktree" codex
}
