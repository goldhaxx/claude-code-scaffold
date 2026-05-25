# Implementation Plan: Workflow Observability C2 — session-trace correlation

> Feature: bts-544-session-trace-correlation
> Work: linear:BTS-544
> Created: 1779652930
> Spec hash: 3edd2f5a
> Based on: docs/spec.md

## Objective

Implement the SessionStart open hook (with reaper), the SessionEnd close hook, the bats-suite linkage attrs, the settings.json wiring, manifests + allowlist, and the live-Tempo verification — producing one rooted `ccanvil-session` trace per Claude Code session, with `session.id` (counter-epoch primary key) and `claude_session_id` (Claude UUID secondary correlation key) carried as span attrs.

## Sequence

Ordered red-green-refactor cycles. Targeted bats runs only mid-cycle (per `.claude/rules/test-discipline.md`); the full suite is the pre-merge gate at Step 11.

### Step 1: AC-2 — open writes state file (normal path)

* **Test:** `hub/tests/session-otel-hooks.bats` "AC-2 open writes state when none exists" — invoke `bash .claude/hooks/session-otel-open.sh` with stdin payload `{"hook_event_name":"SessionStart","session_id":"abc-uuid","source":"startup"}`. Assert exit 0; `.ccanvil/state/session-trace.json` exists with `trace_id ~ ^[0-9a-f]{32}$`, `root_span_id ~ ^[0-9a-f]{16}$`, `started_at_epoch ~ ^[0-9]+\.[0-9]+$`, `session_id ~ ^[0-9]+-[0-9]+$`, `claude_session_id = "abc-uuid"`. Use the `OTEL_SPAN_CLI=<recording-stub>` seam (same shape as `hub/tests/bats-report-end-to-end-trace.bats`) to assert ZERO otel-cli invocations at open time.
* **Implement:** create `.claude/hooks/session-otel-open.sh` mirroring `session-boundary.sh`'s skeleton — `set +e`; `CLAUDE_PROJECT_DIR` fallback; source `_lib/record-failure.sh` with no-op fallback; source `.ccanvil/observability/otel-span.sh`; read stdin once (`payload="$(cat -)"`); extract `claude_session_id` via `jq -r '.session_id // ""' 2>/dev/null <<<"$payload"`; read current `.ccanvil/state/session-counter` (post-bump value — `session-boundary.sh` ran first); compute `started_at_epoch=$(date +%s.%N)`, `session_id="<counter>-<epoch_seconds>"`; generate IDs via `otel_span_new_trace_id` / `otel_span_new_span_id`; atomic mktemp+mv write the JSON shape via `jq -n`.
* **Files:** `.claude/hooks/session-otel-open.sh` (new), `hub/tests/session-otel-hooks.bats` (new — Step 1 test).
* **Verify:** `bats hub/tests/session-otel-hooks.bats -f "AC-2 open writes state"` passes.

### Step 2: AC-2 edge — empty / malformed stdin → claude_session_id=""

* **Test:** extend the .bats with two cases — (a) empty stdin (`< /dev/null`), (b) malformed JSON (`<<< 'not json'`). Both must produce `claude_session_id=""` in the state file, exit 0, zero spans.
* **Implement:** confirm the `jq` invocation already swallows malformed JSON via `2>/dev/null` and falls back via `// ""`. Adjust if the Step 1 cut had a stricter shape.
* **Files:** `.claude/hooks/session-otel-open.sh`, `hub/tests/session-otel-hooks.bats`.
* **Verify:** targeted bats run.

### Step 3: AC-3 — close hook emits rooted span

