# Feature: Branch-Based Feature Lifecycle

> Feature: feature-lifecycle
> Created: 1774223875
> Status: Draft

## Summary

Formalize the feature lifecycle around git branches: multiple specs coexist in a backlog, activating one creates a named branch, work proceeds via `/commit` and concludes with `/pr`. This merges two backlog items (git workflow maturity + multi-spec pipeline) based on the insight that branches ARE the multi-spec isolation mechanism. Research at `docs/research/agentic-git-workflows.md` validates this across 12 teams — every top performer uses branch isolation, agent-prefixed naming, and mandatory human review before merge.

## Job To Be Done

**When** I have multiple features to build and want to prepare specs ahead of time,
**I want to** activate a spec from my backlog to create a feature branch, work on it with enforced commit discipline, and complete it with a structured PR,
**So that** specs don't bottleneck on a single file, git history is clean and conventional, and PRs are consistent and reviewable.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Multi-spec backlog

- [ ] **AC-1:** `docs/specs/` directory holds spec files named `<feature-id>.md`. Each spec has frontmatter with `Status: Draft | Ready | In Progress | Complete`. A script command `docs-check.sh list-specs` outputs JSON: `[{feature_id, status, created}]`.

- [ ] **AC-2:** `docs-check.sh activate <feature-id>` creates branch `claude/<type>/<feature-id>` (type extracted from spec or defaulting to `feat`), copies the spec to `docs/spec.md` on the branch, and updates the spec's status to `In Progress`. Fails if another spec is already In Progress (exit 1 with message naming the blocking spec).

- [ ] **AC-3:** `docs-check.sh complete <feature-id>` updates the spec's status to `Complete` in `docs/specs/`. Fails if the spec is not In Progress (exit 1).

- [ ] **AC-4 (edge):** `docs-check.sh list-specs` works when `docs/specs/` is empty or doesn't exist (returns `[]`).

### Branch naming

- [ ] **AC-5:** Branches created by `activate` follow the convention `claude/<type>/<feature-id>` where type is one of: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. The branch is created from the current HEAD of the default branch.

- [ ] **AC-6:** A PostToolUse hook on `Bash` warns (not blocks) when a `git checkout -b` or `git switch -c` command creates a branch not matching the `claude/<type>/<name>` pattern. Warning on stderr, exit 0.

### `/commit` command

- [ ] **AC-7:** `/commit` stages relevant files, generates a conventional commit message (`type(scope): description`) from the diff context, appends `Co-Authored-By` trailer, and creates the commit. The user sees the proposed message and can approve or edit before commit.

- [ ] **AC-8:** `/commit` runs the test suite before committing. If tests fail, the commit is blocked with the failure output shown. A `--no-test` flag bypasses this for documentation-only commits.

- [ ] **AC-9:** A PostToolUse hook on `Bash` validates that `git commit` messages follow conventional commit format (`type(scope): description` or `type: description`). Warns on non-conforming messages (exit 0, stderr message).

### `/pr` command

- [ ] **AC-10:** `/pr` pushes the current branch, creates a draft PR via `gh pr create` with a structured body: Summary (from spec), Test Plan (from test results), `Generated with Claude Code` footer. Links to the spec feature-id in the PR title.

- [ ] **AC-11:** Before creating the PR, `/pr` runs evaluation gates: test suite must pass, `docs-check.sh validate` must return `aligned`. If any gate fails, PR creation is blocked with specific failure output.

- [ ] **AC-12:** When `pr_review` is enabled in `.claude/scaffold.json`, `/pr` spawns the code-reviewer subagent (existing `/review`) after evaluation gates pass but before PR creation. If the reviewer finds CRITICAL issues, PR creation is blocked. WARN-level issues are included in the PR body under a "Review Notes" section. The user can override with `--skip-review`.

- [ ] **AC-13:** `/pr` fails with a clear message if run on the default branch (main/master) — PRs are only created from feature branches.

### Scaffold configuration

- [ ] **AC-14:** `.claude/scaffold.json` is a project-level config file with feature toggles. Initial schema: `{"features": {"pr_review": true|false, ...}}`. Missing file or missing key defaults to `false`. Scripts read it via `jq`.

- [ ] **AC-15:** `.claude/scaffold.json` is node-only (not synced from hub). Each project controls its own feature toggles. The hub provides defaults via `docs/templates/scaffold.json`.

### Assumptions tracking

- [ ] **AC-16:** When Claude makes a judgment call without explicit user guidance during a session, it writes the decision to `docs/assumptions.md` with format: `- **[topic]**: [decision made] — [why this was chosen over alternatives]`.

- [ ] **AC-17:** `/pr` includes the contents of `docs/assumptions.md` (if it exists and is non-empty) in the PR body under a "Assumptions & Decisions" section, so reviewers see what judgment calls were made.

- [ ] **AC-18:** `docs/assumptions.md` is cleared (emptied, not deleted) when a spec is completed via `docs-check.sh complete`. Assumptions are ephemeral per-feature, not accumulated.

