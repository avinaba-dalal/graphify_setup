#!/usr/bin/env bash
# Removes graphify from the codebase rooted at the current directory (undoes install.sh).
# Repo-level cleanup always runs; user-level removal (skill, ~/.claude/CLAUDE.md section, the tool
# itself) is asked about and defaults to "no". See README.md.
set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

IS_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1
HAS_GRAPHIFY=0
command -v graphify >/dev/null 2>&1 && HAS_GRAPHIFY=1

# Asks a yes/no question ($1) on the terminal; returns 0 only on an explicit yes.
# Without a usable terminal the answer is "no".
confirm() {
  local ans=""
  if (: < /dev/tty) 2>/dev/null; then
    printf '%s [y/N]: ' "$1" > /dev/tty
    read -r ans < /dev/tty || ans=""
  fi
  case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# Removes exact-match line $1 from file $2 (no-op if the file or line is absent).
remove_line() {
  [ -f "$2" ] || return 0
  local tmp; tmp="$(mktemp)"
  grep -vxF "$1" "$2" > "$tmp" || true
  cat "$tmp" > "$2"; rm -f "$tmp"
}

if [ "$IS_GIT" = 1 ]; then
  EXCLUDE="$(git rev-parse --git-path info/exclude)"
  if [ "$HAS_GRAPHIFY" = 1 ]; then
    log "Removing graphify git hooks"
    graphify hook uninstall || warn "graphify hook uninstall failed"
  else
    warn "graphify not on PATH; skipping hook removal (check .git/hooks manually)"
  fi
  # install.sh excludes .graphifyignore only when it created it, so exclusion marks it as ours.
  if [ -f .graphifyignore ] && grep -qxF ".graphifyignore" "$EXCLUDE" 2>/dev/null; then
    rm -f .graphifyignore; log "Removed generated .graphifyignore"
  fi
  remove_line "graphify-out/" "$EXCLUDE"
  remove_line ".graphifyignore" "$EXCLUDE"
  remove_line "graphify-out/graph.json merge=graphify" "$(git rev-parse --git-path info/attributes)"
  log "Cleaned graphify entries from $EXCLUDE"
fi

if [ -d graphify-out ]; then rm -rf graphify-out; log "Removed graphify-out/"; fi

if [ "$HAS_GRAPHIFY" = 1 ] && confirm "Also remove graphify's user-level registration (skill + ~/.claude/CLAUDE.md section)? This affects ALL repos"; then
  graphify uninstall || warn "graphify uninstall failed"
fi

if [ "$HAS_GRAPHIFY" = 1 ] && confirm "Also uninstall the graphify tool itself?"; then
  if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q '^graphifyy'; then uv tool uninstall graphifyy
  elif command -v pipx >/dev/null 2>&1 && pipx list --short 2>/dev/null | grep -q '^graphifyy'; then pipx uninstall graphifyy
  elif command -v pip3 >/dev/null 2>&1; then pip3 uninstall -y graphifyy
  else warn "could not determine how graphify was installed; remove it manually"; fi
fi

log "Done."
