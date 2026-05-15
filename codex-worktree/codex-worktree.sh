# shellcheck shell=bash
codex-worktree() {
  local name base common_git_dir main_root worktrees_dir dir branch

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

  codex
}
