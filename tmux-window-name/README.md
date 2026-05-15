# Tmux Window Name

Sets both the tmux **window name** and **pane title** to a given string. Silently no-ops when not running inside tmux, so it's safe to call unconditionally.

## Usage

```bash
tmux-window-name.sh <name>
```

Commonly called at the top of long-running scripts so the tmux window label reflects what's running:

```bash
#!/usr/bin/env bash
tmux-window-name.sh "api-server"
# ... rest of script
```

## Requirements

- `tmux` must be installed (checked at runtime; exits with an error if missing and `$TMUX_PANE` is set). Install: `brew install tmux` (macOS) or `apt-get install tmux` (Linux).
- Silently exits 0 when `$TMUX_PANE` is unset (i.e., not inside a tmux session).
