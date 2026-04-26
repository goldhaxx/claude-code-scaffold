# Feature: drift-watchdog (Claude Code-native scheduled agent)

> Feature: bts-21-drift-watchdog
> Work: linear:BTS-21
> Created: 1777226176
> Status: In Progress

## Summary

Build a Claude Code-native scheduled agent that detects drift between the hub and registered downstream nodes and opens idempotent Linear issues per drift via the http substrate. Two-layer architecture: deterministic detection via a new `ccanvil-sync.sh drift-watchdog-list` subcommand; stochastic interpretation via a new `drift-analyst` sub-agent that reads drift JSON + recent git log + roadmap context and produces a thoughtful issue body. Hub-only pilot — no distribution to downstream nodes. The cron entry is created out-of-band by the operator using the exact command the skill prints; auto-cron-creation from skill code is deferred until CronCreate semantics are empirically validated.

## Job To Be Done

**When** I haven't manually checked downstream-node drift in over a week,
**I want to** have ccanvil run an autonomous weekly drift check and open a single thoughtful Linear issue per drifted node,
**So that** drift detection stops being "I'll get to it" and converts into a Triaged ticket I can decide about.

## Acceptance Criteria

- [ ] **AC-1:** `ccanvil-sync.sh drift-watchdog-list` emits a JSON array `[{node_uuid, node_name, drift_key, paths_drifted[], summary}, ...]`. `drift_key = sha256(node_name + ":" + sorted-paths-drifted-joined-by-newline) | head -c 16`. Empty array when no nodes drift.
- [ ] **AC-2:** `drift-watchdog-list` is read-only — never mutates the registry, never writes to any downstream node, never commits. Drift-guard test asserts no `git -C` writes, no `>` redirections to registry/node paths, no commit invocations within the function.
- [ ] **AC-3:** A new sub-agent `.claude/agents/drift-analyst.md` (sonnet, tools restricted to Read + Grep + Glob + `Bash(git log:*)`) exists with a frontmatter description matching the skill prose. Drift-guard test asserts the agent file's frontmatter parses cleanly and the `tools:` list is exactly the four entries above.
- [ ] **AC-4:** `.claude/skills/drift-watchdog/SKILL.md` exists with prose orchestrating: (1) call `drift-watchdog-list`, (2) per drifted node, spawn the `drift-analyst` agent with the drift JSON + recent git context + roadmap snippet, (3) dispatch Linear issue creation via `linear-query.sh save-issue` with `--label drift-watchdog`, title `[drift-watchdog] <node_name>: <drift_key>`, body from the agent's synthesis. Drift-guard test asserts the SKILL.md mentions all three steps and references `linear-query.sh save-issue` literally.
- [ ] **AC-5:** Idempotency: when the skill runs against the same drift state twice in a row, the second run produces zero new Linear issues. Implementation: before creating each issue, the skill resolves `idea.list` filtered by label=drift-watchdog, parses titles for the same `<drift_key>`, and skips creation if a match exists in any non-terminal state (Triage / Backlog / In Progress). Drift-guard test stubs `linear-query.sh` and asserts the second invocation produces zero create calls when the first invocation's stub-output is fed back as the listing source.
- [ ] **AC-6:** Pre-flight verification subcommand `ccanvil-sync.sh drift-watchdog-preflight` runs three smoke checks and emits JSON `{claude_p_loads_skills, linear_query_works_from_p_mode, croncreate_validated}` — each `true|false|skipped`. The first two run live (require human-verified ANTHROPIC_API_KEY + LINEAR_API_KEY availability); the third is `skipped` (CronCreate semantics validation deferred to a follow-up ticket). Test stubs the live commands.
- [ ] **AC-7:** Failure mode — if `linear-query.sh save-issue` fails (network/auth/server error), the skill appends a deterministic pending-log entry via `idea-pending-append --op add --title <title> --body <body>`. Drift-guard asserts the SKILL.md prose mentions the pending-log fallback and does not contain `wc -l` (count via `idea-pending-validate`).
- [ ] **AC-8:** Substrate purity — the skill MUST use http (`linear-query.sh save-issue`) for issue creation. Drift-guard test asserts the SKILL.md prose does NOT call `mcp__claude_ai_Linear__save_issue` directly, and the resolver invocation pattern matches the established `eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"` shape.
- [ ] **AC-9:** Cron-entry surfacing — running `bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-cron-print` emits the exact `CronCreate` invocation (or system-cron equivalent line) the operator should run, formatted for direct copy-paste. The skill's exit message references this subcommand. Drift-guard test asserts the printed command contains both the schedule expression (default: `0 9 * * 1` — Monday 9am) and `claude -p "/drift-watchdog"`.
- [ ] **AC-10:** Drift-watchdog issues are findable — each issue carries the `drift-watchdog` label so `idea.list --label drift-watchdog` returns only watchdog-created tickets. Test asserts the label is included in every `linear-query.sh save-issue` invocation emitted by the skill's prose pattern.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified (add `drift-watchdog-list`, `drift-watchdog-preflight`, `drift-watchdog-cron-print` subcommands) |
| `.claude/skills/drift-watchdog/SKILL.md` | New |
| `.claude/agents/drift-analyst.md` | New |
| `hub/tests/drift-watchdog.bats` | New (AC-1, AC-2, AC-5, AC-6, AC-9 — implementation tests) |
| `hub/tests/drift-watchdog-skill.bats` | New (AC-3, AC-4, AC-7, AC-8, AC-10 — drift-guard tests on skill + agent prose) |

