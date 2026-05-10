# Feature: substrate-staleness drift-guard

> Feature: bts-419-substrate-staleness-drift-guard
> Work: linear:BTS-419
> Created: 1778444817
> Subject: substrate-staleness drift-guard
> Status: Complete

## Summary

When a Linear-routed node has `integrations.providers.linear.project_id` configured, `operations.sh resolve` for any project-scoped verb (backlog.list, idea.add, idea.list, idea.count, idea.triage, idea.review-icebox) MUST emit `--project-id` in the resolved command. Today the hub honors this contract (BTS-407, PR #176), but stale downstream nodes silently violate it — their pre-BTS-407 resolver dereferences `.project // ""` only, emits `--project ''`, and Linear falls back to team-only matching, returning workspace-wide results across all projects. Session 41 anchor: tour-scheduler `/recall` reported 23 untriaged ideas (workspace count) when the project's actual is 1-2. Twelve downstream nodes silently leaked cross-project data for ~14 hours before an operator-observed symptom triggered the fleet remediation.

This spec hardens the resolver-correctness surface in two complementary places: (1) a hub-side bats drift-guard that prevents future regressions of the BTS-407 contract from ever merging, and (2) a runtime self-consistency check in `operations.sh resolve` that hard-fails when `project_id` is configured but the emitted command lacks `--project-id` — making stale-substrate symptoms LOUD instead of silent-wrong on every downstream node that ships this fix.

## Job To Be Done

**When** a Linear-routed node runs any project-scoped `operations.sh resolve` verb against a config carrying `project_id`,
**I want to** be told immediately and unambiguously when the resolved command will leak cross-project data,
**So that** stale-substrate failure modes surface as a single clear ERROR (with remediation recipe) at the resolver boundary, not as silently-wrong query results visible only as semantic anomalies hours later in `/recall` / `/idea` / `/radar` output.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1** — Hub-side regression guard (drift-guard fixture): Given a Linear-routed config with `integrations.providers.linear.project_id` set and `project` (name) empty, when the resolver is invoked for EACH of the six project-scoped verbs (backlog.list, idea.add, idea.list, idea.count, idea.triage, idea.review-icebox), the resolved `.invocation.command` MUST contain the substring `--project-id `. Failing this on any verb is an `exit 2` from the new drift-guard bats fixture.
- [ ] **AC-2** — Hub-side regression guard (negative test): Given a Linear-routed config with neither `project_id` nor `project` set, the resolved command MUST NOT contain either `--project-id ''` or `--project ''` — empty-value flag emission is forbidden. (Mirrors and extends BTS-407 AC-5; verifies the no-flag-when-empty contract.)
- [ ] **AC-3** — Runtime self-consistency check: Given a Linear-routed config with `project_id` set, when `operations.sh resolve` is invoked for any project-scoped verb AND the about-to-be-emitted command does not contain `--project-id`, the resolver MUST exit non-zero with stderr matching the literal substring `stale substrate` AND including the remediation recipe `bash .ccanvil/scripts/ccanvil-sync.sh pull`. Verified by bats fixture that synthetically mutates the resolver's emit path (or stubs the conditional emission) to produce the bug shape and asserts the guard fires.
- [ ] **AC-4** — Runtime self-consistency: no false-positives when `project_id` is unset. Given a Linear-routed config with NEITHER `project_id` NOR `project` set, the runtime self-consistency check MUST NOT fire (no error, exit 0, command resolves without `--project-id`). Legacy / not-yet-migrated nodes must keep working.
- [ ] **AC-5** — Runtime self-consistency: no fire on non-project-scoped verbs. Given a Linear-routed config with `project_id` set, when the resolver is invoked for a verb that is intentionally NOT project-scoped (e.g., `ticket.transition`, `work.resolve`), the self-consistency check MUST NOT fire — the assertion is verb-aware, not blanket.
- [ ] **AC-6** — Manifest declares the new contract. The `linear_mcp_adapter` function manifest (in `.ccanvil/scripts/operations.sh`) declares the new `failure-mode` entry for the staleness-guard exit path (per Layer 2 manifest discipline — BTS-239). Drift-guard validate stays clean (`coverage.covered == total`).
- [ ] **AC-7** — Operator-facing surface. The stderr error message produced by AC-3 includes: (a) the configured `project_id` value, (b) the verb that was being resolved, (c) the remediation recipe with absolute or `cd`-prefixed path so the operator can copy-paste. No raw shell-debug stack-traces; the message is operator-grade.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — add runtime self-consistency check in `linear_mcp_adapter` post-emit (AC-3, AC-4, AC-5); update `# @manifest` block for new exit path (AC-6) |
| `hub/tests/operations-drift-guard.bats` | New — verb × config matrix asserting AC-1, AC-2, AC-3, AC-4, AC-5 |
| `hub/tests/operations-resolve-http.bats` | Possibly modified — share fixture setup; verify existing BTS-407 ACs still green |
| `.ccanvil/manifest-allowlist.txt` | Possibly modified — confirm `linear_mcp_adapter` already covered; add new exit-path symbol if discovered |

## Dependencies

- **Requires:** BTS-407 (PR #176) shipped — establishes the `--project-id` emission contract this spec defends. Already merged.
- **Requires:** BTS-239 manifest substrate — for AC-6 manifest declaration discipline.
- **Composes-with:** BTS-418 (resolver-wrapper-flag-contract drift-guard). Both live in the same `operations-drift-guard.bats` fixture file (or are split into sibling fixtures sharing common setup). Resolved order: BTS-419 may ship before, after, or with BTS-418 — no hard blocking. The two guards harden adjacent contracts (resolver→wrapper flag set vs resolver-self-consistency on project-scoping).
- **Blocked by:** Nothing.

## Out of Scope

- **Pull-cadence enforcement.** This spec does not introduce automatic-pull, scheduled-pull, or hub-side push. Operator-driven pull cadence remains the model; the drift-guard makes staleness LOUD when it next runs, not pre-emptively-fixed.
- **Substrate-version lockfile expansion.** Adding a `min_substrate_version` field to `.ccanvil/ccanvil.lock` and gating ALL resolver calls on hub-version-match is a strictly larger intervention; deferred to a separate ticket if pull-cadence drift recurs across other substrate classes.
- **Retroactive cleanup.** The session-41 fleet remediation already happened. This spec defends against the NEXT staleness window, not the previous one.
- **Cross-project query DELETION on legacy nodes.** If a node deliberately runs against the older shape, the runtime check should refuse — but this spec does not migrate stale node configs.
- **Other resolver classes.** GitHub, local, and other future providers are out of scope; the guard fires only on the Linear adapter's project-scoped surface.

## Implementation Notes

**Three architectural shapes for the runtime guard (AC-3) — pick ONE in `/plan`:**

1. **Inline post-emit check inside `linear_mcp_adapter` (per-verb).** After each verb's `jq -n` invocation produces the command string, run a shell-level check: if `project_id` is non-empty AND the emitted command lacks `--project-id`, emit ERROR + exit. Pros: simple, localized, no new helper function. Cons: six call-sites to update; risk of forgetting one when adding verbs in future.

2. **Centralized post-emit wrapper.** Refactor the six `jq -n` invocations to flow through a small helper (e.g., `emit_with_staleness_guard <verb> <config> <command>`) that performs the self-check and stdouts the command (or exits with ERROR). Pros: one place to enforce the contract for all current AND future project-scoped verbs. Cons: small refactor surface; needs to know which verbs are project-scoped.

3. **Resolver-output filter at `resolve` dispatch.** Add the check as a post-pass in the `resolve` command's outer layer (not inside `linear_mcp_adapter`), inspecting the JSON output after the adapter returns. Pros: provider-agnostic (could extend to GitHub/etc. later); fully decoupled from adapter internals. Cons: needs to know the contract surface (which verb × which config requires which flag) at a higher layer; risks duplicating adapter knowledge.

**Pattern to follow for AC-1 / AC-2:** mirror existing BTS-407 ACs in `hub/tests/operations-resolve-http.bats` (lines 229–387) — same fixture setup pattern, same `run bash .ccanvil/scripts/operations.sh resolve <verb> --project-dir .` shape, same `[[ "$output" =~ "--project-id" ]]` assertion form. New fixture is the loop-over-verbs variant of those.

**Pattern to follow for AC-3 fixture:** mirror `hub/tests/module-manifest-drift-guard.bats` mutation-tests pattern (lines 23–38) — synthetically corrupt the input (or stub the emit), assert exit 2 + stderr substring, revert, re-assert clean.

**Manifest update (AC-6):** the `linear_mcp_adapter` function in `operations.sh` carries a `# @manifest` block. New `failure-mode: stale-substrate-emit | exit=N | visible=stderr-ERROR-staleness-guard | mitigation=run-ccanvil-sync.sh-pull` entry needed.

**Operator-facing message shape (AC-7):**
```
ERROR: stale substrate — project_id=<UUID> is configured but resolve(<verb>) did not emit --project-id.
This typically means .ccanvil/scripts/operations.sh is out-of-date relative to the hub.
Run: cd <project-dir> && bash .ccanvil/scripts/ccanvil-sync.sh pull
```

## Open Questions

- **Which of the three architectural shapes (Implementation Notes #1/#2/#3)?** Decide in `/plan`. Recommendation hint: option 2 (centralized wrapper) — minimizes future-drift risk, small refactor, single-source-of-truth for the "project-scoped verb" set.
- **Does AC-3 hard-fail (exit non-zero) or warn-then-continue?** Hard-fail is the LOUDER signal the operator's session 41 quote asks for. Warn-then-continue avoids breaking downstream nodes mid-session if their config is intentionally legacy. Recommendation hint: hard-fail with `ALLOW_STALE_SUBSTRATE=1` env override for emergency escape — fail-LOUD with operator-controlled bypass.
- **Pair-ship with BTS-418 (resolver-wrapper-flag-contract drift-guard) or independent?** Both fixtures are tiny; pairing them into one PR creates a coherent "resolver-correctness substrate" ship. Independent allows faster turnaround on whichever is ready first. Recommendation hint: independent specs but ship adjacent; let `/plan` size decide.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
