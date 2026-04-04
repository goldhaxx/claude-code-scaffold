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

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
