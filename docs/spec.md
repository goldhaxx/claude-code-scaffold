# Feature: Layer 1 validate-spec primitive

> Feature: bts-265-layer-1-validate-spec-primitive
> Work: linear:BTS-265
> Created: 1777742428
> Subject: Layer 1 validate-spec primitive
> Status: In Progress

## Summary

Today the spec template (`.ccanvil/templates/spec.md`) defines structure (Acceptance Criteria, Affected Files, OoS, Implementation Notes), but enforcement is operator-attention-only. There's no machine-checkable gate on whether a spec has the right shape — `/spec` writes whatever Claude generates, and the lifecycle just trusts it. This ticket adds `docs-check.sh validate-spec --feature <id>` that surfaces structural gaps deterministically: AC count, Given/When/Then coverage on complex criteria, presence of at least one error criterion, and resolution of every file path mentioned in `## Affected Files`. `/spec`'s final step calls it as warn-but-don't-block — closes Layer 1's L1-C (loose template) gap.

## Job To Be Done

**When** an operator (or future-Claude) finishes drafting a spec via `/spec`,
**I want to** get a deterministic structural check on the spec — AC count, GWT coverage, error criterion present, file references resolve — without blocking the flow,
**So that** Layer 1 enforcement scales without operator-attention drift, and L1-B's critic-mode hand-off has a JSON envelope to consume.

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh validate-spec --feature <id>` reads `docs/specs/<id>.md` and emits JSON envelope `{coverage: {ac_count, gwt_count, error_criterion_count, file_refs_resolved, file_refs_total}, missing_file_refs: [...], status: "ok"|"drift"}` to stdout. Exit 0 on no findings; exit 2 on any structural drift.
- [ ] **AC-2 (AC count):** `coverage.ac_count` reflects the number of `- [ ] **AC-N:**` bullets under `## Acceptance Criteria`. When `ac_count == 0`, status is `"drift"` and `missing_file_refs` includes a synthetic entry `no-acceptance-criteria` (or the envelope grows a `findings[]` array — implementation choice).
- [ ] **AC-3 (GWT coverage):** `coverage.gwt_count` reflects ACs containing `Given/When/Then` (case-insensitive, all three keywords on one criterion). Required: at least 1 GWT criterion when `ac_count >= 4` (rule of thumb — small specs don't need GWT). Below threshold: silent pass; above threshold with 0 GWT: drift.
- [ ] **AC-4 (error criterion):** `coverage.error_criterion_count` reflects ACs whose body contains `error|edge|fail|invalid` (case-insensitive). Required: at least 1 error/edge AC. Zero → drift.
- [ ] **AC-5 (file ref resolution):** Walk the `## Affected Files` table; collect every backtick-fenced path (e.g., `` `.ccanvil/scripts/foo.sh` ``). Mark "resolved" when the path exists OR the row's "Change" column is `New`. Report `coverage.file_refs_resolved / coverage.file_refs_total` and emit `missing_file_refs: [{path, row}, ...]` for unresolved non-New paths.
- [ ] **AC-6 (clean spec):** Given a well-formed spec (>= 1 GWT when ac_count >=4, >= 1 error AC, all non-New file refs resolve), `validate-spec` exits 0 with `status: "ok"` and empty `missing_file_refs`.
- [ ] **AC-7 (error):** Given `--feature <unknown-id>` where `docs/specs/<id>.md` does not exist, stderr surfaces `ERROR: spec not found: docs/specs/<id>.md` and exit code is 2.
- [ ] **AC-8 (route-aware):** Given a Linear-routed node where the spec lives in a Linear Document, `validate-spec` invokes `artifact-read --kind spec --feature <id>` to fetch content, then validates the same way. (Re-uses the existing `artifact-read` substrate path — no separate Linear fetcher.)
- [ ] **AC-9:** `/spec` final step — after `stamp-spec` and the route-aware Linear dispatch — invokes `validate-spec --feature <id>` and surfaces the envelope as a warning section (NOT a block). The skill flow continues regardless. When drift is reported, the report appears under `## Validation Findings` in the operator-facing summary.
- [ ] **AC-10:** New bats test file `hub/tests/docs-check-validate-spec.bats` covers AC-1 through AC-7 with fixture spec files in `hub/tests/fixtures/specs/`. At least one fixture per drift class (no-AC, no-GWT-when-required, no-error-AC, missing-file-ref) plus one happy-path.
- [ ] **AC-11:** New `cmd_validate_spec` primitive added to `.ccanvil/manifest-allowlist.txt` with complete `# @manifest` block — drift-guard remains 100% (186 → 187).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `cmd_validate_spec` + dispatch entry |
| `.claude/skills/spec/SKILL.md` | Modified — append AC-9 final-step validation invocation |
| `hub/tests/docs-check-validate-spec.bats` | New — bats coverage for AC-1..7 |
| `hub/tests/fixtures/specs/*.md` | New fixtures (drift classes + happy path) |
| `.ccanvil/manifest-allowlist.txt` | Modified — add `cmd_validate_spec` entry |

## Dependencies

- **Requires:** existing `docs-check.sh` substrate (`cmd_artifact_read`, route awareness, lifecycle helpers). Spec template at `.ccanvil/templates/spec.md` defines the canonical shape this primitive validates against.
- **Blocked by:** none.

## Out of Scope

- L1-B `/spec --review` critic-mode hand-off (BTS-266) — separate sibling. L1-B will consume the envelope from this primitive as ONE of its inputs; that wiring is L1-B's scope.
- Validating the spec template itself (`.ccanvil/templates/spec.md`) — this primitive validates instances against the canonical template's shape, not the template definition.
- Retiring the existing `/spec` skill prose around AC quality — the prose stays as guidance for Claude during draft generation; the primitive is the post-draft gate.
- Validating plans (`docs/plan.md`) or stasis. Plan / stasis validation is plausible Phase 3 work but not Layer 1 scope.
- BLOCKING `/spec` flow on validate-spec drift. Warn-but-don't-block is the first ramp; promoting to BLOCKING can come post-soak if false-positive rate is low.

## Implementation Notes

- Pattern: `cmd_validate_spec` follows `cmd_extract` / `cmd_validate` shape — manifest block, dispatch entry, pure bash + awk + grep (no python / yq).
- AC parsing: walk between `## Acceptance Criteria` and the next `##` heading; count `^\s*- \[ \] \*\*AC-` bullets. For each, extract body (everything between `**AC-N:**` and the next `**AC-` or section end). Apply GWT and error regex against bodies.
- File-ref parsing: walk `## Affected Files` table rows. Pipe-split on `|`, extract backtick-fenced paths from column 1 and the literal "Change" string from column 2. Resolve via `[[ -f "$path" ]]` unless Change starts with "New".
- Route-aware: use `cmd_artifact_read` (already exists) — emits the spec content regardless of local-or-Linear routing.
- JSON envelope mirrors `cmd_validate` and `cmd_diff_vs_manifest` shape so `/spec` and L1-B can read with same jq idioms.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