## Dependencies

- **Requires:** ccanvil-sync.sh registry + diff substrate (existing); `linear-query.sh save-issue` with `--label` (existing); `idea-pending-append` (existing); `operations.sh resolve idea.list` (existing).
- **Blocked by:** none. Pre-flight verification step (AC-6) intentionally documents what's NOT validated yet (CronCreate semantics) so the operator can defer cron creation to a follow-up if the smoke-test surfaces issues.

## Out of Scope

- gh-aw migration. The skill prose + agent definition remain portable — if multi-user pain emerges later, port to a `.lock.yml` workflow then.
- Distributing the watchdog skill or agent to downstream nodes. Hub-only.
- Multi-user or off-laptop execution.
- Auto-creating the cron entry from skill code. Operator runs `drift-watchdog-cron-print` and creates the entry manually via `CronCreate` (or `crontab -e`).
- MCP-based issue creation. Per `BTS-183` strategic direction: ccanvil-substrate Linear ops use http exclusively.
- Cleaning up the dead-code MCP branches in `operations.sh` (`idea.promote/defer/dismiss/merge`, `backlog.get`, `ticket.find-by-title`). Captured in BTS-183.
- Stale-issue cleanup (issues whose drift has resolved). Future ticket — drift-watchdog only opens; humans triage and close.

## Implementation Notes

- `drift-watchdog-list` should iterate `.ccanvil/registry.json` nodes, call existing `cmd_diff` per node, summarize the diff per-node, and emit the JSON. Reuse `cmd_diff`'s output rather than reimplementing.
- The `drift-analyst` agent's body should be tight: receive `{node, drift_paths, recent_git_log, roadmap_summary}`, return a Markdown issue body with sections "What drifted", "Why this might matter (or not)", "Recommended action". Avoid telling it to "be thorough" — that produces noise. Use `model: sonnet` (cheap, fast, good enough for this synthesis).
- Idempotency check (AC-5) leverages existing `idea.list` http substrate. The drift-key in the title is the dedup key; never compose drift-keys with timestamps (would defeat dedup).
- Pre-flight (AC-6) is the explicit research-spike portion. The skill prose should also mention these checks should be re-run if Claude Code is upgraded — cheap to verify, expensive to discover broken at fire time.
- The `feedback_skip_review_on_trivial_diffs` rule does NOT apply here — this is substrate-tier work introducing new shapes (skill + agent + scripts). Run /review.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
