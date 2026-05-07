# Implementation Plan: LINEAR_API_KEY auth-chain extension

> Feature: bts-331-linear-key-distribution
> Work: linear:BTS-331
> Created: 1778185800
> Spec hash: c78be528
> Based on: docs/spec.md

## Objective

Extend `linear-query.sh`'s auth-resolution chain with `~/.env` and macOS Keychain fallback tiers so any downstream-node session can dispatch Linear-routed substrate primitives without per-project key distribution.

## Sequence

### Step 1: Bats fixture — auth-chain stub harness

- **Test:** Create `hub/tests/linear-query-auth-chain.bats` with a setup() that builds `$STUB_DIR` containing a fake `security` script driven by `STUB_KEYCHAIN_VALUE` and `STUB_KEYCHAIN_EXIT`. Single failing AC-1 test: when `LINEAR_API_KEY=lin_api_x` is exported, calling `_load_env_if_needed`-equivalent (via `linear-query.sh viewer` with stubbed `LINEAR_QUERY_OVERRIDE`-like seam — or call the function directly via `bash -c "source linear-query.sh; _load_env_if_needed; echo \$LINEAR_API_KEY"` if sourceability holds). Confirm precedence: exported env wins, no .env or keychain consulted.
- **Implement:** Test fixture + stub script only. AC-1 test is the red marker; existing code already passes it (env-var precedence is preserved in current implementation), so the test should pass on first run — establishing the harness.
- **Files:** `hub/tests/linear-query-auth-chain.bats` (new), `.ccanvil/manifest-allowlist.txt` (register).
- **Verify:** `bash .ccanvil/scripts/bats-report.sh -f 'AC-1' --parallel` returns the new test green.

### Step 2: AC-2 regression test — project `.env` walk-up preserved

- **Test:** Add AC-2 test: under tmpdir cd-context with mocked `.git` and `.env` containing `LINEAR_API_KEY=lin_proj_y`, confirm precedence — the project `.env` wins when env var is unset.
- **Implement:** No code change yet — verify existing behavior. If green, harness covers tier-2 regression.
- **Files:** `hub/tests/linear-query-auth-chain.bats` (extend).
- **Verify:** AC-2 test green; existing passes intact.

### Step 3: AC-3 — `~/.env` fallback tier

- **Test:** Add AC-3 test: `HOME=$FAKE_HOME` with `$FAKE_HOME/.env` containing `LINEAR_API_KEY=lin_home_z`, no project `.env`, no env var. Expect resolution to `lin_home_z`. RED — current implementation has no `~/.env` tier.
- **Implement:** Extend `_load_env_if_needed` in `linear-query.sh` after the `.git` walk-up loop: if still unset and `$HOME/.env` exists, source it under `set -a` / `set +a`. Mirror existing source pattern (preserve scope-leak comment context).
- **Files:** `.ccanvil/scripts/linear-query.sh`.
- **Verify:** AC-3 green; AC-1 + AC-2 still green.

### Step 4: AC-4 + AC-5 — macOS Keychain tier with mapping

- **Test:** Add AC-4 + AC-5 tests: stub `security` returns `lin_keychain_q` when called with `-s linear_api_key`; no env var, no `.env` files, `HOME` empty. Expect resolution to `lin_keychain_q`. Add AC-5 mapping assertion (script comment grep).
- **Implement:** After `~/.env` tier in `_load_env_if_needed`: gate on `command -v security >/dev/null 2>&1`; call `security find-generic-password -a "$USER" -s linear_api_key -w 2>/dev/null`; check both rc=0 AND non-empty output before exporting. Add the `LINEAR_API_KEY → linear_api_key` mapping comment.
- **Files:** `.ccanvil/scripts/linear-query.sh`.
- **Verify:** AC-4 + AC-5 green; tiers 1–3 still green.

### Step 5: AC-6 — graceful no-op when `security` absent

- **Test:** Test where `$STUB_DIR` lacks `security`, `PATH` is restricted to `$STUB_DIR:/usr/bin` (no system `/usr/bin/security`). Expect tier-4 to skip silently and chain to fall through to tier-5 error (or pre-existing successful tier-3 if `~/.env` populated). No stderr noise from the keychain step.
- **Implement:** Already covered by `command -v` gate from Step 4 — this test is regression coverage. If the gate works, AC-6 passes without code change.
- **Files:** `hub/tests/linear-query-auth-chain.bats`.
- **Verify:** AC-6 green.

