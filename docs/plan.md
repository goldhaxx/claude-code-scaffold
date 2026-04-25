# Implementation Plan: permissions-audit DANGER override via accept_danger

> Feature: bts-143-permissions-audit-danger-override
> Work: linear:BTS-143
> Created: 1777085933
> Spec hash: f86143d6
> Based on: docs/spec.md

## Objective

Inside `cmd_check`'s DANGER-pattern-match branch (around line 221 of `permissions-audit.sh`), look up the log entry first; if it has `accept_danger: true` AND all four required fields are filled, reclassify the entry as REVIEWED with `matched_pattern` + `risk_accepted: true` preserved in the output. Otherwise, keep current DANGER behavior.

## Sequence

### Step 1: Test the override path (RED)
- **Test:** Add 4 cases to `hub/tests/permissions-audit.bats` next to the existing "DANGER overrides REVIEWED" block:
  - **AC-1**: `Bash(echo:*)` log entry with `accept_danger: true` + filled fields → status REVIEWED, output has `matched_pattern`, `risk_accepted: true`, exit code 0.
  - **AC-2**: `Bash(echo:*)` log entry with `accept_danger: true` BUT empty `rationale` → status DANGER, exit code 2 (no override on incomplete).
  - **AC-3**: `Bash(echo:*)` log entry with `accept_danger: false` + filled fields → status DANGER, exit code 2.
  - **AC-7**: Text-mode rendering shows `[risk-accepted]` annotation on the override entry's REVIEWED line.
- **Implement:** No code change yet.
- **Files:** `hub/tests/permissions-audit.bats`
- **Verify:** AC-1, AC-2, AC-7 fail (current code blindly classifies DANGER); AC-3 passes (matches existing behavior).

### Step 2: Add the override branch in cmd_check (GREEN)
- **Test:** Step 1 cases plus all existing permissions-audit cases (the "DANGER overrides REVIEWED" test specifically — must still pass since its log lacks `accept_danger`).
- **Implement:** In `cmd_check` (line 221 area), restructure the DANGER branch:
  ```bash
  if [[ -n "$matched_pattern" ]]; then
    # BTS-143: check for explicit accept_danger override before classifying DANGER
    local log_entry override
    log_entry=$(echo "$log_data" | jq -c --arg p "$perm" '.[$p] // null')
    override=$(echo "$log_entry" | jq '
      if . == null then false
      elif .accept_danger != true then false
      elif .risk == "" or .risk == "TODO" then false
      elif .rationale == "" or .rationale == "TODO" then false
      elif .efficiency_justification == "" or .efficiency_justification == "TODO" then false
      elif .reviewer == "" or .reviewer == "TODO" then false
      else true
      end
    ')

    if [[ "$override" == "true" ]]; then
      reviewed_count=$((reviewed_count + 1))
      local risk rationale
      risk=$(echo "$log_entry" | jq -r '.risk')
      rationale=$(echo "$log_entry" | jq -r '.rationale')
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" \
        --arg mp "$matched_pattern" --arg risk "$risk" --arg rationale "$rationale" \
        '. + [{permission: $p, source: $s, status: "REVIEWED", matched_pattern: $mp, risk: $risk, rationale: $rationale, risk_accepted: true}]')
    else
      danger_count=$((danger_count + 1))
      classified=$(echo "$classified" | jq --arg p "$perm" --argjson s "$sources" --arg mp "$matched_pattern" \
        '. + [{permission: $p, source: $s, status: "DANGER", matched_pattern: $mp}]')
    fi
  else
    # ... existing no-DANGER branch unchanged
  fi
  ```
- **Files:** `.ccanvil/scripts/permissions-audit.sh`
- **Verify:** Run BTS-143 cases — pass. Run full suite — green.

### Step 3: Text-mode rendering for AC-7
- **Test:** AC-7 from Step 1.
- **Implement:** In the text-mode REVIEWED rendering block (around line 315), add a conditional `[risk-accepted]` annotation when the entry has `risk_accepted == true`. Mirror existing pattern annotation in the DANGER section.
- **Files:** `.ccanvil/scripts/permissions-audit.sh`
- **Verify:** AC-7 case passes.

### Step 4: Documentation
- **Test:** None.
- **Implement:** Find and update the permissions-log schema doc (likely in `.ccanvil/guide/permissions.md` or similar) to describe the `accept_danger` field. If no dedicated doc exists, add a comment block in `permissions-audit.sh` near the `cmd_check` function.
- **Files:** Wherever schema docs live.
- **Verify:** Read once for fidelity.

### Step 5: Dogfood (optional, follow-up ticket)
- **Test:** None (manual).
- **Implement:** No code. Observe that with the fix shipped, the 16 existing DANGER entries stay DANGER (no `accept_danger` flag set yet). The follow-up review pass (separate session/ticket) would write rationales + `accept_danger: true` for each, dropping DANGER count to 0.
- **Files:** None.
- **Verify:** Out of scope for this ship.

## Risks

- **Schema migration concern.** Existing log entries don't have `accept_danger`. The override branch checks `.accept_danger != true` which evaluates to `true` for both `false` and missing → no override fires for legacy entries. Backwards-compatible by design.
- **Text-mode test assertions.** AC-7 needs to grep text output for `[risk-accepted]`. Watch for ANSI-color or whitespace differences. Use `grep -F` with literal string match.
- **Two-jq-call structure.** The override logic runs `jq` twice per DANGER entry (lookup + predicate). Negligible perf hit since DANGER entries are rare.

## Definition of Done

- [ ] All 8 acceptance criteria from spec pass
- [ ] All existing tests still pass (1067 baseline → ~1071 expected)
- [ ] Text-mode `[risk-accepted]` annotation visible
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