* **Test:** pre-seed `.ccanvil/state/session-trace.json` with known fields (non-empty `claude_session_id`); set `OTEL_SPAN_CLI` to a stub recording argv to a file; run `bash .claude/hooks/session-otel-close.sh`. Assert the stub recorded EXACTLY ONE invocation with `--service ccanvil-session`, `--name ccanvil-session`, `--force-trace-id <state.trace_id>`, `--force-span-id <state.root_span_id>`, NO `--force-parent-span-id`, `--attrs` containing `session.id=<id>`, `git.sha=<sha>`, `claude_session_id=<uuid>`. State file is removed.
* **Implement:** create `.claude/hooks/session-otel-close.sh` — same skeleton as the open hook; read state file via `jq` (fail-soft on missing: WARN + record-failure + exit 0); `end_epoch=$(date +%s.%N)`; sanitize attrs via `otel_span_sanitize`; emit via `otel_span_emit --service ccanvil-session --name ccanvil-session --trace-id ... --span-id ... --start ... --end ... --attrs "..."`; on success (`$?` from emit is structurally 0), `rm -f` the state file.
* **Files:** `.claude/hooks/session-otel-close.sh` (new), `hub/tests/session-otel-hooks.bats` (extend).
* **Verify:** targeted bats run.

### Step 4: AC-3 — omit-when-empty + duration ≥ 0

* **Test:** (a) pre-seed state with `claude_session_id=""` → recorded `--attrs` string MUST NOT contain `claude_session_id=` (assert via `grep -vF` — never BRE `\|` per the bats-grep gotcha). (b) parse recorded `--start` / `--end` floats; assert `end >= start`.
* **Implement:** conditional attr append in the close hook — only add `claude_session_id=<v>` when `[[ -n "$claude_session_id" ]]`.
* **Files:** `.claude/hooks/session-otel-close.sh`, `hub/tests/session-otel-hooks.bats`.
* **Verify:** targeted bats run.

### Step 5: AC-4 — reaper for abnormal exit

* **Test:** pre-seed a stale `.ccanvil/state/session-trace.json` (`session_id=99-1234567890`, `claude_session_id=stale-uuid`); attach `OTEL_SPAN_CLI` stub; invoke the open hook with a fresh stdin payload. Assert the stub recorded EXACTLY ONE invocation (the reaper) with `--service ccanvil-session`, `--name ccanvil-session`, `--force-trace-id <stale.trace_id>`, `--force-span-id <stale.root_span_id>`, `--attrs` containing `reaper=true`, `session.id=99-1234567890`, `claude_session_id=stale-uuid`. After the hook returns, the state file content is the NEW session's IDs (not the stale ones).
* **Implement:** in `session-otel-open.sh`, before the new-state write, `if [[ -f "$STATE_FILE" ]]; then` read the stale state, build a reaper attrs string with `reaper=true` + stale `session.id` + stale `claude_session_id` (omit-when-empty), `otel_span_emit ... --start "$stale_started_at_epoch" --end "$(date +%s.%N)"`. Then continue to overwrite.
* **Files:** `.claude/hooks/session-otel-open.sh`, `hub/tests/session-otel-hooks.bats`.
* **Verify:** targeted bats run.

### Step 6: AC-5 — bats suite linkage

