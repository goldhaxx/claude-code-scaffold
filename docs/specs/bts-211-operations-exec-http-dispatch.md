# Feature: operations.sh exec dispatches http-mechanism commands

> Feature: bts-211-operations-exec-http-dispatch
> Work: linear:BTS-211
> Created: 1777342155
> Status: Complete

## Summary

`operations.sh exec <verb>` runs the resolved command only when the provider mechanism is `bash`. For `http` providers, it falls through to echoing the resolution envelope instead of executing. This silently broke at the BTS-175 ship when `backlog.list` migrated bash → http; callers (`/radar`, `/idea triage`) now receive `{provider, mechanism, invocation, contract}` instead of the documented issue array.

Fix: extend `cmd_exec` to eval `.invocation.command` for any mechanism whose resolution carries a shell command — currently `bash` AND `http`. The `mcp` branch stays on the echo path because mcp resolutions carry `.invocation.tool` + `.invocation.params` instead of a shell command (can't be shell-eval'd).

## Job To Be Done

**When** I run `operations.sh exec <verb>` for any verb (regardless of provider routing),
**I want to** receive the executed result (issue array, idea array, etc.),
**So that** callers stay mechanism-agnostic and skill prose contracts (`/radar`'s `.claude/skills/radar/SKILL.md:11`) hold.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_exec` evals `.invocation.command` when mechanism is `bash` (preserved) OR `http` (new). The `mcp` branch (or any other mechanism) still emits the envelope on stdout.

- [ ] **AC-2:** Bats: stub a verb whose resolved mechanism is `http` (with a fake `linear-query.sh` invocation that emits a known JSON shape). Run `operations.sh exec <verb>`. Assert the output matches the canned http response, NOT the resolution envelope.

- [ ] **AC-3:** Bats regression: stub a verb resolving to `bash` mechanism. Run `operations.sh exec <verb>`. Assert the resolved bash command's output is emitted (preserves existing behavior).

- [ ] **AC-4:** Bats regression: a verb resolving to `mcp` mechanism still emits the resolution envelope (preserves the explicit caller-dispatches contract for mcp).

- [ ] **AC-5:** Live AC-5: `bash .ccanvil/scripts/operations.sh exec backlog.list 2>/dev/null | jq -r '.[] | "\(.id) | \(.title)"'` produces the BTS-style issue list (e.g., `BTS-211 | FIX: ...`) without jq error. This is the live-API gate per `.claude/rules/tdd.md` — proves the fix end-to-end against the real Linear-routed substrate.

- [ ] **AC-6:** Drift-guard: `BTS-211` referenced inline in `operations.sh` near the change site.

- [ ] **AC-7:** Full bats suite ≥ 1847 (post-BTS-207 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | `cmd_exec` extends bash-only eval to `bash|http`. |
| `hub/tests/operations-exec-http.bats` | New file: 3 ACs + drift-guard. |

## Out of Scope

- **mcp dispatch shape change.** Stays on the echo path.
- **Re-architecting operations.sh registry.** Out of scope per BTS-211 body.
- **Migrating callers back from manual `resolve | eval` to bare `exec`.** Separate ship — could land same-PR if friction surfaces, but not required for this fix's correctness.

## Implementation Notes

- 5-line change: replace the `if [[ "$mechanism" == "bash" ]]` shape with a `case "$mechanism" in bash|http) ... ;; *) ... ;; esac`.
- The mcp branch must continue to echo the envelope verbatim — its callers explicitly dispatch via the parsed `.invocation.tool` + `.invocation.params`.
