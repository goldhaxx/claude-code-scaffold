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
8. [Decision Guide: When To Use What](#decision-guide)

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
        CHANGELOG["SCAFFOLD_CHANGELOG.md"]
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
        SYNCLOG[".claude/scaffold-sync.log"]
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
    style CHANGELOG fill:#fff3e0
    style SYNCLOG fill:#fff3e0
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
```

### Pull Flow (Hub → Project)

```mermaid
flowchart TD
    START["/scaffold-pull"]
    CHECK{"Scaffold repo<br/>has uncommitted<br/>changes?"}
    STOP["STOP — warn user"]
    SCAN["Compare each file's<br/>scaffold_hash vs current scaffold"]

    subgraph "For each file"
        CHANGED{"Scaffold<br/>changed?"}
        LOCAL{"Local file<br/>is clean?"}
        AUTO["AUTO-UPDATE<br/><i>copy scaffold version</i>"]
        CONFLICT["CONFLICT<br/><i>both sides changed</i>"]
        SKIP_NC["Skip — no change"]
        SKIP_LO["Skip — local changes preserved"]

        OPT{"User chooses:"}
        KEEP["Keep local"]
        TAKE["Take scaffold"]
        MERGE["Merge both<br/><i>Claude proposes combined version</i>"]
        DIFF["Show full diff<br/><i>then choose</i>"]
    end

    NEW{"New file<br/>in scaffold?"}
    OFFER["Offer to add"]
    ACCEPT["Copy to project"]
    DECLINE["Skip"]

    UPDATE["Update lockfile<br/>hashes + version"]
    LOG["Write sync log entry"]

    START --> CHECK
    CHECK -->|"Yes"| STOP
    CHECK -->|"No"| SCAN
    SCAN --> CHANGED
    CHANGED -->|"No"| LOCAL
    LOCAL -->|"Clean"| SKIP_NC
    LOCAL -->|"Modified"| SKIP_LO
    CHANGED -->|"Yes"| LOCAL
    LOCAL -->|"Clean"| AUTO
    LOCAL -->|"Modified"| CONFLICT

    CONFLICT --> OPT
    OPT --> KEEP
    OPT --> TAKE
    OPT --> MERGE
    OPT --> DIFF
    DIFF --> OPT

    SCAN --> NEW
    NEW -->|"Yes"| OFFER
    OFFER --> ACCEPT
    OFFER --> DECLINE

    AUTO --> UPDATE
    KEEP --> UPDATE
    TAKE --> UPDATE
    MERGE --> UPDATE
    ACCEPT --> UPDATE
    UPDATE --> LOG

    style AUTO fill:#c8e6c9
    style CONFLICT fill:#ffcdd2
    style MERGE fill:#fff3e0
    style STOP fill:#ffcdd2,stroke:#333,stroke-width:2px
```

### Push Flow (Project → Hub)

```mermaid
flowchart TD
    START["/scaffold-push"]
    CHECK{"Scaffold repo<br/>has uncommitted<br/>changes?"}
    STOP["STOP — warn user"]

    GATHER["Gather candidates:<br/>MODIFIED + LOCAL files"]

    subgraph "For each candidate"
        READ["Read file content"]
        CLASSIFY{"Classify change"}
        GEN["GENERALIZABLE<br/><i>useful across projects</i>"]
        SPEC["PROJECT-SPECIFIC<br/><i>references project details</i>"]
        MIX["MIXED<br/><i>extract generalizable parts</i>"]

        PRESENT["Present classification<br/>+ diff to user"]
        DECIDE{"User decision"}
        APPROVE["Approved"]
        EDIT["Edit first"]
        SKIP["Skip"]
    end

    APPLY["Copy to scaffold<br/><i>only generalizable parts</i>"]
    COMMIT["Commit in scaffold repo"]
    CHANGELOG["Write SCAFFOLD_CHANGELOG.md"]
    LOCKUP["Update lockfile"]
    LOG["Write sync log"]

    START --> CHECK
    CHECK -->|"Yes"| STOP
    CHECK -->|"No"| GATHER
    GATHER --> READ
    READ --> CLASSIFY
    CLASSIFY --> GEN
    CLASSIFY --> SPEC
    CLASSIFY --> MIX
    GEN --> PRESENT
    MIX --> PRESENT
    SPEC --> SKIP

    PRESENT --> DECIDE
    DECIDE --> APPROVE
    DECIDE --> EDIT
    DECIDE --> SKIP
    EDIT --> PRESENT

    APPROVE --> APPLY
    APPLY --> COMMIT
    COMMIT --> CHANGELOG
    CHANGELOG --> LOCKUP
    LOCKUP --> LOG

    style GEN fill:#c8e6c9
    style SPEC fill:#ffcdd2
    style MIX fill:#fff3e0
    style STOP fill:#ffcdd2,stroke:#333,stroke-width:2px
```

### Promote and Demote

```mermaid
flowchart LR
    subgraph Promote ["/scaffold-promote file"]
        P1["Verify file is<br/>local-only"] --> P2["Check for<br/>project-specific content"]
        P2 --> P3["Copy to scaffold hub"]
        P3 --> P4["Status: local-only → promoted"]
    end

    subgraph Demote ["/scaffold-demote file"]
        D1["Verify file is<br/>clean"] --> D2["Mark as local override"]
        D2 --> D3["Status: clean → modified"]
        D3 --> D4["Future pulls show diff<br/>instead of auto-updating"]
    end

    style Promote fill:#c8e6c9
    style Demote fill:#fff3e0
```

### Document Inheritance (Section-Merge)

Three root-level documents are tracked by the sync system with special merge behavior:

| File | Sync behavior | Hub content | Node content |
|------|--------------|-------------|--------------|
| `SCAFFOLD_FRAMEWORK.md` | Standard auto-update | Entire file (research source material) | None — identical everywhere |
| `GUIDE.md` | Section-merge | Documentation, diagrams, tables (above delimiter) | Project-specific features (below delimiter) |
| `CLAUDE.md` | Section-merge | Workflow, conventions, reference docs, do-not rules (below delimiter) | Project name, tech stack, commands, architecture (above delimiter) |

**How section-merge works:**

Files with delimiters have a hub-managed section and a node-specific section. During `/scaffold-pull`, the hub section is updated from the scaffold while the node section is preserved intact.

```mermaid
flowchart LR
    subgraph "GUIDE.md"
        G_HUB["Hub documentation<br/><i>diagrams, tables, references</i>"]
        G_DELIM["&lt;!-- NODE-SPECIFIC-START --&gt;"]
        G_NODE["Node features<br/><i>local commands, rules, workflows</i>"]
        G_HUB --> G_DELIM --> G_NODE
    end

    subgraph "CLAUDE.md"
        C_NODE["Node identity<br/><i>name, stack, commands, architecture</i>"]
        C_DELIM["&lt;!-- HUB-MANAGED-START --&gt;"]
        C_HUB["Hub methodology<br/><i>workflow, conventions, do-not</i>"]
        C_NODE --> C_DELIM --> C_HUB
    end

    style G_HUB fill:#e8f4e8
    style G_NODE fill:#e3f2fd
    style G_DELIM fill:#fffde7
    style C_NODE fill:#e3f2fd
    style C_HUB fill:#e8f4e8
    style C_DELIM fill:#fffde7
```

**During `/scaffold-pull`:**
- **GUIDE.md:** Hub section (above delimiter) is replaced with scaffold's version. Node section (below) is untouched.
- **CLAUDE.md:** Node section (above delimiter) is untouched. Hub section (below) is replaced with scaffold's version.
- **SCAFFOLD_FRAMEWORK.md:** Auto-updated as a whole file (no delimiter, no node content).

**During `/scaffold-push`:** Node sections are always classified as project-specific and never pushed upstream.

**Legacy projects without delimiters:** The `section-merge` command gracefully handles files that don't have a delimiter yet — it treats the entire local file as node content and adds the hub section from the scaffold.

---

## Command Reference

### Feature Development Commands

| Command | Phase | What it does | Files affected |
|---------|-------|-------------|----------------|
| *"Describe feature"* | Spec | Triggers spec-writer agent | Writes `docs/spec.md` |
| `/plan` | Plan | Creates ordered TDD steps from spec | Writes `docs/plan.md` |
| *"Start building"* | Build | Enters TDD cycle | Source + test files |
| `/review` | Review | Spawns code-reviewer sub-agent | None (read-only) |

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

### Utility Commands

| Command | What it does |
|---------|-------------|
| `/fix-certs` | Diagnoses and repairs Cloudflare WARP TLS certificate issues |
| `/init` | Initializes a new project from the scaffold (global command) |

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

**The principle:** Use hooks for things that must ALWAYS happen (formatting, security). Use rules and CLAUDE.md for things requiring judgment (coding patterns, conventions). Use skills/agents for workflows that only activate sometimes.

### Hooks (settings.json)

| Hook | Event | What it does |
|------|-------|-------------|
| Security blocker | Pre-write | Blocks writes to `.env`, `*credentials*`, `*secret*` files |
| Auto-format | Post-write | Runs formatter (commented out — uncomment for your project) |

### Rules (loaded at launch)

| Rule file | Concern | Key behaviors enforced |
|-----------|---------|----------------------|
| `tdd.md` | Testing | Red-green-refactor cycle, test naming, fix implementation not tests |
| `workflow.md` | Sessions | One objective per session, checkpoint, delegate research, stop after 2 failures |
| `code-quality.md` | Code | Follow existing patterns, typed errors, pin dependencies, intent-revealing names |
| `tls-troubleshooting.md` | Certs | Auto-detect WARP cert errors, fix with CA bundle, never disable TLS |

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
    Q -->|"Made improvements to<br/>a modified scaffold file"| PUSH["/scaffold-push<br/><i>Claude extracts generalizable parts</i>"]
    Q -->|"Starting a new project"| PULL["Pull latest into current project first<br/>then /init in new project"]

    style PROMOTE fill:#c8e6c9
    style STATUS fill:#e3f2fd
    style DEMOTE fill:#fff3e0
    style PUSH fill:#c8e6c9
    style PULL fill:#e3f2fd
```

---

## Appendix: Why Each Practice Exists

Every scaffold feature traces back to transformer architecture research. This table maps features to their underlying justification from `SCAFFOLD_FRAMEWORK.md`.

| Practice | Research basis |
|----------|--------------|
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
| Section-merge for CLAUDE.md/GUIDE.md | Hub methodology and documentation sync to nodes without overwriting project-specific identity and local features. |
| SCAFFOLD_FRAMEWORK.md protection | Research source material is foundational — changes only under paradigm shifts, preserving the reasoning behind every design decision. |

<!-- NODE-SPECIFIC-START -->
<!-- Everything above is managed by the scaffold hub and updated via /scaffold-pull. -->
<!-- Everything below is specific to this project. Add project-specific commands, rules, workflows here. -->

## Project-Specific Features

_No project-specific features yet. As you add local commands, rules, agents, or skills, document them here._
