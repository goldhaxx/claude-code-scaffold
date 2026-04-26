# Implementation Plan: idea-pending-replay substrate primitive

> Feature: bts-179-idea-pending-replay
> Work: linear:BTS-179
> Created: 1777215402
> Spec hash: 2eded4b7
> Based on: docs/spec.md

## Objective

Move the `/idea sync` per-entry dispatch loop out of skill prose and into a deterministic substrate command (`docs-check.sh idea-pending-replay`) so dispatch correctness no longer depends on shell-quoting hygiene at the skill layer.

## Sequence

### Step 1: Empty-log fast path (AC-1)
- **Test:** new bats `hub/tests/idea-pending-replay.bats` — when `.ccanvil/ideas-pending.log` is absent or empty, `idea-pending-replay` outputs `{"synced":0,"failed":0,"pending":0,"entries":[]}` and exits 0.
- **Implement:** add `cmd_idea_pending_replay()` skeleton in `.ccanvil/scripts/docs-check.sh`, wire dispatch case in the main `case` block (next to `idea-sync)`).
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** `bats hub/tests/idea-pending-replay.bats` AC-1 green.

### Step 2: `add` op replay (AC-2)
- **Test:** seed log with one `add` entry (title + body), run replay, assert exit 0, summary shows `synced:1`, log is empty after. Use a stub `linear-query.sh save-issue` (drop a wrapper on PATH that echoes a fake `{"id":"BTS-X","title":"..."}` and exits 0) so the test doesn't hit the real network. Mirrors the pattern in `idea-pending-helpers.bats`.
- **Implement:** inside `cmd_idea_pending_replay`, iterate entries via `jq -c '.[]' <(jq -s . "$pending")`. For `op == "add"`, resolve `idea.add` via `operations.sh`, append `--parent-id $(printf '%s' "$pid" | jq -Rr @sh)` if `args.parent_id` set, then `jq -n --arg title --arg description '{title:..,description:..}' | eval "$cmd --input-json -"`.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-2 green; AC-1 still green.

### Step 3: ticket.transition ops (AC-3, AC-4)
- **Test:** seed log with `promote` (with priority), `defer`, `dismiss`, `merge` (with duplicateOf), `ticket.transition` (with role) entries; assert each routes through the correct resolver + flag combination. Use a stub for `linear-query.sh save-issue` that records its argv to a file the test reads back.
- **Implement:** add case branches: `promote` → resolve `ticket.transition <id> backlog` + eval with `--priority <N>`; `defer/dismiss` → matching transition + plain eval; `merge` → `ticket.transition <id> duplicate` + `--duplicate-of <target>`; `ticket.transition` → resolve `ticket.transition <id> <role>` + plain eval. All flag values quoted via `jq -Rr @sh`.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-3, AC-4 green; AC-1, AC-2 still green.

### Step 4: ack-on-success / preserve-on-failure (AC-5)
- **Test:** seed log with two entries where the stub fails on the first (exit 1) and succeeds on the second. Assert: log still contains the failed entry, log no longer contains the succeeded entry, summary shows `synced:1, failed:1, pending:1`.
- **Implement:** wrap each `eval` in an `if` block; on success call `cmd_idea_sync --ack "$ts" "$project_dir"` (in-process — no fork) and append a result-row JSON to an accumulator; on failure capture stderr, append a failure-row, do NOT ack.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-5 green; AC-1–AC-4 still green.

### Step 5: final JSON summary + exit code (AC-6)
- **Test:** assert exit 0 when all succeed, non-zero when any fail; assert JSON shape includes `entries:[{ts,op,result,error?}]` per entry.
- **Implement:** finalize accumulator → `jq -n` envelope; exit code derived from `failed` count.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-6 green; full file green.

