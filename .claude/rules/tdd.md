# Test-Driven Development Rules

## The Red-Green-Refactor Cycle

When implementing any feature or fix:

1. **RED:** Write exactly ONE failing test. Run it. Paste the failure output to confirm it fails for the right reason.
2. **GREEN:** Write the minimum code to make that test pass. No more.
3. **REFACTOR:** With all tests green, improve code quality. Do not add behavior.
4. **REPEAT:** Move to the next acceptance criterion.

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

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
