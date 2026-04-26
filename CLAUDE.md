# ccanvil

Configuration preset hub for Claude Code — spec-driven development, deterministic-first automation, bi-directional sync between hub and downstream project nodes.

## Tech Stack
- Runtime: Bash (preset automation scripts)
- Testing: bats-core 1.13.0
- Package Manager: Homebrew (brew install bats-core)

## Commands
```bash
bash .ccanvil/scripts/bats-report.sh --parallel           # Run full suite (parallel, ~75% faster)
bats hub/tests/                                           # Run all tests (serial)
bash .ccanvil/scripts/docs-check.sh activate <id>         # Activate spec → branch + draft PR
bash .ccanvil/scripts/docs-check.sh complete <id>         # Complete spec → cleanup + PR ready
bash .ccanvil/scripts/docs-check.sh land                  # Return to main after merge
bash .ccanvil/scripts/docs-check.sh idea-add "text"       # Capture an idea
bash .ccanvil/scripts/docs-check.sh radar-gather          # Project state JSON for /radar
bash .ccanvil/scripts/context-budget.sh check --text      # Context budget
bash .ccanvil/scripts/ccanvil-sync.sh stack-list          # List stack profiles
bash .ccanvil/scripts/ccanvil-sync.sh stack-apply <id>    # Apply stack to project
# Full command list: .ccanvil/guide/command-reference.md
```

## Architecture
```
.claude/                    # Rules, commands, agents, skills, hooks, settings
.ccanvil/                   # Scripts, guide, templates — /init copies from here
├── scripts/                # ccanvil-sync.sh, docs-check.sh, operations.sh
├── guide/                  # Preset reference docs (12 section files)
└── templates/              # Format guides, GitHub templates
CLAUDE.md                   # Project template (node + hub-managed sections)
hub/                        # Hub-only — NOT distributed
├── stacks/                 # Tech stack profiles (fastapi-sqlite, etc.)
├── tests/                  # bats-core test suite (12 .bats files)
├── specs/                  # Completed spec archive
└── meta/                   # SYSTEM_PROMPT.md, INIT_PROMPT.md
docs/                       # Active feature lifecycle (branch-local)
├── specs/                  # Per-feature spec archive (committed history)
└── sessions/               # Per-session stasis archive (committed history — BTS-22)
```

## Fork Setup
`.mcp.json.example` is a template for forks that want the project-scoped Linear MCP server. To activate: rename to `.mcp.json` and complete OAuth via `/mcp`. Contributors who already have Linear wired up via their claude.ai account (`claude.ai Linear`) don't need this — it's a convenience for fresh clones.

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
