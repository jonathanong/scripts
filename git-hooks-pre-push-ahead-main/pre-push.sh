#!/bin/sh
set -eu

remote="$1"
remote_url="$2"

# Fetch the latest main from the actual push destination to ensure comparison is accurate.
echo "Fetching $remote main..."
if ! git fetch "$remote_url" main >/dev/null 2>&1; then
  echo "Error: Could not fetch main from push destination '$remote_url'."
  echo "Please check your network/authentication and retry."
  exit 1
fi

# shellcheck disable=SC2034
while IFS= read -r local_ref local_sha remote_ref remote_sha
do
  case "$local_ref" in
    refs/heads/*) ;;
    *) continue ;;
  esac

  # Skip main itself and remote branch deletions.
  if [ "$local_ref" = "refs/heads/main" ] || [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
    continue
  fi

  # Check if the branch being pushed is behind the push destination's main.
  behind_count=$(git rev-list --count "$local_sha"..FETCH_HEAD)
  if [ "${behind_count:-0}" -gt 0 ]; then
    echo "Error: Branch '${local_ref#refs/heads/}' is behind $remote main by $behind_count commit(s)."
    echo "Please rebase onto the push destination's main before pushing."
    exit 1
  fi
done