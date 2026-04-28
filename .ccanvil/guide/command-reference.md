# Command Reference

## Feature Development Commands

| Command | Phase | What it does | Files affected |
|---------|-------|-------------|----------------|
| `/spec <description>` | Spec | Writes feature spec with acceptance criteria | Writes `docs/specs/<id>.md` |
| `/activate <id>` | Activate | Wraps `docs-check.sh activate` + dispatches the `AUTO-TRANSITION` intent — flips the linked Linear issue to In Progress via `ticket.transition`. BTS-149: enqueue-on-failure-only — script no longer pre-enqueues, skill enqueues only on MCP failure (eliminates write+ack churn on every activate). | Branch, draft PR, Linear issue status |
| `/permissions-review` | Triage | BTS-149: walks user through `permissions-audit.sh promote-review` candidates (DELETE/TRIAGE) and `check` DANGER entries (lacking `accept_danger`) one row at a time. Collects per-row decisions as JSONL and dispatches via `permissions-audit.sh apply --decisions`. No silent mutations; every row confirmed. Idempotent: `No candidates to review.` when both lists empty. | `settings.json`, `settings.local.json`, `permissions-audit.log.json` |
| `/plan` | Plan | Creates ordered TDD steps from spec | Writes `docs/plan.md` |
| *"Start building"* | Build | Enters TDD cycle | Source + test files |
| `/commit` | Build | Stages, generates conventional commit, runs tests | Git history |
| `/review` | Review | Spawns code-reviewer sub-agent | None (read-only) |
| `/pr` | Ship | Creates draft PR with evaluation gates | GitHub PR |
| `/land` | Post-merge | Wraps `docs-check.sh land` + auto-closes the linked Linear issue via `ticket.transition` (BTS-119). On MCP failure, queues to `.ccanvil/ideas-pending.log` for `/idea sync`. | Local + remote branch deletion, Linear issue status |

## Session Management Commands

| Command | When | What it does |
|---------|------|-------------|
| `/recall` | After `/compact` or `/clear` | Reads `docs/stasis.md` + git state, reports status |
| `/stasis` | End of session, before `/compact` | Strategic review — writes state + determinism/security/cross-session review to `docs/stasis.md`, commits |
| `/compact` | Between tasks | Compresses context, retains summary (built-in) |
| `/clear` | Full reset (rare) | Resets context entirely (built-in) |
| `/compact` | Context heavy | Summarizes context to free space (built-in) |
| `/cost` | Monitoring | Shows token usage (built-in) |

## Sync Commands

| Command | Direction | What it does |
|---------|-----------|-------------|
| `/ccanvil-status` | Read-only | Shows sync state of all tracked files |
| `/ccanvil-pull` | Hub → Project | Pulls updates, resolves conflicts |
| `/ccanvil-push` | Project → Hub | Pushes generalizable changes upstream |
| `/ccanvil-promote <file>` | Project → Hub | Promotes a local file to the hub |
| `/ccanvil-demote <file>` | Local | Marks a hub file as local override |
| `/ccanvil-ignore <file>` | Local | Marks file as node-only (permanently excluded from sync) |
| `ccanvil-sync.sh broadcast [--dry-run]` | Hub → All nodes | Pushes auto-updates to all registered nodes in one pass |
| `ccanvil-sync.sh broadcast-resolve-auto [--dry-run]` | Node-side | BTS-116: algorithmic resolution of `.claude/ccanvil.json` conflicts. Emits JSON with `resolution: take-hub \| keep-local \| requires-review \| no-conflict` and the inputs (`hub_hash`, `local_hash`). Auto-applies via `pull-apply` when deterministic (content-identical → take-hub; local-superset-of-hub → keep-local); exits 3 with `divergent_keys` / `removed_keys` when manual review is needed |

## Utility Commands

| Command | What it does |
|---------|-------------|
| `/ccanvil-audit` | Analyzes configuration for stochastic-to-deterministic improvement opportunities. Calls `manifest-check.sh check` for deterministic README verification. Includes permissions audit and context budget check. |
| `/fix-certs` | Diagnoses and repairs Cloudflare WARP TLS certificate issues |
| `/ccanvil-init` | Initializes a new project from the ccanvil hub, or retrofits it onto an existing project. Mode-aware: detects one of five `project_mode` values (fresh, source-no-git, mature-repo, partial-ccanvil, already-initialized) and branches its behavior. Mature-repo mode preserves `CLAUDE.md`, git history, and in-progress lifecycle docs. |
| `ccanvil-sync.sh retrofit-check <hub>` | Read-only dry-run of `/ccanvil-init` — prints the detected mode and the per-file plan (File / Hub / Local / Action / Reason) without modifying anything. |

## Permissions Audit Scripts

