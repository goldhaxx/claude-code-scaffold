# Implementation Plan: Branch-Based Feature Lifecycle

> Feature: feature-lifecycle
> Created: 1774226113
> Spec hash: 6e87cc6f
> Based on: docs/spec.md

## Objective

Implement multi-spec backlog, branch naming, `/commit`, `/pr`, scaffold config, assumptions tracking, and worktree compatibility — 24 ACs across 7 groups.

## Sequence

### Step 1: Scaffold config foundation (AC-14, AC-15)
- **Test:** Write tests that `.claude/scaffold.json` is readable via jq helper, missing file returns defaults, missing key returns `false`, invalid JSON exits with error.
- **Implement:** Create `docs/templates/scaffold.json` with `{"features": {"pr_review": false}}`. Add a `scaffold_config_get` helper function to `docs-check.sh` that reads `.claude/scaffold.json` with fallback defaults. Create `.claude/scaffold.json` for this project.
- **Files:** `docs/templates/scaffold.json`, `.claude/scaffold.json`, `scripts/docs-check.sh` (add helper), `tests/feature-lifecycle.bats` (new file)
- **Verify:** `bats tests/feature-lifecycle.bats` — config reads succeed, defaults work, missing file handled

### Step 2: `list-specs` command (AC-1, AC-4)
- **Test:** Write tests: `list-specs` with populated `docs/specs/` returns JSON array with feature_id/status/created; empty dir returns `[]`; missing dir returns `[]`.
- **Implement:** Add `cmd_list_specs` to `docs-check.sh`. Iterate `docs/specs/*.md`, call `parse_metadata` on each, collect into JSON array. Update dispatch case.
- **Files:** `scripts/docs-check.sh`, `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/feature-lifecycle.bats` — list-specs tests pass

### Step 3: `activate` command (AC-2, AC-5)
- **Test:** Write tests: `activate` creates branch with correct name, copies spec to `docs/spec.md`, updates status in `docs/specs/` to "In Progress"; fails if another spec is already In Progress; fails if feature-id doesn't exist; branch name follows `claude/<type>/<feature-id>` convention.
- **Implement:** Add `cmd_activate` to `docs-check.sh`. Parse spec metadata for type (default `feat`), check no other spec is In Progress (scan `docs/specs/`), create branch via `git checkout -b`, copy spec file to `docs/spec.md`, update status in `docs/specs/<id>.md` via sed.
- **Files:** `scripts/docs-check.sh`, `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/feature-lifecycle.bats` — activate tests pass, branch naming verified

### Step 4: `complete` command (AC-3, AC-18)
- **Test:** Write tests: `complete` updates status to "Complete"; clears `docs/assumptions.md` if it exists; fails if spec is not In Progress; fails if feature-id doesn't exist.
- **Implement:** Add `cmd_complete` to `docs-check.sh`. Verify spec exists and is In Progress, update status to "Complete", truncate `docs/assumptions.md` (write empty string, preserve file).
- **Files:** `scripts/docs-check.sh`, `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/feature-lifecycle.bats` — complete tests pass

### Step 5: Adapt `validate` and `recommend` for multi-spec (AC-23, AC-24, AC-17)
- **Test:** Write tests: `validate` on default branch with no `docs/spec.md` returns `"no-active-spec"` instead of error; `validate` on feature branch works unchanged (existing tests still pass); `recommend` on default branch with Ready specs suggests `activate`.
- **Implement:** Modify `cmd_validate` to handle missing `docs/spec.md` gracefully — check if on default branch, if so return `{result: "no-active-spec"}`. Modify `cmd_recommend` to check `docs/specs/` for Ready specs when no active spec. Default branch detection: `git symbolic-ref refs/remotes/origin/HEAD` with fallback to main/master.
- **Files:** `scripts/docs-check.sh`, `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/` — all existing tests still pass, new multi-spec tests pass

### Step 6: Branch naming hook (AC-6)
- **Test:** Write tests: hook receives `git checkout -b bad-name` → warns on stderr, exits 0; hook receives `git checkout -b claude/feat/my-feature` → no warning, exits 0; hook ignores non-branch-creation commands.
- **Implement:** Create `.claude/hooks/branch-name-lint.sh`. PostToolUse hook on Bash — parse tool input for `git checkout -b` or `git switch -c`, extract branch name, regex match against `^claude/(feat|fix|refactor|test|docs|chore)/`. Warn on stderr, always exit 0.
- **Files:** `.claude/hooks/branch-name-lint.sh`, `.claude/settings.json` (add hook entry), `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/feature-lifecycle.bats` — hook tests pass, `bash -n .claude/hooks/branch-name-lint.sh` passes

### Step 7: Commit message lint hook (AC-9)
- **Test:** Write tests: hook receives `git commit -m "feat(auth): add login"` → no warning, exits 0; hook receives `git commit -m "fixed stuff"` → warns on stderr, exits 0; hook ignores non-commit commands.
- **Implement:** Create `.claude/hooks/commit-msg-lint.sh`. PostToolUse hook on Bash — parse tool input for `git commit`, extract message from `-m` flag, regex match against `^(feat|fix|refactor|test|docs|chore|perf)(\(.+\))?: .+`. Warn on stderr, always exit 0.
- **Files:** `.claude/hooks/commit-msg-lint.sh`, `.claude/settings.json` (add hook entry), `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/feature-lifecycle.bats` — hook tests pass, `bash -n .claude/hooks/commit-msg-lint.sh` passes

