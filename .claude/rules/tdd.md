---
manifest:
  id: tdd
  purpose: Codify red-green-refactor TDD discipline, live-API contract gate, strict-mode bats, and run-the-suite tooling expectations for ccanvil
  input:
    - "read-only: rule consumed by Claude during /plan + implementation"
  output:
    - "behavior-shape: forces test-first cycle, halts implementation drift"
  caller:
    - .claude/commands/plan.md
    - .claude/skills/tdd/SKILL.md
  depends-on:
    - bats-report.sh
    - bats-lint.sh
  side-effect:
    - "shapes-implementation-flow (no file mutation; behavioral influence on Claude)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=test-debt-accumulates | mitigation=stasis-evidence-gap-section"
    - "live-api-gate-skipped | exit=n/a | visible=stub-passes-then-prod-fails | mitigation=BTS-171-explicit-gate"
  contract:
    - one-failing-test-at-a-time
    - never-refactor-and-add-features-simultaneously
    - live-api-validation-before-commit-when-flagged
  anchor:
    - BTS-127 (strict-mode bats)
    - BTS-118 (bats-report.sh)
    - BTS-171 (live-API validation gate)
    - BTS-240 (reference manifest seed)
---

# Test-Driven Development Rules

## The Red-Green-Refactor Cycle

When implementing any feature or fix:

1. **RED:** Write exactly ONE failing test. Run it. Paste the failure output to confirm it fails for the right reason.
2. **GREEN:** Write the minimum code to make that test pass. No more.
3. **REFACTOR:** With all tests green, improve code quality. Do not add behavior.
4. **REPEAT:** Move to the next acceptance criterion.

## Live-API validation gate

When a plan step flags a live-API contract risk — phrasings like *"if the live API rejects, adjust"*, *"the exact filter shape may not work"*, *"verify against live"*, or any equivalent admission of contract uncertainty — the implementation MUST run one live call against the risky endpoint and confirm success BEFORE committing AND BEFORE running `/review`. Stubs accept any shape; only the live API verifies the contract.

**Why:** stub-only tests have shipped contract bugs into commits twice in the recent backlog (BTS-115 dual-capture missed a workspace-scoped label; BTS-170 used `{team:{null:{eq:true}}}` where the live API required `{team:{null:true}}`). Each incident burned an extra `/review`-cycle to surface what one live call would have caught. The cycle "stub-pass → commit → /review-flags → live-test-fails → fix → recommit" is 2× the cost of "live-test-first → commit-once."

**How to apply:** when reading a plan, scan for the risk-language phrasings above. Treat any match as a BLOCKING gate at the implementation step — run the live command, capture its output, only then commit. The check is one command, takes <5 seconds, and prevents a known-class of bug. Doesn't apply to pure-prose, gitignore, or doc-only diffs.

## Test Structure

- Name test files to mirror source: `src/services/auth.ts` → `src/__tests__/services/auth.test.ts`
- Use descriptive test names: `it("returns 401 when token is expired")` not `it("works")`
- Each test covers ONE behavior. If you need "and" in the name, split it.
- Arrange-Act-Assert pattern. One assertion per test when possible.

## What to Test

- **Always test:** Public API contracts, error paths, edge cases, state transitions.
- **Skip testing:** Private internals, framework boilerplate, third-party library behavior.
- **Integration tests** for: database queries, API endpoints, multi-service workflows.
- **Unit tests** for: pure functions, business logic, data transformations.

## When Tests Break

- If a new change breaks existing tests, the change is wrong — not the tests.
- Fix the implementation, not the test, unless the test's specification changed.
- If the spec changed, update the test FIRST, confirm it fails, then update implementation.

## Hooks Integration

After every file edit, the test suite runs automatically via hooks.
If tests fail after your change, fix immediately before proceeding.

## Strict-mode bats tests (BTS-127)

In bats, a test passes iff the *last* statement's exit code is 0. Sequential `jq -e` assertions leak silently — only the final one governs:

```bash
@test "leaky" {
  echo "$output" | jq -e '.a == "x"'   # fails silently if false
  echo "$output" | jq -e '.b == "y"'   # fails silently if false
  echo "$output" | jq -e '.c == "z"'   # ONLY this one decides the test's status
}
```

**Rule:** any `@test` block with ≥2 `jq -e` assertions MUST either:

- **(a)** start with `set -e` so every failing assertion halts the test, OR
- **(b)** combine assertions into a single compound `jq -e '.a == "x" and .b == "y"'`.

**Prefer (a)** — preserves readable per-line assertions and bats reports the exact failing line. Use (b) only when the tight form is genuinely clearer.

```bash
@test "strict (a)" {
  set -e   # BTS-127: halt on any assertion failure
  run bash "$SCRIPT" some-cmd
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.a == "x"'
  echo "$output" | jq -e '.b == "y"'
  echo "$output" | jq -e '.c == "z"'
}
```

`set -e` does NOT affect bats's `run` — `run` captures the inner exit code into `$status` and itself returns 0. So `set -e` only halts on direct assertions after `run`, which is what you want.

Enforced by `.ccanvil/scripts/bats-lint.sh` (runs in CI and locally).

## Running the suite (BTS-118)

Use `.ccanvil/scripts/bats-report.sh` when you need tail + pass/fail counts. It runs bats **once** and derives all metrics from a single capture — never chain `bats | tail`, `bats | grep ok`, `bats | grep not ok` (that's 3× the runtime):

```bash
bash .ccanvil/scripts/bats-report.sh --parallel           # fastest (GNU parallel required)
bash .ccanvil/scripts/bats-report.sh --json <path>        # structured output for skills
bash .ccanvil/scripts/bats-report.sh -f 'some filter'     # bats args pass through
bash .ccanvil/scripts/bats-report.sh --timings            # BTS-137: per-test timing table (slowest first)
bash .ccanvil/scripts/bats-report.sh --slow-top 10        # BTS-137: top 10 slowest tests only
bash .ccanvil/scripts/bats-report.sh --json --timings     # BTS-137: timings[] array in JSON output
```

Parallelism (`--parallel`) uses `bats --jobs N` where N = max(2, cpu/2). Requires GNU parallel: `brew install parallel` on macOS, `apt install parallel` on Debian/Ubuntu, `dnf install parallel` on Fedora. Falls back to serial with a WARN: if missing — CI runners without parallel installed silently run serially, so check CI logs if runs feel slow. See `.ccanvil/guide/command-reference.md` for full flag list.

Per-test timings (`--timings`, BTS-137) add `bats -T` to the invocation and parse the `in Nms` suffix. Use `--slow-top N` when you want only the worst offenders — helpful for prioritizing fixture consolidation. `--json --timings` emits `{timings: [{test, ms}]}` sorted slowest-first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