| Command | What it does |
|---------|-------------|
| `permissions-audit.sh check [--settings-dir DIR] [--log FILE]` | Classify all Bash permission entries as DANGER/UNREVIEWED/REVIEWED → JSON. BTS-143: a permission that trips a DANGER pattern reclassifies as REVIEWED (with `matched_pattern` + `risk_accepted: true` preserved) when its log entry has `accept_danger: true` AND all four required fields (`risk`, `rationale`, `efficiency_justification`, `reviewer`) are filled. Without `accept_danger`, DANGER pattern matches stay DANGER. |
| `permissions-audit.sh check --text [--verbose]` | Human-readable grouped report. Sections: DANGER, UNREVIEWED, REVIEWED (risk-accepted) — always visible, REVIEWED — verbose-only. Risk-accepted entries display the `[matched_pattern]` AND `[risk-accepted]` annotation so the deliberate override is auditable. |
| `permissions-audit.sh init [--settings-dir DIR] [--log FILE]` | Create/update decision log with stubs for unreviewed entries. The schema includes `accept_danger: boolean` (default false) — set to `true` for deliberate broad-wildcard rationales (BTS-143). |
| `permissions-audit.sh promote-review [--settings-dir DIR] [--text]` | BTS-144: list `settings.local.json` entries not in `settings.json` and classify each (DELETE / TRIAGE) for systematic review. Deterministic rules: redundant (covered by broader `Bash(<word>:*)` wildcard) → DELETE, `preset/` dead-path → DELETE, env-prefix bypass with broadly-allowed underlying verb (e.g., `Bash(ALLOW_OUTSIDE_WORKSPACE=1 bash ...)` when `Bash(bash:*)` exists in main) → DELETE, otherwise → TRIAGE. JSON output: `{candidates: [{permission, source, recommendation, reason}], counts: {delete, promote, triage, total}}`. Exit 0 always — read-only review tooling. |
| `permissions-audit.sh apply --decisions <jsonl> [--settings-dir DIR] [--log FILE]` | BTS-149: atomic mutation substrate consumed by `/permissions-review`. Reads JSONL of `{permission, decision}` records (one per line). Decision verbs: `delete` (remove from `settings.local.json`), `promote` (move to `settings.json`, idempotent), `keep-local` (no-op, counted as skipped), `accept-danger` (write log entry with `accept_danger:true` + 4 required fields). Pre-flight validates all lines before any mutation; unknown decision/missing fields → exit 2 with no mutation. Backup `.bak` files created before mutating; ERR trap restores on any failure (exit 3). Refuses to run if stale `.bak` files exist. Output envelope: `{applied, skipped, errors}`. |
| `permissions-audit.sh decision-append --buffer FILE --permission PERM --decision delete\|promote\|keep-local\|accept-danger [--risk R --rationale RA --efficiency E --reviewer RV]` | BTS-159: atomic single-decision writer. Validates inputs against the same pre-flight schema as `apply --decisions`, constructs the JSON line via `jq` (never hand-assembled), appends with POSIX `O_APPEND` for line-atomicity. Replaces the Write+cat+rm dance Claude was running per row. The four extra flags (`--risk`, `--rationale`, `--efficiency`, `--reviewer`) are required for `--decision accept-danger` and silently ignored for the other decisions. Exit 0 success, 2 validation failure (no buffer write on failure). |
| `permissions-audit.sh entry-context <permission> [--settings-dir DIR]` | BTS-161: deterministic per-row context for `/permissions-review` walk. JSON output: `{permission, source_files, matched_pattern, matched_hooks, introduced_in}`. `source_files` lists which settings file(s) contain the permission, sorted. `matched_pattern` reuses `cmd_check`'s `check_danger` for round-trip stability. `matched_hooks` is a heuristic leading-verb scan against `.claude/hooks/*.sh`, filtered to gate-context lines (`=~`, `case`, `*)`) so pure invocations don't pollute the result. `introduced_in` is the first commit that introduced the permission string into either settings file via `git log -S`. Exit 0 always; exit 2 only when the positional arg is missing. |

## Security Audit Scripts

| Command | What it does |
|---------|-------------|
| `security-audit.sh [--files-only] [--history-only] [--json]` | Scan tracked files and git history for secrets, PII, emails, and dangerous file types. Exit 0 clean, 1 with findings, 2 on bad allowlist. `--files-only` skips history scan; `--history-only` skips file scan; `--json` emits structured findings. |
| `.security-audit-allowlist` (config) | Project-local allowlist. Two formats (BTS-152): `<file-substring>` (legacy, silences ALL findings in matched files) or `<file>::<category>::<detail-substring>` (per-finding triple — silences only matching category + detail substring in matched files). Empty `<category>` or `<detail-substring>` acts as a wildcard. Empty `<file-substring>` is rejected. Categories: `secret`, `pii`, `email`, `dangerous-file`. Lines starting with `#` and blank lines ignored. Malformed triples (≠ 3 segments) cause a load-time error with line number. |

## Test Hygiene Scripts

| Command | What it does |
|---------|-------------|
| `bats-lint.sh <dir-or-file>` | Flag bats `@test` blocks with ≥2 sequential `jq -e` assertions and no `set -e` at the top — the leak pattern where only the last `jq -e` governs the test's exit code (BTS-127). Exit 0 clean, 1 if any leaks found (file:line to stderr), 2 on usage error. Convention doc: `.claude/rules/tdd.md`. |
| `bats-report.sh [--parallel] [--json] [--timings] [--slow-top N] [<bats-args>...]` | Run the bats suite exactly once and emit structured output (BTS-118). Replaces the 3×-invocation pattern (`bats \| tail; bats \| grep ok; bats \| grep not ok`). `--parallel` uses `bats --jobs N` where `N = max(2, cpu/2)`; requires `brew install parallel` on macOS. Falls back to serial with `WARN:` when parallel is missing. `--json` emits `{ok, not_ok, total, tail, raw_exit, timings}`. `--timings` (BTS-137) adds `bats -T` and appends a sorted per-test timing table (slowest first). `--slow-top N` (BTS-137) shows only the N slowest; N must be a non-negative integer. Default target `hub/tests/`; exit mirrors bats exit (exit 2 on invalid args). |

## Context Budget Scripts

| Command | What it does |
|---------|-------------|
| `context-budget.sh check` | Measure token cost of always-loaded configuration files → JSON |
| `context-budget.sh check --text` | Human-readable table with per-file tokens and budget status |
| `context-budget.sh check --model MODEL_ID` | Set context window from known model (e.g., `claude-opus-4-6[1m]` → 1M) |
| `context-budget.sh check --context-window N` | Set context window size directly (overrides `--model`) |
| `context-budget.sh check --budget N` | Override budget ceiling directly (overrides `--context-window` and `--model`) |

## Operations Routing Scripts

