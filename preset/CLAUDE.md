# [Project Name]

[One-line description.]

## Tech Stack
<!-- NODE-SPECIFIC: Replace with your project's actual tech stack -->

## Commands
<!-- NODE-SPECIFIC: Replace with your project's actual commands -->
```bash
bash .ccanvil/scripts/security-audit.sh       # Run PII/secrets scan
bash .ccanvil/scripts/permissions-audit.sh check --settings-dir .claude  # Audit permissions
bash .ccanvil/scripts/context-budget.sh check --text                     # Context budget
bash .ccanvil/scripts/docs-check.sh list-specs    # List specs in backlog
bash .ccanvil/scripts/docs-check.sh activate <id> # Activate a spec → create branch
bash .ccanvil/scripts/docs-check.sh complete <id> # Mark spec complete
bash .ccanvil/scripts/operations.sh resolve <operation>   # Resolve operation routing
bash .ccanvil/scripts/operations.sh merge-config          # Merged effective config (JSON)
```

## Architecture
<!-- NODE-SPECIFIC: Replace with your project's actual architecture -->
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
.ccanvil/
├── scripts/      # Preset automation scripts (synced from hub)
├── guide/        # Preset reference docs (synced from hub)
└── templates/    # Format guides and GitHub templates
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
### Preset Guide — .ccanvil/guide/index.md
**Read when:** Adding or modifying preset commands, rules, agents, skills, hooks, or scripts. Read the index first, then the relevant section file. Update diagrams and tables to reflect the change.

### Architecture Decisions — @docs/decisions.md
**Read when:** Making structural changes, adding dependencies, or changing patterns.

### Testing Guide — @docs/testing.md
**Read when:** Writing tests or debugging test failures.

## Do Not
- Do not modify `.ccanvil/guide/scaffold-framework.md` without explicit user approval — it is foundational research source material.
- Do not modify files in `generated/`, `dist/`, or dependency directories.
- Do not install new dependencies without stating the reason and alternatives considered.
- Do not suppress type errors — fix the types.
- Do not change the database schema without writing a migration.
