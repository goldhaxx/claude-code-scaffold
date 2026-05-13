# Feature: CI fire drill — lifecycle-docs design bug fix + canonical example-data SSOT

> Feature: bts-482-lifecycle-docs-canonical-ssot
> Work: linear:BTS-482
> Created: 1778706369
> Subject: CI fire drill — lifecycle-docs design bug fix + canonical example-data
> Status: In Progress

## Summary

Hub's CI workflow template (`.ccanvil/templates/github/workflows/ci.yml`) ships a design bug — the `lifecycle-docs` job runs on every PR push and fails as long as `docs/spec.md`/`docs/plan.md`/`docs/stasis.md` exist on the branch. Since those files are present *throughout* a feature branch's life (only removed at `/pr` pr-cleanup), every implementation push triggers a CI red email. Compounding this, `security-audit.sh` already auto-allowlists `@example.com|@example.org|@example.net` addresses, but downstream test fixtures use ad-hoc fakes (`a@b.com`, `z@z.com`) that don't match the canonical namespace and trip the audit. Phase A: fix the workflow, ship a canonical example-data SSOT that downstream nodes reference for fixture authoring, broadcast to all 14 registered nodes.

## Job To Be Done

**When** I push commits to a feature branch in any ccanvil downstream node,
**I want to** receive CI failure emails ONLY when there is a real merge-blocking problem,
**So that** every CI red is a real signal demanding attention, not noise from in-flight lifecycle state.

## Acceptance Criteria

- [ ] **AC-1:** `lifecycle-docs` job in `.ccanvil/templates/github/workflows/ci.yml` skips execution when the triggering PR has `draft == true`. Verified by a workflow-syntax assertion in a bats test (`if:` condition includes `github.event.pull_request.draft == false`).
- [ ] **AC-2:** `lifecycle-docs` job continues to fire on `pull_request` events where draft is false AND on push-to-main events (regression coverage). Verified by bats assertions on the workflow yaml.
- [ ] **AC-3:** New file `.ccanvil/fixtures/canonical-example-data.json` exists with structure documented in Implementation Notes — emails, names, IDs, domains. Loads as valid JSON.
- [ ] **AC-4:** `.ccanvil/fixtures/canonical-example-data.json` declares at minimum 3 canonical email addresses, all matching the `@example\.(com|org|net)$` namespace already auto-allowlisted by `security-audit.sh` (no script change required for AC-4).
- [ ] **AC-5:** New documentation in `.ccanvil/guide/configuration.md` (or new `.ccanvil/guide/fixtures.md`) cites the SSOT location, structure, and the connection to `security-audit.sh`'s built-in exclusion regex.
- [ ] **AC-6:** Module-manifest declares `cmd_broadcast`'s use of the updated template (regression — broadcast distribution path remains green).
- [ ] **AC-7 (regression):** Hub's full bats suite (`docs-check.sh test-suite-run --parallel`) passes 100%. No existing test breaks.
- [ ] **AC-8 (post-merge):** Operator runs `bash .ccanvil/scripts/ccanvil-sync.sh broadcast` from hub; broadcast summary reports 14 nodes synced (or surfaces per-node conflicts cleanly). NOT automated in the spec — this is a manual post-merge step verified by the operator.
- [ ] **AC-9 (error path):** When `.ccanvil/fixtures/canonical-example-data.json` is malformed JSON, fixture-aware tooling that loads it (if any added in this PR) surfaces a clear error. Phase B's drift-guard depends on this file shape; Phase A only verifies the file parses.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/templates/github/workflows/ci.yml` | Modified — `lifecycle-docs` job gains `if: github.event.pull_request.draft == false` guard |
| `.ccanvil/fixtures/canonical-example-data.json` | New — SSOT for canonical fixture data |
| `.ccanvil/guide/configuration.md` | Modified — new section documenting the canonical fixtures SSOT and its connection to security-audit |
| `hub/tests/ci-template-lifecycle-docs.bats` | New — workflow yaml assertions (AC-1, AC-2) |
| `hub/tests/canonical-fixtures.bats` | New — SSOT file structure + JSON validity (AC-3, AC-4, AC-9) |
| `.ccanvil/manifest-allowlist.txt` | Modified — register canonical-example-data.json (if it gets a manifest block) |

## Dependencies

- **Requires:** existing `ccanvil-sync.sh broadcast` substrate (already exists; AC-8 is a manual invocation post-merge)
- **Requires:** `security-audit.sh`'s existing `@example.(com|org|net)` exclusion regex (line 261; no change needed)
- **Blocked by:** nothing

## Out of Scope

- Downstream node fixture migration (whoop-toolbox `z@z.com` → `alice@example.com` etc.). That's per-node operator work post-broadcast, not in this PR.
- `validate-fixtures` drift-guard for enforcement (Phase B / BTS-483).
- Unifying false-positive suppression across other guards (Phase B / BTS-483).
- CI consumption meta-loop / `ci-pull` substrate (Phase B / BTS-483).
- Cleaning the 9 `tmp.*` artifacts from the registry (separate ticket / BTS-484).
- Tightening `security-audit.sh` email regex beyond what already exists.

## Implementation Notes

**SSOT shape (`.ccanvil/fixtures/canonical-example-data.json`):**

```jsonc
{
  "version": 1,
  "emails": [
    {"address": "alice@example.com", "context": "primary user fixture"},
    {"address": "bob@example.org",   "context": "secondary user fixture"},
    {"address": "charlie@example.net", "context": "tertiary user fixture"}
  ],
  "names": [
    {"first": "Alice", "last": "Example"},
    {"first": "Bob",   "last": "Sample"}
  ],
  "user_ids": [10001, 10002, 10003],
  "domains": ["example.com", "example.org", "example.net", "test", "invalid"],
  "notes": "These reserved-namespace values are auto-allowlisted by .ccanvil/scripts/security-audit.sh's email scanner regex (RFC 2606). Test fixtures across ccanvil downstream nodes SHOULD source fake user data from this file (or use exactly these values inline) so security-audit treats them as known-fake."
}
```

**Lifecycle-docs guard pattern:**

```yaml
lifecycle-docs:
  runs-on: ubuntu-latest
  if: github.event_name == 'pull_request' && github.event.pull_request.draft == false
  ...
```

This preserves the existing intent (fire on PR events) while skipping the in-flight draft state. Push-to-main events don't trigger `pull_request`, so they're naturally excluded (which is correct — main shouldn't have lifecycle docs anyway; that's enforced by `protect-main.sh` hook).

**Test patterns to follow:**

- `hub/tests/bats-report.bats` for shell-script testing
- `hub/tests/ccanvil-init-skill.bats` for asserting yaml/markdown file contents via grep
- `hub/tests/test-suite-run.bats` (BTS-460) for module-manifest registration pattern

**Manifest discipline:**

- New scripts/modules get `# @manifest` blocks per `.ccanvil/templates/manifest.md`. If we don't add a new script in this PR (just a JSON file + workflow edit), no manifest block needed — JSON files are not manifest-tracked.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
