# Stasis: session-2026-05-09-bts-384-rule-distribution-scope-ship

> Feature: session-2026-05-09-bts-384-rule-distribution-scope-ship
> Kind: session
> Last updated: 1778371700
> Session: 37
> Boundary: 2026-05-09T14:26:50-07:00

## Accomplished

End-to-end ratification of **BTS-384 (Rule distribution scope + abstraction discipline)** in a single session arc:

* **PR #173 SHIPPED** at 2026-05-09 \~17:08 PT. Squash-merged as `17a69fe`, branch deleted, BTS-384 → Done in Linear (auto-close fired via `/ship`).
* **Substrate landed:** extends BTS-385/386 rule frontmatter to honor `scope:` at distribution time. New helpers in `ccanvil-sync.sh` (`_resolve_node_role`, `extract_rule_scope`, `is_scope_allowed_for_role`, verbs `node-role` + `scope-check`); filter wired into `cmd_pull_plan` for both file loops with new `scope-skipped` action. New `module-manifest.sh validate` extensions: `rule-scope-invalid` (drift), `rule-scope-missing` (info), `rule-vocabulary-leak` (advisory info on `scope: universal` rule bodies outside `## Anchored on` blocks).
* **Hub config:** `.claude/ccanvil.json` gains `role: hub-substrate-developer`. `.ccanvil/templates/ccanvil.json.md` documents the role field with `substrate-consumer` default.
* **Audit-pass:** `provider-integration.md` re-tagged `universal → substrate` per AC-6. 4 universal rules retain advisory `rule-vocabulary-leak` info entries (background-task-discipline, evidence-required-for-captures, self-review, tdd) — stay as-is per spec Out-of-Scope (advisory soak window).
* **Doc update:** `.ccanvil/guide/sync.md` gains a "Rule scope and node role" section.
* **Triage:** cleared 6 → 0 at session start (BTS-394/395 promoted P2 fixes, BTS-397/398 P3 determinism, BTS-399/380 deferred to icebox).
* **Net test delta:** PASS 2106 → 2133 (+27 tests across 4 new bats files plus 1 AC-1-gap test from review fix-pass).

## Current State

* **Branch:** `main` (post-ship, fast-forward through squash-merge).
* **Tests:** PASS 2133 / FAIL 0 (full suite at /pr time, \~6 min wall via `--parallel --progress`).
* **Uncommitted changes:** none.
* **Build status:** clean. PR #173 MERGED. BTS-384 closed. Manifest 194/194, drift 0, status=ok.

## Blocked On

Nothing.

## Next Steps

1. **BTS-394 + BTS-395 (P2 pair)** — security-audit false-positives. Each \~30 min; full downstream-fleet impact. Quick double-ship to validate the cleared-queue → ship cadence.
2. **BTS-204 — SSOT-Linear.** Major effort, dedicated session. Routes specs/plans/stasis to Linear ticket bodies as primary surface.
3. `/idea triage` — 3 untriaged ideas accumulated mid-session (likely determinism captures from review or implementation observations). Worth triaging before next feature.

## Context Notes

* **Review fix-pass before /pr resolved a real spec/impl divergence.** Code-reviewer flagged AC-4: spec said hub-only files include in hub self-pull; impl always skipped. Tests + docs encoded the impl behavior — but the spec wording would have shipped misaligned. Fix-pass commit (`ecf3e0a`) updated spec AC-4 to match impl (cleaner design — hub-only files live at the hub source by definition; sync mechanism never distributes them anywhere) plus addressed AC-1 leak-scan gap (missing-scope files now scanned) plus added `# @manifest` blocks to 3 new operator-facing helpers. **Lesson:** never skip `/review` when changes touch substrate filter logic — agent-graded structural review catches ambiguity that drafted spec text plus binary tests both miss.
* `ALLOW_CONCURRENT_EDIT_OVERRIDE=1` required for re-dispatching specs after activate. The activate step's `artifact-write` advances the Linear Document's `updatedAt` timestamp; subsequent local edits plus re-dispatch hit the concurrent-edit guard. Same workaround pattern as session-kind documents (sessions 35/36/37).
* **Hash format mismatch in test setup.** First integration test in `rule-distribution-scope.bats` failed because `ccanvil-sync.sh hash` emits `<hash> <path>` (sha256sum format) and the lockfile expects bare hash. Fixed via `awk` first-field extraction. Worth remembering for future bats fixtures that pre-compute lockfile hashes.
* **Velocity discipline held.** ONE full-suite at /pr time (PASS 2133/0/2133). Targeted bats throughout (5+5+6+10+1=27 tests via 4 RED-GREEN cycles). Zero stacked invocations, zero wait-loops, zero buffered-vs-hung confusion (heartbeats throughout).

