# Feature: Provider-neutral work identity

> Feature: bts-130-work-identity
> Work: linear:BTS-130
> Created: 1776973070
> Status: In Progress

## Summary

ccanvil's `feature_id` is a preset-local kebab slug that doesn't map to the actual source of truth for work across providers (Linear, local JSONL, future GitHub/Jira/Shortcut bolt-ons). This creates coordination friction: session-boundary stasis hijacks the `feature_id` slot and trips the validator (BTS-120); filenames and branches lack the ticket substring Linear's GitHub integration needs (BTS-124, BTS-119). This feature introduces a provider-neutral `Work:` reference as the canonical coordination key across all lifecycle artifacts, routed through the existing `operations.sh` provider abstraction.

## Job To Be Done

**When** I start feature work on any ccanvil node (Linear-provider or local-provider),
**I want to** use the provider's native identifier (e.g., `BTS-130` or `idea-29`) as the canonical key across spec / plan / stasis / branch / filename,
**So that** lifecycle artifacts coordinate with the provider's source of truth — enabling auto-linking, auto-close, and cross-system traceability without preset-specific adapters per provider.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Layer 1 — work.resolve operation

- [ ] **AC-1:** `operations.sh resolve work.resolve BTS-130` on a Linear-provider node returns JSON with `provider="linear"`, `id="BTS-130"`, `slug="bts-130"`, and a non-empty `url`.
- [ ] **AC-2:** `operations.sh resolve work.resolve idea-29` on a local-provider node returns JSON with `provider="local"`, `id="idea-29"`, `slug="idea-29"`.
- [ ] **AC-3:** `operations.sh resolve work.resolve linear:BTS-130` (explicit provider prefix) returns Linear-shape output on ANY node — the explicit prefix overrides routing config.
- [ ] **AC-4 (error):** `operations.sh resolve work.resolve` with an empty arg exits non-zero with a clear error message.

### Layer 2 — metadata schema

- [ ] **AC-5:** `docs-check.sh status` JSON emits a `work` field per lifecycle doc (spec, plan, stasis) when `> Work:` is present in metadata. Empty string when absent.
- [ ] **AC-6:** Stasis metadata supports a `> Kind:` field with values `feature` or `session`; `docs-check.sh status` surfaces it as `stasis.kind`. Absence is treated as `feature` (backward-compat).

### Layer 3 — validator

- [ ] **AC-7:** `docs-check.sh validate` with spec+plan+feature-stasis all carrying identical `Work: linear:BTS-130` returns `result="aligned"`.
- [ ] **AC-8:** Differing `Work:` strings across feature docs return `result="mismatched"`.
- [ ] **AC-9 (BTS-120 payoff):** A session-kind stasis (`> Kind: session`, no `> Work:`) on a branch with a feature-kind spec+plan returns `result="aligned"` — session-stasis is excluded from feature alignment.
- [ ] **AC-10 (legacy grandfather):** Specs/plans without `> Work:` metadata fall back to `feature_id`-based alignment (preserves existing projects; new cutover happens at /spec creation, not at validate).

### Layer 4 — /spec enforcement

- [ ] **AC-11:** `/spec <description>` (no work ref) on a provider-configured node is rejected with a clear error directing to `/idea <text>` or `/spec <work-ref>`.
- [ ] **AC-12:** `/spec BTS-130 <description>` on a Linear node resolves via `work.resolve`, writes `docs/specs/<slug>-<kebab-name>.md` with `> Work: linear:BTS-130` in metadata.
- [ ] **AC-13:** `/spec idea-29 <description>` on a local node resolves similarly, writes `docs/specs/idea-29-<kebab-name>.md`.

### Layer 5 — branch convention

- [ ] **AC-14:** `docs-check.sh activate <spec-file>` creates a branch whose name contains the provider slug as a substring (e.g., `bts-130` appears in `claude/feat/bts-130-work-identity` or equivalent). Linear's GitHub-integration matcher is substring-based (per BTS-121 empirical evidence), so this is the integration gate.

### Layer 6 — /stasis kind

- [ ] **AC-15:** Mid-feature `/stasis` writes `> Kind: feature` and `> Work: <ref>` (inherited from spec).
- [ ] **AC-16:** Session-boundary `/stasis` (on main, no active spec) writes `> Kind: session`, no `> Work:` field.

### Layer 7 — regression coverage

- [ ] **AC-17:** Full bats suite stays green (≥ 808 current baseline, plus new tests for the above).
- [ ] **AC-18:** `/idea` skill flow is unaffected — existing idea capture/triage tests continue to pass.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | New `work.resolve` verb; provider-routed |
| `.ccanvil/scripts/docs-check.sh` | `parse_metadata` extracts `work` + `kind`; `status` + `validate` honor new fields; activate uses slug in branch name |
| `.ccanvil/templates/spec.md` | Add `> Work:` metadata line to template |
| `.ccanvil/templates/plan.md` | Add `> Work:` metadata line to template |
| `.ccanvil/templates/stasis.md` | Add `> Work:` + `> Kind:` metadata lines |
| `.claude/skills/spec/SKILL.md` | Require work ref; enforce at creation |
| `.claude/skills/stasis/SKILL.md` | Differentiate feature-kind vs session-kind writes |
| `.ccanvil/guide/command-reference.md` | Document `Work:` schema + `work.resolve` verb |
| `hub/tests/*.bats` | New tests for each AC; update existing fixtures to include `> Work:` where relevant |

## Dependencies

- **Requires:** Linear MCP provider already wired (shipped BTS-121). Local provider already functional.
- **Blocked by:** None.

## Out of Scope

- **Cross-provider migration**: projects moving local → Linear mid-lifecycle are not supported in this spec. A follow-up can address it if needed.
- **Retrofitting legacy specs** in `docs/specs/` archive with `Work:` metadata — the grandfather clause (AC-10) covers them via feature_id fallback.
- **Auto-close on PR merge** (BTS-119) — unblocked by this spec but shipped separately.
- **`ticket.transition` wrapper** (BTS-128) — adjacent infra, shipped separately.

## Implementation Notes

- Work reference parsing: `<provider>:<id>` format. Provider names are lowercase alphanumeric; id format is provider-specific (Linear: `TEAM-N`; local: `idea-<n>`).
- Slug derivation: lowercase the id, replace non-filesystem-safe chars with `-` (e.g., `BTS-130` → `bts-130`; future `github:owner/repo#123` → `owner-repo-123`).
- `work.resolve` routing: same pattern as `idea.add` — reads `.claude/ccanvil.local.json` provider config, branches on `integrations.routing.idea` (rename to `integrations.routing.work` in a follow-up if the idea/work namespaces diverge).
- Validator priority: `mismatched > stale-plan > stale-stasis > missing-work-ref > missing-determinism-review > aligned`. `missing-work-ref` fires only when feature docs exist WITHOUT `Work:` AND without a `feature_id` fallback.
- Enforcement cutover: /spec rejects new work without a ref; validator grandfathers existing specs. This preserves Zach's existing fucina + luxlook downstream projects without forcing a migration step.
- Stasis dual-mode: the /stasis skill inspects whether a spec+plan are active on the current branch. Spec+plan present → feature-kind. None present (main branch, between features) → session-kind.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
