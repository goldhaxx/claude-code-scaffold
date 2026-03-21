# Code Quality Rules

## Patterns Over Descriptions

- When a codebase has an established pattern, follow it exactly.
- Say "Follow the same pattern as [specific file]" rather than describing the pattern.
- If no pattern exists, establish one explicitly and document it.

## Error Handling

- Every function that can fail must have an explicit error path.
- Never swallow errors silently. Log them or propagate them.
- Use typed errors, not generic strings. Create error classes or union types.
- External service calls always get try/catch with meaningful error context.

## Dependencies

- Before adding a dependency, state: what it does, why a native solution won't work, and its maintenance status.
- Prefer standard library and built-in APIs over third-party packages.
- Pin dependency versions. No `^` or `~` in production dependencies.

## Code Organization

- One concept per file. If a file exceeds ~200 lines, consider splitting.
- Imports at the top, exports at the bottom, logic in the middle.
- No circular dependencies. If module A imports B and B imports A, refactor.
- Constants and configuration at the top of the file or in a dedicated config module.

## Protected Files

- `SCAFFOLD_FRAMEWORK.md` is research source material — never modify it without explicit user approval. It documents the foundational research (transformer attention, TDD evidence, context management) that justifies every scaffold design decision. Only update for paradigm shifts, new research findings, or major industry practice changes.

## Naming

- Names should reveal intent. `getUserById` not `getData`. `isExpired` not `check`.
- Boolean variables start with is/has/can/should.
- Functions that return promises are named with verbs: `fetchUser`, `createOrder`.
- Avoid abbreviations unless universally understood (id, url, api).
