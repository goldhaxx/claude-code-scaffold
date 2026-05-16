# Test Performance — Research Lap (BTS-497)

> Status: Research-only, no implementation. Output of dedicated research session 2026-05-15.
> Work: linear:BTS-497
> Adjacent: BTS-118, BTS-127, BTS-137, BTS-263, BTS-277, BTS-282, BTS-283, BTS-383, BTS-460

## 0. Stated problem

Operator framing verbatim (2026-05-15, end of session 54):

> "Our testing sessions are taking the bulk of the development velocity again even though we recently did a lot of work to try and fix this. I think I had recently requested that all test runs have their run times stored so we can look back and see which tests are taking the most time… This is P0. It needs to happen immediately… We need to get test-level performance metrics that are collected every single time tests run, at all times, logged somewhere meaningful."

And the scoping directive that bounds this lap (2026-05-15):

> "Full analysis top to bottom. Clearly document and record how the testing system is set up and get our terminology dialed in because when we go out to research on the open market, we need to figure out how teams are grappling with tests and what they're doing."

This document is therefore three things in one: (1) an end-to-end inventory of the ccanvil test system as it stands today, (2) a glossary that lets us speak to outside literature in a shared vocabulary, and (3) the open question set that the next phase (market scan + spec) needs to answer.

No spec. No schema migration. No code change. The output of this lap is *understanding*.

## 1. The test system, end to end

The system has eight participating surfaces. Each has a single role; the relationships between them are what make the suite go.

### 1.1 The runner — `bats-core`

- Version: 1.13.0, installed via Homebrew (`brew install bats-core`), per `CLAUDE.md`.
- Bats is a TAP-emitting bash test framework. A *test* is one `@test "name" { ... }` block. A *test file* is one `.bats` file containing many `@test` blocks plus optional `setup`, `setup_file`, `teardown`, `teardown_file` hooks.
- Native flags that matter for us:
  - `-T` — emit per-test wall-time as `... in Nms` suffix on each TAP line.
  - `--jobs N` — run test files in parallel across N processes (requires GNU `parallel` installed on the host).
  - `-f <pattern>` — filter by test-name regex (not used in our automation path; available for operator one-offs).
- Bats native data exposed today: TAP stream on stdout, exit code, and (when `-T`) per-test wall-ms. **Nothing else.** No memory, no syscall counts, no CPU time, no fork count.

### 1.2 The wrapper — `.ccanvil/scripts/bats-report.sh`

The single canonical bats entry point. Anchored to BTS-118 (single-invocation discipline), BTS-137 (`--timings`/`--slow-top`), BTS-277 (perf-core default + `bats-runs.jsonl` write), BTS-383 (`--progress` per-file orchestration + heartbeat + per-failure detail).

Flags it accepts:

| Flag | Purpose |
|---|---|
| `--parallel` | Use `bats --jobs N` where N defaults to host's **performance-core** count (`sysctl -n hw.perflevel0.physicalcpu` on Apple Silicon — 12 on M4 Max), with fallback to `logicalcpu/2`. Silently degrades to serial with `WARN:` when `parallel` is not installed. |
| `--json` | Emit a single JSON envelope to stdout: `{ok, not_ok, total, tail, raw_exit, timings, failures, wall_ms, jobs, cpus}`. |
| `--timings` | Run with `bats -T` and append a sorted slowest-first table to human output (or populate `timings:[{test, ms}]` in `--json` mode). |
| `--slow-top N` | Implies `--timings`; truncates the table to N rows. `N=0` emits zero rows. |
| `--progress` | BTS-383 streaming mode. Two sub-modes: with `--parallel`, spawns a 30s heartbeat-only thread (TAP from parallel jobs is interleaved so per-file boundaries are unrecoverable). Without `--parallel`, orchestrates per-file: walks the test files, runs `bats <file>` per subprocess, emits `[N/M] file.bats: PASS X/Y in T.Ts` on stderr, aggregates TAP into the existing summary pipeline. |

Side effects:

- Writes one line to `.ccanvil/state/bats-runs.jsonl` per invocation. Schema (verbatim from the script):
  `{epoch, wall_ms, ok, not_ok, total, jobs, cpus, raw_exit, parallel, failures:[{test_name, file, line_number, error_excerpt}]}`.
- **Never persists per-test timings.** The `--timings` table goes to stdout and dies with the process.
- Pre-warms `module-manifest.sh validate --json` once into a tempfile (BTS-281) and exports `BTS_MANIFEST_VALIDATE_CACHE`, eliminating the dominant fork-pressure source.
- Writes the bats TAP to a tempfile, runs `tail`/`grep` derivations against it, removes on EXIT.

Failure parsing (BTS-383 AC-2): a perl one-liner that walks the TAP looking for `not ok N - <name>`, then attaches the indented `# (in test file <path>, line N)` and `# <excerpt>` annotations bats emits underneath. The resulting `failures` array is always present (empty `[]` on green).

Wall-time measurement: `perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000'` straddles the `bats_cmd` invocation. Millisecond precision on macOS + Linux; falls back to second-precision if perl is missing.

### 1.3 The provider dispatcher — `cmd_test_suite_run` in `docs-check.sh`

Anchored to BTS-460. The skill-facing entry point. Reads `<project-dir>/.claude/ccanvil.json` for `.test-provider` (falling back to `.stacks[0]`, defaulting to `bats`), then `exec`s the matching runner. Today the only implemented provider is `bats` → `exec bash bats-report.sh ...`. Any other provider returns exit 2 with `ERROR: test-provider '<X>' dispatcher not yet implemented`. Forwards `--parallel | --json | --timings | --progress | --slow-top N | --` to the runner. **Refuses zero-arg invocation** to prevent silent full-suite recursion (BTS-383 lesson).

This is the layer where future per-test-timing capture would be turned on suite-wide — flipping `--timings` from opt-in to default would live here.

### 1.4 The fork-pressure profiler — `.ccanvil/scripts/bats-profile.sh`

Anchored to BTS-282. **A different concern entirely from test wall-time.** Profiles a single bats file by intercepting `bash <path>/<wrapped-script>` calls via a PATH-prefixed bash shim, logging `{cmd, verb, elapsed_ms}` per invocation, then aggregating into a sorted JSON table `[{cmd, verb, count, total_ms, mean_ms}]`. Default wrap set: `ccanvil-sync.sh`, `linear-query.sh`, `docs-check.sh`, `module-manifest.sh`, `bats-report.sh`, `operations.sh`. Re-entry guarded via `BTS_PROFILE_INSIDE`.

This tool answers a structurally different question: *"when this bats file runs, which substrate verbs eat the CPU?"*. It does not (and is not designed to) answer *"which `@test` blocks across the whole suite are slow?"*. The two diagnostics are complementary; conflating them is what made BTS-282's framing distinct from BTS-497's.

### 1.5 The strict-mode linter — `.ccanvil/scripts/bats-lint.sh`

Anchored to BTS-127. Scans `.bats` files for any `@test` block containing ≥2 `jq -e` assertions without a leading `set -e` — the leak pattern where only the last assertion's exit code reaches bats. Heredoc bodies are skipped from `jq -e` counting; `run jq -e` is captured (status into `$status`) and skipped too. **Not a perf tool**, but lives in the same scripts directory and shares the same conceptual layer — worth listing here so the layer is documented in full.

### 1.6 Test files and helpers — `hub/tests/`

- 159 `.bats` files; one tracked support directory at `hub/tests/_helpers/`.
- Total tests in the suite as of 2026-05-15: **2338**.
- `hub/tests/_helpers/manifest-validate-cache.bash` (BTS-281) — shared `setup_file()` helper. Reads `$BTS_MANIFEST_VALIDATE_CACHE` (suite-level pre-warm from `bats-report.sh`) into `$BATS_FILE_TMPDIR/manifest-validate.json`; falls back to a per-file `module-manifest.sh validate --json` when invoked standalone. The cache eliminated the dominant fork-pressure source identified by `bats-profile.sh` evidence in BTS-282.

