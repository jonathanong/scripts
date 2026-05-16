# agents-md-max-size

CI script that enforces line and character limits on `AGENTS.md` and `CLAUDE.md` files across a git repository. These instruction files grow over time and bloat agent context windows — keeping them small improves response quality and reduces token cost.

## Limits

| Argument | Default |
|---|---|
| `<max_lines>` | 200 lines |
| `<max_chars>` | 12000 characters |

Violations are reported as GitHub Actions annotations (`::error file=...`).

## Usage

```bash
./agents-md-max-size.sh [<max_lines>] [<max_chars>]
```

Examples:

```bash
# Check with defaults (200 lines, 12 000 chars)
./agents-md-max-size.sh

# Custom limits
./agents-md-max-size.sh 150 8000
```

Example CI step:

```yaml
- name: Check AGENTS.md / CLAUDE.md size limits
  run: ./agents-md-max-size.sh
```

## Requirements

- [`git`](https://git-scm.com/) — used to enumerate tracked files. Install: `brew install git` (macOS) or `apt-get install git` (Linux).

Must be run from inside a git repository.

## Reference

- [Claude Code memory documentation](https://code.claude.com/docs/en/memory) — explains how `AGENTS.md` / `CLAUDE.md` files are loaded into agent context and why size matters.
