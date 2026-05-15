# Git Worktree Reset

Resets a linked git worktree back to `origin/main` without destroying and recreating it. Repeatedly tearing down and rebuilding worktrees is slow and causes unnecessary disk churn; this function lets you reuse them indefinitely.

## Install

Add to `~/.zshrc` (or `~/.bashrc`):

```sh
source ~/scripts/git-worktree-reset/git-worktree-reset.sh
```

## Usage

Run from inside a linked worktree:

```
! git-worktree-reset
/clear
```

The `/clear` after the reset clears Claude Code's context, since the working directory state has changed significantly.

## What it does

1. Refuses to run in the main worktree (safety guard).
2. Fetches `origin main` to get the latest state.
3. `git reset --hard FETCH_HEAD` — moves the branch tip to `origin/main`.
4. `git clean -fd` — removes untracked files and directories. Gitignored files (caches, `node_modules/`, build artifacts) are intentionally left alone so reinstalls aren't needed after each reset.
