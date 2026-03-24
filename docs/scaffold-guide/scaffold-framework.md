# A first-principles framework for Claude Code
**This document is the foundation of the scaffold system built from research and best practices as of March 2026.**

**Structured scaffolding dramatically improves AI code generation because transformer attention mechanisms are architecturally constrained — and every best practice flows from this single fact.** Claude Code's context window fills fast, performance degrades as it fills, and the most effective practitioners treat context as the scarce resource it is. This report synthesizes official Anthropic documentation, peer-reviewed research on transformer architectures, and battle-tested workflows from engineers consuming billions of tokens monthly to build a complete, drop-in framework for Claude Code projects of any size.

The framework rests on three pillars: **specification-driven development** (define what you want before coding), **test-driven verification** (give Claude an external oracle to check itself against), and **hierarchical memory management** (the right information at the right time through CLAUDE.md files, skills, hooks, and sub-agents). Together, these practices exploit how transformers actually process information while mitigating their known failure modes.

---

## Why structured context is not optional — it's architectural

The case for structured scaffolding isn't philosophical. It's grounded in how self-attention works at the hardware level, and the evidence is overwhelming.

**Softmax attention is zero-sum.** Every token in the context window competes for attention weight. At 10,000 tokens, the model manages 100 million pairwise relationships. At 200,000 tokens — Claude Code's working window — that balloons to 40 billion relationships. A 50-line function clearly relevant at 10K tokens becomes one signal among thousands at 200K. The noise floor rises while the signal stays constant. Research from MIT and Meta on "attention sinks" confirmed that initial tokens receive disproportionately high attention scores even when semantically unimportant — the model must "dump" attention somewhere, and the first tokens become default receptacles.

**The "Lost in the Middle" problem is real and measured.** Stanford and Meta researchers demonstrated a U-shaped performance curve: models attend strongly to the beginning and end of context but accuracy plummets for information in the middle. GPT-3.5-Turbo's accuracy fell *below its closed-book baseline* when relevant information was buried in the middle of 20 documents — meaning adding context actively hurt the model. This stems from Rotary Position Embedding (RoPE) properties, where tokens farther apart in sequence receive progressively less mutual attention. The practical implication: **place critical requirements and constraints at the beginning of instruction files**, and reiterate key constraints at the end.

**Length alone degrades reasoning, starting at just ~3,000 tokens.** Researchers at ACL 2024 created tasks where the exact same reasoning problem was embedded in varying lengths of padding text. Performance dropped markedly even with completely unrelated padding. NVIDIA's RULER benchmark found that claimed context lengths far exceed effective ones — GPT-4's effective context is roughly half its claimed 128K. Adobe's NoLiMa benchmark showed 11 of 12 models dropped below 50% of baseline performance at just 32K tokens. The Chroma "Context Rot" study tested 18 frontier models including Claude and found **every single model** degraded with increasing input length, with no exceptions.

The most striking finding comes from a 2025 study showing that even with **100% perfect retrieval** of relevant information, performance degrades 13.9% to 85% as input length increases. This degradation persists even when irrelevant tokens are masked so the model attends only to relevant content. The problem is architectural, not informational.

