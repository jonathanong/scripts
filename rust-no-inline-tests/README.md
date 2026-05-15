# Rust No Inline Tests

CI script that forbids inline `#[cfg(test)] mod tests { … }` blocks. All tests must live in a separate out-of-line module.

## Why

Inline test modules balloon source files. Keeping tests out-of-line enforces a hard ceiling on `src/` file size (see [`rust-max-lines-per-file`](../rust-max-lines-per-file/README.md)) and makes the production/test split obvious at a glance.

## The required pattern

Instead of:

```rust
// src/foo.rs
#[cfg(test)]
mod tests {
    // ...
}
```

Use:

```rust
// src/foo.rs
#[cfg(test)]
mod tests;   // ← out-of-line declaration

// src/foo/tests.rs  ← test code lives here
```

## Usage

```bash
rust-no-inline-tests.sh <src_dir> [<src_dir>...]
```

Examples:

```bash
./rust-no-inline-tests.sh src

# Multiple directories
./rust-no-inline-tests.sh crates/*/src

# Multiple explicit paths
./rust-no-inline-tests.sh crates/foo/src crates/bar/src
```

Example CI step:

```yaml
- name: Check for inline test modules
  run: ./rust-no-inline-tests.sh crates/*/src
```

## Requirements

- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) with PCRE2 support — used for multi-line pattern matching. Install: `brew install ripgrep` (macOS) or `apt-get install ripgrep` (Linux)

Checked at startup; the script exits with an error if `rg` is missing.
