# Implementation Plan: Provider-neutral work identity

> Feature: bts-130-work-identity
> Created: 1776973070
> Spec hash: bd040012
> Based on: docs/spec.md

## Objective

Introduce a provider-neutral `Work:` reference and stasis `Kind:` discriminator as the canonical coordination layer across spec / plan / stasis / branch / filename, routed through the existing `operations.sh` provider abstraction. Solve BTS-120 structurally; generalize BTS-124; unblock BTS-119.

## Sequence

### Phase 1 — Foundation: metadata + status

### Step 1: Extract `work` from metadata

- **Test:** `parse_metadata` on a fixture containing `> Work: linear:BTS-130` emits `.work == "linear:BTS-130"`. Fixture without the line emits `.work == ""`.
- **Implement:** Extend `parse_metadata()` in `.ccanvil/scripts/docs-check.sh:81` to pick up the `> Work:` line alongside the existing `> Feature:` / `> Plan hash:` lines.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/metadata-work.bats` (new)
- **Verify:** `bats hub/tests/metadata-work.bats` green; existing `feature-lifecycle.bats` unaffected.

### Step 2: Extract `kind` from stasis metadata

- **Test:** `parse_metadata` on a stasis fixture with `> Kind: session` emits `.kind == "session"`. Absence → `.kind == ""` (downstream defaults to "feature").
- **Implement:** Extend `parse_metadata()` to pick up `> Kind:` on stasis reads. Keep it scoped to stasis (don't surface on spec/plan where it would be meaningless).
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/metadata-work.bats` (extend)
- **Verify:** New assertions pass.

### Step 3: Surface `work` + `kind` in `status` JSON

- **Test:** `docs-check.sh status` JSON includes `.spec.work`, `.plan.work`, `.stasis.work`, and `.stasis.kind` when present; empty string otherwise.
- **Implement:** Extend `cmd_status()` (line 239) to populate the new fields from `parse_metadata` output.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/status.bats` (extend if present, else new test)
- **Verify:** `bats hub/tests/` green — AC-5, AC-6 satisfied.

### Phase 2 — Provider-neutral resolver

### Step 4: Slug-derivation helper

- **Test:** `slug_from_work_id "linear:BTS-130"` → `bts-130`. `slug_from_work_id "local:idea-29"` → `idea-29`. `slug_from_work_id "github:owner/repo#123"` → `owner-repo-123` (replace non-safe chars).
- **Implement:** Add pure-bash helper `slug_from_work_id()` in `.ccanvil/scripts/operations.sh` near `linear_state_id` (line 329). Lowercase the id; replace `[^a-z0-9-]` with `-`; collapse runs of `-`.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/work-resolve.bats` (new)
- **Verify:** Helper unit tests green.

### Step 5: `work.resolve` — Linear provider path

- **Test:** `operations.sh resolve work.resolve BTS-130` on a Linear-configured fixture returns JSON with `provider=linear`, `id=BTS-130`, `slug=bts-130`, `url` populated (URL format: `https://linear.app/<workspace>/issue/BTS-130`). Same test with explicit `linear:BTS-130` input.
- **Implement:** Add `work.resolve)` branch in `cmd_resolve()` (line 560). Read provider config; if routing points to `linear` OR input has `linear:` prefix, emit Linear-shape JSON. URL can be synthesized from workspace + id — if the workspace slug isn't in config, emit `url=""` and log a soft warning.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/work-resolve.bats` (extend)
- **Verify:** AC-1, AC-3 Linear branch pass.

### Step 6: `work.resolve` — local provider path

- **Test:** `operations.sh resolve work.resolve idea-29` on a local-configured fixture → `provider=local`, `id=idea-29`, `slug=idea-29`, `url=""`. Same for explicit `local:idea-29`.
- **Implement:** Add local branch to `work.resolve`. No MCP required; slug derivation is sufficient.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/work-resolve.bats` (extend)
- **Verify:** AC-2, AC-3 local branch pass.

### Step 7: `work.resolve` — error path

- **Test:** `operations.sh resolve work.resolve ""` exits non-zero with a clear error message pointing at the missing arg.
- **Implement:** Arg validation at the top of the `work.resolve)` branch.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/work-resolve.bats` (extend)
- **Verify:** AC-4 passes.