| Command | What it does |
|---------|-------------|
| `operations.sh resolve <operation> [--project-dir DIR]` | Resolve operation to provider/mechanism/invocation JSON based on `.claude/ccanvil.json` routing config. Returns local bash adapter when no config exists. |
| `operations.sh resolve work.resolve <ref> [--project-dir DIR]` | Resolve a work reference to `{provider, id, slug, url}`. Accepts bare IDs (`BTS-130`, `idea-29`) or explicit prefixes (`linear:BTS-130`, `local:idea-29`). Provider-routed: bare IDs use `integrations.routing.work` (fallback: `integrations.routing.idea`); explicit prefix overrides. Exits non-zero on empty input. |
| `operations.sh resolve ticket.transition <id> <role> [--project-dir DIR]` | Resolve a Linear ticket state transition to an MCP `save_issue` payload with `id` + `state` pre-populated from the configured `integrations.providers.linear.state_ids.<role>` UUID. Roles: `triage`, `backlog`, `icebox`, `canceled`, `duplicate`, `done`. Example: `operations.sh resolve ticket.transition BTS-128 done` → `{invocation.params: {id: "BTS-128", state: "<done-uuid>"}}`. Exits non-zero on unknown role, missing args, unconfigured role UUID, or when called on a local-provider node. |
| `operations.sh resolve ticket.find-by-title "<title>" [--exact] [--project-dir DIR]` | Resolve a ticket-title search to an MCP `list_issues` invocation + a client-side jq filter template (BTS-129). Output shape: `{invocation: {tool:"list_issues", params:{project, team, query}}, client_filter:{mode, jq_template, title_arg}}`. Callers dispatch the MCP tool, then apply the template with `jq --arg title "$(echo "$resolution" \| jq -r '.client_filter.title_arg')" -e "$template"` on the result — safe quoting by construction (the title is a jq variable, never interpolated into the expression source). Use `client_filter.title_arg` as the `--arg title` value; `invocation.params.query` is the same string and either works. Default: case-insensitive substring match. `--exact`: case-sensitive equality. Filter output shape: `[{id, title, status, url}]`; `status` may be `null` when the raw response lacks both top-level `.status` and nested `.state.name` (dedup still returns the match — losing matches over a missing status would defeat the primitive). Filter handles both wrapped Linear MCP shape (`{issues:[...]}`) and bare-array input. Local-provider nodes resolve to a bash command returning `[]` — no Linear backend means no tickets to find, so `exec` succeeds with an empty result for a uniform calling convention. |

**Work identity schema (BTS-130):** Every spec, plan, and feature-kind stasis carries a `> Work: <provider>:<id>` metadata line — the canonical coordination key linking lifecycle docs to their provider source-of-truth (Linear ticket, local JSONL UID, future GitHub/Jira/etc.). The validator aligns on `Work:` equality when all participating docs carry it; falls back to `feature_id` alignment when any doc lacks it (legacy grandfather). Stasis gains a `> Kind: feature | session` discriminator — session-kind stasis (ambient, written between features) is excluded from feature alignment entirely, structurally preventing the BTS-120 "validate halt on session-boundary stasis" trap. Feature-ids derive as `<slug>-<kebab-name>` where slug comes from the work ref (lowercased, filesystem-safe), so the substring appears in branch names and satisfies Linear's GitHub-integration auto-linker.

## Registry & Node Identity

| Command | What it does |
|---------|-------------|
| `ccanvil-sync.sh register` | Register the current project in the hub. Generates a stable UUID at first run (stored in `.claude/ccanvil.local.json`, mirrored in lockfile). Registry is keyed by UUID; path stored in `~`-portable form |
| `ccanvil-sync.sh registry` | List all registered downstream projects with UUID, name, path, last-synced info |
| `ccanvil-sync.sh broadcast` | Iterate registered nodes by UUID (auto-migrates legacy path-keyed entries). Reports `STALE` when a UUID's path no longer exists |
| `ccanvil-sync.sh events [--event T] [--node N] [--since EPOCH]` | Print hub's audit log as newline-delimited JSON. Events: `register`, `broadcast_sync`, `migrate_legacy_keys`. Filter by type, node uuid/name, or minimum timestamp |

Node UUIDs make registration resilient to renames, moves, machine changes, and multi-user setups. The UUID is authoritative; paths self-update on each sync.

`register` and `broadcast` never commit to the hub repo. The registry (`.ccanvil/registry.json`) is gitignored machine-local state, and operational events are appended to `.ccanvil/events.log` (also gitignored). Use `ccanvil-sync.sh events` to query the audit trail. Bootstrap commits in nodes (for the node-side UUID file) still happen because `.claude/ccanvil.local.json` is intentionally tracked per-node.

## Global Commands Sync

| Command | What it does |
|---------|-------------|
| `ccanvil-sync.sh pull-globals [--force]` | Copy hub's `global-commands/ccanvil-*.md` to `~/.claude/commands/`. Conflict-safe: differing local files are reported with diffs, not overwritten. `--force` overwrites conflicts |
| `/ccanvil-pull-globals` | Skill wrapper — runs the script and summarizes results |

Only files matching `ccanvil-*.md` are hub-owned; all other files in `~/.claude/commands/` are user-owned and never touched by ccanvil. This keeps ccanvil as a bolt-on, not a replacement for your Claude Code setup.

### Claude Code scheduled-task boundary (BTS-168)

Claude Code's `/loop` and `/schedule` features emit `.claude/scheduled_tasks*` artifacts inside the project root. These are **session-local** — they don't survive `/compact` reliably and aren't committable state. ccanvil gitignores them by default. ccanvil does not provide a durable cron substrate; recurring work that must survive sessions belongs in **Linear (or the local idea queue)**, surfaced via `/idea triage` and `/radar`, not in scheduled-task state files.

