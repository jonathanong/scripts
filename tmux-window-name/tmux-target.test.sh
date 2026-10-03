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
assert_eq "$(window_name "$socket_a" "$pane_a")" "$label" 'literal window label'
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
export PATH="$TEST_BIN:$PATH" FAKE_CODEX_LOG=$TEST_CHILD_LOG
export AGENT_TMUX_SOCKET=stale-socket AGENT_TMUX_PANE=%999 AGENT_TMUX_WORKTREE=stale-worktree
source "$TEST_LAUNCHER"
codex-worktree "$TEST_NAME" >"$TEST_LOG" 2>&1
printf '%s\n' "$?" >"$TEST_STATUS"
printf '%s\n' "$AGENT_TMUX_SOCKET" "$AGENT_TMUX_PANE" "$AGENT_TMUX_WORKTREE" >"$TEST_PARENT_LOG"
exec sleep 30
DRIVER

for shell_name in bash zsh; do
  result_prefix=$test_dir/launch-$shell_name
  test_name=feature-$shell_name
  tmux -S "$socket_a" set-environment -t test TEST_BIN "$test_dir/bin"
  tmux -S "$socket_a" set-environment -t test TEST_LAUNCHER "$launcher"
  tmux -S "$socket_a" set-environment -t test TEST_NAME "$test_name"
  tmux -S "$socket_a" set-environment -t test TEST_CHILD_LOG "$result_prefix.child"
  tmux -S "$socket_a" set-environment -t test TEST_PARENT_LOG "$result_prefix.parent"
  tmux -S "$socket_a" set-environment -t test TEST_STATUS "$result_prefix.status"
  tmux -S "$socket_a" set-environment -t test TEST_LOG "$result_prefix.log"
  tmux -S "$socket_a" new-window -d -t test -n "$test_name" -c "$repo_a" "$shell_name '$test_dir/launcher-driver.$([ "$shell_name" = bash ] && printf sh || printf zsh)'"
  wait_for_file "$result_prefix.status"
  assert_eq "$(cat "$result_prefix.status")" 0 "$shell_name launcher succeeds"
  launch_pane=$(pane "$socket_a" "test:$test_name")
  assert_eq "$(sed -n '1p' "$result_prefix.child")" "$socket_a" "$shell_name child socket"
  assert_eq "$(sed -n '2p' "$result_prefix.child")" "$launch_pane" "$shell_name child pane"
  assert_eq "$(sed -n '3p' "$result_prefix.child")" "$repo_a/.codex/worktrees/$test_name" "$shell_name child worktree"
  assert_eq "$(sed -n '1p' "$result_prefix.parent")" stale-socket "$shell_name parent binding untouched"
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
