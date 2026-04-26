# Feature: permissions-audit.sh decision-append substrate

> Feature: bts-159-permissions-audit-decision-append
> Work: linear:BTS-159
> Created: 1777163893
> Status: Complete

## Summary

`/permissions-review` currently asks Claude to hand-assemble JSONL decision lines via a Write+cat+rm dance — 4 tool calls per row, 64 calls across a typical 16-row walk, all of them deterministic operations. Add a `decision-append` subcommand to `permissions-audit.sh` that takes typed flags, validates them against the same pre-flight schema `apply --decisions` uses, and atomically appends one validated JSON line to a caller-provided buffer file. Replaces the stochastic dance with one deterministic call per decision.

## Job To Be Done

**When** the `/permissions-review` skill collects a per-row decision (delete / promote / keep-local / accept-danger),
**I want to** append it to the decisions buffer via a single typed-flag invocation that validates structurally before writing,
**So that** Claude doesn't hand-assemble JSON, the buffer can never contain a malformed line, and the per-row cost drops from 4 tool calls to 1.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `permissions-audit.sh decision-append --buffer <file> --permission "<perm>" --decision delete` appends a single JSON line `{"permission":"...","decision":"delete"}` to `<file>`. Exit 0. The file is created if absent; otherwise the line is appended (existing content preserved).
- [ ] **AC-2:** Same shape for `--decision promote` and `--decision keep-local`. Each emits `{"permission":"...","decision":"<verb>"}` with no extra fields.
- [ ] **AC-3:** `--decision accept-danger` requires `--risk`, `--rationale`, `--efficiency`, `--reviewer` (all four). Emits `{"permission":"...","decision":"accept-danger","risk":"...","rationale":"...","efficiency_justification":"...","reviewer":"..."}`. (Note: flag is `--efficiency` for ergonomics; field name is `efficiency_justification` to match the existing log schema.)
- [ ] **AC-4 (validation):** Missing `--permission` or `--decision` exits 2 with a clear stderr message. Missing required fields for `accept-danger` (any of risk/rationale/efficiency/reviewer empty or "TODO") exits 2. No write to the buffer on validation failure.
- [ ] **AC-5 (validation):** Unknown `--decision` value exits 2 with the expected-set listed (`delete|promote|keep-local|accept-danger`). No write.
- [ ] **AC-6 (atomicity):** Append is single-`>>` shell-level append of one fully-validated, jq-emitted JSON line. No partial writes; no torn lines if multiple `decision-append` invocations run in parallel against the same buffer (atomicity of POSIX small-write append guaranteed at OS level for single line under PIPE_BUF).
- [ ] **AC-7 (round-trip):** A buffer built entirely via `decision-append` is consumed without error by `permissions-audit.sh apply --decisions <buffer>` (no validation drift between writer and reader).
- [ ] **AC-8 (edge):** `--decision delete` with extra `--risk`/`--rationale`/`--efficiency`/`--reviewer` flags passed silently ignores the extras (does NOT include them in the emitted JSON). Per the schema, those fields are accept-danger-only.
- [ ] **AC-9 (skill prose):** `.claude/skills/permissions-review/SKILL.md` (or `.claude/commands/permissions-review.md`) Step 3-4 dispatch loop is rewritten to use `decision-append` per row instead of the Write+cat+rm pattern. Negative drift-guard test: skill prose contains `decision-append` and does NOT contain the legacy `cat .* >>` append idiom for decisions.
- [ ] **AC-10 (docs):** `command-reference.md` Permissions Audit Scripts section lists `decision-append` with its flag surface.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Modified — add `cmd_decision_append` + dispatcher entry + usage |
| `.claude/skills/permissions-review/SKILL.md` | Modified — Step 3-4 dispatch loop uses `decision-append` |
| `hub/tests/permissions-audit.bats` | Modified — add coverage for AC-1..AC-8 |
| `.ccanvil/guide/command-reference.md` | Modified — document `decision-append` row in the Permissions Audit Scripts table |

## Dependencies

- **Requires:** Existing `cmd_apply` validation logic (BTS-149) — the new `cmd_decision_append` mirrors that schema exactly.
- **Blocked by:** none.

## Out of Scope

- BTS-161 entry-context substrate (sibling ticket, separate concern). Both tickets target the same skill but solve different stochastic patterns; can ship independently.
- Refactoring `cmd_apply`'s pre-flight to share code with `cmd_decision_append` via a `_validate_decision_line` helper. Worth doing but optional — could be a follow-up if the duplicated validation drifts.
- Locking semantics beyond POSIX small-write append (no flock, no fcntl). Operationally `/permissions-review` is single-threaded per session; concurrent invocations are not a real risk.

## Implementation Notes

- **Flag parser:** mirror the existing `cmd_apply` arg-parsing pattern. New globals: `BUFFER_FILE`, `PERMISSION`, `DECISION`, `RISK`, `RATIONALE`, `EFFICIENCY`, `REVIEWER`.
- **Validation:** extract a `_validate_decision_line()` helper that takes `(perm, dec, risk, rationale, eff, reviewer)` and emits the same error messages as `cmd_apply`'s pre-flight. Call it from both `cmd_decision_append` and (optionally, in a follow-up) `cmd_apply`.
- **JSON construction:** use `jq -nc` with `--arg` for each field; for accept-danger, build the 6-field object; for other decisions, build the 2-field object. Never hand-assemble JSON via `printf '{"permission":"%s",...}'`.
- **Atomic append:** `echo "$json_line" >> "$BUFFER_FILE"`. Bash's `>>` is POSIX `O_APPEND`, single-line writes under `PIPE_BUF` (4KB on Linux/macOS) are atomic.
- **Error envelope:** reuse `emit_error_envelope` with exit 2 (matches `cmd_apply`'s validation contract).
- **Skill prose update (AC-9):** locate the dispatch loop and replace the per-row Write+cat+rm pattern with a single `bash .ccanvil/scripts/permissions-audit.sh decision-append --buffer "$DECISIONS" --permission "..." --decision <verb> [...]` call.
- **BTS-127 compliance:** any new `@test` with ≥2 `jq -e` assertions opens with `set -e`. Most tests assert via `[ "$status" -eq N ]` + `grep` on file content, so BTS-127 may not apply broadly here.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
