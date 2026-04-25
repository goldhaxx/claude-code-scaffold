# Feature: permissions-audit promote-review for settings.local.json delta

> Feature: bts-144-permissions-audit-promote-review
> Work: linear:BTS-144
> Created: 1777086458
> Status: In Progress

## Summary

`settings.local.json` is the staging area where session-time "always allow this command" approvals accumulate. The autonomy-first design (BTS-142) intends a recurring review cycle: when entries pile up, surface the delta against `settings.json` and triage each one — promote to hub, delete as one-shot noise, or keep-local. Today there's no tooling. The pre-BTS-142 145-entry graveyard was the natural endpoint of that drift. Add `permissions-audit.sh promote-review` that lists `settings.local.json` entries not covered by `settings.json`, classifies each deterministically (DELETE / PROMOTE-CANDIDATE / TRIAGE), and outputs both JSON and text modes for skill consumption.

## Job To Be Done

**When** my `settings.local.json` has accumulated session-time "always allow" approvals,
**I want to** see them grouped by recommendation (delete redundant/dead entries, promote durable ones, triage the rest),
**So that** I can decisively flush the staging area in one review pass instead of letting it drift into a graveyard.

## Acceptance Criteria

- [ ] **AC-1:** `permissions-audit.sh promote-review` (JSON mode by default) outputs `{candidates: [{permission, source, recommendation, reason}], counts: {delete: N, promote: N, triage: N, total: N}}` to stdout. Exit 0 always (no failure semantics — this is read-only review tooling).
- [ ] **AC-2:** Candidate set = entries appearing in `settings.local.json` AND NOT appearing literally in `settings.json`. Uses string equality on the permission string, no globbing.
- [ ] **AC-3:** When the local entry's exact-match equivalent does NOT exist in `settings.json` BUT a broader wildcard in `settings.json` already covers it (e.g., local has `Bash(git status:*)`, main has `Bash(git:*)`), recommendation is `DELETE` with reason `"redundant: covered by '<broader>' in settings.json"`.
- [ ] **AC-4:** When the local entry references a path containing `preset/` (the pre-BTS-67 hub directory removed during the flatten), recommendation is `DELETE` with reason `"dead path: pre-BTS-67 preset/ structure removed"`.
- [ ] **AC-5:** When the local entry uses an env-var prefix matching an existing `ALLOW_*=1` bypass (e.g., `Bash(ALLOW_OUTSIDE_WORKSPACE=1 bash ...)`) AND the underlying command is now allowed broadly in `settings.json`, recommendation is `DELETE` with reason `"one-shot bypass: underlying command now broadly allowed"`.
- [ ] **AC-6:** Otherwise, recommendation is `TRIAGE` with reason `"manual review required"` — these are the entries that need human judgment.
- [ ] **AC-7:** Empty `settings.local.json` (or no file) → output `{candidates: [], counts: {delete: 0, promote: 0, triage: 0, total: 0}}`, exit 0.
- [ ] **AC-8:** `--text` mode renders a grouped table: `--- DELETE (redundant) ---`, `--- DELETE (dead path) ---`, `--- DELETE (one-shot) ---`, `--- TRIAGE ---`, with permission + reason per row, summary footer.
- [ ] **AC-9:** No PROMOTE-classified entries in this version. The `counts.promote` field always returns 0; PROMOTE is reserved for `--apply` flow (deferred to follow-up). This keeps Acceptance shape stable across the deferred PROMOTE path.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Add `cmd_promote_review` + register `promote-review` in CMD parser + dispatch |
| `hub/tests/permissions-audit.bats` | New test block for AC-1..AC-9 (extending the existing file) |
| `.ccanvil/guide/command-reference.md` | Document `permissions-audit.sh promote-review` |

## Dependencies

- **Requires:** BTS-142 (autonomy-first permissions, the delta is meaningful), BTS-67 (the `preset/` directory removal — drives AC-4 dead-path detection). Both shipped.
- **Blocked by:** Nothing.

## Out of Scope

- `--apply` flag for automated execution (rewrite settings.json/settings.local.json based on a triage decision JSON). Defer to a follow-up — this ship is read-only review tooling.
- A `/permissions-review` skill that wraps the script and walks the agent through interactive triage. Defer.
- Detecting one-shot specificity beyond the env-prefix pattern (e.g., a path inside a now-deleted feature branch). The simple deterministic rules in AC-3..AC-5 cover the high-frequency cases; deeper heuristics need user judgment, hence TRIAGE.

## Implementation Notes

- Reuse `parse_settings_file` to load both files. Filter local entries by absence in main, then run each through a classifier function.
- Classifier function returns `(recommendation, reason)`. Order of rules matters: redundancy check (AC-3) → dead path (AC-4) → env-prefix one-shot (AC-5) → fallback TRIAGE.
- For AC-3 redundancy detection, use a shell-glob-aware comparison: a local entry like `Bash(git status:*)` is covered by main's `Bash(git:*)` if stripping the local entry's specific suffix and matching against the main entry's wildcard prefix succeeds. Concretely: for each main entry of the form `Bash(<word>:*)`, check whether the local entry starts with `Bash(<word> ` or `Bash(<word>:*)`. Conservative — false positives only DELETE entries that are clearly covered.
- For AC-5 (env-prefix one-shot), match the regex `Bash\(ALLOW_[A-Z_]+=1 (bash|rm|cp|mv|chmod|chown) ` and check whether the underlying verb is now broadly allowed (e.g., `Bash(bash:*)` exists in main).
- The two existing organic entries in `settings.local.json` from earlier this session (`ALLOW_OUTSIDE_WORKSPACE=1 bash ...`) are exactly AC-5 candidates — they should classify as DELETE post-ship. Dogfood validation.
- JSON contract is per the BTS-134 conventions — top-level object with `candidates` array + `counts` summary. Mirrors `check`'s envelope.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
