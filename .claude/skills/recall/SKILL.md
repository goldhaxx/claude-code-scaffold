---
name: recall
description: Re-hydrate context after a reset — read the last /stasis snapshot and report current project state.
---

Read the current state of the project to resume work after a context reset. `/recall` is the inverse of `/stasis`: it reads the snapshot that `/stasis` wrote, re-runs the deterministic state queries, and produces a cold-start briefing.

## Data gathering (deterministic)

0a. **BTS-20: unified lifecycle-state envelope.** Run `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` and capture the JSON envelope. The envelope has shape `{state, legal_next_actions:[{action, command, reason}], blockers:[], suggestions:[]}` and replaces the prior pair of `validate` + `recommend` calls — one resolver call now drives both staleness reporting and the next-action recommendation. The `state` field is one of: `no-active-spec`, `spec-activated`, `plan-written`, `implementing`, `pr-open`, `pr-merged`, `session-wrap`, `blocked`, `uninitialized` (codified in `.ccanvil/templates/lifecycle-graph.json`).
0c. Capture the resolution into `$RESOLUTION` and branch on mechanism:

```bash
RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve backlog.list)
mechanism=$(echo "$RESOLUTION" | jq -r '.mechanism')
case "$mechanism" in
  bash) eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')" ;;  # local list-specs
  http) eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')" ;;  # BTS-175 Linear-routed
  mcp)  ;;  # legacy: call .invocation.tool via MCP with .invocation.params
esac
```

Report counts by status (Draft, Ready, In Progress, Complete) — or by Linear state name when http-routed.

  **Do NOT use `idea.list` as a backlog proxy** (BTS-175). `idea.list` filters by `label=idea` and silently hides scaffold-labeled tickets, leading to phantom "backlog is empty" reports when in fact Backlog-state items exist. `backlog.list` is the canonical "what's left to ship" surface — it filters by Backlog state-id only, no label restriction.
0d. Check the current branch name (`git branch --show-current`). Report whether it follows the `claude/<type>/<name>` naming convention.

0e. **BTS-206: session counter + boundary.** Run `bash .ccanvil/scripts/docs-check.sh session-info --project-dir .` and capture `.counter`, `.iso`. Used in the briefing's session line below.

1. **Read the active stasis via the provider-aware primitive (BTS-204).** Run
   `bash .ccanvil/scripts/docs-check.sh artifact-read --kind stasis` for
   feature-kind, or with `--stasis-kind session` for session-kind. On
   local-routed nodes this reads `docs/stasis.md`; on Linear-routed nodes
   (`integrations.routing.stasis=linear`) this reads the corresponding
   Linear Document. Equivalent to `cat docs/stasis.md` on the local path.
2. Run `git log --oneline -10` to see recent commits.
3. Run `git diff --stat` to see any uncommitted changes.
4. Run `git diff --cached --stat` to see any staged changes.
5. **Read the active spec via the provider-aware primitive (BTS-204).** Run
   `bash .ccanvil/scripts/docs-check.sh artifact-read --kind spec --feature <FEATURE_ID>`.
   On local-routed nodes this reads `docs/spec.md`; on Linear-routed nodes
   it reads the spec Linear Document. Use the active feature id from branch
   name when prompted.

