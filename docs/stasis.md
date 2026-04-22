# Stasis

> Feature: session-2026-04-22-ideas-to-linear-ship
> Last updated: 1776846000
> Plan hash: n/a (post-feature session; plan lived in PR #41 and was cleaned up at merge)
> Session objective: Ship ideas-to-linear (BTS-77/PR #41) end-to-end AND upgrade all 7 downstream nodes to the new Linear-backed `/idea` pipeline in the same session.

## Accomplished

- **Shipped PR #41 (`1b4295b`)** — `ideas-to-linear`: 30 AC across 7 TDD cycles + 2 packaging additions (setup scaffold + migration guide). 716/716 bats green, +65 new tests. 10 commits on `claude/feat/ideas-to-linear`. Squash-merged cleanly, local/origin aligned the entire way (first session in recent memory with a clean fast-forward land — the push-guard + config-hygiene built this session is what enabled it).
- **Dual-provider `/idea` pipeline** — `routing.idea = "local"` → `.ccanvil/ideas.log` (JSONL, gitignored); `routing.idea = "linear"` → Linear Triage via MCP with per-node `project` + `team`. Pending-log fallback for MCP failures, `/idea sync` drains it.
- **Pre-activate push-guard** — `docs-check.sh activate` halts when local `main` has unpublished commits; `--force-local-ahead` bypass for session-boundary artifacts.
- **Linear workspace setup** — custom statuses `Idea` + `Icebox` (Backlog category, BTS team); workspace label `idea` (#F2C94C); 7 new Linear projects, one per downstream.
- **7 downstream nodes fully upgraded** — unifi-toolbox, taxes, fieldnation-toolbox, caffeine-calculator, luxlook, whoop-toolbox, fucina. Each has its own Linear project, `idea-setup` executed, legacy `docs/ideas.md` migrated (where present), `.gitignore` updated.
- **35 legacy active ideas promoted to Linear** across the 4 nodes with untriaged content: BTS-79→88 (unifi, 10), BTS-89 (taxes, 1 new + 11 historical preserved local-only), BTS-90→112 (fieldnation, 23 new + 2 historical local-only). caffeine-calculator/luxlook/whoop-toolbox/fucina had no untriaged content.
- **BTS-78 end-to-end smoke test** — `/idea test capture via the new flow` from the hub created the issue in Linear Idea status with the `idea` label, verifying resolver → MCP → Linear path.
- **Downstream migration guide** — `.ccanvil/guide/ideas-migration.md` with the 6-step walkthrough. Included in broadcast. `idea-setup` scaffold command handles the per-node config + gitignore work.
- **Hub dogfood** — migrated the hub's own 31-line `docs/ideas.md` (29 entries) to `.ccanvil/ideas.log`, source removed.

## Current State

- **Branch:** `main` (at `1b4295b`, synced with origin)
- **Tests:** 716/716 bats green at PR HEAD; no test runs after the seven downstream upgrades (they were config + MCP operations only, no bats-reachable code changes)
- **Uncommitted changes:** None on the hub. Each downstream node committed its upgrade cleanly (commits: unifi `1bb7da0`, taxes `9629ffb`, fieldnation `86d6ecd`, caffeine-calculator `a4a311b`, luxlook `0d1181e`, whoop-toolbox `a5bac38`, fucina `2f233b9`).
- **Build status:** clean; no CI failures

## Blocked On

- Nothing.

## Next Steps

1. **Triage the 35 new Linear ideas** across the 7 projects. Most came in as "Idea" status; decide what moves to Backlog, Icebox, or gets canceled via `/idea triage` inside each node.
2. **Activate the next hub feature** from the 5 untriaged ideas remaining (`docs-check.sh idea-count` shows 5 new). Candidates surfaced during this session's work: (a) Linear MCP `create_issue_status` once exposed, to remove the one manual step in the migration guide; (b) batch-create MCP helper so downstream migrations don't require one tool call per entry; (c) node-specific projects for roadmap items.
3. **If downstream nodes start generating Linear issues from feature work**, consider whether to retire the local `.ccanvil/ideas.log` for Linear-configured nodes (right now captures fall back there only on MCP failure, but the log retains historical pre-migration entries).

## Context Notes

- **`migrated-from-docs` label was silently dropped on every `save_issue` call.** Linear rejects unknown label names instead of auto-creating them. The label wasn't pre-created at the workspace level, so every migrated issue has only the `idea` label (plus `Bug`/`needs-research` where those were added). Not urgent, but worth creating the label next session if we want the historical distinction visible in Linear.
- **Labels on migrated issues vs captured issues**: migrated ones got `idea` + sometimes `Bug`/`needs-research`; captured issues going forward get just `idea` unless the skill is extended.
- **AC-3 was refined mid-implementation.** Original wording put `routing.idea = "linear"` in the shared `ccanvil.json`, which conflicted with AC-29 (unconfigured nodes default to local). Resolved by moving `routing.idea` out of shared defaults entirely — each node opts in via its own `ccanvil.local.json`. This is the model all 7 downstream nodes now use.
- **Linear status creation is a manual UI step.** MCP doesn't expose it. Teams with different naming/statuses need the user to add Idea + Icebox in Linear Settings. Documented prominently in the migration guide.
- **Cross-project ideas aren't supported.** Each idea lives in exactly one Linear project, scoped to the node where `/idea` was invoked. If an idea spans projects, the user decides where it lives at capture time. Worth noting as a design choice — cross-cutting ideas might benefit from a workspace-level "Ideas Inbox" initiative in the future.
- **The AC-29 gotcha surfaced on luxlook.** luxlook's `.claude/ccanvil.json` had only `features.pr_review: false` — no `integrations` key at all. The section-merge in broadcast flagged it as a conflict. Resolution was trivial: `cp` the hub's ccanvil.json into place since luxlook had no custom integrations content to preserve. Future: for config files with no conflicts beyond "hub added fields", the auto-update could just apply (deeper than the current "conflict if hashes differ" heuristic).
- **Historical triaged ideas stay local, not in Linear.** For taxes and fieldnation, entries marked `promoted`/`dismissed`/`merged`/`complete` in the legacy `docs/ideas.md` were moved to `.ccanvil/ideas.log` but NOT created as Linear issues — only `new` entries got promoted. This keeps Linear Triage clean of historical decisions.

## Determinism Review

- **operations_reviewed:** ~50 (7 TDD cycles on the PR; broadcast; 7 node upgrade sequences; 7 Linear project creations; 35 Linear issue creations; ~10 config merges / setups; PR flow + merge + land)
- **candidates_found:** 5
- **Title generation for migrated Linear issues**: I hand-wrote concise summary titles for 33 of 35 promoted issues (the 2 with uid+epoch format that I recognized). Should be a script helper — read the body from each JSONL intent, pipe through a small Claude call via the `claude` CLI, or use a heuristic (first sentence up to 80 chars). Impact: **high** — every future migration of a legacy file will repeat this work.
- **Downstream migration fan-out**: for each node I ran a near-identical sequence: `pull-apply accept-new` → `idea-setup` → `idea-migrate` → `git add -A && commit`. Should be a single script: `docs-check.sh idea-upgrade --provider linear --team T --project P`. Impact: **medium** — recurs any time a new node adopts ccanvil, and it's ~4 commands today.
- **Linear project creation per node**: every node upgrade required a `save_project` MCP call with name + team + description + icon. Boilerplate. Impact: **medium** — `idea-upgrade` could call it if `--linear --create-project` was passed.
- **Batch MCP `save_issue` for migration**: fieldnation alone needed 23 individual MCP calls. Each was the same shape: team / project / state=Idea / labels / title / description. A single batched tool or a tiny node/python helper shelling out to the Linear API would be strictly better for bulk migrations. Impact: **high** during migration sessions, **low** going forward (daily captures are single-item).
- **Linear status creation**: manual UI-only step per team. If MCP ever exposes it, wire into `idea-setup --create-statuses` so the migration guide's one remaining manual step disappears. Impact: **medium** but blocked on upstream Linear MCP capability.

## Cross-Session Patterns

- **Prior stasis reference:** `230673d` (session-2026-04-22-stasis-recall-ship) — `git show HEAD~1:docs/stasis.md` returned empty because the prior stasis was cleaned up at PR #40's merge. Comparison done against 230673d directly.
- **RESOLVED — ALLOW_MAIN=1 divergence pattern.** Last session's stasis flagged this as a "recurring friction pattern across multiple sessions." This session fixed it two ways: (1) the pre-activate push-guard that ships in PR #41, (2) disciplined push-immediately behavior on the hub. Result: merge+land was a clean fast-forward, no `ALLOW_DESTRUCTIVE=1` reset needed. Pattern is now machine-enforced going forward.
- **RECURRING — `audit-session` still reports `line: 0` for every match.** Same finding as last stasis. Didn't fix this session; captured as an idea in last session's determinism review. Still worth a dedicated fix; low-ish impact since findings remain classifiable by file + pattern.
- **legacy-refs-scan: 162 total matches (70 hub-owned, 92 node-specific).** Hub-owned are almost entirely allowlist-covered (historical archives, scanner implementation, migrated session content). Node-specific matches are in downstream projects' own archives — not the hub's responsibility. No action needed; next `/ccanvil-pull` will propagate any hub-side fixes, but nothing urgent surfaced.
- **NEW PATTERN — Linear MCP lacks status creation.** Surfaced clearly this session. Recurring pain point because every new Linear team with a ccanvil integration needs the same two manual UI steps (Idea + Icebox). Candidate for a `guide/` note that scripts the `gh api linear` equivalent if/when Linear exposes a GraphQL mutation with adequate MCP auth scope.

## Security Review

**PASS.** New code this session:
- Operations routing layer (pure JSON shape manipulation, no credentials)
- Script primitives (idea-sync, idea-migrate, idea-setup) — all file/JSON ops
- /idea skill (no secrets; tool dispatch only)
- 7 downstream upgrades — config file edits + MCP calls that reuse the user's existing Linear OAuth session
- No `.env`, token, or credential file touched anywhere
- No URL changes to external services beyond Linear (which already had an authenticated MCP)
- The workspace `idea` label + 7 new Linear projects + 35 Linear issues created via the authenticated MCP are benign

## Memory Candidates

- **Reference (new):** Each of the 7 downstream ccanvil nodes now has a dedicated Linear project in the Blocktech Solutions team. The bidirectional mapping is: unifi-toolbox/taxes/fieldnation-toolbox/caffeine-calculator/luxlook/whoop-toolbox/fucina → Linear projects of the same names. Captures via `/idea` on any node route to that node's project only. Historical pre-migration entries preserved in each node's local `.ccanvil/ideas.log`.
- **Feedback (validated):** Zach prefers project-scoped Linear projects (one per downstream node, all in Blocktech Solutions team) rather than team-level routing or a shared "Ideas" project. Confirmed explicitly: "each project to have its own project, all in the same team." Applied to 7/7 upgrades.
- **Feedback (validated):** "Do the work once to get it right the first time" (carried from last session) — the user expanded Step 6 scope to include `idea-setup` + migration guide packaging BEFORE merging, rather than shipping a "minimal path possible" and handling packaging in a follow-up. Right call — cut downstream friction from 6 manual steps to 2 commands. Keep defaulting to the more-complete version on scope calls unless explicitly told to minimize.
- **Project fact:** Custom Linear statuses on BTS team are now `Idea` (backlog category, id `7615e0fb-6c44-4e6d-83dc-7cb8fe2a5341`) and `Icebox` (backlog category, id `58121463-93c3-4ed1-a26e-7c0c5c2a2ce4`). Workspace-scoped `idea` label (id `eb860048-3010-49b7-94d5-7079006d7e94`, color `#F2C94C`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
