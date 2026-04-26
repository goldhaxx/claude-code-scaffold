# Implementation Plan: backlog.list canonical (BTS-175)

> Feature: bts-175-backlog-list-canonical
> Work: linear:BTS-175
> Created: 1777184300
> Spec hash: 33dda115
> Based on: docs/spec.md

## Objective

Make `backlog.list` the unambiguous canonical query for "what's in the backlog" on Linear-routed projects: http mechanism, state-id filter, no label filter, and routing inherits from `routing.idea` automatically.

## Sequence

### Step 1: Resolver tests first (red)

- **Test:** Write `hub/tests/backlog-list-canonical.bats` covering AC-1, AC-2, AC-4, AC-5, AC-9, AC-10. Use synthetic `.claude/ccanvil.local.json` fixtures via `mktemp -d` + `jq -n` composition. Tests query `bash .ccanvil/scripts/operations.sh resolve backlog.list --project-dir <fixture>` and assert the JSON shape.
- **Implement:** none.
- **Files:** `hub/tests/backlog-list-canonical.bats` (new).
- **Verify:** Tests fail because the substrate hasn't been changed yet.

### Step 2: Substrate change (green for resolver tests)

- **Test:** Re-run the bats from Step 1 — pass.
- **Implement:** Two changes to `.ccanvil/scripts/operations.sh`:
  1. Line ~883 — extend the routing fallback to include `backlog`:
     ```bash
     if [[ -z "$routed_provider" && ("$group" == "work" || "$group" == "ticket" || "$group" == "backlog") ]]; then
       routed_provider=$(jq -r '.integrations.routing.idea // ""' "$CONFIG_FILE")
     fi
     ```
  2. Linear `backlog.list` resolver block (currently at ~474, mechanism: mcp): replace with http mechanism that filters by `--state <backlog_state_id>`. If `state_ids.backlog` is empty/missing, exit 1 with stderr `state_ids.backlog not configured for Linear provider` (AC-10).
- **Files:** `.ccanvil/scripts/operations.sh`.
- **Verify:** `bats hub/tests/backlog-list-canonical.bats` passes.

### Step 3: Live-validation gate (AC-3)

- **Test:** Run on this project (real Linear API):
  ```bash
  RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve backlog.list --project-dir .)
  eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"
  ```
- **Expected:** JSON array containing BTS-22, BTS-20, BTS-21, BTS-175, BTS-77 (or similar — all items in Backlog state, no label filter).
- **Implement:** none — this proves the GraphQL filter shape matches Linear's contract.
- **Files:** none.
- **Verify:** Output includes scaffold-labeled tickets (BTS-22, BTS-20, BTS-21) — the canonical truth that `idea.list` was hiding.

### Step 4: Skill-prose tests first (red)

- **Test:** Write `hub/tests/recall-radar-backlog-prose.bats` covering AC-6, AC-7, AC-8 — drift-guards on `/recall` and `/radar` SKILL.md prose. Pure file-content assertions.
- **Implement:** none.
- **Files:** `hub/tests/recall-radar-backlog-prose.bats` (new).
- **Verify:** Tests fail (skill prose doesn't yet mention http mechanism or anti-pattern).

### Step 5: Skill-prose update (green)

- **Test:** Re-run Step 4 bats — pass.
- **Implement:**
  - `/recall` SKILL.md step 0c — extend the mechanism branching to include `http` (eval the command), add the anti-pattern note: "Do NOT use `idea.list` as a backlog proxy — it filters by `label=idea` and silently hides scaffold-labeled tickets. Always reach for `backlog.list` when reasoning about 'what's left to ship.'"
  - `/radar` SKILL.md step 2 — same anti-pattern note. Step 2 uses `exec backlog.list`; since `exec` evaluates the resolved command transparently, no mechanism-branching needed in the prose, but the note is required for drift-guard.
- **Files:** `.claude/skills/recall/SKILL.md`, `.claude/skills/radar/SKILL.md`.
- **Verify:** All bats pass; full suite stays green.

### Step 6: Project routing config (none)

- **Test:** This project's `.claude/ccanvil.local.json` already has `routing.idea = linear` and `state_ids.backlog` configured. The new fallback will fire automatically.
- **Implement:** No config change needed. (Per AC-1: the fallback fires WITHOUT explicit `routing.backlog`.)
- **Files:** none.
- **Verify:** `operations.sh resolve backlog.list --project-dir .` returns http mechanism on this project (covered in Step 3 live-validation).

### Step 7: /review + /pr

- **Test:** All from prior steps stay green.
- **Implement:** Run `/review` (substrate change to operations.sh — non-trivial diff, /review pays for itself per recurring-pattern memory).
- **Files:** none directly; address any /review findings before commit.
- **Verify:** `/pr` runs clean (validate aligned, tests pass).

## Risks

- **GraphQL filter shape mismatch.** The original BTS-170 incident: `--state` filter syntax. linear-query.sh already supports `--state` via its existing wrapper (BTS-164 substrate). AC-3's live-validation gate (Step 3) catches any contract drift before commit.
- **Existing Linear `mechanism: mcp` consumers.** Any external code that calls `backlog.list` and parses the `tool` + `params` shape will break when the response becomes `command` + `endpoint`. Search the repo for direct consumers; today only `/recall` and `/radar` consume it, and both will be updated in Step 5.
- **Routing fallback false-positive.** Could the new fallback accidentally route an unrelated `backlog.*` op to Linear? Mitigation: the fallback only fires when `routing.idea = linear`, AND the Linear `backlog.list` resolver checks `state_ids.backlog` presence (AC-10). If state_ids.backlog is missing, exit 1 — better than silent malformed query.

## Definition of Done

- [ ] All AC-1 through AC-10 pass
- [ ] All existing tests still pass (1417 baseline + new tests)
- [ ] /review surfaces no CRITICAL findings
- [ ] Live-validation gate (AC-3) passes against real Linear API

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
