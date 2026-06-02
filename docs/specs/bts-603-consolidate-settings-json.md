# Feature: Consolidate settings.json

> Feature: bts-603-consolidate-settings-json
> Work: linear:BTS-603
> Created: 1780371073
> Subject: Consolidate settings.json
> Status: In Progress

## Summary

`.claude/settings.json` is the single largest contributor to the session-start context budget (1604 tokens / **20.1%** of the 8000-token ceiling), and is the main reason every session opens at CRITICAL (114.2% total). The file has accumulated dead Bash entries (shell control-flow keywords that are never standalone commands), duplicate path patterns, and operator-personal MCP / Read entries that belong in `settings.local.json` (per-machine, gitignored) rather than the hub-shared file. A surgical trim — moving operator-personal entries out, deleting structurally-dead entries, and collapsing duplicates — drops the file below ~800 tokens without weakening any security gate, and pulls total session-start budget back under HEALTHY.

## Job To Be Done

**When** a session starts and the agent loads project context,
**I want to** keep `.claude/settings.json` to a tight project-shared permission/hook surface and let operator-personal MCP wirings live in machine-local `settings.local.json`,
**So that** every session opens under the 8000-token budget instead of CRITICAL, and the hub-shared file genuinely represents what the project requires (not what one operator's tooling happens to use).

## Acceptance Criteria

- [ ] **AC-1:** `.claude/settings.json` token count decreases by at least **600 tokens** (1604 → ≤1004). Verified by `bash .ccanvil/scripts/context-budget.sh check --text` on a clean tree post-change, parsing the `settings.json` row.
- [ ] **AC-2:** Total context-budget status reported by `bash .ccanvil/scripts/context-budget.sh check --text` is **HEALTHY** or **WARNING** (not CRITICAL). The "Status:" line on the final stdout line must not contain the literal string `CRITICAL`.
- [ ] **AC-3:** **Given** the deny array `S_pre = jq -S .permissions.deny .claude/settings.json` captured BEFORE the change, **when** the consolidation is applied and `S_post = jq -S .permissions.deny .claude/settings.json` is captured AFTER, **then** `jq -n --argjson pre "$S_pre" --argjson post "$S_post" '$pre - $post | length'` returns `0` (every pre-change deny entry survives; additions allowed, removals forbidden).
- [ ] **AC-4:** Every installed hook script (`.claude/hooks/*.sh`, excluding `_lib/`) that was wired in `.claude/settings.json` before the change remains wired **in the same event group** after. Verified **per event group**: for each event `E` in `{"PreToolUse","PostToolUse","PreCompact","SessionStart","SessionEnd","PermissionRequest"}`, compute `H_pre_E = jq -S --arg e "$E" '[.hooks[$e][]?.hooks[]?.command] | unique' .claude/settings.json` BEFORE the change and `H_post_E = jq -S --arg e "$E" '[.hooks[$e][]?.hooks[]?.command] | unique' .claude/settings.json` AFTER. Then `jq -n --argjson pre "$H_pre_E" --argjson post "$H_post_E" '$pre - $post | length'` returns `0` for every event `E` (per-event subset preservation, not a flat union).
- [ ] **AC-5:** All nine shell control-flow keywords (`Bash(for:*)`, `Bash(while:*)`, `Bash(if:*)`, `Bash(do:*)`, `Bash(done)`, `Bash(then:*)`, `Bash(else:*)`, `Bash(elif:*)`, `Bash(fi)`) are **absent** from `.permissions.allow` after the change. These are syntax tokens, not commands; Claude never invokes them as standalone shell commands.
- [ ] **AC-6:** Each pair of duplicate Bash path patterns is collapsed to its canonical no-leading-`./` form. Specifically: `Bash(.ccanvil/scripts/:*)` **survives** AND `Bash(./.ccanvil/scripts/:*)` **is absent**; `Bash(.claude/hooks/:*)` **survives** AND `Bash(./.claude/hooks/:*)` **is absent**. Verified by four explicit checks: `jq '.permissions.allow | any(. == "Bash(.ccanvil/scripts/:*)")'` returns `true`; `jq '.permissions.allow | any(. == "Bash(./.ccanvil/scripts/:*)")'` returns `false`; `jq '.permissions.allow | any(. == "Bash(.claude/hooks/:*)")'` returns `true`; `jq '.permissions.allow | any(. == "Bash(./.claude/hooks/:*)")'` returns `false`. (Canonical form selection: the no-`./` shape matches the actual invocation form Claude emits — every Bash call this session has used `bash .ccanvil/scripts/...`, never `bash ./.ccanvil/scripts/...`.)
- [ ] **AC-7:** The following **exact set** of allow-list entries — and ONLY this set — is moved (not copied) from `.claude/settings.json` to `.claude/settings.local.json`'s `.permissions.allow`:
  - `Read(//Users/zacharywright/projects/**)`
  - `mcp__claude_ai_Notion__*`
  - `mcp__claude_ai_Granola__*`
  - `mcp__claude_ai_Gmail__*`
  - `mcp__claude_ai_Google_Calendar__*`
  - `mcp__claude_ai_Google_Drive__*`
  - `mcp__open-brain__*`
  - `mcp__claude-in-chrome__*`

  Verified by, for each entry in the set: `jq --arg e "$entry" '.permissions.allow | any(. == $e)' .claude/settings.json` returns `false` AND `jq --arg e "$entry" '.permissions.allow | any(. == $e)' .claude/settings.local.json` returns `true`. For every allow-list entry NOT in the set that was in pre-change `settings.json`: `jq --arg e "$entry" '.permissions.allow | any(. == $e)' .claude/settings.local.json` returns `false` (no other entries are duplicated into the local file).
- [ ] **AC-8:** The following MCP wildcards remain in `.claude/settings.json`'s `.permissions.allow` (classified as project-shared, NOT moved to `settings.local.json`):
  - `mcp__claude_ai_Linear__*` — Linear is the canonical backlog substrate, gated by `LINEAR_API_KEY`, reachable from `operations.sh resolve`.
  - `mcp__claude_ai_Mermaid_Chart__*` — diagram rendering surface usable by `/spec` and `/spec --review` for architecture-shaped specs; project-shared by design.

  Verified by: `jq '.permissions.allow | any(. == "mcp__claude_ai_Linear__*")' .claude/settings.json` returns `true`, AND `jq '.permissions.allow | any(. == "mcp__claude_ai_Mermaid_Chart__*")' .claude/settings.json` returns `true`. Together with AC-7's "ONLY this set" clause and the deny-list invariant from AC-3, the project-shared and operator-personal MCP classifications are now exhaustive — there are no remaining unclassified `mcp__*` entries.
- [ ] **AC-9:** `bash .ccanvil/scripts/bats-report.sh --parallel` exits 0 — zero failures, zero errors. (Count-floor noise is dropped: a permission regression surfaces as a failing test, which the exit code already catches; a missing AC-12 bats file is caught by AC-12 directly. No need to track an absolute baseline that goes stale on any concurrent ship.)
- [ ] **AC-10:** Manifest validate (`bash .ccanvil/scripts/module-manifest.sh validate --json`) returns `status:"ok"` with `drift == []`.
- [ ] **AC-11 (error):** Both `.claude/settings.json` and `.claude/settings.local.json` parse as valid JSON. Verified by `jq . .claude/settings.json` and `jq . .claude/settings.local.json` both exiting 0.
- [ ] **AC-12 (drift-guard):** A new `hub/tests/settings-consolidation.bats` file is added containing per-criterion structural assertions for AC-3, AC-4, AC-5, AC-6, AC-7, AC-8 (re-runnable forever; pin against future re-introduction). The test file is included in the hub test allowlist and runs as part of `bash .ccanvil/scripts/bats-report.sh --parallel`.

## Affected Files

| File | Change |
|------|--------|
| `.claude/settings.json` | Modified — entries removed, moved, or consolidated per AC-3 through AC-8 |
| `.claude/settings.local.json` | Created (or modified) — operator-personal entries moved here |
| `hub/tests/settings-consolidation.bats` | New — drift-guard for AC-3/4/5/6/7/8 |

## Dependencies

- **Requires:** `permissions-audit.sh` (BTS-149) and `context-budget.sh check --text` substrates, both shipped.
- **Blocked by:** none for the local trim. Downstream propagation is blocked by BTS-605 (broadcast unblock), but is explicitly Out of Scope here.

## Out of Scope

- **Downstream broadcast.** BTS-605 must land first; documenting this and the BTS-605 dependency in the PR body is sufficient for this ship.
- **Modifying hook scripts themselves.** Each hook (`protect-files.sh`, `guard-destructive.sh`, etc.) carries its own manifest + tests; this spec only touches their wiring in `settings.json`.
- **Restructuring the `deny` array** beyond preserving every existing entry.
- **Adding NEW permissions or hooks.** Trim-only.
- **Changing `$schema` or `effortLevel`.**
- **Modifying `permissions-audit.sh` logic.** If a candidate the auditor surfaces is rejected, capture as a follow-up — don't change the auditor mid-trim.

## Implementation Notes

- **Pattern: same shape as BTS-602's surgical-removal ship.** Use a single mechanical pass driven by deterministic substrate signals: `permissions-audit.sh promote-review --json` for DELETE/TRIAGE candidates, `context-budget.sh check --text` for before/after token measurement, `jq -S` diff for invariant verification.
- **Shell-keyword removal is structurally safe.** Claude Code matches Bash allow patterns against the literal command being invoked. `for`, `while`, `if`, `do`, `done`, `then`, `else`, `elif`, `fi` never appear as the first token of a shell invocation — they are syntax inside a compound command. These entries have never gated a real call.
- **Operator-personal classification heuristic:** an entry is operator-personal if it would have no effect on a fresh clone of the hub running the canonical ccanvil substrate (bats tests, `/idea triage`, `/spec`, `/pr`, `/ship`, `/stasis`, `/recall`). The Linear MCP IS hit by `operations.sh resolve` paths; Notion / Granola / Gmail / Calendar / Drive / open-brain are not.
- **Verification rhythm:** capture pre-state JSON-snapshots (deny array, hooks block, full allow array) into `/tmp/bts-603-pre.json` at step 1 of the plan, so each AC-3/AC-4/AC-7 check is a `jq diff` against the snapshot, not a re-read of git history.
- The leading-double-slash `Read(//Users/...)`, `Read(//tmp/**)`, `Read(//private/tmp/**)` shape looks unintentional, but normalizing it is a separate fix — for AC-7 just move the `Read(//Users/zacharywright/projects/**)` entry as-is to `settings.local.json` (the `//` works because Claude resolves both `/foo` and `//foo` consistently on macOS).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
