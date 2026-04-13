# Session Management

Sessions should be short and focused. The preset provides tools for preserving and resuming state.

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
        COMPACT["/compact<br/><i>compress context</i>"]
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
    COMMIT --> COMPACT

    COMPACT -->|"Next session"| RESUME

    style NEW fill:#e3f2fd,stroke:#333,stroke-width:2px
    style RESUME fill:#e3f2fd,stroke:#333,stroke-width:2px
    style COMPACT fill:#e3f2fd,stroke:#333,stroke-width:2px
    style STUCK fill:#fffde7
    style LONG fill:#fffde7
```

## What `/catchup` reads

When you run `/catchup` after `/compact` (or `/clear`), Claude reads these sources to orient:

| Source | Purpose |
|--------|---------|
| `docs/checkpoint.md` | What was accomplished, blockers, next steps |
| `git log --oneline -10` | Recent commits |
| `git diff --stat` | Uncommitted changes |
| `git diff --cached --stat` | Staged changes |
| `docs/spec.md` | Current feature specification |

It reports the state but does NOT start implementing. You say "Continue" when ready.

## When to reset context

| Situation | Action |
|-----------|--------|
| Finished a feature | `/compact` → start fresh |
| Switching to a different task | Checkpoint → `/compact` → new task |
| Session feels slow or confused | Checkpoint → `/compact` → `/catchup` → "Continue" |
| After ~30 minutes of complex work | Checkpoint → `/compact` |
| Context at ~60% | `/compact` proactively |
| Completely unrelated new task | `/clear` for full reset (rare) |

**Why aggressive compaction works:** `/compact` preserves a compressed summary of the conversation, reducing cold-start penalty when resuming. Structured prompts preserve 92% fidelity through compaction vs 71% for narrative prompts. Use `/clear` only when you want a truly blank slate.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
