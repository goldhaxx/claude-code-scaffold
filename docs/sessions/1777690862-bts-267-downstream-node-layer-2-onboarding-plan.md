# Implementation Plan: Downstream-node Layer 2 onboarding ramp

> Feature: bts-267-downstream-node-layer-2-onboarding
> Work: linear:BTS-267
> Created: 1777687246
> Spec hash: c2768e8d
> Based on: docs/spec.md

## Objective

Ship `cmd_seed_allowlist` in `module-manifest.sh` plus a `manifest-rollout-runbook.md` template so any downstream node that pulls ccanvil can bootstrap Layer 2 in one command + one read.

## Sequence

### Step 1: Test scaffold + AC-4 (nonexistent dir error)

* **Test:** Create `hub/tests/module-manifest-seed-allowlist.bats`. First test: `seed-allowlist --dir /nonexistent/path` → exit 2, stderr matches `directory not found`.
* **Implement:** Stub `cmd_seed_allowlist` in `module-manifest.sh` — only handles the `--dir` flag and the missing-dir error path. Add dispatch entry `seed-allowlist) cmd_seed_allowlist "$@" ;;` and update Usage line.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/module-manifest-seed-allowlist.bats` (new).
* **Verify:** `bats hub/tests/module-manifest-seed-allowlist.bats` — 1 test passing.

### Step 2: AC-3 (empty substrate → exit 0, empty stdout)

* **Test:** Fixture: `$BATS_TEST_TMPDIR/empty-node` with no `.ccanvil/` and no `.claude/`. `seed-allowlist --dir <tmpdir>` → exit 0, stdout empty (or comment-only header).
* **Implement:** When neither dir tree exists or both trees yield zero candidates, return 0 with empty output (or just the canonical header comment).
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** Step 2 test green; Step 1 still green.

### Step 3: AC-1/AC-6 — shell mega-scripts (function-level entries)

* **Test:** Fixture node with `.ccanvil/scripts/foo.sh` containing two `cmd_a` / `cmd_b` function definitions. `seed-allowlist` emits `.ccanvil/scripts/foo.sh:cmd_a` and `.ccanvil/scripts/foo.sh:cmd_b` (one per line, sorted).
* **Implement:** Walk `<dir>/.ccanvil/scripts/*.sh`. For each: grep for `^cmd_[a-z_]+\s*\(\)` (or `^cmd_[a-z_]+\(\)` — match the actual style in `module-manifest.sh`). When matches exist, emit `<path>:<fn>` per match.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** New test green; suite still green.

### Step 4: AC-1/AC-6 — single-purpose scripts (file-level entries)

* **Test:** Fixture `.ccanvil/scripts/bar.sh` with NO `cmd_*` definitions (just top-level imperative script). `seed-allowlist` emits bare `.ccanvil/scripts/bar.sh` (no `:fn` suffix).
* **Implement:** When the shell-script grep finds zero `cmd_*` matches, emit the bare path. Mixed mega-script-and-single-purpose produces both forms in the same output.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** New test green; previous tests still green.

### Step 5: AC-1 — markdown substrate (skills with `:id` suffix; rules/agents/commands plain path)

* **Test 1:** Fixture `.claude/skills/foo/SKILL.md` with frontmatter `name: foo`. Expect `.claude/skills/foo/SKILL.md:foo`.
* **Test 2:** Fixture `.claude/rules/bar.md`. Expect bare `.claude/rules/bar.md`. Same for `.claude/agents/*.md`, `.claude/commands/*.md`.
* **Implement:** Walk each markdown subtree. For `SKILL.md`, parse the frontmatter `name:` (pure-bash awk, mirror `_extract_markdown` style — no yq). For others, plain path emit.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** Both new tests green; suite green.

### Step 6: AC-1 — hooks (`.claude/hooks/*.sh` file-level)

* **Test:** Fixture `.claude/hooks/protect-foo.sh`. Expect bare `.claude/hooks/protect-foo.sh`.
* **Implement:** Glob `<dir>/.claude/hooks/*.sh` and emit each as a file-level entry.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** New test green.

### Step 7: AC-2 — dedup against existing allowlist

* **Test:** Fixture node with `.ccanvil/manifest-allowlist.txt` already listing `.ccanvil/scripts/foo.sh:cmd_a`. Substrate has `cmd_a` AND `cmd_b`. `seed-allowlist` emits ONLY `cmd_b`'s entry (cmd_a deduped).
* **Implement:** When `<dir>/.ccanvil/manifest-allowlist.txt` exists, read non-blank non-comment lines into a set, filter the proposed list against it before emit.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** New test green.

### Step 8: Refactor — section headers in output + sort stability

* **Test:** Existing tests; possibly tighten one to assert the section-header comment shape (`# Shell scripts`, `# Markdown skills/rules/agents/commands`, `# Hooks`) is present when entries exist in that section.
* **Implement:** Group output by source-class with `#` section headers. Sort entries within each section. No functional change beyond presentation stability.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** Suite green.

### Step 9: AC-8 — drift-guard self-check (manifest block + allowlist entry)

* **Implement:** Add `# @manifest` block above `cmd_seed_allowlist` with full required keys (purpose / input / output / side-effect / failure-mode / contract / anchor + depends-on if applicable). Add `.ccanvil/scripts/module-manifest.sh:cmd_seed_allowlist` entry to `.ccanvil/manifest-allowlist.txt`.
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate` exits 0; coverage 185/185 (or current+1).
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `.ccanvil/manifest-allowlist.txt`.

### Step 10: AC-5 — [manifest-rollout-runbook.md](<http://manifest-rollout-runbook.md>) template

* **Implement:** Write `.ccanvil/templates/manifest-rollout-runbook.md` covering (a) what Layer 2 is + why, (b) `seed-allowlist` bootstrap, (c) per-batch authoring loop (10-30 manifests/session), (d) drift-guard test integration (mirror `hub/tests/module-manifest-drift-guard.bats`), (e) common pitfalls (file-level fallback, SIGPIPE-resistance, aspirational-callers — anchored on memory references). Include `<!-- NODE-SPECIFIC-START -->` marker for node customization.
* **Files:** `.ccanvil/templates/manifest-rollout-runbook.md` (new).
* **Verify:** File exists; manual read-through passes editorial check; distributes via existing `.ccanvil/templates/*.md` glob in `TRACKED_PATTERNS` (no `ccanvil-sync.sh` change needed).

### Step 11: Final verification + commit hygiene

* **Verify:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green (1926+ → 1926+N where N matches new test count). `bash .ccanvil/scripts/module-manifest.sh validate --json | jq '.coverage'` — covered/total both incremented by 1; drift `[]`.
* **Implement:** N/A — verification-only step.

## Risks

* **Mega-script regex sensitivity** — `cmd_extract` uses one specific shape (`^cmd_[a-z_]+\s*\(\)`), but downstream-node scripts may use other styles (`cmd_x()`, `function cmd_x`, etc.). Mitigation: Step 3's regex matches the styles already used in `module-manifest.sh` and `docs-check.sh`; if a node uses an unsupported style, seed-allowlist emits file-level form (correct conservative fallback) — no false drift introduced.
* **Skill frontmatter parsing** — `_extract_markdown` already does this work; reuse pattern rather than re-implementing. Mitigation: Step 5 reads `name:` field only; if absent, emit bare path (fallback to file-level).
* **Drift-guard self-check regression** — the new `cmd_seed_allowlist` must carry a complete manifest block or it fails its own validate. Mitigation: Step 9 is the drift-guard step; existing rollout discipline (4 sessions × \~50 manifests with two substrate fixes) covers this case-class.
* **Runbook prose drift** — runbook references hub artifacts by path. If those move, the runbook stales. Mitigation: keep prose recipe-shaped with explicit paths; the `.claude/rules/evidence-required-for-captures.md`-style anchoring lets future-Claude detect drift.

## Definition of Done

- [ ] All 8 spec ACs pass (AC-1 through AC-8).
- [ ] `bats hub/tests/module-manifest-seed-allowlist.bats` — all new tests passing.
- [ ] Full suite `bash .ccanvil/scripts/bats-report.sh --parallel` — 1926+N / 1926+N passing.
- [ ] `module-manifest.sh validate --json` — coverage covered/total both +1; drift `[]`.
- [ ] `.ccanvil/templates/manifest-rollout-runbook.md` exists and reads cleanly.
- [ ] `/review` (run before `/pr`) — no critical findings.
- [ ] Commit messages follow `feat(bts-267-...)` / `test(bts-267-...)` / `docs(bts-267-...)` shape.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
