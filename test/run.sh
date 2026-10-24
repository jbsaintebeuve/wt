#!/usr/bin/env bash
# Integration tests: each test builds a throwaway origin + clone and drives wt.
set -uo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)/wt"
PASS=0
FAIL=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

fail() { printf '       %s\n' "$*"; return 1; }

assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() {
  case $1 in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac
}

# Fresh sandbox: $SANDBOX/origin.git (bare, branches main + develop) and
# $SANDBOX/repo (clone on main). Leaves the shell in $SANDBOX/repo.
setup() {
  SANDBOX=$(cd "$(mktemp -d)" && pwd -P)
  git init -q --bare -b main "$SANDBOX/origin.git"
  git clone -q "$SANDBOX/origin.git" "$SANDBOX/repo" 2>/dev/null
  cd "$SANDBOX/repo" || exit 1
  echo hello > README
  git add README && git commit -qm init
  git push -q origin main
  git push -q origin main:develop
  git fetch -q origin
}

# Pushes one commit to origin/develop from a separate clone.
advance_develop() {
  local tmp="$SANDBOX/other"
  [ -d "$tmp" ] || git clone -q -b develop "$SANDBOX/origin.git" "$tmp" 2>/dev/null
  (cd "$tmp" && git pull -q && echo "$1" > "$1" && git add "$1" && git commit -qm "$1" && git push -q)
}

# --- go / path / ls / rm -------------------------------------------------------

test_go_creates_new_branch_from_origin_develop() {
  local path
  path=$("$WT" go feature/login 2>/dev/null) || fail "wt go failed"
  assert_eq "$path" "$SANDBOX/repo.worktrees/feature/login" || return 1
  assert_eq "$(git -C "$path" branch --show-current)" "feature/login" || return 1
  assert_eq "$(git -C "$path" rev-parse HEAD)" "$(git rev-parse origin/develop)"
}

test_go_is_idempotent() {
  local first second
  first=$("$WT" go feat 2>/dev/null)
  second=$("$WT" go feat 2>/dev/null)
  assert_eq "$second" "$first" || return 1
  assert_eq "$(git worktree list | wc -l | tr -d ' ')" "2"
}

test_go_returns_worktree_holding_branch_already_checked_out() {
  # main is checked out in the main worktree: plain git would refuse.
  local path
  path=$("$WT" go main 2>/dev/null) || fail "wt go main failed"
  assert_eq "$path" "$SANDBOX/repo"
}

test_go_from_inside_another_worktree() {
  local a b
  a=$("$WT" go a 2>/dev/null)
  b=$(cd "$a" && "$WT" go b 2>/dev/null) || fail "go from worktree failed"
  assert_eq "$b" "$SANDBOX/repo.worktrees/b" || return 1
  assert_eq "$(cd "$b" && "$WT" go a 2>/dev/null)" "$a"
}

test_go_checks_out_existing_local_branch() {
  git branch topic
  local path
  path=$("$WT" go topic 2>/dev/null)
  assert_eq "$(git -C "$path" rev-parse HEAD)" "$(git rev-parse topic)"
}

test_go_tracks_remote_only_branch() {
  git push -q origin main:remote-only
  local path
  path=$("$WT" go remote-only 2>/dev/null) || fail "go failed"
  assert_eq "$(git -C "$path" rev-parse --abbrev-ref '@{upstream}')" "origin/remote-only"
}

test_go_from_explicit_ref() {
  git commit -q --allow-empty -m local-only
  local path
  path=$("$WT" go spike --from main 2>/dev/null)
  assert_eq "$(git -C "$path" rev-parse HEAD)" "$(git rev-parse main)"
}

test_go_honours_dir_config() {
  printf '[wt]\n\tdir = trees\n' > .wt.conf
  assert_eq "$("$WT" go x 2>/dev/null)" "$SANDBOX/repo/trees/x"
}

test_go_rejects_invalid_branch() {
  local out
  out=$("$WT" go 'bad..name' 2>&1) && fail "expected failure"
  assert_contains "$out" "invalid branch name"
}

