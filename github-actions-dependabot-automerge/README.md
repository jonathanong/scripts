# Dependabot Auto-merge

GitHub Actions workflow that automatically approves and enables auto-merge for Dependabot PRs, as long as the update is not a semver-major version bump.

## What it does

1. Detects that the PR author is `dependabot[bot]`.
2. Skips draft PRs.
3. Parses the PR title and body to detect major version bumps (e.g. `1.x → 2.x`). Major bumps are skipped so a human can review them.
4. Approves the PR if no active approval exists yet.
5. Enables auto-merge (squash) via the GitHub GraphQL API.

Auto-merge only completes after all required status checks pass, so this workflow does not bypass branch protection.

## Setup

1. Copy `.github/workflows/dependabot-automerge.yml` into your repository.
2. Enable auto-merge on the repository: **Settings → General → Allow auto-merge**.
3. Configure branch protection on `main` with at least one required status check. Without a required check, auto-merge fires immediately after approval.

### Permissions

The workflow uses `GITHUB_TOKEN` with `pull-requests: write` and `contents: write`. No additional secrets are needed.

## Customization

- **Allow major bumps**: Remove the `hasMajorBump` check.
- **Different merge method**: Change `mergeMethod: SQUASH` to `MERGE` or `REBASE`.
- **Restrict to specific packages**: Add a filter on `pr.title` before the `hasMajorBump` call.