## Determinism Review

operations_reviewed: 22
candidates_found: 0

No candidates this session. The discipline held across 7 commits + 1 fix-pass + 1 ship:

* TDD red-green: each step authored a fixture-backed bats test BEFORE the impl, confirmed RED, then implemented to GREEN. No "implement-then-test" inversions.
* Substrate-driven verification: `module-manifest.sh validate --json`, `rule-scope-validate.bats`, `rule-vocabulary-leak.bats`, `ccanvil-role-field.bats`, `rule-distribution-scope.bats` — all deterministic, all replayable.
* Ship: `/ship 173` substrate handled title-assert + ready + merge + branch-delete + land + auto-close in one verb. Idempotent on already-correct title.
* Diff-vs-manifest gate (BTS-268): drift=\[\]; status=ok — caught zero introduced drift, validated the gate is wired correctly.

Stochastic operations were limited to commit-message and PR-body composition (appropriate Claude work) and the spec-AC-7 GWT reformat (one-shot prose tweak driven by validate-spec feedback).

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

194 / 194 (allowlist), drift incidents: 0. Info-warn count: 12 (8 rule-tier-budget-exceeded — BTS-386 advisory; 4 rule-vocabulary-leak — BTS-384 advisory, soak-window deferred). Status: ok.

## Cross-Session Patterns

* **Recurring pattern: full-bats-runs-during-iteration — STILL CLOSED.** Session 33 violated it 5+ times. Sessions 35/36/37 each ran ONE full-suite at `/pr` time. Three consecutive sessions with discipline holding — substrate (`--progress` plus `--json failures[]`) plus rule (`background-task-discipline.md`) working in concert.
* **Recurring pattern: substrate-collision-mid-PR — DID NOT recur.** Session 33 had 3 collisions; session 35 had 1; sessions 36/37 had 0. Frontmatter atomization arc completed cleanly across 4 PRs (BTS-385/386/387/384) with no architectural surprises.
* **New pattern: review-then-fix-pass shortens distance to clean ship.** Code-reviewer agent caught AC-4 spec divergence plus AC-1 leak gap plus manifest discipline gap — all 3 addressable in one fix-pass commit before `/pr`. Captured as memory candidate §2.
* **No legacy-refs drift** (legacy-refs-scan: empty).

## Security Review

PASS — no secret/PII patterns introduced this session. Security-audit found 9 pre-existing findings (6 HIGH PII absolute paths in docs/sessions/ plus hub/meta/operations.md, 3 MEDIUM email false-positives in docs/specs/bts-72-\* plus a stasis archive prose mention) — none introduced by BTS-384 commits. No `.env` writes, no credentials, no API keys.

## Memory Candidates

* **Project pattern:** `project_bts_384_substrate_complete` — BTS-384 SHIPPED 2026-05-09 PR #173. Completes the BTS-385/386/387/384 frontmatter arc end-to-end: tier (385) plus tier-validator (386) plus atomization (387) plus scope/role distribution filter (384). Hub rule distribution now structurally honors `scope:` at sync time; downstream nodes default to `substrate-consumer` and skip substrate-tagged rules. Vocabulary-leak drift-guard advisory; soak-window before escalation.
* **Feedback (validated):** `feedback_review_fix_pass_before_pr_for_substrate_filter_logic` — when changes touch substrate filter logic (scope/role/distribution gates), `/review` before `/pr` reliably catches spec/impl divergence and silent gaps that drafted spec text plus binary tests both miss. BTS-384 fix-pass commit `ecf3e0a` resolved 3 reviewer findings in one pass: AC-4 spec/impl alignment, AC-1 leak-scan gap, manifest discipline. Apply: never skip `/review` on substrate-filter PRs even if `--skip-review` is allowed by config.
* **Reference:** `reference_bats_lockfile_hash_format` — `bash ccanvil-sync.sh hash <file>` emits sha256sum format (`<hash>  <file>`); for lockfile pre-compute use awk first-field extraction to get bare hash. Misformatted lockfile hashes silently break pull-plan classification (auto-update becomes conflict). Captured as substrate idiom for bats fixture authors.