### Phase 3 — Validator alignment

### Step 8: Validator aligns on `Work:` equality

- **Test:** Spec+plan+stasis all carrying `Work: linear:BTS-130` → `aligned`. One doc carrying a different `Work:` value → `mismatched`.
- **Implement:** In `cmd_validate()` (line 261), when `work` is present on at least two feature docs, use string equality on `work` as the alignment key (in place of `feature_id` when both are available). Keep `feature_id` alignment as a fallback (see step 10).
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/validate-work-alignment.bats` (new)
- **Verify:** AC-7, AC-8 pass.

### Step 9: Session-kind stasis excluded from feature alignment — BTS-120 fix

- **Test:** Spec+plan on a branch with `Work: linear:BTS-130` AND a lingering stasis with `Kind: session` (from prior session boundary) → `aligned`. The session stasis is not treated as a peer to spec/plan.
- **Implement:** When collecting fids/works for alignment, skip any stasis where `kind == "session"`. Document in the function's header comment that session-kind stasis is ambient state, not feature state.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/validate-work-alignment.bats` (extend)
- **Verify:** AC-9 passes — BTS-120 payoff.

### Step 10: Legacy grandfather — fallback to `feature_id`

- **Test:** Spec+plan with only `> Feature:` metadata (no `Work:`) and identical feature_ids → `aligned`. Different feature_ids → `mismatched`. Preserves existing projects unchanged.
- **Implement:** Validator's alignment key selection: prefer `work` when all present docs have it; fall back to `feature_id` when any present doc lacks `work`. Document the cutover rule: `/spec` enforces `Work:` on new specs; validate grandfathers existing ones.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/validate-work-alignment.bats` (extend); sanity-check existing `feature-lifecycle.bats` still passes.
- **Verify:** AC-10 passes; no regressions in the 808 existing tests.

### Phase 4 — /spec enforcement

### Step 11: `/spec` rejects without work ref

