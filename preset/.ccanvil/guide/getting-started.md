# Getting Started

## First-time setup (once per machine)

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

## Starting a new project

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

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
