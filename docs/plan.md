# Implementation Plan: refresh-plan-hash substrate primitive

> Feature: bts-177-refresh-plan-hash
> Work: linear:BTS-177
> Created: 1777217281
> Spec hash: bcaac9f2
> Based on: docs/spec.md

## Objective

Add a deterministic substrate command that refreshes `docs/plan.md`'s `> Spec hash:` metadata line to match `docs/spec.md`'s current `content_hash`, eliminating Claude's manual hand-edit when scope expands mid-implementation.

## Sequence

### Step 1: failing test for happy path (AC-1, AC-2, AC-8)
- **Test:** new `hub/tests/refresh-plan-hash.bats` — fixture creates a minimal `docs/spec.md` and `docs/plan.md` with deliberately mismatched `> Spec hash:` lines. Run `refresh-plan-hash`, assert exit 0, output JSON shape `{updated:true, spec_hash:<8-hex>, plan:"docs/plan.md"}`, plan file's `> Spec hash:` line now matches the live spec hash.
- **Implement:** add `cmd_refresh_plan_hash()` skeleton + dispatch case wired in the main case block. Read `docs/spec.md`, run `content_hash`, then `sed` the `> Spec hash:` line via `mktemp`+`mv`.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/refresh-plan-hash.bats`.
- **Verify:** AC-1, AC-2, AC-8 (success path) green.

### Step 2: idempotence (AC-3)
- **Test:** run `refresh-plan-hash` twice on a fixture where hashes already match. Assert second run exits 0 with `updated:false` and the plan file's mtime/content is unchanged byte-for-byte.
- **Implement:** before sed, compare current spec hash against the plan's existing `> Spec hash:` line; if equal, emit no-op JSON and return without writing.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/refresh-plan-hash.bats`.
- **Verify:** AC-3 green; AC-1, AC-2, AC-8 still green.

### Step 3: stale-plan regression (AC-4)
- **Test:** fixture creates spec+plan in `aligned` state; mutate the spec body (append a paragraph) so its `content_hash` changes; run validate (asserts `stale-plan`); run `refresh-plan-hash`; run validate again (asserts `aligned`). Uses real `cmd_validate` end-to-end.
- **Implement:** no new code expected — this is a regression that the Step 1+2 implementation must satisfy. If it doesn't, fix the implementation.
- **Files:** `hub/tests/refresh-plan-hash.bats`.
- **Verify:** AC-4 green.

### Step 4: error paths (AC-5, AC-6, AC-7)
- **Test:** three failing tests — (a) missing `docs/spec.md` exits non-zero with the spec'd stderr message, plan.md unchanged; (b) missing `docs/plan.md` exits non-zero with the spec'd stderr message; (c) `docs/plan.md` exists but has no `> Spec hash:` line, exits non-zero with the spec'd stderr message and plan.md unchanged.
- **Implement:** guard clauses at the top of `cmd_refresh_plan_hash` for spec presence, plan presence, and `> Spec hash:` line presence (via `grep -q`). Each emits the exact stderr text from the AC and exits non-zero.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/refresh-plan-hash.bats`.
- **Verify:** AC-5, AC-6, AC-7 green; success-path tests still green.

### Step 5: atomicity assertion (AC-9)
- **Test:** drift-guard bats — `grep -E "mktemp|tmpfile" .ccanvil/scripts/docs-check.sh` between the `cmd_refresh_plan_hash() {` line and its closing `}` succeeds AND a literal `> "$plan_file"` (single-redirect to the destination) is absent. Implementation-tier check; documents the rule and prevents future regression to non-atomic write.
- **Implement:** Step 1's `mktemp`+`mv` pattern already satisfies this. Drift-guard locks it in.
- **Files:** `hub/tests/refresh-plan-hash.bats`.
- **Verify:** AC-9 green.

### Step 6: full suite + docs update
- **Verify:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green (1448 → ~1455).
- **Docs update:** preset-infra change → add `docs-check.sh refresh-plan-hash` row to `.ccanvil/guide/command-reference.md` (next to the other docs-check subcommands). Optionally update `/plan` skill prose to mention the command — defer for now; the command is self-discoverable via `/recall`'s lifecycle inspection.

## Risks

- **`sed -i` portability.** macOS `sed -i` requires an empty backup-suffix arg (`sed -i ''`); GNU sed accepts `sed -i`. Mitigation: use `mktemp`+`mv` instead of `sed -i` (the spec's AC-9 requires this anyway), so portability isn't an issue.
- **Hash extension drift.** If a future change makes `content_hash` longer than 8 chars, the regex `[a-f0-9]{6,}` accepts it; if shorter, the regex still matches. Min length 6 is conservative.
- **Empty content_hash.** If the spec metadata blockquote occupies the entire file (no body content), `content_hash` returns the sha of an empty string — `e3b0c442` truncated. Tests should cover this case implicitly via the happy-path fixture; unlikely but worth a single explicit assertion.

## Definition of Done

- [ ] All 9 acceptance criteria from spec pass
- [ ] All 1448+ existing tests still pass via `bats-report.sh --parallel`
- [ ] `command-reference.md` updated with new subcommand
- [ ] Code reviewed (run `/review` — substrate-tier ship per `feedback_skip_review_on_trivial_diffs` cut-line)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
