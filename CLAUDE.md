# [Project Name]

[One-line description.]

## Tech Stack
- Runtime: Bash (scaffold automation scripts)
- Testing: bats-core 1.13.0
- Package Manager: Homebrew (brew install bats-core)

## Commands
```bash
bats tests/                          # Run all tests
bats tests/scaffold-sync.bats        # Run scaffold sync tests only
bats tests/security-audit.bats       # Run security audit tests only
bats tests/feature-lifecycle.bats    # Run feature lifecycle tests only
bash scripts/security-audit.sh       # Run PII/secrets scan
bash scripts/permissions-audit.sh check --settings-dir .claude  # Audit permissions
bash scripts/permissions-audit.sh init --settings-dir .claude   # Init decision log
bash scripts/context-budget.sh check                            # Context budget (JSON)
bash scripts/context-budget.sh check --text                     # Context budget (human)
bash scripts/context-budget.sh check --model claude-opus-4-6[1m] --text  # With model
bash scripts/docs-check.sh list-specs    # List specs in backlog
bash scripts/docs-check.sh activate <id> # Activate a spec → create branch
bash scripts/docs-check.sh complete <id> # Mark spec complete
bash scripts/operations.sh resolve <operation>              # Resolve operation routing
bash scripts/operations.sh resolve <operation> --project-dir DIR  # With project dir
bash scripts/operations.sh merge-config                     # Merged effective config (JSON)
bash scripts/operations.sh merge-config --project-dir DIR   # With project dir
bash -n scripts/scaffold-sync.sh     # Syntax check the sync script
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
├── specs/        # Spec backlog (Draft/Ready/In Progress/Complete)
├── spec.md       # Active feature specification (branch-local)
├── plan.md       # Implementation plan (branch-local)
├── checkpoint.md # Progress state for session continuity
└── assumptions.md # Judgment calls made during implementation
.claude/
├── scaffold.json       # Hub-tracked config (feature toggles, defaults)
└── scaffold.local.json # Node-only overrides (gitignored, deep-merged at read time)
```

<!-- HUB-MANAGED-START -->
<!-- Everything above is project-specific (name, stack, commands, architecture). -->
<!-- Everything below is managed by the scaffold hub and updated via /scaffold-pull. -->

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
