# Feature: init-mature-project — safe retrofit for existing repos

> Feature: init-mature-project
> Created: 1776809739
> Status: Draft

## Summary

`/ccanvil-init` was written assuming the target is a fresh, empty directory with no git history. The real universe of ccanvil targets spans five distinct project shapes, and today only the greenfield case works correctly. This spec adds deterministic project-mode detection, mode-aware preflight defaults, CLAUDE.md delimiter insertion for projects that lack them, mode-conditional git lifecycle behavior, skip-if-exists guards on lifecycle docs, idempotency for already-initialized projects, and a new `retrofit-check` preview subcommand — all backed by comprehensive per-mode bats coverage and updated documentation. After this ships, `/ccanvil-init` can be run safely against a mature repo like docint without clobbering node-specific rules, re-running `git init`, or destroying in-progress work.

## Job To Be Done

**When** I invoke `/ccanvil-init` in a mature git repository with established source, custom CLAUDE.md rules, and possibly pre-existing docs artifacts,
**I want to** retrofit the ccanvil preset without destroying my existing rules, re-initializing git, or overwriting in-progress lifecycle docs,
**So that** I can adopt ccanvil incrementally on established projects with the same confidence I have when initializing a fresh one.

## Acceptance Criteria

### Project-mode detection

- [ ] **AC-1:** `ccanvil-sync.sh init-preflight <hub>` detects the project's mode via deterministic checks and emits `project_mode` as a top-level field in the output JSON. Modes: `fresh`, `source-no-git`, `mature-repo`, `partial-ccanvil`, `already-initialized`.
- [ ] **AC-2:** Detection rules are:
  - `already-initialized` → `.ccanvil/ccanvil.lock` exists AND `.ccanvil/scripts/ccanvil-sync.sh` exists
  - `partial-ccanvil` → any of `.claude/`, `.ccanvil/`, or `CLAUDE.md` exists AND no lockfile
  - `mature-repo` → `.git/` exists AND at least one commit reachable from HEAD AND no partial-ccanvil markers beyond what's expected from a non-ccanvil project
  - `source-no-git` → no `.git/` AND at least one tracked source file (excluding `.DS_Store`, `.gitignore`, `README.md`)
  - `fresh` → everything else
- [ ] **AC-3:** Mode detection is pure — it reads filesystem/git state only, writes nothing.

### Mode-aware per-file defaults

- [ ] **AC-4:** Preflight output's per-file `recommended_action` respects project mode. When mode is `mature-repo` or `partial-ccanvil`:
  - `CLAUDE.md` with different hub/local content AND existing delimiters → `section-merge`
  - `CLAUDE.md` with different hub/local content AND no delimiters → `section-merge-create-delimiters` (new action)
  - `README.md`, `CONTRIBUTING.md` with different hub/local content → `skip` (keep local), regardless of delimiter presence
  - `docs/spec.md`, `docs/plan.md`, `docs/stasis.md`, `docs/roadmap.md` that exist locally with non-template content → `skip` with reason "local file has node-specific content"
  - `.github/workflows/ci.yml` that exists locally → `review` (user choice — CI configs are too project-specific for a default)
- [ ] **AC-5:** When mode is `fresh` or `source-no-git`, the existing recommendations stand (no change from current behavior).

### CLAUDE.md delimiter insertion

