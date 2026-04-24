# Implementation Plan: Auto-close linked Linear issue on PR merge

> Feature: bts-119-auto-close-linear-on-merge
> Work: linear:BTS-119
> Created: 1777004190
> Spec hash: 1fcf1704
> Based on: docs/spec.md

## Objective

Wire the post-merge land flow to the existing BTS-128 `ticket.transition` primitive and BTS-130 `> Work:` metadata so that the linked Linear issue auto-transitions to `Done` without any manual state flip — with a pending-log fallback that replays via `/idea sync` on MCP failure.

## Sequence

### Phase 1 — `cmd_extract_work` helper (AC-2 foundation)

#### Step 1 — RED: test Linear `Work:` extraction
- **Test:** `hub/tests/auto-close-linear-on-merge.bats` — `cmd_extract_work <spec-file>` returns `{"provider":"linear","id":"BTS-119"}` JSON for a spec with `> Work: linear:BTS-119`.
- **Implement:** none yet — confirm failing with "unknown command: extract-work".
- **Files:** `hub/tests/auto-close-linear-on-merge.bats` (NEW)
- **Verify:** `bats hub/tests/auto-close-linear-on-merge.bats` — Step 1 test fails for the right reason (not "Unknown option" drift from BTS-128's Phase 1 trap).

#### Step 2 — GREEN: implement `cmd_extract_work`
- **Test:** Step 1 passes.
- **Implement:** Add `cmd_extract_work <spec-file>` to `docs-check.sh`. Reuses existing `parse_metadata` helper (line 130-ish), reads `.work`, splits on first `:` into `provider`+`id`, emits `{"provider":"<p>","id":"<i>"}`. Empty output when `Work:` is absent or malformed.
- **Files:** `.ccanvil/scripts/docs-check.sh`, wired into the dispatch switch at line 2130-ish.
- **Verify:** Step 1 green.

#### Step 3 — RED+GREEN: edge-case coverage
- **Test:** Add bats cases: missing `Work:` → empty stdout + exit 0; malformed `Work: just-no-colon` → empty + exit 0; `Work: local:idea-29` → `{"provider":"local","id":"idea-29"}`.
- **Implement:** Refine parser if edges fail; use combined `jq -e '.provider == "linear" and .id == "BTS-119"'` asserts per BTS-128 pattern.
- **Files:** `hub/tests/auto-close-linear-on-merge.bats`, maybe `.ccanvil/scripts/docs-check.sh`.
- **Verify:** All edge tests green.

### Phase 2 — `cmd_land` intent emission (AC-5, AC-6, AC-7, AC-9)

#### Step 4 — RED: test `cmd_land` emits AUTO-CLOSE marker
- **Test:** Fixture branch name `claude/feat/bts-119-auto-close-linear-on-merge` + fixture spec archive with `> Work: linear:BTS-119`; invoke `cmd_land` in `--force` mode (bypass merged-PR check); assert stdout contains `AUTO-CLOSE: {"provider":"linear","id":"BTS-119","role":"done"}`.
- **Implement:** none yet.
- **Files:** `hub/tests/auto-close-linear-on-merge.bats`
- **Verify:** test fails; stdout has no marker.

#### Step 5 — GREEN: extend `cmd_land`'s branch-regex safety net
- **Test:** Step 4 passes.
- **Implement:** Inside the existing `[[ "$branch" =~ ^claude/[^/]+/(.+)$ ]]` block in `cmd_land` (line 1075-ish), after the archive-Complete safety net: call `cmd_extract_work "$safety_spec_file"`; if `.provider == "linear"` and `.id` non-empty, emit `AUTO-CLOSE: <json-with-role-done>` to stdout.
- **Files:** `.ccanvil/scripts/docs-check.sh`
- **Verify:** Step 4 green.

#### Step 6 — RED+GREEN: skip paths
- **Test:** 4 bats cases:
  1. Legacy spec without `Work:` → no AUTO-CLOSE marker; no error; exit 0 (AC-5).
  2. `Work: local:idea-29` → no marker; single log line `auto-close: local provider — skipping (BTS-119 Linear-only)`; exit 0 (AC-6).
  3. `Work: github:42` → no marker; log `auto-close: provider 'github' — no adapter, skipping`; exit 0 (AC-7).
  4. Branch `hotfix/something` (doesn't match `claude/*/*`) → no marker; no auto-close log; exit 0 (AC-9).
- **Implement:** Branch on `$provider` in the extended block; emit skip logs per case; return without marker.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/auto-close-linear-on-merge.bats`.
- **Verify:** All 4 cases pass.

### Phase 3 — `/land` skill dispatches MCP (AC-1, AC-3, AC-8)

#### Step 7 — Create `.claude/commands/land.md`
- **Test:** n/a (skill prose — no bats); validated by smoke-test Step 12.
- **Implement:** New `/land` command.md that:
  1. Runs `bash .ccanvil/scripts/docs-check.sh land` and captures stdout.
  2. Greps the output for `^AUTO-CLOSE: ` — extracts the JSON payload.
  3. If payload present: calls `operations.sh resolve ticket.transition <id> done`, then dispatches MCP `save_issue` with the resolved `params`.
  4. On MCP failure: appends one JSONL line to `.ccanvil/ideas-pending.log` with `{"op":"ticket.transition","args":{"id":"<id>","role":"done"},"ts":<epoch>}`, logs `PENDING: auto-close queued for sync`, exits 0.
  5. On MCP success: logs `Auto-closed <id> → Done`.
  6. Documents that `save_issue` is idempotent for same-state transitions (AC-8 covered by Linear API semantics, not a test we write).
- **Files:** `.claude/commands/land.md` (NEW)
- **Verify:** Manual read; cross-check with `/idea` skill's same-shape MCP-failure path.

#### Step 8 — Update `/pr` docs to point at `/land` as the canonical post-merge step
- **Test:** n/a (docs).
- **Implement:** Edit `.claude/commands/pr.md` Rules section line 73 from `run \`docs-check.sh land\`` → `run \`/land\` (or \`docs-check.sh land\` if not using the skill — auto-close will not fire)`.
- **Files:** `.claude/commands/pr.md`
- **Verify:** One-line diff; skill guidance unambiguous.

### Phase 4 — `/idea sync` handles `ticket.transition` op (AC-4)

#### Step 9 — Extend `/idea sync` dispatch table
- **Test:** bats case (maybe in `auto-close-linear-on-merge.bats`): pending log with one `{"op":"ticket.transition","args":{"id":"BTS-119","role":"done"}}` entry; simulate `cmd_idea_sync` — assert the entry count stays 1 (shell side doesn't ack; skill side does on MCP success, but that's not bat-testable). Real test: `cmd_idea_sync` **does not choke** on the unknown op (doesn't error-out).
- **Implement:** Two surfaces:
  1. `.claude/skills/idea/SKILL.md`: add row to the sync dispatch table for `op:"ticket.transition"` → "resolve `ticket.transition <args.id> <args.role>`, dispatch save_issue with resolved params".
  2. `docs-check.sh cmd_idea_sync`: ensure `ticket.transition` entries are listed/read identically to other ops (they should be — entries are opaque JSON lines). Add an explicit test to lock in.
- **Files:** `.claude/skills/idea/SKILL.md`, `hub/tests/auto-close-linear-on-merge.bats`.
- **Verify:** Step 9 bats green.

### Phase 5 — Documentation + smoke test

#### Step 10 — Update command-reference guide
- **Test:** n/a (docs).
- **Implement:** Add `/land` to `.ccanvil/guide/command-reference.md` (the Claude commands table). Note the auto-close behavior and pending-log fallback.
- **Files:** `.ccanvil/guide/command-reference.md`
- **Verify:** Read-through.

#### Step 11 — Full suite + new bats file pass
- **Test:** `bats hub/tests/` — all existing 850 tests still green; new `auto-close-linear-on-merge.bats` adds ~8-10 tests.
- **Implement:** Fix any drift (esp. `legacy-refs-scan.bats` if `/land` reference triggers hub-reference hits).
- **Files:** possibly `hub/tests/legacy-refs-allowlist.txt` if any legacy-ref scan needs updating.
- **Verify:** Green suite.

#### Step 12 — Smoke test AC-1 via dogfood close (real live path)
- **Test:** After squash-merge of PR #48 and running `/land`, BTS-119 shows status `Done` in Linear without manual intervention.
- **Implement:** n/a — feature IS the test.
- **Files:** n/a.
- **Verify:** Run `mcp__claude_ai_Linear__get_issue BTS-119` post-land; assert `status: "Done"` and `completedAt` non-null.

## Risks

- **Branch-regex coverage gap:** cmd_land's existing regex `^claude/[^/]+/(.+)$` requires the `claude/<type>/<name>` convention; non-conventional branches skip (AC-9 covers this). Mitigation: explicit test in Step 6.
- **Intent marker parsing ambiguity:** `AUTO-CLOSE:` prefix on stdout could collide with unrelated output if someone greps for it in other contexts. Mitigation: use a specific, unusual marker and grep with `^AUTO-CLOSE: ` anchor.
- **MCP idempotency unverified at the bats layer:** AC-8 relies on Linear API behavior we can't easily mock in bats. Mitigation: treat AC-8 as smoke-test-only + explicit comment in spec (spec already notes this). Same pattern as BTS-128's AC-4.
- **Direct-script-invocation users miss auto-close:** Users running `docs-check.sh land` directly (not via `/land` skill) won't get the MCP dispatch — intent goes to stdout, nothing reads it. Mitigation: Step 8 updates `/pr` docs to explicitly point at `/land` as the canonical post-merge path. Users calling the script directly can run `/idea sync` to dispatch queued ops.
- **Pending-log op-shape drift:** Adding `op:"ticket.transition"` is additive and shouldn't break existing replay paths, but the SKILL.md edit must be correct. Mitigation: Step 9 bats test locks the shape in.

## Definition of Done

- [ ] All 10 acceptance criteria from spec pass (AC-1 + AC-8 via smoke test; rest via bats).
- [ ] All existing 850 bats tests still pass.
- [ ] `auto-close-linear-on-merge.bats` added with ~8-10 new tests.
- [ ] `/land` skill created; `/pr` docs updated; command-reference updated.
- [ ] Code reviewed via `/review` before `/pr`.
- [ ] BTS-119 auto-closes via the wrapper it ships — dogfood moment parallel to BTS-128's close.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