### 1.7 Persisted state — `.ccanvil/state/bats-runs.jsonl`

The only thing that survives a bats run today. One JSONL line per invocation, ever-growing. Current size:

- File size: 250 KB.
- Row count: 1,734.
- Schema: `{epoch, wall_ms, ok, not_ok, total, jobs, cpus, raw_exit, parallel, failures}`.
- Per-test array: **absent.**

### 1.8 Callers — who pulls the trigger

| Caller | Invocation | Cadence |
|---|---|---|
| `skill:/pr` | `docs-check.sh test-suite-run --parallel --progress` (pre-flight gate before push) | Once per `/pr` |
| `skill:/stasis` | `bats-report.sh --parallel` (state-of-the-suite line in the snapshot) | Once per `/stasis` |
| `.claude/rules/tdd.md` | Operator/agent ad-hoc (`bats <file>` or `bats-report.sh -f 'filter'`) | Iteration cadence — many times per session |
| `hooks/PostToolUse` (legacy, removed BTS-383) | Auto-run after every Edit | Removed by the BTS-383 discipline rule; mentioned here as documentation of what we explicitly chose to stop doing |
| CI workflow `ccanvil-checks.yml` (hub-distributed) | `lifecycle-docs` + `security` jobs only — **does NOT run the bats suite** today | n/a |
| CI workflow `ci.yml` (hub-distributed template, node-customized) | Node decides; template has a `TODO: Replace with your project test command` placeholder | Per-PR / per-push on the node |
| `bats-profile.sh` (developer tool) | `bash bats-profile.sh <bats-file>` | Ad-hoc, operator-driven |

A consequence worth surfacing: **the hub's own CI does not run the hub's bats suite.** All ratification happens locally at `/pr` time, instrumented by the operator's machine. CI is currently a docs/security gate, not a test gate. (See BTS-483 — Phase B of the CI consumption meta-loop — for the path to close this gap.)

## 2. The data we have, the data we don't

### 2.1 Inside-the-process data (ephemeral)

Each `bats-report.sh --timings` run produces, on stdout, the slowest-first per-test timing table for THAT run. It is not appended anywhere. The only way to capture it today is to redirect stdout to a file the operator names by hand.

### 2.2 Persisted aggregate data (longitudinal)

`bats-runs.jsonl` records run-level metadata across all 1,734 historical invocations. The aggregate distribution gives the macro shape:

| Run type | Count | wall_ms p50 | wall_ms p90 | wall_ms max | tests/run range |
|---|---|---|---|---|---|
| `parallel=false` (serial, mostly file-targeted) | 1,151 | 133 ms | 336 ms | 10,351 ms | 0–72 |
| `parallel=true` (overwhelmingly full-suite) | 583 | 713 ms | 344,252 ms | 1,975,606 ms | 0–2,338 |

The `parallel=true` distribution is bimodal: small `--parallel` invocations (file-targeted with `--jobs N`) dominate the count, full-suite runs dominate the wall time. Sliced to full-suite parallel runs only (`total >= 2000`, n=53), the picture is much cleaner:

| Metric | Value |
|---|---|
| Runs | 53 |
| ms per test, p10 | 169 ms |
| ms per test, p50 | 175 ms |
| ms per test, p90 | 188 ms |
| ms per test, max | 879 ms |

The 879 ms/test max is the BTS-263 parallel-output-flakiness outlier (1,975 s wall on a 2,246-test run — a single stuck job). With that excluded, the throughput band is **169–188 ms per test, full-suite, parallel-12**, and it has held remarkably steady across test-count growth from 2,189 to 2,338. This is the *characteristic throughput* of our suite.

Confirmed from the most recent 15 full-suite runs (2026-05-12 → 2026-05-15): walls cluster 387–443 s, totals 2,244 → 2,338. The +149 tests added in that window cost ≈ +6 s wall, consistent with the ≈40 ms median amortized per-test marginal cost in parallel mode.

### 2.3 What we cannot reconstruct

- **Per-test history.** No retroactive answer to "which test was slowest last Tuesday?" or "which test gained 200 ms over the last month?" exists. The data wasn't captured; it's gone.
- **Setup/teardown cost.** Bats `-T` reports per-`@test` wall; it does NOT separately report `setup`, `setup_file`, `teardown`, `teardown_file` cost. Fixture cost is folded into the test wall.
- **CPU time vs wall time.** We measure wall only. A test that spends 95% of its 500 ms wall blocked on a subprocess looks identical to one that spends 95% of it CPU-bound in jq.
- **Fork count / subprocess cost.** `bats-profile.sh` can answer this for a single file but is not part of the routine invocation path. The aggregate suite has no fork-cost record.
- **Resource pressure during the run.** No memory high-water mark, no IO counters, no parallel-scheduler queue depth.
- **Per-file roll-up.** Bats reports `[N/M] file.bats: ...` to stderr in BTS-383 progress mode, but that text is not persisted either.

### 2.4 The capture-overhead consideration

`bats -T` is the only mechanism that exposes per-test ms. Empirically the overhead is low — the same script paths run, with a `gettimeofday` straddling each `@test`. Whether it's low *enough* to flip on by default across all callers (every `/pr`, every `/stasis`, every operator one-off) is one of the open research questions; an in-session A/B before deciding is cheap.

## 3. Terminology — getting our vocabulary in shape

The intent of this section is to nail the terms we use internally so they round-trip cleanly to external literature. Where our usage diverges from common industry usage, that's called out.

### 3.1 Units of work

- **Test** — one `@test "name" { ... }` block in a `.bats` file. Industry-standard: "test case", "spec" (Mocha/Jest/RSpec), "example" (RSpec), "scenario" (Cucumber). All names map to the same thing: one named, independently-pass/fail unit.
- **Test file** — one `.bats` file, grouping related tests with shared `setup`/`teardown`. Industry: "spec file", "test module", "test class" (xUnit family).
- **Suite** — the full set of test files, normally `hub/tests/`. We use "suite" almost exclusively in the BTS-118 sense. Some communities use "suite" for what we call a "test file" — when reading external sources, expect this collision.
- **Sub-suite / targeted run** — a subset selected by file path or `-f <pattern>` filter. We do not have a stable name for this internally beyond "targeted run" (BTS-383). Industry: "shard", "slice", "selection".
- **Fixture** — the setup state a test depends on. Bats expresses this through `setup_file` (once per file), `setup` (once per test), and inverse `teardown_file`/`teardown` hooks. Most other ecosystems use the same word with the same semantics.
- **Helper** — shared bash functions called from multiple bats files (our `hub/tests/_helpers/`). Industry: "test utilities", "support library".

### 3.2 Time and measurement

- **Wall time / wall-clock time / elapsed time** — actual real-world seconds from start to end of the measured region. What `bats -T` reports. Most outside literature uses "wall time"; "elapsed" appears in older docs.
- **CPU time** — seconds the CPU spent executing the process's instructions, summed across all threads. Always ≤ wall × parallelism. Not collected by us today.
- **User vs system CPU time** — userland CPU vs kernel CPU. The `time` command in bash splits these; we don't capture either.
- **Throughput** — tests per second (or its inverse, ms per test). We informally state this in `/pr` summaries and stasis but don't compute it as a metric.
- **Latency** — for a single test, this is just its wall time. For the suite, the difference between "first test starts" and "last test finishes" — i.e., wall time. Industry sometimes distinguishes latency-from-queue-entry vs latency-from-execution-start; we don't.

### 3.3 Parallelism

- **Job** — one parallel worker spawned by `bats --jobs N`. Each job processes test files (not individual tests) from a queue. Bats does not parallelize tests within a file; the file is the parallelism granularity.
- **Performance cores** — Apple Silicon's high-throughput core type (vs efficiency cores). Default `N` in `bats-report.sh --parallel`. Industry: this is an Apple-specific distinction; on x86_64 hosts the script falls back to `logicalcpu/2`.
- **Sharding** — distributing tests across independent runners, typically across CI machines. We don't shard. Industry: a common technique for monorepos; CircleCI/GitHub/Buildkite all expose primitives.
- **Fork pressure** — our coined term (BTS-282) for the wall-time cost of spawning subprocesses (bash, jq, mktemp, perl) during test execution. Industry parallels: "process churn", "fork overhead". The BTS-281 fixture cache is the canonical fork-pressure mitigation we have today.

