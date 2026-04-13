---
name: idea
description: Capture an idea quickly, list ideas, or triage untriaged ideas against the roadmap.
---

Capture, list, or triage project ideas.

## Usage

- `/idea <text>` — capture an idea (default action)
- `/idea list` — show all ideas
- `/idea triage` — review untriaged ideas against roadmap

## Capture (default)

If the argument is NOT `list` or `triage`, treat everything after `/idea` as the idea text.

1. Run: `bash .ccanvil/scripts/docs-check.sh idea-add "<text>"`
2. Confirm: "Captured. N untriaged ideas total." (run `idea-count` to get N)
3. **Return to whatever was in progress. Do NOT discuss the idea further unless asked.**

## List

1. Run: `bash .ccanvil/scripts/docs-check.sh idea-list`
2. Display as a table: ID | Created | Idea | Status

## Triage

1. Run: `bash .ccanvil/scripts/docs-check.sh idea-list --status new`
2. Read `docs/roadmap.md` (if it exists) for strategic context
3. Run: `bash .ccanvil/scripts/operations.sh exec backlog.list` for existing backlog
4. For each untriaged idea, recommend one of:
   - **promote** — create a Linear ticket and/or spec (idea is actionable and aligned)
   - **merge** — overlaps with an existing ticket (name the ticket)
   - **park** — add to roadmap Horizon section (good idea, not yet)
   - **dismiss** — not aligned with project direction
5. Present recommendations as a table. Ask for approval.
6. For each approved recommendation, run: `bash .ccanvil/scripts/docs-check.sh idea-update <uid> <status>`
7. For promoted ideas, create the Linear ticket.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
