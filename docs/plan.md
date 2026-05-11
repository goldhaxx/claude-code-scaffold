# Implementation Plan: pull-globals staleness gate

> Feature: bts-315-pull-globals-staleness-gate
> Work: linear:BTS-315
> Created: 1778516400
> Spec hash: a25d83dc
> Based on: docs/spec.md

## Objective

Add a non-mutating `--check` mode to `cmd_pull_globals` that emits a staleness envelope, and wire `/ccanvil-init` to invoke it on entry so operators see drifted user-level skill files surfaced at init time.

## Architectural decisions resolved at plan time

Three open questions exist; resolving them here (not at spec time) keeps the spec lean and the plan executable.

1. **Branch shape inside `cmd_pull_globals`** — Option A: single function with an `if $check ... else ... fi` split. Option B: extract a private helper `_pull_globals_check` and call it from the flag branch. **Chosen: Option A** — the classification loop is 90% identical to the mutate loop; extracting a helper would force passing `src_dir`, `dst_dir`, plus 3-4 accumulators, with no other caller. Single function with the branch is leaner. Promote to a helper only if a second caller (e.g., a future `/recall` ambient probe) materializes.
2. **Envelope contains hub_hash + local_hash, or just names?** — Spec AC-2 requires both hashes populated. **Decision: full hashes.** The `cp` mutate path knows the hashes for free during the loop; surfacing them in the envelope is one `jq -n` extra arg per entry. Costs ~32 bytes per stale file. Worth the deterministic-debuggability ("operator can diff hashes without re-hashing").
3. **Where in `global-commands/ccanvil-init.md` does the probe slot in?** — The hub skill's existing structure has `## Bootstrap and preflight` as Section 1. **Decision: the probe is the FIRST action of `## Bootstrap and preflight`, before the "Run ccanvil-sync.sh init-classify" call.** The probe IS a preflight: it's always-on, always-non-blocking, always before any project-mode branching. Per critic-mode AC-4 fix, this fires regardless of branch (already-initialized / fresh / mature-repo / partial-ccanvil).

## Sequence

### Step 1: AC-1 — envelope shape + idempotency (one failing test → minimal impl)

