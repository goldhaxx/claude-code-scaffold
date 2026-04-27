# Feature: evidence-scan-session fetches description per bug-shape candidate

> Feature: bts-203-evidence-scan-description-fetch
> Work: linear:BTS-203
> Created: 1777329118
> Status: In Progress

## Summary

`cmd_evidence_scan_session` reads `.description` from `idea.list` results to check the four BTS-201 evidence anchors (`Command:`, `Output:`, `Exit:`, `Reproduce:`). But `idea.list` doesn't return `description` — its shape is `{id, title, status, statusType, priority, createdAt, updatedAt, labels}`. Result: every bug-shape-titled ticket reports `missing-evidence-anchors` even when the body has all four anchors line-leading. The protocol's primary substrate is currently false-positive-prone for any actually-evidence-backed bug capture.

This ship adds a per-candidate `get-issue` fetch to populate the description before the anchor check. Per ticket recommendation (option a): cheaper to ship than introducing a new resolver shape; one extra GraphQL call per matched bug-shape candidate (typical session has <5). Live-mode only — `--input-json` test mode still uses the canned description from the fixture.

## Job To Be Done

**When** I run `/stasis` and the evidence-scan emits the `## Evidence Gaps` section,
**I want to** see only tickets that genuinely lack the four BTS-201 anchors,
**So that** the section is signal not noise and the BTS-201 protocol's automation intent is preserved.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Bug-shape title + all four anchors in description (fetched via `linear-query.sh get-issue`) does NOT report `missing-evidence-anchors`. Live-mode true positive eliminated.
- [ ] **AC-2:** Bug-shape title + body missing one or more of the four anchors STILL reports `missing-evidence-anchors`. The check itself is unchanged.
- [ ] **AC-3:** `DIAGNOSE:` titles are still exempt — no fetch attempted, no anchor check performed.
- [ ] **AC-4:** `--input-json` test mode skips the fetch entirely. The canned `description` field in the fixture is the source of truth. Existing bats coverage relying on `--input-json` continues to pass without modification.
- [ ] **AC-5:** When `get-issue` fails (network/auth/server error), the candidate is reported as `missing-evidence-anchors` (preserving the pre-fix behavior on lookup failure — fail-closed). No silent skip; no false-positive-no-gap.
- [ ] **AC-6:** New bats `hub/tests/evidence-scan-description-fetch.bats` covers AC-1 (positive), AC-2 (negative), AC-3 (DIAGNOSE exemption), AC-4 (input-json skip-fetch), AC-5 (fetch-fail) via `--input-json` for the canned cases plus a `linear-query.sh` stub for the fetch-failure path.
- [ ] **AC-7:** Full bats suite remains green at ≥ 1775 (post-BTS-230 baseline).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/docs-check.sh` | `cmd_evidence_scan_session`: insert per-candidate `get-issue` fetch between the bug-shape title match and the anchor check, when running in live mode (no `--input-json`) and `body` is empty. |
| `hub/tests/evidence-scan-description-fetch.bats` | New bats covering AC-1 through AC-5. |

## Dependencies

* **Requires:** BTS-201 (evidence-scan-session substrate, original ship); `linear-query.sh get-issue` primitive (already exists). All shipped.
* **Blocked by:** Nothing.

## Out of Scope

* Adding a new `idea.list-with-description` resolver (option b in the ticket). Larger substrate change; per-candidate fetch is the simpler path.
* Caching fetched descriptions across multiple `evidence-scan-session` calls within a session. Single call per /stasis; caching not warranted.
* Parallelizing the fetches. Typical session has <5 bug-shape candidates; sequential is fast enough.

## Implementation Notes

* **Fetch placement:** insert after the bug-shape title match, before the anchor loop. Skip when `--input-json` is set OR `id` is empty.
* **Fetch shape:**

  ```bash
  if [[ -z "$body" && -z "$input_json" && -n "$id" ]]; then
    local fetched
    fetched=$(bash "$(dirname "$0")/linear-query.sh" get-issue "$id" 2>/dev/null) || fetched=""
    if [[ -n "$fetched" ]]; then
      body=$(echo "$fetched" | jq -r '.description // empty')
    fi
  fi
  ```
* **Fail-closed on fetch failure:** body remains empty → anchor check fails → reported as `missing-evidence-anchors`. Operator sees the gap, can manually verify the ticket.
* **Test stub pattern:** override `linear-query.sh` via PATH manipulation in the bats fixture for the fetch-failure case. The `--input-json` path covers the no-fetch cases.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
