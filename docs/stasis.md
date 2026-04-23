# Stasis

> Feature: session-2026-04-23-bts-130-work-identity-ship
> Kind: session
> Last updated: 1776975000
> Session objective: Ship BTS-130 (provider-neutral work identity) end-to-end in one session — replacing the lazy BTS-120 regex-tolerance plan with the structural umbrella fix (stasis `Kind:` discriminator + provider-neutral `Work:` schema). Dogfood through the full lifecycle.

## Accomplished

- **Shipped PR #46 (`0fd027a`)** — `bts-130-work-identity`. 11 commits on branch; 6 TDD phases (14 conceptual steps) plus 1 code-review-fix commit plus 1 lifecycle cleanup commit. Full suite **836/836 bats green** (+28 from 808 baseline across 4 new test files). Clean squash-merge + FF `land`. **Zero regressions** in existing 808 tests despite core validator refactor.
- **BTS-130 Linear ticket created** with `relatedTo` links to BTS-120/119/124/128 (Linear auto-linked BTS-121 via embedded issue refs in description — bonus). Priority High, Backlog.
- **Three tickets transitioned to Done in Linear** post-merge: BTS-130 (the feature), BTS-120 (solved structurally via Kind: discriminator), BTS-124 (generalized provider-neutral and shipped inline). All three auto-attached to PR #46 via Linear's GitHub integration — first-try auto-link success on a `claude/feat/bts-130-*` branch confirms the substring-matcher theory.
- **Architecture decision — provider-neutral over Linear-specific.** Initial proposal was `ticket_id` as canonical field; Zach's "ccanvil is modular — we could be using local or future bolt-ons" pushback led to the final `<provider>:<id>` schema (`linear:BTS-130`, `local:idea-29`, future `github:owner/repo#123`). Captured as new feedback memory: `feedback_provider_neutral_schemas.md`.
- **`.ccanvil/scripts/operations.sh`** — new `work.resolve` verb + `slug_from_work_id()` helper. Direct identity shape output `{provider, id, slug, url}`, deliberately different from the wrapped `{provider, mechanism, invocation, contract}` shape of other ops (documented in adapter comments). Work-group routing falls back to idea's routing (same provider). Explicit `<provider>:<id>` prefix overrides routing. Strict format validation: whitespace rejected, empty slug rejected, bare Linear IDs must match `^[A-Z]+-[0-9]+$`, bare local IDs must contain digits or match `idea-*`.
- **`.ccanvil/scripts/docs-check.sh`** — `parse_metadata` extracts `Work:` + `Kind:`. Validator aligns on `Work:` equality across feature docs when all participating docs carry it; falls back to `feature_id` when any doc lacks it (legacy grandfather — zero migration for fucina/luxlook). Session-kind stasis excluded from feature alignment entirely: **this is the BTS-120 structural fix**, not a regex-tolerance hack. THIS stasis is the first session-kind stasis written under the new schema.
- **Skills + templates + guide updated** — `/spec` requires work ref as first arg (with script-side validation, not just prose); `/stasis` picks feature-kind vs session-kind from spec+plan presence; spec/plan/stasis templates have `Work:`/`Kind:` placeholders; `command-reference.md` documents work identity schema and `work.resolve` verb.
- **Code review caught 3 WARN items, all fixed pre-merge** (commit `cbf66b5`): /spec `idea <num>` ordering bug, empty-slug git-branch invalidation, loose /spec stop condition. Three NITs deferred to follow-up (workspace config doc, mechanism default comment, trailing-whitespace trim).
- **Session-boundary stasis workaround used once more** — pre-BTS-130 fix, had to `git rm docs/stasis.md` on the activate'd feature branch to unstick validate. This won't recur: BTS-130 is the fix. The symmetry is satisfying.

## Current State

