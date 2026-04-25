# Feature: Fix BSD mktemp template in /permissions-review skill prose

> Feature: bts-160-fix-bsd-mktemp-template
> Work: linear:BTS-160
> Created: 1777139846
> Status: Complete

## Summary

`.claude/commands/permissions-review.md` uses `mktemp /tmp/pr-promote.XXXXXX.json` and a sibling `pr-check` template. BSD `mktemp` (macOS default) only substitutes the `X` characters when they sit at the END of the template — with `.json` trailing, the substitution doesn't fire and the tmpfile is created with the literal name `/tmp/pr-promote.XXXXXX.json`. Concurrent invocations would collide; observed empirically during the BTS-149 walk-through. The fix replaces the templates with `mktemp -t <prefix>` form, which is BSD/GNU-portable and writes to `$TMPDIR` with a random suffix.

## Job To Be Done

**When** I run `/permissions-review` (especially in any future multi-session or multi-agent scenario),
**I want to** have unique tmpfile paths for `pr-promote`, `pr-check`, and the decisions buffer,
**So that** concurrent invocations cannot collide on a literal filename and the skill behaves deterministically.

## Acceptance Criteria

- [ ] **AC-1:** All `mktemp` invocations in `.claude/commands/permissions-review.md` use the BSD-compatible `mktemp -t <prefix>` form. No `XXXXXX.<ext>` mid-template patterns remain.
- [ ] **AC-2:** Step 1 ("Gather state") creates `PR_PROMOTE` and `PR_CHECK` via `mktemp -t pr-promote` and `mktemp -t pr-check` respectively.
- [ ] **AC-3:** Step 5 ("Dispatch") includes an explicit `mktemp -t pr-decisions` invocation for the JSONL buffer (currently implicit — must be made explicit to close the third mktemp gap called out in BTS-160's body).
- [ ] **AC-4:** Step 6 ("Cleanup") still removes all three tmpfiles by referencing the same variables (`PR_PROMOTE`, `PR_CHECK`, decisions tmpfile var).
- [ ] **AC-5 (edge — concurrent invocation):** Two `/permissions-review` runs started in parallel produce six distinct tmpfile paths with random suffixes. No literal `XXXXXX` strings appear in any tmpfile name.
- [ ] **AC-6 (manual verification):** Running `/permissions-review` once from a clean state and inspecting the resolved `$PR_PROMOTE`, `$PR_CHECK`, and decisions buffer paths shows three unique non-literal paths in `$TMPDIR`.

## Affected Files

| File | Change |
|------|--------|
| `.claude/commands/permissions-review.md` | Modified — three `mktemp` invocations updated to `-t <prefix>` form; step 5 prose made explicit about the decisions tmpfile |

## Dependencies

- **Requires:** Nothing. Skill prose edit only.
- **Blocked by:** Nothing.

## Out of Scope

- Refactoring step 5's dispatch logic beyond the mktemp invocation.
- Migrating any other skill that uses BSD-incompatible mktemp templates (separate audit, separate ticket if the pattern recurs).
- Adding automated tests — this is a prose-only skill change. Verification is manual per AC-6.

## Implementation Notes

- Pattern: `PR_PROMOTE=$(mktemp -t pr-promote)`. BSD `mktemp -t` accepts a prefix and writes to `$TMPDIR` (typically `/tmp` on macOS) with a random suffix. The file extension (`.json`, `.jsonl`) is irrelevant — content type is determined by the substrate (`permissions-audit.sh check --json` writes JSON regardless of filename).
- BTS-160's body documents the alternatives (Option A: trailing X's + rename; Option C: `--suffix` flag). Option B (`-t prefix`) is the chosen fix — cleanest, single-line, portable.
- This is a non-functional fix on the success path: in the single-user-single-session use case the literal-filename bug is benign. The fix matters for race-safety under any concurrent invocation, and as a deterministic-correctness baseline.
- After editing, manually invoke `/permissions-review` from a clean state to verify the three paths resolve to unique non-literal tmpfiles. No bats coverage exists for skill-prose files (skills are not unit-tested at the prose level), so verification is manual + inspection.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