## Multi-Spec Lifecycle Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh list-specs [docs-dir]` | List all specs in `docs/specs/` with feature_id, status, created → JSON array |
| `docs-check.sh activate <feature-id> [--force-sync] [docs-dir]` | Create branch `claude/<type>/<id>`, copy spec to `docs/spec.md`, set status to In Progress, push branch, create draft PR. Pre-flight: invokes `cmd_sync_check` — halts if local main is ahead OR behind `origin/main` (BTS-122). `--force-sync` bypasses the check; `--force-local-ahead` is a silent legacy alias. Also halts if target branch already exists locally or working tree has uncommitted non-spec files. |
| `docs-check.sh complete <feature-id> [docs-dir]` | Set spec status to Complete, remove lifecycle docs (spec/plan/stasis), commit cleanup, mark PR ready |
| `docs-check.sh pr-cleanup [docs-dir]` | Pre-merge lifecycle cleanup invoked by the `/pr` skill. When `docs/spec.md` exists, delegates to `cmd_complete` (flips archive to Complete + removes lifecycle docs + commits). Otherwise, removes any lingering lifecycle docs and commits a "clean up lifecycle docs before merge" commit. Halts non-zero on metadata parse failure or missing archive — `/pr` surfaces the error instead of proceeding. |
| `docs-check.sh land [--force]` | On feature branch: switch to main, fetch, reset to origin, delete local and remote branch. Safety net: if the landed branch matches `claude/<type>/<id>` and `docs/specs/<id>.md` is still `In Progress`, transitions it to `Complete` + commits on main (`ALLOW_MAIN=1`) + pushes — covers the case where `/pr` was skipped. On main (post-`gh pr merge --delete-branch`): fetch and fast-forward to `origin/main`, then recover the landed branch from the last squash-merge's `(#<PR>)` suffix via `gh pr view` and emit the same `AUTO-CLOSE: {...}` marker (BTS-138). `--force` skips PR-merged check. The `/land` skill wrapper reads the marker and dispatches the Linear transition (BTS-119). |
| `docs-check.sh land-recover-branch` | BTS-138 helper: reads the current repo HEAD's last-commit subject (or `HEAD~1` if HEAD is a `docs: stasis` commit), parses the `(#<N>)` PR-number suffix, queries `gh pr view <N> --json headRefName`, and echoes the recovered branch. Empty stdout + `WARN:` on stderr + exit 0 on any recovery failure. Testable in isolation without standing up a full merge workflow. |
| `docs-check.sh extract-work <spec-file>` | Reads `> Work:` metadata from a spec file; emits `{"provider":"<p>","id":"<i>"}` on stdout. Empty stdout + exit 0 for legacy specs without `Work:` or malformed values (BTS-119 grandfather rule). |
| `docs-check.sh auto-close-emit <branch> [docs-dir]` | Pure logic: maps a landed branch name to its archived spec's `Work:` and emits `AUTO-CLOSE: {...}` for linear provider, or a named skip log for local/unknown/non-claude-branch (BTS-119). Invoked internally by `cmd_land` after the post-merge safety net, and from `cmd_land`'s main-path recovery flow (BTS-138). |
| `docs-check.sh auto-transition-emit <branch> <role> [docs-dir]` | Pure logic: maps an active branch name to its spec's `Work:` and emits `AUTO-TRANSITION: {...}` for linear provider (BTS-136). BTS-149: marker is the sole side effect — no pre-enqueue. The `/activate` skill enqueues to `.ccanvil/ideas-pending.log` only on MCP failure via `idea-pending-append`. Silent for local/unknown/non-claude-branch. Invoked internally by `cmd_activate`. |
| `docs-check.sh sync-check <repo-root>` | Fetches `origin/main` (5s timeout), then compares local `main` against the refreshed ref. Exit codes: 0 synced or no-op (no origin, no origin/main, or fetch failed with graceful `WARN:`), 1 ahead (unpushed leak risk), 2 behind (stale baseline). Called by `cmd_activate` (BTS-122). |
| `docs-check.sh pr-guard` | Pre-`/pr` safety net (BTS-122). Fetches `origin/main` from the current feature branch and halts with remediation if the base has moved past HEAD (exit 1). No-op (exit 0) when no origin remote, no origin/main ref, or fetch failure (`WARN:` emitted). Invoked from the `/pr` skill's pre-flight block. |
| `docs-check.sh config-get <key> [project-dir]` | Read feature toggle from `.claude/ccanvil.json` (returns `true`/`false`) |

## Idea Management Scripts

The `/idea` skill routes captures through `operations.sh` based on the node's provider config (`integrations.routing.idea` in `.claude/ccanvil.local.json`). Default: gitignored `.ccanvil/ideas.log` (JSONL). Opt-in: Linear Triage via MCP. The scripts below back the local provider and expose the primitives the skill orchestrates for the Linear path. `/idea` never commits to git and never creates a branch.

