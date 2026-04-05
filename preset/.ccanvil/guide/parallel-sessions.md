# Parallel Agent Sessions

Claude Code supports running multiple agents in parallel via git worktrees (`claude --worktree` or `-w`). The scaffold is compatible with this workflow.

## How it works

- **Worktrees share `.git`:** All scaffold configuration (CLAUDE.md, rules, hooks, settings.json) is inherited automatically. No duplication needed.
- **Branch-local docs:** `docs/spec.md`, `docs/plan.md`, `docs/checkpoint.md` are branch-specific. Each worktree operates on its own branch, so parallel agents get isolated doc state.
- **Lockfile is shared:** `.claude/ccanvil.lock` lives in `.git`-tracked state. Avoid running `/ccanvil-pull` from multiple worktrees simultaneously.

## Usage pattern

```bash
# Start a new agent on a feature branch in a worktree
claude --worktree feature-name

# Or create a worktree manually and launch Claude in it
git worktree add .claude/worktrees/auth-system claude/feat/auth-system
cd .claude/worktrees/auth-system
claude
```

## What to watch for

| Concern | Mitigation |
|---------|-----------|
| Port conflicts | Each worktree may try to start dev servers on the same port. Use different ports per worktree. |
| Database locks | Multiple agents writing to the same SQLite/local DB will conflict. Use separate DB files or a shared server. |
| File locks | Lock files (`.lock`, `*.pid`) in the repo root are shared. Ensure they're branch-specific or gitignored. |
| Scaffold sync | Don't run `/ccanvil-pull` from multiple worktrees simultaneously — lockfile mutations will conflict. |

## `.gitignore` and `.claudeignore`

Both files include `.claude/worktrees/` to prevent worktree contents from being tracked or loaded into context.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
