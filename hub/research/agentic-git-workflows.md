# Agentic Git Workflows: Deep Research Report

> **Research date:** 2026-03-22
> **Scope:** How top AI-first engineering teams handle git workflows in agentic coding environments
> **Sources:** 25+ primary sources across official documentation, engineering blogs, conference talks, and open-source repositories

---

## Table of Contents

1. [Per-Team Findings](#1-per-team-findings)
2. [Common Patterns](#2-common-patterns)
3. [Divergent Approaches](#3-divergent-approaches)
4. [Recommendations for Our Scaffold](#4-recommendations-for-our-scaffold)

---

## 1. Per-Team Findings

### 1.1 Anthropic — Claude Code

**Sources:** [Claude Code Common Workflows](https://code.claude.com/docs/en/common-workflows), [Best Practices](https://code.claude.com/docs/en/best-practices), [GitHub Actions](https://code.claude.com/docs/en/github-actions), [Agent Teams](https://code.claude.com/docs/en/agent-teams)

#### Branch Isolation

- **`--worktree` (`-w`) flag** creates an isolated worktree at `<repo>/.claude/worktrees/<name>` with a branch named `worktree-<name>`, branching from the default remote branch.
- If no name is given, Claude auto-generates one (e.g., `bright-running-fox`).
- Worktrees are auto-cleaned: if no changes were made, the worktree and branch are removed on exit. If changes exist, the user is prompted to keep or remove.
- `.claude/worktrees/` should be added to `.gitignore`.

#### Subagent Worktrees

- Subagents can get their own worktrees via `isolation: worktree` in agent frontmatter.
- Each subagent worktree is auto-cleaned when the subagent finishes without changes.

#### Agent Teams

- Experimental feature: one "team lead" session coordinates multiple "teammate" sessions.
- Shared task list with self-coordination, direct inter-agent messaging.
- Each teammate has its own context window.
- Key constraint: **avoid file conflicts** — break work so each teammate owns different files.
- Task states: pending, in progress, completed. Tasks can have dependencies.
- Quality gates via hooks: `TeammateIdle` and `TaskCompleted` can block or send feedback.

#### Commit Discipline

- Anthropic recommends committing early and often with descriptive messages.
- The four-phase workflow: Explore -> Plan -> Implement -> Commit.
- Claude can `commit with a descriptive message and open a PR` as a single natural-language request.

#### PR Creation

- `gh pr create` is the recommended mechanism.
- Sessions are **automatically linked to PRs** when created — resumable via `claude --from-pr <number>`.
- GitHub Actions integration: `@claude` mention in any PR/issue triggers analysis, code changes, or PR creation.
- Claude Code Action (v1) runs in GitHub Actions with configurable sandbox permissions.

#### Context Between Sessions

- Sessions persist locally with full message history, tool state, and context restoration.
- Named sessions (`-n auth-refactor` or `/rename`) for findability.
- Session picker with branch filtering, preview, and search.
- `/resume` picker shows sessions from the same git repo, including worktrees.

---

### 1.2 OpenAI — Codex

**Sources:** [Codex Workflows](https://developers.openai.com/codex/workflows), [Codex GitHub Action](https://developers.openai.com/codex/github-action), [Codex Cloud](https://developers.openai.com/codex/cloud)

#### Branch Isolation

- Codex runs tasks in **cloud sandboxed environments** with full development stacks.
- Each task gets its own environment; parallel tasks run in separate sandboxes.
- No public documentation on specific branch naming conventions.

#### Commit Discipline

- Minimal public detail. Documentation emphasizes keeping current work committed or stashed before delegating to the cloud.

#### PR Creation & Review

- Codex can create PRs directly from cloud tasks or pull changes locally.
- `@codex` tagging on PRs and issues triggers agent work.
- **Review against a base branch**: Codex finds the merge base, diffs work, highlights risks.

#### GitHub Action Integration

- `openai/codex-action@v1` runs Codex in CI pipelines.
- Sandbox levels: `workspace-write`, `read-only`, `danger-full-access`.
- Safety strategies: `drop-sudo` (default), `unprivileged-user`, `unsafe`.
- The action creates a shallow clone, ensures base/head refs for PRs are available locally.

#### Parallel Work

- Codex handles tasks in the background "including in parallel."
- IDE delegation: kick off cloud tasks from editor, monitor progress, apply resulting diffs locally.

---

### 1.3 GitHub — Copilot Coding Agent

**Sources:** [About Coding Agent](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent), [Coding Agent 101](https://github.blog/ai-and-ml/github-copilot/github-copilot-coding-agent-101-getting-started-with-agentic-workflows-on-github/), [From Idea to PR](https://github.blog/ai-and-ml/github-copilot/from-idea-to-pr-a-guide-to-github-copilots-agentic-workflows/)

#### Branch Isolation

- **Enforced `copilot/` branch prefix.** The agent can only create and push to branches beginning with `copilot/`.
- Cannot modify main or master branches directly.
- This is a hard security constraint, not a convention.

#### Commit Discipline

- Commits are **co-authored** by the developer who assigned the work.
- Agent automates branch creation, commit message writing, pushing, PR opening, and PR description writing.

#### PR Creation & Review

- Agent opens a **draft PR** tagged `[WIP]` and pushes commits as it works.
- Logs key steps for real-time progress tracking.
- **Draft PRs must be reviewed and merged by a human.** Agent cannot mark PRs as "Ready for review" or merge.
- The developer who assigned cannot approve their own agent-created PR (enforces independent review).
- GitHub Actions workflows are blocked for agent PRs until a developer clicks "Approve and run workflows."

#### Issue-to-PR Lifecycle (Complete State Machine)

1. Issue created (optionally via Copilot at github.com/copilot)
2. Issue assigned to `@github`
3. `copilot-setup-steps.yml` configures development environment
4. Agent reviews task, explores codebase, forms plan
5. Agent implements changes, runs lint/test per custom instructions
6. Agent opens draft PR with clear title and description
7. Human reviews body, code changes, and optionally runs in Codespace
8. If feedback needed: reviewer comments tagging `@copilot`, agent iterates
9. If approved: human merges

#### Parallel Tasks

- **Only one PR at a time** per assigned task.
- Cannot make changes across multiple repositories in one run.

#### Security

- Sandboxed environment powered by GitHub Actions with firewall-controlled internet access.
- Read-only repository access inside the sandbox.
- Pre-PR validation: CodeQL, GitHub Advisory Database scanning, secret detection.

---

### 1.4 GitHub — Agentic Workflows (gh-aw)

**Sources:** [GitHub Blog: Agentic Workflows](https://github.blog/ai-and-ml/automate-repository-tasks-with-github-agentic-workflows/), [gh-aw Docs](https://github.github.com/gh-aw/)

#### Architecture

- Workflows authored as **Markdown with YAML frontmatter**, compiled via `gh aw compile` into GitHub Actions YAML + lockfile.
- Supports pluggable agent engines: Copilot CLI, Claude Code, OpenAI Codex.

#### Deterministic vs. Stochastic Separation

This is the most architecturally significant design in the research:

- **Deterministic layer:** Traditional GitHub Actions YAML handles CI/CD (builds, tests, deployments). Unchanged.
- **Stochastic layer:** Agentic workflows handle subjective/repetitive tasks: issue triage, documentation, test improvement, code simplification, CI failure investigation.
- Explicit guidance: **"Do not use agentic workflows as a replacement for GitHub Actions YAML workflows for CI/CD."**

#### Git Operations Model

- **Read-only default posture.** Write operations require explicit approval through "safe outputs."
- Safe outputs map to pre-approved GitHub primitives: creating PRs, adding issue comments, creating issues.
- **PRs are never merged automatically.** Human review mandatory.

#### Use Case Categories

Six automation patterns: Continuous Triage, Continuous Documentation, Continuous Simplification, Continuous Testing, Continuous Quality, Continuous Reporting.

---

### 1.5 Cursor

**Sources:** [Cursor Git Docs](https://cursor.com/help/integrations/git), [Git Integration Guide](https://docs.cursor.com/en/integrations/git)

#### Git Integration

- AI-powered **commit message generation** from staged changes (sparkle icon).
- Adapts to existing commit conventions (e.g., Conventional Commits).
- **Merge conflict resolution**: Agent understands both sides and proposes resolution.
- `@git` in-chat code review assistance.

#### Parallel Agents

- Cursor supports up to **8 concurrent AI coding agents**, each with independent workspaces via git worktrees or remote machines.
- Wave 13 (Windsurf, formerly Codeium) brought first-class git worktree support.

#### Distinctive Feature

- MCP Git integration for enforcing git conventions programmatically.

---

### 1.6 Ramp — Inspect

**Sources:** [Why We Built Our Own Background Agent](https://builders.ramp.com/post/why-we-built-our-background-agent), [InfoQ Coverage](https://www.infoq.com/news/2026/01/ramp-coding-agent-platform/), [Modal Blog](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)

#### Architecture

- Each session runs in a **Modal sandbox VM** containing full-stack dev environment: Postgres, Redis, Temporal, RabbitMQ, VS Code server, VNC + Chromium.
- Repository images rebuilt every 30 minutes via cron; sessions start from snapshots.
- Sessions start "in a few seconds" with at-most-30-minute-old snapshots.

#### Git Workflow

- Sandbox pushes changes to a **feature branch**, then signals the API with branch name and session ID.
- **PR attribution**: API uses the authenticated user's GitHub OAuth token to create PRs "on behalf of the user" (not the agent app). This prevents self-approval vulnerabilities.
- Dynamic git config: agent updates `user.name` and `user.email` per session rather than using a fixed identity.
- Fresh GitHub app installation tokens generated per clone.

#### Parallel Execution

- "Effectively free to run" on Modal infrastructure — no need to ration local checkouts or worktrees.
- Hundreds of concurrent sessions without interference.
- State managed via Cloudflare Durable Objects (conversation context + dev session state).

#### Adoption

- ~30% of merged PRs across frontend and backend repos, achieved through organic adoption (not mandated).

#### Multiplayer Support

- Multiple team members can work in one session with individual attribution per change.
- Enables live QA and peer review without creating tickets.

---

### 1.7 Cognition — Devin

**Sources:** [How Cognition Uses Devin](https://cognition.ai/blog/how-cognition-uses-devin-to-build-devin), [Devin 2025 Performance Review](https://cognition.ai/blog/devin-annual-performance-review-2025), [Devin Docs](https://docs.devin.ai)

#### Git Workflow

- Native branch creation, commits, and PR opening.
- PRs look like any other PR on GitHub — standard review workflow.
- Can respond to review comments and push fixes while session is active.
- Custom PR template support: `.github/PULL_REQUEST_TEMPLATE/devin_pr_template.md`.

#### Best Practices

- Enable branch protection rules on main branches so Devin PRs must pass CI before merging.
- Standard protections: required reviews, status checks, branch protections remain in place.

#### Performance

- PR merge rate improved from **34% to 67%** over 2025.
- Cognition merged **659 Devin PRs in one week** internally (up from 154 in best week of 2025).

#### Interaction Model

- Work originates from Slack mentions, Linear/Jira tickets, web app, or Chrome extension.
- Default branch for repository indexing is configurable per repo.

---

### 1.8 incident.io

**Source:** [Shipping Faster with Claude Code and Git Worktrees](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees)

#### Workflow

- Run **4-5 Claude agents simultaneously**, each in isolated worktrees.
- Custom bash function `w` abstracts worktree management:
  - `w myproject new-feature` — create and enter worktree
  - `w myproject new-feature claude` — create worktree and launch Claude
- Worktrees stored at `~/projects/worktrees/`.
- Username-based branch prefix for organization.

#### Key Practices

- Plan Mode first for safe parallelization.
- Voice-driven development (SuperWhisper) for brain-dump context.
- Agent commits and pushes when requested.
- Treat AI coding sessions as "long-running processes with ongoing, focused dialogues."

#### Scale

- Went from zero Claude Code usage to daily multi-agent workflow in ~4 months.
- Gamified adoption with office leaderboard tracking token usage.

---

### 1.9 QuantumBlack (McKinsey) — Agentic Workflows

**Source:** [Agentic Workflows for Software Development](https://medium.com/quantumblack/agentic-workflows-for-software-development-dc8e64f4a79d)

This is the most architecturally rigorous approach found in the research.

#### Git as State Store

- **Git is the state store.** The branch represents the feature workflow; commits represent completed phases.
- The workflow engine handles ALL deterministic Git operations (clone/branch/commit/push/open PR), keeping them **out of the agent's scope**.
- Agents produce artifacts; the engine moves them through the repo.

#### Branch Lifecycle

- Feature branch naming: `agent/REQ-001-notification-system`.
- Single branch spans the entire development cycle.
- Each completed phase commits to the branch.
- PR opened only after all phases pass evaluation gates.

#### Commit Practices

- Semantic commits tied to artifacts:
  - `feat(REQ-001): add notification system requirement`
  - `feat(REQ-001): add architecture for notification system`
  - `feat(REQ-001): add technical tasks for notification system`

#### Deterministic vs. Stochastic Separation

- **Orchestration layer (deterministic):** Phase sequencing, dependency management, state machine tracking (draft -> in-review -> approved -> complete), task readiness, triggering agents with bounded inputs.
- **Execution layer (stochastic):** Requirements analysis, architecture proposals, code generation, documentation.
- Critical insight: **"Agents cannot decide what comes next."** The engine enforces this boundary programmatically.

#### Evaluation Gates (Two-Layer)

- **Layer 1 — Deterministic:** Linters, formatters, required frontmatter, section structure, cross-reference resolution, test suite, coverage thresholds.
- **Layer 2 — Critic agent:** Testability of acceptance criteria, architectural pattern compliance, security considerations, spec adherence.
- If either layer rejects: producing agent iterates (capped at 3-5 attempts).

#### Repository Structure

```
.sdlc/
  context/              # Applies to all features (persistent)
  specs/                # Per-feature specifications
    REQ-001-notification-system/
      requirement.md
      tasks/
        TASK-001-*.md
  knowledge/            # Accumulated answers
  templates/
```

#### Complete Lifecycle

1. Workflow engine creates feature branch
2. Requirements agent analyzes input, produces structured requirement
3. Deterministic checks + critic agent evaluate
4. Architecture agent reads requirement + existing docs, queries knowledge agent
5. Deterministic checks + critic agent evaluate
6. Task agent generates technical tasks with dependency graphs
7. Deterministic checks + critic agent evaluate
8. Implementation agent writes code per task, runs lint/test/coverage
9. Engine pushes branch, opens PR showing complete feature
10. Human team reviews integrated feature once

#### Knowledge Management

- Dedicated knowledge agent handles context retrieval for all other agents.
- Assumptions are logged and appear as reviewable items in PR diff.
- Reviewer approvals feed decisions back into knowledge base.

---

### 1.10 GitHub — Spec-Driven Development (spec-kit)

**Source:** [Spec-Driven Development with AI](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)

#### Four-Phase Lifecycle

1. **Specify**: Capture user journeys, problem statements, success criteria
2. **Plan**: Technology stack, architectural patterns, integration points, constraints
3. **Tasks**: Decompose into discrete, testable work units
4. **Implement**: Agent executes tasks with specification as reference

#### Tooling

- Open-source `spec-kit`: `uvx --from git+https://github.com/github/spec-kit.git specify init <PROJECT_NAME>`
- Commands: `/specify`, `/plan`, `/tasks`
- Generates Markdown-based specs as source of truth.
- Compatible with GitHub Copilot, Claude Code, Gemini CLI.

---

### 1.11 AWS — AI-DLC (AI-Driven Development Lifecycle)

**Source:** [AWS DevOps Blog](https://aws.amazon.com/blogs/devops/open-sourcing-adaptive-workflows-for-ai-driven-development-life-cycle-ai-dlc/)

#### Adaptive Workflow

- Nine stages; AI recommends which stages apply to specific situations.
- Simple bug fixes skip functional design and architecture.
- New features focus on integration and testing.
- New projects go through all nine stages.

#### Implementation

- Open-source at `github.com/awslabs/aidlc-workflows`.
- Codified into "steering rules" — structured instructions guiding AI coding tools.
- Uses Kiro Steering Files within the project workspace.

---

### 1.12 Community Tools for Parallel Agent Management

**Sources:** [Claude Squad](https://github.com/smtg-ai/claude-squad), [workmux](https://github.com/raine/workmux), [agentdock](https://github.com/vishalnarkhede/agentdock), [dmux](https://dmux.ai/)

| Tool | Architecture | Isolation Method |
|------|-------------|-----------------|
| **Claude Squad** | TUI managing multiple agents | tmux sessions + git worktrees |
| **workmux** | git worktrees + tmux windows | Worktrees as isolated dev environments |
| **agentdock** | Web dashboard | tmux sessions + git worktrees across repos |
| **dmux** | tmux pane manager | Automatic branch management per pane |

All converge on the same pattern: **tmux for terminal isolation + git worktrees for filesystem isolation**.

---

## 2. Common Patterns

These patterns appear across 3+ independent implementations:

### 2.1 Git Worktrees as the Universal Isolation Primitive

**Consensus level: Very strong.** Every major tool now supports or recommends worktrees.

- Claude Code: `--worktree` flag, subagent `isolation: worktree`
- Cursor/Windsurf: Up to 8 concurrent agents via worktrees
- incident.io: 4-5 parallel agents in worktrees
- Community tools (Claude Squad, workmux, agentdock, dmux): All use worktrees
- SWE-AF: Dependency-level scheduling with isolated worktrees

**Why:** Worktrees share `.git` history (no duplication), provide true filesystem isolation, and map naturally to branches. Context switching without worktrees confuses agents' understanding of codebase state.

### 2.2 Agent-Prefixed Branch Naming

**Consensus level: Strong.** Most teams use an agent-identifiable prefix.

| Team | Branch Pattern |
|------|---------------|
| GitHub Copilot | `copilot/<task-description>` (enforced) |
| Claude Code | `worktree-<name>` (auto-generated) |
| Vercel v0 | `feature/<description>-<6char-hash>` |
| QuantumBlack | `agent/REQ-001-<description>` |
| Claude Code Action | `claude/<feature>-<session-id>` |

**Why:** Agent-prefixed branches enable programmatic identification, prevent conflicts with human branches, and support branch protection rules that differentiate agent work from human work.

### 2.3 Draft PRs with Mandatory Human Review

**Consensus level: Very strong.** No team auto-merges agent PRs.

- GitHub Copilot: Draft PRs only, cannot mark "Ready for review" or merge
- Ramp: PRs created via user's OAuth token (prevents self-approval)
- Devin: Standard PRs with branch protection rules
- QuantumBlack: PR opened only after all evaluation gates pass
- GitHub Agentic Workflows: "PRs are never merged automatically"

**Why:** Agent-generated code needs human review for correctness, security, and architectural fit. Auto-merge would create liability and trust issues.

### 2.4 Deterministic/Stochastic Separation

**Consensus level: Strong.** The best-architected systems enforce this explicitly.

- QuantumBlack: Orchestration engine (deterministic) vs. execution agents (stochastic). "Agents cannot decide what comes next."
- GitHub Agentic Workflows: CI/CD (deterministic YAML) vs. agentic workflows (stochastic Markdown). "Do not use agentic workflows as a replacement for CI/CD."
- GitHub Blog (multi-agent reliability): "Treat agents like code, not chat interfaces." Typed schemas, action schemas, MCP enforcement.
- Our scaffold: Hook -> script -> slash command -> pure reasoning hierarchy.

**Why:** LLMs introduce non-determinism. Every deterministic operation performed by an LLM is a reliability risk and a context waste. The best systems push all computable operations to scripts/hooks and reserve LLM reasoning for genuinely semantic tasks.

### 2.5 Spec-Driven Development

**Consensus level: Strong and growing.** Multiple independent implementations converged on this pattern.

- GitHub: spec-kit (open-source `/specify`, `/plan`, `/tasks`)
- QuantumBlack: `.sdlc/specs/REQ-*/` with structured requirements, architecture, tasks
- AWS: AI-DLC with adaptive stage selection
- Our scaffold: `docs/spec.md` -> `docs/plan.md` -> TDD -> `docs/checkpoint.md`

**Why:** "Language models are exceptional at pattern completion, but not at mind reading." Specs eliminate guesswork by providing explicit, reviewable context. Multiple teams independently discovered that structured specs dramatically improve agent output quality.

### 2.6 Sandboxed Execution Environments

**Consensus level: Strong.** All cloud-hosted agent solutions use sandboxing.

- GitHub Copilot: GitHub Actions runner with firewall, read-only repo access
- Ramp: Modal VMs with full dev stack per session
- OpenAI Codex: Cloud environments with configurable sandbox levels
- Vercel: Vercel Sandbox with repo-aware runtime

**Why:** Agents need to run tests, lint, and validate their work. Sandboxing prevents uncontrolled system access while enabling verification loops.

### 2.7 Co-Authored Commits for Attribution

**Consensus level: Moderate.** Approaches vary but all address attribution.

- GitHub Copilot: Commits co-authored by the assigning developer
- Ramp: Dynamic `user.name` and `user.email` per session, PRs via user's OAuth token
- Our scaffold: `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>`

**Why:** Traceability matters for audit, blame, and understanding who validated what. Co-authored commits preserve both the human responsible and the AI that generated the code.

---

## 3. Divergent Approaches

### 3.1 Parallel Task Capacity

| Approach | Team | Tradeoff |
|----------|------|----------|
| **Single task at a time** | GitHub Copilot | Maximum safety, minimum throughput |
| **4-5 parallel agents** | incident.io | Practical sweet spot for single developer |
| **Up to 8 agents** | Cursor/Windsurf | Aggressive parallelism, requires monitoring |
| **Hundreds of concurrent sessions** | Ramp (Modal VMs) | Cloud-native, unlimited by local resources |
| **Agent teams (experimental)** | Claude Code | Coordinated parallel work with shared task list |

**Tradeoff:** More parallelism = higher throughput but more coordination overhead, more token cost, and higher risk of conflicts. The sweet spot depends on whether agents work on truly independent tasks (safe to parallelize) or overlapping files (dangerous).

### 3.2 Where the Agent Runs

| Approach | Teams | Tradeoff |
|----------|-------|----------|
| **Local machine** | Claude Code CLI, Cursor, incident.io | Full environment access, limited parallelism by machine resources |
| **Cloud sandbox per task** | GitHub Copilot, Ramp, OpenAI Codex, Vercel | Unlimited parallelism, requires environment setup/snapshot infrastructure |
| **Hybrid** | Claude Code (local + cloud web) | Flexibility, complexity |

**Tradeoff:** Local execution gives agents access to the developer's actual environment (databases, services, credentials), but limits parallelism. Cloud sandboxes scale infinitely but require environment replication.

### 3.3 Workflow Orchestration

| Approach | Teams | Tradeoff |
|----------|-------|----------|
| **Human orchestrates agents** | Claude Code, Cursor, incident.io | Maximum control, human is the bottleneck |
| **Engine orchestrates agents** | QuantumBlack, GitHub Agentic Workflows | Deterministic phase transitions, less flexible |
| **Agent orchestrates agents** | Claude Code Agent Teams, Devin | Flexible but unreliable without constraints |

**Tradeoff:** The QuantumBlack approach (engine orchestrates, agents execute within bounded phases) is the most reliable but requires more upfront infrastructure. Human orchestration is simplest but doesn't scale. Agent-orchestrating-agent is the most flexible but least predictable.

### 3.4 Commit Granularity

| Approach | Teams | Tradeoff |
|----------|-------|----------|
| **Commit per completed phase** | QuantumBlack | Clean, auditable history but large commits |
| **Commit as you go** | incident.io, Claude Code best practices | Granular history, easy to revert, noisier |
| **Squash on merge** | Common in PR-based workflows | Clean main history, lost intermediate context |

### 3.5 Issue-to-PR Lifecycle Formality

| Approach | Teams | Tradeoff |
|----------|-------|----------|
| **Formal state machine** | QuantumBlack (9 phases with gates), GitHub Copilot (6-step lifecycle) | Predictable, auditable, slower for small tasks |
| **Adaptive stages** | AWS AI-DLC (skips stages based on task type) | Flexible, but adds complexity in stage selection |
| **Informal** | Devin, Ramp | Fast, but less structured review process |
| **Spec-first with templates** | Our scaffold, GitHub spec-kit | Structured but lightweight |

---

## 4. Recommendations for Our Scaffold

Based on the evidence, here are recommendations organized by implementation priority.

### 4.1 HIGH PRIORITY — Adopt Now

#### A. Git Worktree Support

**Evidence:** Universal consensus. Every major tool supports this. incident.io proved the workflow in production.

**Recommendation:**
- Add a `/worktree` command that wraps `git worktree add` with scaffold-aware setup.
- Convention: worktrees at `<repo>/.claude/worktrees/<name>` (matches Claude Code's own pattern).
- Branch naming: `worktree-<name>` (matches Claude Code default) or configurable prefix.
- Add `.claude/worktrees/` to `.gitignore` template.
- Worktree-specific CLAUDE.md / rules should inherit from root.

#### B. `/commit` Command

**Evidence:** Multiple teams emphasize commit-as-you-go with descriptive messages. The scaffold already has conventional commit conventions in CLAUDE.md.

**Recommendation:**
- Create `/commit` command that: stages relevant files, generates conventional commit message from diff context, includes `Co-Authored-By` trailer, runs pre-commit validation.
- Support `--scope` and `--type` flags for explicit conventional commit control.
- Integrate with `docs-check.sh` to validate spec/plan alignment before committing.

#### C. `/pr` Command

**Evidence:** GitHub Copilot, Claude Code, and Ramp all demonstrate PR automation. Claude Code already links sessions to PRs.

**Recommendation:**
- Create `/pr` command that: creates branch if needed, pushes, creates PR with structured description (Summary, Test Plan, Generated by Claude), links to spec/plan if they exist.
- PR title from spec feature_id or first line of plan.
- Include test results summary in PR body.

### 4.2 MEDIUM PRIORITY — Plan and Build

#### D. Agent-Prefixed Branch Naming Convention

**Evidence:** GitHub Copilot enforces `copilot/` prefix. QuantumBlack uses `agent/REQ-001-`. Vercel uses AI-generated names with hash suffixes.

**Recommendation:**
- Default branch naming: `claude/<type>/<description>` (e.g., `claude/feat/notification-system`).
- Document in CLAUDE.md as repository etiquette.
- Hook to validate branch names on push (optional, in settings.json).

#### E. Evaluation Gates Before PR

**Evidence:** QuantumBlack's two-layer evaluation (deterministic checks + critic agent) is the gold standard.

**Recommendation:**
- Before `/pr`, automatically run: syntax checks, test suite, spec alignment check via `docs-check.sh validate`.
- If any deterministic check fails, block PR creation with specific failure output.
- Optional: critic review via subagent before PR (matches our `/review` command flow).

#### F. Parallel Session Orchestration Documentation

**Evidence:** incident.io's `w` function, Claude Code's `--worktree`, and Claude Squad all prove the workflow.

**Recommendation:**
- Add a section to GUIDE.md documenting the parallel agent workflow.
- Include the `--worktree` flag usage pattern.
- Document how scaffold sync works across worktrees (worktrees share `.git` so lockfile state is shared).
- Warn about resource conflicts (ports, databases) across parallel sessions.

### 4.3 LOWER PRIORITY — Research and Evaluate

#### G. Workflow Engine Separation (QuantumBlack Pattern)

**Evidence:** QuantumBlack's orchestration/execution separation is the most architecturally sound approach. "Agents cannot decide what comes next."

**Recommendation:**
- Our scaffold already partially implements this: `docs-check.sh recommend` provides deterministic "next action" recommendations, and hooks enforce binary rules.
- Evaluate building a lightweight state machine script that tracks feature lifecycle: `spec -> plan -> implement -> review -> pr -> merged`.
- This aligns with our existing `docs-check.sh status/validate/recommend` pipeline.

#### H. GitHub Agentic Workflows Integration

**Evidence:** gh-aw enables Markdown-authored automation compiled to GitHub Actions. Supports Claude Code as an engine.

**Recommendation:**
- Monitor gh-aw as it exits technical preview.
- Our scaffold's slash commands could potentially compile to agentic workflows for CI automation (e.g., continuous documentation updates, issue triage).

#### I. Knowledge Agent Pattern

**Evidence:** QuantumBlack's dedicated knowledge agent that handles context retrieval and logs assumptions as reviewable PR items.

**Recommendation:**
- Our scaffold's `docs/` directory (spec, plan, checkpoint) already serves as a knowledge base.
- Consider adding an `assumptions.md` file that agents write to when making decisions without explicit guidance.
- These assumptions would surface in PR review.

---

## Summary Matrix

| Capability | Claude Code | Copilot Agent | Codex | Ramp | Devin | QuantumBlack | Our Scaffold |
|---|---|---|---|---|---|---|---|
| **Worktree isolation** | Native `--worktree` | N/A (cloud) | N/A (cloud) | N/A (cloud VMs) | N/A | N/A | Not yet |
| **Branch naming** | `worktree-<name>` | `copilot/*` (enforced) | Not documented | Feature branches | Not documented | `agent/REQ-*` | Not yet |
| **Draft PRs** | Via `gh` | Auto-draft, human merge | Via cloud | Via user OAuth | Standard PRs | Engine creates | Not yet |
| **Parallel agents** | Teams + worktrees | 1 at a time | Cloud parallel | Hundreds (Modal) | 1 at a time | Engine-scheduled | Not yet |
| **Spec-driven** | Skills/prompts | copilot-instructions.md | AGENTS.md | Internal | Not documented | `.sdlc/specs/` | docs/spec.md |
| **Deterministic separation** | Hooks + skills | CI pipeline | Sandbox levels | Internal tooling | CI checks | Engine vs. agent | Hooks + scripts |
| **Commit attribution** | Co-authored | Co-authored | Not documented | Dynamic git config | Not documented | Semantic per phase | Co-authored |
| **Session persistence** | Local sessions | PR-linked | Cloud state | Durable Objects | Session-based | Branch state | Checkpoint files |
| **Evaluation gates** | Hooks | CodeQL + CI | Sandbox checks | Test + monitoring | CI checks | 2-layer (deterministic + critic) | docs-check.sh |

---

## Sources

### Anthropic / Claude Code
- [Common Workflows](https://code.claude.com/docs/en/common-workflows)
- [Best Practices](https://code.claude.com/docs/en/best-practices)
- [GitHub Actions](https://code.claude.com/docs/en/github-actions)
- [Agent Teams](https://code.claude.com/docs/en/agent-teams)

### OpenAI / Codex
- [Codex Workflows](https://developers.openai.com/codex/workflows)
- [Codex GitHub Action](https://developers.openai.com/codex/github-action)
- [Codex Cloud](https://developers.openai.com/codex/cloud)
- [Introducing Codex](https://openai.com/index/introducing-codex/)

### GitHub
- [About Copilot Coding Agent](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent)
- [Coding Agent 101](https://github.blog/ai-and-ml/github-copilot/github-copilot-coding-agent-101-getting-started-with-agentic-workflows-on-github/)
- [From Idea to PR](https://github.blog/ai-and-ml/github-copilot/from-idea-to-pr-a-guide-to-github-copilots-agentic-workflows/)
- [Automate with Agentic Workflows](https://github.blog/ai-and-ml/automate-repository-tasks-with-github-agentic-workflows/)
- [Multi-Agent Workflows Often Fail](https://github.blog/ai-and-ml/generative-ai/multi-agent-workflows-often-fail-heres-how-to-engineer-ones-that-dont/)
- [Spec-Driven Development with spec-kit](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)

### Cursor / Windsurf
- [Cursor Git Docs](https://cursor.com/help/integrations/git)
- [Windsurf Wave 13](https://www.testingcatalog.com/windsurf-wave-13-brings-free-swe-1-5-and-new-upgrades/)

### Ramp
- [Why We Built Our Own Background Agent](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [InfoQ: Ramp Coding Agent](https://www.infoq.com/news/2026/01/ramp-coding-agent-platform/)
- [Modal Blog: How Ramp Built Inspect](https://modal.com/blog/how-ramp-built-a-full-context-background-coding-agent-on-modal)

### Cognition / Devin
- [How Cognition Uses Devin](https://cognition.ai/blog/how-cognition-uses-devin-to-build-devin)
- [Devin 2025 Performance Review](https://cognition.ai/blog/devin-annual-performance-review-2025)

### incident.io
- [Shipping Faster with Claude Code and Git Worktrees](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees)

### QuantumBlack (McKinsey)
- [Agentic Workflows for Software Development](https://medium.com/quantumblack/agentic-workflows-for-software-development-dc8e64f4a79d)

### AWS
- [Open-Sourcing AI-DLC](https://aws.amazon.com/blogs/devops/open-sourcing-adaptive-workflows-for-ai-driven-development-life-cycle-ai-dlc/)

### Community / Other
- [Using Git Worktrees with AI Agents](https://www.nrmitchi.com/2025/10/using-git-worktrees-for-multi-feature-development-with-ai-agents/)
- [Claude Squad](https://github.com/smtg-ai/claude-squad)
- [Thoughtworks: Spec-Driven Development](https://www.thoughtworks.com/en-us/insights/blog/agile-engineering-practices/spec-driven-development-unpacking-2025-new-engineering-practices)
- [Martin Fowler: SDD Tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
- [SFEIR: Git Integration Best Practices](https://institute.sfeir.com/en/claude-code/claude-code-git-integration/best-practices/)
