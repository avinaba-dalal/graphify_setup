#!/usr/bin/env bash
# Installs and sets up graphify in the codebase rooted at the current directory.
# Run from the codebase root. See README.md for details.
set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

PKG="graphifyy"
IS_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1

# Records the git status before we touch anything so step 7 can detect changes we caused.
BASELINE_STATUS=""
if [ "$IS_GIT" = 1 ]; then
  BASELINE_STATUS="$(git status --porcelain)"
  [ -z "$BASELINE_STATUS" ] || warn "git working tree is not clean; the graph will include uncommitted changes (consider running on an updated, clean main)"
fi

# Step 1: install graphify if missing (prefers uv, then pipx, then pip --user).
install_graphify() {
  if command -v graphify >/dev/null 2>&1; then
    log "graphify already installed ($(command -v graphify))"
    return
  fi
  log "Installing graphify"
  if command -v uv >/dev/null 2>&1; then uv tool install "$PKG"
  elif command -v pipx >/dev/null 2>&1; then pipx install "$PKG"
  elif command -v pip3 >/dev/null 2>&1; then pip3 install --user "$PKG"
  else die "need one of uv, pipx or pip3 to install graphify (Python 3.11.5+ required)"; fi
  export PATH="$HOME/.local/bin:$PATH"
  command -v graphify >/dev/null 2>&1 || die "graphify installed but not on PATH; add ~/.local/bin to PATH and re-run"
}

# Step 3: adds a pattern to .git/info/exclude (idempotent). Never touches tracked/ignored files.
exclude_locally() {
  [ "$IS_GIT" = 1 ] || return 0
  local file; file="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$file")"; touch "$file"
  grep -qxF "$1" "$file" || echo "$1" >> "$file"
}

# Guesses the platform from marker files (searched up to 3 levels deep, skipping build dirs).
# Prints android, ios or general (when neither or both are found).
detect_platform() {
  local found
  found() { find . -maxdepth 3 \( -name build -o -name Pods -o -name node_modules -o -name .git \) -prune -o \( "$@" \) -print -quit | grep -q .; }
  local a=0 i=0
  found -name AndroidManifest.xml -o -name 'build.gradle*' -o -name 'settings.gradle*' && a=1
  found -name '*.xcodeproj' -o -name '*.xcworkspace' -o -name Podfile -o -name Package.swift && i=1
  if [ "$a" = 1 ] && [ "$i" = 0 ]; then echo android
  elif [ "$i" = 1 ] && [ "$a" = 0 ]; then echo ios
  else echo general; fi
}

# Step 4: asks the platform question, defaulting to the detected platform. Reads from the terminal
# (stdin may be the script itself under `curl | bash`); without one, uses the detected platform.
# Prints one of: general, android, ios.
ask_platform() {
  local detected ans="" def=1
  detected="$(detect_platform)"
  case "$detected" in android) def=2;; ios) def=3;; esac
  if [ -r /dev/tty ]; then
    {
      echo "Tailor .graphifyignore to a platform? (detected: $detected)"
      echo "  1) General (no .graphifyignore)"
      echo "  2) Android"
      echo "  3) iOS"
      printf "Choice [%s]: " "$def"
    } > /dev/tty
    read -r ans < /dev/tty || ans=""
  fi
  case "${ans:-$def}" in 2|android|Android) echo android;; 3|ios|iOS) echo ios;; *) echo general;; esac
}

# Writes the platform-specific .graphifyignore (refuses to overwrite an existing one).
write_graphifyignore() {
  [ -e .graphifyignore ] && { warn ".graphifyignore exists, leaving it untouched"; return; }
  case "$1" in
    android) cat > .graphifyignore <<'IGN'
build/
.gradle/
.idea/
*.iml
local.properties
captures/
.cxx/
*.apk
*.aab
*.jar
*.so
res/drawable*/
res/mipmap*/
IGN
    ;;
    ios) cat > .graphifyignore <<'IGN'
build/
DerivedData/
Pods/
Carthage/
.build/
*.xcodeproj/
*.xcworkspace/
*.xcassets/
*.framework/
*.xcarchive/
*.ipa
*.a
IGN
    ;;
  esac
  exclude_locally ".graphifyignore"
  log "Wrote .graphifyignore for $1 (excluded from git)"
}

# Step 7: checks git cleanliness, hooks and generated files. Returns non-zero on any failure.
verify() {
  local ok=0
  grep -qi graphify "$HOME/.claude/CLAUDE.md" 2>/dev/null || { warn "graphify not registered in ~/.claude/CLAUDE.md"; ok=1; }
  [ -f graphify-out/graph.json ] || { warn "graphify-out/graph.json missing"; ok=1; }
  if [ "$IS_GIT" = 1 ]; then
    local hooks; hooks="$(git rev-parse --git-path hooks)"
    graphify hook status >/dev/null 2>&1 || { warn "graphify hook status reports hooks not installed"; ok=1; }
    for h in post-commit post-checkout; do
      grep -qi graphify "$hooks/$h" 2>/dev/null || { warn "graphify hook missing: $hooks/$h"; ok=1; }
    done
    local now; now="$(git status --porcelain)"
    if [ "$now" != "$BASELINE_STATUS" ]; then
      warn "git status changed after setup:"; diff <(echo "$BASELINE_STATUS") <(echo "$now") >&2 || true; ok=1
    elif [ -n "$now" ]; then
      warn "git working tree was already dirty before setup (unchanged by it)"
    fi
    git ls-files --error-unmatch graphify-out >/dev/null 2>&1 && { warn "graphify-out is tracked by git"; ok=1; }
    git check-ignore -q graphify-out || { warn "graphify-out is not ignored"; ok=1; }
  fi
  return $ok
}

install_graphify

log "Registering graphify for Claude"
graphify install

if [ "$IS_GIT" = 1 ]; then
  exclude_locally "graphify-out/"
  log "Excluded graphify-out/ via .git/info/exclude"
else
  warn "not a git repository; skipping git exclude, hook install and git checks"
fi

PLATFORM="$(ask_platform)"
[ "$PLATFORM" = general ] || write_graphifyignore "$PLATFORM"

# Runs graphify with LLM API keys removed so it never auto-selects a hosted backend.
graphify_offline() {
  env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY -u GEMINI_API_KEY -u GOOGLE_API_KEY \
      -u MOONSHOT_API_KEY -u KIMI_API_KEY -u DEEPSEEK_API_KEY graphify "$@"
}

log "Extracting graph (code only, offline)"
graphify_offline extract . --code-only
log "Clustering"
graphify_offline cluster-only .

if [ "$IS_GIT" = 1 ]; then
  log "Installing git hooks"
  graphify hook install
fi

log "Verifying"
if verify; then log "Done. graphify is set up."; else die "verification failed (see warnings above)"; fi