6. If `docs/stasis.md` has a `## Determinism Review` section with candidates_found > 0, read it and prepare to surface those items.
6aa. **BTS-232: carry-forward determinism candidates.** Run `bash .ccanvil/scripts/docs-check.sh stasis-carry-forward --project-dir .` and capture `{candidates, count_total, count_carry_forward}`. The substrate parses the prior stasis's `## Determinism Review` section, extracts each candidate's slug (tolerating both bolded `**slug**:` and backticked `` `tok` `` shapes), queries the current Linear idea listing, and reports which candidates have NO matching `Determinism: <slug>` idea — flagging silent dual-capture drops. Empty + no-prior-stasis cases emit `count_carry_forward: 0` without error.
6a. **Cross-session history (BTS-22):** read up to the 3 most-recent archived stasis files via the `sessions-list` substrate primitive — replaces the prior git-archeology approach (`git show HEAD~1:docs/stasis.md`).
    ```bash
    sessions=$(bash .ccanvil/scripts/docs-check.sh sessions-list --limit 3 --project-dir .)
    if [[ $(echo "$sessions" | jq 'length') -gt 0 ]]; then
      # Read each path's content for cross-session pattern context.
      echo "$sessions" | jq -r '.[].path' | while read -r p; do
        : # cat "$p"  # consumed by the cross-session synthesis below
      done
    else
      # Fallback for first-stasis nodes that pre-date BTS-22 — still works.
      git show HEAD~1:docs/stasis.md 2>/dev/null || true
    fi
    ```
7. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh audit-session --since <last-stasis-commit>` (extract the commit from stasis metadata or use the last 10 commits) and note any new findings.

8. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh idea-count` and note any untriaged ideas.
9. If `.ccanvil/scripts/permissions-audit.sh` exists (BTS-149), run both: `permissions-audit.sh check --json` and `permissions-audit.sh promote-review --json`. Read `.danger` and `.counts.total` and sum them.
10. **BTS-201: parse the prior stasis's `## Evidence Gaps` section.** Read `docs/stasis.md` and extract everything between the `## Evidence Gaps` heading and the next `##` heading. If the section content matches the empty-state literal `No evidence gaps this session.`, treat as empty. Otherwise, parse each `- BTS-X — <title> — <reason>` bullet for surfacing in the briefing. The protocol is documented in `.claude/rules/evidence-required-for-captures.md`.

## Briefing

Then provide a brief summary:
- **Session N — boundary <iso>** (from step 0e). Render this line at the top of the briefing only when `counter > 0`. When `counter == 0` (fresh node, hook hasn't fired yet), OMIT this line entirely (no zero-noise). Format: `**Session N** — boundary <iso>`.
- **Lifecycle state** (from step 0a's envelope) — the `state` field plus legal next actions and any blockers. Render as: one line for the current state name, then a `**Legal next actions:**` sub-list walking `legal_next_actions[]` (each entry's `action` + `command` + `reason`). When `blockers[]` is non-empty, render a `**Blockers:**` sub-list with one bullet per entry — these always come BEFORE legal next actions because recovery is required first.
- **Spec backlog** — count of specs by status from step 0c, and which spec (if any) is active on the current branch
- **Ideas** — untriaged idea count from step 8 (if > 0, note: "N untriaged ideas — run /idea triage")
- **Permissions Review** — sum from step 9. When `(check.danger + promote-review.counts.total) > 0`, print one line: `**Permissions Review:** N candidates pending — run /permissions-review`. When 0, omit entirely (no noise).
- **Evidence Gaps from prior session:** (BTS-201) — when step 10 found non-empty bullets, surface them under the literal heading `**Evidence Gaps from prior session:**` with one line per gap (`- BTS-X — <title> — <reason>`). When the section matched the empty-state literal `No evidence gaps this session.`, **OMIT this heading entirely** — silent on empty (no noise).
- **Branch** — current branch name and whether it follows convention (from step 0d)
- **Outstanding determinism improvements** — if the previous stasis's `## Determinism Review` had candidates, list them under this heading before the regular summary
- **Carry-forward determinism candidates:** (BTS-232) — when `count_carry_forward > 0`, surface under the literal heading `**Carry-forward determinism candidates:**` with one bullet per `candidates[?has_idea==false].slug`. These are candidates listed in the prior stasis whose dual-capture didn't land — the operator should manually create the missing ticket. Silent when `count_carry_forward == 0` (no zero-noise).
- **Post-stasis audit findings** — if `audit-session` found patterns since the last stasis, list them here
- What was accomplished in previous sessions
- Current state (clean/dirty, passing/failing tests)
- What the next step should be based on stasis and spec

Do NOT start implementing anything. Just orient and report.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
