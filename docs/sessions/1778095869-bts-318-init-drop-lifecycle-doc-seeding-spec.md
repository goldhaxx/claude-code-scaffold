# Feature: Init drops per-feature lifecycle-doc seeding

> Feature: bts-318-init-drop-lifecycle-doc-seeding
> Work: linear:BTS-318
> Created: 1778092558
> Subject: Init drops per-feature lifecycle-doc seeding
> Status: In Progress

## Summary

`/ccanvil-init` Step 6 currently seeds four files from `.ccanvil/templates/` into every fresh project: `docs/spec.md`, `docs/plan.md`, `docs/stasis.md`, and `docs/roadmap.md`. Three of these are **per-feature lifecycle artifacts** (created by `/spec`/`/plan`/`/stasis`, removed by `/pr`'s pr-cleanup). Seeding them at init pre-fills branch-local state into a fresh repo with no active feature, which violates the lifecycle invariant "active spec exists ↔ docs/spec.md exists" and breaks the very first `/stasis` on every newly initialized node — the validator reads the bracketed `Work:` placeholders as two non-matching references and halts on `state: blocked`. This spec drops the three per-feature files from Step 6's seed loop, leaving only `docs/roadmap.md` (the single project-strategic seed) and `mkdir -p docs/specs`.

## Job To Be Done

**When** I initialize a new project with `/ccanvil-init`,
**I want to** be able to run `/stasis` immediately at the next session boundary without manual cleanup,
**So that** session-discipline rituals work on day one and downstream agents don't have to invent recovery flows for lifecycle corruption introduced by init itself.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `global-commands/ccanvil-init.md` Step 6 seed loop iterates over **exactly one** file: `docs/roadmap.md`. The file list `docs/spec.md docs/plan.md docs/stasis.md docs/roadmap.md` is replaced with `docs/roadmap.md`.
- [ ] **AC-2:** `global-commands/ccanvil-init.md` Step 6 retains the `mkdir -p docs/specs` line so the per-feature spec archive directory exists post-init.
- [ ] **AC-3:** `hub/tests/ccanvil-init-skill.bats` AC-10's "skill names the four lifecycle docs by path" test is rewritten to assert (a) `docs/roadmap.md` IS seeded, (b) `docs/spec.md`, `docs/plan.md`, `docs/stasis.md` are NOT in the seed loop. Test name updated to reflect new behavior.
- [ ] **AC-4:** A new bats test asserts that the seed loop body grep for `docs/spec.md\|docs/plan.md\|docs/stasis.md` returns ZERO matches inside the Step 6 fenced code block. Drift-guard against re-introduction.
- [ ] **AC-5:** `hub/tests/ccanvil-init-skill.bats` AC-11 ("in-progress feature detection from docs/stasis.md header") is preserved or rewritten to reflect that `docs/stasis.md` is no longer seeded but may still exist on retrofitted nodes — the in-progress-feature detection logic only fires when stasis is genuinely PRESERVED (file existed pre-init), not seeded fresh.
- [ ] **AC-6:** Edge: when init runs in `mature-repo` or `partial-ccanvil` mode and the project ALREADY has `docs/spec.md`/`docs/plan.md`/`docs/stasis.md`, the existing files are preserved (the `[[ -s "$f" ]]` branch never runs in the new flow because those files are no longer in the loop — preservation is automatic by absence).
- [ ] **AC-7:** Error: post-fix, a freshly initialized project must report `lifecycle-state.state == "no-active-spec"` (benign) and a session-kind `/stasis` must complete without halt. Verified manually on a scratch directory or fresh node.
- [ ] **AC-8:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel`) — baseline 1993/1993 maintained or improved.
- [ ] **AC-9** (scope-up): `cmd_artifact_read` honors `--project-dir` for local-route reads. The local-route case in `.ccanvil/scripts/docs-check.sh` `cmd_artifact_read` reads `$project_dir/docs/<kind>.md`, not the cwd-relative `docs/<kind>.md`. Surfaced live during impl: an orphaned `docs/stasis.md` on main was leaking into `stasis-carry-forward` AC-5 fixture (test passed `--project-dir <tmpdir>` but substrate read hub-cwd's stasis). Pre-existing latent bug; in same locality as init-lifecycle work.

## Affected Files

| File | Change |
| -- | -- |
| `global-commands/ccanvil-init.md` | Modified — Step 6 seed loop reduced to `docs/roadmap.md` only |
| `hub/tests/ccanvil-init-skill.bats` | Modified — AC-10 test rewritten; new drift-guard test added |
| `.ccanvil/scripts/docs-check.sh` | Modified — `cmd_artifact_read` honors `--project-dir` for local reads (AC-9 scope-up) |

## Dependencies

* **Requires:** none — purely behavioral change to init script prose.
* **Blocked by:** none.

## Out of Scope

* Modifying `.ccanvil/templates/spec.md` / `plan.md` / `stasis.md` themselves — they remain valid for `/spec`, `/plan`, `/stasis` to copy into branch-local locations on demand.
* Healing already-initialized nodes that have placeholder lifecycle docs (e.g., microsoft365-toolbox) — that's a separate operator/agent action covered under BTS-314 (onboarding repair). This spec only fixes forward.
* Changes to `/spec`, `/plan`, `/stasis` skills — they continue to write `docs/spec.md`/`docs/plan.md`/`docs/stasis.md` at the appropriate lifecycle phase.
* Changes to `pr-cleanup` (which removes lifecycle docs at PR-ready) — already correct.

## Implementation Notes

* Same file-edit shape as the BTS-237/241 docs-check refactors: surgical edit to one fenced block in a global skill markdown file.
* Step 6's `if [[ -s "$f" ]]; then echo "PRESERVED: $f"; else cp ...; fi` pattern with a one-element list is acceptable; alternatively collapse to a direct `[[ -s docs/roadmap.md ]] || cp ... docs/roadmap.md` if cleaner.
* Drift-guard test (AC-4) can grep the skill file content for the absence of the three filenames inside the Step 6 region, demarcated by `## Step 6` and `## Step 7` headers.
* Sibling slice under BTS-316 (Modular provider connectivity / forklift-heal) — same root cause family as BTS-313/314 (init has no canonical activation flow), but a distinct concrete bug (lifecycle-doc seeding violates an invariant that's separate from provider-config fragility).
