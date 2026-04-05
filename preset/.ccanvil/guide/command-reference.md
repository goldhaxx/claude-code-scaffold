# Command Reference

## Feature Development Commands

| Command | Phase | What it does | Files affected |
|---------|-------|-------------|----------------|
| *"Describe feature"* | Spec | Triggers spec-writer agent | Writes `docs/specs/<id>.md` |
| `/plan` | Plan | Creates ordered TDD steps from spec | Writes `docs/plan.md` |
| *"Start building"* | Build | Enters TDD cycle | Source + test files |
| `/commit` | Build | Stages, generates conventional commit, runs tests | Git history |
| `/review` | Review | Spawns code-reviewer sub-agent | None (read-only) |
| `/pr` | Ship | Creates draft PR with evaluation gates | GitHub PR |

## Session Management Commands

| Command | When | What it does |
|---------|------|-------------|
| `/catchup` | After `/clear` | Reads checkpoint + git state, reports status |
| *"Checkpoint this"* | Pausing work | Writes state to `docs/checkpoint.md`, commits |
| `/clear` | Between tasks | Resets context (built-in) |
| `/compact` | Context heavy | Summarizes context to free space (built-in) |
| `/cost` | Monitoring | Shows token usage (built-in) |

## Scaffold Sync Commands

| Command | Direction | What it does |
|---------|-----------|-------------|
| `/ccanvil-status` | Read-only | Shows sync state of all tracked files |
| `/ccanvil-pull` | Hub → Project | Pulls updates, resolves conflicts |
| `/ccanvil-push` | Project → Hub | Pushes generalizable changes upstream |
| `/ccanvil-promote <file>` | Project → Hub | Promotes a local file to the scaffold |
| `/ccanvil-demote <file>` | Local | Marks a scaffold file as local override |
| `/ccanvil-ignore <file>` | Local | Marks file as node-only (permanently excluded from sync) |

## Utility Commands

| Command | What it does |
|---------|-------------|
| `/ccanvil-audit` | Analyzes scaffold for stochastic-to-deterministic improvement opportunities. Calls `manifest-check.sh check` for deterministic README verification. Includes permissions audit and context budget check. |
| `/fix-certs` | Diagnoses and repairs Cloudflare WARP TLS certificate issues |
| `/init` | Initializes a new project from the scaffold (global command) |

## Permissions Audit Scripts

| Command | What it does |
|---------|-------------|
| `permissions-audit.sh check [--settings-dir DIR] [--log FILE]` | Classify all Bash permission entries as DANGER/UNREVIEWED/REVIEWED → JSON |
| `permissions-audit.sh check --text [--verbose]` | Human-readable grouped report (DANGER, UNREVIEWED, optionally REVIEWED) |
| `permissions-audit.sh init [--settings-dir DIR] [--log FILE]` | Create/update decision log with stubs for unreviewed entries |

## Context Budget Scripts

| Command | What it does |
|---------|-------------|
| `context-budget.sh check` | Measure token cost of always-loaded scaffold files → JSON |
| `context-budget.sh check --text` | Human-readable table with per-file tokens and budget status |
| `context-budget.sh check --model MODEL_ID` | Set context window from known model (e.g., `claude-opus-4-6[1m]` → 1M) |
| `context-budget.sh check --context-window N` | Set context window size directly (overrides `--model`) |
| `context-budget.sh check --budget N` | Override budget ceiling directly (overrides `--context-window` and `--model`) |

## Operations Routing Scripts

| Command | What it does |
|---------|-------------|
| `operations.sh resolve <operation> [--project-dir DIR]` | Resolve operation to provider/mechanism/invocation JSON based on `.claude/scaffold.json` routing config. Returns local bash adapter when no config exists. |

## Multi-Spec Lifecycle Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh list-specs [docs-dir]` | List all specs in `docs/specs/` with feature_id, status, created → JSON array |
| `docs-check.sh activate <feature-id> [docs-dir]` | Create branch `claude/<type>/<id>`, copy spec to `docs/spec.md`, set status to In Progress |
| `docs-check.sh complete <feature-id> [docs-dir]` | Set spec status to Complete, clear `docs/assumptions.md` |
| `docs-check.sh config-get <key> [project-dir]` | Read feature toggle from `.claude/scaffold.json` (returns `true`/`false`) |

## Manifest Verification Scripts

| Command | What it does |
|---------|-------------|
| `manifest-check.sh parse <readme>` | Parse markdown tables → JSON `[{path, description}]` |
| `manifest-check.sh check-existence <readme>` | Check which paths exist on disk, discover untracked files |
| `manifest-check.sh init <readme>` | Create `.claude/manifest.lock` with file hashes + git commit |
| `manifest-check.sh hash-check` | Compare current hashes against lockfile → verified/stale |
| `manifest-check.sh extract-identity <file>` | Extract identity metadata (comment headers, frontmatter, headings) |
| `manifest-check.sh check <readme>` | Full report: verified + stale (with diffs) + missing + untracked (with identity) |
| `manifest-check.sh verify <paths...>` | Update lockfile entries for confirmed paths |

## Docs Lifecycle Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh status [docs-dir]` | Extract metadata (feature_id, hashes, timestamps) from spec/plan/checkpoint → JSON |
| `docs-check.sh validate [docs-dir]` | Check alignment: `aligned`, `stale-plan`, `stale-checkpoint`, `mismatched`, `unlinked`, `missing-determinism-review` |
| `docs-check.sh recommend [docs-dir]` | State machine → `{next_action, reason}` (e.g., "Run /plan", "Ready to build") |
| `docs-check.sh audit-session [--since commit] [repo-dir]` | Scan git diffs for stochastic patterns (cp, jq, shasum, git -C, curl, wget) + commit messages for indicator phrases → JSON |

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