test_path_and_ls() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  assert_eq "$("$WT" path feat)" "$path" || return 1
  echo dirty > "$path/README"
  out=$("$WT" ls)
  assert_contains "$out" "*  main" || return 1
  assert_contains "$out" " ! feat" || return 1
  "$WT" path nope 2>/dev/null && fail "path for unknown branch should fail"
  return 0
}

test_rm_removes_clean_worktree_and_branch() {
  local path
  path=$("$WT" go feat 2>/dev/null)
  "$WT" rm feat --delete-branch 2>/dev/null || fail "rm failed"
  [ ! -d "$path" ] || fail "directory still exists"
  git show-ref --verify --quiet refs/heads/feat && fail "branch still exists"
  return 0
}

test_rm_refuses_dirty_unless_forced() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  echo change > "$path/README"
  out=$("$WT" rm feat 2>&1) && fail "rm should refuse a dirty worktree"
  assert_contains "$out" "uncommitted changes" || return 1
  "$WT" rm feat --force 2>/dev/null || fail "forced rm failed"
  [ ! -d "$path" ] || fail "directory still exists"
}

test_rm_refuses_main_worktree_and_current_dir() {
  local path out
  out=$("$WT" rm main 2>&1) && fail "rm main should fail"
  assert_contains "$out" "main worktree" || return 1
  path=$("$WT" go feat 2>/dev/null)
  out=$(cd "$path" && "$WT" rm feat 2>&1) && fail "rm of current worktree should fail"
  assert_contains "$out" "you are inside"
}

test_go_recovers_after_worktree_dir_deleted() {
  local path
  path=$("$WT" go feat 2>/dev/null)
  rm -rf "$path"
  assert_eq "$("$WT" go feat 2>/dev/null)" "$path" || return 1
  [ -d "$path" ] || fail "worktree not recreated"
}

test_go_branches_differing_only_by_slash() {
  local a b
  a=$("$WT" go feature/login 2>/dev/null) || fail "first go failed"
  b=$("$WT" go feature-login 2>/dev/null) || fail "second go failed"
  [ "$a" != "$b" ] || fail "both branches share $a"
}

test_go_and_ls_with_non_ascii_path() {
  printf '[wt]\n\tdir = ../Développement\n' > .wt.conf
  local path
  path=$("$WT" go feat 2>/dev/null) || fail "go failed"
  assert_eq "$path" "$SANDBOX/Développement/feat" || return 1
  assert_eq "$("$WT" go feat 2>/dev/null)" "$path" || return 1
  assert_contains "$("$WT" ls)" "$SANDBOX/Développement/feat"
}

test_main_checkout_with_separate_git_dir() {
  git init -q -b main --separate-git-dir "$SANDBOX/gitdir" "$SANDBOX/sep"
  cd "$SANDBOX/sep" || return 1
  git commit -q --allow-empty -m init
  assert_eq "$("$WT" go feat --from main 2>/dev/null)" "$SANDBOX/sep.worktrees/feat"
}

test_rejects_option_like_remote() {
  printf '[wt]\n\tremote = --upload-pack=touch pwned\n' > .wt.conf
  local out
  out=$("$WT" go feat 2>&1) && fail "go should refuse"
  assert_contains "$out" "invalid wt.remote" || return 1
  [ ! -e pwned ] || fail "option was executed"
}

test_rejects_malformed_conf() {
  printf '[wt\n\texclude = docs/**\n' > .wt.conf
  local out
  out=$("$WT" finish 2>&1) && fail "finish should refuse"
  assert_contains "$out" "cannot parse"
}

# --- finish ------------------------------------------------------------------

test_finish_rebases_onto_origin_develop() {
  local path
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo work > work && git add work && git commit -qm work
  advance_develop upstream-change
  "$WT" finish 2>/dev/null || fail "finish failed"
  git merge-base --is-ancestor origin/develop HEAD || fail "not rebased onto origin/develop"
  assert_eq "$(git log --format=%s -1)" "work"
}

test_finish_refuses_staged_excluded_paths() {
  printf '[wt]\n\texclude = docs/**\n\texclude = **/mocks/**\n' > .wt.conf
  git add .wt.conf && git commit -qm conf && git push -q origin HEAD:develop
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  mkdir -p docs src/api/mocks
  echo d > docs/guide.md; echo m > src/api/mocks/user.json; echo c > src/code.js
  git add docs src
  out=$("$WT" finish --no-fetch 2>&1) && fail "finish should refuse"
  assert_contains "$out" "docs/guide.md" || return 1
  assert_contains "$out" "src/api/mocks/user.json" || return 1
  case $out in *src/code.js*) fail "non-excluded file listed" ;; esac
}

