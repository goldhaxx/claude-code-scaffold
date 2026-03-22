<!-- Active checkpoint — overwritten each session. See docs/templates/checkpoint.md for format guide. -->

# Checkpoint

> Last updated: 2026-03-22
> Session objective: Complete 5 checkpoint next-steps + plan deterministic manifest verification

## Accomplished

- **Fucina cleanup** — deleted stale `.claude/scaffold-sync.log`, added `.claude/lint.json` with cppcheck linter + clang-format formatter for C++/Arduino stack
- **LICENSE selection in /init** — new `scripts/fetch-license.sh` fetches licenses from GitHub API (deterministic, avoids content filtering issues with license text). `/init` now asks for license choice (MIT, Apache 2.0, GPL-3.0, BSD, Unlicense, none) and runs the script
- **Format-on-write tests** — 9 new tests in `tests/format-hook.bats` (config-driven, graceful skip, exit 0 always, pipe-separated globs, empty config, missing command)
- **GitHub Actions CI template** — `docs/templates/github/workflows/ci.yml` runs bats tests + security audit. `/init` copies it to `.github/workflows/ci.yml`
- **README manifest completed** — added 3 missing rules (deterministic-first, tls-troubleshooting, self-review), new scripts section (scaffold-sync, security-audit, fix-cloudflare-certs, fetch-license), updated github templates description
- **Deterministic manifest verification plan** — wrote `docs/plan.md` for `manifest-check.sh` + `.claude/manifest.lock` system

## Current State

- **Branch:** main (hub committed, not pushed; fucina committed, not pushed)
- **Tests:** 77/77 passing (41 scaffold-sync + 15 security-audit + 12 lint-hook + 9 format-hook)
- **Uncommitted changes:** This checkpoint + docs/plan.md
- **Build status:** Clean

## Blocked On

- Nothing

## Next Steps

### 1. Implement deterministic manifest verification
- Follow `docs/plan.md` — 7 steps, TDD
- `scripts/manifest-check.sh` + `.claude/manifest.lock` + tests
- Key insight: hash comparison auto-verifies unchanged files; diffs constrain stale review; identity extraction structures new entry discovery

### 2. Sync fucina with new scaffold changes
- Fucina needs: fetch-license.sh, CI template, format-hook, updated /init
- Run `/scaffold-pull` from fucina after manifest-check is complete

### 3. Push both repos to GitHub
- Hub and fucina both have unpushed commits

## Determinism Notes

- **LICENSE fetching is now fully deterministic**: `scripts/fetch-license.sh` uses GitHub API via `gh` CLI. Claude never reads or writes license text. This pattern (script for content that triggers content filtering) is reusable for other legal/compliance text.
- **Manifest verification identified as stochastic**: The full verification process (parse tables, check existence, judge descriptions, find missing files) was done by a Claude agent. The plan in `docs/plan.md` decomposes this into deterministic (parse, hash, diff, discover) and stochastic (judge diff impact, write descriptions) components.
- **No other stochastic interventions**: All file creation, test writing, and README editing followed established patterns.

## Context Notes

- `fetch-license.sh` requires `gh` CLI (GitHub CLI) authenticated. Falls back with clear error if not available.
- The manifest-check plan stores git commit SHA at verification time to enable `git diff <commit> -- <path>` for stale entries. Rebases or shallow clones need a fallback.
- Fucina's lint.json uses `cppcheck` (not `platformio check`) because the lint hook appends file paths and PlatformIO's `--src-filter` flag expects a different argument format.