- **Test:** (bats fixture-driven) `/spec "my cool thing"` without a leading work ref and no `idea <num>` form is rejected; the skill emits a pointer to `/idea <text>` or `/spec <work-ref> <description>`.
- **Implement:** Update `.claude/skills/spec/SKILL.md` to require a work ref arg. Runtime check happens in the skill logic (Claude reads args, calls `operations.sh resolve work.resolve <arg1>`, halts if resolution fails).
- **Files:** `.claude/skills/spec/SKILL.md`, `hub/tests/spec-skill-enforcement.bats` (new — tests the skill's bash-callable helper if one is introduced; otherwise asserts the doc reflects the requirement)
- **Verify:** AC-11 passes.

### Step 12: `/spec` resolves ref, writes slug-prefixed filename with `Work:` metadata

- **Test:** `/spec BTS-130 add cool feature` resolves via `work.resolve`, writes `docs/specs/bts-130-add-cool-feature.md` with `> Work: linear:BTS-130` and `> Feature: bts-130-add-cool-feature`. Local equivalent: `/spec idea-29 ...` → `docs/specs/idea-29-....md` with `> Work: local:idea-29`.
- **Implement:** Spec skill instructs Claude to: (a) resolve work ref; (b) derive slug; (c) generate feature_id as `<slug>-<kebab-name>`; (d) write file at `docs/specs/<feature_id>.md` with new metadata. AC-14 falls out: `activate` derives branch from feature_id, so `claude/feat/bts-130-add-cool-feature` contains `bts-130` substring — satisfies Linear auto-link.
- **Files:** `.claude/skills/spec/SKILL.md`, `hub/tests/spec-skill-enforcement.bats` (extend), fixture specs.
- **Verify:** AC-12, AC-13, AC-14 pass.

### Phase 5 — /stasis kind discriminator

### Step 13: `/stasis` writes `Kind:` (feature vs session) and conditional `Work:`

- **Test:** With an active spec+plan on the branch → stasis metadata contains `> Kind: feature` and `> Work: <ref-from-spec>`. Without an active spec+plan (main branch, between features) → `> Kind: session`, no `> Work:`.
- **Implement:** Update `.claude/skills/stasis/SKILL.md`: detect spec+plan presence via `docs-check.sh status`; pick kind accordingly; inherit `Work:` from spec when feature-kind. Update `.ccanvil/templates/stasis.md` to include both metadata lines.
- **Files:** `.claude/skills/stasis/SKILL.md`, `.ccanvil/templates/stasis.md`, `hub/tests/stasis-kind.bats` (new)
- **Verify:** AC-15, AC-16 pass. Existing stasis-related tests unaffected (the new fields are additive; parse_metadata step 2 already handles both present and absent).

### Phase 6 — Templates & documentation

### Step 14: Update templates + skill docs + command reference

- **Test:** Template files (`spec.md`, `plan.md`, `stasis.md`) include the new metadata fields. Skill docs describe the enforcement and kind-discrimination behavior. `command-reference.md` documents the `work.resolve` verb and the `Work:` / `Kind:` schema.
- **Implement:**
  - `.ccanvil/templates/spec.md`: add `> Work:` line after `> Feature:`.
  - `.ccanvil/templates/plan.md`: same.
  - `.ccanvil/templates/stasis.md`: already updated in Step 13; double-check.
  - `.claude/skills/spec/SKILL.md`: update `ARGUMENTS` section, rewrite Step 5 (feature_id derivation) to reflect slug-prefixed naming.
  - `.claude/skills/stasis/SKILL.md`: document kind detection.
  - `.ccanvil/guide/command-reference.md`: add `work.resolve` to operations table; add `Work:` / `Kind:` to metadata schema section.
- **Files:** listed above.
- **Verify:** Manual read-through; existing suite stays green.

## Risks

- **Breaking existing bats fixtures**: many fixture spec/plan files use `feature_id` only. The grandfather clause (step 10) protects them, but tests that construct fixtures with explicit `> Work:` while others don't may create misaligned expectations. **Mitigation**: introduce work-aware tests in dedicated new files; touch existing fixtures only when necessary to prevent validator regression.
- **Bootstrap self-reference**: this spec itself carries `> Work: linear:BTS-130`. Once step 8 ships and validator aligns on `work`, our own spec+plan must align. Since both are authored together in this session, they will — but any session restart before step 13 (/stasis) needs to avoid writing a stasis with mismatched `Work:`. **Mitigation**: manually set `> Work: linear:BTS-130` and `> Kind: feature` on any stasis written mid-ship.
- **Session-stasis heuristic**: "no spec+plan present → session-kind" is simple but depends on `docs-check.sh status` returning truthful info. **Mitigation**: add explicit bats tests covering both branches in step 13.
- **Linear URL synthesis**: the resolver needs a workspace slug to emit a valid URL. If `.claude/ccanvil.local.json` doesn't contain one, emit `url=""` rather than guessing. **Mitigation**: soft-warning log line; downstream consumers treat empty URL as "not available."
- **Slug collisions**: two specs with the same slug prefix (e.g., two features for BTS-130) would clash on filename. **Mitigation**: feature_id includes the kebab name suffix (`bts-130-work-identity` vs `bts-130-phase-2`), so collisions are intentional-rename-only, not accidental.

## Definition of Done

- [ ] All 18 acceptance criteria from spec pass
- [ ] Full bats suite green (≥ 808 existing + new tests)
- [ ] No regressions in `/idea` skill flow
- [ ] `docs-check.sh validate` on this branch returns `aligned`
- [ ] Code reviewed via `/review`
- [ ] PR finalized via `/pr`

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
