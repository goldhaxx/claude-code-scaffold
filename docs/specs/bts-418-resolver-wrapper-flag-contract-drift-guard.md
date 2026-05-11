# Feature: resolver-wrapper-flag-contract drift-guard

> Feature: bts-418-resolver-wrapper-flag-contract-drift-guard
> Work: linear:BTS-418
> Created: 1778472647
> Subject: resolver-wrapper-flag-contract drift-guard
> Status: In Progress

## Summary

When a resolver in `linear_mcp_adapter` (`.ccanvil/scripts/operations.sh`) emits an http-mechanism command, that command invokes a `linear-query.sh` subcommand with one or more `--<flag> <value>` pairs. Every emitted flag MUST have a matching `--<flag>)` arm in the wrapper subcommand's `case "$1" in` parser — otherwise the wrapper fires `_die 2 "unknown flag: --<flag>"` and the verb fails post-merge, in production, on whatever node pulled the diverged substrate next. Today the contract is enforced by code review, the BTS-419 staleness-guard (different contract), and live-call failure. None of those run at merge time on the hub.

Session 42 anchor: BTS-407 (PR #176) added `--project-id` emission to 5/6 idea verbs in the resolver but never updated `cmd_list_issues` in the wrapper to accept it. The wrapper `_die`d on `--project-id` for every Linear-routed idea verb the moment downstream nodes pulled the change. PR #177 (hot-fix the same session) was the operator-observed remediation. A deterministic merge-time fixture would have blocked PR #176 before it shipped — and would block every future BTS-407-shape regression for both directions of the resolver↔wrapper contract.

This spec closes the OTHER half of the resolver-correctness surface BTS-419 hardens: BTS-419 enforces resolver self-consistency (config → emitted flags), this spec enforces resolver-to-wrapper flag-set acceptance (emitted flags → wrapper-accepted flags). Together they structurally close the BTS-407-shape regression class.

## Job To Be Done

**When** a hub-side change in either `operations.sh` (resolver) or `linear-query.sh` (wrapper) modifies the flag-set on either side of the resolver-wrapper boundary,
**I want to** be told at `bats` time — before merge — that the two sides have drifted and which flag is unaccepted by which subcommand,
**So that** post-merge wrapper-`_die` failures (the exact shape that broke 5/6 idea verbs immediately after PR #176) cannot leave the hub again.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1** — Flag-extraction (resolver side): Given an http-mechanism resolver-output JSON envelope, a deterministic shell helper extracts the ordered list of long-flag names (`--<flag>`) from `.invocation.command`. Tokens that start with `--` and are followed by whitespace count; `--flag=value` form is NOT supported (and the resolver does not emit it — see Out of Scope). Verified against synthetic envelopes covering 0, 1, and N flag emissions.
- [ ] **AC-2** — Flag-extraction (wrapper side): Given a `linear-query.sh` subcommand name (e.g., `list-issues`), a deterministic shell helper extracts the set of accepted long-flag names from that subcommand's `case "$1" in ... esac` argv parser. Verified against `cmd_list_issues` (which accepts `--project`, `--project-id`, `--team`, `--state`, `--label`, `--limit`).
- [ ] **AC-3** — Contract-check, clean state: For EACH http-mechanism resolver verb in `linear_mcp_adapter` (the canonical set: `backlog.list`, `idea.add`, `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`, `ticket.transition BTS-418 todo`, `ticket.get BTS-418`, `spec.read BTS-418`, `spec.write BTS-418`, `plan.read BTS-418`, `plan.write BTS-418`, `stasis.read BTS-418`, `stasis.write BTS-418` — positional args supplied per the resolver's contract), the fixture (a) resolves the verb against the Maximal-Config Fixture defined in Implementation Notes, (b) extracts the emitted flag set via AC-1, (c) extracts the target wrapper subcommand's accepted flag set via AC-2, (d) asserts every emitted flag is in the accepted set. Zero drift on the unmodified hub = bats exit 0.
- [ ] **AC-4** — Contract-check, drift detection: **Given:** a synthetically mutated resolver output that emits a flag NOT accepted by the target wrapper subcommand (e.g., `--bogus` injected into the `backlog.list` emission). **When:** the fixture runs the contract-check against that mutated output. **Then:** the fixture MUST exit non-zero AND stderr MUST name (a) the resolver verb, (b) the target wrapper subcommand, and (c) the offending flag literal. Verified by stubbing the resolver output via a fixture-local override.
- [ ] **AC-5** — Verb-to-wrapper-subcommand mapping is derived, not hardcoded. The fixture extracts the wrapper subcommand from the FIRST positional after `bash .ccanvil/scripts/linear-query.sh` in the resolved command (i.e., the wrapper's dispatch verb). Adding a new resolver verb that targets an existing wrapper subcommand requires zero fixture changes; adding a wrapper subcommand requires only its dispatch entry to be reachable from a resolver.
- [ ] **AC-6** — Empty-config negative path: Given a resolver verb invoked with a minimal config (only required fields, e.g., `team` only, no `project_id` / `project` / `label`), the conditional `--<flag>` emissions correctly omit those flags AND the contract-check still passes — i.e., the helper doesn't false-positive on "emitted flags ⊆ accepted flags" when the emitted set is a strict subset.
- [ ] **AC-7** — Operator-facing failure surface: When AC-4 fires, the bats failure output is grep-able and copy-paste-ready: one line per drifting flag in the form `DRIFT: <verb> emits --<flag> not accepted by linear-query.sh <subcommand>`. No raw shell debug, no jq backtrace.

## Affected Files

| File | Change |
|------|--------|
| `hub/tests/operations-drift-guard.bats` | Modified — append the resolver↔wrapper flag-contract test block; share setup with the BTS-419 verb fixture (`_with_linear_routing_and_project_id`, `_with_project_id_only`, etc.) |
| `.ccanvil/scripts/operations.sh` | Probably unmodified — the helper extraction is bats-local. If `/plan` chooses a shared shell helper (Implementation Notes #2), that script is created |
| `.ccanvil/manifest-allowlist.txt` | Possibly modified — only if a new shared helper script is introduced (Implementation Notes #2/#3 paths) |

## Dependencies

- **Requires:** BTS-407 (PR #176) shipped — establishes the contract shape this spec defends. Merged.
- **Composes-with:** BTS-419 (substrate-staleness drift-guard). Shipped session 42 (PR #178). Both fixtures live in `hub/tests/operations-drift-guard.bats` and share fixture setup (`OPS=`, `setup()`/`teardown()`, `_with_linear_routing_and_project_id`, etc.). No hard ordering needed — BTS-418 lands on top of BTS-419's file.
- **Requires:** BTS-239 manifest substrate — only if a new shared helper is introduced (AC-5 path-2/3).
- **Blocked by:** Nothing.

## Out of Scope

- **`--flag=value` form.** The resolver exclusively emits space-separated `--flag value` pairs (all six idea verbs + transition + reads/writes audited). Supporting `=` form would add parser complexity for zero current callers. If a future resolver emits `=` form, that's a separate ticket.
- **Short-flag forms (`-f`, `-t`).** The resolver never emits short flags; the wrapper never accepts them. No coverage needed.
- **Reverse drift (wrapper accepts a flag no resolver emits).** That's "dead wrapper flag" — a docs/cleanup concern, not a regression-causing one. Out of scope; capture separately if it grows.
- **Flag VALUE shape validation.** The fixture checks flag NAMES only. UUID-shape on `--project-id`, integer-shape on `--limit`, etc. is the wrapper's runtime responsibility.
- **Non-http mechanism verbs (`idea.sync`, `work.resolve`, local-routed verbs).** These don't emit `linear-query.sh` invocations. The fixture filters by `.mechanism == "http"` and target-wrapper-name.
- **Linear MCP path / claude.ai connectors.** Wrapper-side validation only covers the `linear-query.sh` shell substrate.
- **GitHub / future-provider adapters.** Same pattern would compose; this ticket scopes to the Linear surface.

## Implementation Notes

**Three architectural shapes — pick ONE in `/plan`:**

1. **Inline bats helpers.** Two bash functions (e.g., `_emitted_flags()` parses resolver output, `_wrapper_accepted_flags()` parses the wrapper script's case block) defined inside the bats file. Fixture iterates verbs in a `@test` per verb or in a single loop-test. Pros: no new substrate, zero coupling, lightest-weight. Cons: helpers are not reusable from other test files.

2. **Shared helper script.** Extract `.ccanvil/scripts/flag-contract-check.sh` with subcommands `emitted-flags <json>` and `accepted-flags <wrapper-cmd>`. Bats fixture shells out per verb. Pros: reusable from `/review` or `/ccanvil-audit` if the operator ever wants ad-hoc audits. Cons: new substrate + manifest entry + drift-guard surface.

3. **Build-time pre-compute.** Generate `hub/tests/fixtures/flag-contract.json` at hub-CI time via a one-shot extractor; bats fixture diffs against the live state. Pros: zero parse cost per test. Cons: cache-invalidation concern, generator script becomes another moving piece.

**Recommendation hint:** Option 1 (inline bats). The surface is small (≤15 verbs × ≤6 wrapper subcommands), the parse helpers are <20 lines each, and the fixture is single-purpose. Promote to Option 2 ONLY if `/review` or `/ccanvil-audit` calls for the same check from outside bats.

**Pattern to follow for setup:** mirror `hub/tests/operations-drift-guard.bats` helpers (`_with_linear_routing_and_project_id`, `_with_project_id_only`, `_with_neither_project`) — already shipped session 42, sourced via `OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"`. Reuse the BASH_SOURCE-sourceability guard that BTS-419 established.

**Maximal-Config Fixture (definition for AC-3):** the contract-check uses ONE fixture — `_with_linear_routing_and_project_id` from the BTS-419 file — for ALL listed verbs. It populates `integrations.routing=linear`, `integrations.providers.linear.{project_id, project, team, idea_label, state_ids.{triage,backlog,icebox,canceled,duplicate,done,todo,in_progress}}`. The "maximal" claim holds because: (a) the six idea-class verbs (`backlog.list`, `idea.add`, `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`) emit ALL their conditional `--<flag>` arms when `project_id` + `team` + `idea_label` + the relevant `state_ids` entry are populated; (b) the transition class (`ticket.transition`, `ticket.get`) emits a fixed positional + `--id` + `--state` (no further conditional flags); (c) the document class (`spec.read`/`plan.read`/`stasis.read` → `get-document <doc-id>`; `spec.write`/`plan.write`/`stasis.write` → `save-document --id <doc-id> --title <t> --content -`) emits NO conditional flags at the resolver — all argument variation is positional or stdin-fed. Therefore one fixture × all verbs covers the contract surface. If a future verb is added with conditional `--<flag>` emissions that this fixture does NOT populate, extend the helper there — not here.

**Resolver-side parse heuristic.** From `jq -r '.invocation.command'`, extract flags via:
```bash
grep -oE -- '--[a-z][a-z0-9-]*' <<<"$cmd" | sort -u
```
The resolver emits no `--flag=value` form (verified across all http branches), so this regex is sound.

**Wrapper-side parse heuristic.** Within `linear-query.sh`, locate the target `cmd_<verb>()` function body (e.g., `cmd_list_issues`), then extract `case` arms via:
```bash
awk '/^cmd_'<wrapper-cmd>'\(\) \{/,/^}/' linear-query.sh \
  | grep -oE '\-\-[a-z][a-z0-9-]*\)' \
  | tr -d ')' | sort -u
```
Note: the awk range works because every wrapper subcommand body terminates at column-0 `}`.

## Open Questions

- **Architectural shape (#1/#2/#3 above)?** Decide in `/plan`. Recommendation: option 1, inline bats helpers.
- **Test granularity: one `@test` per verb, or one matrix test?** One-per-verb gives better failure isolation in bats output; one matrix test is terser. Recommendation: one-per-verb (mirrors BTS-419 Step 7 / Step 8 shape).
- **Hub-only or also-downstream?** The drift surface lives in hub scripts; downstream nodes pull the substrate as-is. Recommendation: hub-only fixture (mirrors BTS-419 — the runtime self-consistency check defends downstream nodes; this static contract-check defends the hub at merge time).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
