# Claude Code Preset System — Agent Customization Guide

You are being asked to customize a ccanvil preset for a specific project. Before making any changes, you must understand the system's architecture, constraints, and the reasoning behind them. **Every constraint below is grounded in transformer attention research and Anthropic's official best practices. Do not deviate from them.**

---

## What This System Is

This is a structured preset for working with Claude Code (Anthropic's CLI coding agent). It consists of layered configuration files that control how Claude Code behaves during development sessions. The preset enforces three principles:

1. **Specification-driven development** — Define acceptance criteria before writing code
2. **Test-driven verification** — Tests are the external oracle that keeps implementation honest
3. **Context discipline** — Claude Code's ~200K token context window degrades as it fills; every file in this system is designed to minimize context consumption while maximizing signal

---

## File Hierarchy and Load Order

Claude Code loads files from most general to most specific. Later files override earlier ones on conflicts.

| File | Location | Scope | Loaded When |
|------|----------|-------|-------------|
| Global personal | `~/.claude/CLAUDE.md` | All projects | Always at launch |
| **Project root** | `./CLAUDE.md` | This project | **Always at launch** |
| Rules | `.claude/rules/*.md` | Per-topic | Always at launch (same priority as CLAUDE.md) |
| Subdirectory | `./src/api/CLAUDE.md` | Module-specific | On-demand when Claude works in that directory |
| Skills | `.claude/skills/*/SKILL.md` | Workflow-specific | On-demand when skill triggers match |
| Agents | `.claude/agents/*.md` | Task-specific | On-demand when spawned as sub-agents |
| Commands | `.claude/commands/*.md` | Slash commands | On-demand when user invokes `/command-name` |
| Settings | `.claude/settings.json` | Hooks, permissions | Always at launch |
| MCP config | `.mcp.json` | Tool connections | Always at launch |
| Ignore rules | `.claudeignore` | File exclusions | Always at launch |

### Complete directory structure:
```
project-root/
├── CLAUDE.md                          # Project identity, stack, commands, conventions
├── .claudeignore                      # Files/dirs Claude should never read
├── .mcp.json                          # MCP server connections (Linear, Jira, etc.)
├── .claude/
│   ├── settings.json                  # Permissions, hooks (deterministic automation)
│   ├── settings.local.json            # Personal overrides (gitignored)
│   ├── rules/
│   │   ├── tdd.md                     # TDD enforcement rules
│   │   ├── workflow.md                # Session and context management rules
│   │   └── code-quality.md            # Code standards and patterns
│   ├── skills/
│   │   └── tdd/
│   │       └── SKILL.md               # Full TDD workflow procedure
│   ├── agents/
│   │   ├── code-reviewer.md           # Code review sub-agent
│   │   └── spec-writer.md             # Specification writing sub-agent
│   └── commands/
│       ├── catchup.md                 # /catchup — Resume after /compact or /clear
│       ├── plan.md                    # /plan — Create implementation plan
│       └── review.md                  # /review — Review uncommitted changes
└── docs/
    ├── spec.md                        # Current feature specification
    ├── plan.md                        # Implementation plan
    └── checkpoint.md                  # Session continuity state
```

---

## Hard Constraints — Do Not Violate

These constraints exist because of measured transformer attention limitations. They are not style preferences.

### CLAUDE.md Constraints

1. **Maximum 80 lines, ideally 50-60.** Claude Code wraps CLAUDE.md in a `<system-reminder>` tag noting that content "may or may not be relevant." Beyond ~150-200 total instructions (including system prompt overhead), Claude actively deprioritizes content. The project CLAUDE.md shares this budget with global config and rules files.

2. **Most important instructions go at the TOP and are briefly reiterated at the BOTTOM.** Research demonstrates a U-shaped attention curve: models attend strongly to the beginning and end of context, but accuracy plummets for information in the middle.

3. **No content Claude already knows.** Do not include standard language conventions (e.g., "use const instead of let in JavaScript"), common framework patterns, or anything the model does correctly without being told. Every line must correct a default behavior or establish a project-specific convention.

4. **No detailed documentation inline.** Use the `@path/to/file.md` import syntax to point Claude to detailed docs. Claude loads these on-demand rather than consuming context on every session.

5. **Commands must be copy-pasteable.** Wrap all commands in code blocks with the exact invocation. Do not describe commands in prose.

6. **Architecture section uses a directory tree, not prose descriptions.** A tree structure is information-dense and parseable. Prose wastes tokens.

7. **Conventions section lists only deviations from defaults.** "We use Zustand instead of Redux" is useful. "Components use PascalCase" is not (that's already standard).

### Rules Files Constraints (`.claude/rules/*.md`)

1. **Each file covers ONE concern.** Don't mix testing rules with deployment rules.
2. **Maximum 40 lines per file.** Rules load alongside CLAUDE.md into the same attention budget.
3. **Imperative, actionable language.** "Run the test suite after every file edit" not "It's generally a good idea to test frequently."
4. **No overlap with CLAUDE.md content.** Rules extend CLAUDE.md; they don't repeat it.

### Skills Constraints (`.claude/skills/*/SKILL.md`)

1. **YAML frontmatter is required** with `name` and `description` fields.
2. **Description must specify trigger conditions** — when should Claude activate this skill?
3. **~100 tokens for metadata, under 5K for full instructions.** Skills are designed for progressive disclosure.
4. **Skills are probabilistic.** Claude may or may not activate them based on description matching. For mandatory behavior, use hooks or rules instead.

### Agent Constraints (`.claude/agents/*.md`)

1. **YAML frontmatter is required** with `name`, `description`, `tools`, and optionally `model`.
2. **Tools must be explicitly listed.** Agents only have access to tools you grant: `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash(command:*)`, `Task`.
3. **Each agent runs in an isolated 200K context window.** Only the final output returns to the parent session.
4. **Agents cannot spawn sub-agents.** One level of delegation only.
5. **Model selection matters:** `haiku` for simple lookups, `sonnet` for most tasks, `opus` for complex reasoning.

### Commands Constraints (`.claude/commands/*.md`)

1. **File name becomes the slash command.** `catchup.md` → `/catchup`
2. **First line should describe what the command does.**
3. **Numbered steps for multi-step procedures.**
4. **Commands should NOT implement — they should orient, plan, or delegate.**

### Settings Constraints (`.claude/settings.json`)

1. **Hooks are deterministic — they always fire.** Use for formatting, security, validation.
2. **Never put formatting rules in CLAUDE.md.** Use a PostToolUse hook with Prettier/Black/gofmt instead.
3. **PreToolUse hooks can block dangerous operations** (writing to .env, deleting protected files).
4. **Permissions whitelist preferred over blacklist.** Explicitly allow safe commands.

### .claudeignore Constraints

1. **Exclude everything that doesn't contain project logic:** node_modules, dist, coverage, lock files, .env, large data files, generated code.
2. **This is the single biggest lever for context management.** File reads consume ~80% of Claude Code's context. Excluding irrelevant files prevents them from ever entering the window.

---

## How to Customize the CLAUDE.md for a New Project

When asked to set up or customize this preset for a specific project, follow this procedure:

### Step 1: Gather Minimal Information
Ask the user for only two things:
- **Project name**
- **One-line description of what it does**

Do NOT ask about tech stack, framework, commands, directory structure, or conventions at initialization time. The preset provides opinionated defaults for all of these. Technical decisions are made later, during the spec-and-build workflow, as the project takes shape.

### Step 2: Write the CLAUDE.md
Replace only the `[Project Name]` and `[One-line description]` placeholders. Leave the Tech Stack section as TBD, leave the Commands section as the placeholder comment, and leave the Architecture, Conventions, and Do Not sections as their preset defaults.

The CLAUDE.md template is designed to work as-is. Do not add sections. Do not exceed 80 lines.

As the project evolves and technical decisions are made (choosing a framework, setting up a test runner, installing a database), update the Tech Stack and Commands sections to reflect those decisions. This is an ongoing process, not an upfront one.

### Step 3: Update Supporting Files (only if needed)
Most supporting files work out of the box. Only modify if the user has a specific request:
- **`.claudeignore`**: Defaults cover common patterns. Add project-specific exclusions only as they arise.
- **`.claude/settings.json`**: The formatter hook is commented out by default. Uncomment and configure when a formatter is chosen.
- **`.mcp.json`**: Pre-configured for Linear. Remove or add servers based on what the user actually uses.
- **Rules/Skills/Agents/Commands**: These are project-agnostic. Do not modify unless the user explicitly asks.

### Step 4: Validate
After initialization, verify:
- [ ] CLAUDE.md is under 80 lines
- [ ] Only the project name and description placeholders were replaced
- [ ] The preset defaults (architecture, conventions, do-not rules) are intact
- [ ] No overlap between CLAUDE.md and rules files
- [ ] .claudeignore is present
- [ ] settings.json is present with hooks

---

## What NOT To Do

- **Do not add verbose explanations.** Every token in CLAUDE.md competes for attention with actual code context.
- **Do not include standard language idioms.** Claude already knows TypeScript conventions, Python PEP 8, Go formatting rules, etc.
- **Do not embed full API docs.** Use `@path/to/doc.md` progressive disclosure instead.
- **Do not describe the codebase file-by-file.** The architecture tree is sufficient. Claude uses grep/glob to explore.
- **Do not add aspirational rules.** If it says "always write comprehensive error handling" but the codebase doesn't do that consistently, Claude will be confused by the contradiction. Only codify what is actually enforced.
- **Do not duplicate rules across files.** If TDD rules are in `.claude/rules/tdd.md`, do not also describe TDD procedure in CLAUDE.md. The workflow summary in CLAUDE.md is the bridge; the rules file has the detail.
- **Do not put formatting rules in any markdown file.** Formatting is deterministic. Use hooks in settings.json.

---

## Examples: CLAUDE.md Lifecycle

### At initialization (after `/init`)

This is what CLAUDE.md looks like right after running `/init`:

```markdown
# Acme Dashboard

Internal analytics dashboard for the Acme sales team.

## Tech Stack
<!-- Updated by Claude Code as technical decisions are made. -->
- Runtime: TBD
- Framework: TBD
- Testing: TBD
- Package Manager: TBD

## Commands
<!-- Updated by Claude Code when the project toolchain is established. -->
\```bash
# Commands will be added here as the project is set up.
\```

## Architecture
\```
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
\```

[... rest is preset defaults: Workflow, Conventions, Reference Documents, Do Not ...]
```

*Only the name and description were filled in. Everything else uses preset defaults.*

### After several features built (evolved over weeks)

As technical decisions are made during development, Claude Code updates the TBD sections:

```markdown
# Acme Dashboard

Internal analytics dashboard for the Acme sales team.

## Tech Stack
- Runtime: Node.js 22 / TypeScript 5.7
- Framework: Next.js 15 (App Router)
- Database: PostgreSQL 16 via Drizzle ORM
- Testing: Vitest + React Testing Library
- Package Manager: pnpm 9

## Commands
\```bash
pnpm dev              # Start dev server on :3000
pnpm test             # Run Vitest
pnpm test:watch       # Vitest in watch mode
pnpm lint             # ESLint + tsc --noEmit
pnpm db:migrate       # Run pending Drizzle migrations
pnpm db:generate      # Generate migration from schema changes
\```

## Architecture
\```
src/
├── app/              # Next.js App Router pages and layouts
│   └── api/          # Route handlers
├── components/       # React components (PascalCase files)
├── lib/              # Shared utilities, db client, auth helpers
├── services/         # Business logic (one file per domain)
├── schema/           # Drizzle ORM table definitions
└── __tests__/        # Mirrors src/ structure
drizzle/              # Generated migrations (do not edit manually)
\```

[... Workflow section unchanged from preset ...]

## Conventions
- State management: Zustand stores in `lib/stores/`. No Redux, no React Context for global state.
- API responses: `{ success: boolean, data?: T, error?: string }`
- DB queries go in `services/`, never in route handlers or components.
- Server Components by default. Add `"use client"` only when hooks or interactivity required.
- All env vars typed in `lib/env.ts`. Access via `env.DATABASE_URL`, never `process.env` directly.

## Reference Documents
### Database Schema Guide — @docs/schema.md
**Read when:** Adding or modifying database tables.

### Component Patterns — @docs/components.md
**Read when:** Creating new UI components. Follow the Card pattern in `components/MetricCard.tsx`.

## Do Not
- Do not edit files in `drizzle/` — these are generated migrations.
- Do not add dependencies without stating reason and alternatives.
- Do not suppress type errors — fix the types.
- Do not put DB queries in components or route handlers.
\```

*This evolved version is 58 lines. The CLAUDE.md grew organically from preset defaults as technical decisions were made during development.*

---

## Summary of Token Budgets

| File Type | Target Length | Hard Max | Why |
|-----------|-------------|----------|-----|
| CLAUDE.md (project) | 50-60 lines | 80 lines | Shares ~150 instruction slots with global + rules |
| CLAUDE.md (global) | 20-30 lines | 40 lines | Loaded for every project; must be minimal |
| Rules files | 20-30 lines each | 40 lines each | Load alongside CLAUDE.md into same budget |
| Skills | Under 5K tokens | — | Progressive disclosure; metadata ~100 tokens |
| Agents | 30-50 lines | — | Isolated context; more room but clarity still matters |
| Commands | 10-20 lines | — | Procedural; loaded on-demand only |
| Total rules+CLAUDE.md | — | ~150 instructions | Beyond this, Claude deprioritizes content |
