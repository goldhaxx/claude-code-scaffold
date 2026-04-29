# Feature: Markdown agents + commands manifests

> Feature: bts-256-markdown-agents-commands-manifests
> Work: linear:BTS-256
> Created: 1777491760
> Subject: Markdown agents + commands manifests
> Status: In Progress

## Summary

Per `docs/manifest-rollout.md` Session 10 — extend Layer 2 (Self-Describing Systems) coverage to markdown agents + commands. Adds 19 YAML-frontmatter `manifest:` blocks across 4 remaining agents (`ccanvil-differ`, `drift-analyst`, `spec-writer`, `strategic-advisor`) and 15 remaining commands (`activate`, `ccanvil-audit`, `ccanvil-demote`, `ccanvil-ignore`, `ccanvil-promote`, `ccanvil-pull`, `ccanvil-push`, `ccanvil-status`, `commit`, `fix-certs`, `land`, `permissions-review`, `plan`, `review`, `security-audit`). Allowlist 165 → 184. After this ship, **all ccanvil markdown surfaces and shell substrate are 100% manifest-covered**.

## Job To Be Done

**When** I'm cold-reading an agent or command and need to know its purpose, callers, dependencies, side-effects, and failure modes,
**I want to** read the YAML frontmatter `manifest:` block at the top of the file using the same field set as cmd\_\* primitives,
**So that** every agent + command surface in `.claude/agents/` and `.claude/commands/` is self-describing and drift-guard catches regressions across the full operator-callable preset.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Each of the 4 agents (`ccanvil-differ`, `drift-analyst`, `spec-writer`, `strategic-advisor`) carries a top-level YAML frontmatter `manifest:` block with all required keys (`purpose`, `input`, `output`, `side-effect`, `failure-mode`, `contract`, `anchor`).
- [ ] **AC-2:** Each of the 15 commands carries a top-level YAML frontmatter `manifest:` block with all required keys.
- [ ] **AC-3:** `.ccanvil/manifest-allowlist.txt` adds 19 file-level markdown entries under a new `# BTS-256 — Session 10` section. Total entries 165 → 184.
- [ ] **AC-4:** `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0 with `coverage.covered == 184`, `coverage.total == 184`, `drift == []`. Bidirectional drift-guard verifies all 19 new manifests via the BTS-240 markdown branch + BTS-252 SIGPIPE-resistant body grep.
- [ ] **AC-5:** Every declared `caller:` resolves — for path-form callers, the file exists and contains a word-boundary match; for `skill:/<name>` callers, the skill or command file exists and matches.
- [ ] **AC-6:** Every declared `depends-on:` resolves via the markdown body grep (post-frontmatter scope).
- [ ] **AC-7:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel` reports 1926+ / 0 / total). No new tests introduced — existing markdown drift-guard suite verifies semantic correctness.
- [ ] **AC-8:** `docs/manifest-rollout.md` inventory updated: `Done` columns reflect agents 5/5, commands 16/16, total 184/184. Note Session 11 still pending for Layer 3 ramp + close-out.

## Affected Files

| File | Change |
| -- | -- |
| `.claude/agents/ccanvil-differ.md` | Modified — frontmatter manifest block added |
| `.claude/agents/drift-analyst.md` | Modified — frontmatter manifest block added |
| `.claude/agents/spec-writer.md` | Modified — frontmatter manifest block added |
| `.claude/agents/strategic-advisor.md` | Modified — frontmatter manifest block added |
| `.claude/commands/activate.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-audit.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-demote.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-ignore.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-promote.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-pull.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-push.md` | Modified — frontmatter manifest block added |
| `.claude/commands/ccanvil-status.md` | Modified — frontmatter manifest block added |
| `.claude/commands/commit.md` | Modified — frontmatter manifest block added |
| `.claude/commands/fix-certs.md` | Modified — frontmatter manifest block added |
| `.claude/commands/land.md` | Modified — frontmatter manifest block added |
| `.claude/commands/permissions-review.md` | Modified — frontmatter manifest block added |
| `.claude/commands/plan.md` | Modified — frontmatter manifest block added |
| `.claude/commands/review.md` | Modified — frontmatter manifest block added |
| `.claude/commands/security-audit.md` | Modified — frontmatter manifest block added |
| `.ccanvil/manifest-allowlist.txt` | Modified — +19 markdown entries (165 → 184) |
| `docs/manifest-rollout.md` | Modified — Inventory `Done` columns updated to 184/184 |

## Dependencies

* **Requires:** BTS-239 (manifest substrate), BTS-240 (markdown frontmatter parser), BTS-252 (SIGPIPE fix in `_target_body_grep`)
* **Blocked by:** none

## Out of Scope

* Layer 3 / `code-reviewer` integration — Session 11
* Manifest-aware `/review` skill — Session 11
* Modifying agent/command bodies — frontmatter-only ship
* Closing `docs/manifest-rollout.md` — Session 11 closes the doc

## Implementation Notes

* **Frontmatter shape:** existing seeded agent (`code-reviewer`) and command (`pr`) carry the canonical shape. Read them for the field structure. Existing top-level `name:` / `description:` keys must be preserved; the `manifest:` key is added as a sibling.
* **id field:** for both agents and commands, use the file's basename without `.md` (e.g., `ccanvil-differ`, `activate`, `plan`, `review`). The `id` MUST match what the validator's basename fallback would compute. Allowlist entries are path-only (no `:fn` suffix needed since basename match is exact).
* **Caller resolution:** for commands, common callers are `skill:/<name>` from skills that route through them (e.g., `skill:/pr` references `commit.md` patterns). For agents, common callers are commands or skills that spawn them via the Agent tool.
* **Depends-on:** body-scoped grep via the BTS-240 markdown branch (frontmatter is stripped before grep). Declare deps that the body actually mentions by name (script names, helper functions referenced in command examples).
* **Anchor:** at least one origin BTS, plus BTS-256 (manifest seed) for traceability.
* **No body changes:** every agent and command body is unchanged. Only the frontmatter is touched.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
