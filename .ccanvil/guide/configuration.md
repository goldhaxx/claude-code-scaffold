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

**Validator behavior (BTS-386).** `bash module-manifest.sh validate --json` scans `.claude/rules/*.md` and emits:

- `info[].rule-tier-budget-exceeded` — tier-0 rule whose whole-file token estimate (char-count / 4) exceeds 150. Advisory only; status stays `ok` (so existing consumers don't see false-alarm drift). Exit 0 by default; `--strict` flag escalates to exit 2.
- `drift[].rule-frontmatter-malformed` — rule with malformed YAML frontmatter. Block-shape: always exit 2 with status=`drift`.
- `info[].frontmatter-missing` — rule without frontmatter. Advisory only; the validator continues with the back-compat default envelope.

The `info` array is always present in the JSON envelope (empty when no info entries). Status is `drift` only when block-shape entries exist in `drift[]`; warn-shape signal lives in `info[]` and is the discoverable "atomization needed" list without blocking PR finalize.

### Stacks declaration (BTS-385)

`.claude/ccanvil.json` accepts a top-level `stacks:` array declaring the project's tech stacks (e.g. `["bats"]`, `["jest", "playwright"]`, `["pytest"]`). Defaults to `["any"]` when absent. Future Tier-1 skill loaders will use this to conditionally load stack-specific skills (`tdd-bats`, `tdd-jest`, etc.) — the field is declarative for now; substrate enforcement ships in a follow-up.

### Hub describes behavior, node describes implementation (BTS-460)

Hub-shipped rules, skills, and hooks describe *behavior* (run the test suite, check the lint, etc.); node-local config (`.claude/ccanvil.json`) describes *implementation* (which tool actually runs). A substrate dispatcher reads the config and forwards to the right runner. This keeps the same hub content working correctly across bats / pytest / vitest / jest / go nodes without per-node forks or tool names leaking through universal rules.

**First concrete instance — test-suite dispatch:**

`.claude/ccanvil.json` accepts an optional top-level `test-provider:` string (`bats`, `pytest`, `vitest`, `jest`, `go`, ...). Resolution order: explicit `test-provider`, then `stacks[0]`, then literal default `bats`.

```jsonc
{
  "test-provider": "bats",       // optional — explicit wins
  "stacks": ["bats"]              // fallback when test-provider absent
}
```

Hub rule cites the verb, not the tool:

```
Run `bash .ccanvil/scripts/docs-check.sh test-suite-run --project-dir . --parallel --progress`.
```

Dispatcher (`cmd_test_suite_run` in `docs-check.sh`) resolves the provider and runs the runner. `bats` and `pytest` are implemented; remaining providers exit 2 with an explicit `dispatcher not yet implemented` message — the contract is intentionally fail-loud so missing implementations surface at /pr time rather than silently no-op'ing.

**pytest nodes** set `test-provider: pytest` plus two node-local keys — the interpreter path and test directory are node-specific, so they cannot live in the hub:

```jsonc
{
  "test-provider": "pytest",
  "test-command": ".venv/bin/python -m pytest",  // required — how this node runs pytest
  "test-path": "src/"                             // optional — where its tests live
}
```

`test-command` runs inside the project dir (so relative venv/test paths resolve); `test-path` is appended when present, else pytest uses its own discovery. `test-command` is word-split on whitespace into the interpreter + arguments, so its tokens (including the interpreter path) must not themselves contain spaces. The dispatcher translates `--parallel` to pytest-xdist's `-n auto` and treats the bats-only flags (`--json`, `--timings`, `--progress`, `--slow-top`, `--no-telemetry`) as no-ops. A missing `test-command` is a loud exit-2 dispatch error; pytest exit 5 (no tests collected) is normalized to a failing exit so the /pr gate never reads it as a false green. The OTel healthcheck is currently gated to the `bats` provider — BTS-559 extends it to pytest once non-bats test-observability tooling exists.

**Leak-site inventory (captured follow-up).** As of BTS-460's ship, the following hub-shared content still references tool names directly. Each is a candidate for the same indirection treatment when the friction surfaces:

- `.claude/rules/tdd.md` — bats-specific verbiage (`strict-mode bats`, `bats-report.sh`). Indirect via `test-provider` or rewrite to "the project's test runner".
- `.claude/skills/stasis/SKILL.md` — line 131 hardcodes `bats-report.sh --parallel` for the post-stasis tests count. Migrate to the dispatcher.
- `.ccanvil/guide/command-reference.md` — bats-specific entries for `bats-report.sh` / `bats-lint.sh`. Keep as-is for hub developers; downstream consumption is mediated by skills.

Other axes that may want the same dispatcher pattern (when friction surfaces, not before): linter, formatter, package manager, build tool.

### Canonical example-data SSOT (BTS-482)

`.ccanvil/fixtures/canonical-example-data.json` is the hub-shipped source of truth for fake user data used in downstream-node test fixtures. The substrate's design principle: keep CI alerts loud by ensuring every CI red is a real signal, and silence false positives at the data level (not by relaxing detector thresholds).

`security-audit.sh`'s email scanner already auto-allowlists addresses matching the RFC 2606 reserved namespace (`@example.com`, `@example.org`, `@example.net`) and the `noreply@` prefix. Test fixtures that use ad-hoc fakes (`a@b.com`, `z@z.com`, `x@y.com`) match the email-shaped pattern but NOT the reserved namespace, so they flag as MEDIUM PII findings and fail CI. The SSOT documents the canonical addresses, names, and IDs every downstream node should use; following it keeps fixtures auto-allowlisted with no per-node `.security-audit-allowlist` configuration.

```jsonc
{
  "version": 1,
  "emails": [
    {"address": "alice@example.com", "context": "primary user fixture"},
    {"address": "bob@example.org",   "context": "secondary user fixture"},
    {"address": "charlie@example.net", "context": "tertiary user fixture"}
  ],
  "names":    [{"first": "Alice", "last": "Example"}, ...],
  "user_ids": [10001, 10002, 10003],
  "domains":  ["example.com", "example.org", "example.net", "test", "invalid"]
}
```

**Resolution at the substrate layer.** No code reads the SSOT at audit time today — the security-audit script's existing regex (`@example\.(com|org|net)`) is the enforcement point. The SSOT is the *declarative* counterpart: it tells fixture authors which exact values to use. A drift-guard that scans test files for non-canonical example data (failing CI when a fixture uses `a@b.com` instead of `alice@example.com`) is the Phase B follow-up (BTS-483) — keeps alerts loud by surfacing fixture-hygiene drift as a real CI failure.

**The pattern this enables.** Every false-alert surface in ccanvil (workspace-fence heredoc, guard-workspace slash-prefix, shape-gate narrative cascade) has the same shape: a guard fires on a string that *looks* like the dangerous pattern but is *known-safe*. The right answer is never "lower the threshold"; it's "declare the known-safe shape in an SSOT both the guard and the author reference." Phase B unifies that pattern across guards.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