* **Test:** extend `hub/tests/bats-report-end-to-end-trace.bats` with one case — pre-seed `.ccanvil/state/session-trace.json`; run `bash .ccanvil/scripts/bats-report.sh --parallel --no-telemetry` with `OTEL_SPAN_CLI` recording stub; from the captured invocations, find the `test-suite-run` and `bats suite (...)` spans; assert their `--attrs` contain `session.id=<expected>` AND `claude_session_id=<expected>`. Negative: their `--force-trace-id` MUST NOT equal `state.trace_id` (link, do not merge).
* **Implement:** in `.ccanvil/scripts/bats-report.sh` near where `BTS_TELEMETRY_TRACE_ID` is cached (\~line 195-220), read `.ccanvil/state/session-trace.json` via `jq` (fail-soft when absent) into `BTS_SESSION_ID` + `BTS_CLAUDE_SESSION_ID` shell vars; append `,session.id=$BTS_SESSION_ID` (and `,claude_session_id=$BTS_CLAUDE_SESSION_ID` when non-empty) to the `--attrs` strings on the `bats suite` emission (line \~593) and the `test-suite-run` root emission (line \~643). Do not touch `manifest pre-warm` or `otel-flatten` spans (per spec AC-5 — only suite-root + bats-suite).
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-end-to-end-trace.bats` (extend).
* **Verify:** targeted run of the extended file + the existing 11 bats-report-end-to-end-trace tests still pass.

### Step 7: AC-6 — settings.json wiring

* **Test:** `hub/tests/session-otel-hooks.bats` "AC-6 settings wiring" — `jq` query asserts `.hooks.SessionStart | length == 2`, `.hooks.SessionStart[0].hooks[0].command` contains `session-boundary.sh`, `.hooks.SessionStart[1].hooks[0].command` contains `session-otel-open.sh`; `.hooks.SessionEnd | length == 1`, `.hooks.SessionEnd[0].hooks[0].command` contains `session-otel-close.sh`.
* **Implement:** edit `.claude/settings.json` — append the second SessionStart entry (preserving the existing one's position so the counter bumps first); add a new top-level `SessionEnd` block. Use jq or direct Edit; never re-write the file via cat-EOF (preserves comments / ordering of other top-level keys).
* **Files:** `.claude/settings.json`, `hub/tests/session-otel-hooks.bats`.
* **Verify:** targeted bats run; manual `jq '.hooks' .claude/settings.json` matches the asserted shape.

### Step 8: AC-7 — graceful-skip in three modes

* **Test:** three cases — (a) `CCANVIL_TELEMETRY_DISABLED=1` → zero recorded otel-cli invocations from either hook; (b) `OTEL_SPAN_CLI=/nonexistent/binary` → zero invocations (init detects missing binary, `OTEL_SPAN_LIVE=0`, `otel_span_emit` returns 0 silently); (c) bogus `CCANVIL_TELEMETRY_URL=http://127.0.0.1:1` → zero invocations (healthcheck fails). In all three: exit 0, ≥1 `WARN:` line on stderr, ≥1 JSONL entry in `.ccanvil/state/hook-failures.log`.
* **Implement:** in each hook, after `otel_span_init`, branch on `OTEL_SPAN_LIVE` — when `!=1`, emit a `WARN:` line + `_hook_record_failure "session-otel-{open,close}" "telemetry-skipped" "<reason>"`. Continue exit-0. The `otel_span_emit` calls themselves remain in the happy path; they'll silently no-op even if the OTEL_SPAN_LIVE branch is skipped.
* **Files:** `.claude/hooks/session-otel-open.sh`, `.claude/hooks/session-otel-close.sh`, `hub/tests/session-otel-hooks.bats`.
* **Verify:** targeted bats run.

### Step 9: AC-8 — manifests + allowlist