- [ ] **AC-6:** New `init-apply` action `section-merge-create-delimiters`: on a mature-repo CLAUDE.md without delimiters, insert `<!-- HUB-MANAGED-START -->` (and `<!-- HUB-MANAGED-END -->` if the hub's template has a paired closer), fold existing content into the node section (above the start delimiter), and append the hub section below. Result preserves all pre-existing local content verbatim while making future section-merges possible.
- [ ] **AC-7:** Running `section-merge-create-delimiters` a second time is a no-op (delimiters already exist → falls through to standard `section-merge`).

### Mode-aware git lifecycle

- [ ] **AC-8:** `/ccanvil-init` skill reads `project_mode` from preflight output and branches:
  - `fresh`, `source-no-git` → run `git init` then commit `chore: initialize project with ccanvil preset`
  - `mature-repo`, `partial-ccanvil` → skip `git init`, commit `chore(ccanvil): retrofit preset onto existing project`
  - `already-initialized` → offer update-mode (see AC-15); do not commit an init commit
- [ ] **AC-9:** Pre-push hook install is conditional: if `.git/hooks/pre-push` already exists AND its contents differ from `hub/templates/github/pre-push`, log a warning and skip; otherwise install.

### Skip-if-exists for lifecycle docs

- [ ] **AC-10:** Step 7 of the init flow (create placeholder `docs/*.md`) never overwrites an existing file. For each of `docs/spec.md`, `docs/plan.md`, `docs/stasis.md`, `docs/roadmap.md`: if the file exists AND is non-empty, log "PRESERVED: <path>" and skip. If empty or missing, copy from `.ccanvil/templates/`.
- [ ] **AC-11:** **Edge: existing docs/stasis.md has feature metadata.** When a mature repo has `docs/stasis.md` with a `> Feature: <id>` header, the skill reports "detected in-progress feature: <id>" in the post-init summary so the user knows their work is preserved.

### Idempotency / already-initialized handling

- [ ] **AC-12:** When `project_mode == already-initialized`, `/ccanvil-init` does NOT proceed with the standard flow. Instead, it offers three options:
  - **Update from hub** → runs `ccanvil-sync.sh pre-check` + `pull-plan` + auto-applies safe updates (equivalent to `/ccanvil-pull` for non-conflict files)
  - **Re-register with hub** → `ccanvil-sync.sh register` only (refreshes registry entry)
  - **Abort** → exit without changes
- [ ] **AC-13:** The already-initialized path never runs `git init` and never writes a `chore:` initialization commit.

### Report-first, apply-second

- [ ] **AC-14:** `/ccanvil-init` skill presents the preflight result as a rendered table with columns: **File** | **Hub** | **Local** | **Action** | **Reason**. Mode is printed as a header above the table: "Detected mode: **mature-repo**". User approves, edits actions (any `review` entry or overriding a default), or aborts before any write happens.
- [ ] **AC-15:** New subcommand `ccanvil-sync.sh retrofit-check <hub>` runs `init-preflight` and prints a human-readable report to stdout — exactly the same table the skill would show, but without launching the skill. Exit 0 always (it's a read-only preview). Used for dry-runs outside a Claude Code session.

### Bats coverage per mode

- [ ] **AC-16:** New `hub/tests/init-mode-detection.bats` covers each of the 5 modes with a fixture project, asserting the correct `project_mode` value is emitted by `init-preflight`.
- [ ] **AC-17:** New `hub/tests/init-mature-retrofit.bats` covers the end-to-end mature-repo path: fixture mature repo with custom CLAUDE.md (no delimiters), run preflight, verify action recommendations, run init-apply, verify CLAUDE.md has delimiters + hub content + original content preserved, verify no `git init` ran, verify retrofit commit message.
- [ ] **AC-18:** New `hub/tests/init-idempotent.bats` covers the already-initialized path: fixture project with existing lockfile, verify preflight emits `already-initialized`, verify update-mode is offered, verify re-run doesn't corrupt state.
- [ ] **AC-19:** Existing `hub/tests/init-preflight.bats` + `init-apply.bats` continue to pass unchanged (backward compatibility for `fresh` mode).

### Documentation

- [ ] **AC-20:** `README.md` gains a "Retrofitting an existing project" section under "Quick Start" explaining the mature-repo flow.
- [ ] **AC-21:** `hub/meta/HOW_TO_USE.md` adds a "Adding ccanvil to an existing project" subsection.
- [ ] **AC-22:** `.ccanvil/guide/command-reference.md` gains a `retrofit-check` row and notes `/ccanvil-init` mode-awareness.
- [ ] **AC-23:** `global-commands/ccanvil-init.md` skill file is rewritten to reflect the new flow (mode detection, conditional git, interactive plan review). Bats test verifies the skill file references `project_mode`, `retrofit-check`, and conditional `git init`.

### Error / edge cases

- [ ] **AC-24:** **Error: preflight in uninitialized git repo fails gracefully.** When mode is `mature-repo` but `git log` has zero commits (initialized but never committed), classify as `source-no-git` instead so we don't try to classify a bare repo as mature.
- [ ] **AC-25:** **Error: CLAUDE.md delimiter insertion on a file with content resembling delimiters but not matching.** If `<!-- HUB-MANAGED` appears in local CLAUDE.md as part of prose (not as a delimiter line), do NOT treat as an existing delimiter. Match on exact line `<!-- HUB-MANAGED-START -->` only (no leading whitespace, no trailing content).
- [ ] **AC-26:** **Edge: mature repo with no source files but has `.git/`.** Classify as `mature-repo` if `.git/` + `git log -1` succeeds, regardless of source file count — the history itself is the signal worth preserving.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — `cmd_init_preflight` adds mode detection; `cmd_init_apply` handles new `section-merge-create-delimiters` action; new `cmd_retrofit_check`; dispatch entry |
| `global-commands/ccanvil-init.md` | Modified — mode-aware flow, conditional git lifecycle, idempotency path, plan review table |
| `.ccanvil/guide/command-reference.md` | Modified — add `retrofit-check` row, note `/ccanvil-init` mode-awareness |
| `README.md` | Modified — "Retrofitting an existing project" section |
| `hub/meta/HOW_TO_USE.md` | Modified — "Adding ccanvil to an existing project" subsection |
| `hub/tests/init-mode-detection.bats` | New — AC-1 through AC-3, AC-24, AC-26 |
| `hub/tests/init-mature-retrofit.bats` | New — AC-4 through AC-11, AC-17, AC-25 |
| `hub/tests/init-idempotent.bats` | New — AC-12, AC-13, AC-18 |
| `hub/tests/ccanvil-init-skill.bats` | New — AC-23 grep assertions on the skill file content |

## Dependencies

- **Requires:** existing `init-preflight`, `init-apply`, `section-merge`, `ccanvil.lock` infrastructure.
- **Blocked by:** none.

## Out of Scope

- **Rollback / transaction semantics.** If an apply fails partway, user recovers manually via `git checkout`. Adding transactional init is complex and the error rate is already low.
- **Stack auto-detection.** Detecting `package.json`/`pyproject.toml` etc. and suggesting a stack profile is scope creep — `ccanvil-sync.sh stack-apply` exists as a separate step.
- **Multi-hub support.** Completely orthogonal.
- **Migrating existing `docs/specs/*.md`** into the hub-managed form. Users keep their spec backlog as-is.
- **Auto-resolving existing hooks/CI conflicts.** Those remain `review` actions — too project-specific to pick a default.
- **Non-Git VCS support** (hg, svn). Ccanvil is git-specific by construction.

## Implementation Notes

- Mode detection goes at the top of `cmd_init_preflight` before the per-file classify loop. Emit `project_mode` as a sibling to `plan` and `summary` in the output JSON.
- `classify_file` grows a `$project_mode` parameter; mature/partial modes override defaults per AC-4 rules.
- `section-merge-create-delimiters` reuses `cmd_section_merge` logic: write existing file content as node section, append hub template content below the start delimiter. Bash-only, no sed trickery for the delimiter insertion (line-based awk is simpler).
- The `/ccanvil-init` skill branches early on `project_mode`. The table rendering is stochastic (skill presents, user approves) — the underlying preflight data is deterministic.
- `retrofit-check` is a thin wrapper that calls `init-preflight` with `--report` and formats the output as a table. Reuses the same table format the skill uses internally (single source of truth).
- For AC-25's delimiter detection, use `grep -qx '<!-- HUB-MANAGED-START -->' <file>` — the `-x` flag matches the whole line, rejecting prose mentions.
- For AC-26, `git log -1` on a bare-init repo returns exit 128 with "does not have any commits yet" — test that condition as the tiebreaker between `mature-repo` and `source-no-git`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
