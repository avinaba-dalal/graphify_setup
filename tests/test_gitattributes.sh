#!/usr/bin/env bash
# Tests install.sh's localize_gitattributes in throwaway git repos.
# Silent with exit 0 on success; prints the failed assertion and exits 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
LINE="graphify-out/graph.json merge=graphify"
fail() { echo "FAIL: $*" >&2; exit 1; }
# Loads only the function under test from install.sh.
eval "$(sed -n '/^localize_gitattributes() {/,/^}/p' "$ROOT/install.sh")"
newrepo() { rm -rf "$T/r"; mkdir "$T/r"; cd "$T/r"; git init -q .; git config user.email t@t; git config user.name t; }

# Case 1: .gitattributes created solely by graphify -> removed, line moved to info/attributes.
newrepo; echo "$LINE" > .gitattributes
localize_gitattributes
[ ! -e .gitattributes ] || fail "generated .gitattributes not removed"
grep -qxF "$LINE" .git/info/attributes || fail "attribute not moved to info/attributes"
[ -z "$(git status --porcelain)" ] || fail "tree not clean (case 1)"

# Case 2: tracked .gitattributes modified by graphify -> restored to original content.
newrepo; echo "*.png binary" > .gitattributes; git add .gitattributes; git commit -q -m a
echo "$LINE" >> .gitattributes
localize_gitattributes
[ -z "$(git status --porcelain)" ] || fail "tree not clean (case 2)"
grep -qxF "$LINE" .git/info/attributes || fail "attribute not moved (case 2)"

# Case 3: idempotent / no-op when there is no .gitattributes.
newrepo; localize_gitattributes; [ ! -e .git/info/attributes ] || fail "created attributes without need"
