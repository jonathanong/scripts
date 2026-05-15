# Scripts

A collection of reusable scripts and CI tools. Each subdirectory is self-contained with its own README.

## Index

| Script | Description |
|---|---|
| [agents-md-max-size](agents-md-max-size/README.md) | CI script: fail if any `AGENTS.md` or `CLAUDE.md` file exceeds a configurable line/character count |
| [codex-worktree](codex-worktree/README.md) | Shell function: create a git worktree under `.codex/worktrees/` and open Codex |
| [git-hooks-pre-push-ahead-main](git-hooks-pre-push-ahead-main/README.md) | Git pre-push hook that blocks pushes if the branch is behind `main` |
| [git-worktree-reset](git-worktree-reset/README.md) | Reset a linked worktree to `origin/main` without destroying and recreating it |
| [github-actions-dependabot-automerge](github-actions-dependabot-automerge/README.md) | GitHub Actions workflow: auto-approve and auto-merge Dependabot PRs (minor/patch only) |
| [rust-max-lines-per-file](rust-max-lines-per-file/README.md) | CI script: fail if any Rust source file exceeds a configurable line count |
| [rust-no-inline-tests](rust-no-inline-tests/README.md) | CI script: fail if any `src/` file contains an inline `#[cfg(test)] mod` block |
| [tmux-window-name](tmux-window-name/README.md) | Set the tmux window name and pane title; no-ops outside tmux |