| Command | What it does |
|---------|-------------|
| `docs-check.sh idea-add "<body>" [--title TITLE] [project-dir]` | Append a JSONL entry to `.ccanvil/ideas.log` (local provider). `--title` defaults to body when omitted (short-text fast path). |
| `docs-check.sh idea-list [--status <status>] [project-dir]` | List ideas as JSON array. Default view excludes `icebox`, `canceled`, `duplicate` (and legacy `parked`, `dismissed`, `merged`). Explicit `--status <x>` accepts five-state vocab (`triage`, `backlog`, `icebox`, `canceled`, `duplicate`) and legacy aliases (`new`, `promoted`, `parked`, `dismissed`, `merged`). |
| `docs-check.sh idea-count [project-dir]` | Count ideas by status → JSON `{total, triage, backlog, icebox, canceled, duplicate, icebox_stale_count, new, promoted, parked, dismissed, merged}`. Legacy counters retained for back-compat; legacy entries fold into the corresponding new-vocab counter. |
| `docs-check.sh idea-update <uid> <status> [project-dir]` | Update an entry's status by UID. Accepts five-state vocab + legacy aliases. Unknown status values are rejected. |
| `docs-check.sh idea-review-icebox [project-dir]` | List Icebox entries (status `icebox` or legacy `parked`) older than 60 days. Feeds `/idea review-icebox` and the `/radar` ambient icebox-stale surface. |
| `docs-check.sh idea-migrate-state [project-dir]` | One-shot translation of legacy status vocab (`new`/`promoted`/`parked`/`dismissed`/`merged`) to new vocab (`triage`/`backlog`/`icebox`/`canceled`/`duplicate`) in `.ccanvil/ideas.log`. Timestamped backup preserved (`ideas.log.YYYYMMDD-HHMMSS.bak`). Idempotent: re-running on a migrated log reports `0 entries migrated`. |
| `docs-check.sh idea-sync [--ack <ts>] [project-dir]` | Enumerate-only primitive: without args → emit `{pending, entries}` from `.ccanvil/ideas-pending.log`. With `--ack <ts>` → remove matching pending entry (operator-callable for manual recovery). BTS-179: replay dispatch moved to `idea-pending-replay`; `idea-sync` is no longer on the `/idea sync` hot path. |
| `docs-check.sh idea-pending-replay [--project-dir <dir>]` | BTS-179: deterministic substrate replay primitive. Iterates every entry in `.ccanvil/ideas-pending.log`, dispatches each by `op` via the http substrate (resolves `idea.add` or `ticket.transition`, eval's the resolved command), ack's on success, preserves on failure. Emits `{synced, failed, pending, entries}` JSON. Exit 0 when failed=0; non-zero otherwise. Replaces the per-skill shell loop in `/idea sync` that tripped on echo-then-jq round-trips when bodies contained JSON-escaped `\n`. |
| `docs-check.sh refresh-plan-hash [--project-dir <dir>]` | BTS-177: recompute `docs/spec.md`'s `content_hash` and rewrite `docs/plan.md`'s `> Spec hash:` metadata line to match. Idempotent — re-running when hashes already match emits `{updated:false, ...}` no-op. Atomic rewrite via `mktemp`+`mv`. Errors with non-zero exit when spec/plan absent or plan missing the `> Spec hash:` line. Eliminates the manual hand-edit Claude was performing on mid-flow scope expansion (BTS-175 incident, 2026-04-25). |
| `docs-check.sh assert-pr-title <pr-number> [--project-dir <dir>]` | BTS-178: read live PR title via `gh pr view`, compute expected `feat(<feature-id>): <first-summary-line>` from `docs/spec.md` (or `docs/specs/<feature-id>.md` post-cleanup), and force-update via `gh pr edit` when the title is placeholder-shaped (`feat(auth-system)`, `feat(default)`) or missing the `feat(<feature-id>):` prefix. No-op when prefix already matches. Wired into `/pr` after `gh pr ready` so the squash-merge commit on main always carries the correct subject. Errors when spec absent or `gh` CLI unavailable. |
| `docs-check.sh idea-migrate [--extract\|--finalize] [project-dir]` | Move legacy `docs/ideas.md` entries to `.ccanvil/ideas.log`, `git rm` the source, update `.gitignore`. `--extract` emits JSONL intents for skill-level Linear dispatch; `--finalize` does the filesystem cleanup alone. Idempotent. |
| `docs-check.sh idea-setup --provider local\|linear [--team TEAM --project PROJECT] [project-dir]` | One-shot per-node scaffolder. Deep-merges `integrations.routing.idea` + `integrations.providers.linear` into `.claude/ccanvil.local.json` and adds the `.gitignore` entries. Idempotent; safe to re-run to change providers. |
| `docs-check.sh idea-upgrade --provider local\|linear [--team TEAM --project PROJECT] [--from-legacy] [--create-project] [--dry-run] [project-dir]` | One-command downstream adoption. Wraps `idea-setup` + (optional) `idea-migrate` + a single commit. `--from-legacy` parses `docs/ideas.md`, generates concise titles via `title-from-body`, writes JSONL, and `git rm`s the source — all in the same commit as the config write. `--create-project` emits a `save_project` JSON intent on stdout for the skill layer to dispatch. `--dry-run` prints the plan without mutating. Idempotent: re-running on an already-upgraded node exits 0 with `Already upgraded`. On `--provider linear`, also prepends a `# ARCHIVE: read-only after <ISO>` header to `.ccanvil/ideas.log` so the log's archive-only role is self-documenting. |
| `docs-check.sh title-from-body "<body>" [--title-map <file>]` | Derive a concise title (≤80 chars) from an idea body. Fast-path: bodies ≤80 chars on a single line are returned verbatim. Longer/multi-line bodies go through the local `claude` CLI; when the CLI is absent, falls back to the first 80 chars of the first line. `--title-map` accepts a JSON `{body: title}` map that bypasses the stochastic path for known bodies. |
| `docs-check.sh idea-list [--include-archive] [--status <status>] [project-dir]` | On local/unconfigured nodes: returns a JSON array of ideas (filterable by status). On Linear-configured nodes: prints a pointer to `/idea list` for live queries and, with `--include-archive`, surfaces the historical local log under an `ARCHIVE:` header. |

**Provider config:** `.claude/ccanvil.json` ships Linear provider defaults (mechanism, label, statuses). Each node opts in by setting `integrations.routing.idea = "linear"` and `integrations.providers.linear.{project, team}` in its own `.claude/ccanvil.local.json` — usually via `docs-check.sh idea-upgrade`. Unconfigured nodes use the local provider.

**State-ID config:** for the Linear provider, `integrations.providers.linear.state_ids` maps lifecycle roles to Linear workflow-state UUIDs (`triage`, `backlog`, `icebox`, `canceled`, `duplicate`). `/idea` uses these IDs to dispatch triage outcomes, sidestepping the name-vs-type resolver collision that silently no-ops name-based state transitions. Lookup via `mcp__claude_ai_Linear__list_issue_statuses` once per workspace.

**Five-state lifecycle:** `Triage → Backlog / Icebox / Canceled / Duplicate`. Capture lands in Triage (Linear: resolver injects `state` from `state_ids.triage`; local log writes `status:"triage"`). `/idea triage` moves items to one of the four outcomes via state-ID mutations.

**Archive-only semantic (Linear nodes):** on nodes with `routing.idea = "linear"`, `.ccanvil/ideas.log` is read-only after `idea-upgrade`. New captures route through Linear via the `/idea` skill; `cmd_idea_add` refuses direct writes. The pending log (`.ccanvil/ideas-pending.log`) remains the MCP-failure fallback, drained by `/idea sync`.

**Migration guide:** `.ccanvil/guide/ideas-migration.md` walks a downstream node through the full migration. Prefer `idea-upgrade` for new adoptions; the 4-step manual path (`idea-setup` → `idea-migrate` → commit) remains documented under "Manual alternative".

### `linear-query.sh` (BTS-164/166 — Linear GraphQL substrate)

`.ccanvil/scripts/linear-query.sh` is the http transport layer that backs the Linear provider. It speaks GraphQL via curl + jq, authed by `LINEAR_API_KEY` (auto-sourced from `.env` per BTS-167). The resolver (`operations.sh`) returns `mechanism: http` for Linear-routed verbs and emits a complete `linear-query.sh` invocation in `.invocation.command` — consumers `eval` it.

| Subcommand | What it does |
|------------|-------------|
| `viewer` | Identity smoke test (`{ viewer { id, name } }`). |
| `list-issues [--project NAME] [--team NAME] [--state NAME-or-TYPE-or-ID] [--label NAME] [--limit N]` | List issues with name-based or ID-based filters. State filter accepts type ("triage"), name ("Triage"), or UUID. Returns `[{id, title, status, statusType, priority, createdAt, ...}]`. |
| `get-issue <ID>` | Fetch one issue including description. |
| `list-states [--team NAME]` | Workflow states for a team — returns `[{id, name, type}]`. Useful for populating `state_ids` config. |
| `list-labels [--team NAME]` / `list-teams [--name NAME]` / `list-projects [--name NAME]` | Lookup helpers — return `[{id, name, ...}]`. BTS-166's name-based create flags (`--team`, `--project`, `--labels`) call these internally to resolve NAME → ID before dispatching `save-issue`. |
| `save-issue [--id ID] [--title TITLE] [--description BODY] [--state STATE-NAME-or-ID] [--team NAME or --team-id UUID] [--project NAME or --project-id UUID] [--labels NAME[,NAME] or --label-ids UUID[,UUID]] [--priority N] [--duplicate-of UUID] [--input-json -]` | Create (no `--id`) or update (with `--id`) an issue. Mode selector by `--id`. BTS-166: `--input-json -` reads a JSON object from stdin and merges it into the input — title/description with embedded newlines, quotes, backticks, `$VAR`, `$(cmd)` round-trip without shell-quoting friction (jq owns the escaping). CLI flags layer on top, so flag values override stdin fields on collision. **BTS-228:** `--duplicate-of` is now a two-step flow — issueUpdate happens first (state/fields), then a follow-up `issueRelationCreate` (type=duplicate) fires for the relation. State-transition success is preserved even if the relation half fails (substrate emits `WARN: save-issue: relation-create-failed —` + retry recipe; exit 0). For non-duplicate relation types (`blocks`, `related`), use `create-relation` directly. |
| `create-relation --type {duplicate\|blocks\|related} --issue UUID --related UUID` | BTS-228: clean primitive wrapping `issueRelationCreate`. Returns `{id, type}` on success. Exit 2 on input validation (missing flag, unknown type), exit 3 on GraphQL errors. Use directly when you want explicit control over relation creation; `save-issue --duplicate-of` dispatches through this internally. |

**Auth:** `LINEAR_API_KEY` env var. BTS-167 auto-sources it from `.env` files walked from `$PWD` upward. Never check the key into git — `.env` files are gitignored.

**Error contract:** exit 0 success, exit 2 invalid args / missing creds, exit 3 GraphQL errors (Linear server response carried `errors[]`).

## Radar Scripts

| Command | What it does |
|---------|-------------|
| `docs-check.sh radar-gather [docs-dir]` | Collect project state as JSON: active spec, completed specs, idea counts, roadmap theme, git activity, backlog |

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

## Module Manifest Substrate (BTS-239 + BTS-240)

Layer 2 of the Dark Code framework — Self-Describing Systems. Each substrate primitive on `.ccanvil/manifest-allowlist.txt` carries a manifest block — `# @manifest` shell comment above a function (function-level), or YAML `manifest:` key inside a markdown file's frontmatter (BTS-240). Format reference: `.ccanvil/templates/manifest.md`.

| Command | What it does |
|---------|-------------|
| `module-manifest.sh extract <path>` | Parse manifest blocks from a single file → JSON array, one object per block. Branches on file extension: `.sh` reads `# @manifest` shell comment shape; `.md` reads YAML frontmatter `manifest:` key (BTS-240). Repeated keys collapse to arrays; scalar keys (`id`, `purpose`, `routes-by`) emit as plain strings. Exit 2 on missing/file-not-found/malformed-manifest. |
| `module-manifest.sh validate [--json] [--allowlist <path>]` | Walk allowlist, drift-check each entry: required keys present, `failure-mode` records parseable, declared `caller`/`depends-on` cross-checked against grep-of-source, `@failure-mode`/`@side-effect` source markers present in body. Marker checks are SKIPPED for `.md` paths (BTS-240). For `.md` targets, body grep covers everything after the closing `---` (frontmatter excluded). Emits `DRIFT: <path>:<id> reason=<class>` to stderr per drift. `--json` emits `{coverage:{covered,total}, drift:[...], status}`. Exit 0 clean / 2 drift. |
| `module-manifest.sh query '<key>:<value>'` | Substring-match filter against `.ccanvil/state/manifests.json` (regenerated lazily if mtime-stale). Returns JSON array of matching entries. Empty array on no match. Exit 0 always (2 on usage error). |
| `module-manifest.sh index` | Walk `.ccanvil/scripts/`, `.claude/hooks/`, `.claude/hooks/_lib/` (`.sh` only) PLUS `.claude/skills/<n>/SKILL.md`, `.claude/rules/*.md`, `.claude/agents/*.md`, `.claude/commands/*.md` (BTS-240), invoke `extract` per file, merge into a sorted JSON object keyed `<path>:<id>` at `.ccanvil/state/manifests.json` (gitignored). Atomic via `mv`; deterministic across runs. |

## Stack Distribution Scripts

| Command | What it does |
|---------|-------------|
| `ccanvil-sync.sh stack-list` | List available stack profiles as JSON array `[{id, description, files}]` |
| `ccanvil-sync.sh stack-apply <stack-id>` | Apply a stack profile: copy files, merge CLAUDE.md section, merge settings.json hooks, update lockfile + ccanvil.json. Idempotent — re-running patches without clobbering |
| `ccanvil-sync.sh init-preflight <hub> --stack <id>` | Include stack files in init preflight plan |

## Drift Watchdog (BTS-21)

Hub-only substrate that powers the `/drift-watchdog` skill and its launchd-scheduled `claude -p "/drift-watchdog"` entry. Read-only by construction — no registry mutations, no downstream-fs writes, no commits. See `.claude/skills/drift-watchdog/SKILL.md` for the orchestration body.

| Command | What it does |
|---------|-------------|
| `ccanvil-sync.sh drift-watchdog-list` | Emit a JSON array of drifted nodes `[{node_uuid, node_name, drift_key, paths_drifted[], commits_behind, summary}]`. Drift = `last_synced_version != current hub HEAD`. `paths_drifted` is the intersection of "paths touched in `last_synced_version..HEAD`" with the canonical tracked-pattern set (filters out hub-private paths like `hub/`, `docs/specs/`, etc.). `drift_key` = `sha256("$node_name:$paths-joined-by-newline") \| head -c 16` — used as the dedup key in Linear issue titles. Empty array when no drift. |
| `ccanvil-sync.sh drift-watchdog-preflight` | Smoke-test the watchdog's runtime dependencies. Emits JSON `{claude_p_available, linear_query_works}` (booleans). `claude_p_available` checks `command -v claude`. `linear_query_works` runs `linear-query.sh viewer` and asserts exit-0 + valid JSON. Run before relying on the next scheduled fire after a Claude Code upgrade. |
| `ccanvil-sync.sh drift-watchdog-launchd-print` | Print a complete macOS launchd `.plist` to stdout. Label `com.ccanvil.drift-watchdog`, `StartCalendarInterval` Monday 09:13 (non-:00 jitter per scheduling discipline), `ProgramArguments` invoke `claude -p "/drift-watchdog" --max-budget-usd 0.50` from the hub repo. Building block — most operators want the install wrapper below instead. |
| `ccanvil-sync.sh drift-watchdog-launchd-install [--reload]` | BTS-199: idempotent install/reload wrapper. Generates plist via `drift-watchdog-launchd-print`, lints with `plutil`, optional unload (`--reload`), copies to `~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist`, runs `launchctl load -w`, verifies via `launchctl print`. Emits `{installed, reloaded, plist_path, verified}` JSON. Exit 0 on success; 2 on lint/generation failure (refuses launchctl ops); 3 on verify failure. Operator: `ALLOW_OUTSIDE_WORKSPACE=1 bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-launchd-install --reload`. |

The skill itself uses the http substrate exclusively for issue creation (resolver-eval pattern → `linear-query.sh save-issue --label drift-watchdog`); MCP tool invocations are forbidden by drift-guards. Idempotency is enforced by parsing existing `drift-watchdog`-labeled issues for the same `drift_key` in the title before each create.

## Docs Lifecycle Scripts

> **BTS-212 — uniform flag parsing.** Every `docs-check.sh` subcommand that operates on a project root accepts `--project-dir <path>` as a flag in addition to the legacy positional `[docs-dir]` / `[project-dir]` form. Skill prose can pass `--project-dir .` mechanically across the family. Unknown flags emit `Usage:` to stderr and exit 2 — no more cryptic `dirname:` / `jq:` / `rm:` downstream-tool errors. The canonical set is the `PROJECT_TREE_SUBCOMMANDS` array near the top of `docs-check.sh`; the contract is locked in by `hub/tests/docs-check-flags.bats`.

| Command | What it does |
|---------|-------------|
| `docs-check.sh status [--project-dir <path>] [<docs-dir>]` | Extract metadata (feature_id, hashes, timestamps) from spec/plan/stasis → JSON |
| `docs-check.sh validate [--project-dir <path>] [<docs-dir>]` | Check alignment: `aligned`, `stale-plan`, `stale-stasis`, `mismatched`, `unlinked`, `missing-determinism-review` |
| `docs-check.sh legacy-refs-scan [--respect-allowlist <path>] [project-dir]` | Scan for legacy references (`/catchup`, `/checkpoint`, `docs/checkpoint.md`, etc.) → JSON. Scope: `hub-owned` vs `node-specific`. `--respect-allowlist <path>` (BTS-132) pre-filters matches against ERE patterns in `<path>` (same format as `hub/tests/legacy-refs-allowlist.txt`) — comments (`^#`) and blank lines skipped. Exit 1 if any post-filter matches remain; exit 2 if allowlist file is missing. |
| `docs-check.sh evidence-scan-session [--since <commit>] [--project-dir <path>] [--input-json <file>] [--no-time-filter]` | BTS-201: scan session captures (via `idea.list` resolver, or canned `--input-json` for tests) for bug-shape titles missing the four evidence anchors (`Command:`, `Output:`, `Exit:`, `Reproduce:`). Returns `{evidence_gaps:[{id,title,reason}], scanned:N, fallback?:"24h"}`. `DIAGNOSE:`-titled captures are exempt; `--since` falls back to a 24h window when unresolvable. Invoked by `/stasis`; protocol documented in `.claude/rules/evidence-required-for-captures.md`. |
| `docs-check.sh recommend [docs-dir]` | State machine → `{next_action, reason}` (e.g., "Run /plan", "Ready to build") |
| `docs-check.sh lifecycle-state [--project-dir <path>]` | BTS-20: unified envelope composing `validate` + git/marker state. Returns `{state, legal_next_actions:[{action,command,reason}], blockers:[], suggestions:[]}`. State values: `no-active-spec`, `spec-activated`, `plan-written`, `implementing`, `pr-open`, `pr-merged`, `session-wrap`, `blocked`, `uninitialized` (codified in `.ccanvil/templates/lifecycle-graph.json`). Replaces separate `validate` + `recommend` calls in `/recall`; future skill migrations land in Session-2/3 ships. Exit 2 when invoked outside a ccanvil tree (no `.ccanvil/scripts/` or no `.git/`). |
| `docs-check.sh session-info [--project-dir <path>]` | BTS-206: read session counter + ISO-8601 boundary state files. Returns `{counter:int, epoch:int|null, iso:string|null, tz:string|null}`. Source files written by the `SessionStart` hook (`.claude/hooks/session-boundary.sh`). Counter file containing non-integer reads as 0 with a stderr WARN; malformed boundary JSON reads as nulls. Always exit 0 — fault-tolerant by design. Used by `/stasis` (write side) and `/recall` (read side). |
| `docs-check.sh audit-session [--since commit] [repo-dir]` | Scan git diffs for stochastic patterns (cp, jq, shasum, git -C, curl, wget) + commit messages for indicator phrases → JSON |
| `docs-check.sh artifact-read --kind {spec\|plan\|stasis} [--feature <BTS-N>] [--stasis-kind feature\|session]` | BTS-204: provider-aware lifecycle artifact reader. Routes bash↔http per `integrations.routing.<kind>`. On local route reads `docs/<kind>.md`; on Linear route reads the corresponding Document via deterministic uuid5 derivation. Exit 0 found, 2 missing-or-not-found, 3 substrate failure. **BTS-219:** on Linear-route failure, emits a structured `WARN: artifact-read: <class>` line to stderr (one of `auth-missing` / `not-found` / `network-error` / `parse-error`) plus a copy-pasteable retry recipe. Classifier helper: `_classify_linear_failure`. |
| `docs-check.sh artifact-write --kind {spec\|plan\|stasis} --feature <BTS-N> [--stasis-kind feature\|session]` | BTS-204: provider-aware lifecycle artifact writer (stdin → routed destination). On local route writes `docs/<kind>.md`; on Linear route upserts the Document (document-updated-at pre-check + create-with-id-on-404 OR update). Pre-write concurrent-edit gate compares cached vs remote `updatedAt`; exit 4 on divergence (ALLOW_CONCURRENT_EDIT_OVERRIDE=1 to force). |
| `docs-check.sh route-of <spec\|plan\|stasis> [--project-dir <path>]` | BTS-213: public wrapper over `_lifecycle_route`. Returns `linear` or `local` for the given kind based on merged `integrations.routing.<kind>` config. Used by `/spec` to gate the artifact-write Linear dispatch (the SKILL fires `artifact-write --kind spec` only when this returns `linear`). Exit 2 on missing/invalid kind. |
| `docs-check.sh ssot-migrate --to {linear\|local} --feature <BTS-N>` | BTS-204: bidirectional, idempotent migration of lifecycle artifacts between local files and Linear Documents. Operator-driven (never auto). `--to linear` writes locals to Linear via artifact-write then removes locals on success. `--to local` materializes Linear Documents to files (does NOT trash; use `/complete` for that). |
| `linear-query.sh get-document <id-or-slug>` | BTS-204: fetch one Document. Returns `{id, title, content, slugId, url, updatedAt, createdAt, updatedBy, creator, project, issue}`. |
| `linear-query.sh save-document --input-json - [--create-with-id]` | BTS-204: create or update a Document. Auto-detects mode by stdin `.id` presence (id present → update). `--create-with-id` forces create with caller-supplied UUID for idempotent first-write. |
| `linear-query.sh document-updated-at <id>` | BTS-204: cheap projection — returns `{id, updatedAt, updatedBy}`. Used for concurrent-edit pre-checks. |
| `linear-query.sh trash-document <id>` | BTS-204: soft-delete via documentDelete. Linear has no hard-delete in public API. |
| `linear-query.sh list-documents [--project <id>] [--issue <id>] [--initiative <id>] [--limit N] [--with-content]` | BTS-204: list Documents filtered by parent. Returns array of `{id, title, slugId, updatedAt, createdAt}`. BTS-214: `--with-content` adds `content` to each node — used by `_complete_archive_linear` to batch-read all 3 lifecycle Documents in one call. **Live-validated caveat:** `DocumentFilter` rejects `{id:{in:[...]}}` ("Argument Validation Error") — `id`-list filtering is not supported by Linear's API; use `--issue <uuid>` instead. |
| `linear-query.sh document-history <id>` | BTS-204: content snapshot history. Returns `[{id, snapshotAt, actorIds}]`. |
| `linear-query.sh resolve-document-id --kind {spec\|plan\|feature-stasis\|session-stasis} --ticket <BTS-N>` | BTS-204: deterministic UUID derivation from {namespace, kind, ticket}. Pure compute — no API call. Idempotency for create-or-update writes relies on this. **BTS-216:** output is RFC 4122 v4-shaped (version nibble forced to `4`, variant nibble forced to `8`). Linear's `class-validator` `isUuid('4')` accepts ONLY v4; v3/v5 are rejected with `"id must be a UUID"`. Live-validated against api.linear.app/graphql. |

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
