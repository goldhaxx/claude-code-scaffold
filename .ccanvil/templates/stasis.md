# Stasis

> Feature: [feature-id or session-YYYY-MM-DD-<slug>-ship]
> Work: [provider:id — only on feature-kind stasis; omit on session-kind]
> Kind: [feature | session]
> Last updated: [epoch]
> Session: [N — monotonic counter from .ccanvil/state/session-counter, sourced via `docs-check.sh session-info`. Omit if counter=0 (fresh node).]
> Boundary: [ISO-8601 local timestamp from .ccanvil/state/session-boundary, e.g. 2026-04-26T18:44:36-07:00. Omit if unavailable.]
> Plan hash: [hash — only on feature-kind stasis]
> Session objective: [what we set out to do]
<!-- Reminder: if no plan exists yet, run /plan before /stasis (plan before stasis). -->
<!-- Kind: `feature` when an active spec+plan exists (mid-feature stasis); `session` when on main between features (ambient session-boundary stasis). Session-kind stasis is excluded from validator feature alignment. -->
<!-- Work: mirrors the active spec's `> Work:` when Kind=feature; omitted when Kind=session. -->

## Accomplished

- [What was completed this session]

## Current State

- **Branch:** [branch name]
- **Tests:** [all passing / N failing — list which]
- **Uncommitted changes:** [yes/no — what]
- **Build status:** [clean / errors — what]

## Blocked On

- [Any issues preventing progress]

## Next Steps

1. [Exact next action to take when resuming]
2. [Following action]
3. [...]

## Context Notes

[Anything the next session needs to know that isn't captured elsewhere — failed approaches, decisions made, alternatives considered]

## Determinism Review

- **operations_reviewed:** [count]
- **candidates_found:** [count]
- [For each candidate: **[operation]**: Claude [what happened]. Should be [deterministic replacement]. Impact: [high/medium/low].]
- [If no candidates: "No candidates this session."]

## Evidence Gaps

[BTS-201: bug-shape captures from this session lacking the four evidence anchors (Command:, Output:, Exit:, Reproduce:). One bullet per gap: `- BTS-X — <title> — <reason>`. If no gaps: `No evidence gaps this session.` — keep this literal verbatim so /recall can parse the empty state.]

No evidence gaps this session.

## Cross-Session Patterns

[Any determinism-review candidates or audit-session findings that also appeared in the previous stasis. Run `docs-check.sh legacy-refs-scan` as part of this check. If no prior stasis exists: "First stasis — no prior state to compare." If no patterns: "No recurring patterns."]

## Security Review

[Run the project's security scan (via `security-audit` skill if present, else static grep for secrets/PII keywords in the session's diff). Report `PASS` or a bullet list of findings.]

## Memory Candidates

[List insights that meet auto-memory criteria — non-obvious feedback, surprising project facts, external references. If none: "No candidates this session."]

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
