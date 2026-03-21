# [Project Name]

[One-line description.]

## Tech Stack
<!-- Updated by Claude Code as technical decisions are made. -->
- Runtime: TBD
- Framework: TBD
- Testing: TBD
- Package Manager: TBD

## Commands
<!-- Updated by Claude Code when the project toolchain is established. -->
```bash
# Commands will be added here as the project is set up.
# Example: npm run dev, npm test, npm run lint, npm run build
```

## Architecture
```
src/
├── app/          # Entry points, routes, pages
├── lib/          # Shared utilities and helpers
├── services/     # Business logic (one file per domain)
├── models/       # Data models, types, schemas
└── __tests__/    # Test files mirror src/ structure
docs/
├── spec.md       # Current feature specification
├── plan.md       # Implementation plan
└── checkpoint.md # Progress state for session continuity
```

## Workflow: Specification → Test → Implement → Verify

**Every feature follows this sequence. No exceptions.**

1. **Spec first.** Before coding, define acceptance criteria in `docs/spec.md`. Each criterion must be binary: pass or fail.
2. **Test first.** Write one failing test targeting the first acceptance criterion. Run it. Confirm it fails.
3. **Implement minimally.** Write only enough code to pass the failing test.
4. **Verify.** Run the full test suite. If anything broke, fix it before moving on.
5. **Refactor.** Clean up only after all tests pass. Never refactor and add features simultaneously.
6. **Commit.** One logical change per commit. Message format: `type(scope): description`

## Conventions
- All functions that can fail return typed errors or throw typed exceptions — never return null for errors.
- API responses use shape: `{ success: boolean, data?: T, error?: string }`
- File names: kebab-case. Component/class names: PascalCase. Variables: camelCase.
- No barrel exports (index re-exports). Import directly from the source file.
- Environment variables: typed in a dedicated config module, never accessed raw.

## Reference Documents
### Scaffold Guide — @GUIDE.md
**Read when:** Adding or modifying scaffold commands, rules, agents, skills, hooks, or scripts. Update its diagrams and tables to reflect the change.

### Architecture Decisions — @docs/decisions.md
**Read when:** Making structural changes, adding dependencies, or changing patterns.

### Testing Guide — @docs/testing.md
**Read when:** Writing tests or debugging test failures.

## Do Not
- Do not modify `SCAFFOLD_FRAMEWORK.md` without explicit user approval — it is foundational research source material.
- Do not modify files in `generated/`, `dist/`, or dependency directories.
- Do not install new dependencies without stating the reason and alternatives considered.
- Do not suppress type errors — fix the types.
- Do not change the database schema without writing a migration.
