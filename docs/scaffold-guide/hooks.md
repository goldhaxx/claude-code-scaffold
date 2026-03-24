# Hooks System

Hooks are deterministic automation that runs at Claude Code lifecycle events — outside the reasoning loop, at zero context cost. They are the foundation of the deterministic-first principle.

> **Reference:** See `docs/templates/hooks-reference.md` for the complete hook specification including JSON schemas, all event types, and writing conventions.

## How Hooks Work

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

## Deterministic-First Principle

Every operation falls somewhere on the deterministic-stochastic spectrum. The scaffold enforces this hierarchy:

```mermaid
graph TD
    subgraph "1. HOOK — zero context cost"
        H1["Block writes to .env"]
        H2["Auto-format on save"]
        H3["Protect scaffold-framework.md"]
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

## Hook vs Rule vs Skill

| Situation | Mechanism | Why |
|-----------|-----------|-----|
| "Never write to .env files" | **Hook** (PreToolUse, exit 2) | Binary file path check, zero context cost |
| "Always format code after writing" | **Hook** (PostToolUse) | Deterministic formatter, zero context cost |
| "Protect scaffold-framework.md" | **Hook** (PreToolUse, exit 2) | Binary check, enforced even if Claude forgets the rule |
| "Follow existing code patterns" | **Rule** | Requires semantic understanding of codebase |
| "Don't add unnecessary dependencies" | **Rule** | Requires judgment about "unnecessary" |
| "Run TDD red-green-refactor cycle" | **Skill** | Multi-step workflow with verification |

## Active Hooks

| Script | Event | Exit 2 blocks | What it checks |
|--------|-------|---------------|----------------|
| `protect-files.sh` | PreToolUse | Yes | `.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key`, `scaffold-framework.md`, `node_modules/`, `dist/`, `generated/`, `.git/` |
| `lint-on-write.sh` | PostToolUse | Yes | Syntax validation: `bash -n` for `.sh`, `jq empty` for `.json`, python yaml check for `.yaml`. Blocks writes with syntax errors. |
| `format-on-write.sh` | PostToolUse | No | Detects file type, runs appropriate formatter (uncomment for your stack) |

## Adding a New Hook

1. Create script in `.claude/hooks/` (use `protect-files.sh` as template)
2. `chmod +x .claude/hooks/my-hook.sh`
3. Add entry to `.claude/settings.json` under the appropriate event
4. Test: `echo '{"tool_input":{"file_path":"test.env"}}' | .claude/hooks/my-hook.sh; echo "exit: $?"`
5. Update this section and `docs/templates/hooks-reference.md`

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
