#!/usr/bin/env bash
# Tests uninstall.sh against a throwaway git repo with a fake `graphify` on PATH.
# Silent with exit 0 on success; prints the failed assertion and exits 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin" "$T/repo"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\n' "$T" > "$T/bin/graphify"; chmod +x "$T/bin/graphify"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Case 1: generated .graphifyignore (excluded) is removed; user-level removal is declined without a tty.
cd "$T/repo"; git init -q .
mkdir graphify-out; : > graphify-out/graph.json; echo "ignore" > .graphifyignore
printf 'keep-me\ngraphify-out/\n.graphifyignore\n' >> .git/info/exclude
PATH="$T/bin:$PATH" bash "$ROOT/uninstall.sh" </dev/null >/dev/null 2>&1 || fail "uninstall exited non-zero"
[ ! -e graphify-out ] || fail "graphify-out not removed"
[ ! -e .graphifyignore ] || fail "generated .graphifyignore not removed"
grep -qxF keep-me .git/info/exclude || fail "unrelated exclude line lost"
! grep -q graphify .git/info/exclude || fail "graphify exclude lines remain"
grep -qx 'hook uninstall' "$T/calls" || fail "hook uninstall not called"
! grep -qx uninstall "$T/calls" || fail "global uninstall ran without confirmation"

# Case 2: a user's own .graphifyignore (not excluded) is kept.
echo "mine" > .graphifyignore
PATH="$T/bin:$PATH" bash "$ROOT/uninstall.sh" </dev/null >/dev/null 2>&1 || fail "second run exited non-zero"
[ -e .graphifyignore ] || fail "user .graphifyignore was deleted"
