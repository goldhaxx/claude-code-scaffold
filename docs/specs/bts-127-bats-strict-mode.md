# Feature: Bats strict-mode convention — stop silent jq -e leaks

> Feature: bts-127-bats-strict-mode
> Work: linear:BTS-127
> Created: 1777054322
> Status: Draft

## Summary

In bats, a test passes iff the last statement's exit code is 0. Many `hub/tests/*.bats` tests use sequential `echo "$output" | jq -e '.a == "x"'` assertions — all but the final one fail silently, giving false confidence. Adopt strict-mode (`set -e` at top of affected tests) so every `jq -e` failure halts the test. Codify the convention in `.claude/rules/tdd.md` so future tests follow the pattern.

## Job To Be Done

**When** I write a bats test with multiple JSON-field assertions,
**I want to** have every failing assertion surface immediately,
**So that** a regression in any field — not just the last — fails the test loudly.

## Acceptance Criteria

- [ ] **AC-1:** Every `@test` block in `hub/tests/*.bats` that contains ≥2 `jq -e` invocations either uses `set -e` at its top OR combines the assertions into a single compound `jq -e`. No sequential-`jq -e` leakage remains.
- [ ] **AC-2:** When a `jq -e` assertion fails at line N inside a strict-mode test, bats reports the failure and the test halts at line N (verified by deliberately breaking one assertion in the suite and reverting).
- [ ] **AC-3:** `.claude/rules/tdd.md` contains a "Strict-mode bats tests" subsection explaining: (a) why the pattern matters, (b) when to apply `set -e` vs compound `jq -e`, (c) an example.
- [ ] **AC-4:** Full `bats hub/tests/` green after conversion — no regressions, no new failures surfaced (or if new failures ARE surfaced, they represent real bugs and are either fixed or filed as separate tickets with explicit AC addendum).
- [ ] **AC-5:** `run` helpers that consume `$output` from earlier commands are not affected — strict-mode applies to the assertion block, not to `run` itself. (Verified by inspecting a representative test.)
- [ ] **AC-6:** Error case: a sequential-`jq -e` pattern that a developer introduces in a new bats test is caught — the convention is enforceable via `grep` or lint (e.g., a simple `.ccanvil/scripts/bats-lint.sh` or documented grep pattern).

## Affected Files

| File | Change |
|------|--------|
| `hub/tests/auto-close-linear-on-merge.bats` | Modified (strict-mode) |
| `hub/tests/ccanvil-json-override.bats` | Modified (strict-mode) |
| `hub/tests/ccanvil-sync.bats` | Modified (strict-mode) |
| `hub/tests/context-budget.bats` | Modified (strict-mode) |
| `hub/tests/docs-check.bats` | Modified (strict-mode) |
| `hub/tests/feature-lifecycle.bats` | Modified (strict-mode) |
| `hub/tests/idea-triage-native.bats` | Modified (strict-mode) |
| `hub/tests/ideas-to-linear.bats` | Modified (strict-mode) |
| `hub/tests/legacy-refs-scan.bats` | Modified (strict-mode) |
| `hub/tests/init-mode-detection.bats` | Modified (strict-mode) |
| `hub/tests/metadata-work.bats` | Modified (strict-mode) |
| `hub/tests/node-uuid-registry.bats` | Modified (strict-mode) |
| `hub/tests/manifest-check.bats` | Modified (strict-mode) |
| `hub/tests/operations.bats` | Modified (strict-mode) |
| `hub/tests/pull-globals.bats` | Modified (strict-mode) |
| `hub/tests/permissions-audit.bats` | Modified (strict-mode) |
| `hub/tests/security-audit.bats` | Modified (strict-mode) |
| `hub/tests/registry-local-state.bats` | Modified (strict-mode) |
| `hub/tests/tech-stack-distribution.bats` | Modified (strict-mode) |
| `hub/tests/work-resolve.bats` | Modified (strict-mode) |
| `.claude/rules/tdd.md` | Modified (convention doc) |
| `.ccanvil/scripts/bats-lint.sh` (optional) | New (grep-based enforcement) |

## Dependencies

- **Requires:** bats-core 1.5.0+ (already pinned).
- **Blocked by:** Nothing.

## Out of Scope

- BTS-118 (suite performance / parallelization). Strict-mode is orthogonal to parallelism.
- Migrating tests to a different assertion framework (e.g., bats-assert). Stays in-tree, zero new deps.
- Converting single-`jq -e` tests — they already govern the exit code correctly.

## Implementation Notes

- **Chosen mechanism:** `set -e` at the start of each affected `@test` block. Surgical per-test, no file-level side effect. Verify bats semantics around `set -e` + `run` interaction before bulk-converting: `run` itself catches exit codes and stashes them in `$status`, so `set -e` should NOT affect `run` calls — only the assertions that follow.
- **Conversion pattern:**
  ```bash
  @test "some test" {
    set -e   # BTS-127: halt on any assertion failure
    run bash "$OPS" resolve something
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.a == "x"'
    echo "$output" | jq -e '.b == "y"'
    echo "$output" | jq -e '.c == "z"'
  }
  ```
- **Proof-of-fix TDD step:** pick one converted test, deliberately flip an assertion (`.a == "xx"`), confirm bats reports failure at that line, revert. Commit only the convention + conversions, not the broken flip.
- **New-surface risk:** currently-passing tests that were passing *because* of the leak. Any such test that surfaces a real bug should be handled in one of:
  - Fixing the underlying bug in the same PR if trivial (< 10 lines + clearly isolated).
  - Filing a separate ticket + adding `skip "BTS-XXX"` with explicit linkage (so it's visible in the suite report).
  - Not silently masking it with a weaker assertion.
- **Scope discipline:** new bats file created this session (`lifecycle-gate-audit.bats`) already uses strict-mode pattern — exempt from conversion but worth verifying against checklist.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