### Worktree compatibility

- [ ] **AC-19:** `.claude/worktrees/` is added to `.gitignore` and `.claudeignore` in the scaffold template. Worktrees created by Claude Code's native `--worktree` flag inherit all scaffold configuration (CLAUDE.md, rules, hooks, settings.json) since they share the same `.git` directory.

- [ ] **AC-20:** GUIDE.md includes a "Parallel Agent Sessions" section documenting: (a) how to use `claude --worktree` with the scaffold, (b) that lockfile state is shared across worktrees (`.git` is shared), (c) that `docs/spec.md`, `docs/plan.md`, `docs/checkpoint.md` are branch-local (safe to use in parallel), (d) resource conflict warnings (ports, databases, file locks).

- [ ] **AC-21:** `docs-check.sh validate` works correctly when run from a worktree (paths resolve relative to repo root, not worktree root).

### Integration with existing workflow

- [ ] **AC-22:** `/catchup` detects and reports: (a) which spec is active on the current branch, (b) how many specs are in `docs/specs/` by status, (c) whether the current branch follows naming convention.

- [ ] **AC-23:** `docs-check.sh validate` continues to work unchanged on feature branches (spec/plan/checkpoint chain validation). On the default branch with no `docs/spec.md`, it reports `no active spec` instead of an error.

- [ ] **AC-24:** `docs-check.sh recommend` on the default branch with Ready specs in `docs/specs/` recommends `Activate a spec: docs-check.sh activate <feature-id>`.

## Affected Files

| File | Change |
|------|--------|
| `scripts/docs-check.sh` | Modified — add `list-specs`, `activate`, `complete` commands; adapt `validate`/`recommend` for multi-spec |
| `.claude/commands/commit.md` | New — `/commit` slash command |
| `.claude/commands/pr.md` | New — `/pr` slash command with optional critic review |
| `.claude/hooks/commit-msg-lint.sh` | New — conventional commit format validation hook |
| `.claude/hooks/branch-name-lint.sh` | New — branch naming convention warning hook |
| `.claude/scaffold.json` | New — project-level feature toggles (node-only, not synced) |
| `docs/templates/scaffold.json` | New — default scaffold config template |
| `.claude/settings.json` | Modified — add hook entries for new hooks |
| `.claude/commands/catchup.md` | Modified — add multi-spec awareness |
| `.gitignore` | Modified — add `.claude/worktrees/` |
| `.claudeignore` | Modified — add `.claude/worktrees/` |
| `GUIDE.md` | Modified — add "Parallel Agent Sessions" section |
| `docs/templates/assumptions.md` | New — assumptions file template |
| `tests/feature-lifecycle.bats` | New — tests for activate, complete, list-specs, config, worktree compat |
| `docs/specs/` | New directory — backlogged specs |

## Dependencies

- **Requires:** `docs-check.sh` (existing), `gh` CLI (for PR creation), `bats` (for testing)
- **Blocked by:** Nothing

## Out of Scope

- Worktree creation/management tooling (Claude Code's native `--worktree` is sufficient; scaffold ensures compatibility, not replacement)
- Workflow engine / state machine beyond what `docs-check.sh recommend` already provides (ZWR-20)
- GitHub Agentic Workflows / `gh-aw` integration (ZWR-21)
- Auto-merge or CI integration (human review mandatory per research consensus)
- Linear integration for spec state (ZWR-19)

## Implementation Notes

- **Branch = isolation.** On a feature branch, `docs/spec.md`, `docs/plan.md`, `docs/checkpoint.md` work exactly as today. Zero changes to the on-branch workflow. The new capability is managing specs on the default branch + creating/completing branches.
- **`activate` copies, doesn't move.** The spec stays in `docs/specs/` (status updated) and is also copied to `docs/spec.md` on the new branch. This means `docs/specs/` is always the source of truth for spec states.
- **Hook pattern:** PostToolUse (not PreToolUse) for commit and branch validation — warn, don't block. Developers may have legitimate reasons to deviate. The warning creates awareness without friction.
- **Research validation:** Branch naming matches GitHub Copilot's `copilot/*` pattern (strong evidence). Draft PRs with human review match universal consensus (12/12 teams). Conventional commits match QuantumBlack's semantic commit pattern.
- **Test strategy:** `tests/feature-lifecycle.bats` — test `list-specs`, `activate`, `complete` with fixture specs in `mktemp -d`. Commit/PR commands tested via integration tests that mock `gh` and `git`.
- **Assumptions.md is lightweight.** No frontmatter, no tooling beyond append and clear. The value is surfacing decisions in PRs — the file is just a list. Cleared on `complete`, not archived (assumptions are meaningful only in review context, not historically).
- **Worktree compatibility is mostly free.** Since worktrees share `.git`, all hooks, settings, and scaffold config are inherited automatically. The main risk is `docs-check.sh` using paths that assume repo root = working directory. Test this explicitly (AC-21).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
