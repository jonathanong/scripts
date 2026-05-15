# Git Pre-Push Hook: Assert Branch is Ahead of Main

Blocks a push if the local branch is behind `main` on the push destination. Fetches `main` fresh before each push so the comparison is always accurate, even if your local `origin/main` ref is stale.

## Why

- Ensures your branch is always up to date before pushing.
- Prevents PRs that will have merge conflicts.
- Avoids wasted CI runs caused by known-stale branches.
- Nudges you to rebase early, before divergence compounds.

## Install

```bash
cp pre-push.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Or to share it across a team via the repo itself:

```bash
# In your repo's setup / bootstrap script:
cp scripts/git-hooks-pre-push-ahead-main/pre-push.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Some teams configure `core.hooksPath` to point at a tracked directory:

```bash
git config core.hooksPath .githooks
mkdir -p .githooks
cp pre-push.sh .githooks/pre-push
chmod +x .githooks/pre-push
```

## Behavior

- Pushes to `main` itself are allowed through unconditionally (branch deletion semantics).
- Branch-deletion pushes (`sha = 0000…`) are skipped.
- If the branch is behind `main` by even one commit, the push is blocked with a message:

  ```
  Error: Branch 'my-feature' is behind origin main by 3 commit(s).
  Please rebase onto the push destination's main before pushing.
  ```

## Fix a blocked push

```bash
git fetch origin
git rebase origin/main
git push
```
