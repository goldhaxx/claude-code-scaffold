# Stasis

> Feature: session-2026-04-27-bts-217-and-substrate-hardening-release
> Kind: session
> Last updated: 1777306385
> Session: 5
> Boundary: 2026-04-27T09:13:05-07:00
> Session objective: ship BTS-217 (SSOT-Linear routing flip) end-to-end as a substrate dogfood; let the dogfood surface what it surfaces; package the resulting cluster of substrate-fix tickets into a release if one emerges.

## Accomplished

* **Investigated the prior-session "Background work running" panel.** Confirmed it was a `/schedule`'d in-session `CronCreate` for the BTS-163 drainage check (NOT the drift-watchdog, which runs on macOS launchd). The drift-watchdog at `~/Library/LaunchAgents/com.ccanvil.drift-watchdog.plist` fires Mondays 9:13 — verified state via `launchctl print`.
* **Documented the launchd setup persistently.** 2 new memories (`reference_drift_watchdog_launchd`, `project_bts_163_drainage_check`) + new repo doc `hub/meta/operations.md` (commit `9080d84`, pushed) including the canonical plist source so the watchdog can be recreated on a new machine without rediscovery.
* **Resurrected the BTS-163 drainage check as a remote routine** `trig_01VAjaAbt8S9r4v5RkLYo1cT` — durable across session exits this time, fires 2026-05-11 09:00 PT.
* **Captured BTS-218** (radar-gather `--project-dir` bug) and **updated** `docs/roadmap.md` to reflect the BTS-204 SSOT-Linear arc shipped end-to-end; reflowed Up Next; expanded determinism cluster to 6 P3s.
* **Shipped BTS-217 (PR #116, squash commit** `4f13e01`) — `routing.{spec,plan,stasis}=linear` flipped on hub. Inline-fixed a substrate bug surfaced during the dogfood: `_normalize_feature_to_ticket` helper in `docs-check.sh`, called at 4 sites (`cmd_artifact_{read,write}`, `_artifact_present_linear`, `_complete_archive_linear`) because all of them did Linear lookups using kebab `feature_id` when canonical `BTS-N` is required. Added 5 new bats tests (1707 → 1712 passing). Bash-3.2 portable.
* **Manually archived the orphaned BTS-217 spec Document** (`ba9a9764-…`) — pr-cleanup ran with the buggy code BEFORE my substrate fix landed. Replayed the archive flow manually post-fix to verify the substrate now works end-to-end and to clean up the orphan. Posted project_id correction comment on BTS-217 ticket body.
* **/idea triage processed 11 items.** 7 drift-watchdog dups merged (BTS-220–226 → BTS-191–197) with content-migration comments preserving the updated drift hashes + commit counts on the originals. 4 substrate-fix items promoted to Backlog: BTS-227 (P3, drift-watchdog `$()` jq capture bug), BTS-219 (P3, `cmd_artifact_read` silent-exit-2), BTS-218 (P3, radar-gather `--project-dir`), BTS-215 (P4, docs-check usage string).
* **Surfaced BTS-228** during the triage merge dispatch itself: `linear-query.sh save-issue --duplicate-of <uuid>` fails because Linear's `IssueUpdateInput` doesn't have `duplicateOf` — duplicate-of is a separate `IssueRelation` mutation. Workaround used: state-only transition + cross-reference comments. Captured + promoted to Backlog P3.
* **Packaged the 9 substrate-fix tickets into BTS-229 ("Release: substrate-hardening-v1")** — In Progress, Priority High, 9 children reparented (BTS-202, BTS-203, BTS-205, BTS-210, BTS-212, BTS-218, BTS-219, BTS-227, BTS-228). Body documents theme, members, ship criteria, cadence (2 ships of 4-5 over 1-2 sessions; co-shipping where touch-points overlap). **Dogfoods BTS-163's lightweight Linear-backend design without building the resolver-verbs / state-machine substrate.** Cross-reference comment posted on BTS-163 explaining the substrate-driven pivot and ramp-or-scope-down logic for the 5/11 drainage agent.

## Current State

* **Branch:** `main`, fast-forwarded to origin/main, working tree clean.
* **Tests:** **1712 / 1712 passing** (1707 baseline + 5 new BTS-217 normalize-helper tests).
* **Uncommitted changes:** none.
* **Build status:** clean.

## Blocked On

Nothing.

## Next Steps

1. **Substrate-hardening-v1 Ship 1**: BTS-218 + BTS-212 co-ship (both touch `docs-check.sh` flag parsing — same parser, both small). One PR, \~1hr.
2. **Substrate-hardening-v1 Ship 2**: BTS-219 + BTS-227 (live-API diagnostic surfacing — both add WARN-on-failure to substrate that currently silently exits 2 OR silently double-queues to pending log). One PR, \~1.5hr.
3. **Substrate-hardening-v1 Ship 3**: BTS-228 (separate state transition from `IssueRelationCreate`; document two-step shape in `/idea triage` skill prose). Standalone ship, \~1hr.
4. **Other release members** ship as touch-points permit: BTS-202 (guard-destructive false-positive), BTS-203 (evidence-scan description-fetch), BTS-205 (silent dual-capture failure), BTS-210 (guard-workspace prose false-positive — triggered 4× this session, real friction).
5. **5/11 drainage agent fires** — its recommendation should now reflect BTS-229's state. If substrate-hardening-v1 has shipped cleanly, BTS-163 collapses to "document the lightweight pattern + add a `release` label." If friction surfaced, BTS-163 ramps with concrete motivation. Update routine prompt before then if scope shifts.

## Context Notes

* **The dogfood-finds-substrate-bugs pattern compounded massively.** BTS-217 alone surfaced 5 substrate-fix tickets (BTS-218, BTS-219, BTS-227, BTS-228, plus reinforced BTS-210). Add the drift-watchdog Monday firing and the in-session `/idea triage`, and the count is **9 substrate-bug captures in one session** — enough that a release primitive emerged organically from the cluster shape.
* **Substrate-driven pivot on BTS-163.** Instead of building the full release primitive substrate (resolver verbs `release.list/propose/accept/dismiss/close/migrate`, state machine `proposed→active→shipped`, local backend `.ccanvil/releases.log`), shipped the LIGHTWEIGHT half (Linear native parent/child + workflow states) to validate sufficiency. If BTS-229 ships cleanly, BTS-163 scope-downs to docs + label. If friction, BTS-163 ramps with motivation.
* **Linear API contract:** `duplicateOf` is NOT a field on `IssueUpdateInput`. Substrate's `--duplicate-of` flag silently fails the relation half. Linear's relation API (`issueRelationCreate` mutation, `type=duplicate`) is the correct path. Captured as BTS-228.
* `_normalize_feature_to_ticket` sits at the substrate boundary now. All Linear-API-bound feature_id values normalize through it. The /spec convention requires `<lower-slug>-<kebab-name>`; the helper extracts the leading slug + uppercases for Linear API consumption. Without this normalization, every new caller had the same bug.
* `guard-workspace.sh` fires repeatedly on narrative prose. Triggered 4× this session: `/spec,`, `/complete`, `/bin/bash`, `/opt/homebrew/bin/bash` in commit messages, idea bodies, PR bodies. Each requires `ALLOW_OUTSIDE_WORKSPACE=1` bypass. Already tracked (BTS-210); severity bumped via the repeated trigger.
* **The lightweight release pattern IS BTS-163's Linear-backend design exactly.** Resolver verbs + local backend would be additive substrate; state machine codifies lifecycle. None of that is needed yet — Linear's native semantics cover it.
* **Git flow snag at activate time:** `docs-check.sh activate` blocked because main was ahead of origin (the roadmap commit hadn't been pushed). The substrate auto-pushed and continued — appropriate behavior for a one-line guard, but worth noting that working-on-main + activating-immediately needs the auto-push fallback to stay smooth.

## Determinism Review

* **operations_reviewed:** \~60 (BTS-217 spec/plan/activate/implement/pr/land + substrate fix application + manual archive + /idea triage of 11 items + BTS-229 creation + 9 reparentings + comment posting on 9 issues + drift-watchdog dup analysis + project_id correction comment)
* **candidates_found:** 0
* No candidates this session. The substrate-fix work itself was the deterministic improvement (`_normalize_feature_to_ticket` helper + the 5 tests). The /idea triage merge dispatch failure landed as a Linear API contract issue (captured as BTS-228), not a substrate-architecture decision. All other operations rode existing deterministic paths.

## Evidence Gaps

No evidence gaps this session.

## Cross-Session Patterns

* **CONFIRMED RECURRING (7+ sessions, now load-bearing): dogfood surfaces substrate bugs that bats stubs miss.** This session is the strongest single-session evidence yet: BTS-217 alone surfaced 5 substrate-fix tickets; the full session yielded 9 across BTS-217, drift-watchdog Monday firing, and `/idea triage`. Bats stubs (1707/1707 then 1712/1712 green throughout) didn't catch any of them. Pattern is now load-bearing — the substrate-hardening release literally exists because of it.
* **NEW: substrate-driven pivot at the architectural-question point.** BTS-163 was a major-architecture question (build a release primitive?). When the cluster of substrate-fix tickets emerged, the natural next-step was to dogfood the LIGHTWEIGHT half of BTS-163's design (Linear native parent/child) rather than commit to the full substrate. This generalizes `feedback_substrate_driven_pivot`: when an emergent cluster reveals demand, ship the lightweight pattern first, let the friction (or lack thereof) decide whether to ramp the full substrate.
* **CONFIRMED RECURRING (3+ sessions): orphaned Linear Documents from buggy archive paths.** BTS-217 dogfood found that pr-cleanup couldn't archive when feature_id was kebab-shaped. Substrate fix landed; manual cleanup of the orphan succeeded. BTS-204's stasis-falsely-claimed-validation pattern continues to remind us: archive paths only work end-to-end when ALL inputs match the substrate's expected shape.
* **CONFIRMED RECURRING (this session, repeated trigger):** `guard-workspace.sh` false-positive on narrative slash-command tokens. Triggered 4× on prose containing `/spec`, `/complete`, `/bin/bash`. Tracked as BTS-210; this session promotes it from "annoyance" to "real friction" — a member of the substrate-hardening release.
* **NEW: scheduling surface confusion.** Operator (and me earlier) confused the launchd drift-watchdog with the in-session `CronCreate` schedule. The 3-surface comparison table now lives in `hub/meta/operations.md`. Pattern: when scheduling agents, EVERY mention should specify which surface — `launchd plist`, `/schedule remote routine`, or `in-session CronCreate`.
* **No legacy-refs or audit-session findings.** Substrate is clean.

## Security Review

* BTS-217 substrate work: bash + GraphQL via existing http machinery (BTS-164). No new auth surfaces.
* BTS-229 release packaging: comment-posting + state transitions via Linear MCP. No secrets in commits.
* The PR #116 body contains the full BTS-217 spec inlined (activate-time embed). The spec openly discusses the project_id discrepancy. No secrets exposed.
* Linear API key sourced via `set -a; source .env; set +a` only for live commands. `.env` stays gitignored.
* Manual archive of orphaned Document `ba9a9764-…` succeeded with `trash-document` returning `{"success": true}`. No leaked content.
* **Verdict: PASS.**

## Memory Candidates

* **NEW MEMORY:** `feedback_lightweight_pattern_dogfoods_substrate_design` — When considering whether to BUILD a substrate primitive vs. use existing platform features, check whether the platform already provides what the design describes. BTS-163 was going to be a "release primitive" with its own resolver verbs + state machine + local backend — but Linear's native parent/child + workflow states cover the Linear half entirely. Ship the lightweight pattern first; let real friction (or its absence) decide whether to commit to building substrate. Pairs with `feedback_substrate_driven_pivot`.
* **NEW MEMORY:** `feedback_normalize_at_substrate_boundary` — When a substrate function does provider-API lookups using a caller-supplied identifier, that identifier may arrive in MULTIPLE shapes from MULTIPLE callers. Normalize at the substrate boundary, not at every callsite. BTS-217 bug: 4 call sites all passed kebab feature_id when Linear API needed canonical BTS-N. Fix: one helper at the boundary, four updated callers. Without it, every new caller would inherit the same bug.
* **NEW MEMORY:** `reference_three_scheduling_surfaces` — Three distinct mechanisms for scheduling Claude Code work, easy to confuse: (a) macOS launchd LaunchAgent — durable across sessions/reboot, used for the drift-watchdog; (b) `/schedule` remote routine — durable in Anthropic cloud across sessions, used for one-shot follow-ups (e.g. BTS-163 drainage); (c) in-session CronCreate — dies on session exit, only useful within a single live session. The "Background work running" panel on Claude Code exit ALWAYS shows category (c) — never the launchd watchdog or remote routines. Now documented in `hub/meta/operations.md`.
* **REINFORCE:** `feedback_dogfood_probe_as_thesis_test` — Now load-bearing. BTS-217 alone surfaced 5 substrate-fix tickets; the full session yielded 9. The pattern compounds at every substrate maturity tier.
* **NEW REFERENCE: BTS-229** — substrate-hardening-v1 release ticket, parent of 9 P3 substrate-fix tickets. Dogfoods BTS-163's lightweight pattern. State In Progress, Priority High. This is the first ccanvil "release" — its trajectory determines whether BTS-163 ramps or scope-downs.
