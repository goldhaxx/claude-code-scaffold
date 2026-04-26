# Implementation Plan: /idea jq -R @sh raw-flag fix

> Feature: bts-176-idea-jq-shsh-rawflag
> Work: linear:BTS-176
> Created: 1777183800
> Spec hash: 7a1e836f
> Based on: docs/spec.md

## Objective

Bring the two buggy `jq -R @sh` sites in `/idea` triage prose into parity with the established `jq -Rr @sh` pattern; lock in with a drift-guard bats so the buggy form can't reappear.

## Sequence

### Step 1: Drift-guard bats first (red)

- **Test:** Write `hub/tests/idea-skill-jq-rawflag.bats` with two assertions:
  - AC-3: `grep -q 'jq -R @sh' .claude/skills/idea/SKILL.md` returns NON-zero exit (pattern absent).
  - AC-4: `grep -c 'jq -Rr @sh' .claude/skills/idea/SKILL.md` returns ≥ 3.
- **Implement:** N/A — test-first.
- **Files:** `hub/tests/idea-skill-jq-rawflag.bats` (new).
- **Verify:** Run `bats hub/tests/idea-skill-jq-rawflag.bats`. Tests fail (current skill has `jq -R @sh` and only 3 occurrences of `jq -Rr @sh`, but AC-3 asserts `-R @sh` ABSENT, which currently fails).

### Step 2: Patch the two sites (green)

- **Test:** Re-run the bats from Step 1 — both pass.
- **Implement:** Two single-character edits to `.claude/skills/idea/SKILL.md`:
  - Line 165: `jq -R @sh` → `jq -Rr @sh` (priority quoting).
  - Line 169: `jq -R @sh` → `jq -Rr @sh` (target-id quoting).
- **Files:** `.claude/skills/idea/SKILL.md`.
- **Verify:** `bats hub/tests/idea-skill-jq-rawflag.bats` passes; full suite via `bash .ccanvil/scripts/bats-report.sh --parallel` stays green.

### Step 3: Live-validation gate (AC-5/AC-6)

- **Test:** Manual one-shot — run the original repro:
  ```bash
  RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve ticket.transition BTS-176 backlog --project-dir .)
  cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
  p=$(printf '%s' "3" | jq -Rr @sh)
  eval "$cmd --priority $p"
  ```
  Expect: `{id: "BTS-176", title: ...}` JSON, exit 0.
- **Implement:** N/A — proves the fix.
- **Files:** none.
- **Verify:** save-issue accepts the priority; BTS-176 ends up in Backlog state. Then transition it back to In-Progress so the rest of the lifecycle (PR, land, auto-close) is uninterrupted.

### Step 4: /review and /pr

- **Test:** All from prior steps stay green.
- **Implement:** Run `/review` (skill prose change is small but per the skip-review-on-trivial-diffs rule, this is borderline — drift-guard tests are sufficient. Decide on /review based on diff scope at commit time).
- **Files:** none.
- **Verify:** Run `/pr` (which itself runs validate + tests + review per `pr_review` config). PR #98 marked ready.

## Risks

- **Live-validation re-transitions BTS-176 to Backlog mid-lifecycle.** AC-6's repro uses `ticket.transition <id> backlog` to dogfood the fix, which actually moves the ticket. Mitigation: re-transition back to `in_progress` after the dogfood call so the standard auto-close at `/land` works correctly. (Or: pick a no-op transition target — but that's hacky; the dogfood is the proof.)
- **Drift-guard false negatives across distribution.** `hub/tests/...` runs only at the hub. Downstream nodes that already pulled `idea/SKILL.md` get the fix automatically via `/ccanvil-pull`. The drift-guard runs only in CI here.

## Definition of Done

- [ ] All acceptance criteria from spec pass (AC-1 through AC-6)
- [ ] All existing tests still pass (1413 baseline + 2 new = 1415)
- [ ] No type errors (n/a — bash + markdown only)
- [ ] Code reviewed (run /review or skip-on-trivial — judgment call at commit time)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
