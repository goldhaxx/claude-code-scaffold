# Feature: Bats subprocess profiler

> Feature: bts-282-bats-subprocess-profiler
> Work: linear:BTS-282
> Created: 1777771781
> Subject: Bats subprocess profiler
> Status: Complete

## Summary

Add `.ccanvil/scripts/bats-profile.sh <bats-file>` — a profiling wrapper that runs a bats file with PATH-prefixed shims around hot substrate scripts (`docs-check.sh`, `module-manifest.sh`, configurable). Each shim logs `{cmd, verb, elapsed_ms}` to a temp trace file; the wrapper aggregates the trace into `[{cmd, verb, count, total_ms, mean_ms}]` sorted by `total_ms` descending. Pure observation — no modifications to the wrapped scripts. Pre-req for BTS-281's fork-pressure fixture work: data-driven prioritization of which substrate calls to share-cache.

## Job To Be Done

**When** I want to know which substrate primitives dominate per-test CPU during a bats run,
**I want to** invoke `bash .ccanvil/scripts/bats-profile.sh hub/tests/<file>.bats` and get a sorted top-N table by total elapsed ms,
**So that** BTS-281 can target the highest-leverage `setup_file()` fixtures with evidence rather than intuition.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** **Given** a self-contained bats fixture authored under `hub/tests/fixtures/bats-profile-passthrough.bats` that invokes `docs-check.sh status` once and asserts a fixed prefix of its stdout, **when** the fixture is run (a) directly via `bats` and (b) via `bash .ccanvil/scripts/bats-profile.sh hub/tests/fixtures/bats-profile-passthrough.bats`, **then** both invocations produce identical exit codes AND the same count of `^ok ` lines AND the same count of `^not ok ` lines AND the same tail-3 lines emitted by bats. The wrapped invocation MAY produce additional bytes (the JSON aggregation report on stdout) but the bats-emitted prefix lines must match exactly. Verified by parsing both runs' bats-output sections and comparing pass/fail counts + tail-3.

- [ ] **AC-2:** When `bats-profile.sh <path>` runs, it produces a JSON array on stdout shaped `[{cmd, verb, count, total_ms, mean_ms}]`. Each entry: `cmd` is the basename of the wrapped script (e.g., `docs-check.sh`); `verb` is the first positional arg passed to that script (e.g., `status`, `lifecycle-state`, or the literal `(none)` if no positional); `count` is integer ≥ 1; `total_ms` and `mean_ms` are integers ≥ 0; entries sort by `total_ms` descending. Verified via `jq -e` assertions on a fixture run.

- [ ] **AC-3:** When `bats-profile.sh --top N <path>` runs, the output array is capped to the N rows with highest `total_ms` (ties broken by `count` descending). N must be a positive integer; non-integer or zero exits 2 with an `ERROR:` on stderr. Verified by stubbing trace data and asserting the row count equals N.

- [ ] **AC-4:** When `bats-profile.sh --wrap <cmd>,<cmd>,... <path>` runs, the comma-separated list overrides the default wrapped set. Default set is `docs-check.sh,module-manifest.sh`. Each named script must exist on PATH or under `.ccanvil/scripts/` — unresolvable names exit 2 with `ERROR: --wrap target '<name>' not found` to stderr.

- [ ] **AC-5 (error path):** **Given** a bats file that does not exist, **when** `bats-profile.sh /no/such/path` runs, **then** the wrapper exits 2 with `ERROR: bats target '/no/such/path' not found` to stderr, without invoking bats and without leaving trace files behind. Verified by directory listing of the system temp dir before/after.

- [ ] **AC-6 (regression):** All existing tests in `hub/tests/` continue to pass when the suite is run through `bats-report.sh --parallel`. The new wrapper script's manifest entry passes drift-guard with the substrate's `validate --json` returning `status: ok`, drift count 0.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/bats-profile.sh` | New — orchestration: argv parse, shim seeding, trace aggregation, JSON emit |
| `.ccanvil/manifest-allowlist.txt` | Modified — add `.ccanvil/scripts/bats-profile.sh:cmd_main` (or whichever functions the manifest declares) |
| `hub/tests/bats-profile.bats` | New — AC-1/2/3/4/5 coverage; trace-data stubbing where helpful |
| `hub/tests/fixtures/bats-profile-passthrough.bats` | New — minimal bats fixture used by AC-1 to assert wrapper does not alter wrapped-script behavior |
| `hub/tests/module-manifest-self-application.bats` | Modified — bump verb count if the new script's manifest adds verbs |
| `.ccanvil/templates/manifest.md` | Modified (only if a new field shape is needed; default: no change) |

## Dependencies

- **Requires:** nothing. Stand-alone observation tool — does not depend on BTS-277's bats-runs.jsonl, but COMPOSES with it (the operator could profile a slow run, then check the jsonl trend to confirm regressions).
- **Blocked by:** nothing.

## Out of Scope

- **Wrapping `jq`, `bash`, or other ubiquitous tools.** The wrapper itself adds a fork per call; wrapping high-frequency primitives would inflate measurements and produce misleading attribution. Stick to top-level substrate scripts.
- **Per-function (intra-script) attribution.** "Which function inside `docs-check.sh` cost the most" is BTS-281 territory or a dedicated follow-up; this ticket measures script-level + verb-level only.
- **Continuous integration.** This is an on-demand operator tool, not a CI gate. Running in CI would require deciding on regression thresholds — a separate decision (and BTS-283 already covers soak-tracking as a separate concern).
- **Auto-recommendation of fixtures.** This ticket produces evidence; BTS-281 acts on it.

## Implementation Notes

- **Shim shape.** The wrapper writes shims to a private `bin/` dir under a tempdir, prepends that dir to `PATH`, then runs bats. Each shim is generated:
  ```bash
  #!/usr/bin/env bash
  start=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000')
  "REAL_PATH" "$@"
  rc=$?
  end=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000')
  printf '%s\t%s\t%d\n' "BASENAME" "${1:-(none)}" "$((end-start))" >> "$TRACE_FILE"
  exit $rc
  ```
  `REAL_PATH` is resolved at shim-generation time via `command -v` then de-aliased through PATH — protects against the shim self-recursion when PATH is prefixed.
- **Aggregation.** Read trace file as TSV (`cmd<TAB>verb<TAB>elapsed_ms`); pipe through `jq -Rs` with a grouping reducer:
  ```jq
  split("\n") | map(select(length>0) | split("\t") | {cmd:.[0], verb:.[1], ms:(.[2]|tonumber)})
    | group_by([.cmd, .verb])
    | map({cmd:.[0].cmd, verb:.[0].verb, count:length,
           total_ms:(map(.ms)|add), mean_ms:((map(.ms)|add)/length|floor)})
    | sort_by(-.total_ms)
  ```
- **PATH self-recursion guard.** The wrapper sets `BATS_PROFILE_REAL_<CMD>` env vars (e.g., `BATS_PROFILE_REAL_DOCS_CHECK=/abs/path/to/docs-check.sh`) so the shim invokes the resolved real path, not whatever currently resolves on PATH (which would be the shim itself).
- **Cleanup.** `trap 'rm -rf "$TRACE_DIR"' EXIT` ensures temp shim+trace are scrubbed even on bats failure.
- **Live-validation gate (BTS-171, TDD rule):** One AC-1 byte-identical check is a stub. Live-validate by running `bash .ccanvil/scripts/bats-profile.sh hub/tests/bats-report.bats` against a known-clean small bats file; assert (a) output JSON parses, (b) the table contains at least `docs-check.sh` and/or `module-manifest.sh` rows for tests that invoke them, (c) the wrapped suite still passes.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
