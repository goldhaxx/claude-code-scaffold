# Implementation Plan: Flip Linear routing on hub for spec/plan/stasis

> Feature: bts-217-flip-linear-routing
> Work: linear:BTS-217
> Created: 1777304400
> Spec hash: bc066ebf
> Based on: docs/spec.md

## Objective

Add three routing keys to `.claude/ccanvil.local.json` so the hub's lifecycle docs (spec, plan, stasis) write to and read from Linear Documents instead of branch-local files, then validate the full SSOT-Linear flow end-to-end against the live API in this same session.

## Sequence

Each step is small. No bats tests are added — this ship's "tests" are end-to-end live-API validations executed against `api.linear.app`. The substrate it dogfoods is already covered by the BTS-204/213/214/216 test suite (1707/1707).

### Step 1: Edit `.claude/ccanvil.local.json` to add the 3 routing keys

- **Test:** N/A (configuration change). Pre-state assertion: `route-of spec` returns `local`. Post-state assertion: `route-of spec`, `route-of plan`, `route-of stasis` all return `linear`.
- **Implement:** Use `jq` to add the three routing keys peer to `routing.idea`. Pattern:

  ```bash
  jq '.integrations.routing.spec = "linear"
    | .integrations.routing.plan = "linear"
    | .integrations.routing.stasis = "linear"' \
    .claude/ccanvil.local.json > .claude/ccanvil.local.json.tmp && \
    mv .claude/ccanvil.local.json.tmp .claude/ccanvil.local.json
  ```

- **Files:** `.claude/ccanvil.local.json`
- **Verify:**
  ```bash
  bash .ccanvil/scripts/docs-check.sh route-of spec    # → linear
  bash .ccanvil/scripts/docs-check.sh route-of plan    # → linear
  bash .ccanvil/scripts/docs-check.sh route-of stasis  # → linear
  bash .ccanvil/scripts/docs-check.sh route-of idea    # → linear (unchanged)
  ```
  Confirms AC-1.

### Step 2: Live artifact-write smoketest

> **Live-API validation gate (per `tdd.md`):** AC-2 explicitly flags a live-API contract step. Stubs cannot verify this — only the live call against `api.linear.app` does. Run the live command before treating Step 2 complete.

- **Test:** Pipe a smoketest body into `cmd_artifact_write` with `--kind spec --feature BTS-217`. Capture stdout + exit code. Expected: exit 0, stdout contains a Linear Document URL.

- **Implement:**
  ```bash
  set -a; source .env 2>/dev/null; set +a   # surface LINEAR_API_KEY if .env is gitignored
  printf '# smoketest body for AC-2\n\nDocument round-trip verifier.\n' \
    | bash .ccanvil/scripts/docs-check.sh artifact-write \
        --kind spec --feature BTS-217 --project-dir .
  ```

- **Files:** none modified.
- **Verify:** Document is parented to BTS-217 issue. Cross-check via Linear MCP:
  ```bash
  bash .ccanvil/scripts/linear-query.sh list-documents --issue BTS-217 --with-content \
    | jq '.[] | {id, title, parentIssue: .issue.identifier}'
  ```
  Confirms AC-2.

### Step 3: Live artifact-read symmetry

- **Test:** `cmd_artifact_read` for the same kind/feature must return the body written in Step 2 (NOT the contents of `docs/specs/bts-217-flip-linear-routing.md`).

- **Implement:**
  ```bash
  bash .ccanvil/scripts/docs-check.sh artifact-read \
    --kind spec --feature BTS-217 --project-dir .
  ```

- **Files:** none.
- **Verify:** stdout contains the smoketest body from Step 2, NOT the spec template. Confirms AC-3.

### Step 4: Replace smoketest with actual spec content

- **Test:** N/A (data move). Required so /pr embed reads meaningful content in Step 5.

- **Implement:**
  ```bash
  bash .ccanvil/scripts/docs-check.sh artifact-write \
    --kind spec --feature BTS-217 --project-dir . \
    < docs/specs/bts-217-flip-linear-routing.md
  ```

- **Files:** none locally; updates the Linear Document.
- **Verify:** `cmd_artifact_read` returns the spec body verbatim.

### Step 5: Run /pr and verify embed reads from Linear

- **Test:** PR body's spec section must contain content sourced from the Linear Document (Step 4), not from `docs/spec.md`.

- **Implement:** Run `/pr` (which calls `pr-cleanup` then marks the PR ready). Inspect the rendered body via:
  ```bash
  gh pr view 116 --json body --jq .body | grep -A 20 '## Spec'
  ```

- **Files:** PR body on GitHub.
- **Verify:** PR body shows the BTS-217 spec content. Confirms AC-4.

### Step 6: Verify /complete archives + trashes

