# Feature: [Name]

> Feature: [feature-id]
> Work: [provider:id e.g. linear:BTS-130 or local:idea-29]
> Created: [epoch]
> Status: Draft | In Progress | Complete

<!-- Work: is the canonical coordination key. `feature-id` should be derived as `<slug>-<kebab-name>` where slug comes from `operations.sh resolve work.resolve <ref>`. Legacy specs without Work: are grandfathered by the validator. -->

<!-- Subject: (BTS-236) optional — auto-populated by `stamp-spec` from this file's H1 (form `# Feature: <name>`). Used by cmd_derive_pr_title as the canonical PR subject after the `feat(<feature-id>):` prefix. Cap ≤72 chars (auto-truncated with word-boundary walkback). Override manually by editing the metadata block. Legacy specs without Subject: fall back to first-line-of-Summary truncation. -->

## Summary

[One paragraph: what this feature does and why it matters to the user.]

## Job To Be Done

**When** [situation/trigger],
**I want to** [action/capability],
**So that** [outcome/benefit].

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** [When X, then Y]
- [ ] **AC-2:** [Given A and B, when C, then D]
- [ ] **AC-3:** [Error: when X fails, user sees Y and system does Z]
- [ ] **AC-4:** [Edge: when input is empty/null/maximum, behavior is Z]

## Affected Files

| File | Change |
|------|--------|
| `src/...` | New / Modified / Deleted |
| `src/__tests__/...` | New test file |

## Dependencies

- **Requires:** [prerequisites that must exist first]
- **Blocked by:** [external blockers]

## Out of Scope

- [Explicit boundary: what this feature does NOT do]

## Implementation Notes

- [Pattern to follow: "Same shape as src/services/existing.ts"]
- [Technical constraints or gotchas]
- [Performance requirements if any]

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
