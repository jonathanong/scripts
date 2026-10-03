# Codex Worktree

Creates a git worktree at `.codex/worktrees/<name>`, checks out a new branch based on `origin/main`, and launches `codex`. Equivalent to `claude --worktree` but for the Codex CLI.

## Install

Add to `~/.zshrc` (or `~/.bashrc`):

```sh
source ~/scripts/codex-worktree/codex-worktree.sh
```

## Usage

Call the function from inside any git repo:

```bash
# Create a worktree with an auto-generated timestamp name
codex-worktree

# Create a worktree with a specific name
codex-worktree my-feature

# Use a different base branch
codex-worktree my-feature origin/develop
```

The worktree is created at `<repo-root>/.codex/worktrees/<name>` on branch `codex/<name>`. The function `cd`s into it and launches `codex`.

When launched from a real tmux terminal, it passes a verified socket, pane, and worktree binding to the Codex process as `AGENT_TMUX_SOCKET`, `AGENT_TMUX_PANE`, and `AGENT_TMUX_WORKTREE`. It matches the controlling terminal rather than trusting inherited `TMUX_PANE` and does not change the parent shell's binding variables.

Without a verified terminal, Codex still starts with those binding values cleared. Background or GUI callers must pass an explicit target to the [window-name helper](../tmux-window-name/README.md); it refuses unbound tmux updates. Keep the sibling `tmux-window-name` directory installed with this script.

## Notes

- Name must match `[A-Za-z0-9._-]`.
- If the worktree directory already exists and is a valid git worktree, the function just `cd`s into it (idempotent).
- This is a **shell function**, not an executable script — source it rather than running it directly, since a subshell would discard the `cd`.
