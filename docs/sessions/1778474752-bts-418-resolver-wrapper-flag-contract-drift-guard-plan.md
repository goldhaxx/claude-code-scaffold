# Implementation Plan: resolver-wrapper-flag-contract drift-guard

> Feature: bts-418-resolver-wrapper-flag-contract-drift-guard
> Work: linear:BTS-418
> Created: 1778473200
> Spec hash: ba69b29a
> Based on: docs/spec.md

## Objective

Add a deterministic merge-time fixture in `hub/tests/operations-drift-guard.bats` that, for every http-mechanism resolver verb in `linear_mcp_adapter`, statically verifies every emitted `--<flag>` is accepted by the target `linear-query.sh` subcommand. Inline bats helpers; per-verb `@test` granularity; hub-only.

## Architectural Decisions (resolving spec Open Questions)

1. **Implementation shape:** **Option 1 — inline bats helpers.** Two parse helpers (`_emitted_flags`, `_wrapper_accepted_flags`) + one mapping helper (`_target_wrapper_subcmd`) + one contract-check helper (`_check_flag_contract`) defined at the top of the fixture file. No new substrate scripts, no manifest changes, no extra drift surface. Promote to Option 2 only if a future `/review` or `/ccanvil-audit` consumer needs the check from outside bats.
2. **Test granularity:** **One** `@test` per verb (mirrors BTS-419 Step 7/8 shape). Better bats-tap failure isolation in `--progress` mode + each verb's failure shows as its own line.
3. **Hub-only / downstream:** **Hub-only.** This is a static contract-check on hub-controlled scripts; downstream nodes inherit it via the BTS-419 runtime self-consistency check that's already shipping. No node-side counterpart needed.

## Sequence

### Step 1: Resolver-side flag extraction (AC-1)

* **Test:** Three bats tests verifying `_emitted_flags` returns: `[]` for an envelope with command `bash .ccanvil/scripts/linear-query.sh list-issues`; `["--team"]` for `... list-issues --team T`; the full sorted set for the live `backlog.list` envelope under `_with_linear_routing_and_project_id`.
* **Implement:** Define `_emitted_flags()` in the bats file. Reads JSON from stdin or arg, extracts `.invocation.command`, runs `grep -oE -- '--[a-z][a-z0-9-]*' | sort -u`.
* **Files:** `hub/tests/operations-drift-guard.bats` (append below existing BTS-419 tests).
* **Verify:** `bats hub/tests/operations-drift-guard.bats --filter 'BTS-418 Step 1'` → 3/3 green.

### Step 2: Wrapper-side flag extraction (AC-2)

* **Test:** Two bats tests. (a) `_wrapper_accepted_flags list-issues` returns exactly `--label --limit --project --project-id --state --team`. (b) `_wrapper_accepted_flags save-issue` returns the union expected from `cmd_save_issue`.
* **Implement:** Define `_wrapper_accepted_flags(<subcmd>)`. Locates the wrapper script path (`$BATS_TEST_DIRNAME/../../.ccanvil/scripts/linear-query.sh`), runs `awk '/^cmd_<subcmd_underscored>\(\) \{/,/^}/' linear-query.sh | grep -oE '\-\-[a-z][a-z0-9-]*\)' | tr -d ')' | sort -u`. Subcommand-to-function mapping converts `-` to `_` (e.g., `list-issues` → `cmd_list_issues`).
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 2'` → 2/2 green. **Sanity check the wrapper-script-path resolution** lands at the real file via `[ -f "$path" ]`.

### Step 3: Target-wrapper-subcommand derivation (AC-5)

* **Test:** Three bats tests. Given a resolver envelope whose command starts with `bash .ccanvil/scripts/linear-query.sh list-issues …`, `_target_wrapper_subcmd` returns `list-issues`. Same for `save-issue`, `get-document`, `save-document`. Negative: envelope command starting with anything other than `bash .ccanvil/scripts/linear-query.sh` returns empty (not a wrapper invocation).
* **Implement:** Define `_target_wrapper_subcmd()`. Reads command, splits on whitespace, finds the token after `linear-query.sh`, returns it. Empty on non-match.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 3'` → 3/3 green.

### Step 4: Contract-check helper, clean state on a single verb (AC-3 seed)

* **Test:** Given `_with_linear_routing_and_project_id` config and verb `backlog.list`, `_check_flag_contract backlog.list` returns empty stdout (no drift) and exit 0.
* **Implement:** Define `_check_flag_contract(<verb> [<op_args>...])`. Internally: (a) `bash $OPS resolve <verb> <args>` → envelope; (b) `target=$(_target_wrapper_subcmd <<<envelope)`; (c) `emitted=$(_emitted_flags <<<envelope)`; (d) `accepted=$(_wrapper_accepted_flags $target)`; (e) `comm -23 <(emitted) <(accepted)` → drift flags; (f) for each drift flag, emit `DRIFT: <verb> emits <flag> not accepted by linear-query.sh <target>`. Exit non-zero iff any DRIFT line printed.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 4'` → 1/1 green.

### Step 5: Per-verb positive sweep, idea-class (AC-3 main)