### 3.4 Test states and dispositions

- **Pass / fail** — TAP-native; one of `ok` or `not ok`.
- **Skip** — TAP-native; `ok N # SKIP <reason>`. Not currently surfaced by `bats-report.sh` as a distinct count (folded into `ok`).
- **Flaky** — passes sometimes, fails sometimes, on the same input. Industry term-of-art. We have one known flake class (BTS-263 parallel-output-flakiness) but no formal "flake" label or retry policy. The 11-fail row in 2026-05-12's `bats-runs.jsonl` is the BTS-263 manifestation.
- **Hermetic / non-hermetic** — a hermetic test depends only on its declared inputs and produces the same result everywhere. The opposite is a test that reaches outside its sandbox (network, host filesystem, real clock). Bats fixtures are hermetic-by-convention; we don't enforce.
- **Setup failure / teardown failure** — bats reports these as test failures with `# setup_file failed` or similar annotation. The 2026-05-10 row in `bats-runs.jsonl` with `not_ok=1, total=26, expected=29` is a setup_file failure cascading into 3 unrun tests — useful failure-pattern example.

### 3.5 Observability vocabulary

- **Profiling** — observing a single execution to identify which parts dominate the cost. `bats-profile.sh` profiles fork pressure.
- **Tracing** — recording an ordered series of events with timing context. We don't trace anything.
- **Instrumentation** — code added (or wrapped around) the system to emit observability data. `bats-report.sh`'s `_now_ms` straddling the bats call is instrumentation.
- **Telemetry** — the data emitted by instrumentation, flowing somewhere it can be analyzed. `bats-runs.jsonl` is our only telemetry today.
- **Soak** — running over a long time horizon to surface regressions or flakes that don't show up in a single run. BTS-283 (Backlog) proposes a "soak-tracking remote agent" that consumes `bats-runs.jsonl`. The term is OUR convention; industry sometimes uses "soak test" for a different meaning (extended-duration load test), so we should be careful when reading external sources.

### 3.6 Quality and SLO vocabulary

- **Slow test** — no formal threshold today. Practical use: above 1 s gets human attention; above 5 s gets a ticket.
- **SLO (service-level objective)** — a target threshold a system commits to meeting. For tests, this would be "p95 test wall < 500 ms" or similar. We don't have one.
- **Regression** — a test that newly takes longer than its historical baseline. Industry usage: "performance regression". Requires per-test history we don't have.
- **Test impact analysis (TIA)** — selecting only the tests affected by a code change instead of running the whole suite. Industry technique; Microsoft's TIA paper is the canonical reference. We don't do TIA.
- **Test selection / test prioritization** — broader term for any strategy that runs a subset (TIA is one form). Empirical research literature uses these interchangeably.
- **Mutation testing** — orthogonal to perf, mentioned only because it shows up in adjacent search results when researching test analytics.

### 3.7 Things we call something specific

- **`@manifest` block** — our self-describing-systems convention (BTS-239). Not a test term per se, but every primitive in §1 carries one; when reading the codebase, that's where each script's contract lives.
- **Caller graph** — derived from `caller:` lines in manifests + grep over the code. The reverse direction (every grep-able caller must be declared) is the BTS-495 gap.
- **Substrate** — internal term for the ccanvil layer beneath the skills/rules. The bats scripts are substrate.
- **Hub vs node** — hub = this repo, node = a downstream project (15 of them) that consumes hub-distributed config. The hub runs its own bats suite; each node may or may not have one (per its `test-provider`).

## 4. Two-paradigm framing — ccanvil-self first, then framework distillation

A constraint on every Stage-1 decision below. This research has to solve the test-velocity problem **twice**, in order:

1. **Stage 1 — ccanvil-self.** The hub's own bats suite. Concrete: 2,338 tests, parallel-12, ~400 s wall, one outlier test consuming 35% of serial CPU. The headline operator pain. Solve this first.
2. **Stage 2 — distillation into shareable test framework.** The substrate, methodology, and tools developed in Stage 1 get abstracted and broadcast to downstream nodes (15 today; 7 fully wired, 8 in various drift states). Each node selects `test-provider` (bats | pytest | vitest | …) and inherits the timing-capture + visualization + regression-detection contract — *without* inheriting the bats-specific implementation. The hub keeps the methodology; the nodes pick the runner.

Stage 2 isn't a future-only concern — it shapes every Stage 1 decision. Specifically:

- **Schema neutrality.** Any persisted file must carry runner-agnostic column names. `bats-runs.jsonl` should probably become `test-runs.jsonl` with a `provider` field. The column `ms` works for bats `-T` and pytest `--durations` and vitest `--reporter` alike; a column named `bats_in_ms` does not.
- **Capture-mechanism boundary.** The BTS-460 dispatcher (`cmd_test_suite_run`) is already the abstraction layer that swaps runners per-node. It is therefore the right place to enforce "always capture per-test timings" — independent of which runner is below. Each runner's wrapper translates the runner's native format into the neutral schema. For bats this means `bats-report.sh` translates TAP `-T` output + injected worker-IDs into a shared row format; a future pytest wrapper would translate pytest's per-test wall + xdist's worker IDs into the same row format.
- **Query-verb portability.** `bats-report.sh slow-history` is a tempting name; `docs-check.sh test-history` (or `test-suite-history`) is a better one. The "bats" string in operator-facing tool names is currently leaking provider into the contract.
- **Visualization-format portability.** Whatever serialization powers the swimlane / trace view (research question 14 below) must be runner-agnostic. Chrome Trace Event Format is provider-neutral by construction — perfetto.dev opens a Bazel trace, a Chrome dev-tools trace, and our trace identically.
- **What stays runner-specific.** The *extraction shim* — the per-runner code that reads the runner's native output and writes the neutral schema. That's deliberately small and per-provider. The downstream effort to add pytest support becomes: write the pytest shim + dispatcher branch, reuse the entire methodology + storage + query + viz layer.

The litmus test for Stage 1 decisions: *would this work, byte-identically, if the runner were pytest?* When the answer is no, the schema or naming choice is too bats-coupled and needs another pass.

## 5. Open research questions

The eight from BTS-497, expanded with what the inventory above surfaced.

1. **Storage shape.** Where do per-test rows live?
   - (a) Extend `bats-runs.jsonl` schema to include `timings: [{test_name, file, ms}]` inline.
   - (b) Separate file per run at `.ccanvil/state/bats-timings/<epoch>.jsonl`, keyed back to the run summary.
   - (c) A single ever-growing `bats-tests.jsonl` with rows `{run_epoch, test_name, file, ms}` — most "long format", most queryable but largest growth.
   - (d) Some combination — `bats-runs.jsonl` keeps aggregate, `bats-timings/<epoch>.jsonl` keeps per-test.
   The tradeoff axis is: query ergonomics (one file vs many) × storage growth × append-cost.

2. **Retention policy.** With 2,338 tests × ~5 runs/ship × ship cadence, what's the rolloff?
   - Last N runs? (e.g., 100 = ~3 MB on the (c) shape.)
   - Last N days? (e.g., 30 days × 5 runs/day = 150 runs.)
   - Tiered: keep all aggregate, age out per-test detail.
   - Append-only with manual archival.
   Related: gitignore vs commit. The `.ccanvil/state/` dir is gitignored today; the operator currently has no remote copy of `bats-runs.jsonl` other than via the local filesystem.

3. **Capture overhead.** Today `bats -T` is opt-in. To get "every time tests run" the dispatcher needs to flip it on by default.
   - Measured overhead of `-T` per test? (Sub-research: A/B 5 runs with vs without `-T`.)
   - Does it affect the BTS-263 parallel-flake rate?
   - Does it interact with `--progress` (BTS-383)? Both add per-test instrumentation.

