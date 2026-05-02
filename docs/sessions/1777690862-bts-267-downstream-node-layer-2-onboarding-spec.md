# Feature: Downstream-node Layer 2 onboarding ramp

> Feature: bts-267-downstream-node-layer-2-onboarding
> Work: linear:BTS-267
> Created: 1777686649
> Subject: Downstream-node Layer 2 onboarding ramp
> Status: In Progress

## Summary

Today the manifest substrate (`module-manifest.sh`, `.ccanvil/templates/manifest.md`, `code-reviewer.md`'s Layer 3 prose, all rules) propagates to downstream nodes via `ccanvil-sync.sh`'s `TRACKED_PATTERNS`. What does NOT propagate: the per-node manifest allowlist (correctly node-specific) AND the rollout playbook (hub-historical, lives in `docs/manifest-rollout.md` outside the distribution surface). A fresh node pulls the engine but has no path from "I adopted ccanvil" to "my substrate is self-describing too." This feature closes that gap with two deliverables: a `seed-allowlist` primitive that proposes an initial allowlist for a node by scanning its substrate, and a node-rollout runbook that ships via `.ccanvil/templates/`.

## Job To Be Done

**When** a downstream-node operator runs `ccanvil-pull` and inherits the manifest substrate,
**I want to** run one command that scans my node's substrate and proposes a starting allowlist, plus read a runbook that walks me through the per-batch authoring loop,
**So that** my node's substrate becomes self-describing without me re-discovering the hub's 11-session rollout playbook.

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/module-manifest.sh seed-allowlist [--dir <path>]` scans the target node's substrate (`.ccanvil/scripts/*.sh` for `cmd_*` functions and bare scripts; `.claude/skills/*/SKILL.md`; `.claude/rules/*.md`; `.claude/agents/*.md`; `.claude/commands/*.md`; `.claude/hooks/*.sh`) and emits a proposed allowlist on stdout in the canonical format (one path-or-`path:fn` entry per line, comments preserved-on-section-headers).
- [ ] **AC-2:** The seed output filters out entries that already appear in an existing `.ccanvil/manifest-allowlist.txt` (when present), so re-running `seed-allowlist` after partial adoption yields only NEW candidates — not duplicates.
- [ ] **AC-3:** Given a node directory with no `.ccanvil/scripts/` and no `.claude/` substrate (or both empty), When the operator runs `seed-allowlist --dir <path>`, Then the command exits 0 with an empty stdout (or a single comment-only header) — not an error.
- [ ] **AC-4 (error):** Given `--dir <path>` points at a non-existent directory, When the operator runs `seed-allowlist`, Then stderr surfaces `ERROR: directory not found: <path>` and exit code is 2.
- [ ] **AC-5:** A new file `.ccanvil/templates/manifest-rollout-runbook.md` lands, distributed via the existing `.ccanvil/templates/*.md` glob in `ccanvil-sync.sh`'s `TRACKED_PATTERNS`. Content covers: (a) what Layer 2 is + why, (b) running `seed-allowlist` to bootstrap, (c) per-batch authoring loop (10-30 manifests per session), (d) drift-guard test integration (one bats file mirroring `hub/tests/module-manifest-drift-guard.bats`), (e) common pitfalls from the hub rollout (file-level fallback, SIGPIPE-resistance, aspirational-callers).
- [ ] **AC-6 (edge):** Given a node with mixed shell-script substrate (mega-scripts with multiple `cmd_*` functions AND single-purpose file-level scripts), When `seed-allowlist` runs, Then mega-script entries take `<path>:<fn>` form and single-purpose entries take bare `<path>` form, matching the format documented in `.ccanvil/templates/manifest.md` "Allowlist format" section.
- [ ] **AC-7:** A new bats test file `hub/tests/module-manifest-seed-allowlist.bats` covers AC-1 / AC-2 / AC-3 / AC-4 / AC-6 / AC-9 against fixture node trees in `$BATS_TEST_TMPDIR`.
- [ ] **AC-8:** New `cmd_seed_allowlist` primitive is added to `.ccanvil/manifest-allowlist.txt` with a complete `# @manifest` block — drift-guard remains green at 100% coverage.
- [ ] **AC-9 (dogfood-surfaced):** When `<dir>/.ccanvil/ccanvil.lock` is present, `seed-allowlist` filters out any candidate path that appears in the lockfile's `.files` map — those are hub-managed files distributed via `ccanvil-sync.sh` and already manifested upstream. A node operator running seed-allowlist on a project that has no project-specific code (only hub-mirrored substrate) sees an empty proposed allowlist — the correct "I have nothing of my own to manifest yet" signal. Lockfile-absent falls back to unfiltered behavior (preserves AC-1).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified — add `cmd_seed_allowlist` + dispatch entry |
| `.ccanvil/templates/manifest-rollout-runbook.md` | New — node-onboarding runbook |
| `hub/tests/module-manifest-seed-allowlist.bats` | New test file |
| `.ccanvil/manifest-allowlist.txt` | Modified — add `cmd_seed_allowlist` entry |

## Dependencies

* **Requires:** `module-manifest.sh` substrate (BTS-239, shipped); `ccanvil-sync.sh` `TRACKED_PATTERNS` distribution surface (already covers `.ccanvil/templates/*.md`).
* **Blocked by:** none.

## Out of Scope

* The stretch `stub-batch --batch <N>` primitive that emits N missing-manifest stubs for operator fill-in. Capture as a follow-up ticket if `seed-allowlist` adoption surfaces real friction at the per-batch authoring step.
* Auto-PR'ing the seed allowlist into a downstream node — the operator reviews and pipes manually. Automation can come later if multi-node rollouts ramp.
* Updating per-node `docs/manifest-rollout.md` — the runbook in `.ccanvil/templates/` IS the per-node equivalent. Hub's `docs/manifest-rollout.md` stays historical.
* Backfilling Layer 2 onto specific known downstream nodes (fucina, luxlook). That is per-node operator work; this ticket ships the substrate that enables it.

## Implementation Notes

* Pattern: `cmd_seed_allowlist` follows the same shape as existing `cmd_extract` / `cmd_validate` — manifest block above, dispatch entry in the bottom case statement, plain bash + awk + grep (no yq / python).
* Discovery walk: pure-bash globbing under `--dir`. For shell scripts, grep for `^cmd_[a-z_]+\s*\(\)` (mega-script test) and otherwise emit file-level entry. For markdown, emit `<path>:<id>` when the basename is `SKILL.md` (use frontmatter `id:` value), otherwise plain path form.
* Dedup against existing allowlist: if `<dir>/.ccanvil/manifest-allowlist.txt` exists, parse out non-comment non-blank entries into a set, filter the proposed list against it.
* Runbook prose: lean toward concrete recipes ("run validate, fix one drift, commit") over Layer-2-philosophy. Reference existing artifacts (`.ccanvil/templates/manifest.md`, drift-guard bats fixture) by path so node operators can fork-and-edit.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
