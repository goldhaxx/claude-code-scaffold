# Feature: Stasis & Recall — paired session-boundary commands (full rename)

> Feature: stasis-recall
> Created: 1776794240
> Status: In Progress

## Summary

Rename ccanvil's session-boundary surface to a paired Protoss-Arbiter theme, comprehensively and without compatibility shims:

- `/stasis` replaces the stochastic "checkpoint this" phrase-trigger. End-of-session strategic review that writes a frozen snapshot before `/compact`.
- `/recall` replaces `/catchup`. Start-of-session re-hydration that reads the snapshot.
- `docs/checkpoint.md` → `docs/stasis.md`. The artifact IS the stasis field.
- `.ccanvil/templates/checkpoint.md` → `.ccanvil/templates/stasis.md`.
- Every internal identifier carrying "checkpoint" or "catchup" is renamed to `stasis` or `recall` respectively (full spelling, never abbreviated).

The git checkpoint/rewind collision that prompted this rename is just as present in the filename and internals as in the verb; partial renames produce a two-vocabulary system future readers have to carry. This spec commits to the full rename plus migration logic so downstream projects that have already run `/init` get cleanly updated when they next pull from the hub.

Stasis also expands the current checkpoint's scope: it runs determinism review, security review, cross-session pattern detection, and surfaces insights to roadmap/memory — the strategic microscope/macroscope that pairs with `/compact`.

## Job To Be Done

**When** I'm about to `/compact` at the end of a session,
**I want to** run `/stasis` to freeze a thorough snapshot of session/project state plus derived insights,
**So that** compaction doesn't lose strategic context.

**When** I start a new session or resume after a reset,
**I want to** run `/recall` to re-hydrate everything the last `/stasis` preserved,
**So that** I pick up with full situational awareness.

## Acceptance Criteria

### /stasis command

- [ ] **AC-1:** `/stasis` exists as a slash command at `.claude/skills/stasis/SKILL.md` and is invokable without stochastic intent detection.
- [ ] **AC-2:** Running `/stasis` gathers data deterministically by calling existing scripts: `docs-check.sh status`, `docs-check.sh validate`, `docs-check.sh radar-gather`, `docs-check.sh idea-count`, `docs-check.sh audit-session`, `permissions-audit.sh check`, `context-budget.sh check`, and `git log --oneline -20`.
- [ ] **AC-3:** `/stasis` writes `docs/stasis.md` using the template at `.ccanvil/templates/stasis.md`, extended with three new required subsections beyond the current checkpoint template: **Cross-Session Patterns**, **Security Review**, and **Memory Candidates**.
- [ ] **AC-4:** The rendered artifact contains a populated `## Determinism Review` section (existing requirement from `self-review.md`) — `docs-check.sh validate` reports `aligned` (not `missing-determinism-review`).
- [ ] **AC-5:** The `## Cross-Session Patterns` section surfaces any determinism-review candidates or audit-session findings that also appeared in the previous stasis (read `git show HEAD~1:docs/stasis.md` when available). If none, it states "No recurring patterns."
- [ ] **AC-6:** The `## Security Review` section runs the project's security scan (via `security-audit` skill if present, else a static grep for secret/PII keywords in the session's diff) and reports `PASS` or a bullet list of findings.
- [ ] **AC-7:** The `## Memory Candidates` section lists insights that meet auto-memory criteria (non-obvious feedback, surprising project facts, external references) or states "No candidates this session."
- [ ] **AC-8:** `/stasis` commits `docs/stasis.md` with message `docs: stasis <feature-id>` via `ALLOW_MAIN=1` when on main (pattern from commit `7fe69c4`).
- [ ] **AC-9:** `/stasis` closes with an explicit-next-action directive — one line saying "Run `/compact` to wrap session" on success; on validation failure, surfaces the failure instead.
- [ ] **AC-10:** **Edge: no previous stasis.** When `git show HEAD~1:docs/stasis.md` fails (fresh project or first stasis), AC-5's Cross-Session Patterns section states "First stasis — no prior state to compare" without erroring.
- [ ] **AC-11:** **Error: validate failure.** If `docs-check.sh validate` reports anything other than `aligned` or `missing-determinism-review` (e.g., `stale-plan`, `mismatched`), `/stasis` surfaces the failure and stops before writing.

### /recall command

- [ ] **AC-12:** `/recall` exists at `.claude/skills/recall/SKILL.md` with behavior equivalent to today's `/catchup` (reads stasis, runs validate/recommend, reports state), reading from `docs/stasis.md`.
- [ ] **AC-13:** The legacy `.claude/commands/catchup.md` file is deleted (no compat alias).

### Filename + template rename

