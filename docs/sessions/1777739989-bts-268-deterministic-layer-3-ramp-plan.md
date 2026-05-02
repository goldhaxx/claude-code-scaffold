# Implementation Plan: Deterministic Layer 3 ramp — diff-vs-manifest

> Feature: bts-268-deterministic-layer-3-ramp
> Work: linear:BTS-268
> Created: 1777737656
> Spec hash: 7f96c2e0

## Objective

Ship `cmd_diff_vs_manifest` in `module-manifest.sh` (pure bash + awk + grep), wire it into `/review`'s Step 0 pre-flight as a BLOCKING gate, and self-manifest at 100% drift-guard.

## Sequence

### Step 1: Test scaffold + AC-7 (missing diff file)

* **Test:** `hub/tests/module-manifest-diff-vs-manifest.bats`. First test: `diff-vs-manifest --diff /nonexistent` → exit 2, stderr matches `diff file not found`.
* **Implement:** Stub `cmd_diff_vs_manifest` with `--diff` flag parsing + missing-file error path. Add dispatch entry + Usage update.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/module-manifest-diff-vs-manifest.bats` (new).
* **Verify:** 1 test passing.

### Step 2: AC-6 (clean diff → empty drift)

* **Test:** Fixture diff `hub/tests/fixtures/manifest/diffs/clean.diff` touching only docs (no manifested paths). Expect `{drift:[],status:"ok"}`, exit 0.
* **Implement:** Stub returns `{drift:[],status:"ok"}` envelope when no candidate drift found.
* **Verify:** Step 1 + 2 green.

### Step 3: AC-2 — new-caller-not-declared

* **Test:** Fixture diff that ADDS a new file `.claude/skills/foo/SKILL.md` whose body invokes `cmd_extract` (manifested). Expect drift entry `{drift_type:"new-caller-not-declared", path:".ccanvil/scripts/module-manifest.sh:cmd_extract", value:".claude/skills/foo/SKILL.md"}`. Exit 2.
* **Implement:** Parse diff `+++ b/<path>` headers + `^+` body lines (excluding `+++`). For each NEW caller-eligible path (`.claude/{skills,commands,rules,agents}/*`, `.ccanvil/scripts/*.sh`, `.claude/hooks/*.sh`): scan its added body for any `cmd_X\b` where `cmd_X` is on the allowlist. Cross-reference primitive's existing `caller:` list (extract via `cmd_extract`). Emit drift if new caller not declared.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, fixture `.diff`.
* **Verify:** Steps 1-3 green.

### Step 4: AC-3 — new-depends-on-not-declared

* **Test:** Fixture diff adding a `bash linear-query.sh ...` line INSIDE the body of an existing manifested primitive (e.g., `cmd_query` body), but `linear-query.sh` is NOT in the manifest's `depends-on:`. Expect drift entry.
* **Implement:** For each touched manifested file in the diff, find added lines that fall inside a primitive's body (function-level: brace-counted; file-level: whole file). Extract candidate dep tokens (`bash <script>`, `jq`, `<helper_fn>`, etc.) from added lines; cross-ref against manifest's `depends-on:` array. Emit drift on mismatch.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, fixture `.diff`.
* **Verify:** Steps 1-4 green.

### Step 5: AC-4 — new-exit-path-not-declared

* **Test:** Fixture diff adding `+ return 7` (or `+ exit 7`) inside a manifested primitive's body where the manifest's `failure-mode:` list has no `exit=7` entry. Expect drift entry with `value: "7"`.
* **Implement:** Scan added lines for `^[+]\s*(return|exit)\s+([1-9][0-9]*)` (N != 0). For each, parse the manifest's `failure-mode:` array, extract exit codes via `exit=<N>` segment, compare. Emit drift on novel exit.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, fixture `.diff`.
* **Verify:** Steps 1-5 green.

### Step 6: AC-5 — new-side-effect-not-declared

* **Test:** Fixture diff adding `+   # @side-effect: writes-some-file` inside a manifested primitive's body where the manifest's `side-effect:` array doesn't list `writes-some-file`. Expect drift entry.
* **Implement:** Scan added lines for `^[+]\s*#\s*@side-effect:\s*(\S+)` markers. Extract the marker id, cross-ref against manifest's `side-effect:` array. Emit drift on novel marker.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, fixture `.diff`.
* **Verify:** Steps 1-6 green.

### Step 7: stdin support (`--diff -`)

* **Test:** Tests up to now use `--diff <path>`. Add a smoke test that pipes a fixture file via stdin (`< clean.diff bash module-manifest.sh diff-vs-manifest --diff -`) and gets the same envelope.
* **Implement:** When `--diff -`, read from stdin to a tempfile, then re-enter the file path code path.
* **Verify:** All tests green.

### Step 8: AC-10 — drift-guard self-check

* **Implement:** Add `# @manifest` block above `cmd_diff_vs_manifest` (purpose / input / output / side-effect=reads-diff-and-allowlist / failure-mode markers / contract / anchor=BTS-268). Add allowlist entry. Add `@failure-mode` and `@side-effect` markers in body.
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate` (or spot-test with tiny allowlist of just this entry) exits 0.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `.ccanvil/manifest-allowlist.txt`.

### Step 9: AC-8 — wire into /review

* **Implement:** Edit `.claude/commands/review.md` Step 0 (or the manifest pre-flight section) to ALSO run `bash .ccanvil/scripts/module-manifest.sh diff-vs-manifest --diff <(git diff main...HEAD)` and surface its `drift[]` to the review report. When non-empty, all entries are BLOCKING.
* **Files:** `.ccanvil/commands/review.md`.
* **Verify:** Manual read-through.

### Step 10: Final verification

* **Verify:** Full bats suite green; manifest coverage 185 → 186 (cmd_diff_vs_manifest); drift `[]`. Live dogfood: run `git diff main...HEAD | bash module-manifest.sh diff-vs-manifest --diff -` on the BTS-268 branch itself to confirm self-application surfaces no false-positive drift on our own commits.

## Risks

* **Diff parsing brittleness** — git diff format edge cases (rename, binary, very long context). Mitigation: scope first ship to common cases (file add / modify); rename/copy fall through as plain modify of the new path.
* **Body-scope detection on file-level scripts** — `_target_body_grep` already handles file-level (whole-file scope). Reuse rather than re-implement.
* **False positives on new-depends-on** — distinguishing "this is a real new dep" from "this is just a string in a comment / heredoc / different scope" is hard. Mitigation: be permissive — flag everything that looks like a new dep + let the operator decide. Better to over-surface than under-surface in the first ramp.
* **Live-API contract risk: NONE.** Pure local diff parsing — no API calls, no live services.

## Definition of Done

- [ ] All 10 spec ACs pass.
- [ ] `bats hub/tests/module-manifest-diff-vs-manifest.bats` — all new tests passing.
- [ ] Full suite parallel — 1937+N / 1937+N passing.
- [ ] `module-manifest.sh validate` → 186/186 covered, drift \[\]. (Spot-tested via tiny allowlist if full validate is slow.)
- [ ] `/review` Step 0 invokes `diff-vs-manifest`; manual read confirms.
- [ ] Live dogfood on BTS-268's own branch produces sensible output (likely just self-additions, no drift on existing primitives).
