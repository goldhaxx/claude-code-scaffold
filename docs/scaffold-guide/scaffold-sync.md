# Scaffold Sync System

The scaffold is a hub with downstream project nodes. The sync system enables bi-directional flow of configuration.

## Architecture

```mermaid
graph TB
    subgraph HUB["Scaffold Hub<br/>~/projects/claude-code-scaffold"]
        H_RULES["rules/"]
        H_CMD["commands/"]
        H_AGENTS["agents/"]
        H_SKILLS["skills/"]
        H_TEMPLATES["docs/templates/"]
        H_SCRIPTS["scripts/"]
        H_GUIDE["docs/scaffold-guide/<br/><i>hub sections</i>"]
        H_CLAUDE["CLAUDE.md<br/><i>hub methodology</i>"]
        H_FRAMEWORK["docs/scaffold-guide/scaffold-framework.md<br/><i>research — read-only</i>"]
    end

    subgraph NODE["Downstream Project (e.g. fucina)"]
        N_RULES["rules/<br/><i>global + local</i>"]
        N_CMD["commands/<br/><i>global + local</i>"]
        N_AGENTS["agents/"]
        N_SKILLS["skills/"]
        N_TEMPLATES["docs/templates/"]
        N_SCRIPTS["scripts/"]
        N_GUIDE["docs/scaffold-guide/<br/><i>hub + node sections</i>"]
        N_CLAUDE["CLAUDE.md<br/><i>node identity + hub methodology</i>"]
        N_FRAMEWORK["docs/scaffold-guide/scaffold-framework.md<br/><i>read-only copy</i>"]
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

## File Status Lifecycle

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

## Pull Flow (Hub → Project)

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

## Push Flow (Project → Hub)

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

## Sync Hardening: Guards and Dry-Run

Every destructive operation in the sync system is self-validating. Guards verify preconditions immediately before execution; `--dry-run` previews changes without applying them.

### Guards (exit code 3)

| Guard | Trigger | What it prevents |
|-------|---------|-----------------|
| **jq validation** | After every lockfile mutation | Corrupt JSON replacing valid lockfile |
| **Hash re-check** | `pull-apply` with `PLAN_LOCAL_HASH` env var | File modified between plan and apply phases |
| **Status re-check** | `pull-apply delete` with `PLAN_LOCAL_STATUS` env var | Deleting file whose status changed since plan |
| **Commit verification** | `pull-finalize`, `push-finalize` | Silent commit failure (HEAD unchanged) |

All guards produce: `GUARD_FAIL: <operation> on <file>: <reason>` on stderr, exit code 3.

### Dry-run mode

| Command | Flag | What it shows |
|---------|------|--------------|
| `pull-auto --dry-run` | `--dry-run` | Files that would be copied |
| `pull-apply <file> <action> --dry-run` | `--dry-run` | Action that would be applied |
| `pull-finalize --dry-run` | `--dry-run` | Commit message and file list |
| `push-apply <file> --dry-run` | `--dry-run` | File that would be pushed |
| `push-finalize <msg> --dry-run` | `--dry-run` | Commit message |

Dry-run output uses prefix: `DRY-RUN: would <verb> <file>`. Pre-check still runs (cleanness verification is not skipped).

## Promote and Demote

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

## Universal Delimiters (Section-Merge)

**Principle:** Every synced markdown file ships with a `<!-- NODE-SPECIFIC-START -->` delimiter. Hub content lives above the delimiter, node-specific customizations live below. This enables section-merge on pull — hub updates flow automatically without overwriting project customizations.

### Which files have delimiters

| Component type | Files | Delimiter | Hub section | Node section |
|----------------|-------|-----------|-------------|--------------|
| Rules | `.claude/rules/*.md` (5 files) | `NODE-SPECIFIC-START` | Universal principles, anti-patterns | Project-specific exceptions, local conventions |
| Commands | `.claude/commands/*.md` (10 files) | `NODE-SPECIFIC-START` | Workflow steps, script calls, universal rules | Project-specific paths, tools, additional steps |
| Agents | `.claude/agents/*.md` (3 files) | `NODE-SPECIFIC-START` | Role definition, output format, universal rules | Project-specific context, domain knowledge |
| Skills | `.claude/skills/*/SKILL.md` (1 file) | `NODE-SPECIFIC-START` | Methodology, phases, rules | Project test command, framework config |
| Templates | `docs/templates/*.md` (4 files) | `NODE-SPECIFIC-START` | Document structure, required sections | Project-specific fields, custom sections |
| Guide files | `docs/scaffold-guide/*.md` | `NODE-SPECIFIC-START` | Documentation, diagrams, tables | Project-specific features |
| CLAUDE.md | `CLAUDE.md` | `HUB-MANAGED-START` | Workflow, conventions, do-not rules | Project name, tech stack, commands, architecture |

**What does NOT get delimiters (and why):**

| Component type | Why not | Alternative |
|----------------|---------|-------------|
| Scripts (`*.sh`) | Can't splice bash — functions depend on each other. HTML comments aren't valid bash. | Whole-file tracked. Node customization via separate scripts or node-only fork. |
| Hooks (`*.sh`) | Same as scripts. | Stack hooks: hub provides universal hooks, node adds additional hook entries in settings.json. |
| `settings.json` | JSON has no comments. | Node-only. Hub hook scripts sync; settings.json references are node-managed. |
| `scaffold-framework.md` | Research source material — identical everywhere, no node content. | Whole-file auto-update. |

### How section-merge works

Files with delimiters have a hub-managed section and a node-specific section. During `/scaffold-pull`, the hub section is updated from the scaffold while the node section is preserved intact.

```mermaid
flowchart LR
    subgraph "Most files (rules, commands, agents, skills, templates, guide)"
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
- **scaffold-framework.md:** Auto-updated as a whole file (no delimiter, no node content).

**During `/scaffold-push`:** Node sections are always classified as project-specific and never pushed upstream.

**Legacy projects without delimiters:** The `section-merge` command gracefully handles files that don't have a delimiter yet — it treats the entire local file as node content and adds the hub section from the scaffold.

### Creating new markdown components

When adding a new rule, command, agent, skill, or template to the scaffold, **always** include the delimiter at the end:

```
<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
```

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