4. **Retrospective tooling.** What verb shape mines the data?
   - `bats-report.sh slow-history --top 30 --since 7d` — sliding-window slowest tests.
   - `bats-report.sh regressed --since 14d --pct 25` — tests that gained >25% over the last 14d.
   - `bats-report.sh test-history <test-name>` — full timeline for one test.
   - Where does the output go? Stdout JSON for agent consumption? Rendered table for operator?

5. **Regression detection thresholds.** What counts as "this test slowed down"?
   - Absolute Δ ms (e.g., +200 ms is alert-worthy).
   - Relative Δ pct (e.g., +50%).
   - Variance-aware (z-score against historical mean).
   - p95 shift vs median shift.
   What triggers the alert: a single bad run, N consecutive runs, a moving-average crossing?

6. **Slow-test SLO.** Above what wall is a single test "too slow"?
   - >500 ms? >1 s? >5 s?
   - Per-test vs per-file (a fast file with one slow test vs a uniformly-slow file)?
   - SLO violations as advisory vs blocking?

7. **Root-cause classes — what kinds of slow are there?** The operator explicitly asked for "no bucketing" at the *initial* analysis stage, which means: don't pre-decide the categories before looking. Once data lands, candidate classes that will likely fall out include subprocess-fork cost (the BTS-282 axis), real-binary execution inside the test, sequential-by-design assertions, oversized fixtures, manifest-validate stragglers (BTS-281 mitigation already addresses this for most callers). The right move is: capture first, classify second. **This is a deliberate non-decision.**

8. **Cross-system scope.** Who else needs this data?
   - Operator (interactive `/radar`, `/stasis`).
   - Downstream agents (drift-watchdog, future soak agent BTS-283).
   - CI (does CI even run our tests? — BTS-483 territory).
   - Other hub-stack nodes (each runs its own suite via the dispatcher).
   Read access matters: the format should be jq-queryable; the path should be discoverable from the dispatcher.

Surfaced by this lap, in addition to BTS-497's eight:

9. **Provider neutrality.** The dispatcher (BTS-460) intentionally separates "test verb" from "test runner". If we extend `bats-runs.jsonl` schema with `timings`, do we make it `bats`-specific or `runner`-neutral? A future pytest/vitest provider would emit comparable data structures; getting the column names right today avoids a v2 migration.
10. **Setup vs test cost.** Bats `-T` doesn't separately time `setup`/`setup_file`/`teardown`/`teardown_file`. If 30% of a test's wall is fixture, our optimization target is fixture, not the `@test` body. Worth distinguishing — even if the answer is "not on the first lap".
11. **The 175 ms floor.** Median full-suite ms/test is ~175 ms. Even if every individual `@test` body executed in zero time, fork-pressure + bats startup would still apply. What is the minimum-achievable ms/test given the runner architecture? Knowing this bounds the optimization headroom.
12. **Failure-row cost.** Failed tests are over-represented in wall: a `setup_file failed` cascades the file's tests as failures that ran zero useful logic but consumed bats overhead. The current schema captures `failures[]` but not their wall contribution.
13. **The `bats-runs.jsonl` 583/1151 split.** Half our parallel runs are file-targeted (small `--jobs N` invocations). Per-test history would presumably only be useful for the full-suite slice. Filtering at write time? Tagging the row?