- **Branch:** `main` at `0fd027a`, synced with origin.
- **Tests:** 836/836 bats green at PR HEAD; post-merge on main: not re-run (squash was FF-equivalent).
- **Uncommitted changes:** none (working tree clean post-`land`).
- **Build status:** clean.
- **Context budget:** 5188 / 8000 tokens = 64.8% (HEALTHY).
- **Permissions audit:** 20 DANGER + 166 UNREVIEWED (long-standing; up by ~2 from prior session — verify source next session if relevant).
- **Specs archive:** 43 complete (was 41); no active/ready/in-progress specs.

## Blocked On

- Nothing.

## Next Steps

1. **Triage the Linear inbox** — Local idea-count shows 5 items in triage state; Linear Triage has more (prior captures: BTS-122/123/125/127 and possibly others). Run `/idea triage` to assign priorities + promote/defer/dismiss. Highest-leverage candidates for `/spec` promotion: BTS-122 (pre-activate guard audit), BTS-125 (Linear markdown truncation).
2. **Ship BTS-128** (`ticket.transition` wrapper) — now the *only* remaining adjacent infra to BTS-130. Same session used it 3× (BTS-130/120/124 Done transitions) via manual UUID paste. Also adds `done` to `state_ids` config. Natural next ship — small and strictly deterministic.
3. **Ship BTS-119** (auto-close Linear on merge) — unblocked by BTS-130. Every new branch now carries the ticket substring via the slug convention, so Linear's GitHub integration can auto-transition. Small ship, delivers big ongoing automation.
4. **Ship BTS-122** (pre-activate guard audit) — comprehensive review + hardening of pre-flight checks. Larger scope but each gap is well-scoped.
5. **Ship BTS-125** (Linear `save_issue` markdown truncation) — workaround exists (H3 per section); the ticket is about codifying the rule.
6. **Ship BTS-118 / BTS-127** (bats assertion leak family) — same pattern family, could merge into one ship.
7. **Pick from Backlog**: BTS-113 (stale recommend after stasis+compact+recall).

## Context Notes

- **Strategic pivot this session** — rejected a lazy fix path (stasis regex tolerance for BTS-120) in favor of the structural umbrella (BTS-130). Decisive moment was Zach saying "this feels like it could be a lazy fix... think harder. There's an optimal high level strategic fix here." The reframe was: BTS-120 is a symptom of ccanvil having no canonical work-identity abstraction. Solution had to be provider-neutral to preserve ccanvil's modularity, not Linear-specific.
- **Provider-neutral `<provider>:<id>` schema** — new canonical identity format. Applies wherever ccanvil coordinates with external systems. Generalizes to GitHub, Jira, Shortcut, etc. without code changes — each provider just gets a new adapter branch.
- **Grandfather clause philosophy** — validator falls back to `feature_id` alignment when any doc lacks `Work:`. Enforcement happens at `/spec` creation, not at validate. Clean forward cutover, zero migration for existing projects. This pattern should be reused for future schema changes.
- **Direct identity shape for work.resolve** — different output shape from other `operations.sh resolve` ops (work.resolve IS the result, not a plan). Documented in both adapters. The "operations.sh resolve family has two patterns" design is pragmatic, not purist.
- **Code-review-then-fix-pre-merge** validated as the right approach for WARN findings. Three WARN items fixed inline; only NITs deferred. Contrasts with BTS-121's Option A choice (file everything as follow-ups).
- **Validator self-consistency** — this feature's own spec+plan both carried `Work: linear:BTS-130`, validated clean through the new alignment logic throughout TDD. Meta-dogfood: the code paths added in steps 8-10 were exercising our own lifecycle by step 14.
- **`activate` side-effect discovered** — the squash-merge's Linear auto-link fired because the branch name `claude/feat/bts-130-work-identity` contained the substring `bts-130`. This confirms the empirical finding from BTS-121 about Linear's GitHub matcher. AC-14 works in production, not just in bats.

## Determinism Review

