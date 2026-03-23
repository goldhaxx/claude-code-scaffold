Analyze the scaffold for opportunities to reduce stochastic surface area and increase deterministic automation.

This is a self-review process. Run it on demand (`/scaffold-audit`) or as part of checkpoints and reviews.

## Step 1: Collect evidence

Review recent work for stochastic interventions — moments where Claude exercised judgment on operations that could be deterministic:

1. Read `docs/checkpoint.md` for recent session activity.
2. Run `git log --oneline -20` to see recent commits.
3. Run `git diff HEAD~5..HEAD --stat` to see recent changes.
4. Read `.claude/rules/deterministic-first.md` for the principle and anti-patterns.

## Step 1b: Permissions check

Run `scripts/permissions-audit.sh check --settings-dir .claude` and check the exit code:

- **Exit 0:** All entries REVIEWED, no DANGER. Report "Permissions: PASS" and move on.
- **Exit 1 or 2:** Include a "Permissions" section in the audit report with:
  - Danger count and unreviewed count from the JSON output
  - List all DANGER permission strings with their matched pattern
  - Recommendation: run `permissions-audit.sh check --text` for details, or `permissions-audit.sh init` to create the decision log

If `permissions-audit.sh` does not exist, skip this step.

## Step 1c: Context budget check

Run `scripts/context-budget.sh check` and check the exit code:

- **Exit 0 (HEALTHY):** Report "Context budget: HEALTHY (X% of Y token budget)" and move on.
- **Exit 1 (WARNING):** Include a "Context Budget" section with the budget percentage and list the top 3 files by token count.
- **Exit 2 (CRITICAL):** Include a "Context Budget" section marked CRITICAL with the full file breakdown and a recommendation to move content to on-demand files.

If `context-budget.sh` does not exist, skip this step.

## Step 2: Identify violations

For each recent operation, classify it:

| Pattern | Classification | Action |
|---------|---------------|--------|
| Claude ran `cp`, `diff`, `jq`, `shasum`, `git` manually | **Violation** — should be a script command | Add script command |
| Claude computed hashes, parsed JSON, manipulated paths | **Violation** — deterministic in stochastic costume | Wrap in script function |
| Claude proposed merged content for conflicting files | **Correct** — requires semantic understanding | Leave as-is |
| Claude classified changes as generalizable vs specific | **Correct** — requires judgment | Leave as-is |
| Claude wrote a spec, plan, or code | **Correct** — creative work | Leave as-is |
| Claude read output and decided next step | **Review** — could the decision tree be scripted? | Check if binary |
| Claude formatted output for the user | **Review** — could the script output be better? | Improve script output |

## Step 3: Propose improvements

For each violation or reviewable item, propose:

1. **What exists now** — the stochastic operation
2. **What should exist** — the deterministic replacement (hook, script command, or improved output)
3. **Where to implement** — which file(s) to change
4. **Test case** — how to verify the fix in `tests/scaffold-sync.bats`

## Step 4: Report

Output a structured audit:

```markdown
## Scaffold Audit — [date]

### Violations Found
- [description + proposed fix]

### Opportunities
- [things that work but could be more deterministic]

### Healthy Patterns
- [stochastic operations that are correctly placed]

### Test Coverage Gaps
- [deterministic operations lacking tests]
```

## Rules
- Be specific. "Could be more deterministic" is useless. "Claude manually runs `jq` to read lockfile status on line 42 of scaffold-pull.md — should call `scaffold-sync.sh lock-get <file>`" is useful.
- Don't flag stochastic operations that genuinely require semantic understanding.
- Prioritize by impact: operations that run frequently or consume many tokens first.
- If no violations found, say so — don't invent problems.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