These findings map directly to code generation failure modes. Research across multiple studies identifies three dominant categories: **logical errors** (~40% of failures, reflecting misunderstanding of requirements), **incomplete code** (~25%, growing as prompt complexity increases), and **context misunderstanding** (~20%, where generated code doesn't align with intended use). The WebApp1K benchmark identified "instruction loss" as the primary bottleneck — models successfully implement individual features but lose track of earlier requirements when multiple features are specified together. This is precisely the attention dilution mechanism at work.

**The relationship between structure and quality is not monotonic.** A 2026 study across 360 configurations found that increasing constraint specificity does not always improve correctness — there's a sweet spot. Too few constraints leave the output distribution too wide; too many overwhelm the model. The optimal point is enough structure to guide, but minimal enough to stay within effective attention range. This finding directly justifies Anthropic's official recommendation to keep CLAUDE.md files under 200 lines.

---

## The context window is the fundamental constraint

Boris Cherny, creator of Claude Code, states it plainly: "Most best practices are based on one constraint: Claude's context window fills up fast, and performance degrades as it fills." Understanding how Claude Code's ~200K token budget gets consumed explains nearly every best practice.

The budget splits roughly as follows: system prompt and tool schemas consume about 4%, CLAUDE.md instructions take a variable but ideally small share, conversation history accounts for approximately 46%, tool results (file reads, grep outputs, bash stdout) consume around 27%, and a response buffer of ~20K tokens is reserved. The critical insight is that **80% of context is typically consumed by file reads and tool results**, not by the conversation itself. This means the biggest lever for context management is controlling what Claude reads, not what you type.

Anthropic provides several commands for managing this constraint. The `/clear` command resets context entirely between unrelated tasks. The `/compact` command triggers manual summarization, and `/compact <instructions>` lets you specify what to preserve. The `/cost` command shows token consumption, and `/context` reveals what's using space. The `/btw` command asks quick questions in a dismissible overlay that never enters conversation history. Auto-compaction triggers automatically when approaching limits, but operates in a degraded state — compacting proactively at ~60% utilization produces much better results than waiting for auto-compact.

The most powerful context management tool is **sub-agents**. They run in separate context windows and report back only summaries, keeping the main conversation clean. One practitioner described the principle: "Delegate research with 'use sub-agents to investigate X.' They explore in a separate context window, keeping your main conversation focused on implementation." Anthropic's documentation calls sub-agents "one of the most powerful tools" precisely because context is the fundamental constraint.

Expert practitioners recommend sessions of 30–45 minutes with precise objectives. By turn ~100, even well-compacted sessions lose early context. The solution: commit progress externally (Git, updated CLAUDE.md notes), `/clear`, and resume fresh. **Structured prompts preserve 92% fidelity through compaction versus 71% for narrative prompts** — another direct consequence of how attention mechanisms handle structured versus unstructured text.

---

## Tests and specifications are the highest-leverage practices

Anthropic's official documentation is unequivocal: "This is the single highest-leverage thing you can do" — give Claude a way to verify its work. The reasons are both architectural and practical.

**Tests create an external oracle that stays accurate regardless of context fill.** Without tests, Claude's only verification mechanism is its own judgment, which degrades as context fills. At 80% accuracy per decision point, 20 sequential decisions yield only 1% overall success (0.8²⁰ = 0.012). TDD collapses ambiguous decisions into verified specifications, and each red-to-green cycle gives Claude unambiguous feedback that survives context compaction.

The empirical evidence is strong. The TiCoder framework (ICSE 2025, Microsoft Research) showed a **45.97% average improvement in pass@1 accuracy** within just 5 user interactions when tests guided intent clarification. The Property-Generated Solver framework achieved **23–37% relative gains** over established TDD methods by using property-based testing as the core validation engine. The Planning-Driven Programming approach achieved up to **16.4% absolute improvement** in Pass@1, with one variant reaching 98.2% on HumanEval.

A surprising finding from the TDAD research (2025): TDD *prompting* alone — telling the model how to do TDD — actually increased regressions by 9.94%. But providing a **test-to-code dependency graph** — telling the model which tests to check — reduced regressions by 70%. The takeaway: agents don't need to be told *how* to do TDD; they need to know *which tests to check*. Contextual, structured information outperforms procedural instructions.

**Specification-driven development has emerged as the complementary practice.** GitHub's Spec Kit, Martin Fowler's analysis, and Addy Osmani's workflow guides converge on the same pattern: define what you want in a structured specification before writing any code. The spec captures intent and scope; tests make that intent executable and verifiable. Together they provide the constraints LLMs need to produce reliable code.

The practical TDD workflow recommended by both Anthropic and experienced practitioners follows this pattern:

1. Write one failing test targeting a specific behavior
2. Confirm the test fails (validates it targets non-existent functionality)
3. Commit the failing test
4. Have Claude implement minimal code to pass
5. Use hooks to auto-run linters and test suites after edits
6. Refactor, then repeat

Jesse Vincent's "superpowers" skill (published in the Anthropic marketplace) enforces this as "tracer bullets" — vertical slices where a single test must fail before implementation begins. The constraint prevents cheating: if a test fails first, the LLM can't fake it. Multiple practitioners report that without explicit guidance, agents naturally skip the refactoring phase, making enforcement through skills or hooks valuable.

---

## The CLAUDE.md specification and what belongs in it

CLAUDE.md is a markdown file that Claude Code reads at the start of every session. It provides persistent instructions for a project, personal workflow, or organization. Anthropic's documentation describes two complementary memory systems: **CLAUDE.md files** (human-written, imposed memory) and **auto memory** (Claude-written, learned from corrections and patterns, stored in MEMORY.md).

The file hierarchy loads from most general to most specific, with later entries overriding earlier ones:

| Location | Scope | When loaded |
|---|---|---|
| `~/.claude/CLAUDE.md` | All projects (personal) | Always at launch |
| Enterprise managed policy | Organization-wide | Always (cannot be excluded) |
| `./CLAUDE.md` or `./.claude/CLAUDE.md` | Project root (shared) | At launch |
| `.claude/local/CLAUDE.md` | Personal project overrides | At launch (gitignored) |
| Subdirectory `CLAUDE.md` | Module-specific | On-demand when Claude reads files in that directory |
| `.claude/rules/*.md` | Per-topic/file-type rules | At launch (same priority as CLAUDE.md) |

The most important authoring principle is brevity. LLMs can reliably follow approximately **150–200 instructions** total, and Claude Code's system prompt already consumes roughly 50 of those slots. HumanLayer's own CLAUDE.md — maintained by a company that builds Claude Code tooling — is under 60 lines. Anthropic's official recommendation is under 200 lines per file, with 80 lines as a strong practical target.

Claude Code wraps CLAUDE.md content in a `<system-reminder>` tag noting that "this context may or may not be relevant." Claude will actively deprioritize content it considers irrelevant to the current task. This means every line must earn its place. The recommended structure follows a WHY/WHAT/HOW pattern:

```markdown
# Project Name
One-line description. Tech stack summary with versions.

## Commands
```bash
npm run dev       # Start dev server
npm run test      # Run all tests  
npm run lint      # Lint and type-check
```

## Architecture
```
src/routes/       # API endpoints
src/models/       # DB models  
src/handlers/     # Business logic
```

## Conventions
- Use Zustand for state, never Redux
- All API responses use `{ success, data, error }` shape
- Database migrations go in src/database/migrations/

## Reference Documents
### API Architecture — `@docs/api-architecture.md`
**Read when:** Adding or modifying API endpoints

### Testing Guide — `@docs/testing.md`  
**Read when:** Writing or updating tests
```

What to include: **project context** (1–2 lines), **essential commands** (dev, test, build, lint), **directory structure**, **non-default conventions only**, and **common gotchas**. What to exclude: standard language conventions the model already knows, detailed API documentation (use progressive disclosure instead), code style enforced by linters (use hooks), file-by-file codebase descriptions, and vague instructions like "write clean code."

The `@path/to/file.md` import syntax enables progressive disclosure — pointing Claude to detailed documentation that it pulls in only when relevant. The `.claude/rules/` directory provides an alternative splitting mechanism where rule files are auto-loaded alongside CLAUDE.md, useful for separating concerns by domain (frontend rules, backend rules, testing rules).

---

## The complete configuration ecosystem

Claude Code's configuration extends well beyond CLAUDE.md into a layered architecture of hooks, skills, sub-agents, and MCP servers. Understanding when to use each layer is critical.

**Hooks are deterministic — they always fire.** Use them for formatting, security enforcement, and validation. A PostToolUse hook that runs Prettier after every file write ensures consistent formatting without consuming instruction budget. A PreToolUse hook that blocks writes to `.env` files provides hard security guarantees that CLAUDE.md instructions cannot. Key principle: never send an LLM to do a linter's job. Formatting rules in CLAUDE.md waste precious instruction slots on something a deterministic tool handles perfectly.

**Skills are probabilistic but context-efficient.** Skills are directories containing a SKILL.md file with YAML frontmatter plus optional scripts and resources. They use approximately 100 tokens for metadata loading and under 5K for full instructions, with bundled resources loading only as needed. Claude discovers skills based on description matching and invokes them when relevant. Multiple skills can remain available without overwhelming context. Simon Willison described skills as "maybe a bigger deal than MCP" for their elegant progressive disclosure model.

**Sub-agents provide context isolation.** Claude Code supports three built-in sub-agent types: Explore (read-only, optimized for codebase search, runs on Haiku by default), Plan (gathers context before strategy), and general-purpose (both exploration and modification). Custom sub-agents are defined as YAML-fronted markdown files in `.claude/agents/`:

```yaml
---
name: security-reviewer
description: Reviews code for security vulnerabilities
tools: Read, Grep, Glob
model: opus
---
You are a senior security engineer. Analyze code for...
```

Each sub-agent runs in its own isolated 200K-token context. Only the final output returns to the parent. Sub-agents cannot spawn further sub-agents. The practical rule of thumb: **2–3 focused information-gathering agents in parallel**, with the main session synthesizing outputs and making decisions.

**MCP servers connect external tools.** Linear, Jira, GitHub, and databases all connect through MCP. Configuration lives in `.mcp.json` (shared, committed to git) or in settings files (personal). Linear provides an official MCP server at `https://mcp.linear.app/mcp` with full issue, project, and cycle management capabilities. Atlassian provides a similar server for Jira and Confluence.

The recommended layering principle: CLAUDE.md for foundational instructions (always loaded, concise), skills for repeatable domain workflows (loaded on demand), hooks for deterministic automation (always fires, no exceptions), sub-agents for parallelization (isolated context), and MCP servers for external tool integration.

The complete `.claude` directory structure for a mature project:

```
project-root/
├── CLAUDE.md                     # Project instructions (committed)
├── .mcp.json                     # Shared MCP config (committed)
├── .claude/
│   ├── settings.json             # Permissions, hooks (committed)
│   ├── settings.local.json       # Personal settings (gitignored)
│   ├── rules/
│   │   ├── frontend.md           # Rules for frontend code
│   │   ├── api.md                # Rules for API code
│   │   └── testing.md            # Testing conventions
│   ├── skills/
│   │   └── tdd/
│   │       └── SKILL.md          # TDD enforcement skill
│   ├── agents/
│   │   ├── code-reviewer.md      # Review sub-agent
│   │   └── test-writer.md        # TDD sub-agent
│   └── commands/
│       └── catchup.md            # Custom /catchup command
```

---

## Scaling from side projects to monorepos

The hierarchical CLAUDE.md system is the primary mechanism for scaling. A monorepo's root CLAUDE.md should contain only the high-level repo map, tech stack, standard commands, and "do not touch" zones — kept under **13–25KB** according to practitioners at Abnormal AI. Subdirectory CLAUDE.md files load on-demand when Claude works in those directories, providing module-specific context without polluting the global window.

One practitioner reduced their CLAUDE.md from 47,000 words to 9,000 by splitting context across frontend, backend, and core services. Backend components don't need frontend guides. This principle — **only load what's relevant to the current task** — flows directly from the attention dilution research.

**Git worktrees have emerged as the dominant technique for parallel AI development.** Claude Code v2.1.50+ has native worktree support: `claude --worktree feature-auth` creates an isolated directory with its own branch and file state. Teams at incident.io report running 4–5 parallel Claude sessions as their default workflow. Combined with tmux, this enables genuinely parallel development where each session has its own full context budget.

The practical scaling patterns that emerge from practitioner reports:

- **One objective per session.** Name the goal explicitly. Reset when the goal changes.
- **Prefer grep/glob before dumping code.** Ask the agent to search for symbol usage first, then open only the 3–5 most relevant files.
- **Use .claudeignore** to exclude node_modules, dist, .git, large data files, and generated code.
- **Chunk refactoring tasks** into individual file-level operations, each with its own verification step, rather than attempting bulk changes.
- **Encode patterns as templates, not descriptions.** "Follow the same pattern as components/UserCard.tsx" improves consistency by roughly 65% compared to describing the pattern in prose.

For task decomposition across sub-agents, the most common pattern is orchestrator-worker: a parent agent analyzes a task, decides how to delegate, and spawns sub-agents that each work independently and return summaries. One team at Abnormal AI prefers a simpler "master-clone" approach: let the main agent spawn copies of itself using the built-in `Task(...)` feature rather than defining custom sub-agents, since custom agents "gatekeep context" and "force human workflows."

---

## What top practitioners actually do day-to-day

Anthropic surveyed 132 engineers and conducted 53 in-depth interviews about internal Claude Code usage. The results: engineers use Claude in **59% of their work** (up from 28% one year prior), report a **50% productivity boost**, and show a **67% increase in merged pull requests per engineer per day**. Roughly 27% of Claude-assisted work consists of tasks that wouldn't have been done at all otherwise — quality-of-life improvements, documentation, and "papercut" fixes.

The Anthropic Security team's workflow illustrates the TDD pattern in practice: instead of "design doc → janky code → refactor → give up on tests," their pattern became "pseudocode → TDD → periodic check-ins." They use more custom slash commands than any other team — 50% of all slash command implementations in the entire Anthropic monorepo. The Product team uses auto-accept mode (Shift+Tab) for rapid prototyping, reviewing the 80% complete solution before taking over for the final 20%.

**Shrivu Shankar at Abnormal AI**, whose team consumes billions of tokens monthly, recommends avoiding `/compact` entirely in favor of a `/clear` + custom `/catchup` command that reads all changed files in the current git branch. For complex tasks, the "Document & Clear" pattern: have Claude dump its plan into a markdown file, `/clear`, then start a fresh session reading that file. His team uses Claude Code GitHub Actions as their "most slept-on feature," enabling PR creation from anywhere — Slack, Jira, CloudWatch alerts. They regularly review GHA logs for common agent mistakes and feed improvements back into CLAUDE.md, creating a continuous improvement flywheel.

**Simon Willison** built a `claude-code-transcripts` tool for creating readable HTML versions of sessions. His key contribution to the community is the concept of "cognitive debt" — code that runs but you don't understand the principle behind it. His mitigation: use Claude's explanation capabilities to walk through generated code line-by-line after it's working.

**Thorsten Ball**, co-founder of Amp and contributor to Ghostty, reduces the entire agent architecture to 315 lines of code: "an LLM, a loop, and enough tokens." His central insight: knowing what context to add and what to tell the model is "90% of the game." His practical test for CLAUDE.md attention: tell Claude to call you by a distinctive name, and you can tell when it stops paying attention to instructions when it stops using the name.

The anti-patterns that experienced practitioners consistently flag:

- **The kitchen-sink session**: mixing unrelated tasks in one conversation. Fix: `/clear` between tasks.
- **Correcting over and over**: context polluted with failed approaches. Fix: after two failed corrections, `/clear` and write a better initial prompt incorporating lessons learned.
- **The over-specified CLAUDE.md**: too long, Claude ignores half. Fix: ruthlessly prune; if Claude already does something correctly without the instruction, delete it.
- **Not using scaffolding**: one practitioner described spending "more time removing code and fixing bugs than if I'd just coded it myself" because autonomous loops without patterns produced hallucinated solutions and technical debt faster than cleanup could handle.
- **@-mentioning docs in CLAUDE.md**: bloats context by embedding entire files on every run. Instead, "pitch" the agent on why and when to read a file using progressive disclosure.

---

## Integrating project management into the workflow

The MCP protocol enables direct integration between Claude Code and project management tools, closing the loop between task definition and implementation.

**Linear** provides an official remote MCP server at `https://mcp.linear.app/mcp` using OAuth 2.1 authentication. Configuration is straightforward: `claude mcp add --transport http linear-server https://mcp.linear.app/mcp`, then run `/mcp` in a Claude Code session to complete the OAuth flow. Once connected, Claude can find, create, and update issues, manage projects and cycles, and interact with documents — all through natural language in the terminal.

**GitHub's integration runs deeper.** The official `anthropics/claude-code-action` GitHub Action enables @claude mentions on any issue or PR. Comment `@claude fix this bug` on an issue and Claude creates a complete PR. GitHub's Agent HQ now allows assigning issues directly to Claude, Copilot, or Codex, producing reviewable artifacts.

**Jira integration** works through Atlassian's official remote MCP server supporting Jira, Confluence, and Compass. An open-source alternative, `mcp-atlassian`, provides equivalent functionality with local credential management.

The emerging pattern for JTBD-style task management combines Linear (or similar) as the source of truth with Claude Code as the executor. Each task in the board maps to a Claude Code session with a clear objective, acceptance criteria, and verification steps. The task definition becomes the specification; tests derived from acceptance criteria become the verification; Claude Code becomes the implementation engine. Tools like Vibe Kanban (9.4K GitHub stars) orchestrate this by running each task in an isolated Git worktree with a dedicated AI agent session.

---

## The agent instruction file ecosystem beyond Claude Code

CLAUDE.md is Claude Code's native format, but a broader ecosystem of agent instruction files is rapidly converging.

**AGENTS.md** has emerged as the leading universal standard, stewarded by the Agentic AI Foundation under the Linux Foundation. It's supported natively by Codex (OpenAI), Jules (Google), Cursor, Devin, JetBrains Junie, GitHub Copilot, Windsurf, and over 20 other tools, used by 60,000+ open-source projects. Claude Code does *not* natively read AGENTS.md — the recommended bridge is a symlink: `ln -s AGENTS.md CLAUDE.md`.

Other formats include `.cursor/rules/*.mdc` (Cursor's current recommended format), `.github/copilot-instructions.md` and `.github/instructions/*.instructions.md` (GitHub Copilot), `.windsurf/rules/*.md` (Windsurf), `GEMINI.md` (Google's Gemini CLI), and tool-specific files for Amazon Q, JetBrains AI, Roo Code, and Augment Code.

For multi-tool teams, three synchronization approaches exist. **Symlinks** (`ln -s AGENTS.md CLAUDE.md`) are simplest. **Pre-commit hook sync** copies a single source file to all tool-specific locations. **Controlled divergence** puts 90%+ of shared content in AGENTS.md with tool-specific additions only in native files (CLAUDE.md `@path` imports, Cursor MDC frontmatter, etc.).

---

## Conclusion

The framework that emerges from this research is not a collection of tips but a direct consequence of transformer architecture. Self-attention is zero-sum; context length degrades reasoning starting at 3,000 tokens; information in the middle of long contexts gets lost; and irrelevant context actively misleads. Every effective practice — concise CLAUDE.md files, TDD verification loops, progressive disclosure of documentation, sub-agent context isolation, specification-driven development, and aggressive use of `/clear` — traces back to managing these architectural constraints.

Three practices deserve special emphasis as highest-leverage. First, **give Claude a way to verify its work** through tests, screenshots, or expected outputs. Second, **keep instruction files short and specific** — 60–80 lines is the proven sweet spot, with progressive disclosure handling everything else. Third, **use sub-agents and `/clear` aggressively** to maintain fresh, focused context rather than letting a single session degrade.

The emerging consensus across Anthropic's internal teams, independent practitioners consuming billions of tokens monthly, and academic research points to a workflow that is less about prompt engineering and more about **development discipline**: define specifications before coding, write tests before implementation, commit frequently, reset context between tasks, and encode patterns as templates rather than descriptions. The LLM becomes dramatically more capable when you treat it less like a magic oracle and more like a literal-minded junior engineer who needs clear requirements, verification mechanisms, and well-organized context to do excellent work.