# Configuration Layers

## What goes where

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

**The principle:** Use hooks for things that must ALWAYS happen (formatting, security). Use rules and CLAUDE.md for things requiring judgment (coding patterns, conventions). Use skills/agents for workflows that only activate sometimes. See `hooks.md` for the deterministic-first hierarchy.

## Hooks (`.claude/hooks/`)

Hook scripts live in `.claude/hooks/` and are referenced from `settings.json`. They receive JSON on stdin and control behavior via exit codes.

| Hook | Event | Script | What it does |
|------|-------|--------|-------------|
| File protection | PreToolUse (Write\|Edit\|MultiEdit) | `protect-files.sh` | Blocks writes to `.env`, credentials, `foundations.md`, `node_modules/`, `dist/`, `generated/` |
| Syntax lint | PostToolUse (Write\|Edit\|MultiEdit) | `lint-on-write.sh` | Validates syntax: bash -n for .sh, jq for .json, yaml check for .yaml. Blocks on errors. |
| Auto-format | PostToolUse (Write\|Edit\|MultiEdit) | `format-on-write.sh` | Runs project formatter (uncomment for your stack: Prettier, Black, gofmt, etc.) |

## Rules (loaded at launch)

| Rule file | Concern | Key behaviors enforced |
|-----------|---------|----------------------|
| `deterministic-first.md` | Architecture | Use scripts/hooks over Claude reasoning for computable operations; hierarchy: hook → script → slash command → pure reasoning |
| `tdd.md` | Testing | Red-green-refactor cycle, test naming, fix implementation not tests |
| `workflow.md` | Sessions | One objective per session, `/stasis` before `/compact`, delegate research, stop after 2 failures |
| `code-quality.md` | Code | Follow existing patterns, typed errors, pin dependencies, intent-revealing names |
| `tls-troubleshooting.md` | Certs | Auto-detect WARP cert errors, fix with CA bundle, never disable TLS |
| `self-review.md` | Meta | Flag stochastic interventions during stasis runs and reviews; lightweight always-on version of `/ccanvil-audit` |

### Rule frontmatter (BTS-385)

Rule files MAY declare top-level frontmatter peer to the existing `manifest:` block:

```yaml
---
tier: 0          # 0 = atom (always-on, ≤150 token target); 1 = skill; 2 = reference
scope: universal # universal | substrate | hub-only (composes with BTS-384 distribution filter)
stack: any       # any | bats | jest | pytest | ... (composes with ccanvil.json stacks declaration)
anchors:
  apply: []          # skill paths to load when applying the rule (Tier-1)
  evidence: []       # reference docs explaining rationale + war stories (Tier-2)
  related-rules: []  # peer rule files
manifest:
  ...                # existing manifest block (drift-detection)
---
```

Atomized rules trim the body to the directive layer and route operational detail to the `anchors.evidence` reference doc. Files without frontmatter default to `tier=0 scope=universal stack=any anchors={}` (back-compat preserved).

Resolve a rule's bundle: `bash docs-check.sh rule-resolve <rule-id> --project-dir .` returns `{rule, tier, scope, stack, anchors, body_path}`.

### Stacks declaration (BTS-385)

`.claude/ccanvil.json` accepts a top-level `stacks:` array declaring the project's tech stacks (e.g. `["bats"]`, `["jest", "playwright"]`, `["pytest"]`). Defaults to `["any"]` when absent. Future Tier-1 skill loaders will use this to conditionally load stack-specific skills (`tdd-bats`, `tdd-jest`, etc.) — the field is declarative for now; substrate enforcement ships in a follow-up.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
