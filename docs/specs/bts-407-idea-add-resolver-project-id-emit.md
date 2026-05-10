# Feature: idea.add resolver emits --project-id when configured

> Feature: bts-407-idea-add-resolver-project-id-emit
> Work: linear:BTS-407
> Created: 1778387840
> Subject: idea.add resolver emits --project-id when configured
> Status: Complete

## Summary

`operations.sh` Linear-routed verbs (`idea.add`, `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`, `backlog.list`) emit `--project '<name>'` exclusively. On downstream nodes whose `.claude/ccanvil.local.json` defines `integrations.providers.linear.project_id` but leaves `.project` empty, the resolved command becomes `--project ''`, which `linear-query.sh save-issue` rejects with `--project '' did not resolve to a project id`. Operators currently hand-append `--project-id <uuid>` before eval'ing every captured command. Fix: when `project_id` is present in provider config, the resolver emits `--project-id <uuid>` (UUID-direct, skips name→ID lookup); otherwise it falls back to `--project <name>` as today.

## Job To Be Done

**When** I run `/idea <text>` on a Linear-routed downstream node configured with `project_id`,
**I want to** capture without a manual `--project-id` append,
**So that** every `/idea` capture lands cleanly in the configured project on the first dispatch.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given a Linear-routed config with `project_id` set and `project` empty, when `operations.sh resolve idea.add` runs, then `.invocation.command` contains `--project-id '<uuid>'` and does NOT contain `--project ''`.
- [ ] **AC-2:** Given a Linear-routed config with both `project_id` AND `project` (name) set, when `operations.sh resolve idea.add` runs, then `.invocation.command` contains `--project-id '<uuid>'` and does NOT contain `--project '<name>'` (UUID is preferred — skips the name-resolution round-trip in `linear-query.sh`).
- [ ] **AC-3:** Given a Linear-routed config with `project_id` empty and `project` (name) set, when `operations.sh resolve idea.add` runs, then `.invocation.command` contains `--project '<name>'` (existing behavior preserved).
- [ ] **AC-4:** AC-1/AC-2/AC-3 hold identically for the other Linear-routed verbs that emit `--project`: `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`, `backlog.list`.
- [ ] **AC-5:** Given a Linear-routed config with both `project_id` and `project` empty, when any affected resolver runs, then the resolved command emits NEITHER `--project` nor `--project-id` (no empty-string flag is ever emitted).
- [ ] **AC-6:** Edge — `project_id` containing an apostrophe or shell-meta char is single-quote escaped via `@sh` in the resolved command (no shell-injection surface; matches existing `--project` quoting).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — read `project_id` in `linear_mcp_adapter`; gate `--project` vs `--project-id` per verb |
| `hub/tests/operations-resolve-http.bats` | Modified — extend fixtures + assertions for AC-1 through AC-6 |
| `.ccanvil/manifest-allowlist.txt` | Unchanged (operations.sh already covered) |

## Dependencies

- **Requires:** None — substrate is self-contained; `linear-query.sh save-issue` already accepts `--project-id` (verified line 739).
- **Blocked by:** None.

## Out of Scope

- Renaming the legacy function `linear_mcp_adapter` (it dispatches http now, not MCP — but rename is unrelated cleanup).
- Updating `init`/`provider-resolve-ids` to populate `project_id` more aggressively on downstream nodes — covered by BTS-314 onboarding cluster.
- Changing `linear-query.sh save-issue`'s flag handling — wrapper is unchanged.

## Implementation Notes

- Single-point fix in `linear_mcp_adapter()` at the top of the function: `project_id=$(echo "$provider_config" | jq -r '.project_id // ""')`.
- Per-verb pattern in the `jq -n` invocation: pass both `--arg project` and `--arg project_id`, then in the command-string concat use `(if $project_id != "" then " --project-id " + ($project_id | @sh) elif $project != "" then " --project " + ($project | @sh) else "" end)`.
- Keep the order project_id → project → omit so existing tests asserting `contains("ccanvil")` still pass (hub config has both set; UUID wins).
- Existing `BTS-164 AC-4` hub test (`operations-resolve-http.bats:74-82`) asserts `contains("ccanvil")` — fixture has only `project: "ccanvil"`, no `project_id`. That test stays green via AC-3 fallback.
- Keep `linear_mcp_adapter` function name unchanged (out of scope per above).
<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
