# Feature: provider-heal-auth substrate (Phase 3 of provider-heal)

> Feature: bts-321-provider-heal-auth
> Work: linear:BTS-321
> Created: 1778170230
> Subject: provider-heal-auth substrate (Phase 3 of provider-heal)
> Status: Complete

## Summary

Add `docs-check.sh provider-heal-auth` — a single-verb substrate that verifies the Linear provider's authentication is sourceable AND functional. Phase 3 of the provider-heal umbrella (Phase 1 = `provider-resolve-ids` BTS-319; Phase 2 = `provider-heal-preflight` BTS-320). The substrate sources the standard `.env` chain, checks `LINEAR_API_KEY` presence, and runs `linear-query.sh viewer` as a live smoke-test to confirm the key is actually valid against the Linear API. Read-only — no state mutation. Empirical anchor: unifi-toolbox 2026-05-06 had no `.env` file and `LINEAR_API_KEY` was not in shell env; the manual heal worked only because we sourced `~/projects/ccanvil/.env` at the prompt. The heal flow MUST verify auth before declaring success — otherwise heal "succeeds" but next dispatch fails on auth with no clear remediation path.

## Job To Be Done

**When** I'm running the heal flow on a partially-configured downstream node,
**I want to** know in one read-only command whether `LINEAR_API_KEY` is sourceable from the standard env chain AND functional against the live Linear API,
**So that** auth failures are caught at preflight rather than mid-heal as confusing GraphQL 401 errors.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh provider-heal-auth --project-dir <path>` exits 0 with stdout `AUTH-OK: viewer=<viewer-id>` (newline-terminated) when `LINEAR_API_KEY` is set in shell env AND `linear-query.sh viewer` returns a non-empty `.id`.
- [ ] **AC-2:** Source order when `LINEAR_API_KEY` is not in shell env: (a) try `<project_dir>/.env`, (b) try `$HOME/.env`. First source that yields a non-empty key wins. Sourcing uses `set -a; source <file>; set +a` semantics so other env vars in the file don't leak.
- [ ] **AC-3:** Error: when `LINEAR_API_KEY` is missing from shell env AND not present in either `.env` file, exits non-zero with stderr `ERROR: LINEAR_API_KEY not found in shell env, <project>/.env, or ~/.env. Generate at https://linear.app/settings/api and add to shell env or .env.`
- [ ] **AC-4:** Error: when `LINEAR_API_KEY` is set but `linear-query.sh viewer` fails (HTTP 401, network error, exit non-zero), exits non-zero with stderr `ERROR: LINEAR_API_KEY found but viewer smoke-test failed. Key may be invalid, expired, or revoked.` plus the wrapper's stderr verbatim under `WRAPPER ERROR:` prefix.
- [ ] **AC-5:** Output is structured JSON when `--json` flag is passed: `{status: "ok"|"missing-key"|"invalid-key"|"wrapper-error", key_source: "shell-env"|"<path>/.env"|"~/.env"|null, viewer_id: <id>|null, error: <string>|null}`. Default text output for human reading; JSON for skill composition.
- [ ] **AC-6:** No side-effects to caller's shell: env vars sourced from `.env` files inside the substrate must NOT leak into the parent shell. (The substrate runs in its own bash invocation; this is automatic, but verified by setup that runs the substrate then asserts `LINEAR_API_KEY` is still unset in the test shell.)
- [ ] **AC-7:** Bats coverage at `hub/tests/provider-heal-auth.bats` using `LINEAR_QUERY_OVERRIDE` for the viewer call. Tests AC-1 (key in env), AC-2 (key sourced from project .env), AC-3 (missing everywhere), AC-4 (key set but viewer fails), AC-5 (--json shape), AC-6 (env isolation).
- [ ] **AC-8:** Manifest declared per Layer 2: `cmd_provider_heal_auth` includes `# @manifest` block declaring purpose/input/output/depends-on/side-effect=read-only/failure-mode/contract. Registered in `.ccanvil/manifest-allowlist.txt`. Drift-guard validates 100%.
- [ ] **AC-9:** Full bats suite passes — 2007/2007 baseline maintained or improved.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_provider_heal_auth` function + `provider-heal-auth` subcommand dispatch + `PROJECT_TREE_SUBCOMMANDS` registration (BTS-212 invariant) |
| `hub/tests/provider-heal-auth.bats` | New: bats coverage for AC-1 through AC-6 using `LINEAR_QUERY_OVERRIDE` for viewer stub |
| `.ccanvil/manifest-allowlist.txt` | Modified: register `cmd_provider_heal_auth` |

## Dependencies

- **Requires:** existing `linear-query.sh viewer` subcommand (already shipped, BTS-164/166/167 era).
- **Requires:** existing `LINEAR_QUERY_OVERRIDE` test pattern (already shipped, BTS-203 era).
- **Blocked by:** none.

## Out of Scope

- **Auto-creating `.env` or prompting for the key.** The substrate is a read-only check; it surfaces the missing-key error with a clear remediation message but does not mutate `.env`.
- **Composing into the `provider-heal` umbrella.** That's the next ship after Phase 3 lands — orchestrates Phase 1 (BTS-319) + Phase 2 (BTS-320) + Phase 3 (this) into one verb.
- **OAuth or alternative auth flows.** API-key only.
- **Verifying the key's specific scope/permissions.** Viewer smoke-test only confirms the key is valid for read-only auth. Other scopes are checked when the corresponding operations run.

## Implementation Notes

- Mirror `cmd_provider_heal_preflight` (BTS-320) shape: read-only, `--project-dir` + `--json` flags, structured JSON envelope, deterministic stub via `LINEAR_QUERY_OVERRIDE`.
- Source-order chain: shell env first, then `<project>/.env`, then `~/.env`. Must use a subshell or save/restore to prevent env leak — actually since this is a function inside docs-check.sh which itself runs as a fresh bash invocation per command call, the leak concern is automatically handled.
- Inside the function, when sourcing `.env` files, use `set -a` + `source` + `set +a` to export every assignment temporarily for the viewer call.
- `--json` output: parse viewer-id from `linear-query.sh viewer 2>/dev/null | jq -r '.id // empty'` for the success case; null on failure.
- Anchor file references for AC-7 (per BTS-265 file-ref validator): `.ccanvil/scripts/linear-query.sh`, `.claude/rules/provider-integration.md`.
- Pure read-only deterministic substrate per `.claude/rules/deterministic-first.md`.