* **Test:** Six `@test` blocks — one per `backlog.list`, `idea.add`, `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`. Each runs `_check_flag_contract <verb>` under `_with_linear_routing_and_project_id` and asserts exit 0 + empty stdout.
* **Implement:** Tests only — no new helpers.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 5'` → 6/6 green.

### Step 6: Per-verb positive sweep, transition + reads/writes (AC-3 main, continued)

* **Test:** Eight `@test` blocks — `ticket.transition BTS-418 todo`, `ticket.get BTS-418`, `spec.read BTS-418`, `spec.write BTS-418`, `plan.read BTS-418`, `plan.write BTS-418`, `stasis.read feature BTS-418`, `stasis.write feature BTS-418`. Each asserts exit 0 + empty drift. (Session-kind stasis uses project_id, also covered.)
* **Implement:** Tests only.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 6'` → 8/8 green. **This is where BTS-407-shape drift would have been caught: any verb whose resolver emits a flag the wrapper doesn't accept will exit non-zero here.**

### Step 7: Drift-detection negative test (AC-4 + AC-7)

* **Test:** Synthetically construct a mutated envelope JSON in the test (NOT a live resolver call) where the command contains an injected `--bogus-flag-xyz`. Pipe to `_check_flag_contract` via a stubbed entry — actually, since the helper resolves internally, write a sibling `_check_flag_contract_envelope <verb> <stubbed-envelope-json>` that accepts a pre-built envelope. The test passes the mutated envelope, asserts exit non-zero AND stdout matches the literal pattern `DRIFT: backlog.list emits --bogus-flag-xyz not accepted by linear-query.sh list-issues`.
* **Implement:** Add `_check_flag_contract_envelope(<verb> <envelope>)` as a sibling that bypasses the resolver call. The original `_check_flag_contract` becomes a thin wrapper that resolves then delegates.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 7'` → 2/2 green (one exit-code test, one stdout-format test).

### Step 8: Empty-config negative path (AC-6)

* **Test:** With `_with_neither_project` config (no project_id, no project, only team + idea_label), `_check_flag_contract idea.list` exits 0 with empty drift — i.e., emitted flags are a strict subset (missing `--project-id`) but the wrapper still accepts every emitted one.
* **Implement:** Test only.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats --filter 'BTS-418 Step 8'` → 1/1 green.

### Step 9: Full-suite regression + manifest validate

* **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel --progress` end-to-end; capture pass count. Run `bash .ccanvil/scripts/module-manifest.sh validate --json` and assert `coverage.covered == coverage.total` and `drift == []`. No new manifest entries needed (inline bats helpers do not declare module-manifest blocks).
* **Implement:** No code changes — verification step.
* **Files:** none.
* **Verify:** Full suite exit 0; manifest 194/194 drift 0 unchanged.

## Risks

* **R1 (low):** `awk '/^cmd_<subcmd>\(\) \{/,/^}/'` range-match relies on `cmd_<name>` functions terminating at column-0 `}`. Audited via `grep -nE "^}" .ccanvil/scripts/linear-query.sh` — confirmed convention. If a future helper function inside a `cmd_` body opens a nested block that closes at column 0, the awk range would truncate. Mitigation: a test in Step 2 asserts the parsed accepted-flag set against the known-good `cmd_list_issues` flag list; any regression in the parser surfaces immediately.
* **R2 (low):** Subcommand-to-function name translation (kebab → snake) is a one-line `tr -- '-' '_'`. Trivial, but easy to invert. Mitigation: Step 2's tests cover both `list-issues` (hyphenated → `cmd_list_issues`) and a single-word subcommand (e.g., `viewer` → `cmd_viewer`).
* **R3 (medium):** Resolver `ticket.transition` REQUIRES `OP_ARG2`. The fixture's `_check_flag_contract` must pass positional args through. Mitigation: helper takes `<verb>` + optional `<args...>` and forwards via `bash $OPS resolve <verb> "$@"`. Tested explicitly in Step 6.
* **R4 (low):** Document-kind verbs (`spec.read`/`stasis.write` etc.) pull `doc_id` from a sub-shell call to `linear-query.sh resolve-document-id`. That sub-call requires the wrapper script to exist at the path the test expects — already true on the test host; covered by Step 6 verification.
* **R5 (very low):** `comm -23 <(emitted) <(accepted)` needs sorted input. Both helpers already `sort -u`. Test the helpers separately so any regression surfaces before the matrix sweep.

## Live-API Validation Gate (BTS-171)

**Not required.** This spec is a pure static-analysis fixture — no live API calls anywhere in the test path. The resolver invocations are deterministic shell expansions; the contract-check is static parsing. The flow runs entirely offline. (BTS-419 lived-API-tested on `idea.count` after merge; that gate doesn't apply here because the work surface introduces zero new API contracts.)

## Definition of Done

- [ ] All 7 acceptance criteria pass
- [ ] All existing tests still pass (full suite via `bash .ccanvil/scripts/bats-report.sh --parallel --progress`)
- [ ] Manifest 194/194 drift 0 (unchanged)
- [ ] No type errors (bats is shell — N/A; bash strict-mode in test bodies)
- [ ] Code reviewed (`/review`)
- [ ] PR title fix + body summary
- [ ] Linear BTS-418 auto-closed via `/ship`

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
