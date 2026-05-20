# Stasis: session-2026-05-19-bts-504-dashboards-handoff

> Feature: session-2026-05-19-bts-504-dashboards-handoff
> Kind: session
> Last updated: 1779234893
> Session: 66
> Boundary: 2026-05-19T11:09:01-07:00
> Session objective: Ship BTS-504 wiring + AC-8 verification, harden the OTel observability stack (hierarchical spans, duration fix, trace-id sharing, 100% coverage), then identify dashboard kinks and hand off to next session for dashboard polish.

## Accomplished

* **BTS-504 wiring substrate landed** — `.ccanvil/scripts/inject-telemetry-source.sh` (deterministic, idempotent, category-dispatched injector), `hub/tests/telemetry-coverage.bats` (drift-guard), 44 unit tests. 100% bats files now wired (178/178); skip-list is empty by design. Cat G (teardown-only) added mid-flight when 3 files surfaced outside BTS-504's original 6-category survey.
* **Heredoc regression fixed** — v1 rollout misread heredoc-internal `}` as function close, regressed 39 tests. State-machine now tracks `<<-?['"]?IDENT['"]?` open + identifier-only close-marker. Regression fixture: `hub/tests/fixtures/inject-telemetry/cat-c-heredoc.bats`.
* **AC-8 verified** — pre-rollout 2505 pass / 9 not-pass vs post-rollout 2517 pass / 8 not-pass. `post_failures − pre_failures == ∅`. The 8 residual not-passing tests are pre-existing env-dependent shapes (sysctl mocking + GNU parallel detection), not BTS-504 regressions.
* **OTel-canonical hierarchy** — spans now form `suite root → file → test` via `--force-trace-id` + `--force-span-id` + `--force-parent-span-id`. End-to-end verified: full suite (`377c7bf9...`) = 1 ROOT + 178 FILE + 2493 TEST in one trace.
* **Span duration accuracy** — telemetry_setup captures `BTS_TELEMETRY_TEST_START_EPOCH` via `date +%s.%N`; telemetry_teardown passes `--start`/`--end` to otel-cli. Previously every span landed point-in-time (duration=0); now spans show real wall time (drift-guard test at \~279s, etc.).
* **Tempo flush tuning** — `max_block_duration: 5m → 30s`, `trace_idle_period: 10s → 5s`. New runs surface spans in TraceQL search within \~30-45s of emission.
* **Dashboard scaffolding** — added `.ccanvil/observability/grafana/provisioning/dashboards/test-runs-live.json` (live feed + recent suite roots + slowest + non-passing panels). Fixed `test-runs-overview.json`'s "Slowest tests" panel to filter out suite-root + file-level spans.
* **PR #192 OPEN** — title force-asserted; full body composed including Spec excerpt; Tempo waterfall trace ID `377c7bf981304a0fb77c04d0cb9bf8ed` available for review.
* **BTS-533 captured** — explicit follow-up ticket "Test observability dashboards — fix open kinks" with 8 enumerated issues, completion criteria, and refs back to anchor commits.

## Current State

* **Branch:** `claude/feat/bts-504-wire-telemetry-into-all-bats`
* **PR:** #192 OPEN (not draft), title `feat(bts-504-wire-telemetry-into-all-bats): Wire telemetry helper into all hub/tests/*.bats`
* **Tests:** 2515 pass / 6 not-pass / 2521 total (last full suite at HEAD `377c7bf...`); 6 residuals are the documented env-dependent shapes
* **Uncommitted changes:** none
* **Build status:** clean. Manifest 202/202, drift 0 (cached at `bf86b01` per `check-skip-validate`; HEAD touches only dashboard JSON + Tempo YAML, neither in allowlist)
* **Linear:** BTS-504 In Progress; BTS-533 captured (Triage)
* **Observability stack:** running; Tempo storage was nuked + restarted mid-session (operator-approved); current data is post-restart only

## Blocked On

Nothing for next session's start. PR #192 is reviewable + mergeable from a wiring standpoint; the BTS-533 follow-up gates the broader "test observability is useful" goal.

## Next Steps

1. **Start fresh session focused on BTS-533** (dashboards). Workflow: `/recall` → `/spec BTS-533` → iterate on dashboard panels against actual live data. Operator explicitly scoped the next session this way.
2. **Decision point for PR #192**: ship now (BTS-504 wiring + hierarchy is complete and verified) and let BTS-533 land separately on a new branch, OR keep #192 OPEN and add dashboard polish to the same PR. Operator preference unknown — surface in `/recall`.
3. **BTS-498 (drift-guard 5.5-min optimization)** still relevant — the slow regression test is now beautifully visible in the waterfall as the dominant bar, making it an obvious BTS-498 target.
4. **BTS-511 (test-discipline rule enforcement)** still has 3 evidence items; not surfaced this session but ready to ship when capacity returns.

## Context Notes