- [ ] **AC-14:** `docs/checkpoint.md` no longer exists as a live artifact path in the hub. The template moves to `.ccanvil/templates/stasis.md`; the old `.ccanvil/templates/checkpoint.md` is deleted.
- [ ] **AC-15:** `manifest.lock` path entries for `docs/templates/checkpoint.md` and `docs/checkpoint.md` are updated to their stasis equivalents.
- [ ] **AC-16:** `.claude/ccanvil.local.json` (if it references any of these paths) and `.claudeignore` patterns are updated.

### Internal API rename (full spelling — no `cp_`/`st_` abbreviations)

- [ ] **AC-17:** `operations.sh` operations `checkpoint.read` and `checkpoint.write` are renamed to `stasis.read` and `stasis.write`. No compat aliases — old names removed.
- [ ] **AC-18:** `docs-check.sh` validate state `stale-checkpoint` is renamed to `stale-stasis` in both the return values and the documentation. The `missing-determinism-review` state name is independent of this rename and stays.
- [ ] **AC-19:** All internal variable names in `docs-check.sh` containing `cp_`, `checkpoint_`, or `catchup_` are renamed to `stasis_` or `recall_` using full spelling (never abbreviated to `st_` or `rc_`).
- [ ] **AC-20:** `cmd_complete` in `docs-check.sh` removes `docs/stasis.md` (was `docs/checkpoint.md`); `pr` skill's lifecycle-doc cleanup list updates accordingly.
- [ ] **AC-21:** CI workflow template at `.ccanvil/templates/github/workflows/ci.yml` updates its stale-file grep from `docs/checkpoint.md` → `docs/stasis.md`.

### Rules, guide, and discoverability surface

- [ ] **AC-22:** `.claude/rules/workflow.md` replaces `On "checkpoint," use …` with `Run /stasis before /compact`, and `Resume after reset: read docs/checkpoint.md first.` becomes `Resume after reset: run /recall.` No residual "checkpoint" references.
- [ ] **AC-23:** `.claude/rules/self-review.md` updates its reference from `docs/checkpoint.md` to `docs/stasis.md` and from "at every checkpoint" to "at every stasis."
- [ ] **AC-24:** `.ccanvil/guide/session-management.md`, `.ccanvil/guide/decision-guide.md`, and `.ccanvil/guide/command-reference.md` have all instances of "Checkpoint this", "/catchup", "checkpoint.md", and related prose/Mermaid references updated to the new vocabulary.
- [ ] **AC-25:** `.ccanvil/guide/command-reference.md`'s Session Management table gains `/stasis` and `/recall` rows; stale `*"Checkpoint this"*` and `/catchup` rows are removed.
- [ ] **AC-26:** `.ccanvil/guide/system-overview.md`, `.ccanvil/guide/configuration.md`, and `.ccanvil/guide/index.md` have all "checkpoint" and "catchup" references updated.
- [ ] **AC-27:** `hub/meta/SYSTEM_PROMPT.md` and `hub/meta/HOW_TO_USE.md` have their references updated.
- [ ] **AC-28:** `README.md` references are updated.

### Comprehensive coverage guarantee