### Step 6: `\n`-escape regression (AC-7)
- **Test:** seed log with an `add` entry whose body literally is `"## What\n\nfirst paragraph\nsecond paragraph"` (JSON-escaped `\n`); run replay through the stub; assert the stub captured a description with REAL newlines (i.e. the recorded argv shows `printf` output where `## What`, `first paragraph`, `second paragraph` are on separate lines), AND that no `jq: parse error` appears on stderr.
- **Implement:** if Step 2's iteration pattern is `jq -c '.[]' <(...)`, this should already pass — the test exists to lock the contract. If it doesn't pass, fix the iteration to use file-direct `jq -r` reads.
- **Files:** `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-7 green.

### Step 7: resolver wiring (AC-8)
- **Test:** new bats line in the same file: `operations.sh resolve idea.sync --project-dir .` returns `.invocation.command` containing `idea-pending-replay` (NOT `idea-sync`). Test both Linear-routed and local-routed projects.
- **Implement:** in `.ccanvil/scripts/operations.sh`, change line 349 (local adapter) AND the Linear adapter case (line 616 — currently delegates to `local_adapter "$op"`) to point at `docs-check.sh idea-pending-replay`. Local branch: literal cmd string. Linear branch: still delegates to local adapter so the change happens once.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/idea-pending-replay.bats`.
- **Verify:** AC-8 green; existing operations.bats / ccanvil-json-override.bats still green (no regressions on idea.sync resolution shape).

### Step 8: skill prose collapse (AC-9)
- **Test:** new bats `hub/tests/idea-skill-sync-collapse.bats` — assert the `## Sync` section in `.claude/skills/idea/SKILL.md` contains exactly one `eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"` form and does NOT contain a per-op `case "$op" in` block (AC-10 drift-guard). Negative-grep for `case "$op"` between the `## Sync` heading and the next `## ` heading.
- **Implement:** rewrite `## Sync: /idea sync` section in `.claude/skills/idea/SKILL.md`. New form: 4-line resolve+eval+render. Keep the per-op dispatch table as documentation prose with a "before BTS-179" note explaining it now lives in substrate.
- **Files:** `.claude/skills/idea/SKILL.md`, `hub/tests/idea-skill-sync-collapse.bats`.
- **Verify:** AC-9, AC-10 green.

### Step 9: live-API validation gate (BTS-171)
- **BLOCKING gate before commit and before /review.** This step is required because the spec's Implementation Notes flag the eval-with-stdin-JSON contract as the surface that broke at the skill-prose layer. Stub-only tests pass any shape; only live calls verify contract.
- **Live command to run:** create a real pending entry on this branch (fresh idea body containing `\n` escapes), run `bash .ccanvil/scripts/docs-check.sh idea-pending-replay`, confirm the actual Linear ticket gets created with intact newlines in the description (read back via `linear-query.sh get-issue <id>` or the Linear UI screenshot in the PR body). Then `/idea triage` the resulting test ticket → dismiss to clean up.
- **Verify:** test ticket created, description shows real newlines, log is empty post-run, exit 0.

### Step 10: full-suite + docs update
- **Verify:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green (1430 → ~1445).
- **Docs update:** preset-infra change → update relevant `.ccanvil/guide/` files. Specifically `.ccanvil/guide/script-reference.md` (or equivalent) needs an `idea-pending-replay` entry. Skip if the guide doesn't have a matching section yet — the substrate is self-documented in `cmd_idea_pending_replay`'s comment block.

## Risks

- **Subshell stdin-JSON edge cases.** `jq -n | eval "$cmd --input-json -"` relies on `linear-query.sh save-issue --input-json -` reading stdin. If the wrapper changes that contract, replay breaks. Mitigation: AC-7's regression test exercises this path with `\n` escapes, which is the most fragile case.
- **Stub design drift.** Step 2-5 tests use a PATH-injected stub for `linear-query.sh`. If `operations.sh` ever resolves an absolute path to the wrapper, the stub stops intercepting. Mitigation: spot-check the resolver's `.invocation.command` in Step 2's setup; if it's already absolute, switch to overriding `$PATH` with the stub directory first.
- **Dual resolver branches.** Linear adapter for `idea.sync` (line 616) currently delegates to `local_adapter`. If a future refactor inlines the Linear branch, AC-8 might silently fail on the Linear path. Mitigation: AC-8 test explicitly resolves on a Linear-routed fixture.

## Definition of Done

- [ ] All 10 acceptance criteria from spec pass
- [ ] Live-API validation (Step 9) succeeded — test ticket created with intact `\n` round-trip
- [ ] All 1430+ existing tests still pass via `bats-report.sh --parallel`
- [ ] Skill prose `## Sync` section is single resolve+eval form
- [ ] Code reviewed (run `/review` — substrate-tier ship, /review is required per skip-review-on-trivial-diffs memory)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