* **Test:** `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0; `coverage.covered == coverage.total`; `drift_count == 0`. Both new hook paths land in `.ccanvil/manifest-allowlist.txt`. Each hook contains a `# @manifest` block with: `purpose`, `input` (env + stdin), `output` (state file / spans / hook-failures.log / exit-0 / stderr), `caller` (`.claude/settings.json`), `depends-on` (`jq`, `date`, `mktemp`, `otel-cli`, `curl`, `git`), `side-effect` (`emits-otel-spans`, `writes-state-file` (open) / `removes-state-file` (close), `writes-stderr-warn-on-failure`), `failure-mode` (telemetry-skipped, mktemp-failure), `contract` (`never-blocks-session-lifecycle`, `best-effort-emission`), `anchor: BTS-544 (origin)`, `anchor: BTS-542 (umbrella)`.
* **Implement:** prepend `# @manifest` blocks to both hooks (mirror `session-boundary.sh:14-38`); append two lines to `.ccanvil/manifest-allowlist.txt`.
* **Files:** both hooks, `.ccanvil/manifest-allowlist.txt`.
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate` returns ok; `--json` shows `coverage.covered/total` incremented by 2 vs HEAD (expected 205/205).

### Step 10: AC-9 — live verification + smoke recipe

* **Live-API gate (BTS-171):** this step IS the live-API verification — execute BEFORE commit + before `/review`. The Claude Code SessionEnd contract reliability is the unknown; the reaper is the safety net (AC-4 covers the "didn't fire" case).
* **Test (live):** (a) `docker compose -f .ccanvil/observability/docker-compose.yml up -d` — stack live on 127.0.0.1. (b) simulate via `bash .claude/hooks/session-otel-open.sh < <(echo '{"hook_event_name":"SessionStart","session_id":"'"$(uuidgen)"'","source":"startup"}')` then `bash .claude/hooks/session-otel-close.sh < <(echo '{"hook_event_name":"SessionEnd"}')`. (c) Tempo search: `curl -s 'http://127.0.0.1:3200/api/search?q=%7Bname%3D%22ccanvil-session%22%7D&limit=5' | jq '.traces[0]'` returns at least one trace with non-zero `durationMs` from the past 60s. (d) reaper exercise: invoke open hook twice (no close between); query Tempo for the first run's `ccanvil-session` span carrying `reaper=true`.
* **Implement:** add a "Live smoke — ccanvil-session" section to `.ccanvil/observability/README.md` with the exact commands above (and the open-twice reaper recipe). No code change; docs only.
* **Files:** `.ccanvil/observability/README.md`.
* **Verify:** live Tempo query returns the expected span shape. Record the trace_id observed for the spec record.

### Step 11: Pre-merge gates (executed by /pr + /ship)

* `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green; new test count \~12 new tests on top of 2558.
* `bash .ccanvil/scripts/module-manifest.sh validate` — clean (205/205).
* `/review` — code-reviewer agent + security audit + self-review.
* `/pr` — push (already pushed) + commit lifecycle cleanup + mark draft ready + title-fix; then `/ship 196`.

## Risks

* **Claude Code hook-chaining model (load-bearing).** Spec assumes independent fd 0 per hook entry. AC-2's empty/malformed-fallback covers shared-fd failure mode by construction. Step 10's simulated invocation explicitly pipes the payload so the live contract gets exercised; observing `claude_session_id` populated on Tempo confirms the assumption.
* **SessionEnd firing reliability.** If Claude Code doesn't fire SessionEnd on certain exit paths (`/exit`, crash, Ctrl-C), the close hook never runs → state file stays → reaper covers on next SessionStart. Step 10's open-twice-without-close exercise validates the safety net.
* `OTEL_SPAN_INIT_DONE` **env-leak (BTS-560 lesson).** Hooks are terminal processes — env-leak risk is minimal. But Step 6's `bats-report.sh` edit MUST NOT call `otel_span_init` before the bats subprocess is spawned — the `_otel_trace_live` gate is the structural fix. Read `.ccanvil/state/session-trace.json` ahead of the bats subprocess (file read, not span emission — safe); span emission for the suite-root span already happens AFTER bats per the existing BTS-560 order.
* **BSD grep** `\|` **BRE gotcha (memory:** `reference_grep_env_dependent`**).** Inside bats, `grep` resolves to `/usr/bin/grep` (BSD). Use `grep -F` or `grep -E` for new assertions; never `\|`. The omit-when-empty assertion in Step 4 specifically must use `grep -vF` (fixed string).
* **otel-cli attr sanitization.** UUIDs from Claude session_id are dashed hex — no commas, sanitization is moot. But pass through `otel_span_sanitize` anyway as a defense-in-depth (the helper exists; AC-3's attrs string is comma-delimited).

## Definition of Done

- [ ] All 9 acceptance criteria from `docs/spec.md` pass (AC-2..AC-7 via the new `session-otel-hooks.bats`; AC-5 via the extended `bats-report-end-to-end-trace.bats`; AC-8 via `module-manifest.sh validate`; AC-9 via live Tempo query).
- [ ] Full bats suite passes (`bats-report.sh --parallel` — expected \~2570).
- [ ] Manifest validate clean (205/205, drift 0).
- [ ] Live `ccanvil-session` span observed in Tempo (AC-9).
- [ ] /review run clean (code-reviewer + security audit + self-review).
- [ ] BTS-544 squash-merged via `/ship 196`.
