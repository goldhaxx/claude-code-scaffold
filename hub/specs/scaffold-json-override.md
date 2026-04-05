# Feature: scaffold.json Node-Override Strategy

> Feature: scaffold-json-override
> Created: 1774312905
> Status: Complete

## Summary

Introduces `scaffold.local.json` — a gitignored, node-only overlay file that deep-merges over the hub-tracked `scaffold.json` at read time. Hub owns `scaffold.json` (whole-file auto-update on pull). Node owns `scaffold.local.json` (never synced). All scripts read the merged effective config via a shared `read_effective_config()` function. This unblocks adding Linear routing config to the hub without overwriting node-specific provider settings.

## Job To Be Done

**When** a developer configures project-specific tool integrations (Linear project, team, routing) in `scaffold.json`,
**I want to** keep those overrides in a separate local file that survives scaffold pulls,
**So that** hub feature toggles flow automatically while my provider config is never overwritten.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1 (merge basics):** Given `scaffold.json` with `{"features":{"pr_review":false}}` and `scaffold.local.json` with `{"integrations":{"routing":{"backlog":"linear"}}}`, a merge function produces `{"features":{"pr_review":false},"integrations":{"routing":{"backlog":"linear"}}}`. Verified with `jq`.

- [ ] **AC-2 (node wins on conflict):** Given both files define the same key (e.g., `features.pr_review`), the value from `scaffold.local.json` wins. This is the permissive deep-merge (Option A) — node can override any key.

- [ ] **AC-3 (no local file):** When `scaffold.local.json` does not exist, the effective config equals `scaffold.json` exactly. No error, exit 0.

- [ ] **AC-4 (no hub file):** When `scaffold.json` does not exist (and `scaffold.local.json` does not exist), operations.sh behaves identically to today — all local adapters, exit 0.

- [ ] **AC-5 (operations.sh wired):** `operations.sh resolve backlog.list --project-dir <dir>` reads the merged effective config. Given routing config only in `scaffold.local.json`, the operation resolves to the configured provider (not local fallback).

- [ ] **AC-6 (docs-check.sh wired):** `docs-check.sh config-get pr_review <dir>` reads the merged effective config. Given `features.pr_review: true` only in `scaffold.local.json`, it returns `"true"`.

- [ ] **AC-7 (invalid local JSON):** When `scaffold.local.json` contains invalid JSON, scripts exit 1 with stderr: `ERROR: .claude/scaffold.local.json is not valid JSON`.

- [ ] **AC-8 (pull safety):** `ccanvil-sync.sh pull-plan` classifies `scaffold.json` as `auto-update` when the hub changes it and the local copy is clean (node overrides live in `scaffold.local.json`, not in `scaffold.json`). Verified by: hub changes `scaffold.json`, `pull-plan` output shows `"action": "auto-update"` for `.claude/scaffold.json`.

- [ ] **AC-9 (gitignore):** `.claude/scaffold.local.json` is listed in `.gitignore`. Verified with `grep`.

- [ ] **AC-10 (claudeignore):** `.claude/scaffold.local.json` is listed in `.claudeignore` (Claude reads the effective config via scripts, not raw file reads). Verified with `grep`.

- [ ] **AC-11 (deep merge, not shallow):** Given `scaffold.json` with `{"integrations":{"providers":{"github":{"mechanism":"cli"}}}}` and `scaffold.local.json` with `{"integrations":{"providers":{"linear":{"mechanism":"mcp"}}}}`, the merged result contains BOTH providers. Verified with `jq '.integrations.providers | keys | length == 2'`.

- [ ] **AC-12 (hub template updated):** `docs/templates/scaffold.json` includes a comment or documentation reference explaining the `scaffold.local.json` overlay pattern. Verified by reading the template.

## Affected Files

| File | Change |
|------|--------|
| `scripts/operations.sh` | Modified — `read_config()` reads merged effective config |
| `scripts/docs-check.sh` | Modified — `config-get` reads merged effective config |
| `tests/operations.bats` | Modified — add tests for local override merge |
| `tests/scaffold-json-override.bats` | New — dedicated test file for merge behavior |
| `.gitignore` | Modified — add `.claude/scaffold.local.json` |
| `.claudeignore` | Modified — add `.claude/scaffold.local.json` |
| `docs/templates/scaffold.json` | Modified — document overlay pattern |
| `CLAUDE.md` | Modified — document `scaffold.local.json` in Commands/Architecture |
| `GUIDE.md` | Modified — document overlay pattern in Configuration Layers and Scaffold Sync |

## Dependencies

- **Requires:** `jq` (already used everywhere)
- **Requires:** BTS-19 (operations.sh) — Complete
- **Blocked by:** Nothing

## Out of Scope

- Enforcement mode (hub keys that node cannot override — Chrome "mandatory" model). Future enhancement if needed.
- Schema validation of scaffold.local.json structure.
- Migration tooling for existing node-modified scaffold.json files.
- Array merge strategies (no arrays in current schema; document the policy for when they're added).
- `ccanvil-sync.sh` changes to pull-plan action classification (scaffold.json already gets `auto-update` when local is clean; the design ensures local stays clean by moving overrides to the local file).

## Implementation Notes

- **Merge expression:** `jq -s '.[0] * (.[1] // {})' scaffold.json scaffold.local.json` — standard RFC 7396 deep merge via jq's `*` operator. Node wins on conflict.
- **Shared function pattern:** Both `operations.sh` and `docs-check.sh` need the merge logic. Options: (a) duplicate the ~10-line function in each script, (b) extract to a shared `lib.sh` sourced by both. Given the scaffold's bash-3 constraint and current pattern (no shared libs), option (a) is simpler and matches existing patterns.
- **Existing `settings.local.json` precedent:** `.gitignore` already has `.claude/settings.local.json`. The pattern is established.
- **No init changes needed:** `/init` creates `scaffold.json` from the template. `scaffold.local.json` is created by the user when they configure integrations. No scaffolding needed.
- **Deterministic-first:** The merge is a pure `jq` expression — deterministic, no Claude judgment involved.
- **Research basis:** See `docs/research/layered-config-ownership.md` for the full analysis of 9 systems + 2 RFCs that informed this design. Chrome's managed preferences model (separate files per owner) + RFC 7396 (jq `*` deep merge) was the convergent recommendation.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
