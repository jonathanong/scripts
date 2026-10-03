# Tmux Window Name

Sets the tmux **window name** and **pane title** on a verified task pane. Silently no-ops when there is no tmux context.

## Usage

```bash
tmux-window-name.sh <name>
```

Interactive calls identify their pane from the controlling terminal. Viewing another window does not change the target. The inherited `TMUX_PANE` alone is never sufficient.

Background, GUI, and shared-runner calls must provide the complete target binding and run from the task's worktree:

```bash
~/scripts/tmux-window-name/tmux-window-name.sh \
  --socket /tmp/tmux-501/default --pane %80 \
  --worktree "$PWD" "infra-tmux-fix"
```

Use the actual socket and pane supplied by the task launcher, not the example values. A launcher can also pass `AGENT_TMUX_SOCKET`, `AGENT_TMUX_PANE`, and `AGENT_TMUX_WORKTREE` to its agent process; `codex-worktree` does this for a verified launching terminal. Complete command-line options override that environment binding.

The helper checks that the live pane and binding belong to the caller's Git worktree (or the same physical directory outside Git). Missing, partial, and mismatched bindings fail without updating tmux. It never guesses from a worktree path: multiple panes may share one path. Use `--` before a label beginning with `-`.

Commonly called at the top of long-running scripts so the tmux window label reflects what's running:

```bash
#!/usr/bin/env bash
tmux-window-name.sh "api-server"
# ... rest of script
```

## Requirements

- `tmux` must be installed when a tmux context or explicit binding is supplied. Install: `brew install tmux` (macOS) or `apt-get install tmux` (Linux).
- Supports Linux and macOS Bash, including macOS Bash 3.2. Git worktree validation uses Git when available.
- For regression tests, run `bash tmux-window-name/tmux-target.test.sh`; tests use isolated servers and require Git, tmux, Bash, and zsh.
