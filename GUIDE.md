# Claude Code Scaffold — Complete Guide

A visual, browsable guide to the scaffold system: how it works, when to use each feature, and the reasoning behind every design decision.

> **Why this scaffold exists:** Transformer attention is zero-sum. Every token in Claude's ~200K context window competes for attention weight. Performance degrades as context fills — starting at just 3,000 tokens. This scaffold manages that constraint through specification-driven development, test-driven verification, and hierarchical context management. Every feature described below traces back to this architectural reality.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Getting Started](#getting-started)
3. [The Core Workflow: Spec → Plan → Build → Review](#the-core-workflow)
4. [Session Management](#session-management)
5. [Scaffold Sync System](#scaffold-sync-system)
6. [Command Reference](#command-reference)
7. [Configuration Layers](#configuration-layers)
8. [Hooks System](#hooks-system)
9. [Decision Guide: When To Use What](#decision-guide)

---

## System Overview

The scaffold is a layered configuration system. Each layer loads at a different time and serves a different purpose.

```mermaid
graph TB
    subgraph "Always Loaded at Launch"
        GM["~/.claude/CLAUDE.md<br/><i>Personal preferences</i>"]
        PM["./CLAUDE.md<br/><i>Project identity & conventions</i>"]
        R1[".claude/rules/*.md<br/><i>TDD, workflow, code quality, TLS</i>"]
        S[".claude/settings.json<br/><i>Permissions & hooks</i>"]
        CI[".claudeignore<br/><i>File exclusions</i>"]
    end

    subgraph "Loaded On-Demand"
        SK[".claude/skills/tdd/SKILL.md<br/><i>TDD enforcement</i>"]
        AG1[".claude/agents/spec-writer.md"]
        AG2[".claude/agents/code-reviewer.md"]
        AG3[".claude/agents/scaffold-differ.md"]
        CMD[".claude/commands/*.md<br/><i>Slash commands</i>"]
    end

    subgraph "Working Documents"
        SP["docs/spec.md<br/><i>Active specification</i>"]
        PL["docs/plan.md<br/><i>Active plan</i>"]
        CP["docs/checkpoint.md<br/><i>Session state</i>"]
    end

    subgraph "Persistent Templates"
        T1["docs/templates/spec.md"]
        T2["docs/templates/plan.md"]
        T3["docs/templates/checkpoint.md"]
    end

    subgraph "Reference Documents (synced)"
        GUIDE["GUIDE.md<br/><i>hub + node sections</i>"]
        FRAMEWORK["SCAFFOLD_FRAMEWORK.md<br/><i>research — read-only</i>"]
    end

    GM --> PM
    PM --> R1
    R1 --> S

    SK -.->|"triggers on 'tdd',<br/>'test first'"| PM
    AG1 -.->|"triggers on<br/>'spec this'"| PM
    CMD -.->|"triggers on<br/>/command"| PM

    T1 -.->|"format guide"| SP
    T2 -.->|"format guide"| PL
    T3 -.->|"format guide"| CP

    style GM fill:#e8f4e8
    style PM fill:#e8f4e8
    style R1 fill:#e8f4e8
    style S fill:#e8f4e8
    style CI fill:#e8f4e8
    style SK fill:#fff3e0
    style AG1 fill:#fff3e0
    style AG2 fill:#fff3e0
    style AG3 fill:#fff3e0
    style CMD fill:#fff3e0
    style SP fill:#e3f2fd
    style PL fill:#e3f2fd
    style CP fill:#e3f2fd
    style T1 fill:#f3e5f5
    style T2 fill:#f3e5f5
    style T3 fill:#f3e5f5
    style GUIDE fill:#fff3e0
    style FRAMEWORK fill:#e0e0e0
```

**Why this layering matters:** Claude has ~150-200 effective instruction slots. The always-loaded layer (CLAUDE.md + rules) should stay under that budget. Everything else loads on-demand to avoid diluting attention. The `.claudeignore` file is the single biggest lever — file reads consume 80% of context.

---

## Getting Started

### First-time setup (once per machine)

```mermaid
flowchart LR
    A["Copy GLOBAL_CLAUDE.md<br/>→ ~/.claude/CLAUDE.md"] --> B["Copy global-commands/init.md<br/>→ ~/.claude/commands/init.md"]
    B --> C["Edit ~/.claude/CLAUDE.md<br/>with your preferences"]
    C --> D["Done — works for<br/>all future projects"]

    style A fill:#e8f4e8
    style B fill:#e8f4e8
    style C fill:#fff3e0
    style D fill:#e3f2fd
```

### Starting a new project

```mermaid
flowchart TD
    A["mkdir ~/projects/my-project<br/>cd ~/projects/my-project<br/>claude"] --> B["/init"]
    B --> C["Claude reads scaffold README<br/>and SCAFFOLD_SYSTEM_PROMPT.md"]
    C --> D["Copies all scaffold files<br/>to current directory"]
    D --> E["Asks for project name<br/>and one-line description"]
    E --> F["Replaces placeholders<br/>in CLAUDE.md"]
    F --> G["Generates .claude/scaffold.lock<br/><i>tracks sync state</i>"]
    G --> H["git init && git add -A<br/>&& git commit"]
    H --> I["Ready to build"]

    style B fill:#e8f4e8,stroke:#333,stroke-width:2px
    style G fill:#f3e5f5
    style I fill:#e3f2fd,stroke:#333,stroke-width:2px
```

---

## The Core Workflow

Every feature follows this sequence. No exceptions.

```mermaid
flowchart TD
    DESC["1. DESCRIBE<br/><i>'I want the app to do X'</i>"]
    SPEC["2. SPEC<br/><i>spec-writer agent creates docs/spec.md<br/>with acceptance criteria</i>"]
    REV_SPEC{"Review spec?"}
    ADJ["Adjust criteria<br/><i>'Add a criterion for...'</i>"]
    PLAN["3. PLAN<br/><i>/plan creates docs/plan.md<br/>ordered TDD steps</i>"]
    REV_PLAN{"Review plan?"}
    BUILD["4. BUILD<br/><i>TDD cycles for each step</i>"]
    TDD_CYCLE["Red → Green → Refactor → Commit"]
    MORE{"More steps<br/>in plan?"}
    REVIEW["5. REVIEW<br/><i>/review spawns code-reviewer agent</i>"]
    REV_FB{"Issues found?"}
    FIX["Fix issues"]
    DONE["6. DONE<br/><i>/clear for next feature</i>"]

    DESC --> SPEC
    SPEC --> REV_SPEC
    REV_SPEC -->|"Looks good"| PLAN
    REV_SPEC -->|"Needs changes"| ADJ
    ADJ --> SPEC
    PLAN --> REV_PLAN
    REV_PLAN -->|"Looks good"| BUILD
    REV_PLAN -->|"Needs changes"| PLAN
    BUILD --> TDD_CYCLE
    TDD_CYCLE --> MORE
    MORE -->|"Yes"| BUILD
    MORE -->|"No"| REVIEW
    REVIEW --> REV_FB
    REV_FB -->|"PASS"| DONE
    REV_FB -->|"CONCERNS"| FIX
    FIX --> REVIEW

    style DESC fill:#e3f2fd,stroke:#333,stroke-width:2px
    style SPEC fill:#e8f4e8
    style PLAN fill:#e8f4e8
    style BUILD fill:#fff3e0
    style TDD_CYCLE fill:#fff3e0
    style REVIEW fill:#f3e5f5
    style DONE fill:#e3f2fd,stroke:#333,stroke-width:2px
    style REV_SPEC fill:#fffde7
    style REV_PLAN fill:#fffde7
    style REV_FB fill:#fffde7
```

### The TDD Cycle (Step 4 in detail)

Each step in the plan goes through this exact sequence. The TDD skill enforces it automatically.

```mermaid
flowchart TD
    START["Pick next acceptance criterion"]
    RED["RED: Write ONE failing test"]
    RUN1["Run test suite"]
    FAIL{"New test fails?"}
    REWRITE["Rewrite test —<br/>if it passes without<br/>implementation,<br/>the test is wrong"]
    COMMIT_TEST["Commit failing test"]
    GREEN["GREEN: Write MINIMUM code<br/>to make test pass"]
    RUN2["Run FULL test suite"]
    PASS{"ALL tests pass?"}
    FIX_IMPL["Fix implementation<br/><i>not the tests</i>"]
    COMMIT_IMPL["Commit implementation"]
    REFACTOR["REFACTOR: Improve code quality<br/><i>extract, rename, simplify</i>"]
    RUN3["Run tests after EACH change"]
    COMMIT_REF["Commit refactoring<br/><i>if non-trivial</i>"]
    NEXT{"More criteria?"}
    DONE["All criteria met"]

    START --> RED
    RED --> RUN1
    RUN1 --> FAIL
    FAIL -->|"Yes ✓"| COMMIT_TEST
    FAIL -->|"No — passes already"| REWRITE
    REWRITE --> RED
    COMMIT_TEST --> GREEN
    GREEN --> RUN2
    RUN2 --> PASS
    PASS -->|"Yes ✓"| COMMIT_IMPL
    PASS -->|"No"| FIX_IMPL
    FIX_IMPL --> RUN2
    COMMIT_IMPL --> REFACTOR
    REFACTOR --> RUN3
    RUN3 --> COMMIT_REF
    COMMIT_REF --> NEXT
    NEXT -->|"Yes"| START
    NEXT -->|"No"| DONE

    style RED fill:#ffcdd2
    style GREEN fill:#c8e6c9
    style REFACTOR fill:#e3f2fd
    style COMMIT_TEST fill:#e0e0e0
    style COMMIT_IMPL fill:#e0e0e0
    style COMMIT_REF fill:#e0e0e0
```

**Why TDD matters here:** Without tests, Claude's only verification is its own judgment — which degrades as context fills. At 80% accuracy per decision, 20 sequential decisions yield 1.2% overall success. Tests provide ground truth that survives context compaction and session resets.

---

## Session Management

Sessions should be short and focused. The scaffold provides tools for preserving and resuming state.

```mermaid
flowchart TD
    subgraph "Starting a Session"
        NEW["New feature?<br/>Describe what you want"]
        RESUME["Resuming?<br/>/catchup"]
    end

    subgraph "Working"
        WORK["Implement features<br/><i>TDD cycles</i>"]
        STUCK{"Stuck after<br/>2 attempts?"}
        STOP["STOP — write alternatives<br/>to docs/checkpoint.md"]
        LONG{"Session > 30 min<br/>or context heavy?"}
    end

    subgraph "Ending a Session"
        CP["'Checkpoint this'<br/><i>writes docs/checkpoint.md</i>"]
        COMMIT["Commit current work"]
        CLEAR["/clear<br/><i>reset context</i>"]
    end

    NEW --> WORK
    RESUME --> WORK
    WORK --> STUCK
    STUCK -->|"No"| LONG
    STUCK -->|"Yes"| STOP
    STOP --> CP
    LONG -->|"Yes — checkpoint"| CP
    LONG -->|"No — keep going"| WORK
    CP --> COMMIT
    COMMIT --> CLEAR

    CLEAR -->|"Next session"| RESUME

    style NEW fill:#e3f2fd,stroke:#333,stroke-width:2px
    style RESUME fill:#e3f2fd,stroke:#333,stroke-width:2px
    style CLEAR fill:#ffcdd2,stroke:#333,stroke-width:2px
    style STUCK fill:#fffde7
    style LONG fill:#fffde7
```

### What `/catchup` reads

When you run `/catchup` after a `/clear`, Claude reads these sources to orient:

| Source | Purpose |
|--------|---------|
| `docs/checkpoint.md` | What was accomplished, blockers, next steps |
| `git log --oneline -10` | Recent commits |
| `git diff --stat` | Uncommitted changes |
| `git diff --cached --stat` | Staged changes |
| `docs/spec.md` | Current feature specification |

It reports the state but does NOT start implementing. You say "Continue" when ready.

### When to `/clear`

| Situation | Action |
|-----------|--------|
| Finished a feature | `/clear` → start fresh |
| Switching to a different task | Checkpoint → `/clear` → new task |
| Session feels slow or confused | Checkpoint → `/clear` → `/catchup` → "Continue" |
| After ~30 minutes of complex work | Checkpoint → `/clear` → `/catchup` |
| Context at ~60% | `/compact` first, or checkpoint → `/clear` |

**Why aggressive clearing works:** A fresh 30-minute session with clear context outperforms a degraded 3-hour session. Structured prompts preserve 92% fidelity through compaction vs 71% for narrative prompts.

---

## Scaffold Sync System

The scaffold is a hub with downstream project nodes. The sync system enables bi-directional flow of configuration.

### Architecture

```mermaid
graph TB
    subgraph HUB["Scaffold Hub<br/>~/projects/claude-code-scaffold"]
        H_RULES["rules/"]
        H_CMD["commands/"]
        H_AGENTS["agents/"]
        H_SKILLS["skills/"]
        H_TEMPLATES["docs/templates/"]
        H_SCRIPTS["scripts/"]
        H_GUIDE["GUIDE.md<br/><i>hub section</i>"]
        H_CLAUDE["CLAUDE.md<br/><i>hub methodology</i>"]
        H_FRAMEWORK["SCAFFOLD_FRAMEWORK.md<br/><i>research — read-only</i>"]
    end

    subgraph NODE["Downstream Project (e.g. fucina)"]
        N_RULES["rules/<br/><i>global + local</i>"]
        N_CMD["commands/<br/><i>global + local</i>"]
        N_AGENTS["agents/"]
        N_SKILLS["skills/"]
        N_TEMPLATES["docs/templates/"]
        N_SCRIPTS["scripts/"]
        N_GUIDE["GUIDE.md<br/><i>hub + node sections</i>"]
        N_CLAUDE["CLAUDE.md<br/><i>node identity + hub methodology</i>"]
        N_FRAMEWORK["SCAFFOLD_FRAMEWORK.md<br/><i>read-only copy</i>"]
        LOCK[".claude/scaffold.lock<br/><i>provenance manifest</i>"]
    end

    H_RULES <-->|"sync"| N_RULES
    H_CMD <-->|"sync"| N_CMD
    H_AGENTS <-->|"sync"| N_AGENTS
    H_SKILLS <-->|"sync"| N_SKILLS
    H_TEMPLATES <-->|"sync"| N_TEMPLATES
    H_SCRIPTS <-->|"sync"| N_SCRIPTS
    H_GUIDE -->|"section-merge"| N_GUIDE
    H_CLAUDE -->|"section-merge"| N_CLAUDE
    H_FRAMEWORK -->|"auto-update"| N_FRAMEWORK

    LOCK -.->|"tracks state"| N_RULES
    LOCK -.->|"tracks state"| N_CMD

    style HUB fill:#e8f4e8,stroke:#333,stroke-width:2px
    style NODE fill:#e3f2fd,stroke:#333,stroke-width:2px
    style LOCK fill:#f3e5f5
    style H_GUIDE fill:#fff3e0
    style H_CLAUDE fill:#fff3e0
    style H_FRAMEWORK fill:#e0e0e0
    style N_GUIDE fill:#fff3e0
    style N_CLAUDE fill:#fff3e0
    style N_FRAMEWORK fill:#e0e0e0
```

### File Status Lifecycle

Every tracked file has a status in the lockfile. Status determines what happens during pull/push.

```mermaid
stateDiagram-v2
    [*] --> clean: /init copies from scaffold

    clean --> modified: User edits locally
    clean --> modified: /scaffold-demote

    modified --> clean: /scaffold-pull → Take scaffold
    modified --> clean: /scaffold-pull → Merge (if result matches)

    [*] --> local_only: User creates new file

    local_only --> promoted: /scaffold-promote
    promoted --> clean: Next /scaffold-pull

    [*] --> scaffold_only: New file added to scaffold hub
    scaffold_only --> clean: /scaffold-pull → Accept

    clean --> node_only: /scaffold-ignore
    modified --> node_only: /scaffold-ignore
    local_only --> node_only: /scaffold-ignore
    node_only --> clean: scaffold-sync.sh track

    state clean {
        [*]: Auto-updated on pull
    }
    state modified {
        [*]: Conflict review on pull
    }
    state local_only {
        [*]: Never synced
    }
    state promoted {
        [*]: Pushed to hub
    }
    state scaffold_only {
        [*]: Not yet in project
    }
    state node_only {
        [*]: Permanently excluded from sync
    }
```

### Pull Flow (Hub → Project)

Every step is handled by a script command except conflict merge proposals, which require Claude's semantic understanding.

```mermaid
flowchart TD
    subgraph DETERMINISTIC ["Deterministic (script handles)"]
        START["pre-check"]
        PLAN["pull-plan → JSON"]
        AUTO["pull-auto<br/><i>all clean files in one pass</i>"]
        SM["pull-apply file section-merge"]
        TAKE["pull-apply file take-scaffold"]
        KEEP["pull-apply file keep-local"]
        ACCEPT["pull-apply file accept-new"]
        DEL["pull-apply file delete"]
        FIN["pull-finalize"]
    end

    subgraph STOCHASTIC ["Claude judgment"]
        MERGE["Read both versions,<br/>propose combined content"]
    end

    subgraph USER ["User decision"]
        OPT{"Conflict:<br/>keep / take /<br/>merge / diff?"}
        NEW_OPT{"New file:<br/>accept / skip?"}
        RM_OPT{"Removed:<br/>keep / delete?"}
        APPROVE{"Approve<br/>merged content?"}
    end

    START --> PLAN
    PLAN -->|"auto-update"| AUTO
    PLAN -->|"section-merge"| SM
    PLAN -->|"conflict"| OPT
    PLAN -->|"new"| NEW_OPT
    PLAN -->|"removed"| RM_OPT

    OPT -->|"Take scaffold"| TAKE
    OPT -->|"Keep local"| KEEP
    OPT -->|"Merge"| MERGE
    MERGE --> APPROVE
    APPROVE -->|"Yes"| TAKE
    APPROVE -->|"No"| OPT

    NEW_OPT -->|"Accept"| ACCEPT
    RM_OPT -->|"Keep"| KEEP
    RM_OPT -->|"Delete"| DEL

    AUTO --> FIN
    SM --> FIN
    TAKE --> FIN
    KEEP --> FIN
    ACCEPT --> FIN
    DEL --> FIN

    style DETERMINISTIC fill:#c8e6c9,stroke:#333,stroke-width:2px
    style STOCHASTIC fill:#fff3e0,stroke:#333,stroke-width:2px
    style USER fill:#e3f2fd,stroke:#333,stroke-width:2px
```

**Bootstrap requirement:** The pull process uses `scaffold-sync.sh` itself. If the hub has a newer version of the script with new commands, the node's old script won't know them. When this happens, manually copy the new script first: `cp <hub>/scripts/scaffold-sync.sh scripts/scaffold-sync.sh`, then run `/scaffold-pull`.

### Push Flow (Project → Hub)

Every step is handled by a script command except change classification, which requires Claude's semantic understanding.

```mermaid
flowchart TD
    subgraph DETERMINISTIC ["Deterministic (script handles)"]
        START["pre-check"]
        CANDS["push-candidates → JSON"]
        DIFF["diff file"]
        APPLY["push-apply file desc"]
        FIN["push-finalize message"]
    end

    subgraph STOCHASTIC ["Claude judgment"]
        CLASSIFY{"Classify change:<br/>generalizable /<br/>project-specific / mixed"}
    end

    subgraph USER ["User decision"]
        PRESENT["Review classification<br/>+ diff"]
        DECIDE{"Approve / skip /<br/>edit first?"}
    end

    START --> CANDS
    CANDS --> DIFF
    DIFF --> CLASSIFY
    CLASSIFY -->|"project-specific"| SKIP["Auto-skip"]
    CLASSIFY -->|"generalizable / mixed"| PRESENT
    PRESENT --> DECIDE
    DECIDE -->|"Approve"| APPLY
    DECIDE -->|"Skip"| SKIP
    DECIDE -->|"Edit"| PRESENT
    APPLY --> FIN

    style DETERMINISTIC fill:#c8e6c9,stroke:#333,stroke-width:2px
    style STOCHASTIC fill:#fff3e0,stroke:#333,stroke-width:2px
    style USER fill:#e3f2fd,stroke:#333,stroke-width:2px
```

### Sync Hardening: Guards and Dry-Run

Every destructive operation in the sync system is self-validating. Guards verify preconditions immediately before execution; `--dry-run` previews changes without applying them.

#### Guards (exit code 3)

| Guard | Trigger | What it prevents |
|-------|---------|-----------------|
| **jq validation** | After every lockfile mutation | Corrupt JSON replacing valid lockfile |
| **Hash re-check** | `pull-apply` with `PLAN_LOCAL_HASH` env var | File modified between plan and apply phases |
| **Status re-check** | `pull-apply delete` with `PLAN_LOCAL_STATUS` env var | Deleting file whose status changed since plan |
| **Commit verification** | `pull-finalize`, `push-finalize` | Silent commit failure (HEAD unchanged) |

All guards produce: `GUARD_FAIL: <operation> on <file>: <reason>` on stderr, exit code 3.

#### Dry-run mode

| Command | Flag | What it shows |
|---------|------|--------------|
| `pull-auto --dry-run` | `--dry-run` | Files that would be copied |
| `pull-apply <file> <action> --dry-run` | `--dry-run` | Action that would be applied |
| `pull-finalize --dry-run` | `--dry-run` | Commit message and file list |
| `push-apply <file> --dry-run` | `--dry-run` | File that would be pushed |
| `push-finalize <msg> --dry-run` | `--dry-run` | Commit message |

Dry-run output uses prefix: `DRY-RUN: would <verb> <file>`. Pre-check still runs (cleanness verification is not skipped).

### Promote and Demote

Demote is fully deterministic. Promote has one judgment call: checking for project-specific content.

```mermaid
flowchart LR
    subgraph Promote ["/scaffold-promote file"]
        P1["Claude: check for<br/>project-specific content"] --> P2["scaffold-sync.sh promote file<br/><i>verify + copy + lockfile + git + log</i>"]
    end

    subgraph Demote ["/scaffold-demote file — fully deterministic"]
        D1["scaffold-sync.sh demote file<br/><i>verify + lockfile + log</i>"]
    end

    style Promote fill:#c8e6c9
    style Demote fill:#fff3e0
    style P1 fill:#fff3e0
    style P2 fill:#c8e6c9
    style D1 fill:#c8e6c9
```

### Universal Delimiters (Section-Merge)

**Principle:** Every synced markdown file ships with a `<!-- NODE-SPECIFIC-START -->` delimiter. Hub content lives above the delimiter, node-specific customizations live below. This enables section-merge on pull — hub updates flow automatically without overwriting project customizations.

#### Which files have delimiters

| Component type | Files | Delimiter | Hub section | Node section |
|----------------|-------|-----------|-------------|--------------|
| Rules | `.claude/rules/*.md` (5 files) | `NODE-SPECIFIC-START` | Universal principles, anti-patterns | Project-specific exceptions, local conventions |
| Commands | `.claude/commands/*.md` (10 files) | `NODE-SPECIFIC-START` | Workflow steps, script calls, universal rules | Project-specific paths, tools, additional steps |
| Agents | `.claude/agents/*.md` (3 files) | `NODE-SPECIFIC-START` | Role definition, output format, universal rules | Project-specific context, domain knowledge |
| Skills | `.claude/skills/*/SKILL.md` (1 file) | `NODE-SPECIFIC-START` | Methodology, phases, rules | Project test command, framework config |
| Templates | `docs/templates/*.md` (4 files) | `NODE-SPECIFIC-START` | Document structure, required sections | Project-specific fields, custom sections |
| GUIDE.md | `GUIDE.md` | `NODE-SPECIFIC-START` | Documentation, diagrams, tables | Project-specific features |
| CLAUDE.md | `CLAUDE.md` | `HUB-MANAGED-START` | Workflow, conventions, do-not rules | Project name, tech stack, commands, architecture |

**What does NOT get delimiters (and why):**

| Component type | Why not | Alternative |
|----------------|---------|-------------|
| Scripts (`*.sh`) | Can't splice bash — functions depend on each other. HTML comments aren't valid bash. | Whole-file tracked. Node customization via separate scripts or node-only fork. |
| Hooks (`*.sh`) | Same as scripts. | Stack hooks: hub provides universal hooks, node adds additional hook entries in settings.json. |
| `settings.json` | JSON has no comments. | Node-only. Hub hook scripts sync; settings.json references are node-managed. |
| `SCAFFOLD_FRAMEWORK.md` | Research source material — identical everywhere, no node content. | Whole-file auto-update. |

#### How section-merge works

Files with delimiters have a hub-managed section and a node-specific section. During `/scaffold-pull`, the hub section is updated from the scaffold while the node section is preserved intact.

```mermaid
flowchart LR
    subgraph "Most files (rules, commands, agents, skills, templates, GUIDE.md)"
        M_HUB["Hub content<br/><i>universal methodology</i>"]
        M_DELIM["&lt;!-- NODE-SPECIFIC-START --&gt;"]
        M_NODE["Node content<br/><i>project customizations</i>"]
        M_HUB --> M_DELIM --> M_NODE
    end

    subgraph "CLAUDE.md (inverted)"
        C_NODE["Node identity<br/><i>name, stack, commands, architecture</i>"]
        C_DELIM["&lt;!-- HUB-MANAGED-START --&gt;"]
        C_HUB["Hub methodology<br/><i>workflow, conventions, do-not</i>"]
        C_NODE --> C_DELIM --> C_HUB
    end

    style M_HUB fill:#e8f4e8
    style M_NODE fill:#e3f2fd
    style M_DELIM fill:#fffde7
    style C_NODE fill:#e3f2fd
    style C_HUB fill:#e8f4e8
    style C_DELIM fill:#fffde7
```

**During `/scaffold-pull`:**
- **Files with `NODE-SPECIFIC-START`:** Hub section (above delimiter) is replaced with scaffold's version. Node section (below) is untouched.
- **CLAUDE.md** (`HUB-MANAGED-START`): Node section (above delimiter) is untouched. Hub section (below) is replaced with scaffold's version.
- **SCAFFOLD_FRAMEWORK.md:** Auto-updated as a whole file (no delimiter, no node content).

**During `/scaffold-push`:** Node sections are always classified as project-specific and never pushed upstream.

**Legacy projects without delimiters:** The `section-merge` command gracefully handles files that don't have a delimiter yet — it treats the entire local file as node content and adds the hub section from the scaffold.

#### Creating new markdown components

When adding a new rule, command, agent, skill, or template to the scaffold, **always** include the delimiter at the end:

```
&lt;!-- NODE-SPECIFIC-START --&gt;
&lt;!-- Add project-specific content below this line. --&gt;
&lt;!-- Hub content above is updated via /scaffold-pull. --&gt;
```

---

## Command Reference

### Feature Development Commands

| Command | Phase | What it does | Files affected |
|---------|-------|-------------|----------------|
| *"Describe feature"* | Spec | Triggers spec-writer agent | Writes `docs/specs/<id>.md` |
| `/plan` | Plan | Creates ordered TDD steps from spec | Writes `docs/plan.md` |
| *"Start building"* | Build | Enters TDD cycle | Source + test files |
| `/commit` | Build | Stages, generates conventional commit, runs tests | Git history |
| `/review` | Review | Spawns code-reviewer sub-agent | None (read-only) |
| `/pr` | Ship | Creates draft PR with evaluation gates | GitHub PR |

### Session Management Commands

| Command | When | What it does |
|---------|------|-------------|
| `/catchup` | After `/clear` | Reads checkpoint + git state, reports status |
| *"Checkpoint this"* | Pausing work | Writes state to `docs/checkpoint.md`, commits |
| `/clear` | Between tasks | Resets context (built-in) |
| `/compact` | Context heavy | Summarizes context to free space (built-in) |
| `/cost` | Monitoring | Shows token usage (built-in) |

### Scaffold Sync Commands

| Command | Direction | What it does |
|---------|-----------|-------------|
| `/scaffold-status` | Read-only | Shows sync state of all tracked files |
| `/scaffold-pull` | Hub → Project | Pulls updates, resolves conflicts |
| `/scaffold-push` | Project → Hub | Pushes generalizable changes upstream |
| `/scaffold-promote <file>` | Project → Hub | Promotes a local file to the scaffold |
| `/scaffold-demote <file>` | Local | Marks a scaffold file as local override |
| `/scaffold-ignore <file>` | Local | Marks file as node-only (permanently excluded from sync) |

### Utility Commands

| Command | What it does |
|---------|-------------|
| `/scaffold-audit` | Analyzes scaffold for stochastic-to-deterministic improvement opportunities. Calls `manifest-check.sh check` for deterministic README verification. Includes permissions audit and context budget check. |
| `/fix-certs` | Diagnoses and repairs Cloudflare WARP TLS certificate issues |
| `/init` | Initializes a new project from the scaffold (global command) |

### Permissions Audit Scripts

| Command | What it does |
|---------|-------------|
| `permissions-audit.sh check [--settings-dir DIR] [--log FILE]` | Classify all Bash permission entries as DANGER/UNREVIEWED/REVIEWED → JSON |
| `permissions-audit.sh check --text [--verbose]` | Human-readable grouped report (DANGER, UNREVIEWED, optionally REVIEWED) |
| `permissions-audit.sh init [--settings-dir DIR] [--log FILE]` | Create/update decision log with stubs for unreviewed entries |

### Context Budget Scripts

| Command | What it does |
|---------|-------------|
| `context-budget.sh check` | Measure token cost of always-loaded scaffold files → JSON |
| `context-budget.sh check --text` | Human-readable table with per-file tokens and budget status |
| `context-budget.sh check --model MODEL_ID` | Set context window from known model (e.g., `claude-opus-4-6[1m]` → 1M) |
| `context-budget.sh check --context-window N` | Set context window size directly (overrides `--model`) |
| `context-budget.sh check --budget N` | Override budget ceiling directly (overrides `--context-window` and `--model`) |

### Operations Routing Scripts

| Command | What it does |
|---------|-------------|
| `operations.sh resolve <operation> [--project-dir DIR]` | Resolve operation to provider/mechanism/invocation JSON based on `.claude/scaffold.json` routing config. Returns local bash adapter when no config exists. |

### Multi-Spec Lifecycle Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh list-specs [docs-dir]` | List all specs in `docs/specs/` with feature_id, status, created → JSON array |
| `docs-check.sh activate <feature-id> [docs-dir]` | Create branch `claude/<type>/<id>`, copy spec to `docs/spec.md`, set status to In Progress |
| `docs-check.sh complete <feature-id> [docs-dir]` | Set spec status to Complete, clear `docs/assumptions.md` |
| `docs-check.sh config-get <key> [project-dir]` | Read feature toggle from `.claude/scaffold.json` (returns `true`/`false`) |

### Manifest Verification Scripts

| Command | What it does |
|---------|-------------|
| `manifest-check.sh parse <readme>` | Parse markdown tables → JSON `[{path, description}]` |
| `manifest-check.sh check-existence <readme>` | Check which paths exist on disk, discover untracked files |
| `manifest-check.sh init <readme>` | Create `.claude/manifest.lock` with file hashes + git commit |
| `manifest-check.sh hash-check` | Compare current hashes against lockfile → verified/stale |
| `manifest-check.sh extract-identity <file>` | Extract identity metadata (comment headers, frontmatter, headings) |
| `manifest-check.sh check <readme>` | Full report: verified + stale (with diffs) + missing + untracked (with identity) |
| `manifest-check.sh verify <paths...>` | Update lockfile entries for confirmed paths |

### Docs Lifecycle Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh status [docs-dir]` | Extract metadata (feature_id, hashes, timestamps) from spec/plan/checkpoint → JSON |
| `docs-check.sh validate [docs-dir]` | Check alignment: `aligned`, `stale-plan`, `stale-checkpoint`, `mismatched`, `unlinked`, `missing-determinism-review` |
| `docs-check.sh recommend [docs-dir]` | State machine → `{next_action, reason}` (e.g., "Run /plan", "Ready to build") |
| `docs-check.sh audit-session [--since commit] [repo-dir]` | Scan git diffs for stochastic patterns (cp, jq, shasum, git -C, curl, wget) + commit messages for indicator phrases → JSON |

---

## Configuration Layers

### What goes where

```mermaid
graph LR
    subgraph "Deterministic (Always fires)"
        HOOKS["settings.json hooks<br/><i>formatting, security blocks</i>"]
        IGNORE[".claudeignore<br/><i>file exclusions</i>"]
    end

    subgraph "Judgment-based (Loaded at launch)"
        CLAUDE["CLAUDE.md<br/><i>project identity, conventions</i>"]
        RULES["rules/*.md<br/><i>TDD, workflow, code quality</i>"]
    end

    subgraph "On-demand (Loaded when needed)"
        SKILLS["skills/*/SKILL.md<br/><i>TDD workflow procedure</i>"]
        AGENTS["agents/*.md<br/><i>spec-writer, code-reviewer</i>"]
        CMDS["commands/*.md<br/><i>slash commands</i>"]
    end

    HOOKS -->|"No context cost"| HOOKS
    CLAUDE -->|"Shares ~150<br/>instruction budget"| RULES
    SKILLS -.->|"Loaded on trigger"| SKILLS
    AGENTS -.->|"Isolated 200K<br/>context window"| AGENTS

    style HOOKS fill:#c8e6c9
    style IGNORE fill:#c8e6c9
    style CLAUDE fill:#e3f2fd
    style RULES fill:#e3f2fd
    style SKILLS fill:#fff3e0
    style AGENTS fill:#fff3e0
    style CMDS fill:#fff3e0
```

**The principle:** Use hooks for things that must ALWAYS happen (formatting, security). Use rules and CLAUDE.md for things requiring judgment (coding patterns, conventions). Use skills/agents for workflows that only activate sometimes. See the [Deterministic-First rule](#deterministic-first-principle) for the full hierarchy.

### Hooks (`.claude/hooks/`)

Hook scripts live in `.claude/hooks/` and are referenced from `settings.json`. They receive JSON on stdin and control behavior via exit codes.

| Hook | Event | Script | What it does |
|------|-------|--------|-------------|
| File protection | PreToolUse (Write\|Edit\|MultiEdit) | `protect-files.sh` | Blocks writes to `.env`, credentials, `SCAFFOLD_FRAMEWORK.md`, `node_modules/`, `dist/`, `generated/` |
| Syntax lint | PostToolUse (Write\|Edit\|MultiEdit) | `lint-on-write.sh` | Validates syntax: bash -n for .sh, jq for .json, yaml check for .yaml. Blocks on errors. |
| Auto-format | PostToolUse (Write\|Edit\|MultiEdit) | `format-on-write.sh` | Runs project formatter (uncomment for your stack: Prettier, Black, gofmt, etc.) |

### Rules (loaded at launch)

| Rule file | Concern | Key behaviors enforced |
|-----------|---------|----------------------|
| `deterministic-first.md` | Architecture | Use scripts/hooks over Claude reasoning for computable operations; hierarchy: hook → script → slash command → pure reasoning |
| `tdd.md` | Testing | Red-green-refactor cycle, test naming, fix implementation not tests |
| `workflow.md` | Sessions | One objective per session, checkpoint, delegate research, stop after 2 failures |
| `code-quality.md` | Code | Follow existing patterns, typed errors, pin dependencies, intent-revealing names |
| `tls-troubleshooting.md` | Certs | Auto-detect WARP cert errors, fix with CA bundle, never disable TLS |
| `self-review.md` | Meta | Flag stochastic interventions during checkpoints/reviews; lightweight always-on version of `/scaffold-audit` |

---

## Hooks System

Hooks are deterministic automation that runs at Claude Code lifecycle events — outside the reasoning loop, at zero context cost. They are the foundation of the [deterministic-first principle](#deterministic-first-principle).

> **Reference:** See `docs/templates/hooks-reference.md` for the complete hook specification including JSON schemas, all event types, and writing conventions.

### How Hooks Work

```mermaid
sequenceDiagram
    participant C as Claude
    participant CC as Claude Code
    participant H as Hook Script
    participant F as File System

    C->>CC: Write tool call
    CC->>H: PreToolUse (JSON on stdin)
    alt Exit 0 (allow)
        H-->>CC: OK
        CC->>F: Write file
        F-->>CC: Done
        CC->>H: PostToolUse (JSON on stdin)
        H->>F: Run formatter
        H-->>CC: OK
    else Exit 2 (block)
        H-->>CC: BLOCKED: reason (stderr)
        CC->>C: "Hook blocked: reason"
        Note over C: Claude adjusts approach
    end
```

### Deterministic-First Principle

Every operation falls somewhere on the deterministic-stochastic spectrum. The scaffold enforces this hierarchy:

```mermaid
graph TD
    subgraph "1. HOOK — zero context cost"
        H1["Block writes to .env"]
        H2["Auto-format on save"]
        H3["Protect SCAFFOLD_FRAMEWORK.md"]
    end

    subgraph "2. SCRIPT — one command instead of many"
        S1["pull-auto: copy + lockfile + log"]
        S2["promote: verify + copy + git + log"]
        S3["demote: verify + lockfile + log"]
    end

    subgraph "3. SLASH COMMAND — script calls + judgment"
        C1["scaffold-pull: script plans, Claude resolves conflicts"]
        C2["scaffold-push: script lists candidates, Claude classifies"]
    end

    subgraph "4. PURE CLAUDE — semantic understanding only"
        L1["Propose merge content"]
        L2["Classify generalizable vs specific"]
        L3["Write specs and code"]
    end

    style H1 fill:#c8e6c9
    style H2 fill:#c8e6c9
    style H3 fill:#c8e6c9
    style S1 fill:#e8f4e8
    style S2 fill:#e8f4e8
    style S3 fill:#e8f4e8
    style C1 fill:#e3f2fd
    style C2 fill:#e3f2fd
    style L1 fill:#fff3e0
    style L2 fill:#fff3e0
    style L3 fill:#fff3e0
```

**The test:** "Can this step produce a wrong answer?" If no → it belongs in a script or hook, not Claude's reasoning.

### Hook vs Rule vs Skill

| Situation | Mechanism | Why |
|-----------|-----------|-----|
| "Never write to .env files" | **Hook** (PreToolUse, exit 2) | Binary file path check, zero context cost |
| "Always format code after writing" | **Hook** (PostToolUse) | Deterministic formatter, zero context cost |
| "Protect SCAFFOLD_FRAMEWORK.md" | **Hook** (PreToolUse, exit 2) | Binary check, enforced even if Claude forgets the rule |
| "Follow existing code patterns" | **Rule** | Requires semantic understanding of codebase |
| "Don't add unnecessary dependencies" | **Rule** | Requires judgment about "unnecessary" |
| "Run TDD red-green-refactor cycle" | **Skill** | Multi-step workflow with verification |

### Active Hooks

| Script | Event | Exit 2 blocks | What it checks |
|--------|-------|---------------|----------------|
| `protect-files.sh` | PreToolUse | Yes | `.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key`, `SCAFFOLD_FRAMEWORK.md`, `node_modules/`, `dist/`, `generated/`, `.git/` |
| `lint-on-write.sh` | PostToolUse | Yes | Syntax validation: `bash -n` for `.sh`, `jq empty` for `.json`, python yaml check for `.yaml`. Blocks writes with syntax errors. |
| `format-on-write.sh` | PostToolUse | No | Detects file type, runs appropriate formatter (uncomment for your stack) |

### Adding a New Hook

1. Create script in `.claude/hooks/` (use `protect-files.sh` as template)
2. `chmod +x .claude/hooks/my-hook.sh`
3. Add entry to `.claude/settings.json` under the appropriate event
4. Test: `echo '{"tool_input":{"file_path":"test.env"}}' | .claude/hooks/my-hook.sh; echo "exit: $?"`
5. Update this section and `docs/templates/hooks-reference.md`

---

## Decision Guide

### "Should I use a slash command or just talk?"

```mermaid
flowchart TD
    Q["What do you want to do?"]

    Q -->|"Start building a feature"| A1["Just describe it<br/><i>'I want the app to...'</i>"]
    Q -->|"Create an implementation plan"| A2["/plan"]
    Q -->|"Review code before committing"| A3["/review"]
    Q -->|"Resume after a break"| A4["/catchup"]
    Q -->|"Check scaffold sync state"| A5["/scaffold-status"]
    Q -->|"Pull scaffold updates"| A6["/scaffold-pull"]
    Q -->|"Share a local file globally"| A7["/scaffold-promote file"]
    Q -->|"Fix TLS certificate errors"| A8["/fix-certs"]
    Q -->|"Session feels degraded"| A9["'Checkpoint this'<br/>→ /clear → /catchup"]

    style A1 fill:#e3f2fd
    style A2 fill:#e8f4e8
    style A3 fill:#e8f4e8
    style A4 fill:#e8f4e8
    style A9 fill:#ffcdd2
```

### "When should I checkpoint vs clear vs compact?"

```mermaid
flowchart TD
    Q["Context concern?"]

    Q -->|"Finished a feature"| CLEAR["/clear<br/><i>Full reset, start fresh</i>"]
    Q -->|"Need a break,<br/>coming back later"| CP["'Checkpoint this'<br/>→ /clear"]
    Q -->|"Context at ~60%<br/>but mid-task"| COMPACT["/compact<br/><i>Summarize to free space</i>"]
    Q -->|"Session > 30 min"| CP2["'Checkpoint this'<br/>→ /clear → /catchup → 'Continue'"]
    Q -->|"Stuck after<br/>2 failed attempts"| STOP["STOP<br/>Write alternatives to checkpoint<br/>→ /clear → restart with better approach"]

    style CLEAR fill:#ffcdd2
    style CP fill:#fff3e0
    style COMPACT fill:#e3f2fd
    style STOP fill:#ffcdd2,stroke:#333,stroke-width:2px
```

### "When should I sync with the scaffold?"

```mermaid
flowchart TD
    Q["Sync scenario?"]

    Q -->|"Created a useful<br/>new rule/command/agent"| PROMOTE["/scaffold-promote file<br/><i>Share with all projects</i>"]
    Q -->|"Want to check for<br/>scaffold updates"| STATUS["/scaffold-status<br/><i>then /scaffold-pull if updates exist</i>"]
    Q -->|"Customized a scaffold file<br/>and want to keep my version"| DEMOTE["/scaffold-demote file<br/><i>Prevents auto-update on pull</i>"]
    Q -->|"File is permanently<br/>project-specific"| IGNORE["/scaffold-ignore file<br/><i>Excluded from all future sync</i>"]
    Q -->|"Made improvements to<br/>a modified scaffold file"| PUSH["/scaffold-push<br/><i>Claude extracts generalizable parts</i>"]
    Q -->|"Starting a new project"| PULL["Pull latest into current project first<br/>then /init in new project"]

    style PROMOTE fill:#c8e6c9
    style STATUS fill:#e3f2fd
    style DEMOTE fill:#fff3e0
    style IGNORE fill:#ffcdd2
    style PUSH fill:#c8e6c9
    style PULL fill:#e3f2fd
```

---

## Appendix: Why Each Practice Exists

Every scaffold feature traces back to transformer architecture research. This table maps features to their underlying justification from `SCAFFOLD_FRAMEWORK.md`.

| Practice | Research basis |
|----------|--------------|
| Deterministic-first principle | Every token Claude spends on a deterministic operation (cp, diff, hash, lockfile update) is a token stolen from judgment calls that need a transformer. Computable operations must be scripts/hooks. |
| Hooks over rules for binary checks | Hooks run outside the context window at zero cost. Rules consume instruction slots and can be forgotten under context pressure. Hooks enforce unconditionally. |
| Compound script commands | One `pull-auto` call replaces 4-6 manual commands per file (cp + hash + lock-update ×3 + log). Reduces context burn by ~70% during sync operations. |
| Node-only classification | Separates sync intent from sync state. Project-specific files (custom permissions, domain rules) are permanently excluded from pull/push — zero context burned evaluating files that will never move. |
| CLAUDE.md under 80 lines | U-shaped attention: models attend to beginning/end, lose the middle. ~150-200 effective instruction slots. |
| TDD verification loops | Without tests, 80% accuracy per decision × 20 decisions = 1.2% overall success. Tests provide external oracle. |
| Spec before code | "Instruction loss" is the primary bottleneck — models lose track of earlier requirements when multiple features specified together. |
| Short sessions + `/clear` | Performance degrades starting at 3,000 tokens. Even with 100% perfect retrieval, accuracy drops 13-85% as input grows. |
| Sub-agents for research | Isolated 200K context windows. Only summaries return. Keeps main session focused on implementation. |
| `.claudeignore` exclusions | File reads consume 80% of context. Excluding irrelevant files is the biggest single lever. |
| Hooks for formatting | Never send an LLM to do a linter's job. Deterministic tools handle formatting perfectly without consuming instruction budget. |
| Progressive disclosure (`@path`) | Loading detailed docs on-demand prevents attention dilution. Every token competes; don't load what isn't needed now. |
| Templates separate from active docs | Format guides persist as scaffold resources; active docs are overwritten freely. Agents always have the format reference available. |
| Scaffold sync with lockfile | Configuration inheritance with provenance tracking. Enables knowledge reuse across projects while respecting local customization. |
| Universal delimiters for all markdown | Every synced markdown file has a section delimiter. Hub updates flow via section-merge without overwriting node customizations. Eliminates manual conflict resolution for the most common sync case: hub improves a rule/command while node has project-specific additions. |
| SCAFFOLD_FRAMEWORK.md protection | Research source material is foundational — changes only under paradigm shifts, preserving the reasoning behind every design decision. |
| Manifest verification with lockfile | Hash comparison auto-verifies unchanged files (zero Claude involvement). Changed files get a diff (not full content) — Claude judges "does this diff affect the description?" rather than re-reading 200-line files. Untracked files get identity extraction (headers/frontmatter), not full reads. Converts N full-file reads into N hash comparisons + K diffs where K << N. |
| Docs lifecycle linking | Hash-chain validation between spec→plan→checkpoint. Metadata changes (status, timestamps) don't invalidate hashes — only body content changes do. State machine maps document state to next action deterministically. `/catchup` surfaces staleness before reading content, preventing wasted sessions on outdated context. |
| Multi-spec backlog | Specs live in `docs/specs/` with lifecycle states. One active spec at a time (enforced by `activate`). Branch = isolation boundary. Git already solves parallel workstreams — the scaffold just formalizes the mapping. |
| Branch-based feature lifecycle | Branch naming convention (`claude/<type>/<name>`) enables programmatic identification. Draft PRs with mandatory human review (universal consensus across 12 teams). `/commit` and `/pr` commands enforce discipline without manual git orchestration. |
| Context budget measurement | Token estimation (chars/4) for always-loaded files with model-aware budget ceilings. Makes the attention cost of scaffold configuration visible. Three-tier thresholds (HEALTHY/WARNING/CRITICAL) surface problems before they degrade performance. |

---

## Parallel Agent Sessions

Claude Code supports running multiple agents in parallel via git worktrees (`claude --worktree` or `-w`). The scaffold is compatible with this workflow.

### How it works

- **Worktrees share `.git`:** All scaffold configuration (CLAUDE.md, rules, hooks, settings.json) is inherited automatically. No duplication needed.
- **Branch-local docs:** `docs/spec.md`, `docs/plan.md`, `docs/checkpoint.md` are branch-specific. Each worktree operates on its own branch, so parallel agents get isolated doc state.
- **Lockfile is shared:** `.claude/scaffold.lock` lives in `.git`-tracked state. Avoid running `/scaffold-pull` from multiple worktrees simultaneously.

### Usage pattern

```bash
# Start a new agent on a feature branch in a worktree
claude --worktree feature-name

# Or create a worktree manually and launch Claude in it
git worktree add .claude/worktrees/auth-system claude/feat/auth-system
cd .claude/worktrees/auth-system
claude
```

### What to watch for

| Concern | Mitigation |
|---------|-----------|
| Port conflicts | Each worktree may try to start dev servers on the same port. Use different ports per worktree. |
| Database locks | Multiple agents writing to the same SQLite/local DB will conflict. Use separate DB files or a shared server. |
| File locks | Lock files (`.lock`, `*.pid`) in the repo root are shared. Ensure they're branch-specific or gitignored. |
| Scaffold sync | Don't run `/scaffold-pull` from multiple worktrees simultaneously — lockfile mutations will conflict. |

### `.gitignore` and `.claudeignore`

Both files include `.claude/worktrees/` to prevent worktree contents from being tracked or loaded into context.

<!-- NODE-SPECIFIC-START -->
<!-- Everything above is managed by the scaffold hub and updated via /scaffold-pull. -->
<!-- Everything below is specific to this project. Add project-specific commands, rules, workflows here. -->

## Project-Specific Features

_No project-specific features yet. As you add local commands, rules, agents, or skills, document them here._
