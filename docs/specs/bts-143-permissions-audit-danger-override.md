# Feature: permissions-audit DANGER override via accept_danger log flag

> Feature: bts-143-permissions-audit-danger-override
> Work: linear:BTS-143
> Created: 1777085933
> Status: Complete

## Summary

`permissions-audit.sh check`'s DANGER classification currently overrides any log entry — broad wildcards (`Bash(bash:*)`, `Bash(rm:*)`, `Bash(chmod:*)`) flag DANGER unconditionally even when the user has written a deliberate rationale accepting the risk. Post-BTS-142 the audit reports 16 DANGER entries that are all intentional broad wildcards backed by hooks; there is no path to mark them as deliberately accepted. Add an `accept_danger: true` flag to log entries: when set alongside filled rationale/justification/reviewer, a DANGER pattern match classifies as REVIEWED (with `matched_pattern` + `risk_accepted: true` preserved in the output for audit trail). DANGER count goes to 0 by design once all broad wildcards have rationales — the audit's role becomes "force review" not "block."

## Job To Be Done

**When** I'm reviewing the permissions audit and want to mark a broad wildcard as deliberately accepted (because hooks provide the actual safety floor),
**I want to** write a rationale + justification + reviewer + `accept_danger: true` in `permissions-log.json` and have the audit reclassify it as REVIEWED,
**So that** the DANGER count reflects only genuinely-unreviewed dangerous patterns, not intentional-by-design ones.

## Acceptance Criteria

- [ ] **AC-1:** When a permission trips a DANGER pattern AND has a log entry with `accept_danger: true` AND all four required fields filled (`risk`, `rationale`, `efficiency_justification`, `reviewer`), the entry classifies as REVIEWED. The output JSON includes `matched_pattern: "<pattern>"` AND `risk_accepted: true` to preserve audit trail.
- [ ] **AC-2:** When a permission trips a DANGER pattern AND has a log entry with `accept_danger: true` BUT one or more required fields are stub/empty/TODO, it stays DANGER (no override on incomplete entries).
- [ ] **AC-3:** When a permission trips a DANGER pattern AND has a log entry WITHOUT `accept_danger: true` (or with `accept_danger: false`), it stays DANGER (must be explicitly opted in).
- [ ] **AC-4:** When a permission trips a DANGER pattern AND has NO log entry, it stays DANGER (current behavior preserved).
- [ ] **AC-5:** When a permission does NOT trip a DANGER pattern, the existing 4-field-filled rule for REVIEWED applies unchanged. `accept_danger` is ignored in this branch.
- [ ] **AC-6:** Exit codes: 0 when 0 DANGER + 0 UNREVIEWED (matches existing semantics — risk_accepted entries count toward REVIEWED, not DANGER).
- [ ] **AC-7:** Text-mode output groups risk-accepted REVIEWED entries with a visual marker (e.g., `[risk-accepted]`) so they're distinguishable from clean REVIEWED entries.
- [ ] **AC-8:** All existing permissions-audit bats cases pass without modification.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Modified — `cmd_check` reclassifies DANGER → REVIEWED when log entry has `accept_danger: true` + all fields filled; output JSON adds `matched_pattern` + `risk_accepted` fields on the override path |
| `hub/tests/permissions-audit-check.bats` | Modified — add cases for AC-1..AC-7 |
| `.ccanvil/guide/permissions.md` (or wherever the log schema is documented) | Modified — document `accept_danger` field and the reclassification behavior |

## Dependencies

- **Requires:** BTS-142 (autonomy-first permissions rewrite) — already shipped. The 16 broad wildcards that produce the current DANGER count are the exact use case for this feature.
- **Blocked by:** Nothing.

## Out of Scope

- Backfilling rationales for the 16 existing broad wildcards. That's a separate review-pass task, naturally done after this ships.
- BTS-144 (settings.local.json delta tooling). Pairs with this but is a separate ship.
- Adding a new `RISK_ACCEPTED` status tier. The spec deliberately uses REVIEWED to keep status enum stable and exit-code semantics simple. The `risk_accepted: true` field in the output gives consumers the granularity if they need it.

## Implementation Notes

- The change is localized to the `if [[ -n "$matched_pattern" ]]; then` branch in `cmd_check` (around line 221). Inside, lookup the log entry first, check `accept_danger == true` AND the same 4-field-filled predicate that the no-DANGER branch uses, and reclassify as REVIEWED with the audit-trail fields. Otherwise, preserve current DANGER behavior.
- Reuse the existing `is_reviewed` jq predicate so the 4-field check is identical between branches. Just AND in `.accept_danger == true`.
- Output schema for the override path:
  ```json
  {
    "permission": "Bash(rm:*)",
    "source": ["settings.json"],
    "status": "REVIEWED",
    "matched_pattern": "rm.*\\*",
    "risk": "HIGH",
    "rationale": "...",
    "risk_accepted": true
  }
  ```
- Text-mode rendering: in the REVIEWED section, add a `[risk-accepted]` annotation when `risk_accepted == true`. Mirror the existing `[<pattern>]` annotation pattern from the DANGER section.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
