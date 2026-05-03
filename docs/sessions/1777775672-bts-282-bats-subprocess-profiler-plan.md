# Implementation Plan: Bats subprocess profiler

> Feature: bts-282-bats-subprocess-profiler
> Work: linear:BTS-282
> Created: 1777771871
> Spec hash: 48e8f262
> Based on: docs/spec.md

## Objective

Land `.ccanvil/scripts/bats-profile.sh` as a PATH-shim profiler that runs a bats file, captures TSV trace lines per wrapped substrate invocation, and emits a JSON aggregation — without modifying any wrapped script.

## Sequence

Each step is one TDD cycle. Tests under `hub/tests/bats-profile.bats` use a temp `$WORK` dir (mirrors `bats-report.bats` pattern).

### Step 1: AC-5 + AC-3 + AC-4 — argv parsing + error paths

* **Test:** Run `bash bats-profile.sh /no/such/path` → assert exit 2 + `ERROR: bats target` on stderr. Run `bats-profile.sh --top 0 fixture.bats` → assert exit 2. Run `bats-profile.sh --top abc fixture.bats` → exit 2. Run `bats-profile.sh --wrap nope fixture.bats` → exit 2 + "not found". Run `bats-profile.sh --wrap docs-check.sh,module-manifest.sh fixture.bats` → exit 0 (no trace yet, but argv accepted).
* **Implement:** Skeleton script with arg loop: parses `--top N`, `--wrap a,b,c`, positional `<bats-file>`. Validates target existence. Validates --wrap targets resolve via `command -v` or `.ccanvil/scripts/<name>`. For passing-arg case, run `bats <fixture>` directly (no shims yet) and emit `[]` JSON.
* **Files:** `.ccanvil/scripts/bats-profile.sh` (new), `hub/tests/bats-profile.bats` (new).
* **Verify:** Bats passes.

### Step 2: AC-1 — passthrough fixture + shim seeding

* **Test:** `hub/tests/fixtures/bats-profile-passthrough.bats` exists and contains one `@test` that invokes `bash docs-check.sh status` and asserts a stable prefix. Run that fixture (a) directly via `bats` and (b) via `bats-profile.sh`. Assert exit codes match, `^ok ` count matches, `^not ok ` count matches, tail-3 of bats output matches between the two.
* **Implement:** `bats-profile.sh` now: creates a tempdir `$TMPDIR/bats-profile-$$/{bin,trace}`, generates one shim per `--wrap` target (each shim invokes `BATS_PROFILE_REAL_<UPPER>` and logs `<basename>\t<verb>\t<ms>` to `$TRACE_FILE`), prepends `$TMPDIR/.../bin` to PATH, runs bats with that PATH, then emits the aggregation. Trap cleans up the tempdir on EXIT.
* **Files:** `.ccanvil/scripts/bats-profile.sh`, `hub/tests/bats-profile.bats`, `hub/tests/fixtures/bats-profile-passthrough.bats` (new).
* **Verify:** AC-1 test passes; both runs match.

### Step 3: AC-2 — JSON aggregation shape

* **Test:** Run `bats-profile.sh hub/tests/fixtures/bats-profile-passthrough.bats`. `jq -e` assertions: result is array, each entry has `cmd, verb, count, total_ms, mean_ms` of correct types; entries sort by `total_ms` desc; at least one row's `cmd == "docs-check.sh"`.
* **Implement:** The aggregation jq pipeline (per spec implementation note) reads `$TRACE_FILE` as TSV via `jq -Rs ... split("\n")`. Empty trace → `[]`.
* **Files:** `.ccanvil/scripts/bats-profile.sh` (extend existing).
* **Verify:** Bats passes.

### Step 4: AC-3 — `--top N` cap

* **Test:** Stub trace data (skip the bats run by mocking `$TRACE_FILE` directly via a `--trace-from-file <path>` test-only override — OR just rely on the natural test producing >1 row, then `--top 1` returns 1 row). Asserts row count == N when N < total.
* **Implement:** Pass `--argjson top "$top"` into the jq pipeline; when `top > 0`, append `| .[:$top]` after the sort. Default `top = -1` (no cap).
* **Files:** `.ccanvil/scripts/bats-profile.sh`.
* **Verify:** Bats passes.

### Step 5: AC-6 — manifest declarations + drift-guard + allowlist

* **Test:** `bash module-manifest.sh validate --json` returns `status: ok`, drift 0. Self-application bats verb count bumped if the new script declares functions.
* **Implement:** Add `# @manifest` block to `bats-profile.sh` (function-level if multiple cmd\_\*; file-level if single entry point). Append the new path to `.ccanvil/manifest-allowlist.txt` in the right alphabetical/section position. Bump `hub/tests/module-manifest-self-application.bats` verb count if new verbs were added.
* **Files:** `.ccanvil/scripts/bats-profile.sh`, `.ccanvil/manifest-allowlist.txt`, `hub/tests/module-manifest-self-application.bats`.
* **Verify:** `validate --json` clean.

### Step 6: full-suite + live gate

* **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel hub/tests/` — must show `PASS: 1983+N / FAIL: 0` (existing 1983 + new bats-profile tests). Live gate: run `bash .ccanvil/scripts/bats-profile.sh hub/tests/bats-report.bats` and confirm output is valid JSON with at least one `docs-check.sh` row.
* **Implement:** No new code.
* **Files:** none.
* **Verify:** Suite green; live gate produces actionable JSON.

## Live-API validation gate (BTS-171)

Step 6's live gate is the contract test. Stubbed shims accept any TSV; only a real bats run with real substrate invocations proves the shim mechanism actually intercepts and records meaningful data. Required command BEFORE the final commit:

```bash
bash .ccanvil/scripts/bats-profile.sh hub/tests/bats-report.bats | jq 'length, .[0]'
```

Expected: a positive `length` and a top-row entry with non-zero `total_ms` and `cmd in ("docs-check.sh","module-manifest.sh","bats-report.sh")`.

## Risks

* **Shim-self-recursion.** If the shim invokes the wrapped script via `command -v` while PATH is prefixed, it calls itself. Mitigation: the wrapper resolves the real path BEFORE prepending PATH and bakes it into the shim as a `BATS_PROFILE_REAL_<UPPER>` env var.
* **Wrapper overhead inflates measurements.** Each shim adds \~5-10ms of overhead (perl Time::HiRes call ×2 + file append). Acceptable for ranking — the signal we care about is which scripts dominate, not absolute ms. Document the constraint in the manifest's `contract:` lines.
* **Manifest fields drift.** New script must declare `caller:` (none — operator-invoked), `depends-on: bats, jq, perl`, side-effect `writes-temp-file`. Easy to forget; drift-guard catches it.
* **Test fixture dependency on **[**docs-check.sh**](<http://docs-check.sh>)**.** AC-1 fixture invokes `docs-check.sh status` — that command must be stable and fast. It is (<100ms cached). If it ever becomes slow/flaky, swap the fixture's invocation to something simpler.

## Definition of Done

- [ ] All 6 ACs from spec pass
- [ ] All existing tests still pass
- [ ] Manifest validate green (drift 0)
- [ ] Live gate produces meaningful aggregation JSON
- [ ] Code reviewed (`/review`)
- [ ] PR ready for merge
