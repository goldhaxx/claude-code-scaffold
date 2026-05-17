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

Overlap patterns observed during BTS-497 session 57 (the origin incident — ~2+ hours of test-wait time on a single ship) and validated against the audit catalog above.

### Pattern 1: /stasis re-runs manifest validate after /review on the same commit

- **Duplicate sites:** `.claude/commands/review.md` (Step 0) → `.claude/skills/stasis/SKILL.md` (step 12).
- **Same HEAD, same diff, no code change in between.** /review just emitted the validate envelope; /stasis discards it and re-runs.
- **Candidate state-key:** `last_manifest_validate_commit == HEAD AND manifest_tracked_files_changed_since_last_validate == 0` → skip the second run, surface the cached result.

### Pattern 2: /recall re-runs manifest validate at session start when /stasis just ran it

- **Duplicate sites:** `.claude/skills/stasis/SKILL.md` (step 12) → `.claude/skills/recall/SKILL.md` (step 11).
- **Across-session duplicate.** /stasis writes the validate result for the session boundary; /recall ignores it and runs validate again at the next session's start.
- **Candidate state-key:** `last_manifest_validate_commit == HEAD` after persistence reload → /recall reads the cached envelope.

### Pattern 3: /stasis re-runs full bats suite after /pr just ran it

- **Duplicate sites:** `.claude/commands/pr.md` (Step 2) → `.claude/skills/stasis/SKILL.md` (Tests line).
- **/pr → /ship → /stasis lifecycle path.** /pr ran the full suite ~5 min ago; main is unchanged between the merge and the stasis snapshot.
- **Candidate state-key:** `last_full_suite_commit == HEAD AND files_changed_since_last_full_suite == 0` → skip /stasis's re-run.

### Pattern 4 (cross-gate): code-reviewer agent re-reads validate output /review already produced

- **Duplicate sites:** `.claude/commands/review.md` (Step 0) → `.claude/agents/code-reviewer.md` (step 5).
- **Advisory re-read, not re-invocation** — but the agent's prompt currently instructs it to consult the same envelope structure. As long as `/review` caches the envelope in-process before spawning the agent, no duplicate work fires. Documented here for completeness; the cache pattern is the mitigation.

## Framework

State + intent + scope drive every test-run decision. The gate table:

| Phase | State | Intent | Scope |
|-------|-------|--------|-------|
| TDD-cycle | per-AC commit + targeted file edits | "did my latest change keep the failing test failing / passing" | Only the bats file under active TDD |
| pre-review | branch-local commits since last manifest-validate run | "is the diff manifest-correct (no orphaned callers, deps, etc.)" | manifest validate, gated on `manifest_tracked_files_changed_since_last_validate > 0` |
| pre-commit | files in `git diff --cached` | "do touched bats files still pass" | Only the bats files in the staged diff (never full suite) |
| pre-merge | branch HEAD vs main | "is the full state of the branch shippable" | Full bats suite + manifest validate. THE load-bearing gate. |
| session-boundary | HEAD of current branch | "record state at boundary; no re-verification" | None. /stasis records, doesn't test. Validate output is documentation, not gating. |
| post-merge | merged commit on main | "/pr already verified — nothing to re-run" | None. /ship is record-keeping. |

**Universal rule:** if `state == "no allowlisted file has changed since the last successful <substrate> run"`, skip and surface the cached result. HEAD does not need to match the cached SHA — only the diff (cached_sha..HEAD ∩ allowlist) needs to be empty. The substrate writes its own success state; consumers read state via `bash .ccanvil/scripts/docs-check.sh test-state` (or its decision-wrapper `check-skip-validate`).

## Decision Tree

### TDD-cycle

```
files_changed_since_last_touched_bats > 0 ? → run targeted bats file
otherwise → no-op (file already verified at this content)
```

### pre-review (/review Step 0)

```
test-state envelope empty (no prior validate) ? → run manifest validate (fail-safe)
manifest_tracked_files_changed_since_last_validate > 0 ? → run manifest validate (allowlisted file changed)
otherwise → SKIP and emit `SKIP: manifest validate — no manifest-tracked files changed since <SHA>`
```

Note: HEAD does not need to match the cached commit. The decision is driven by the diff intersected with the allowlist, not by SHA equality.

### pre-commit

```
staged diff touches bats files ? → run those bats files
otherwise → no-op
```

### pre-merge (/pr Step 2)

```
ALWAYS run the full bats suite + manifest validate.
This is the load-bearing gate. No skip path. State writers fire on success
so downstream phases can skip.
```

### session-boundary (/stasis)

```
NO test invocation. Surface cached state from test-state envelope only.
Validate output rendered as documentation in the Manifest Coverage section.
```

### post-merge (/ship, /land)

```
NO test invocation. /pr already verified the merge state.
```

## Anti-Patterns

1. **Reflexive full-suite "just to be safe"** after a small change that touched zero suite-relevant files. The full suite already ran (or will run) at the pre-merge gate; mid-session re-runs cost wall time without adding signal.
2. **Re-running manifest validate at every skill step** that mentions it. The envelope is cacheable per-commit; downstream consumers read state, not re-invoke the substrate.
3. **Running the full bats suite to verify ONE bats file passes.** Use `bash bats <file>` (or `bats hub/tests/<file>`) directly. The full suite is for pre-merge state-of-the-branch verification, not per-file confirmation.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
