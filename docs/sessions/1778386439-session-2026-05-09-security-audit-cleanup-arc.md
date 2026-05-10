# Stasis: session-2026-05-09-security-audit-cleanup-arc

> Feature: session-2026-05-09-security-audit-cleanup-arc
> Kind: session
> Last updated: 1778386439
> Session: 39
> Boundary: 2026-05-09T17:50:18-07:00

## Accomplished

A 4-ship arc on the `security-audit.sh` substrate, consolidating false-positive cleanup that was generating per-node allowlist boilerplate across the downstream fleet.

* **Inbound** `/ccanvil-push` from fieldnation-toolbox landed two commits on local main:
  * `7c474b2 chore(security-audit): fix history-scanner glob for nested allowlist paths` — pathspec `**${fpat}*` → `**/${fpat}**`. The broken glob silently let nested-path entries (`docs/fn-atlas/captures/...`) bypass file-form allowlist exclusion in `git log -S` pickaxe history scans. Verified upstream on fieldnation-toolbox (commit `e18e68e` was kept CRITICAL until the fix).
  * `866a22a test(security-audit): add nested-path regression for history-scan glob` — RED-then-GREEN regression test added BEFORE pushing to origin (prior session-37 pattern: regression test always lands with a substrate-filter fix). Pushed `7c474b2..866a22a` to origin via `ALLOW_MAIN=1 git`.
