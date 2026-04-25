# Feature: permissions rewrite — autonomy-first

> Feature: bts-142-permissions-rewrite-autonomy-first
> Work: linear:BTS-142
> Created: 1777078321
> Status: Complete

## Summary

The accumulated `.claude/settings*.json` allowlists have grown into a graveyard of pre-flatten paths, one-shot historical operations, and narrow per-command entries that do nothing except trigger Claude-Code permission prompts on routine operations. This blocks forward motion in the name of safety the hooks already provide. Rewrite both files: `settings.json` (the canonical hub-broadcast policy) gets aggressive command-namespace wildcards trusting the existing hook layer (`protect-files.sh`, `protect-main.sh`, `guard-force-push.sh`, `guard-destructive.sh`) to catch the genuinely dangerous cases. `settings.local.json` is reset to empty — by design — so it becomes the natural staging area where session-time "always-allow" approvals accumulate for periodic promotion review. Extend `guard-destructive.sh` with chmod-destructive patterns (777/666/000) so blanket `Bash(chmod:*)` is safe.

## Job To Be Done

**When** Claude is performing routine development work in this project,
**I want to** approve a deliberate, broad allowlist policy once and let hooks gate the actually-dangerous operations,
**So that** speed and forward motion are the default, and per-prompt friction disappears.

## Acceptance Criteria

- [ ] **AC-1:** `.claude/settings.json` `permissions.allow` contains broad command-namespace wildcards including `Bash(git:*)`, `Bash(gh:*)`, `Bash(bash:*)`, `Bash(.ccanvil/scripts/:*)`, `Bash(rm:*)`, `Bash(cp:*)`, `Bash(mv:*)`, `Bash(chmod:*)`, `Bash(chown:*)`, `Bash(security:*)`, and `mcp__claude_ai_Linear__*`.
- [ ] **AC-2:** `.claude/settings.json` `permissions.deny` retains only catastrophic, hook-uncatchable ops: `rm -rf /` (and variants for `/*`, `~`, `$HOME`, `.`), `sudo`/`su`/`doas`, `dd`, `mkfs`, `diskutil`, `kill -9`. Does NOT contain any `chmod` patterns (delegated to the destructive-guard hook).
- [ ] **AC-3:** `.claude/settings.local.json` contains exactly `{"permissions": {"allow": []}}` — empty by design; future session "always-allow" approvals land here for periodic promotion review.
- [ ] **AC-4:** `guard-destructive.sh` blocks `chmod 777`, `chmod -R 777`, `chmod 666`, `chmod -R 666`, `chmod 000`, `chmod -R 000`. Each block emits stderr naming the pattern and showing `ALLOW_DESTRUCTIVE=1` bypass.
- [ ] **AC-5:** `guard-destructive.sh` allows non-destructive chmod: `chmod +x`, `chmod 644`, `chmod 755`, `chmod -R 755` — exit 0.
- [ ] **AC-6:** `ALLOW_DESTRUCTIVE=1 chmod 777 path` bypasses the guard (exit 0). Consistent with existing bypass pattern.
- [ ] **AC-7:** `hub/tests/guard-hooks.bats` has new chmod cases covering AC-4 / AC-5 / AC-6; full bats suite stays green (no regressions in the existing 1024 cases).
- [ ] **AC-8:** `settings.json` `hooks` block (PreToolUse, PostToolUse, PreCompact) is preserved verbatim — no hook config changes.
- [ ] **AC-9:** Both `settings.json` and `settings.local.json` are valid JSON (`jq empty` passes).

## Affected Files

| File | Change |
|------|--------|
| `.claude/settings.json` | Modified — rewrite `permissions.allow` + tighten `permissions.deny`. Hooks block preserved. |
| `.claude/settings.local.json` | Modified — reset to `{"permissions": {"allow": []}}` |
| `.claude/hooks/guard-destructive.sh` | Modified — add chmod-destructive patterns (777/666/000) |
| `hub/tests/guard-hooks.bats` | Modified — add chmod-destructive test cases (AC-4/5/6) |

## Dependencies

- **Requires:** Existing hook layer (`protect-files.sh`, `protect-main.sh`, `guard-force-push.sh`, `guard-destructive.sh`) — already in place.
- **Blocked by:** Nothing.

## Out of Scope

- Updating `permissions-audit.sh check` so log-marked rationales can override DANGER status. Currently DANGER-by-pattern always wins; broad wildcards added here will all flag as DANGER. Capture as follow-on idea.
- Building promotion-review tooling (`permissions-audit.sh promote-review` or similar) that surfaces settings.local.json delta vs settings.json for periodic review. Capture as follow-on idea.
- Writing rationale entries in `permissions-log.json` for the new broad wildcards to mark them REVIEWED. Deliberate review pass — separate session.
- Migrating downstream nodes (fucina, luxlook). They receive the new `settings.json` via `ccanvil-sync.sh broadcast` after merge.

## Implementation Notes

- The hook layer is the real safety floor. Trust it. `guard-destructive.sh` already blocks `git reset --hard`, `git branch -D`, `git push --delete`, `git clean -f`. Adding chmod patterns extends the same pattern (regex match → exit 2 with bypass).
- `settings.json` is broadcast to downstream nodes via `ccanvil-sync.sh broadcast` (see line 31 of ccanvil-sync.sh). The new wildcards apply to all nodes. `settings.local.json` is NOT broadcast — per-node by design.
- `Bash(security:*)` allowed because `~/.claude/rules/tls-troubleshooting.md` (Zach's WARP setup) uses `security find-certificate` for cert exports.
- The audit will continue to report many DANGERs after this ships. That is intended — the audit's role becomes "force review of the broad-wildcard list" rather than "block all broad wildcards." The follow-on out-of-scope items will let rationales mark them REVIEWED.
- Test pattern: extend `hub/tests/guard-hooks.bats` directly. Strict-mode bats per `.claude/rules/tdd.md`. Use the same JSON-piping pattern as existing chmod-adjacent cases.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