test_finish_reads_uncommitted_conf_from_main_checkout() {
  printf '[wt]\n\texclude = docs/**\n' > .wt.conf
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  mkdir docs && echo d > docs/a.md && git add docs
  out=$("$WT" finish --no-fetch 2>&1) && fail "finish should refuse"
  assert_contains "$out" "docs/a.md"
}

test_finish_refuses_committed_excluded_paths() {
  git config wt.exclude 'docs/**'
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  mkdir docs && echo d > docs/a.md && git add docs && git commit -qm docs
  out=$("$WT" finish 2>&1) && fail "finish should refuse"
  assert_contains "$out" "commits on feat change excluded paths" || return 1
  assert_contains "$out" "docs/a.md"
}

test_finish_checks_excludes_from_subdirectory() {
  git config wt.exclude 'docs/**'
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  mkdir -p docs src && echo d > docs/a.md && echo c > src/c.js && git add docs src
  out=$(cd src && "$WT" finish --no-fetch 2>&1) && fail "staged check bypassed from subdirectory"
  assert_contains "$out" "docs/a.md" || return 1
  git commit -qm both
  out=$(cd src && "$WT" finish 2>&1) && fail "commit check bypassed from subdirectory"
  assert_contains "$out" "docs/a.md"
}

test_finish_refuses_excluded_path_added_then_removed() {
  git config wt.exclude 'docs/**'
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  mkdir docs && echo secret > docs/a.md && git add docs && git commit -qm add
  git rm -q docs/a.md && git commit -qm remove
  out=$("$WT" finish 2>&1) && fail "finish should refuse"
  assert_contains "$out" "docs/a.md"
}

test_finish_refuses_excluded_path_hidden_behind_merge() {
  git config wt.exclude 'docs/**'
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  git checkout -q -b side
  mkdir docs && echo secret > docs/a.md && git add docs && git commit -qm side
  git checkout -q feat && git merge -q -s ours side -m merge
  out=$("$WT" finish 2>&1) && fail "finish should refuse"
  assert_contains "$out" "docs/a.md"
}

test_finish_push_refuses_to_drop_remote_merge() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  "$WT" finish --push 2>/dev/null || fail "first push failed"
  git clone -q -b feat "$SANDBOX/origin.git" "$SANDBOX/teammate" 2>/dev/null
  # The side commit duplicates our own patch; only the merge resolution is new.
  (cd "$SANDBOX/teammate" && git checkout -q -b side HEAD~1 && git cherry-pick -x feat >/dev/null \
    && git checkout -q feat && git merge -q --no-ff --no-commit -s ours side \
    && echo resolved > w && git add w && git commit -qm merge && git push -q)
  advance_develop upstream-change
  "$WT" finish 2>/dev/null || fail "local finish failed"
  out=$("$WT" finish --push 2>&1) && fail "push should refuse"
  assert_contains "$out" "has commits that feat lacks"
}

test_finish_push_refuses_to_drop_remote_commits() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  "$WT" finish --push 2>/dev/null || fail "first push failed"
  git clone -q -b feat "$SANDBOX/origin.git" "$SANDBOX/teammate" 2>/dev/null
  (cd "$SANDBOX/teammate" && echo t > t && git add t && git commit -qm teammate && git push -q)
  out=$("$WT" finish --push 2>&1) && fail "push should refuse"
  assert_contains "$out" "has commits that feat lacks" || return 1
  assert_eq "$(git -C "$SANDBOX/teammate" rev-parse HEAD)" "$(git --git-dir="$SANDBOX/origin.git" rev-parse feat)"
}

test_finish_push_after_earlier_unpushed_finish() {
  local path
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  "$WT" finish --push 2>/dev/null || fail "first push failed"
  advance_develop upstream-change
  "$WT" finish 2>/dev/null || fail "finish failed"
  "$WT" finish --push 2>/dev/null || fail "rebased push refused"
  assert_eq "$(git rev-parse origin/feat)" "$(git rev-parse HEAD)"
}

