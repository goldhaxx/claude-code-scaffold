# Decision Guide

## "Should I use a slash command or just talk?"

```mermaid
flowchart TD
    Q["What do you want to do?"]

    Q -->|"Start building a feature"| A1["Just describe it<br/><i>'I want the app to...'</i>"]
    Q -->|"Create an implementation plan"| A2["/plan"]
    Q -->|"Review code before committing"| A3["/review"]
    Q -->|"Resume after a break"| A4["/catchup"]
    Q -->|"Check sync state"| A5["/ccanvil-status"]
    Q -->|"Pull hub updates"| A6["/ccanvil-pull"]
    Q -->|"Share a local file globally"| A7["/ccanvil-promote file"]
    Q -->|"Fix TLS certificate errors"| A8["/fix-certs"]
    Q -->|"Session feels degraded"| A9["'Checkpoint this'<br/>→ /compact → /catchup"]

    style A1 fill:#e3f2fd
    style A2 fill:#e8f4e8
    style A3 fill:#e8f4e8
    style A4 fill:#e8f4e8
    style A9 fill:#ffcdd2
```

## "When should I checkpoint vs clear vs compact?"

```mermaid
flowchart TD
    Q["Context concern?"]

    Q -->|"Finished a feature"| COMPACT["/compact<br/><i>Compress context, start fresh</i>"]
    Q -->|"Need a break,<br/>coming back later"| CP["'Checkpoint this'<br/>→ /compact"]
    Q -->|"Context at ~60%<br/>but mid-task"| COMPACT_MID["/compact<br/><i>Summarize to free space</i>"]
    Q -->|"Session > 30 min"| CP2["'Checkpoint this'<br/>→ /compact → /catchup → 'Continue'"]
    Q -->|"Stuck after<br/>2 failed attempts"| STOP["STOP<br/>Write alternatives to checkpoint<br/>→ /compact → restart with better approach"]
    Q -->|"Completely unrelated<br/>new task"| CLEAR["/clear<br/><i>Full reset (rare)</i>"]

    style COMPACT fill:#e3f2fd
    style CP fill:#fff3e0
    style COMPACT_MID fill:#e3f2fd
    style STOP fill:#ffcdd2,stroke:#333,stroke-width:2px
    style CLEAR fill:#ffcdd2
```

## "When should I sync with the hub?"

```mermaid
flowchart TD
    Q["Sync scenario?"]

    Q -->|"Created a useful<br/>new rule/command/agent"| PROMOTE["/ccanvil-promote file<br/><i>Share with all projects</i>"]
    Q -->|"Want to check for<br/>hub updates"| STATUS["/ccanvil-status<br/><i>then /ccanvil-pull if updates exist</i>"]
    Q -->|"Push hub changes to<br/>all downstream nodes"| BCAST["ccanvil-sync.sh broadcast<br/><i>auto-updates + section-merges in one pass</i>"]
    Q -->|"Customized a hub file<br/>and want to keep my version"| DEMOTE["/ccanvil-demote file<br/><i>Prevents auto-update on pull</i>"]
    Q -->|"File is permanently<br/>project-specific"| IGNORE["/ccanvil-ignore file<br/><i>Excluded from all future sync</i>"]
    Q -->|"Made improvements to<br/>a modified hub file"| PUSH["/ccanvil-push<br/><i>Claude extracts generalizable parts</i>"]
    Q -->|"Starting a new project"| PULL["Pull latest into current project first<br/>then /init in new project"]

    style PROMOTE fill:#c8e6c9
    style STATUS fill:#e3f2fd
    style DEMOTE fill:#fff3e0
    style IGNORE fill:#ffcdd2
    style PUSH fill:#c8e6c9
    style BCAST fill:#c8e6c9
    style PULL fill:#e3f2fd
```

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
