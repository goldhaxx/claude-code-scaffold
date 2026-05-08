# Stasis

> Feature: session-2026-05-07-bts-331-key-distribution-and-fleet-migration
> Kind: session
> Last updated: 1778203147
> Session: 28
> Boundary: 2026-05-07T18:19:07-07:00
> Session objective: Ship BTS-331 (LINEAR_API_KEY 4-tier auth chain) end-to-end, broadcast the new substrate to all 11 downstream nodes, then migrate stranded local-routed legacy ideas across 5 nodes into the Linear-routed system of record.

## Accomplished

**One full lifecycle ship:**

| Ship | PR | Notes |
|---|---|---|
| BTS-331 | #167 | LINEAR_API_KEY 4-tier auth chain extension (env → project .env → ~/.env → macOS Keychain). Service-name mapping rule: lowercased env-var. Live-API-validated end-to-end via the keychain tier. |

**Fleet broadcast.** After ship landed, ran `ccanvil-sync.sh broadcast` against all 11 registered nodes. First pass: 8 synced, 3 blocked by either uncommitted CLAUDE.md updates (3 nodes — committed via chore-branch + ff-merge pattern) or operator WIP (3 nodes — left untouched per agency-first principle, then operator cleaned and re-broadcast hit 11/11).

**Pre-existing fleet substrate finally functional.** BTS-321 (provider-heal-auth) verified auth at heal time but never distributed the key; BTS-331 closed that gap. Verified post-broadcast: `cd ~/projects/web-browser-toolbox && env -i HOME=… USER=… PATH=… bash .ccanvil/scripts/linear-query.sh viewer` resolves via the keychain tier from a downstream node's relative path with every other env var stripped.

**Legacy data migration across 5 nodes (40 ports).** Audit found 49 stranded local ideas across 5 of 11 nodes (taxes 12, fieldnation-toolbox 25, caffeine-calculator 1, inbox-toolbox 8, microsoft365-toolbox 3) plus 5 pending-log entries — all invisible to Linear-routed `/idea` workflow post-activation. Per-node interactive triage:

