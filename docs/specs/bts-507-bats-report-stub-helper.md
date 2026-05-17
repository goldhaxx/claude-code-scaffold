# Feature: Bats-Report Pre-Warm Stub Helper

> Feature: bts-507-bats-report-stub-helper
> Work: linear:BTS-507
> Created: 1778973343
> Subject: Bats-Report Pre-Warm Stub Helper
> Status: Complete

## Summary

`bats-report.sh` runs a ~7-min `module-manifest.sh validate` pre-warm whenever `BTS_MANIFEST_VALIDATE_CACHE` is unset. Any bats test that invokes `bash bats-report.sh ...` in a subshell pays that toll per invocation. Today, 6 test files duplicate an ad-hoc `BTS_MANIFEST_VALIDATE_CACHE=…` bypass — 4 with valid JSON content, 2 with bare paths — and the trap silently re-appears in any new test that forgets the pattern (cost the BTS-497 session ~28 min before catch). This ship codifies the bypass as a shared helper `hub/tests/_helpers/bats-report-stub.bash` and adds a mechanical drift-guard so no future test re-enters the trap.

## Job To Be Done

**When** I author a new `.bats` test that invokes `bash bats-report.sh` in a subshell,
**I want to** call one helper line that opts out of the BTS-281 pre-warm correctly,
**So that** I don't burn 7+ minutes per sub-invocation by forgetting the env-var dance, and I can't accidentally land such a file in a PR.

## Acceptance Criteria

- [ ] **AC-1:** A new helper at `hub/tests/_helpers/bats-report-stub.bash` exports a function `stub_bats_report_prewarm` that writes a canonical zero-coverage manifest envelope (`{"coverage":{"covered":0,"total":0},"drift":[],"status":"ok"}`) to a path under `$BATS_FILE_TMPDIR` and exports `BTS_MANIFEST_VALIDATE_CACHE` pointing at it.
- [ ] **AC-2:** The helper is idempotent at file scope — calling `stub_bats_report_prewarm` twice within the same bats file does not error and yields the same exported path.
- [ ] **AC-3:** After helper land, the 6 existing call-sites (`bats-report-no-telemetry.bats`, `bats-report-stdout-config-line.bats`, `bats-report-otel-flatten.bats`, `docs-check-test-suite-run-healthcheck.bats`, `bats-report-failures-preserved.bats`, `bats-report-progress.bats`) are refactored to `load _helpers/bats-report-stub` + call `stub_bats_report_prewarm`. Their inline `BTS_MANIFEST_VALIDATE_CACHE=…` lines are removed.
- [ ] **AC-4:** A new drift-guard test `hub/tests/bats-report-stub-drift-guard.bats` scans every `.bats` file matching the glob `hub/tests/*.bats` (one level, non-recursive) for the pattern `bash[^\n]*bats-report\.sh` and asserts each matching file ALSO contains the literal token `load _helpers/bats-report-stub` OR an exemption marker `# bats-report-stub: exempt` on a comment line.
- [ ] **AC-5:** Error: Given a `.bats` file matching the AC-4 glob that invokes `bats-report.sh`, When neither the helper-load token nor the exemption marker is present, Then the drift-guard test fails with output naming the offending file path.
- [ ] **AC-6:** Edge: files under `hub/tests/fixtures/` are unreachable by the AC-4 glob and therefore implicitly out of scope — no special-casing required in the scan.
- [ ] **AC-7:** The full bats suite (`bash .ccanvil/scripts/bats-report.sh --parallel`) passes after the refactor, including the new drift-guard.

## Affected Files

| File | Change |
|------|--------|
| `hub/tests/_helpers/bats-report-stub.bash` | New helper |
| `hub/tests/bats-report-stub-drift-guard.bats` | New drift-guard test |
| `hub/tests/bats-report-no-telemetry.bats` | Refactor to use helper |
| `hub/tests/bats-report-stdout-config-line.bats` | Refactor to use helper |
| `hub/tests/bats-report-otel-flatten.bats` | Refactor to use helper |
| `hub/tests/docs-check-test-suite-run-healthcheck.bats` | Refactor to use helper |
| `hub/tests/bats-report-failures-preserved.bats` | Refactor to use helper |
| `hub/tests/bats-report-progress.bats` | Refactor to use helper |

## Dependencies

- **Requires:** existing `BTS_MANIFEST_VALIDATE_CACHE` env-var contract in `.ccanvil/scripts/bats-report.sh` (line 194 — unchanged by this ship).
- **Blocked by:** none.

## Out of Scope

- `.ccanvil/scripts/bats-report.sh` heuristic detection of single-fixture invocations to auto-skip the pre-warm (Path 2 in the ticket). Helper + drift-guard is the chosen path; substrate-side autodetect is a separate ship.
- Any changes to BTS-281's per-test cache helper (`hub/tests/_helpers/manifest-validate-cache.bash`). That helper consumes the cache from within a bats file; this ship is about subshell invocations of `bats-report.sh` from within a bats file. Different scope.
- Module-manifest declarations for the new helper or drift-guard test. Test fixtures under `hub/tests/_helpers/` and `hub/tests/*.bats` are not in `.ccanvil/manifest-allowlist.txt` and don't get manifest blocks (parity with `manifest-validate-cache.bash` and `module-manifest-drift-guard.bats`).

## Implementation Notes

- Follow the shape of `hub/tests/_helpers/manifest-validate-cache.bash`: single-purpose helper, descriptive function name, BTS-anchor in the comment header.
- The helper writes to `$BATS_FILE_TMPDIR` (auto-cleaned by bats), not `/tmp` (which the BTS-383 bypasses leak).
- Drift-guard glob: `hub/tests/*.bats` only (one level). Scan depth is stated authoritatively in AC-4; this note is confirming guidance.
- Exemption marker `# bats-report-stub: exempt` should be discoverable by `grep -F` and require explicit prose justification in the same comment block (drift-guard checks for the marker only; the prose is convention).