- **Test:** Add `@test "pull-globals --check: emits envelope with stale_count/missing_count/up_to_date_count, no writes, idempotent"` to `hub/tests/pull-globals.bats`. Seed temp hub with two `ccanvil-*.md` files; seed `FAKE_HOME/.claude/commands/` with identical copies. Assert `--check` exits 0, emits valid JSON containing all five top-level keys with the expected zero/two counts, no diff in `FAKE_HOME/.claude/commands/` mtimes between two consecutive `--check` invocations, byte-identical stdout on the two runs.
- **Implement:** In `cmd_pull_globals`, add `--check) check=true; shift ;;` to the flag parser. After existing env validation + `dst_dir` setup, before the mutate loop, branch: when `$check`, run a parallel classification loop populating three bash arrays (`stale_names`, `stale_hub_hashes`, `stale_local_hashes`, `missing_names`, `up_to_date_count`), emit a single `jq -n` envelope, and `return 0` before the mutate loop. The mutate loop is left unchanged.
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/pull-globals.bats`.
- **Verify:** `bats hub/tests/pull-globals.bats -f "envelope"` — red, then green.

### Step 2: AC-2 — stale detection populates `stale[]` with both hashes

- **Test:** `@test "pull-globals --check: hash mismatch surfaces file in stale[] with hub_hash + local_hash"` — seed FAKE_HOME with a divergent local copy. Parse `jq '.stale | length'` (assert 1), `jq '.stale[0] | (.name and .hub_hash and .local_hash)'` (assert all populated), `jq '.stale_count == 1'`, `jq '.up_to_date_count == 0'`, `jq '.missing_count == 0'`.
- **Implement:** Within the classification loop, when both files exist and `hub_h != local_h`, append `name` / `hub_h` / `local_h` to the three stale arrays. (No-op if Step 1 already implemented this cleanly; the test asserts the field shape.)
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Test passes.

### Step 3: AC-3 — missing detection populates `missing[]`

- **Test:** `@test "pull-globals --check: hub file with no local file surfaces in missing[]"` — temp hub has one `ccanvil-*.md`, `FAKE_HOME/.claude/commands/` empty. Assert `missing_count == 1`, `missing[0].name == "ccanvil-X.md"`, `stale_count == 0`, `up_to_date_count == 0`.
- **Implement:** Within the classification loop, the `[[ ! -f "$dst" ]]` branch appends to the missing array (parallel to the existing mutate branch which `cp`'s).
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Test passes.

### Step 4: AC-8 — degenerate empty-hub case

- **Test:** `@test "pull-globals --check: empty hub global-commands emits zero envelope"` — temp hub has no `ccanvil-*.md` files. Assert exit 0, JSON `{stale_count:0, stale:[], missing_count:0, missing:[], up_to_date_count:0}`.
- **Implement:** Already covered by Step 1's loop (zero iterations → zero accumulators). No additional code expected; if the test fails, the bug is in the `jq -n` envelope's default values (must emit `[]` not `null` for empty arrays — use `--argjson stale "$(...)"` from a `printf '[]'` fallback when count is 0).
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Test passes.

### Step 5: AC-5 — error paths preserved under `--check`

- **Test:** Two tests:
  - `@test "pull-globals --check: \$HOME unset → non-zero exit with clear error"` — `HOME="" run bash ccanvil-sync.sh pull-globals --check`, assert exit non-zero, stderr contains `\$HOME is not set`.
  - `@test "pull-globals --check: missing lockfile → non-zero exit"` — run from a directory without the lockfile, assert non-zero exit, stderr matches `require_lockfile`'s existing error literal.
- **Implement:** The `$HOME` check and `require_lockfile` call are inherited from the existing function head (before the branch). No new code required; tests assert no regression.
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Tests pass.

### Step 6: AC-6 — namespace scope (non-ccanvil files never read)

- **Test:** `@test "pull-globals --check: non-ccanvil-* files in ~/.claude/commands are never reported"` — seed `FAKE_HOME/.claude/commands/` with both `ccanvil-foo.md` (matching a hub file) and `user-owned-tool.md` (no hub counterpart). Assert envelope does NOT mention `user-owned-tool` in any of `stale[]`/`missing[]` (parsed by `jq -r '[.stale[].name, .missing[].name] | .[]' | grep -v user-owned-tool` — actually simpler: assert `jq -r '..|strings'` over the envelope contains no `"user-owned-tool"`).
- **Implement:** The hub-side glob `$src_dir/ccanvil-*.md` already constrains iteration to ccanvil-prefix files. No new code expected; test asserts the glob discipline.
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Test passes.

### Step 7: AC-7 — `pull-globals` (without --check) unchanged

- **Test:** `@test "pull-globals (no --check): existing copy/skip/conflict envelope unchanged"` — verify with seeded fixture that the existing top-level keys `{copied, skipped, conflicts}` are still emitted (and ONLY those keys; the new staleness keys do NOT appear in mutate mode). This is a regression guard.
- **Implement:** The flag branch returns early when `$check` is set; the mutate path is untouched. Assertions only — no new code.
- **Files:** `hub/tests/pull-globals.bats`.
- **Verify:** Test passes.

### Step 8: AC-4 — `/ccanvil-init` skill prose invokes the probe

- **Test:** Add `@test "AC-4: skill invokes pull-globals --check as first preflight action"` to `hub/tests/ccanvil-init-skill.bats`. Grep-style: assert `global-commands/ccanvil-init.md` contains the literal `pull-globals --check`, AND the literal recommendation line `Run /ccanvil-pull-globals to refresh, then re-run /ccanvil-init.`, AND the warning emit appears in the `## Bootstrap and preflight` section BEFORE any `init-classify` reference. Three greps; all must pass.
- **Implement:** Edit `global-commands/ccanvil-init.md` — under `## Bootstrap and preflight`, prepend a new sub-step (numbered ahead of the existing init-classify call) that says:

  ```
  ### Step 0: User-level skill staleness probe

  Always run, regardless of project_mode:

  ```bash
  staleness=$(bash .ccanvil/scripts/ccanvil-sync.sh pull-globals --check 2>/dev/null)
  drift=$(echo "$staleness" | jq -r '.stale_count + .missing_count')
  if [[ "$drift" -gt 0 ]]; then
    echo "WARN: $drift user-level ccanvil-* skill file(s) have drifted from hub canonical:" >&2
    echo "$staleness" | jq -r '(.stale[].name, .missing[].name)' | head -5 | sed 's/^/  - /' >&2
    [[ "$drift" -gt 5 ]] && echo "  + $((drift - 5)) more" >&2
    echo "" >&2
    echo "Run /ccanvil-pull-globals to refresh, then re-run /ccanvil-init." >&2
  fi
  ```

  Proceed to the next step regardless of staleness — this is informational, not gating.
  ```