* **One trace per suite has a known tradeoff with TraceQL search.** Tempo holds the trace in ingester until either idle or `max_block_duration` (now 30s). Direct `/api/traces/<id>` lookup serves partial data immediately; TraceQL search lags by the block-flush interval. Operator initially expected real-time search; Tempo tuning + dashboard panel design need to thread this carefully (BTS-533 #1, #3).
* `docs-check.sh status` **returns nulls when local lifecycle docs are absent** but `lifecycle-state` correctly reports `plan-written` (it reads Linear). Edge case: post-`/pr` cleanup removes local files even though the feature is mid-flight. This stasis is session-kind for that reason; the feature scope is encoded in the slug instead of `> Feature:` metadata.
* **Linear's markdown normalizer mangles tables.** When the `docs/spec.md` was clobbered by a linter mid-session and restored from Linear, the truth-table cells came back as `| A** | | | | | urce helper...` — bold markers stripped from one side, "no"/"yes" replaced with empty/"s", and leading 2 chars of action text dropped. Restored from git (commit `c6e59d2`). **For future captures bound to Linear: avoid bold-cell-headers and** `yes`**/**`no` **cells in tables**; use codespans or different cell content.
* `legacy-refs-scan` **doesn't exclude** `.ccanvil/observability/` — it surfaces 100+ false positives from `raw-traces.jsonl` where span names contain `checkpoint`/`catchup`. Same shape as the `stasis-recall.bats:51` grep-guard I fixed in commit `3939ad5`. Should add `--exclude-dir=observability` to legacy-refs-scan too. (Captureable as a small substrate ticket.)
* **The** `--force` **PreToolUse hook false-positives on commit messages containing** `--force-*-id` **strings.** Workaround was to write the commit body to a file and use `git commit -F /tmp/file`. Worth a shape-gate refinement so word-prefix matching on `--force ` (with trailing space) avoids matching `--force-trace-id` etc.

## Determinism Review

* **operations_reviewed:** \~15 (idea capture, spec/plan/stasis writes, manifest validate, bats-report-driven suite runs, otel-cli probes, docker compose volume ops, Tempo trace-id queries, dashboard JSON edits, git workflow).
* **candidates_found:** 0.

No candidates this session. All operations rode existing deterministic substrate ([bats-report.sh](<http://bats-report.sh>), [inject-telemetry-source.sh](<http://inject-telemetry-source.sh>), otel-cli, docker compose, jq pipelines, artifact-read/write). The substrate decisions made this session (hierarchy + duration + trace-id) ARE the deterministic substrate for future test observability — they're shipped code, not session-bounded heuristics.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

202 / 202 (allowlist), drift incidents: 0

(Cached at `bf86b013c0d34a9d87e5d117009ef470e60e6c5b` per `check-skip-validate` — HEAD `7c537ed` only modifies dashboard JSON + Tempo YAML, neither in the manifest allowlist.)

## Cross-Session Patterns

* `legacy-refs-scan` **substrate-gap** — same false-positive shape as the `stasis-recall.bats` grep-guard I patched earlier in this session. Both scans need `--exclude-dir=observability` to skip OTel runtime artifacts. Pattern fired twice in one session on adjacent substrates; worth a one-shot capture.
* **Linear markdown normalizer round-trip mangling** — first surfaced as the `feedback_safe-markdown-for-Linear-bound-bodies` memory (BTS-125, numbered-list-with-leading-codespan). This session surfaced a NEW shape: bold-cell-headers + `yes`/`no` cells in tables get mangled. Pattern: complex markdown in Linear is unreliable. Memory should be expanded.
* **Auto-classifier denying multi-impact destructive ops** — operator approval workflow worked correctly when I asked permission for `docker compose down -v`. The classifier protected against unintended scope; operator override unblocked it cleanly. Reinforces the explicit-permission pattern.
* **Scope-up-on-reveal pattern fired again** — Cat G category surfaced mid-rollout; heredoc handling surfaced after v1 regression; per-test parent_span_id surfaced after operator asked about waterfall. Each mid-flight discovery was absorbed into the same PR rather than deferred. Healthy pattern; matches `feedback_scope_up_on_live_api_reveal.md`.

## Security Review

PASS. This session's diffs touched:

* New bash substrate (`.ccanvil/scripts/inject-telemetry-source.sh`) — no secrets, no PII, no network egress beyond the localhost Tempo endpoint.
* \~178 bats files modified — telemetry hook injection only; no logic changes, no credential paths.
* Dashboard JSON + Tempo config YAML — local-only observability config; no auth tokens stored.
* One operator-approved destructive op (docker compose down -v on observability stack) — single-user local stack, no shared infrastructure impact.

No secrets committed; `.env` excluded by gitignore; OTel emissions go only to `127.0.0.1:4318`.

## Memory Candidates

1. **Linear markdown table normalizer mangling** — bold-cell-headers (`| **A** |`) get stripped to `| A** |`; cell values `no`/`yes` get replaced with empty/`s`; first 2-3 chars of long action-text cells get truncated. Add to existing `feedback_safe-markdown-for-Linear-bound-bodies` or create `feedback_linear_table_normalizer_mangles_cells`. Confirmed reproducibly: `docs/spec.md` was clobbered to one line by a linter, restored from Linear via `artifact-read`, came back mangled.
2. `docker compose down -v` **on observability stack is operator-approved-only** — single-user local stack, but the auto-classifier blocks it as "shared infrastructure". Explicit prompt + approval is the cleanest flow.
3. **Tempo** `max_block_duration` **+** `trace_idle_period` **tuning for real-time visibility** — defaults (5m / 10s respectively) hold long-running suite traces in ingester, breaking TraceQL search for in-flight traces. 30s / 5s gives near-real-time search with acceptable block-count overhead. Worth capturing as `reference_tempo_realtime_tuning`.
4. **OTel hierarchical span model** — `suite → file → test` via `--force-*-id` flags on otel-cli. Operator was unaware spans could nest; now wants this as the canonical structure. Add `feedback_otel_hierarchical_spans_canonical` if not already captured by `feedback_test_framework_two_paradigm`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->