### Step 6: AC-8 — updated error message naming all 4 tiers

- **Test:** AC-8 test: all 4 tiers miss; expect `_require_api_key` to exit 2 with stderr containing each of `LINEAR_API_KEY`, `.env at the project root`, `~/.env`, and `linear_api_key` (Keychain service name).
- **Implement:** Update the `_die 2 ...` message string in `_require_api_key` to enumerate all tiers in resolution order.
- **Files:** `.ccanvil/scripts/linear-query.sh`.
- **Verify:** AC-8 green. Confirm via grep that pre-existing error-message expectations elsewhere in the test suite aren't tightly coupled to the old wording (`grep -rn "LINEAR_API_KEY not set" hub/tests/`).

### Step 7: Live-API validation (BTS-171 gate, AC-10)

- **Test:** Live invocation — not bats. From a fresh shell:
  ```bash
  cd ~/projects/web-browser-toolbox
  unset LINEAR_API_KEY
  bash ~/projects/ccanvil/.ccanvil/scripts/linear-query.sh viewer
  ```
  Expect `{id, name}` JSON success via the keychain tier.
- **Implement:** No code — validation only. **This step is BLOCKING per `.claude/rules/tdd.md#live-api-validation-gate`** — keychain integration cannot be verified by stubs alone. The `security` command's interactive-approval semantics are unknowable from the test harness; only a live invocation proves the chain works end-to-end. Run BEFORE commit and BEFORE `/pr`.
- **Files:** none.
- **Verify:** Capture `Command:`, `Output:`, `Exit:`, `Reproduce:` evidence anchors per `.claude/rules/evidence-required-for-captures.md`. Paste into a stasis or commit body.

### Step 8: Test-suite verify + module-manifest sync

- **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green.
- **Implement:** Add `# @manifest` block to the new bats file's purpose comment. Run `bash .ccanvil/scripts/module-manifest.sh validate --json` and confirm coverage 194/194 drift 0 (current is 193/193, +1 for the new bats file).
- **Files:** `hub/tests/linear-query-auth-chain.bats`, `.ccanvil/manifest-allowlist.txt`.
- **Verify:** Full bats suite green; manifest drift 0.

### Step 9: Documentation update — none required

- The substrate change is internal to `linear-query.sh`. The `_require_api_key` error message is the operator-visible surface; AC-8 covers it.
- No `.ccanvil/guide/` update needed — `linear-query.sh` is not documented at the verb level there.
- No CLAUDE.md change — auth-chain mechanics are below the CLAUDE.md abstraction line.

## Risks

- **Sourceability of `linear-query.sh`.** The script ships with `set -euo pipefail` and a top-level dispatch. If `bash -c "source linear-query.sh; _load_env_if_needed"` triggers the dispatch instead of sourcing the function, AC tests need to invoke through a subcommand (e.g., `viewer`) rather than calling `_load_env_if_needed` directly. Mitigation: read the script's tail before writing tests; if a `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard exists, source works; otherwise wrap tests around `viewer` invocations with stubbed graphql endpoint.
- **`security` interactive prompt on first run.** Operator already approved the keychain entry on the prior `find-generic-password` invocation when storing the key. Subsequent calls from the same process tree should be silent. If a fresh shell triggers a prompt, AC-7 covers the live-validation step. Mitigation: run AC-10 from a fresh shell to surface this if it happens.
- **`/usr/bin/security` on `PATH` shadowing the stub.** The fixture must set `PATH=$STUB_DIR:$PATH` first AND ensure `$STUB_DIR/security` is executable. Cross-check with `which security` from inside the bats test.

## Definition of Done

- [ ] All 10 acceptance criteria from spec pass (9 via bats, 1 via live invocation per AC-10)
- [ ] All existing tests still pass (193/193 → 194/194)
- [ ] Manifest drift 0
- [ ] Live-API gate (Step 7) executed with evidence anchors captured
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