- **Test:** After `pr-cleanup`, three files appear under `docs/sessions/<epoch>-bts-217-flip-linear-routing-{spec,plan,stasis}.md` and the originals no longer surface in `list-documents` (default excludes trashed).

- **Implement:** This happens automatically inside `pr-cleanup`'s call to `cmd_complete` → `_complete_archive_linear`. No manual action needed; verify post-fact.

- **Files:** new files in `docs/sessions/`. Linear Documents trashed.
- **Verify:**
  ```bash
  ls docs/sessions/*bts-217-flip-linear-routing*    # → 3 files (spec, plan, stasis)
  bash .ccanvil/scripts/linear-query.sh list-documents --issue BTS-217 \
    | jq 'length'                                   # → 0 (trashed by default)
  ```
  Confirms AC-5.

### Step 7: Verify downstream nodes unaffected

- **Test:** `.claude/ccanvil.json` (hub-tracked) is unmodified by this work. Reading any registered downstream's local config shows spec/plan/stasis defaulting to local (or absent).

- **Implement:** None — assertion check only.
- **Files:** read-only inspection.
- **Verify:**
  ```bash
  git diff main...HEAD -- .claude/ccanvil.json    # → empty diff
  cat .ccanvil/registry.json | jq -r '.nodes[].path' \
    | while read -r p; do
        printf '%s: ' "$p"
        jq -r '.integrations.routing.spec // "(unset)"' "$p/.claude/ccanvil.local.json" 2>/dev/null \
          || echo '(no local config)'
      done
  ```
  Each downstream should print `local` or `(unset)` — never `linear`. Confirms AC-6.

### Step 8: Verify graceful degradation under API failure

- **Test:** With `LINEAR_API_KEY` unset, lifecycle commands warn but do not abort.

- **Implement:**
  ```bash
  env -u LINEAR_API_KEY bash .ccanvil/scripts/docs-check.sh artifact-read \
    --kind spec --feature BTS-217 --project-dir .
  ```

- **Files:** none.
- **Verify:** Command emits a `WARN:` line on stderr containing a retry recipe. Exit code is 0 OR 2 (per substrate convention) but never aborts the parent command. Confirms AC-7.

### Step 9: Documentation update — note flip in `hub/meta/operations.md`

- **Test:** N/A (doc).
- **Implement:** Add a short subsection under Hub Operations describing that hub uses `routing.{idea,spec,plan,stasis}=linear` as of 2026-04-27, and that this is hub-only (downstream nodes opt in independently).
- **Files:** `hub/meta/operations.md`
- **Verify:** Diff shows the addition; new section renders.

## Risks

- **R1: Live API rate-limit during Steps 2–4.** Three sequential mutations + reads. Mitigation: small payloads, single-feature scope, retry budget. If hit, flip-back via `git checkout .claude/ccanvil.local.json` and rerun.

- **R2: Document already exists from prior dogfood test.** During the BTS-216 session, an `artifact-write --kind spec --feature BTS-215` test ran. Same-feature collision is possible if BTS-217 was used as a prior dogfood target. Mitigation: `cmd_artifact_write` in the substrate is upsert-aware (BTS-204 logic); the deterministic UUID will hit the existing Document if one exists, no error. Verify in Step 2 by inspecting whether the returned URL is a NEW Document or an updated one (Linear's response includes `createdAt` vs `updatedAt`).

- **R3: PR body embed for a Linear-routed spec returns empty when `/pr` runs against a spec that was never uploaded.** Step 4 mitigates by uploading the actual spec body before Step 5. Without Step 4, the PR body would inline the smoketest from Step 2, making AC-4 meaningless.

- **R4: Project_id discrepancy between BTS-217 ticket body and live config.** Spec implementation note covers this — local config (`305b7cbe…`) is canonical; ticket body is wrong (`0c5fec47…`). Do NOT propagate the wrong value. Add a Linear comment correction post-merge.

- **R5: Step-1 jq edit could clobber `ccanvil.local.json` on a typo.** Mitigation: test the jq pipeline against a temp file first; verify output is valid JSON via `jq . <file>` before overwriting.

## Definition of Done

- [ ] All 7 acceptance criteria from `docs/spec.md` pass (verified in Steps 1–8 above).
- [ ] `.claude/ccanvil.json` is unmodified (downstream-isolation guarantee).
- [ ] Existing test suite still passes: `bash .ccanvil/scripts/bats-report.sh --parallel` → 1707/1707.
- [ ] `/review` run (per `pr` skill default), no CRITICAL findings.
- [ ] `hub/meta/operations.md` updated with the flip note (Step 9).
- [ ] Linear comment posted on BTS-217 correcting the project_id in the ticket body.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