### Step 8: `/commit` command (AC-7, AC-8)
- **Test:** Manual verification — slash commands are Claude prompts, not testable scripts. Verify the command file covers: staging, message generation, co-authored-by, test run, `--no-test` bypass.
- **Implement:** Create `.claude/commands/commit.md`. Instructions: 1) run `git diff --stat` and `git diff --cached --stat`, 2) if `--no-test` not passed, run test suite and block on failure, 3) stage relevant files, 4) generate conventional commit message from diff, 5) show user for approval, 6) commit with `Co-Authored-By` trailer.
- **Files:** `.claude/commands/commit.md`
- **Verify:** Read the command file, confirm it covers AC-7 and AC-8.

### Step 9: `/pr` command (AC-10, AC-11, AC-12, AC-13, AC-17)
- **Test:** Manual verification. Verify instructions cover: evaluation gates, optional critic review via scaffold.json, branch check, structured PR body with assumptions, feature-id in title.
- **Implement:** Create `.claude/commands/pr.md`. Instructions: 1) verify not on default branch (AC-13), 2) run test suite — block on failure (AC-11), 3) run `docs-check.sh validate` — block if not aligned (AC-11), 4) read `.claude/scaffold.json` for `pr_review` toggle — if true and no `--skip-review`, spawn code-reviewer subagent (AC-12), 5) read `docs/assumptions.md` if exists (AC-17), 6) push branch with `-u`, create draft PR via `gh pr create` with structured body (AC-10).
- **Files:** `.claude/commands/pr.md`
- **Verify:** Read the command file, confirm all ACs covered.

### Step 10: Assumptions template and `/catchup` update (AC-16, AC-22)
- **Test:** Verify template exists with correct format. Verify `/catchup` instructions reference multi-spec awareness.
- **Implement:** Create `docs/templates/assumptions.md` with format guide. Update `.claude/commands/catchup.md` to add steps: check current branch naming convention, run `docs-check.sh list-specs` to report spec backlog counts, identify active spec on current branch.
- **Files:** `docs/templates/assumptions.md`, `.claude/commands/catchup.md`
- **Verify:** Read files, confirm format and instructions are complete.

### Step 11: Worktree compatibility (AC-19, AC-20, AC-21)
- **Test:** Write tests: `docs-check.sh validate` resolves paths correctly when run from a subdirectory or worktree. Test `.gitignore` and `.claudeignore` contain `.claude/worktrees/`.
- **Implement:** Add `.claude/worktrees/` to `.gitignore` and `.claudeignore`. Audit `docs-check.sh` for hardcoded path assumptions — ensure `docs_dir` resolves relative to git repo root via `git rev-parse --show-toplevel`. Add "Parallel Agent Sessions" section to GUIDE.md hub section documenting worktree usage with the scaffold.
- **Files:** `.gitignore`, `.claudeignore`, `scripts/docs-check.sh` (path resolution), `GUIDE.md`, `tests/feature-lifecycle.bats`
- **Verify:** `bats tests/` — all tests pass including worktree path resolution

### Step 12: Documentation update (GUIDE.md, CLAUDE.md)
- **Test:** No test — documentation only.
- **Implement:** Update GUIDE.md hub section: add `/commit` and `/pr` to command reference tables, add multi-spec workflow diagram, add `scaffold.json` to configuration layers, add assumptions.md to working documents. Update CLAUDE.md hub section: add `docs-check.sh list-specs|activate|complete` to commands block, add `docs/specs/` to architecture. Update README if it references docs structure.
- **Files:** `GUIDE.md`, `CLAUDE.md`, `README.md` (if needed)
- **Verify:** Read updated sections, confirm accuracy.

## Risks

- **`docs-check.sh` complexity:** Adding 3 commands + modifying 2 existing ones to a ~580-line script. Mitigation: each command is self-contained with its own function. Consider extracting multi-spec commands to a separate script if it exceeds ~800 lines.
- **Hook false positives:** PostToolUse hooks fire for ALL bash commands. Hooks must parse tool input carefully to only trigger on relevant git commands. Mitigation: strict regex on command string, exit 0 for anything unrecognized.
- **Default branch detection:** Determining "am I on the default branch" requires knowing the branch name (main vs master vs other). Mitigation: `git symbolic-ref refs/remotes/origin/HEAD` with fallback to checking both `main` and `master`.
- **`activate` on dirty worktree:** Creating a branch with uncommitted changes could cause issues. Mitigation: `activate` should run a cleanness check before branching.
- **Slash command testability:** `/commit` and `/pr` are markdown prompt files, not scripts — they can't be unit tested. Mitigation: the deterministic parts (hooks, evaluation gates, config reads) are testable scripts. The commands are verified by reading for completeness.

## Definition of Done

- [ ] All 24 acceptance criteria from spec pass
- [ ] All existing tests still pass (188 current + new)
- [ ] No syntax errors (`bash -n` on all scripts and hooks)
- [ ] Code reviewed (run /review)
- [ ] GUIDE.md and CLAUDE.md updated to reflect new commands and workflow
- [ ] Linear issue ZWR-10 updated

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
