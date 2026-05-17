# Test-Run Discipline Research

> Anchor for: `.claude/rules/test-discipline.md` (BTS-508)
> Tier-2 reference — excluded from auto-load; read on-demand via the rule's `anchors.evidence` pointer.

This doc audits every place ccanvil invokes a long-running test substrate (`bats-report.sh`, `module-manifest.sh validate`, `docs-check.sh test-suite-run`), identifies same-gate and cross-gate redundancy, codifies a state/intent/logic-driven framework, and provides a per-gate decision tree.

The thesis the framework formalizes (operator-locked, 2026-05-16): **full suite + manifest validate run ONCE, as one of the very last steps before merge.** Mid-lifecycle phases verify with targeted scope only, gated by state + intent.

## Audit

Catalog of canonical invocation sites in the hub. Drift-guarded by `hub/tests/test-discipline-doc.bats`. Test fixtures, drift-guard files, and `bats-report-stub: exempt` files are intentionally excluded — they exercise the substrate but are not lifecycle gates.

| # | Site | Phase | Trigger | Scope | Observed redundancy |
|---|------|-------|---------|-------|---------------------|
| 1 | `.claude/skills/stasis/SKILL.md` (Tests line, step 12) | session-boundary | skill step | `bats-report.sh --parallel` full-suite | Re-runs full bats suite at the END of the session even when /pr (which always runs it) just ran 5 min earlier and main is unchanged. Pure redundancy when /pr → /ship → /stasis is the lifecycle path. |
| 2 | `.claude/skills/stasis/SKILL.md` (step 12, BTS-239) | session-boundary | skill step | `module-manifest.sh validate --json` (full) | Re-runs manifest validate at /stasis after /review already ran it on the same commit. Same-commit duplicate when /review → /pr → /stasis flow holds. |
| 3 | `.claude/skills/recall/SKILL.md` (step 11, BTS-239) | session-resume | skill step | `module-manifest.sh validate --json` (full) | Runs at session start; if the prior session's /stasis already validated the same HEAD, this is duplicate work. |
| 4 | `.claude/commands/review.md` (Step 0, BTS-257 Layer 3) | pre-review | skill step | `module-manifest.sh validate --json` (full) | Canonical pre-review gate. The audit's PRIMARY skip candidate when nothing manifest-tracked has changed since the last validate. |
| 5 | `.claude/commands/pr.md` (Step 2) | pre-merge | skill step | `docs-check.sh test-suite-run --parallel --progress` → full bats suite | Canonical pre-merge gate. THE load-bearing run; never skip. Dispatcher (BTS-460) routes to `bats-report.sh` on bats-stack nodes. |
| 6 | `.claude/agents/code-reviewer.md` (steps 5, BTS-257 Layer 3) | pre-review (agent side) | agent guidance | `module-manifest.sh validate --json` (advisory re-read) | Reads the same validate output `/review` just produced; advisory only — doesn't re-invoke if `/review` already cached the envelope. |

**Substrates touched:**

- `bats-report.sh` — sites 1, 5 (transitive via test-suite-run dispatcher)
- `module-manifest.sh validate` — sites 2, 3, 4, 6
- `docs-check.sh test-suite-run` — site 5 (dispatcher; forwards to bats-report.sh)

## Redundancy

Filled in Step 2 (BTS-508 plan).

## Framework

Filled in Step 2 (BTS-508 plan).

## Decision Tree

Filled in Step 2 (BTS-508 plan).

## Anti-Patterns

Filled in Step 2 (BTS-508 plan).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
