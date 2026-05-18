# shellcheck shell=bash
git-worktree-reset() {
  local git_common_dir git_dir branch

  if ! command -v git >/dev/null 2>&1; then
    printf 'git-worktree-reset: git is required. Install: brew install git (macOS) or apt-get install git (Linux)\n' >&2
    return 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git-worktree-reset: not inside a git repo — cd into a git repository and retry\n' >&2
    return 1
  fi

  # Refuse to run in the main worktree — only for linked worktrees.
  git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir)" || return
  git_dir="$(git rev-parse --path-format=absolute --git-dir)" || return
  if [ "$git_common_dir" = "$git_dir" ]; then
    printf 'git-worktree-reset: refusing to run in the main worktree — cd into a linked worktree (e.g. .codex/worktrees/<name>) and retry\n' >&2
    return 1
  fi

  branch="$(git rev-parse --abbrev-ref HEAD)" || return
  if [ "$branch" = "HEAD" ]; then
    printf 'git-worktree-reset: detached HEAD — run: git checkout <branch>\n' >&2
    return 1
  fi

  printf 'Fetching origin main...\n'
  git fetch origin main || return

  printf 'Resetting %s to origin/main...\n' "$branch"
  git reset --hard FETCH_HEAD || return
  git clean -fd || return
}
