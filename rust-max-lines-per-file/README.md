# Rust Max Lines per File

CI script that enforces a maximum number of code lines per Rust file. Clippy does not have a built-in line-length-per-file lint, so this fills the gap.

## Limits

| Argument | Default max |
|---|---|
| `<src_dir>` | 200 lines |
| `<tests_dir>` (optional) | 500 lines |

Violations are reported as GitHub Actions annotations (`::error file=...`).

## Usage

```bash
rust-max-lines-per-file.sh <src_dir> [<tests_dir>]
```

Examples:

```bash
# Check src only
./rust-max-lines-per-file.sh crates/my-crate/src

# Check src and tests with separate limits
./rust-max-lines-per-file.sh crates/my-crate/src crates/my-crate/tests

# Whole workspace (relies on shell glob)
./rust-max-lines-per-file.sh crates/*/src crates/*/tests
```

Example CI step:

```yaml
- name: Check Rust file line limits
  run: ./rust-max-lines-per-file.sh crates/*/src crates/*/tests
```

## Requirements

- [`tokei`](https://github.com/XAMPPRocky/tokei) — counts code lines (excluding blanks and comments). Install: `brew install tokei` (macOS) or `cargo install tokei` (Linux/macOS)
- [`jq`](https://jqlang.github.io/jq/) — parses tokei's JSON output. Install: `brew install jq` (macOS) or `apt-get install jq` (Linux)

Both are checked at startup; the script exits with an error if either is missing.

## Changing the limits

Edit `SRC_MAX` and `TEST_MAX` at the top of the script.
