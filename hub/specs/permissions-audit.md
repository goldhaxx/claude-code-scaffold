# Feature: Permissions Security Audit

> Feature: permissions-audit
> Created: 1774218765
> Status: Complete

## Summary

Add a deterministic script (`scripts/permissions-audit.sh`) and a tracked decision log (`.claude/permissions-log.json`) that audit every Bash permission entry in `.claude/settings.json` and `.claude/settings.local.json`. Every grant gets a documented rationale, risk level, and efficiency tradeoff. Dangerous or unreviewed entries are surfaced immediately rather than accumulating silently.

**Prior art (this session):** We established a permission philosophy — read-only commands (git status, git log, docs-check.sh) should auto-allow; mutating commands (cp, git push, rm) require approval. We removed 7 dangerous entries from `settings.json` (cat, find, env, echo, sort, git branch, git tag) and identified that compound commands (`cmd1; cmd2`) bypass allow-list matching. `settings.local.json` currently has 37 unreviewed entries including `Bash(find:*)`, `Bash(echo:*)`, loop primitives, and a `FILTER_BRANCH_SQUELCH_WARNING` compound command — all dangerous and unreviewed.

## Job To Be Done

**When** a Bash permission is added to either settings file (manually or via Claude Code's approval prompt),
**I want to** know immediately if it matches a known-dangerous pattern and require a documented rationale, risk level, and efficiency justification before it is considered reviewed,
**So that** every permission has an explicit tradeoff decision on record and dangerous grants cannot accumulate unnoticed.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `permissions-audit.sh check` parses all `allow` and `deny` entries from both `.claude/settings.json` and `.claude/settings.local.json`, outputs JSON: `{"entries": [{permission, source, status}], "danger": N, "unreviewed": N, "reviewed": N}`.

- [ ] **AC-2:** Exit codes: `0` = all REVIEWED and no DANGER; `1` = UNREVIEWED entries exist (no DANGER); `2` = DANGER entries exist (takes precedence).

- [ ] **AC-3:** `check` flags entries matching hardcoded dangerous patterns as `DANGER` regardless of log status. Patterns: broad command wildcards (`echo:*`, `cat:*`, `find:*`, `bash:*`), arbitrary execution (`env `, `xargs -I`, `find -exec`, `find -delete`), shell loop primitives (`for `, `do `, `done`), file mutation (`sort -o`, `git branch -D`, `git tag -d`), redirect operators (`>`, `>>`), compound operators (`;`, `&&`, `||`), and env-prefix commands (`VAR=value cmd`).

- [ ] **AC-4:** Entries absent from `.claude/permissions-log.json` are `UNREVIEWED`. Entries present with all required fields non-empty and non-`"TODO"` are `REVIEWED`.

- [ ] **AC-5:** `check --text` outputs grouped human-readable report: DANGER first (naming matched pattern), then UNREVIEWED, then REVIEWED (with risk and rationale). REVIEWED suppressed unless `--verbose`.

- [ ] **AC-6:** `.claude/permissions-log.json` schema: `{"entries": {"<permission>": {"risk": "CRITICAL|HIGH|MEDIUM|LOW", "rationale": "...", "efficiency_justification": "...", "reviewer": "...", "reviewed_epoch": N}}}`.

- [ ] **AC-7:** `permissions-audit.sh init` creates the log with all unreviewed entries as stubs (`risk: "", rationale: "TODO", ...`). Preserves existing reviewed entries. Idempotent.

- [ ] **AC-8 (error):** Missing log file → treat all as UNREVIEWED, exit `1`, stderr: `NOTE: permissions-log.json not found — run permissions-audit.sh init`.

- [ ] **AC-9 (error):** Invalid JSON log → stderr: `ERROR: permissions-log.json is not valid JSON`, exit `2`.

- [ ] **AC-10 (edge):** Same permission in both files → report once with `"source": ["settings.json", "settings.local.json"]`, count as one entry.

- [ ] **AC-11:** `/scaffold-audit` includes a "Permissions" section when `permissions-audit.sh check` exits non-zero, showing danger/unreviewed counts and all DANGER permission strings.

## Affected Files

| File | Change |
|------|--------|
| `scripts/permissions-audit.sh` | New — deterministic audit script |
| `.claude/permissions-log.json` | New — tracked decision log (committed) |
| `.claude/commands/scaffold-audit.md` | Modified — add permissions check step |
| `tests/permissions-audit.bats` | New — tests for the audit script |

## Dependencies

- **Requires:** `jq` (already used by ccanvil-sync.sh)
- **Blocked by:** Nothing

## Out of Scope

- Auto-remediation (removing or rewriting permission entries)
- Auditing non-Bash permission types (`Read(...)`, `Write(...)`)
- Per-project overrides to the dangerous-pattern list
- Cleaning up `settings.local.json` (separate manual task using audit output)

## Implementation Notes

- **Script pattern:** Follow `scripts/security-audit.sh` structure — `set -euo pipefail`, pattern arrays, finding helpers, exit code logic.
- **Pattern extraction:** Strip `Bash(` prefix and trailing `)` with sed, test against regex array.
- **Log keys:** Exact permission strings, no normalization. `"Bash(find:*)"` in settings must match `"Bash(find:*)"` in log.
- **Test strategy:** Own test file `tests/permissions-audit.bats` — fixture settings/log files in `mktemp -d`, assert exit codes and JSON output with jq.
- **Compound command detection (AC-3):** The `;`, `&&`, `||` patterns catch entries like the `FILTER_BRANCH` command and the `bash -n ... && echo` entries in `settings.local.json`. These bypass allow-list matching and should always be flagged.
- **Behavioral rule (from this session):** Claude should never chain Bash commands with `;`/`&&` — use parallel tool calls instead. This is documented in feedback memory and prevents new compound entries from being created.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