| Node | Active before | Ported | Marked-as-already-in-Linear | Active after |
|---|---|---|---|---|
| microsoft365-toolbox | 3 | 3 (BTS-338/339/340) | 0 | **0** |
| inbox-toolbox | 6 | 2 (BTS-341 consolidated, BTS-342 child of BTS-311) | 4 (3 already as BTS-273; consolidated under BTS-341) | **0** |
| taxes | 8 | 8 (BTS-343–349 → Backlog/P3, BTS-350 → Triage) | 0 | **0** |
| fieldnation-toolbox | 23 | 23 (BTS-351–373; #15 → Icebox per operator self-flag, #22 → Backlog/P1 per "HIGH PRIORITY" prefix, rest → Triage) | 0 | **0** |
| caffeine-calculator | 0 | 0 | 0 | **0** |

Every migrated local entry carries a `migrated_to: "BTS-XXX"` audit field for traceability.

**Pending-log drain.** 5 stranded `ideas-pending.log` entries (3 inbox-toolbox, 1 unifi-toolbox, 1 web-browser-toolbox) drained via `/idea sync` per node — zero failures. These were dispatch failures from pre-BTS-331 sessions where auth was broken; auth now works.

**6 new captures from review + audit work.** BTS-332 (credential-management research — naming conventions, framework comparison solo→org), BTS-333 (DIAGNOSE: tier-3 ~/.env parse-error coverage gap), BTS-334 (manifest accuracy: declare reads-file-HOME-env + invokes-subprocess-security side-effects), BTS-337 (provider-heal: add legacy-data-scan step before routing flip), BTS-374 (FIX: substrate snippets must declare bash explicitly — zsh array-indexing footgun). Plus the four session-25 captures (BTS-327/328/329/330) all promoted from Triage to Backlog this session.

**BTS-315 spec drafted but parked.** Init drift probe spec written to `docs/specs/bts-315-init-drift-probe.md`, dispatched to Linear, transitioned to Todo, then paused when BTS-331's auth-distribution gap surfaced as a hard prerequisite. Spec is ready; activate when next session begins.

## Current State

- **Branch:** main, clean working tree (one untracked file: `docs/specs/bts-315-init-drift-probe.md` — parked spec for next session).
- **Tests:** 2035 / 2035 passing.
- **Build status:** clean.
- **Manifest coverage:** 193 / 193, drift 0.
- **Idea queue:** Triage 5 (BTS-332/333/334/337/374) / Backlog 19 / Icebox 2.

## Blocked On

Nothing.

## Next Steps

1. **Triage the 5 fresh captures.** BTS-332 (research-shape, recommend P3 with timebox), BTS-333 (small substrate fix, P3), BTS-334 (manifest-accuracy substrate, P3), BTS-337 (legacy-data-scan in provider-heal, recommend P2 — directly prevents the recurrence of today's stranded-data problem), BTS-374 (zsh-array footgun rule + helper, P3).
2. **Resume BTS-315** (init drift probe). Spec is in Todo, drafted, dispatched. Activate via `bash .ccanvil/scripts/docs-check.sh activate bts-315-init-drift-probe`. The `docs/specs/bts-315-init-drift-probe.md` file already exists in the working tree.
3. **Decide cluster ordering.** Open onboarding-theme work: BTS-312 (test-runner indirection — small pattern-anchor), BTS-313 (Linear provider activation deterministic flow during init), BTS-315 (init drift probe — drafted), BTS-327/328/329 (init-flow gaps), BTS-337 (provider-heal legacy-data-scan). Natural ordering: BTS-337 next (closes today's just-discovered gap), then BTS-315 (operator-facing init friction, spec-ready), then BTS-313 (broader init-time provider activation polish).

## Context Notes

- **The 4-tier auth chain shape is generalizable.** Linear-specific today (`linear-query.sh`); BTS-332 will define the broader pattern (env → project .env → ~/.env → keychain) as a reusable substrate primitive (`secret-resolve <env-var>`). Future provider integrations (GitHub, Notion) inherit the chain by name.
- **macOS Keychain is the operator's chosen secret store.** Service-name mapping rule: lowercased env-var name (`LINEAR_API_KEY` → `linear_api_key`). Mechanical, no per-key thinking required. Operator stored key via `security add-generic-password -a "$USER" -s linear_api_key -w` (interactive — key never passed through agent).
- **zsh-vs-bash array indexing bit twice this session.** Both during ad-hoc migration scripts where `${ids[0]}` evaluates to empty in zsh (1-indexed default) but bash-style 0-indexed expected. Fix: wrap multi-line shell snippets in `bash <<'BASHEOF' … BASHEOF` to force bash semantics regardless of operator $SHELL. BTS-374 captures the rule formally.
- **Migration audit-field convention.** When porting local→Linear, mark the local entry as `status: duplicate` AND add `migrated_to: "<linear-id>"`. Both fields persist; together they make the migration traceable from the local-routed gitignored ledger forward to the Linear ticket. This convention should be encoded in BTS-337's substrate.
- **Provider-heal-auth's "all healed" claim was misleading at session-25 close.** It verified auth from a shell where the key was already loaded — gave false steady-state usability signal. BTS-321's verify step needs a "is the key actually distributed where a fresh shell will find it?" check, not just "can I auth right now from MY shell?" Folded into BTS-337's scope (legacy-data-scan + auth-distribution-check at heal time).
- **Operator preference established mid-session.** Display ported entries title-led with summary, no raw uids — uids give zero context. Followed for taxes + fieldnation-toolbox after the m365 first-pass.
- **Code-review fold-in pattern reinforced.** BTS-331 review surfaced 4 concerns; concerns 1+2 (test-quality bugs in dead `STUB_KEYCHAIN_VALUE=` prefixes) folded into the same PR as commit 3a5c6b7; concerns 3+4 captured as BTS-333/334. Lightweight separation: fix what's same-touch, defer what's different scope.

## Determinism Review

- operations_reviewed: ~50 (1 ship lifecycle ~5 ops + 11-node broadcast verification + 5-node legacy-data audit + ~40 entry ports + 4 ledger rewrites + 6 captures)
- candidates_found: 1

* **idea-migrate-fleet**: For each of the 5 nodes with stranded local ideas, I composed an ad-hoc multi-step pipeline (read JSONL, filter active, port via idea.add, optionally transition state, then jq-rewrite the local ledger to add migrated_to). 5 iterations of similar substrate composition with a known shape. Should be a single substrate verb: `bash .ccanvil/scripts/docs-check.sh idea-migrate-fleet [--dry-run] [--filter <node-pattern>]` that reads `.ccanvil/registry.json`, iterates each node, ports active local entries to that node's Linear project (preserving local triage state via Backlog/P3 for `promoted`, Triage for `new`, Icebox for operator-flagged-defer entries), then rewrites the local ledger with `status: duplicate` + `migrated_to: <linear-id>`. Impact: high — directly closes BTS-337's gap and prevents this manual sweep from being repeated when the next batch of nodes onboard. Alternative shape: extend `provider-heal` umbrella with a `--with-migrate` flag.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

193 / 193 (allowlist), drift incidents: 0

## Cross-Session Patterns

- **CONFIRMED RECURRING (sessions 25 + 26 + 28): substrate-driven discovery loops compound.** Session 25 shipped provider-heal trio + capstone, dogfooded across 11 nodes, surfaced 3 init-flow gap captures (BTS-327/328/329). Session 26 drafted BTS-315 spec, surfaced LINEAR_API_KEY distribution gap → BTS-331. Session 28 (this one) shipped BTS-331, broadcast-deployed it, then the legacy-data audit surfaced BTS-337 (provider-heal needs a legacy-data-scan step). Each substrate maturity layer reveals the next gap-cluster — and each gap is in the substrate that just shipped. The pattern is durable.
- **NEW PATTERN: post-activation legacy-data audit is a critical missing step.** Provider-heal flips routing without scanning what was there before. 49 stranded local ideas across 5 nodes is a real visibility loss — invisible to `/idea list`, `/idea triage`, or any Linear-routed dispatcher. The migration substrate needed to fix this is captured as BTS-337. Reinforces "pre-activation state must be enumerated before activation."
- **NEW PATTERN: ad-hoc shell migration scripts must declare bash explicitly.** zsh's 1-indexed arrays bit twice in one session. Substrate scripts (`#!/usr/bin/env bash` shebanged) are fine; the bug surface is agent-driven multi-line shell snippets executed via the Bash tool. BTS-374 captures the rule.
- **No recurring legacy-refs.** legacy-refs-scan returns `[]`.

## Security Review

- Session diffs touched substrate (`.ccanvil/scripts/linear-query.sh` 4-tier auth chain), 4 existing bats files (HOME+PATH isolation in setup), 1 new bats file (auth-chain coverage), 11 downstream-node copies of `linear-query.sh` (broadcast). Plus 11 `.ccanvil/ideas.log` rewrites across 5 nodes (legacy-data migration with `migrated_to` audit fields).
- **NO credentials, NO PII, NO secrets in any committed change.** LINEAR_API_KEY was sourced from the operator's hub `.env` for substrate dispatch; never logged, never committed. macOS Keychain entry stored interactively by operator; key never passed through agent.
- security-audit.sh: 0 critical, 5 high, 3 medium — all pre-existing findings in `docs/sessions/` historical archives and `docs/specs/bts-72-...`. **None introduced this session.**
- Verdict: **PASS**.

## Memory Candidates

- **NEW PROJECT MEMORY candidate** — `project_bts_331_auth_distribution_complete` — BTS-331 shipped + broadcast 2026-05-07. 4-tier auth chain (env → project .env → ~/.env → macOS Keychain) live across all 11 registered downstream nodes. Single canonical key location: macOS Keychain service `linear_api_key`. Live-validated from web-browser-toolbox via env-stripped relative-path call.
- **NEW PROJECT MEMORY candidate** — `project_legacy_data_migration_complete` — 40 stranded local ideas migrated to Linear across 5 of 11 nodes; 5 pending-log entries drained. Every migrated entry carries `migrated_to: "BTS-XXX"` for audit. All 11 nodes now show 0 active local idea-log entries.
- **NEW REFERENCE candidate** — `reference_keychain_secret_store` — macOS Keychain is the operator's chosen secret store. Add a key: `security add-generic-password -a "$USER" -s <lowercased-env-var> -w` (interactive). Retrieve: `security find-generic-password -a "$USER" -s <name> -w`. ccanvil's `linear-query.sh` auto-resolves via tier-4 of the auth chain.
- **NEW FEEDBACK candidate** — `feedback_bash_explicit_for_multi_line_snippets` — When the Bash tool runs multi-line shell with bash-specific semantics (array indexing, parameter expansion edge cases), wrap in `bash <<'BASHEOF' … BASHEOF`. Operator's $SHELL is zsh on this machine; zsh's 1-indexed arrays silently corrupt outputs that assume bash 0-indexed semantics. Surfaced in 2 ad-hoc migration scripts session 28; tracked as BTS-374.
- **NEW FEEDBACK candidate** — `feedback_show_summaries_not_uids` — When presenting bulk-decision lists to the operator, lead with title + short summary, not raw uid/identifier. Uids give no context. Confirmed mid-session-28 during legacy-data triage.
- **REINFORCE** — `feedback_lightweight_pattern_dogfoods_substrate_design` — BTS-331 shipped as a 5-line substrate change wrapping the existing 2-tier auth chain rather than a new generic resolver. The follow-on (BTS-332) is the generic resolver; the lightweight ship validated the keychain integration end-to-end first.
- **REINFORCE** — `feedback_validate_plan_flagged_live_api` — BTS-331's plan flagged AC-10 as a live-API gate. Live invocation from web-browser-toolbox cwd with `env -i` stripped every variable; resolution via keychain tier worked. Caught nothing the bats stubs missed THIS time, but the discipline cost ~15 seconds and would have surfaced any first-run keychain prompt issue.
