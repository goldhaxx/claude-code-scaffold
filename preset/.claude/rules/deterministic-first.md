# Deterministic-First Principle

## The Rule

When an operation is computable (same input → same output, every time), it MUST be implemented as deterministic machinery — scripts, hooks, or tooling — not as Claude reasoning. Every token Claude spends on a deterministic operation is a token stolen from judgment calls that actually need a transformer.

## Why This Matters

Transformer attention is zero-sum. Context consumed by `cp`, `diff`, `jq`, hash comparisons, and lockfile manipulation is context NOT available for merge conflict resolution, code review, or architecture decisions. Deterministic operations also introduce non-determinism when executed stochastically — Claude might run commands in a different order, forget a lockfile update, or compute a hash incorrectly.

## The Hierarchy

Use this decision ladder for every operation:

1. **Hook** — if the action is binary (always/never) and triggered by a lifecycle event, make it a hook. Zero context cost. Examples: block writes to `.env`, auto-format on save, protect `scaffold-framework.md`.

2. **Script** — if the action involves multiple deterministic steps (hash, compare, copy, update lockfile), wrap them in a shell function/command. Claude calls one command instead of orchestrating ten. Examples: `ccanvil-sync.sh pull-auto`, `ccanvil-sync.sh promote <file>`.

3. **Slash command with script calls** — if the workflow has BOTH deterministic steps and judgment calls, the slash command should call scripts for the deterministic parts and describe ONLY the judgment calls for Claude. Examples: conflict resolution (script identifies conflicts, Claude proposes merge), push classification (script lists candidates, Claude classifies).

4. **Pure Claude reasoning** — ONLY for tasks that genuinely require semantic understanding: merge proposal synthesis, generalizable-vs-specific classification, spec writing, code review.

## How to Apply

When adding or modifying ANY scaffold automation:

- **Ask:** "Can this step produce a wrong answer?" If no → script/hook, not Claude.
- **Ask:** "Does this step require reading and understanding code semantics?" If no → script/hook, not Claude.
- **Ask:** "Would a shell script do this identically every time?" If yes → it should BE a shell script.

When reviewing existing automations:

- Flag any slash command where Claude is running `cp`, `diff`, `ls`, `cat`, `jq`, `shasum`, or `git` commands that could be a single script call.
- Flag any workflow where Claude computes hashes, parses JSON, or manipulates file paths — these are deterministic operations wearing a stochastic costume.

## Anti-Patterns

- Claude manually running `cp` to copy files during sync (should be one script call)
- Claude running `jq` to read lockfile fields (should be a script subcommand)
- Claude computing sha256 hashes to compare versions (script already has `file_hash`)
- Claude running `lock-update` 3 times per file (should be one compound command)
- Claude running `git -C <path> status --porcelain` (should be a script pre-check)
- Inline shell in settings.json hooks (should be executable scripts in `.claude/hooks/`)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
