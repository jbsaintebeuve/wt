#!/usr/bin/env bash
# Replays the README demo against the real wt in a throwaway repository and
# prints the transcript, with the sandbox path shown as ~. The text in
# build.mjs must match this output.
set -euo pipefail

PATH="$(cd "$(dirname "$0")/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com

HOME_DIR=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$HOME_DIR"' EXIT
mkdir -p "$HOME_DIR/code"
git init -q --bare -b main "$HOME_DIR/origin.git"
git clone -q "$HOME_DIR/origin.git" "$HOME_DIR/code/app" 2>/dev/null
cd "$HOME_DIR/code/app"
git commit -q --allow-empty -m init
git push -q origin main main:develop
printf '[wt]\n\tbase = develop\n\texclude = docs/**\n' > .wt.conf
echo .wt.conf >> .git/info/exclude
wt go feature/login >/dev/null 2>&1

# A teammate pushes to develop, so finish has something to rebase onto.
git clone -q -b develop "$HOME_DIR/origin.git" "$HOME_DIR/other" 2>/dev/null
(cd "$HOME_DIR/other" && git commit -q --allow-empty -m teammate && git push -q)

run() {
  printf '%s $ %s\n' "$(pwd | sed "s|^$HOME_DIR|~|")" "$*"
  "$@" 2>&1 | sed "s|$HOME_DIR|~|g" || true
}

run git checkout feature/login
cd "$(wt go feature/login 2>/dev/null)"
run wt ls
mkdir docs && echo notes > docs/notes.md && echo code > login.ts
run git add -A
run wt finish
run git restore --staged docs
run git commit -qm "Add login"
run wt finish
