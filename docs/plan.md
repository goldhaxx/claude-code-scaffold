# Implementation Plan: guard-workspace bare-slash false-positive

> Feature: bts-147-guard-workspace-bare-slash
> Work: linear:BTS-147
> Created: 1777083046
> Spec hash: 081ea8eb
> Based on: docs/spec.md

## Objective

Make the workspace fence ignore bare `/` tokens by tightening the absolute-path case glob from `/*)` to `/?*)`, so commands containing literal standalone slashes (jq format strings, shell math) no longer trip the hook.

## Sequence

### Step 1: Add regression tests for the bare-`/` false-positive (RED)
- **Test:** In `hub/tests/guard-hooks.bats`, add cases targeting AC-1, AC-3, AC-5, AC-6:
  - AC-1: `bash script | jq '\(.a) / \(.b)'` → exit 0
  - AC-3: `cat /etc/foo | jq '\(.a) / \(.b)'` → exit 2 (real path wins)
  - AC-5: `ALLOW_OUTSIDE_WORKSPACE=1 jq '\(.a) / \(.b)'` → exit 0 (bypass still works — verb is `bash`-equivalent only if present; the bypass should pre-empt regardless)
  - AC-6: `rm /a` → exit 2 (single-char absolute path still gets whitelist-checked)
- **Implement:** No code change yet. Run the suite. Confirm AC-1 fails (exit 2) — this proves the bug.
- **Files:** `hub/tests/guard-hooks.bats`
- **Verify:** `bash .ccanvil/scripts/bats-report.sh -f 'bare slash'` shows AC-1 failing for the right reason.

### Step 2: Fix the case glob (GREEN)
- **Test:** AC-1 from Step 1, plus all 16 existing BTS-146 cases.
- **Implement:** In `.claude/hooks/guard-workspace.sh` line 61, change `/*)` → `/?*)`.
- **Files:** `.claude/hooks/guard-workspace.sh`
- **Verify:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green; new cases pass; BTS-146 cases unchanged.

### Step 3: Dogfood + close
- **Test:** Run `bash .ccanvil/scripts/context-budget.sh check` (the original failing invocation in the prior session) without `ALLOW_OUTSIDE_WORKSPACE=1`. Should now succeed.
- **Implement:** No code change. Manual verification.
- **Files:** None.
- **Verify:** Command exits 0 cleanly. Confirms the bug-discovery path is now resolved.

## Risks

- **Glob semantics surprise.** `?` in shell glob is "any single char," not "optional." Risk of misreading. Mitigation: AC-6 (`rm /a`) explicitly verifies that single-char paths still go through the whitelist.
- **Other tokenizer edge cases surface.** This fix narrows one symptom. Other documented limitations (variable indirection, relative-path traversal) remain — out of scope per spec, but worth flagging if they appear.

## Definition of Done

- [ ] All 6 acceptance criteria from spec pass
- [ ] All existing tests still pass (1058 baseline → ~1062 expected)
- [ ] Hook header comment unchanged (limitations doc still accurate)
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