14. **Visualization — the swimlane / Gantt / trace view.** The natural deliverable of per-test timing data is a *visualization*: 12 lanes (one per parallel worker), tests stacked horizontally in time, the operator immediately sees which lane is the bottleneck. This is industry-standard and goes by several names:
    - **Swimlane diagram** (most common; process / org-chart heritage)
    - **Gantt chart** (project-management heritage; same shape)
    - **Execution trace** / **timeline view** (profiler heritage — Chrome DevTools, perfetto.dev, Tracy)
    - **Worker timeline** (pytest-xdist, Bazel build-event-protocol)
    - **Flame chart for parallel execution** (Brendan Gregg's "flame graph" extended to parallel scheduling)

    The de-facto interchange is **Chrome Trace Event Format** — a flat JSON list of events `{name, cat, ph, ts, dur, pid, tid}`. The viewer at **perfetto.dev** opens any such file in-browser. Bazel emits this format natively; many profilers consume it.

    Capturing this requires more than bats `-T`. The fields we need per test:

    | Field | Today | Needed | Capture mechanism |
    |---|---|---|---|
    | Test name | ✓ bats -T | ✓ | TAP parse |
    | Duration (ms) | ✓ bats -T | ✓ | TAP parse |
    | **Start timestamp** (epoch ms) | ✗ | NEW | Wrap `@test` in bats setup/teardown OR custom reporter |
    | **End timestamp** (epoch ms) | ✗ | NEW | Same — or derive from `start + dur` |
    | **Worker ID** (which of N lanes) | ✗ | NEW | Read from `BATS_PARALLEL_ID` if exposed; else inject via env at job dispatch |
    | File | parseable | ✓ | TAP `# (in test file …)` annotation |

    **Bats does not natively expose worker IDs.** When `bats --jobs N` runs, the TAP stream is interleaved without a worker tag. To capture worker_id we have to either (a) patch bats's internal `parallel` dispatcher to emit a tag, (b) inject the worker ID into the test's environment before invocation and have a setup hook echo it into a sidecar trace file, or (c) approximate worker_id from the start-timestamp ordering (which falls apart under any non-trivial scheduler). This is a real research question — not just a "persist what we have."

    A research-only deliverable from Stage 1 worth considering: a single hand-built swimlane (rendered from a one-time instrumented run) for the operator to *see* what the suite looks like before any code change. The visualization is its own deliverable — distinct from "persist timings."

## 6. Open-market research — vocabulary to take outside

When we go look at how other teams handle this, these are the search terms most likely to surface useful prior art. They're grouped by intent, not by tool.

**For "we don't have per-test history yet":**
- *test analytics* — broad category; covers Buildkite Test Analytics, Datadog CI Visibility, Launchable, CircleCI Insights.
- *test telemetry*
- *flaky test detection* — almost every CI vendor's pitch starts here.
- *test result database* — older term; surfaces stats-on-tests writeups from before the SaaS market crystallized.

**For "which tests slowed down":**
- *test performance regression*
- *test duration trend*
- *slowest tests report*

**For "running only the tests that matter":**
- *test impact analysis* (TIA) — Microsoft Research's canonical term.
- *predictive test selection* — Facebook's term for the same.
- *test prioritization* — academic literature uses this.

**For "fork overhead, profile a single test":**
- *bats profiling* — narrow but useful for our specific stack.
- *shell test performance*
- *make profile* / *bash profiler*

**Tooling names worth specifically looking up:**
- *Buildkite Test Analytics* — possibly the closest fit to our shape (CI-agnostic, per-test history, p95/regression detection).
- *Launchable* — TIA-focused.
- *Datadog CI Visibility* — broader test-results-as-traces.
- *Bazel test profiling* — Bazel emits per-test wall by default; their flag set is worth studying.
- *RSpec --profile* — RSpec's per-test slowest-N reporter; the simplest comparable to `bats-report.sh --slow-top`.
- *pytest-benchmark* / *pytest --durations=N* — pytest-side equivalents.
- *Mocha --reporter dot --slow N* — JS-side equivalent.
- *go test -bench / -benchtime / -count* — Go's first-class benchmarking discipline. Different shape (benchmarks vs unit tests) but worth understanding the framing.
- *JUnit XML* — the de-facto interchange format for test results; per-test duration is a standard field. Worth knowing as a fallback if we ever export.

**Academic-shape references:**
- Microsoft's "Mining Test Repositories" line of work.
- Google's continuous-test-selection papers (the "billions of tests" framing).
- ICSE / FSE test-performance papers from the last 5 years.

**Frameworks for the "every-run capture" decision:**
- Hyrum's law applied to test instrumentation (every observed property gets depended on; pick the columns carefully).
- Observability vs monitoring (Charity Majors / Honeycomb's framing) — the distinction matters when deciding whether `bats-runs.jsonl` is a metric log or a structured event store.

## 7. What this lap does NOT decide

- **Storage shape.** Listed; not selected.
- **Retention policy.** Listed; not selected.
- **Whether `--timings` becomes default.** A pre-decision A/B is cheap and should happen before the spec, not during it.
- **Slow-test SLO.** Premature without per-test history to calibrate against.
- **Whether to ship a query verb in the same PR as capture.** Could be one ship; could be two. Spec will decide.
- **Whether to retroactively run `bats-profile.sh` over the suite as part of this work.** Different concern; complementary; not blocking.

## 8. Next-step shape (informational, not a spec)

The successor session — after this research lap is operator-reviewed — will likely:

1. Pick the storage shape (question 1) and the retention policy (question 2). Apply the §4 schema-neutrality litmus test to whatever shape is picked.
2. Decide the visualization deliverable scope (question 14): one-shot manual trace, durable swimlane substrate, or both. Pick the capture mechanism for `start_ts` + `worker_id`.
3. Run a single in-session A/B on `-T` overhead (question 3).
4. Pick a query-verb shape and a regression-detection threshold (questions 4 + 5). Use provider-neutral naming.
5. Decide capture cadence: every run vs full-suite-only vs operator-flag.
6. Spec the implementation. Likely PR slices, mirroring BTS-497's "Companion follow-on" and the Stage 1 / Stage 2 framing:

   **Stage 1 — ccanvil-self:**
   - Capture: dispatcher + `bats-report.sh` always pass `--timings` (or whatever question 3 resolved); append per-test rows in the runner-neutral schema.
   - Worker-ID / start-timestamp instrumentation (question 14).
   - Query verb (`docs-check.sh test-history` or similar, provider-neutral).
   - One-shot swimlane export to Chrome Trace Event Format.
   - Drift-guard outlier addressed (its own lane — sharding, fixture caching, or accepted-and-documented as the irreducible structural-drift cost).
   - Consumer unblock: BTS-283 (soak-tracking remote agent) with the new shape.

   **Stage 2 — framework distillation:**
   - Document the methodology in a guide section (test-perf practices, slow-test triage runbook).
   - pytest / vitest dispatcher branches in `cmd_test_suite_run` for the first non-bats node that needs them.
   - Each new provider supplies its own extraction shim translating native output → neutral schema.
   - Broadcast via the normal hub-to-node ccanvil-sync flow.

This is sequencing, not commitment.

## 10. Open-market scan — what's out there (deep-research synthesis)

Four research streams (test-analytics platforms; Grafana-stack observability; execution-trace standards + parallel viz; test-framework-native primitives + fail-closed patterns) ran in parallel and **converged on the same answer**. That convergence is itself a finding worth noting: it means the operator's described end-state is well-served by an existing, mature, OSS-only architecture pattern. The pattern is a Frankenstein, but every component is standard.

### 10.1 The convergence — four streams, same conclusion

| Question | Independent answer all four streams reached |
|---|---|
| What's the canonical instrumentation layer? | **OpenTelemetry** — language- and runner-agnostic, free, mature. |
| What instruments bash specifically? | **`equinix-labs/otel-cli`** (~1.5 k stars, mature, CNCF-adjacent). Wraps any command, emits OTel spans. |
| What turns test results into traces post-hoc? | **`mdelapenya/junit2otlp`** — reads JUnit XML, emits OTLP. Bridge from any runner that emits JUnit XML (bats can via `--report-formatter junit`). |
| What stores traces locally, free? | **Grafana Tempo** — self-hosted, single binary, filesystem-backed (no S3 needed). Swimlane/Gantt view comes free as the trace-detail view. |
| What does the operator look at? | **Grafana OSS** with Tempo (traces) + Mimir/Prometheus (metrics) + optional Loki (logs). Free Grafana Cloud also viable up to limits. |
| Ad-hoc swimlane viewer for one-off deep dives? | **perfetto.dev** with **Chrome Trace Event Format** JSON. Drag-drop, browser-only, zero install. |
| How do downstream nodes inherit this? | Each runner has an OTel exporter that emits the same span schema: **`pytest-opentelemetry`** (pytest), **`vitest` built-in OTel reporter** (vitest), **`traceloop/jest-opentelemetry`** (Jest), **`go test -json` → junit2otlp** (Go). |
| How do we enforce non-optional observability? | OTel Collector **`healthcheckv2extension`** + a `setup_file`-style precondition probe that fails the suite if the sink is down. Standard pattern across pytest, Jest, Vitest, RSpec, minitest. |

This isn't a coincidence — the OTel project's stated goal is exactly this kind of cross-runtime, cross-framework observability layer, and the test-runner ecosystem has converged on it over the last 2–3 years.

### 10.2 Reference architecture (the Frankenstein, drawn)

```
                          (per-runner OTel exporter — provider-neutral schema)
                                              │
   ┌──────────────┐    ┌───────────────┐     │     ┌────────────────────────┐
   │ bats (today) │───>│  otel-cli +   │     │     │  pytest-opentelemetry  │ (downstream)
   │ + tap/junit  │    │  setup_file   │     │     │  vitest --reporter otel│
   └──────────────┘    │  hooks        │     │     │  jest-opentelemetry    │
                       └───────────────┘     │     │  junit2otlp (any XML)  │
                                │            │     └────────────────────────┘
                                ▼            ▼            ▼
                       ┌─────────────────────────────────────┐
                       │   OTel Collector (local, OSS)       │
                       │   - OTLP gRPC receiver :4317        │
                       │   - healthcheckv2 extension         │
                       │   - fan-out exporters:              │
                       │     ├── otlp → Tempo                │
                       │     ├── prometheus → Mimir          │
                       │     ├── loki → Loki                 │
                       │     └── file → traces.jsonl backup  │
                       └─────────────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        ┌──────────┐      ┌──────────┐      ┌──────────┐
        │  Tempo   │      │  Mimir   │      │   Loki   │
        │ (traces) │      │ (metrics)│      │  (logs)  │
        └──────────┘      └──────────┘      └──────────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                ▼
                         ┌─────────────┐
                         │ Grafana OSS │   ── operator dashboards
                         │             │   ── alert rules (regression detection)
                         └─────────────┘

           Side-channel ad-hoc viewing:
           traces.jsonl + jq → Chrome Trace Event Format → perfetto.dev (browser)

           Agent read path:
           sqlite3 -json (option B) OR TraceQL / PromQL → Grafana HTTP API
```

The whole thing runs on one machine in `docker-compose`, ~5 services, ~2 days of wiring. The operator's machine is enough; nothing leaves the laptop unless they choose to ship it to Grafana Cloud's free tier.

### 10.3 Two concrete option shapes (operator picks one)

**Option A — Full LGTM (Loki + Grafana + Tempo + Mimir) via OpenTelemetry.** What §10.2 describes verbatim. Best fit for *exactly* the operator's described end-state, including the "side-by-side parallelism visualization" (which is the native trace-detail view in Tempo/Grafana — 12 lanes appear automatically when 12 workers emit spans with distinct `tid`/`worker.id` attributes). Setup cost ~2 days; ongoing operational cost low (LGTM stack runs unattended). Mandatory-observability gate is a 5-line `setup_file` curl probe against the Collector's healthcheck endpoint.

**Option B — Boring SQLite + Grafana SQLite plugin.** bats → TAP → `tap-parser --json` → `sqlite3 INSERT` → Grafana with `frser-sqlite-datasource` plugin (v4.0.6, May 2026, stable). Schema is two tables (`runs`, `tests`). Agent read path is literal `sqlite3 -json` — no API tokens, no query language. Setup cost ~1 day. Loses: real-time swimlane viz, cross-trace correlation, OTel's runner-neutral protocol (you have to convert pytest/vitest data into the same SQLite schema yourself with per-runner shims). Gains: extreme simplicity, single file, zero infra, agent-readable without any tooling.

**The honest tradeoff:** Option A is the right answer for the operator's stated end-state ("funnel data into Grafana, visualize, regression patterns, agent-readable on schedule"). Option B is the right answer for "ship something this week, see if I actually use the dashboards before paying the LGTM operational tax." Both keep the runner-neutral schema discipline from §4. Both can be migrated to each other — the schema is the durable artifact.

A third variant worth naming: **Option B + Metabase** instead of Grafana SQLite plugin. Metabase is `docker run` to dashboard in 10 minutes, more polished UI than Grafana SQLite, no real-time-streaming features but they're not load-bearing for this use case.

### 10.4 The bats-specific instrumentation recipe (concrete, drop-in)

A real recipe surfaced from the research — not theoretical, paste-and-go:

```bash
# hub/tests/_helpers/telemetry.bash — sourced by every .bats file via setup_file

telemetry_setup_file() {
  : "${CCANVIL_TELEMETRY_URL:?telemetry endpoint not configured — set to OTel Collector OTLP endpoint}"
  curl -fsS --max-time 2 "${CCANVIL_TELEMETRY_URL}/health" >/dev/null \
    || { echo "TELEMETRY DOWN — refusing to run tests" >&2; return 1; }
  export CCANVIL_RUN_ID="$(date +%s)-$$"
  export TID="${PARALLEL_JOBSLOT:-0}"   # GNU parallel sets this; bats inherits it under --jobs N

  # Start a background span server (otel-cli) — child spans connect via unix socket, microsecond overhead
  otel-cli span background \
    --service bats \
    --name "ccanvil-suite" \
    --attrs "git.sha=$(git rev-parse HEAD),runner.kind=bats,worker.id=$TID" \
    --sockdir "$BATS_FILE_TMPDIR" &
  export TRACEPARENT=$(otel-cli span traceparent --sockdir "$BATS_FILE_TMPDIR")
}

telemetry_teardown() {
  otel-cli exec --service bats --name "$BATS_TEST_NAME" \
    --attrs "test.file=$BATS_TEST_FILENAME,test.outcome=${BATS_TEST_COMPLETED:-fail},worker.id=$TID" \
    -- true   # ":" trick — otel-cli emits the span with the captured timing context
}
```

**Two non-obvious load-bearing details:**

1. **`PARALLEL_JOBSLOT`** is set by GNU parallel when bats shells out to it (which is what `--jobs N` does for multi-file runs). This is the bats worker-ID mechanism — surfaced in bats-core issue #998. It's the closest thing bats has to pytest-xdist's `PYTEST_XDIST_WORKER`, and it's enough for the swimlane viz. Caveat: single-file `--jobs N` may not set it; needs verification before committing.
2. **`otel-cli span background`** starts a unix-socket span server so each per-test `otel-cli exec` call is microseconds rather than a fresh OTLP connect. Without this, per-test instrumentation overhead would dominate test wall time. This is the canonical bash-OTel pattern documented in Howard John's blog (see reading list).

### 10.5 Fail-closed observability — the canonical pattern across runners

The four research streams converged on a single recipe:

| Runner | The "telemetry-or-fail" hook |
|---|---|
| bats | `setup_file` curl probe → exit 1 on failure |
| pytest | `@pytest.fixture(scope="session", autouse=True)` calling `pytest.fail(pytrace=False)` |
| Jest | `globalSetup` script that throws on telemetry probe failure |
| Vitest | `globalSetup` returning rejected Promise |
| Mocha | root `before()` hook that throws |
| RSpec | `RSpec.configure { |c| c.before(:suite) { raise unless ... } }` |
| Go | `TestMain` precondition check, `os.Exit(1)` |
| Cargo nextest | setup-script that exits non-zero + `fail-fast = true` |

This is one of those rare cases where the **same conceptual hook exists in every test runner** — "before any test body runs, probe the world, abort the run if the probe fails." That's the surface ccanvil substrate hooks into for cross-runner mandatory observability. The fail-closed contract is portable.

At the collector layer: OTel Collector ships **`healthcheckv2extension`** which exposes a `/status` endpoint returning HTTP 200 only when every pipeline (receiver → processor → exporter chain) is healthy. The bats `setup_file` probe targets this endpoint. Simple, deterministic, no new substrate required.

A second layer worth noting: **Prometheus Dead Man's Switch** — the pattern where the test suite emits a `test_suite_heartbeat{run_id="..."}` metric every N tests, and a `vector(1)` always-firing alert combined with `absent_over_time(test_suite_heartbeat[10m])` catches silent telemetry failure. This is the right pattern for catching "the probe lied" — telemetry says OK but actually nothing is landing in storage. Belt + suspenders.

### 10.6 Stage-2 distillation map — what each downstream-node runner needs

When the substrate broadcasts down to downstream nodes, each node's test-provider gets a dedicated OTel exporter. The list is mature:

| Provider | OTel-ready instrumentation | Stars / maturity | Notes |
|---|---|---|---|
| **pytest** | `chrisguidry/pytest-opentelemetry` (MIT) | Active, xdist-aware (unifies parallel workers into one trace) | The cleanest provider-side story across all runners. |
| **Vitest** | Built-in `experimental.openTelemetry` (since 2025) | First-party, marked experimental | Vitest team is investing here. |
| **Jest** | `traceloop/jest-opentelemetry` | Active | Less polished than pytest's; usable. |
| **RSpec / minitest** | `appsignal/opentelemetry-ruby-rspec`, manual via formatters | Plugins exist; not universal | Slight DIY tax. |
| **Go test** | `go test -json` → `junit2otlp` OR direct OTel SDK in `TestMain` | First-class JSON output makes the bridge trivial | go's machine-readable output is the gold standard. |
| **Cargo / nextest** | `nextest run --message-format libtest-json` → custom bridge | Manual bridge today | nextest has machine-readable output; ad-hoc OTel emission. |
| **JUnit-family (Java/Kotlin)** | `junit2otlp` from JUnit XML | Direct | Same bridge as bats. |
| **bash / other** | `otel-cli` + `junit2otlp` | Direct | Universal fallback. |

The substrate's job per provider is small: a shim that resolves "where does this runner's output land" + "how does it tag its workers" into the standard OTel attribute set (`test.name`, `test.file`, `test.outcome`, `worker.id`, `git.sha`, `runner.kind`). Each shim is ~50–100 lines. The 90% of the substrate is the cross-runner schema + the OTel pipeline, and that lives in the hub.

### 10.7 TIA, regression detection, flake handling — honest assessment

The research surfaced an inconvenient truth: **there is no production-grade OSS test-impact-analysis tool you can drop in today.** What does exist:

- **`pytest-flakefinder` (Dropbox, MIT)** — re-runs each test N times to expose flakiness. Real, usable.
- **`flaky`, `pytest-rerunfailures`** — mark-based retry with hook visibility into rerun protocol.
- **`gotestsum --rerun-fails`** — built-in retry with flake vs real-fail distinction.
- **`cargo nextest run --retries N`** — first-class retry config.
- **Launchable's "Predictive Test Selection"** — SDK is open, the ML brain is proprietary SaaS. Treat as vendor lock.
- **Microsoft TIA** — research paper (CRANE, 2011); zero OSS implementation.
- **Closest OSS alternative for changeset-driven test selection:** `coverage.py --contexts` + diff-driven test selection scripts (~200 LOC, DIY).

Implication for ccanvil: **regression detection is a question for the Grafana alert rules layer**, not a separate OSS tool to adopt. Grafana alerts can fire on PromQL/TraceQL queries like "p95 of test.duration_ms for test.name='X' over last 7d > 1.5× of same metric over last 30d" — that IS regression detection, expressed in metrics rather than as a dedicated TIA system. The operator builds the alert rule once; new tests inherit it by being recorded.

### 10.8 Top-10 reading-list links (concrete, follow-tomorrow)

Ranked by load-bearing-ness for the next phase:

1. **[`equinix-labs/otel-cli`](https://github.com/equinix-labs/otel-cli)** — the bash-side primitive. README + `examples/` are the canonical recipe.
2. **[Howard John, "Tracing shell scripts with OpenTelemetry"](https://blog.howardjohn.info/posts/shell-tracing/)** — the most concrete bash-OTel writeup. `trap DEBUG`/`functrace` autoinstrumentation patterns.
3. **[`mdelapenya/junit2otlp`](https://github.com/mdelapenya/junit2otlp)** — the "I have JUnit XML, I want OTel traces in Grafana" bridge.
4. **[`chrisguidry/pytest-opentelemetry`](https://github.com/chrisguidry/pytest-opentelemetry)** — exemplar OTel-native test reporter. Pattern other runners follow.
5. **[Sam Zhu, "Building a Complete Grafana LGTM Observability Platform with Docker Compose" (Mar 2025)](https://blog.samzhu.dev/2025/03/25/Building-a-Complete-Grafana-LGTM-Observability-Platform-with-Docker-Compose/)** — full single-node LGTM compose file.
6. **[Bazel JSON Trace Profile docs](https://bazel.build/advanced/performance/json-trace-profile)** — production-grade reference for "build/test actions as Chrome Trace Event `ph:X` events with `tid` per worker." Steal their schema.
7. **[`nico/ninjatracing`](https://github.com/nico/ninjatracing)** — smallest "log lines → Chrome Trace Event Format JSON" Python implementation. Copy-paste target for the bats variant.
8. **[Perfetto UI](https://ui.perfetto.dev)** + **[other-formats docs](https://perfetto.dev/docs/getting-started/other-formats)** — drag-drop swimlane viewer.
9. **[bats-core issue #998 — PARALLEL_JOBSLOT](https://github.com/bats-core/bats-core/issues/998)** — the bats worker-ID mechanism, with caveats.
10. **[OTel Collector `healthcheckv2extension`](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/extension/healthcheckv2extension/README.md)** — the fail-closed gate. Current canonical (V1 is deprecated).

Honorable mentions: Martin Fowler's [Rise of TIA](https://martinfowler.com/articles/rise-test-impact-analysis.html) (evidence-driven, not vendor pitch); [Aiman Ismail's otel-cli CI instrumentation writeup](https://pokgak.xyz/articles/instrument-your-ci/); [Grafana's own flaky-test reduction blog](https://grafana.com/blog/how-we-reduced-flaky-tests-using-grafana-prometheus-grafana-loki-and-drone-ci/) (self-referential but useful).

### 10.9 Honest gaps + risks

- **`junit2otlp` is ~70 stars, single-maintainer.** Mature in capability but light on community. Vendor the binary at a pinned tag; verify build reproducibility.
- **`PARALLEL_JOBSLOT` reliability under bats `--jobs N` varies.** Single-file parallel may not set it. Needs an in-session verification probe before committing to it as the worker-ID source.
- **OTel-for-bash is mature but small.** `otel-cli` is solid, but Python/JS/Java OTel SDKs have orders of magnitude more usage. Operationally fine; ecosystem-risk to know.
- **"Fail if observability is offline" requires the operator's harness.** No turnkey tool ships this contract — it's a 5-line `setup_file` hook + Collector health probe. Easy, but the operator owns enforcement.
- **No OSS TIA.** Regression detection has to be built on Grafana alert rules; there is no drop-in test-impact tool to adopt.
- **Storage growth at our cadence.** ~2,338 tests × ~10 runs/day × 365 days = ~8.5M test-events/year. Tempo handles this trivially (designed for orders of magnitude more); SQLite handles this trivially (~600 MB at one row per test event); but worth knowing the magnitude.
- **The Frankenstein has 5 moving pieces.** Bats hook + otel-cli + OTel Collector + Tempo + Grafana. Each is mature; the integration surface is the operator's responsibility. Day-1 docker-compose covers it but ongoing maintenance is real.

### 10.10 What I'd build if I were the operator (synthesis of all four streams)

**Ship Option B-with-Metabase first; ramp to Option A when the swimlane question becomes load-bearing.**

Honest read: the operator's stated need decomposes into two distinct lanes — (1) *"per-test perf history, queryable, agent-readable"* and (2) *"swimlane visualization of parallel scheduling"*. Lane 1 is 90% of the value; lane 2 is the dopamine hit. SQLite + Metabase delivers lane 1 in a day with zero ongoing operational tax, runs anywhere, the agent-read path is literal `sqlite3 -json`. Lane 2 is delivered for one-off use today by dumping Chrome Trace Event Format and dragging into perfetto.dev — no infra needed. The full LGTM stack solves both lanes simultaneously and elegantly, but costs ~2 days to wire and ongoing operational attention.

**Concrete suggested first ship (Stage 1, ccanvil-self):**

1. Schema: `.ccanvil/state/test-runs.jsonl` (runner-neutral; rows `{run_id, started_at_us, ended_at_us, test_name, file, worker_id, status, ms, runner}`).
2. bats hooks: `setup_file` probe (curl localhost otel-collector or just a sentinel file), `teardown` appends JSON row, `teardown_file` flushes.
3. Worker-ID source: `${PARALLEL_JOBSLOT:-0}` with documented caveat.
4. Fail-closed: `setup_file` exits 1 if sink unreachable.
5. Swimlane export verb: `docs-check.sh test-suite-trace --run <run_id>` → emits Chrome Trace Event Format JSON for drag-drop into perfetto.dev. One-off, not always-on.
6. Query verb: `docs-check.sh test-suite-history --top 30 --since 7d` → reads the JSONL, jq-aggregates, emits markdown table.
7. Address the drift-guard 5.5-min outlier in its own follow-on ticket.

**Stage 2 (broadcast):** the JSONL schema and the dispatcher's exporter contract are the durable artifacts. Each future test-provider supplies its own JSONL-emitting shim. The Grafana stack becomes optional — nodes that want it stand up their own; nodes that don't, just have the JSONL.

This ramps incrementally. Skip the OTel Collector + Tempo + Mimir + Loki tax until the dashboards justify it. The OTel-stack option remains the migration target — its schema is upward-compatible from JSONL (`run_id`, `test_name`, `worker_id`, `ms` map cleanly to OTel attributes).

## 11. Live snapshot — 2026-05-15

A single full-suite `--timings --json` capture, taken in this session, preserved at `.ccanvil/state/bts-497-timings-snapshot-1778897.json`. This is the *only* per-test history that exists for this codebase today. Without this lap there would still be none.

### 11.1 Run summary

| Metric | Value |
|---|---|
| Tests | 2,338 |
| Passes | 2,338 (100%) |
| Wall time | 402,007 ms (6 min 42 s) |
| Jobs (parallel) | 12 |
| CPUs reported | 16 |
| Timed tests captured | 2,335 / 2,338 |
| Sum of per-test ms (serial-equivalent) | 945,835 ms (15 min 46 s) |
| Effective parallelism (serial-sum ÷ wall) | 2.35× |

The effective parallelism number is much lower than the 12 jobs would predict — the immediate explanation is in §11.2.

### 11.2 The single-test cliff

| Rank | ms | Cumulative share of serial-sum | Test name | File |
|---|---|---|---|---|
| 1 | **329,649 ms (5 min 29 s)** | **34.9%** | `drift-guard production allowlist clean (regression guard against this branch)` | `hub/tests/module-manifest-drift-guard.bats` |
| 2 | 30,044 ms (30.0 s) | 38.0% | `AC-1: --progress emits [N/M] markers per file` | `hub/tests/bats-report-progress.bats` |
| 3 | 8,776 ms (8.8 s) | 39.0% | `AC-8: already-initialized re-run produces no fresh-template plan entry` | `hub/tests/init-fresh-claudemd.bats` |
| 4 | 4,061 ms | 39.4% | `BTS-212 reverse: every cmd parsing --project-dir is registered in PROJECT_TREE_SUBCOMMANDS` | `hub/tests/docs-check-flags.bats` |
| 5 | 4,047 ms | 39.8% | `AC-1: --progress emits [heartbeat] during long-running file` | `hub/tests/bats-report-progress.bats` |
| … | (top 30 below) | reach 46.4% | | |

**One test consumes 5 minutes 29 seconds.** It is `module-manifest.sh validate` run against the full production allowlist — the BTS-268 regression guard. In a parallel-12 schedule, that single test sets the wall-time floor: nothing can finish before it does. If this one test moved to a sharded/standalone runner (or was deleted), the next-largest single-test ceiling is 30 s, and the theoretical floor from sum/jobs drops to ~80 s.

The 12-job parallelism is doing real work — the 2,334 other tests average 2.6 s of wall per worker (264 s of work distributed across 11 workers). But Amdahl's law applies brutally here: the single longest serial dependency dominates.

**Conceptual swimlane** (text mock-up of the actual schedule, not from instrumentation):

```
       0s        60s       120s      180s      240s      300s   330s   402s
Lane  1  ──[drift-guard test, runs continuously..........................]────
Lane  2  ──[ts][ts][30s test][ts][ts]──[idle.................................]
Lane  3  ──[ts......]──[idle................................................]
Lane  4  ──[ts......]──[idle................................................]
Lane  5  ──[ts......]──[idle................................................]
...
Lane 12  ──[ts......]──[idle................................................]
```

Read this row by row: lane 1 is captured by drift-guard for 5 min 29 s. The other 11 lanes finish their share of the 577 s of remaining work in ~60–80 s of wall (well-parallelized), then sit idle for ~250 s waiting for lane 1. The total wall (402 s) is just lane 1's duration (330 s) plus the ~70 s of pre-lane-1-completion parallel work plus scheduler overhead.

**Caveat: this is a conceptual diagram, not measured.** Per-lane assignment is not currently captured (see research question 14 in §5). To produce the real diagram we would need `worker_id` per test, which bats does not natively emit.

### 11.3 Top-30 with cumulative share

```
   ms     cum (% of 946 s)   test
329649      329649 (34.9%)   drift-guard production allowlist clean (regression guard against this branch)
 30044      359693 (38.0%)   AC-1: --progress emits [N/M] markers per file
  8776      368469 (39.0%)   AC-8: already-initialized re-run produces no fresh-template plan entry
  4061      372530 (39.4%)   BTS-212 reverse: every cmd parsing --project-dir is registered in PROJECT_TREE_SUBCOMMANDS
  4047      376577 (39.8%)   AC-1: --progress emits [heartbeat] during long-running file
  3168      379745 (40.1%)   AC-25: prose mention of HUB-MANAGED-START is not treated as delimiter
  3083      382828 (40.5%)   graph: --format dot emits digraph G with subgraph clusters
  3064      385892 (40.8%)   pr-cleanup: flips archive to Complete when docs/spec.md exists (AC-1)
  3052      388944 (41.1%)   graph: empty allowlist emits empty envelope (exit 0)
  3015      391959 (41.4%)   graph: nodes assigned to correct clusters
  2991      394950 (41.8%)   graph: tiny allowlist with command→agent edge → 1 cross_cluster_edge
  2854      397804 (42.1%)   AC-7: section-merge-create-delimiters is idempotent on already-wrapped files
  2766      400570 (42.4%)   AC-6: section-merge-create-delimiters wraps local content + appends hub section
  2592      403162 (42.6%)   self-app: index includes self-described verbs
  2553      405715 (42.9%)   complete: works on spec with YAML frontmatter
  2543      408258 (43.2%)   AC-4: post-apply CLAUDE.md accepts the canonical Step 8 sed substitution
  2536      410794 (43.4%)   AC-6: fresh-mode init-apply preserves hub-managed section byte-for-byte
  2498      413292 (43.7%)   AC-3: fresh-mode init-apply writes placeholder CLAUDE.md
  2371      415663 (43.9%)   broadcast: skips node with dirty working tree
  2304      417967 (44.2%)   register: updates timestamp on repeated registration
  2223      420190 (44.4%)   activate: succeeds with uncommitted docs/roadmap.md
  2212      422402 (44.7%)   BTS-212 shape A: every PROJECT_TREE_SUBCOMMAND accepts --project-dir without downstream-tool error
  2190      424592 (44.9%)   activate: succeeds with uncommitted spec file (AC-1)
  2150      426742 (45.1%)   activate: copies spec to docs/spec.md
  2095      428837 (45.3%)   activate: creates branch with correct naming convention
  2064      430901 (45.6%)   activate: works on spec with YAML frontmatter
  2058      432959 (45.8%)   broadcast: syncs auto-updates to node
  2035      434994 (46.0%)   complete: commits the cleanup
  2022      437016 (46.2%)   complete: removes lifecycle docs
  1996      439012 (46.4%)   broadcast: updates registry with last_synced fields
```

### 11.4 Distribution by ms band

Descriptive bands only — these are NOT root-cause categories.

| Band | Test count | Share of count | Sum ms | Share of serial-sum |
|---|---|---|---|---|
| > 5,000 ms | 3 | 0.1% | 368,469 | **39.0%** |
| 1,001–5,000 ms | 132 | 5.6% | 205,799 | 21.8% |
| 501–1,000 ms | 228 | 9.8% | 171,307 | 18.1% |
| 101–500 ms | 678 | 29.0% | 148,073 | 15.7% |
| ≤ 100 ms | 1,294 | 55.4% | 52,187 | 5.5% |

Read this row by row: 55% of tests cost almost nothing (5.5% of serial). 3 tests cost 39%. The middle bands (101–5,000 ms, ~45% of tests) account for ~55% of serial time. This is a Pareto-shaped distribution with an extreme outlier.

### 11.5 Per-test statistics

| Metric | Value |
|---|---|
| n | 2,335 |
| min | 5 ms |
| p10 | 17 ms |
| p50 (median) | 83 ms |
| p90 | 785 ms |
| p95 | 1,075 ms |
| p99 | 2,150 ms |
| max | 329,649 ms |
| mean | 405 ms |

The mean (405 ms) is ~5× the median (83 ms) — the slow tail is pulling the mean hard. This is the classic shape that makes "average test time" misleading and "p95/p99" load-bearing.

### 11.6 What this snapshot reveals that the inventory could not

- **A single test dominates wall time.** The drift-guard regression-guard test alone consumes 35% of serial-equivalent CPU. It is the canonical reason `/pr` takes 6+ minutes today. No optimization elsewhere matters more than addressing this one test (whether by sharding it, fixture-caching it further, or accepting it as the irreducible cost of structural drift detection).
- **The `--progress` self-tests are 30 s + 4 s.** Tests that verify "the progress emitter emits progress over a long-running file" *must* take a long time by construction. These belong in a separate slow-test track, possibly run only at /pr time rather than every iteration.
- **The "graph" tests cluster at 3 s.** Four tests in `module-manifest-self-application` (`graph: --format dot`, `graph: empty allowlist`, `graph: nodes assigned to correct clusters`, `graph: tiny allowlist with command→agent edge`) each run ~3 s — likely a shared fixture cost worth examining.
- **The activate/complete/broadcast cluster.** Seven tests in the 2-2.4 s range exercise `activate`, `complete`, and `broadcast` — these spin up real git repos in tmpdirs and exercise full lifecycle flows. Fixture-heavy; expected.
- **The 55% sub-100ms cohort exists.** Half the suite genuinely tests pure functions, parsers, or string transformations with minimal fork pressure. This is the population that benefits from BTS-281 fixture caching working as designed.

### 11.7 Snapshot artifact

The full `--timings --json` envelope is preserved at:

```
.ccanvil/state/bts-497-timings-snapshot-1778897.json
```

251 KB. Schema: `{ok, not_ok, total, tail, raw_exit, timings:[{test, ms}], failures, wall_ms, jobs, cpus}` — the standard `bats-report.sh --json --timings` shape. The next phase can re-run the same capture for delta comparison without re-deriving the inventory.