* **BTS-394 SHIPPED** (PR #174, `7bb6b94`). Carve out `.example`/`.template`/`.sample` basename suffixes from `scan_dangerous_files`. Single `case` statement; scope-tight (every other dangerous-extension regex is `$`-anchored, so the carve-out only ever exercises on the broad `\.env\.` matcher). 6 ACs + 2 edge tests covering `.env.local.example` (carved) and `.env.example.local` (still flags). One review fix-pass commit `ba241e4` addressed two WARNs: (1) the missed `.env.local.example`/`.env.example.local` edges, (2) `@manifest purpose:` line not yet documenting the carve-out.
* **BTS-395 SHIPPED** (PR #175, `105e3ca`). Filter URI-scheme prefixes out of the email-finding scan. Per-line `case "${content%%@*}"` match (position-aware: requires the URI scheme to precede the first `@`) plus `tr` lowercase folding (case-insensitive). 6 ACs + 2 edge tests covering trailing-comment URI mention and uppercase-scheme variants. One review fix-pass commit `7ff081a` addressed two WARNs that became real-fix instead of documentation: (1) silent-suppression-of-real-emails class bug → moved from substring-anywhere to position-aware match, (2) lowercase-only patterns → `tr`-lowered prefix.
* **Backlog drained 28 → 26.** Both BTS-394 and BTS-395 auto-closed in Linear via `/ship`'s ticket.transition dispatch.

## Current State

* **Branch:** `main` (clean, fast-forward through both squash-merges).
* **Tests:** PASS 2151 / FAIL 0 / TOTAL 2151 (was 2135 baseline at session start; +16 = 6 BTS-394 ACs + 2 BTS-394 edges + 6 BTS-395 ACs + 2 BTS-395 edges).
* **Uncommitted changes:** none.
* **Build status:** clean. PR #174 + #175 MERGED. BTS-394 + BTS-395 closed. Manifest 194/194 drift 0 status=ok.

## Blocked On

Nothing.

## Next Steps

1. **BTS-407 (P2)** — newly promoted substrate fix from session 38 triage. `operations.sh idea.add` resolver emits `--project ''` instead of `--project-id` when downstream config has `project_id`. Affects every `/idea` capture on Linear-routed downstream nodes. Quick fix, substrate-internal — same cache-warm cadence test as the BTS-394/395 pair (although different cache: [operations.sh](<http://operations.sh>) + [linear-query.sh](<http://linear-query.sh>), not [security-audit.sh](<http://security-audit.sh>)).
2. **Onboarding theme cluster (P2)** — re-anchor to the active theme. BTS-314 (Linear-config audit + heal pass for 3 drifted nodes) is the canonical first ship. Other onboarding tickets: BTS-324 (routing.ticket→routing.idea rename), BTS-327 (init fresh-mode CLAUDE.md inheritance), BTS-337 (provider-heal legacy-data-scan), BTS-312 (test-runner indirection).
3. **BTS-317 (P3, scheduled 2026-05-06 — 3 days overdue)** — Layer 3 ramp 1-week verification. Either confirm the remote agent fired and what it reported, or pull forward as a manual audit pass.
4. **BTS-204 — SSOT-Linear** (Triage; major effort, dedicated session).

## Context Notes

* **Cache-warm cadence test PASSED.** 4 ships in one session arc all on `security-audit.sh` + `security-audit.bats` (3 commits + 1 squash-merge per ship × 2 = \~8 commits hitting the same two files). Zero substrate-collision-mid-PR. Same mental model carried cleanly across the two BTS- fixes — same `case "$x" in *...*) continue ;;` pattern, same fix-pass discipline, same /ship outcome shape.
* **Inbound** `/ccanvil-push` pattern validated end-to-end. First operator-witnessed downstream→hub bidirectional sync this session: fieldnation-toolbox shipped a fix straight to my local hub main (ahead of origin by 1), then I added the regression test the substrate fix didn't include, ran tests, pushed to origin. Gap noticed: no regression test included by the original push. Operator chose "add regression test, then push" — established pattern for future inbound pushes.
* **Position-aware vs substring-anywhere matching.** Both BTS-394 and BTS-395 first shipped naive substring-anywhere `case` statements. BTS-395's review caught a class of silent-suppression bug (real email + URI scheme on same line gets suppressed). The fix used `${content%%@*}` to anchor the substring check at the position of the first `@`. Worth remembering as a discriminator-position pattern for future per-line filter substrate.
* **2/2 substrate-filter PRs had review WARNs requiring fix-pass.** Confirms the `feedback_review_fix_pass_before_pr_for_substrate_filter_logic` memory: substrate filter logic (carve-outs, exclusions, scope gates) is the high-yield surface for `/review` to catch impl divergence. Both fix-passes were tight: 1-2 commits before `/pr`, no sprawl.
* **BTS-263 known flakiness fired live.** First `/pr` full-suite for BTS-394 hit 1 spurious test failure on parallel run; re-running with `--json` returned `failures: []`. Re-run discipline (verify-twice on parallel-bats fail) is the correct mitigation until BTS-263 ships.
* **Context budget at 102.3% CRITICAL** (unchanged from prior session — settings.json + project CLAUDE.md are still the biggest single-file contributors). Not blocking; ceiling breached.

## Determinism Review

operations_reviewed: 26
candidates_found: 0

No candidates this session. The four-ship arc was deterministic by construction:

* `/recall` and `/radar` are read-only orient skills; all data via existing substrate (`docs-check.sh lifecycle-state`, `radar-gather`, `session-info`, `idea-count`, `permissions-audit.sh`, `module-manifest.sh validate`, `linear-query.sh list-issues`).
* `/spec` and `/plan` for both tickets used `docs-check.sh stamp-spec`, `artifact-write` (Linear-routed), `validate-spec` Layer 1 gate. Local archive write happens BEFORE Linear dispatch (BTS-213 ordering).
* `/activate` × 2 used `docs-check.sh activate` + `AUTO-TRANSITION` marker dispatch via `operations.sh resolve ticket.transition`.
* TDD red-then-green for both tickets: each AC authored a fixture-backed bats test BEFORE the impl, confirmed RED, then implemented to GREEN. RED-side validation for the BTS-395 fix-pass via `git stash` round-trip.
* `/review` × 2 = manifest pre-flight (`module-manifest.sh diff-vs-manifest --diff -`) + `security-audit.sh --files-only` + code-reviewer agent. All three deterministic; the agent's prose verdict is appropriate Claude work.
* `/pr` + `/ship` × 2 used `docs-check.sh pr-cleanup`, `assert-pr-title`, `gh pr ready`, `gh pr edit`, `ship-finalize` substrate. All idempotent.

Stochastic operations were limited to spec/plan/PR-body composition (Claude judgment) and reviewer-finding interpretation (Claude judgment). No script-replaceable patterns flagged.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

194 / 194 (allowlist), drift incidents: 0. Status: ok. Unchanged from session 38 baseline.

## Cross-Session Patterns

* **Recurring (positive, holding 5+): zero-candidates determinism review.** Sessions 35/36/37/38/39 all reported `candidates_found: 0`. 5 consecutive clean stasis snapshots — substrate maturity signal. The frontmatter atomization arc (BTS-385/386/387/384) plus velocity substrate (BTS-383) plus security-audit cleanup arc (7c474b2 + 866a22a + BTS-394 + BTS-395) all shipped without introducing new stochastic ops.
* **Recurring (positive, holding 4+): full-bats-runs-during-iteration discipline.** Sessions 35/36/37/38/39 each ran ONE full-suite per `/pr` gate. Discipline soaking in.
* **Recurring (positive, holding 3+): review-then-fix-pass shortens distance to clean ship.** Session 37 (BTS-384), session 39 (BTS-394), session 39 (BTS-395) — three consecutive substrate-filter PRs each had `/review` flag genuine issues that one fix-pass commit resolved cleanly. The pattern is: review BEFORE `/pr`, address WARN findings as a single fix-pass commit, then `/pr` clean. Captured to memory after BTS-384 (`feedback_review_fix_pass_before_pr_for_substrate_filter_logic`); confirmed twice more this session.
* **New (sample size 2): substrate-filter review catches discriminator-position bugs.** BTS-395's WARN-1 (silent-suppression-of-real-emails) was a position-aware-match issue: substring-anywhere case statement could swallow a real email when a URI scheme appeared in trailing prose. Position-aware fix using `${content%%@*}`. Same shape as the BTS-384 spec/impl divergence on AC-4 — both were "the impl behavior is broader than the spec implied." Worth watching: do future per-line filter substrates also surface this class? If yes, the fix could be a `/review` checklist item ("for per-line filter substrates: verify the discriminator-position is correctly anchored").
* **No legacy-refs drift** (legacy-refs-scan: empty).
* **No substrate-collision-mid-PR** despite 4 commits on the same 2 files. Cache-warm cadence pick worked.
* **Validated thesis: bidirectional sync ships work.** Session 39 was the first session to receive a downstream `/ccanvil-push` (fieldnation-toolbox) and operator-walk it to origin with a regression test. The pattern (push lands directly on local main → operator adds missing regression test → push to origin) is now precedent.

## Security Review

PASS — no secret/PII patterns introduced this session. Pre-existing security-audit findings unchanged from session 37 baseline (6 HIGH PII absolute paths in `hub/meta/operations.md` describing the drift-watchdog launchd plist, 3 MEDIUM email false-positives in `docs/sessions/` archive prose). Net new content this session: 4 commits' worth of substrate code + bats tests; security-audit gates ran clean on all four.

## Memory Candidates

* **Project pattern:** `project_security_audit_false_positives_closed` — BTS-394 (`.env.example` dangerous-file) + BTS-395 (URI-scheme email) SHIPPED 2026-05-09 in PR #174 + #175. Fleet-wide implications: every downstream node tracking `.env.example` or a DB connection string can now drop the per-node `.env.example::dangerous-file::` and `.env.example::email::` allowlist entries. The `security-audit.sh` substrate's two-known false-positive surfaces are closed upstream.
* **Feedback (validated):** `feedback_position_aware_match_for_per_line_substrate_filters` — when a per-line filter could over-suppress (skip a real finding because the skip-condition appears anywhere on the line), use a discriminator-position anchor (`${content%%@*}` to extract the prefix before the first `@`, then check for the URI scheme there). Why: substring-anywhere matches in mixed-content lines silently swallow real findings. How to apply: any future `case "$content" in *XXX*) continue ;; esac` substrate filter on per-line input — first ask "what's the per-line discriminator? could the skip-condition appear AFTER it?" and anchor accordingly.
* **Reference:** `reference_ccanvil_push_inbound_pattern` — when a downstream node runs `/ccanvil-push`, the resulting commit lands directly on the hub's local main (ahead of origin by 1) authored by the downstream operator. Hub operator's job: review the commit, add any missing regression test, push to origin. Confirmed live 2026-05-09 with fieldnation-toolbox → hub via 7c474b2 + 866a22a.
* **Reference:** `reference_bts_263_parallel_flakiness_mitigation` — when `bash bats-report.sh --parallel` reports 1 spurious failure on a single run, re-run with `--json` to confirm. Empirical: session 39's first BTS-394 /pr full-suite hit 1/2143 spurious; second run returned 0/2143. BTS-263 will eventually ship a fix; until then, two-run discipline is the mitigation.