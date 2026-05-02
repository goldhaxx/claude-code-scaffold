# Feature: Manifest query helpers

> Feature: bts-270-manifest-query-helpers
> Work: linear:BTS-270
> Created: 1777746662
> Subject: Manifest query helpers
> Status: Complete

## Summary

Today `module-manifest.sh query <key>:<value>` does substring filter across all manifest fields. Useful but loose — operators trying to ask "what touches the lockfile?" or "what calls cmd_X?" run a generic filter and post-process. This ticket adds four targeted query helpers as flags on the same primitive: `--by-side-effect <pattern>`, `--callers-of <id>`, `--depends-on <id>`, `--by-failure-mode <pattern>`. Each emits a JSON array of `{id, path, ...matched-field}` so `/recall` cold-starts and `/radar` strategic briefings can compose lenses without hand-rolled jq. Closes Layer 3's "188 self-describing primitives but no fast lens for cross-cutting questions" gap.

## Job To Be Done

**When** an operator (or future-Claude in `/recall` / `/radar`) wants to ask a cross-cutting structural question — "what touches disk?", "what depends on `linear-query.sh`?", "who calls `cmd_X`?", "what fails with exit 4?",
**I want to** run one targeted flag on `module-manifest.sh query` and get a clean JSON array of matches with the relevant field surfaced,
**So that** Layer 3 has fast, deterministic answers without operator-attention drift or hand-rolled jq.

## Acceptance Criteria

- [ ] **AC-1 (existing-shape preserved):** `bash .ccanvil/scripts/module-manifest.sh query <key>:<value>` (positional, existing shape) continues to work unchanged — substring filter across scalar + array fields, returns JSON array. No regression in coverage or output shape from BTS-239.
- [ ] **AC-2 (--by-side-effect):** `bash .ccanvil/scripts/module-manifest.sh query --by-side-effect <pattern>` returns a JSON array of `{id, path, "side-effect": [...matched-values]}` for every primitive whose `side-effect` array contains a string with `<pattern>` as substring (case-sensitive). Empty array when no matches; exit 0.
- [ ] **AC-3 (--callers-of):** `bash .ccanvil/scripts/module-manifest.sh query --callers-of <id>` returns a JSON array of `{id, path, caller: [...matched-values]}` for every primitive whose `caller` array includes `<id>` (or its skill: form for skills). Resolution mirrors BTS-269's caller normalization. Empty array when no callers; exit 0.
- [ ] **AC-4 (--depends-on):** `bash .ccanvil/scripts/module-manifest.sh query --depends-on <id>` returns `{id, path, "depends-on": [...matched-values]}` for every primitive whose `depends-on` array contains `<id>` (exact match). Empty array when no matches; exit 0.
- [ ] **AC-5 (--by-failure-mode):** `bash .ccanvil/scripts/module-manifest.sh query --by-failure-mode <pattern>` returns `{id, path, "failure-mode": [...matched-records]}` for every primitive whose `failure-mode` array contains a record with `<pattern>` as substring of the record's id segment OR full string. Empty array when no matches; exit 0.
- [ ] **AC-6 (mutually exclusive):** Given two or more flags from `{--by-side-effect, --callers-of, --depends-on, --by-failure-mode}` are passed simultaneously, OR a flag is mixed with a positional `<key>:<value>` argument, stderr surfaces `ERROR: query flags are mutually exclusive` and exit code is 2.
- [ ] **AC-7 (error: missing flag value):** Given `query --by-side-effect` with no following value, stderr surfaces `ERROR: --by-side-effect requires a pattern` and exit code is 2.
- [ ] **AC-8 (live dogfood):** Run `module-manifest.sh query --by-side-effect writes-` against the hub's 188 manifested entries; confirm at least one match in the result (since multiple primitives have `writes-*` side-effects). Document the count in the PR body.
- [ ] **AC-9:** New bats test file `hub/tests/module-manifest-query-helpers.bats` covers AC-1 through AC-7 with fixture allowlists or in-place hub data.
- [ ] **AC-10:** No new primitive added — existing `cmd_query` extended with flag parsing. Existing manifest block updated to declare the new flag inputs (`--by-side-effect`, `--callers-of`, `--depends-on`, `--by-failure-mode`). Drift-guard remains 100% (188 unchanged).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/module-manifest.sh` | Modified — extend `cmd_query` flag parsing + dispatch |
| `hub/tests/module-manifest-query-helpers.bats` | New — bats coverage for AC-1..7 |

## Dependencies

- **Requires:** existing `cmd_query` substrate (BTS-239); the manifest index store at `.ccanvil/state/manifests.json` (`_maybe_regenerate_index` already auto-refreshes when stale).
- **Blocked by:** none.

## Out of Scope

- Composable AND/OR query expressions (`--by-side-effect writes-disk AND --depends-on jq`). Single-key filter v1 only; composition can ride post-soak if friction surfaces.
- UI / interactive browsing of manifest results. CLI suffices — `/recall` / `/radar` consume JSON.
- CI integration (e.g., "fail PR if a primitive grows a new side-effect not declared elsewhere"). Out of band — that's BTS-268's deterministic-Layer-3 territory.
- `--callers-of` transitive resolution (i.e., "who calls callers of X"). One-hop only — matches BTS-239's existing one-hop caller validation.
- New primitive (`cmd_query_helpers` or similar). Stay inside `cmd_query` for surface area parsimony.

## Implementation Notes

- Pattern: extend the front of `cmd_query` with flag parsing. When any of the four flags is passed, dispatch to a specialized jq filter. When only positional `<key>:<value>` is passed, fall through to existing behavior unchanged.
- Each flag maps to a small jq pipeline:
  - `--by-side-effect`: `[ to_entries[] | .value as $m | $m | select(.["side-effect"] // [] | any(contains($v))) | {id, path: .key-derived-or-stored, "side-effect": [.["side-effect"][] | select(contains($v))]} ]`. (The path field comes from to_entries' key.)
  - `--callers-of`: same shape, filter on `.caller // [] | any(. == $id or . == "skill:/" + ...)`.
  - `--depends-on`: filter on `."depends-on" // [] | any(. == $id)`.
  - `--by-failure-mode`: filter on `."failure-mode" // [] | any(contains($v))`.
- Reuse `_maybe_regenerate_index` to ensure `.ccanvil/state/manifests.json` is fresh.
- Output shape consistent across all four flags: `{id, path, <field>: [...matched-values]}` so consumers read with same jq idioms.
- Live-API contract risk: NONE — pure local file walk + JSON emission.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