- **operations_reviewed:** 35
- **candidates_found:** 1 recurring (already captured)
- **Linear state transition by role name** (recurring from prior): Claude manually issued `save_issue { id, state: <uuid> }` 3× this session (BTS-130/120/124 → Done) pasting the "Done" UUID `bc6aa160-258d-4eae-b3b5-a2575732a188` literally each time. The Done UUID is still not in `.claude/ccanvil.local.json:state_ids`. Should be `operations.sh exec ticket.transition <id> done` wrapper. Already captured as **BTS-128**; same operation recurred this session, confirming the leverage.
- **No new candidates this session.** The `ticket.find-by-title` workflow (BTS-129) did NOT recur (no title-dedup searches needed). The session-boundary stasis `rm` workaround IS the bug BTS-130 just shipped to fix — post-merge it won't recur, so not a candidate.

## Cross-Session Patterns

- **RESOLVED: BTS-120 session-stasis trap** — prior stasis flagged this as recurring. Hit this session AGAIN at activate (fourth consecutive occurrence). **Fix shipped in this PR.** Next session on a fresh activate should NOT trip it because the validator now excludes `Kind: session` stasis from alignment. THIS stasis is the first session-kind stasis written under the new schema — self-proof.
- **RECURRING: BTS-128 manual UUID paste** — prior stasis flagged it; used 3× this session. Still open; next ship target per Next Steps.
- **RECURRING: `git rm docs/stasis.md` workaround during activate** — fourth consecutive session. Last time this should appear: BTS-130 ships the structural fix.
- **Legacy-refs-scan: `/catchup`** — 5 matches (`command-reference.md` hub-owned, `foundations.md` node-specific × 4). Same as prior session, no change. Next `/ccanvil-pull` on a downstream node will resolve hub-owned matches.
- **Audit-session false positives** — `git -C` patterns flagged in `spec-slug-convention.bats`. These are committed test-fixture code (bats setup for activate tests), not stochastic Claude operations. Ignore.

## Security Review

- `security-audit.sh --files-only` run during `/review`: **PASS** (no secrets, PII, emails, dangerous file types).
- Code review explicitly checked command-injection surface: `OP_ARGS` flows only through `jq -n --arg`, never shell-interpolated. URL synthesis safe (serialized as JSON data, never shell-executed). PASS.
- No new secrets/tokens/keys introduced. Commit diffs scanned clean.
- NIT: parse_metadata doesn't trim trailing whitespace on extracted values — pre-existing across all fields; now load-bearing for Work: alignment. Minor hardening target (captured in PR's Review Notes).

## Memory Candidates

- **Provider-neutral schemas for ccanvil** (feedback) — **ALREADY CAPTURED this session** in `feedback_provider_neutral_schemas.md`. The lesson: when designing new coordination layers, always ask "does this work on local-provider AND Linear AND future bolt-ons?" Provider-neutral `<provider>:<id>` preserves modularity; bare provider-specific fields break it.
- **Pre-merge WARN fix over follow-up** (feedback) — code-review WARN findings that affect documented use cases (e.g., `/spec idea <num>` producing wrong filenames) should be fixed before merge, not filed as follow-up tickets. NITs file fine as follow-ups. This session validated the pattern cleanly; worth capturing as feedback vs BTS-121's broader "Option A" choice.
- **BTS-130 canonical schema** (project) — `Work: <provider>:<id>` is now the coordination key across all lifecycle docs. Session-kind stasis carries `Kind: session` and is excluded from feature alignment. Future schema changes should use the grandfather-clause pattern (enforce at creation, legacy fallback at validate) to preserve downstream nodes without migration.
- **Blocktech "Done" state UUID** (reference) — `bc6aa160-258d-4eae-b3b5-a2575732a188`. Used 3× this session by manual paste. Should be added to `.claude/ccanvil.local.json:state_ids` in the BTS-128 ship. Same note as prior stasis — not yet done.
- **Linear GitHub integration auto-link confirmed in production** (reference) — branch `claude/feat/bts-130-work-identity` containing the `bts-130` substring triggered Linear's auto-attach of PR #46 to BTS-130 (and, via description refs, to BTS-120/124). Confirms the lenient-prefix, strict-substring matcher model. Same note as prior stasis, with added confirmation that `claude/feat/<slug>-<name>` prefix works.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
