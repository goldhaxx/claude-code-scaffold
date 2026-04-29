---
name: tdd-workflow
description: "Enforces test-driven development workflow. Use when implementing new features, fixing bugs, or when the user says 'tdd', 'test first', or 'red green refactor'. Guides through the full red-green-refactor cycle with verification at each step."
manifest:
  id: tdd-workflow
  purpose: Enforce strict TDD discipline (specification → red → green → refactor → verify) when implementing features, fixing bugs, or any change with logic. Each acceptance criterion becomes exactly one test; tests are written and confirmed-failing before implementation; refactor only happens with all tests green.
  routes-by: /tdd
  input:
    - "context: feature spec or bug repro from current conversation"
    - "no positional args"
  output:
    - "behavior-shape: forces operator/agent through Specification → Red → Green → Refactor → Verify phases"
    - "side-effect: shapes the implementation flow during the session — no file mutations"
  side-effect:
    - "shapes-implementation-flow (no file mutation; behavioral influence on the agent)"
  failure-mode:
    - "phase-skipped | exit=n/a | visible=test-debt-or-broken-build | mitigation=halt-and-restart-from-Specification-phase"
  contract:
    - one-test-per-acceptance-criterion
    - red-before-green
    - never-refactor-and-add-features-simultaneously
    - all-tests-green-before-refactor
  anchor:
    - BTS-127 (strict-mode bats)
    - BTS-252 (manifest seed)
---

# TDD Workflow Skill

You are operating in strict TDD mode. Every implementation follows this exact sequence.

## Phase 1: Specification
Before writing any code, define what success looks like:
- List acceptance criteria as binary pass/fail statements
- Each criterion becomes exactly one test
- If criteria are unclear, ask for clarification before proceeding

## Phase 2: Red (Write Failing Test)
1. Write ONE test targeting the first acceptance criterion
2. Run the test suite: `$TEST_COMMAND`
3. Confirm the new test FAILS (and only the new test)
4. If it passes without implementation, the test is wrong — rewrite it
5. Commit the failing test: `git add -A && git commit -m "test: add failing test for [criterion]"`

## Phase 3: Green (Minimal Implementation)
1. Write the MINIMUM code to make the failing test pass
2. Do not add features, optimizations, or "nice to haves"
3. Run the full test suite: `$TEST_COMMAND`
4. ALL tests must pass. If existing tests broke, fix the implementation (not the tests)
5. Commit: `git add -A && git commit -m "feat: implement [criterion]"`

## Phase 4: Refactor
1. With all tests green, improve code quality
2. Extract duplicated logic, improve naming, simplify control flow
3. Run tests after EACH refactoring change
4. Do NOT add new behavior during refactoring
5. Commit if refactoring was non-trivial: `git add -A && git commit -m "refactor: [what improved]"`

## Phase 5: Next Criterion
Repeat phases 2-4 for each remaining acceptance criterion.

## Environment Variables
Replace these with your project's actual commands:
- `$TEST_COMMAND` = the command to run your test suite (e.g., `pnpm test`, `pytest`, `go test ./...`)

## Rules
- NEVER skip the red phase. If you can't make a test fail first, you don't understand the requirement.
- NEVER write implementation code without a failing test driving it.
- NEVER refactor while tests are failing.
- If stuck after 2 attempts, stop and write alternatives to `docs/stasis.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