- [ ] **AC-29:** `grep -riE "(checkpoint|catchup)" --include='*.md' --include='*.sh' --include='*.yml' --include='*.json' .claude .ccanvil docs hub README.md | grep -vE "^(hub/tests/|\.claude/manifest\.lock|docs/specs/.*-(complete|archive))"` returns only intentionally retained references (git's literal checkpoint feature, quoted historical references in archived/completed specs, test fixtures that exercise the migration logic). Any match not on the allow-list is a bug.
- [ ] **AC-30:** Bats tests that previously asserted on the string `"checkpoint"` or `"catchup"` are updated to assert on `"stasis"` or `"recall"` where semantically appropriate. Tests that specifically exercise the legacy → new migration logic retain the old strings as inputs.

### Downstream migration (hub → nodes)

- [ ] **AC-31:** `ccanvil-sync.sh` gains logic that, on pull into a downstream node, detects legacy artifacts and migrates them:
  - If `docs/checkpoint.md` exists in node AND `docs/stasis.md` does NOT exist → rename in place (git mv).
  - If both exist (rare — user wrote a new stasis without migrating) → abort with a clear message; user resolves manually.
  - If `.claude/commands/catchup.md` exists in node → delete (hub owns it, hub removed it).
  - Migration is idempotent — running it twice produces no change on the second run.
- [ ] **AC-32:** The migration runs as part of the normal `broadcast`/`pull-apply` flow; the user does not need to invoke a separate command. Migration events are logged to `.ccanvil/events.log` (`event: migrate_stasis_rename`).
- [ ] **AC-33:** Downstream nodes with CLAUDE.md (or similar) sections that contain literal "checkpoint" or "catchup" strings in hub-owned content get updated when the hub file is pulled. Node-specific content (below the `NODE-SPECIFIC-START` marker) is not touched.
- [ ] **AC-34:** **Error: migration detected but partially complete.** If a node has `docs/stasis.md` but the last-pulled hub version still references `docs/checkpoint.md` in its content, `ccanvil-sync.sh` surfaces a clear warning so the user knows the node is between migrations.

### Legacy-reference scanner (for downstream projects)

- [ ] **AC-35:** New `docs-check.sh legacy-refs-scan [project-dir]` subcommand scans a project directory for references to legacy ccanvil verbs/artifacts (`/catchup`, `/checkpoint`, `docs/checkpoint.md`, `checkpoint.read`, `checkpoint.write`, `stale-checkpoint`). Reports JSON with file, line, and match. Exit 0 if clean, 1 if any found.
- [ ] **AC-36:** The legacy-refs scanner distinguishes between hub-owned content (above NODE-SPECIFIC markers) and node-specific content. Hub-owned matches are flagged as "pull needed" (hub has the fix); node-specific matches are flagged as "manual update needed" (the user wrote these).
- [ ] **AC-37:** `/stasis` invokes `legacy-refs-scan` as part of its Cross-Session Patterns check and surfaces any findings. A node with stale references never silently accumulates them.

### Rename-as-replacement semantics

- [ ] **AC-38:** No compatibility aliases or dual-name support exist anywhere in the shipping code. `checkpoint.read`/`checkpoint.write` are gone, not dual-registered. `docs/checkpoint.md` is gone, not a symlink. `/catchup` is gone, not a redirect.

## Affected Files

| File | Change |
|------|--------|
| `.claude/skills/stasis/SKILL.md` | New |
| `.claude/skills/recall/SKILL.md` | New (contents ported from `.claude/commands/catchup.md` with path updates) |
| `.claude/commands/catchup.md` | Deleted |
| `.ccanvil/templates/stasis.md` | New (contents of checkpoint.md + 3 new sections) |
| `.ccanvil/templates/checkpoint.md` | Deleted |
| `.ccanvil/scripts/docs-check.sh` | Modified — state name, variable names, path references, cmd_complete, new legacy-refs-scan subcommand |
| `.ccanvil/scripts/operations.sh` | Modified — operation names |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — migration logic, events.log type |
| `.claude/rules/workflow.md` | Modified |
| `.claude/rules/self-review.md` | Modified |
| `.ccanvil/guide/*.md` | Modified — all references |
| `.ccanvil/guide/command-reference.md` | Modified — table rows |
| `.ccanvil/templates/github/workflows/ci.yml` | Modified — grep pattern |
| `hub/meta/SYSTEM_PROMPT.md` | Modified |
| `hub/meta/HOW_TO_USE.md` | Modified |
| `README.md` | Modified |
| `.claude/manifest.lock` | Modified — path entries |
| `.claude/skills/pr/SKILL.md` (and equivalents) | Modified — lifecycle cleanup list |
| `hub/tests/stasis-recall.bats` | New — AC coverage for /stasis + /recall + rename + internals |
| `hub/tests/stasis-migration.bats` | New — AC-31 through AC-34 migration scenarios |
| `hub/tests/legacy-refs-scan.bats` | New — AC-35 through AC-37 scanner |

## Dependencies

- **Requires:** existing `docs-check.sh`, `permissions-audit.sh`, `context-budget.sh`, `ccanvil-sync.sh`, `operations.sh`, `security-audit` skill (graceful fallback).
- **Blocked by:** none.

## Out of Scope

- Auto-running `/stasis` from a hook on `/compact`. Manual invocation — hook coupling risks false positives on mid-session compactions.
- A hub-owned global command variant. Stasis/Recall are project-scoped.
- Changing the `missing-determinism-review` validate state name (unrelated to the stasis/recall rename).
- Changing the metadata field names in the stasis artifact (`feature_id`, `plan_hash`, `last_updated`) — load-bearing for `validate`, orthogonal to the rename.

## Implementation Notes

- Follow the `radar` skill structure for `/stasis` and `/recall`: "Data gathering (deterministic)" + "Synthesis" sections.
- Reuse `self-review.md`'s determinism-review criteria — do not duplicate.
- Cross-Session Patterns needs the prior stasis: `git show HEAD~1:docs/stasis.md 2>/dev/null` — expect empty on first run (AC-10).
- Variable naming: use full words `stasis_` / `recall_`, never `st_` / `rc_`. This follows the user's stated preference for less-likely overlap with standard verbs.
- Deletion of legacy files follows the "no backwards-compatibility hacks" rule.
- Migration logic runs in ccanvil-sync.sh as part of the existing broadcast/pull-apply flow — do not require a separate user-invoked command.
- Update Linear ticket BTS-75's title from "Pylon" → "Stasis & Recall (full rename)" as part of the landing commit.
- Test suite may need minor runtime allowance for the larger migration tests — but AC-30 should not require rewriting the majority of test assertions; most existing tests care about the artifact's metadata and content, not its literal filename.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
