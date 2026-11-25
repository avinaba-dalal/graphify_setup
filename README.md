# graphify_setup

One-shot installer that sets up [graphify](https://pypi.org/project/graphifyy/) in a codebase without leaving any graphify files in git.

## Install

Run from the root of the target codebase (nothing is written to disk; the script is streamed into bash). Requires the [GitHub CLI](https://cli.github.com) (`gh`), logged in:

```sh
bash -c "$(gh api repos/avinaba-dalal/graphify_setup/contents/install.sh -H 'Accept: application/vnd.github.raw')"
```

Alternative with `curl` (fails on networks where `raw.githubusercontent.com` is blocked or TLS-intercepted):

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/avinaba-dalal/graphify_setup/main/install.sh)"
```

The `bash -c "$(...)"` form keeps stdin attached to your terminal so the interactive prompt works.

## What it does

1. Installs graphify (`graphifyy` package) if `graphify` isn't on `PATH`, using `uv`, `pipx` or `pip3 --user` (first available). Requires Python 3.11.5+.
2. Registers graphify for Claude via `graphify install`. This is user-level only: it adds the skill and a graphify section to `~/.claude/CLAUDE.md` (telling Claude to query the graph first in any repo with a `graphify-out/`), and does **not** write `CLAUDE.md` or `.claude/` into the repo.
3. If the codebase is a git repo, adds `graphify-out/` to `.git/info/exclude` (local only; `.gitignore` is never modified). Skipped for non-git directories, as are the hook and git checks.
4. Detects the platform from the codebase (Android: `build.gradle*`, `AndroidManifest.xml`; iOS: `*.xcodeproj`, `Podfile`, `Package.swift`) and asks whether to tailor `.graphifyignore` for **Android** or **iOS**, defaulting to the detected platform (*general*, i.e. no `.graphifyignore`, if unknown or ambiguous). An existing `.graphifyignore` is never overwritten; a generated one is also added to `.git/info/exclude`.
5. Runs `graphify extract .` and `graphify cluster-only .`.
6. Installs the git hooks (`graphify hook install`) so the graph rebuilds on commit/checkout.
7. Verifies:
   - `graphify-out/graph.json` exists
   - graphify is registered in `~/.claude/CLAUDE.md`
   - `graphify hook status` passes and the `post-commit`/`post-checkout` hooks contain graphify
   - `graphify-out` is ignored and untracked
   - `git status` is unchanged from before the script ran

The script exits non-zero if verification fails.

## Notes

- Best run on an up-to-date, clean `main` (`git checkout main && git pull`). The script warns if the git working tree isn't clean, since the first graph would include uncommitted changes.

- Review the script before running: `gh api repos/avinaba-dalal/graphify_setup/contents/install.sh -H 'Accept: application/vnd.github.raw' | less`
- To undo: `graphify uninstall --purge`, remove `graphify-out/`, and delete the graphify lines from `.git/info/exclude`.
