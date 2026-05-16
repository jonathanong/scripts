# Reset Usage Timers

Resets usage timers for Claude and Codex at specific times, with the goal to start your day with ~2-3 hours left in the window.

## Requirements

- macOS (uses LaunchAgents)
- This repository must be cloned at `~/scripts` — the plists reference `$HOME/scripts/reset-usage-windows/kick-*` directly

## Claude

Copy to LaunchAgents:

```bash
cp reset-usage-windows/com.jong.kick-claude-window.plist ~/Library/LaunchAgents
```

Load it with launchctl:

```bash
plutil -lint ~/Library/LaunchAgents/com.jong.kick-claude-window.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-claude-window.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-claude-window.plist
launchctl enable gui/$(id -u)/com.jong.kick-claude-window
```

Test through launchd:

```bash
launchctl kickstart -k gui/$(id -u)/com.jong.kick-claude-window
```

Check logs:

```bash
cat /tmp/kick-claude-window.log
cat /tmp/kick-claude-window.err
```

To change the model, edit this line in the plist:

```xml
<string>haiku</string>
```

Then reload:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-claude-window.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-claude-window.plist
launchctl enable gui/$(id -u)/com.jong.kick-claude-window
```

## Codex

Copy to LaunchAgents:

```bash
cp reset-usage-windows/com.jong.kick-codex-window.plist ~/Library/LaunchAgents
```

Load it with launchctl:

```bash
plutil -lint ~/Library/LaunchAgents/com.jong.kick-codex-window.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-codex-window.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-codex-window.plist
launchctl enable gui/$(id -u)/com.jong.kick-codex-window
```

Test through launchd:

```bash
launchctl kickstart -k gui/$(id -u)/com.jong.kick-codex-window
```

Check logs:

```bash
cat /tmp/kick-codex-window.log
cat /tmp/kick-codex-window.err
```

To change models, edit this line in the plist:

```xml
<string>gpt-5.4-mini gpt-5.3-codex-spark</string>
```

Then reload:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-codex-window.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jong.kick-codex-window.plist
launchctl enable gui/$(id -u)/com.jong.kick-codex-window
```