test_finish_stops_when_autostash_conflicts() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  echo local-edit > README
  (cd "$SANDBOX" && git clone -q -b develop origin.git other2 2>/dev/null && cd other2 && echo upstream > README && git commit -qam up && git push -q)
  out=$("$WT" finish --push 2>&1) && fail "finish should fail"
  assert_contains "$out" "uncommitted changes conflict" || return 1
  git rev-parse -q --verify origin/feat >/dev/null && fail "pushed despite conflict"
  return 0
}

test_finish_keeps_unstaged_excluded_changes() {
  git config wt.exclude 'docs/**'
  mkdir docs && echo v1 > docs/a.md && git add docs && git commit -qm docs && git push -q origin HEAD:develop
  local path
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo local-notes > docs/a.md
  echo work > work && git add work && git commit -qm work
  advance_develop upstream-change
  "$WT" finish 2>/dev/null || fail "finish failed"
  assert_eq "$(cat docs/a.md)" "local-notes" || return 1
  git merge-base --is-ancestor origin/develop HEAD || fail "not rebased"
}

test_finish_uses_configured_base() {
  printf '[wt]\n\tbase = main\n' > .wt.conf
  local path
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  "$WT" finish 2>/dev/null || fail "finish failed"
  git merge-base --is-ancestor origin/main HEAD || fail "not on origin/main"
  local out
  out=$("$WT" finish --base nope 2>&1) && fail "unknown base should fail"
  assert_contains "$out" "origin/nope not found"
}

test_finish_push() {
  local path
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo w > w && git add w && git commit -qm w
  "$WT" finish --push 2>/dev/null || fail "finish --push failed"
  assert_eq "$(git rev-parse origin/feat)" "$(git rev-parse HEAD)"
}

test_finish_reports_conflict() {
  local path out
  path=$("$WT" go feat 2>/dev/null)
  cd "$path" || return 1
  echo mine > clash && git add clash && git commit -qm mine
  advance_develop clash
  out=$("$WT" finish 2>&1) && fail "finish should stop on conflict"
  assert_contains "$out" "rebase stopped on a conflict"
}

test_finish_refuses_on_base_branch() {
  git checkout -q -b develop origin/develop
  local out
  out=$("$WT" finish 2>&1) && fail "finish on base should fail"
  assert_contains "$out" "on the base branch"
}

# --- misc ----------------------------------------------------------------------

test_config_shows_effective_values() {
  printf '[wt]\n\tbase = main\n\texclude = docs/**\n' > .wt.conf
  git config wt.exclude '**/mocks/**'
  local out
  out=$("$WT" config)
  assert_contains "$out" "base     main" || return 1
  assert_contains "$out" "exclude  docs/**" || return 1
  assert_contains "$out" "exclude  **/mocks/**"
}

test_shell_init_cds_into_worktree() {
  local out
  out=$(PATH="$(dirname "$WT"):$PATH" bash -c 'eval "$(wt shell-init)"; wt go feat 2>/dev/null; pwd -P')
  assert_eq "$out" "$SANDBOX/repo.worktrees/feat"
}

test_shell_init_under_nounset_without_args() {
  local out
  out=$(PATH="$(dirname "$WT"):$PATH" bash -uc 'eval "$(wt shell-init)"; wt' 2>&1) || fail "bare wt failed: $out"
  assert_contains "$out" "Usage:"
}

test_outside_repo_fails_cleanly() {
  local out
  out=$(cd "$SANDBOX" && "$WT" ls 2>&1) && fail "should fail outside a repo"
  assert_contains "$out" "not inside a git repository"
}

# --- runner --------------------------------------------------------------------

tests=$(declare -F | awk '{print $3}' | grep '^test_' | grep -e "${1:-.}")
for t in $tests; do
  if ( setup >/dev/null && trap 'rm -rf "$SANDBOX"' EXIT && "$t" ); then
    printf '  ok   %s\n' "$t"
    PASS=$((PASS + 1))
  else
    printf '  FAIL %s\n' "$t"
    FAIL=$((FAIL + 1))
  fi
done
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
