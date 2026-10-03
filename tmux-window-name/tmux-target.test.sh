#!/usr/bin/env bash
# The repeated subshell exports intentionally isolate ambient tmux variables.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
repo_dir=$(cd -- "$script_dir/.." && pwd -P)
name_helper=$script_dir/tmux-window-name.sh
launcher=$repo_dir/codex-worktree/codex-worktree.sh
test_dir=$(mktemp -d /tmp/tmux-target-test.XXXXXX)
test_dir=$(cd -- "$test_dir" && pwd -P)
socket_a=$test_dir/a.sock
socket_b=$test_dir/b.sock
repo_a=$test_dir/repo-a
repo_b=$test_dir/repo-b
linked=$test_dir/linked

cleanup() {
  tmux -S "$socket_a" kill-server >/dev/null 2>&1 || true
  tmux -S "$socket_b" kill-server >/dev/null 2>&1 || true
  if [ "${TMUX_TEST_KEEP:-}" = 1 ]; then
    printf 'retained test directory: %s\n' "$test_dir" >&2
  else
    rm -rf -- "$test_dir"
  fi
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() {
  if [ "$1" != "$2" ]; then fail "expected [$2], got [$1]: $3"; fi
}
wait_for_file() {
  local path=$1 attempt=0
  while [ ! -f "$path" ] && [ "$attempt" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done
  [ -f "$path" ] || fail "timed out waiting for $path"
}
pane() { tmux -S "$1" list-panes -t "$2" -F '#{pane_id}'; }
window_name() { tmux -S "$1" display-message -p -t "$2" '#{window_name}'; }
pane_title() { tmux -S "$1" display-message -p -t "$2" '#{pane_title}'; }
name_from() {
  local directory=$1
  shift
  (cd -- "$directory" && "$name_helper" "$@")
}
name_path_from() {
  local directory=$1 helper_path=$2
  shift 2
  (cd -- "$directory" && "$helper_path" "$@")
}
expect_failure() {
  if "$@" >"$test_dir/last.out" 2>"$test_dir/last.err"; then
    fail "command unexpectedly succeeded: $*"
  fi
}
expect_status() {
  local expected=$1 actual
  shift
  if "$@" >"$test_dir/last.out" 2>"$test_dir/last.err"; then
    actual=0
  else
    actual=$?
  fi
  assert_eq "$actual" "$expected" "exit status for $*"
}

for repository in "$repo_a" "$repo_b"; do
  git init -q -b main "$repository"
  git -C "$repository" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m init
done
git -C "$repo_a" worktree add -q -b linked "$linked"
tmux -f /dev/null -S "$socket_a" new-session -d -s test -n first -c "$repo_a" 'sleep 120'
tmux -S "$socket_a" new-window -d -t test -n second -c "$repo_b" 'sleep 120'
tmux -f /dev/null -S "$socket_b" new-session -d -s test -n first -c "$repo_b" 'sleep 120'
pane_a=$(pane "$socket_a" test:first)
pane_other=$(pane "$socket_a" test:second)
pane_b=$(pane "$socket_b" test:first)
assert_eq "$pane_a" "$pane_b" 'isolated servers should reuse the same pane ID'

# The selected/viewed window may differ from the target. Every write must use
# the named pane on the named server.
tmux -S "$socket_a" select-window -t test:second
name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" alpha
assert_eq "$(window_name "$socket_a" "$pane_a")" alpha 'target window'
assert_eq "$(pane_title "$socket_a" "$pane_a")" alpha 'target pane title'
assert_eq "$(window_name "$socket_a" "$pane_other")" second 'viewed window unchanged'

# Git repository selectors and runtime config inherited from a different
# checkout must not collapse the caller, binding, and pane into one fake root.
(
  export GIT_DIR=$repo_a/.git GIT_WORK_TREE=$repo_a GIT_COMMON_DIR=$repo_a/.git
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0=$repo_a
  expect_failure name_from "$repo_b" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" wrong-git-root
  expect_failure name_from "$repo_b" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_b" wrong-live-pane
  name_from "$repo_b" --socket "$socket_a" --pane "$pane_other" --worktree "$repo_b" valid-git-root
)
assert_eq "$(window_name "$socket_a" "$pane_a")" alpha 'wrong pane refused under Git overrides'
assert_eq "$(window_name "$socket_a" "$pane_other")" valid-git-root 'correct pane accepted under Git overrides'
name_from "$repo_b" --socket "$socket_a" --pane "$pane_other" --worktree "$repo_b" second

# A repository trusted through ordinary global safe.directory configuration
# remains discoverable, even when ownership validation would otherwise fail.
# The wrapper enables Git's ownership test after the resolver has scrubbed its
# inherited Git environment. Ignore machine system config in this fixture, as
# it may already trust every path; normal global config still loads from HOME.
mkdir "$repo_a/nested" "$test_dir/trust-home" "$test_dir/gitbin"
real_git=$(command -v git)
printf '#!/usr/bin/env bash\nGIT_CONFIG_NOSYSTEM=1 GIT_TEST_ASSUME_DIFFERENT_OWNER=1 exec %q "$@"\n' "$real_git" >"$test_dir/gitbin/git"
chmod +x "$test_dir/gitbin/git"
(
  export HOME=$test_dir/trust-home PATH="$test_dir/gitbin:$PATH"
  # Some packaged Git builds do not honor this internal ownership-test seam.
  # Probe with an empty global config before asserting the refusal.
  if GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
      "$real_git" -C "$repo_a/nested" rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'Git ownership-test seam unavailable; skipping untrusted refusal assertion\n' >&2
  else
    expect_failure name_from "$repo_a/nested" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" untrusted
  fi
  "$real_git" config --file "$HOME/.gitconfig" --add safe.directory "$repo_a"
  name_from "$repo_a/nested" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" trusted
)
assert_eq "$(window_name "$socket_a" "$pane_a")" trusted 'global safe.directory retains Git root discovery'
name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" alpha

# Installed command links may be absolute, relative, or a chain of both.
# Sibling sources must be found beside the real script, not beside the link.
mkdir "$test_dir/linkbin"
ln -s "$name_helper" "$test_dir/linkbin/name-absolute"
ln -s name-absolute "$test_dir/linkbin/name-relative"
for linked_helper in "$test_dir/linkbin/name-absolute" "$test_dir/linkbin/name-relative"; do
  (
    unset TMUX TMUX_PANE AGENT_TMUX_SOCKET AGENT_TMUX_PANE AGENT_TMUX_WORKTREE
    expect_status 0 name_path_from "$repo_a" "$linked_helper" outside
  )
  name_path_from "$repo_a" "$linked_helper" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" linked-helper
  assert_eq "$(window_name "$socket_a" "$pane_a")" linked-helper 'linked helper targets real sibling'
done
ln -s missing-target "$test_dir/linkbin/name-broken"
ln -s name-cycle-b "$test_dir/linkbin/name-cycle-a"
ln -s name-cycle-a "$test_dir/linkbin/name-cycle-b"
expect_failure name_path_from "$repo_a" "$test_dir/linkbin/name-broken" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" wrong
expect_failure name_path_from "$repo_a" "$test_dir/linkbin/name-cycle-a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" wrong

# An entire CLI tuple overrides a stale ambient dedicated tuple and TMUX_PANE.
(
  export AGENT_TMUX_SOCKET=$socket_a AGENT_TMUX_PANE=$pane_other AGENT_TMUX_WORKTREE=$repo_b
  export TMUX="$socket_a,1,0" TMUX_PANE=$pane_other
  name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" explicit
)
assert_eq "$(window_name "$socket_a" "$pane_a")" explicit 'CLI tuple overrides ambient tuple'
expect_failure name_from "$repo_a" --socket "$socket_a" --pane "$pane_other" --worktree "$repo_b" wrong
expect_failure name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_b" wrong
expect_failure name_from "$repo_a" --socket "$socket_a" --pane bad --worktree "$repo_a" wrong
expect_failure name_from "$repo_a" --socket "$socket_a" --pane %999999 --worktree "$repo_a" wrong
expect_failure name_from "$repo_a" --socket "$test_dir/missing.sock" --pane "$pane_a" --worktree "$repo_a" wrong
expect_status 2 name_from "$repo_a" --socket "$socket_a" wrong
expect_failure name_from "$repo_a" --socket relative.sock --pane "$pane_a" --worktree "$repo_a" wrong
(
  export AGENT_TMUX_SOCKET=$socket_a AGENT_TMUX_PANE=$pane_other AGENT_TMUX_WORKTREE=$repo_b
  expect_failure name_from "$repo_a" wrong
)
(
  export AGENT_TMUX_SOCKET=$socket_a AGENT_TMUX_PANE='' AGENT_TMUX_WORKTREE=$repo_a
  expect_failure name_from "$repo_a" wrong
)
assert_eq "$(window_name "$socket_a" "$pane_a")" explicit 'invalid targets did not rename target'
assert_eq "$(window_name "$socket_a" "$pane_other")" second 'invalid targets did not rename neighbor'

# A matching pane number on a different server must never direct the write to
# the first server. Git-linked worktrees are distinct despite one common git dir.
name_from "$repo_b" --socket "$socket_b" --pane "$pane_b" --worktree "$repo_b" server-b
assert_eq "$(window_name "$socket_b" "$pane_b")" server-b 'second server target'
assert_eq "$(window_name "$socket_a" "$pane_a")" explicit 'first server unchanged'
tmux -S "$socket_a" new-window -d -t test -n linked -c "$linked" 'sleep 120'
pane_linked=$(pane "$socket_a" test:linked)
expect_failure name_from "$linked" --socket "$socket_a" --pane "$pane_a" --worktree "$linked" wrong
name_from "$linked" --socket "$socket_a" --pane "$pane_linked" --worktree "$linked" linked-ok
assert_eq "$(window_name "$socket_a" "$pane_linked")" linked-ok 'linked worktree target'
(
  export GIT_DIR=$repo_a/.git GIT_WORK_TREE=$repo_a GIT_COMMON_DIR=$repo_a/.git
  expect_failure name_from "$linked" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" wrong-linked-root
  name_from "$linked" --socket "$socket_a" --pane "$pane_linked" --worktree "$linked" linked-ok
)
assert_eq "$(window_name "$socket_a" "$pane_a")" explicit 'linked worktree override did not rename main pane'

# Pane identity must continue to select its containing window after a move.
tmux -S "$socket_a" move-pane -s "$pane_a" -t "$pane_other"
name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" moved
assert_eq "$(window_name "$socket_a" "$pane_a")" moved 'moved pane window'
assert_eq "$(window_name "$socket_a" "$pane_other")" moved 'new shared window'
assert_eq "$(window_name "$socket_a" "$pane_linked")" linked-ok 'unrelated window after move'

# A label is passed as literal data, including shell metacharacters. An empty
# label clears the pane title.
# shellcheck disable=SC2016
label='literal $(touch injected) ; $HOME `backtick`'
name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" "$label"
# tmux sanitizes stored window names differently across platforms. Compare the
# helper with a direct tmux rename using the identical argument on this server.
tmux -S "$socket_a" new-window -d -t test -n literal-baseline -c "$repo_a" 'sleep 120'
pane_baseline=$(pane "$socket_a" test:literal-baseline)
tmux -S "$socket_a" rename-window -t "$pane_baseline" -- "$label"
tmux -S "$socket_a" select-pane -t "$pane_baseline" -T "$label"
assert_eq "$(window_name "$socket_a" "$pane_a")" "$(window_name "$socket_a" "$pane_baseline")" 'literal window label matches tmux behavior'
assert_eq "$(pane_title "$socket_a" "$pane_a")" "$(pane_title "$socket_a" "$pane_baseline")" 'literal pane title matches tmux behavior'
[ ! -e "$repo_a/injected" ] || fail 'label executed as a shell command'
name_from "$repo_a" --socket "$socket_a" --pane "$pane_a" --worktree "$repo_a" ''
assert_eq "$(pane_title "$socket_a" "$pane_a")" '' 'empty name clears pane title'
assert_eq "$(window_name "$socket_a" "$pane_a")" '' 'empty name clears window name'

# Outside tmux remains a no-op. A background process with only ambient tmux
# metadata must fail instead of using an inherited pane.
(
  unset TMUX TMUX_PANE AGENT_TMUX_SOCKET AGENT_TMUX_PANE AGENT_TMUX_WORKTREE
  expect_status 0 name_from "$repo_a" outside
)
(
  unset AGENT_TMUX_SOCKET AGENT_TMUX_PANE AGENT_TMUX_WORKTREE
  export TMUX="$socket_a,1,0" TMUX_PANE=$pane_a
  expect_status 1 name_from "$repo_a" stale-background
)

# For a non-Git directory, the physical directory must match exactly.
mkdir "$test_dir/plain" "$test_dir/other"
tmux -S "$socket_b" new-window -d -t test -n plain -c "$test_dir/plain" 'sleep 120'
pane_plain=$(pane "$socket_b" test:plain)
name_from "$test_dir/plain" --socket "$socket_b" --pane "$pane_plain" --worktree "$test_dir/plain" plain-ok
expect_failure name_from "$test_dir/other" --socket "$socket_b" --pane "$pane_plain" --worktree "$test_dir/plain" wrong
(
  export GIT_DIR=$repo_a/.git GIT_WORK_TREE=$repo_a GIT_COMMON_DIR=$repo_a/.git
  name_from "$test_dir/plain" --socket "$socket_b" --pane "$pane_plain" --worktree "$test_dir/plain" plain-ok
  expect_failure name_from "$test_dir/other" --socket "$socket_b" --pane "$pane_plain" --worktree "$test_dir/plain" wrong
)
assert_eq "$(window_name "$socket_b" "$pane_plain")" plain-ok 'non-Git mismatch refused'

# Run inside an actual tmux pane, with its controlling TTY. This is the only
# permitted implicit target mode.
cat >"$test_dir/interactive.sh" <<'DRIVER'
#!/usr/bin/env bash
"$1" tty-bound >"$2.out" 2>&1
first_status=$?
printf 'piped input\n' | "$1" tty-piped >"$2.piped.out" 2>&1
second_status=$?
printf '%s\n' "$first_status" "$second_status" >"$2"
exec sleep 30
DRIVER
interactive_result=$test_dir/interactive.result
pane_interactive=$(tmux -S "$socket_a" new-window -d -P -F '#{pane_id}' -t test -n interactive -c "$repo_a" "bash '$test_dir/interactive.sh' '$name_helper' '$interactive_result'")
wait_for_file "$interactive_result"
assert_eq "$(sed -n '1p' "$interactive_result")" 0 'interactive terminal target succeeds'
assert_eq "$(sed -n '2p' "$interactive_result")" 0 'piped stdin retains real controlling terminal'
assert_eq "$(window_name "$socket_a" "$pane_interactive")" tty-piped 'interactive pane renamed itself'

# A sourced launcher binds the child from its genuine terminal. It must not
# overwrite the parent shell's stale dedicated variables.
git init -q --bare "$test_dir/remote.git"
git -C "$repo_a" remote add origin "$test_dir/remote.git"
git -C "$repo_a" push -q origin main
mkdir "$test_dir/bin"
cat >"$test_dir/bin/codex" <<'CODEX'
#!/usr/bin/env bash
printf '%s\n' "$AGENT_TMUX_SOCKET" "$AGENT_TMUX_PANE" "$AGENT_TMUX_WORKTREE" >"$FAKE_CODEX_LOG"
CODEX
chmod +x "$test_dir/bin/codex"
cat >"$test_dir/launcher-driver.sh" <<'DRIVER'
#!/usr/bin/env bash
export PATH="$TEST_BIN:$PATH" FAKE_CODEX_LOG=$TEST_CHILD_LOG
export AGENT_TMUX_SOCKET=stale-socket AGENT_TMUX_PANE=%999 AGENT_TMUX_WORKTREE=stale-worktree
source "$TEST_LAUNCHER"
codex-worktree "$TEST_NAME" >"$TEST_LOG" 2>&1
printf '%s\n' "$?" >"$TEST_STATUS"
printf '%s\n' "$AGENT_TMUX_SOCKET" "$AGENT_TMUX_PANE" "$AGENT_TMUX_WORKTREE" >"$TEST_PARENT_LOG"
exec sleep 30
DRIVER
cat >"$test_dir/launcher-driver.zsh" <<'DRIVER'
#!/usr/bin/env zsh
emulate zsh
unsetopt functionargzero
export PATH="$TEST_BIN:$PATH" FAKE_CODEX_LOG=$TEST_CHILD_LOG
export AGENT_TMUX_SOCKET=stale-socket AGENT_TMUX_PANE=%999 AGENT_TMUX_WORKTREE=stale-worktree
source "$TEST_LAUNCHER"
codex-worktree "$TEST_NAME" >"$TEST_LOG" 2>&1
printf '%s\n' "$?" >"$TEST_STATUS"
printf '%s\n' "$AGENT_TMUX_SOCKET" "$AGENT_TMUX_PANE" "$AGENT_TMUX_WORKTREE" >"$TEST_PARENT_LOG"
exec sleep 30
DRIVER

# An incomplete installation must fail before fetch/worktree creation or cd.
mkdir -p "$test_dir/orphan/codex-worktree"
cp "$launcher" "$test_dir/orphan/codex-worktree/codex-worktree.sh"
before_remote_ref=$(git -C "$repo_a" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)
(
  cd -- "$repo_a"
  original_dir=$PWD
  # shellcheck disable=SC1091
  source "$test_dir/orphan/codex-worktree/codex-worktree.sh"
  export PATH="$test_dir/bin:$PATH"
  if codex-worktree feature-missing-helper >"$test_dir/missing-helper.log" 2>&1; then
    fail 'launcher succeeded without its sibling helper'
  fi
  assert_eq "$PWD" "$original_dir" 'missing helper preserves caller directory'
)
[ ! -e "$repo_a/.codex/worktrees/feature-missing-helper" ] || fail 'missing helper created worktree'
assert_eq "$(git -C "$repo_a" branch --list codex/feature-missing-helper)" '' 'missing helper created no branch'
assert_eq "$(git -C "$repo_a" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)" "$before_remote_ref" 'missing helper did not fetch'

ln -s "$launcher" "$test_dir/linkbin/launcher-absolute"
ln -s launcher-absolute "$test_dir/linkbin/launcher-relative"
for launch_case in bash zsh bash-absolute zsh-relative; do
  case $launch_case in
    bash) shell_name=bash; driver_extension='sh'; test_launcher=$launcher ;;
    zsh) shell_name=zsh; driver_extension=zsh; test_launcher=$launcher ;;
    bash-absolute) shell_name=bash; driver_extension='sh'; test_launcher=$test_dir/linkbin/launcher-absolute ;;
    zsh-relative) shell_name=zsh; driver_extension=zsh; test_launcher=$test_dir/linkbin/launcher-relative ;;
  esac
  result_prefix=$test_dir/launch-$launch_case
  test_name=feature-$launch_case
  tmux -S "$socket_a" set-environment -t test TEST_BIN "$test_dir/bin"
  tmux -S "$socket_a" set-environment -t test TEST_LAUNCHER "$test_launcher"
  tmux -S "$socket_a" set-environment -t test TEST_NAME "$test_name"
  tmux -S "$socket_a" set-environment -t test TEST_CHILD_LOG "$result_prefix.child"
  tmux -S "$socket_a" set-environment -t test TEST_PARENT_LOG "$result_prefix.parent"
  tmux -S "$socket_a" set-environment -t test TEST_STATUS "$result_prefix.status"
  tmux -S "$socket_a" set-environment -t test TEST_LOG "$result_prefix.log"
  tmux -S "$socket_a" new-window -d -t test -n "$test_name" -c "$repo_a" "$shell_name '$test_dir/launcher-driver.$driver_extension'"
  wait_for_file "$result_prefix.status"
  assert_eq "$(cat "$result_prefix.status")" 0 "$launch_case launcher succeeds"
  launch_pane=$(pane "$socket_a" "test:$test_name")
  assert_eq "$(sed -n '1p' "$result_prefix.child")" "$socket_a" "$launch_case child socket"
  assert_eq "$(sed -n '2p' "$result_prefix.child")" "$launch_pane" "$launch_case child pane"
  assert_eq "$(sed -n '3p' "$result_prefix.child")" "$repo_a/.codex/worktrees/$test_name" "$launch_case child worktree"
  assert_eq "$(sed -n '1p' "$result_prefix.parent")" stale-socket "$launch_case parent binding untouched"
done

# Without a trustworthy terminal, the launcher still starts Codex but strips
# inherited dedicated bindings from the child process.
background_prefix=$test_dir/launch-background
(
  cd -- "$repo_a"
  export PATH="$test_dir/bin:$PATH" FAKE_CODEX_LOG="$background_prefix.child"
  export TMUX="$socket_a,1,0" TMUX_PANE=$pane_a
  export AGENT_TMUX_SOCKET=stale-socket AGENT_TMUX_PANE=%999 AGENT_TMUX_WORKTREE=stale-worktree
  # shellcheck disable=SC1090,SC1091
  source "$launcher"
  codex-worktree feature-background >"$background_prefix.log" 2>&1
)
assert_eq "$(sed -n '1p' "$background_prefix.child")" '' 'background child socket cleared'
assert_eq "$(sed -n '2p' "$background_prefix.child")" '' 'background child pane cleared'
assert_eq "$(sed -n '3p' "$background_prefix.child")" '' 'background child worktree cleared'

printf 'tmux target regression tests passed\n'