- **Files:** `global-commands/ccanvil-init.md`, `hub/tests/ccanvil-init-skill.bats`.
- **Verify:** `bats hub/tests/ccanvil-init-skill.bats -f "AC-4"`.

### Step 9: Manifest update for `cmd_pull_globals`

- **Test:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json` — assert no new drift introduced (`status: "ok"`, drift `[]`).
- **Implement:** Update `cmd_pull_globals`'s existing `@manifest` block above the function to declare the new mode in `input:` (`optional: --check (probe-only, no writes; emits staleness envelope)`) and in `output:` (`stdout: probe envelope JSON when --check is set`). Add a `# caller: global-commands/ccanvil-init.md` comment since the skill is now a confirmed caller (was previously only `skill:/ccanvil-pull-globals`).
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`.
- **Verify:** Manifest drift count unchanged or zero.

### Step 10: Full-suite verification

- **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel`.
- **Implement:** None — verification only.
- **Files:** None.
- **Verify:** All bats pass (modulo the known pre-existing `module-manifest-query-helpers.bats:46` parallel flake, which is unrelated to this work).

## Risks

- **R1: jq `null` vs `[]` for empty arrays.** When all accumulator arrays are empty (e.g., AC-8 degenerate case), `jq -n --argjson stale "$EMPTY"` could emit `null` instead of `[]` depending on how `$EMPTY` is built. Mitigation: build empty arrays explicitly with `printf '[]'` and feed via `--argjson`; assert AC-8 test catches any regression. (Step 4.)
- **R2: bash array → JSON serialization quoting.** File names contain `-` and `.`; passing them to `jq` via `--arg` per-entry is safe but verbose. Alternative: emit a JSONL-shaped string from bash and pipe to `jq -s` to wrap into the final envelope. The two are functionally equivalent; Step 1 picks whichever reads cleanest given the existing `cmd_pull_globals` style.
- **R3: `# caller:` manifest line — over-declaration.** The substrate already declares `skill:/ccanvil-pull-globals` as a caller. Adding `global-commands/ccanvil-init.md` is correct (per `feedback_manifest_authoring_is_substrate_dogfood`: only declare callers that grep-resolve). Verify the grep resolves before declaring.
- **R4: existing pull-globals tests are parallel-safe?** The temp-hub + FAKE_HOME pattern is per-test; bats runs each test in its own subshell. The new tests follow the same shape, so they should be parallel-safe. Confirm in Step 10.
- **R5: AC-4 wording on warning destination.** Spec says stderr; the implementation snippet writes to stderr via `>&2`. The test asserts the literal recommendation line appears in the skill file — which it will. If the implementer changes the destination during impl (e.g., stdout), the bats test still passes (it greps the file), but the spec is violated. Mitigation: keep `>&2` in the implemented snippet; reviewer-agent should catch a destination flip.

## Definition of Done

- [ ] AC-1 through AC-8 pass via `hub/tests/pull-globals.bats` and `hub/tests/ccanvil-init-skill.bats`.
- [ ] Full `bats-report.sh --parallel` green (modulo pre-existing module-manifest-query-helpers flake).
- [ ] `module-manifest.sh validate` returns `status: "ok"`, drift `[]`.
- [ ] No new permissions-audit DANGER findings; no new secret/PII patterns.
- [ ] `/review` clean (or WARN-level findings triaged + commented).
- [ ] PR #180 title force-updated by `assert-pr-title`; description carries the spec excerpt.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
