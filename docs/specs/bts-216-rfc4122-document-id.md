# Feature: resolve-document-id emits valid RFC 4122 UUIDs

> Feature: bts-216-rfc4122-document-id
> Work: linear:BTS-216
> Created: 1777271137
> Status: Complete

## Summary

Fix `cmd_resolve_document_id` in `linear-query.sh` to force the RFC 4122
version + variant nibbles on the SHA-256 hash slice. Without this, every
caller-supplied `DocumentCreateInput.id` is rejected by Linear's validator
with `"id must be a UUID"` — silently breaking the BTS-204/BTS-213/BTS-214
SSOT-Linear flow that depends on idempotent first-write. Determinism is
preserved (same input still yields the same UUID).

## Job To Be Done

**When** any ccanvil flow writes a lifecycle Document to Linear with a
caller-supplied UUID,
**I want** Linear's GraphQL validator to accept the UUID,
**So that** the deterministic-UUID idempotency contract from BTS-204 actually
works end-to-end (concurrent-edit cache, /spec dispatch, archive matching).

## Acceptance Criteria

- [ ] **AC-1:** `linear-query.sh resolve-document-id --kind <K> --ticket <T>`
      output's third group (chars 14-17) starts with the literal character
      `4` (RFC 4122 version 4 — random). **Live-validated against
      api.linear.app/graphql:** Linear's validator (`class-validator`
      `isUuid('4')`) accepts ONLY v4. Hand-crafted control test:
      `aaaaaaaa-bbbb-4ccc-8ddd-...` succeeded; same UUID with `5ccc`
      version-nibble was rejected with `"id must be a UUID"`. Substituting
      the version nibble with literal `4` after the SHA-256 slice keeps
      determinism (this is "v4-shaped" not actually-v4 since v4 spec
      requires RNG, but the validator checks shape, not entropy).
- [ ] **AC-2:** `resolve-document-id` output's fourth group (chars 19-22)
      starts with one of `[89ab]` (RFC 4122 variant `10xx` — "DCE 1.1, ISO/IEC
      11578:1996"). The deterministic choice MUST be `8` so the UUID is
      reproducible.
- [ ] **AC-3 (determinism):** `resolve-document-id` is byte-stable —
      running it twice with identical `--kind` + `--ticket` returns the
      same output. Verified by hashing both invocations and asserting
      equality.
- [ ] **AC-4 (different inputs, different outputs):** kind/ticket changes
      still produce distinct UUIDs (no collision regression).
- [ ] **AC-5 (live API contract):** A `save-document --create-with-id`
      call against `api.linear.app/graphql` with a freshly-derived UUID
      succeeds (HTTP 200, no `Argument Validation Error`). Reverse-tested:
      the SAME call with the pre-fix derivation 422s with `"id must be a
      UUID"`. Live test trashes its own artifact via `trash-document`
      after success.
- [ ] **AC-6 (regression):** Existing 1702 bats tests pass unchanged. Any
      tests that captured pre-fix UUIDs as expected values are updated to
      the post-fix outputs (deterministic, easy to regenerate).
- [ ] **AC-7 (cache invalidation):** Any `.ccanvil/state/document-cache.json`
      cache file from a pre-fix run is left alone (it can't accumulate stale
      keys because no `--create-with-id` ever succeeded). No migration
      needed.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/linear-query.sh` | `cmd_resolve_document_id`: force version/variant nibbles |
| `hub/tests/ssot-linear.bats` | New BTS-216 drift-guards (AC-1/2/3/4); existing UUID-equality fixtures regenerate via `resolve-document-id` (no hard-coded values to update) |
| `.ccanvil/guide/command-reference.md` | Note `resolve-document-id` is RFC 4122 v4-shaped (Linear validates v4 only) |

## Dependencies

- **Requires:** BTS-204 substrate (already shipped; this is a defect fix on it).

## Out of Scope

- Migrating any existing Linear Documents created with the broken UUID — none
  exist (every prior `--create-with-id` 422'd).
- Changing the namespace UUID (`5b8e4a8e-4f3c-4d2a-9c1e-bf204550b91d`) —
  keep stable so derivations stay deterministic across the fix.
- Implementing strict RFC 4122 v4 (which requires RNG). Our derivation
  uses SHA-256 of `"<NS>:<kind>:<ticket>"` and forces v4 nibbles
  cosmetically. This passes Linear's `isUuid('4')` validator (which checks
  shape, not entropy) while preserving the deterministic-derivation
  invariant the BTS-204 idempotency contract depends on.

## Implementation Notes

- The fix is two extra characters of forcing in the printf format string.
  Stable across re-runs because we substitute the version/variant nibbles
  with constants (`4` and `8`).
- Live-validation gate: BTS-204's stasis claimed live-validation, but the
  test cited Linear-assigned UUIDs (not derived ones). This shipped a
  contract bug into 3 subsequent ships (BTS-213, BTS-214, BTS-204 itself).
  Anchor the live-API gate per `.claude/rules/tdd.md#live-api-validation-gate`
  — actually round-trip a `--create-with-id` call.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
