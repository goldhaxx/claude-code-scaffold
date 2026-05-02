# Manifest Rollout Runbook

> Layer 2 of the Dark Code framework — Self-Describing Systems. This runbook walks a downstream-node operator from "I just adopted ccanvil" to "my substrate is self-describing too." The hub itself ran this same playbook over 11 sessions; this template captures what worked.

## What you're rolling out

`module-manifest.sh` distributes via ccanvil's `TRACKED_PATTERNS` (`.ccanvil/scripts/*.sh`), and the format spec lives at `.ccanvil/templates/manifest.md`. What does NOT distribute: your node's `.ccanvil/manifest-allowlist.txt` (correctly node-specific) and your per-primitive `# @manifest` blocks (you author these). The runbook below covers the bootstrap + per-batch loop to close that gap.

## Step 0 — verify the substrate is present

```bash
bash .ccanvil/scripts/module-manifest.sh validate --json | jq '.coverage'
```

If you see `{"covered": 0, "total": 0}`, the substrate is loaded but no allowlist is configured yet. That's the expected starting state for a fresh node.

## Step 1 — seed the initial allowlist

```bash
bash .ccanvil/scripts/module-manifest.sh seed-allowlist --dir . > /tmp/seed.txt
$EDITOR /tmp/seed.txt
mv /tmp/seed.txt .ccanvil/manifest-allowlist.txt
git add .ccanvil/manifest-allowlist.txt
git commit -m "feat(layer-2): seed initial manifest allowlist"
```

`seed-allowlist` walks your substrate (`.ccanvil/scripts/*.sh` for `cmd_*` mega-scripts and bare scripts; `.claude/skills/*/SKILL.md`; `.claude/rules/*.md`; `.claude/agents/*.md`; `.claude/commands/*.md`; `.claude/hooks/*.sh`) and proposes one entry per primitive. Two filters are applied:

1. **Hub-managed files are excluded.** When `.ccanvil/ccanvil.lock` is present (any node that ever ran `ccanvil-sync` will have one), seed reads the `.files` map and skips every path it lists. Hub already manifests its own substrate — your node consumes those manifests via the next pull, you don't re-author them.
2. **Existing entries are deduped.** Re-running after partial adoption emits only NEW candidates (deduped against your existing `.ccanvil/manifest-allowlist.txt`).

Together: a freshly-adopted node with NO project-specific code yet sees empty seed output — the correct "you have nothing of your own to manifest" signal. Add custom scripts/skills/rules over time, then re-run seed; only the additions surface.

Review the output before committing. Comment out entries you don't want manifested yet — the rollout works batch-by-batch, not all-at-once.

## Step 2 — install the drift-guard test

Mirror the hub's `hub/tests/module-manifest-drift-guard.bats` shape into your node's test directory. The test shells out to `bash .ccanvil/scripts/module-manifest.sh validate` and asserts exit 0.

```bash
@test "module-manifest drift-guard: validate exits 0 (no drift)" {
  run bash "$REPO_ROOT/.ccanvil/scripts/module-manifest.sh" validate
  [ "$status" -eq 0 ]
}
```

This is the only structural enforcement that compounds quality across sessions. CI runs it; broken manifests block merge.

## Step 3 — per-batch authoring loop

Don't try to manifest everything in one session. Hub's rollout shipped ~10-30 manifests per session over 11 sessions. The loop:

1. **Pick a batch.** 10-30 entries from your allowlist (one cluster — e.g. all skills, or one mega-script's `cmd_*` primitives).
2. **Author one manifest at a time.** Above each `cmd_*` function (or in markdown frontmatter under `manifest:`), write a `# @manifest` block per `.ccanvil/templates/manifest.md` schema. Required keys: `purpose`, `input`, `output`, `side-effect`, `failure-mode`, `contract`, `anchor`. Optional: `caller`, `depends-on`, `routes-by`.
3. **Add inline markers.** Every `failure-mode: <id>` and `side-effect: <id>` declared in the manifest needs a matching `# @failure-mode: <id>` or `# @side-effect: <id>` comment inside the function body — this is what drift-guard uses to catch behavior drift.
4. **Validate as you go.** `bash .ccanvil/scripts/module-manifest.sh validate` after each manifest. Fix drift incrementally — don't accumulate.
5. **Commit per batch.** One commit per cluster, with all manifests + their markers in one diff.

## Step 4 — common pitfalls (from the hub rollout)

- **Aspirational callers.** Don't declare `caller: skill:/foo` if no `.claude/skills/foo/SKILL.md` actually grep-resolves to your primitive. Drift-guard rejects it. If a primitive is operator-invoked-only (no programmatic caller), OMIT the `caller:` field entirely — it's conditional, not required.
- **`||` in failure-mode mitigation.** The pipe character `|` is the field separator; literal `||true` in a mitigation phrase breaks the parser. Reword (e.g. `mitigation=formatter-errors-suppressed-deliberately`).
- **File-level scripts vs. mega-scripts.** A single-purpose script with no `cmd_*` declaration uses file-level form (`<path>` only); a mega-script with `cmd_a` / `cmd_b` uses function-level form (`<path>:cmd_a` / `<path>:cmd_b`). `seed-allowlist` proposes the right form automatically.
- **Skill `:id` suffix.** Skills live at `.claude/skills/<name>/SKILL.md` — basename is `SKILL`, not `<name>`. Allowlist entries need explicit suffix: `.claude/skills/<name>/SKILL.md:<name>`. `seed-allowlist` reads the frontmatter `name:` field and writes the suffix automatically.
- **Body-grep SIGPIPE under `set -o pipefail`.** Long primitive bodies + early grep matches can trip pipefail. The substrate already handles this (BTS-252 fix), but if you hit a `MALFORMED:` on a manifest that visibly matches, capture both the failing command and `set -o pipefail` state in your bug report.

## Step 5 — what good looks like

- Coverage holds at 100% (`covered == total` in `validate --json`).
- Drift list is empty (`drift == []`).
- Every PR that touches a manifested primitive either updates the manifest or proves the primitive's behavior signature didn't change.
- New primitives land with their manifest + markers in the same commit, not as a follow-up.

That's Layer 2 in steady-state. Pair with Layer 3 (manifest-aware code review via `code-reviewer.md`) to catch architecture-shaped change at PR time.

## Anchors

- `.ccanvil/templates/manifest.md` — format spec.
- `.ccanvil/scripts/module-manifest.sh` — the substrate.
- BTS-239 — manifest substrate origin.
- BTS-267 — node-portable onboarding (this runbook + `seed-allowlist`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
