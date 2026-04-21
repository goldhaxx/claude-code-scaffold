---
name: stasis
description: End-of-session strategic review — freeze a snapshot of session/project state before /compact so cross-session context survives compaction.
---

Run at the end of a session, immediately before `/compact`. Writes `docs/stasis.md` — the strategic microscope/macroscope that captures determinism review, security review, cross-session patterns, and memory candidates that compaction would otherwise lose.

`/stasis` is the counterpart to `/recall`: stasis writes, recall reads.

## Pre-flight halt check

1. Run `bash .ccanvil/scripts/docs-check.sh validate` and read the `.result` field.
   - If the result is `aligned` or `missing-determinism-review` → continue.
   - If the result is `stale-plan`, `mismatched`, `unlinked`, or any other non-aligned state → **STOP**. Report the validate output to the user and ask them to fix the lifecycle state before running stasis. Do not write a clean snapshot on top of a broken lifecycle.

## Data gathering (deterministic)

Collect these inputs via scripts — all deterministic, all cheap:

2. `bash .ccanvil/scripts/docs-check.sh status` — feature_id, plan_hash, content hashes for spec/plan/stasis.
3. `bash .ccanvil/scripts/docs-check.sh radar-gather` — active spec, completed specs, idea counts, roadmap theme, git activity, backlog.
4. `bash .ccanvil/scripts/docs-check.sh idea-count` — untriaged idea count for the Next Steps section.
5. `bash .ccanvil/scripts/docs-check.sh audit-session --since <last-stasis-commit>` — scan git diffs for stochastic patterns (fallback to last 20 commits if no prior stasis).
6. `bash .ccanvil/scripts/docs-check.sh legacy-refs-scan` — check for stale references to legacy verbs/artifacts (fuels Cross-Session Patterns).
7. `bash .ccanvil/scripts/permissions-audit.sh check` (if available) — classify any DANGER or UNREVIEWED permissions.
8. `bash .ccanvil/scripts/context-budget.sh check` (if available) — context budget HEALTHY/WARNING/CRITICAL.
9. `git log --oneline -20` — recent commit history.
10. `git show HEAD~1:docs/stasis.md 2>/dev/null || true` — the prior stasis snapshot, if any. If the command fails (no prior), proceed and note "First stasis — no prior state to compare" in the Cross-Session Patterns section.

## Synthesis — write docs/stasis.md

Copy `.ccanvil/templates/stasis.md` to `docs/stasis.md` and fill each section:

### ## Accomplished
What was completed this session. Use git log + file changes as the factual spine, your own session memory for the narrative.

### ## Current State
- **Branch:** current branch
- **Tests:** result of the project's test suite
- **Uncommitted changes:** summary from `git diff --stat`
- **Build status:** clean / errors (state any failing steps)

### ## Blocked On
Anything preventing progress. "Nothing" if clean.

### ## Next Steps
Explicit numbered next actions when resuming. Pull from radar-gather's roadmap "Up Next" + spec backlog state + untriaged idea count.

### ## Context Notes
Decisions made, alternatives considered, failed approaches. Anything the next session needs to know that isn't in git history or the code itself.

### ## Determinism Review
Follow `.claude/rules/self-review.md`. Review operations from this session; flag ones that should become scripts/hooks. Fill `operations_reviewed: <count>`, `candidates_found: <count>`, plus a bullet per candidate or "No candidates this session." **This section is mandatory** — validate will flag it as missing-determinism-review if empty.

### ## Cross-Session Patterns
Compare this session to the prior stasis (from step 10):
- Any determinism-review candidate that appeared last session AND this session → flag as a recurring pattern.
- Any audit-session finding that also appeared last time → flag.
- Surface any matches from `legacy-refs-scan` (step 6). Split by scope: `hub-owned` (fix at the hub) vs `node-specific` (fix in the node). If all matches are hub-owned, note "Next /ccanvil-pull will resolve."
- If `git show HEAD~1:docs/stasis.md` failed in step 10, state: "First stasis — no prior state to compare."
- If no recurring patterns found, state: "No recurring patterns."

### ## Security Review
Prefer the `security-audit` skill if available — invoke it and summarize the finding.
Fallback: grep the session's diff for secret/PII patterns (tokens, private keys, emails in non-.example files, etc.). Report `PASS` or a bullet list of findings.

### ## Memory Candidates
List insights that meet auto-memory criteria:
- Non-obvious feedback the user gave.
- Surprising project facts you learned.
- External references (Linear tickets, Slack channels, dashboards, docs).
- Patterns the user validated explicitly ("yes, exactly that").

If none: "No candidates this session."

## Commit the snapshot

11. Stage and commit `docs/stasis.md`:
    ```bash
    ALLOW_MAIN=1 git add docs/stasis.md
    ALLOW_MAIN=1 git -c commit.gpgsign=false commit -m "docs: stasis <feature-id>"
    ```
    The `ALLOW_MAIN=1` bypass is required because `protect-main.sh` otherwise blocks direct commits to main — and stasis commits are a deliberate exception (they capture state at a boundary, not feature work).

## Close

12. Final output must end with a single explicit next-action directive:
    ```
    Run `/compact` to wrap session.
    ```

## Rules

- `/stasis` is a write command. It writes exactly one file (`docs/stasis.md`), commits it, and nothing else.
- Never write a stasis on top of a non-aligned lifecycle state — halt per the pre-flight check.
- Never run `/compact` as part of stasis. Compaction is the user's next explicit action.
- Keep the synthesis tight. The stasis is a briefing, not a novel — every section should survive a cold read in the next session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
