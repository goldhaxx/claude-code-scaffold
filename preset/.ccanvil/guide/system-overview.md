# System Overview

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
        T1[".ccanvil/templates/spec.md"]
        T2[".ccanvil/templates/plan.md"]
        T3[".ccanvil/templates/checkpoint.md"]
    end

    subgraph "Reference Documents (synced)"
        GUIDE[".ccanvil/guide/<br/><i>hub + node sections</i>"]
        FRAMEWORK[".ccanvil/guide/scaffold-framework.md<br/><i>research — read-only</i>"]
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

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
