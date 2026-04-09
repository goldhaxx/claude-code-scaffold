# [Project Name]

[One-line description.]

## Tech Stack
<!-- NODE-SPECIFIC: Replace with your project's actual tech stack -->

## Commands
<!-- NODE-SPECIFIC: Replace with your project's actual commands -->
```bash
bash .ccanvil/scripts/docs-check.sh activate <id> # Activate a spec → create branch + draft PR
bash .ccanvil/scripts/docs-check.sh complete <id> # Mark spec complete, clean up, mark PR ready
bash .ccanvil/scripts/docs-check.sh land           # Return to main after merge
bash .ccanvil/scripts/docs-check.sh idea-add "text" # Capture an idea
bash .ccanvil/scripts/docs-check.sh radar-gather    # Project state JSON for /radar
bash .ccanvil/scripts/context-budget.sh check --text # Context budget
bash .ccanvil/scripts/security-audit.sh              # PII/secrets scan
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
├── ccanvil.json       # Hub-tracked config (feature toggles, defaults)
└── ccanvil.local.json # Node-only overrides (gitignored, deep-merged at read time)
.ccanvil/
├── scripts/      # Preset automation scripts (synced from hub)
├── guide/        # Preset reference docs (synced from hub)
└── templates/    # Format guides and GitHub templates
```

<!-- HUB-MANAGED-START -->
<!-- Everything above is project-specific (name, stack, commands, architecture). -->
<!-- Everything below is managed by the preset hub and updated via /ccanvil-pull. -->

## Workflow: Specification → Test → Implement → Verify

**Every feature follows this sequence. No exceptions.**

1. **Spec first.** Before coding, define acceptance criteria in `docs/spec.md`. Each criterion must be binary: pass or fail.
2. **Test first.** Write one failing test targeting the first acceptance criterion. Run it. Confirm it fails.
3. **Implement minimally.** Write only enough code to pass the failing test.
4. **Verify.** Run the full test suite. If anything broke, fix it before moving on.
5. **Refactor.** Clean up only after all tests pass. Never refactor and add features simultaneously.
6. **Commit.** One logical change per commit. Message format: `type(scope): description`

## Reference Documents
### Preset Guide — .ccanvil/guide/index.md
**Read when:** Adding or modifying preset commands, rules, agents, skills, hooks, or scripts.

## Do Not
- Do not modify `.ccanvil/guide/foundations.md` without explicit user approval — it is foundational research source material.
- Do not modify files in `generated/`, `dist/`, or dependency directories.
- Do not install new dependencies without stating the reason and alternatives considered.
