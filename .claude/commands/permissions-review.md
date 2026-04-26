Walk the user through pending permissions-review candidates interactively, collect per-row decisions, and dispatch them via `permissions-audit.sh apply --decisions`.

`/permissions-review` is the agentic glue between BTS-143 (`accept_danger` override), BTS-144 (`promote-review` classifier), and BTS-149 (`apply --decisions` substrate). It surfaces the silent classifier output, gates every mutation behind explicit user confirmation, then dispatches the decision JSONL deterministically. No silent mutations; no Linear-UI bypasses; no manual JSON editing.

## Steps

### 1. Gather state

```bash
PR_PROMOTE=$(mktemp -t pr-promote)
PR_CHECK=$(mktemp -t pr-check)
DECISIONS=$(mktemp -t pr-decisions)
bash .ccanvil/scripts/permissions-audit.sh promote-review --json > "$PR_PROMOTE"
bash .ccanvil/scripts/permissions-audit.sh check --json > "$PR_CHECK"
```

Parse `.candidates[]` from `$PR_PROMOTE` (delta entries from `settings.local.json`, classified DELETE / TRIAGE).
Parse `.entries[]` from `$PR_CHECK` and filter to those with `.status == "DANGER"` (broad wildcards lacking `accept_danger:true`). Use `mktemp` to avoid races between concurrent `/permissions-review` invocations.

### 2. No-op fast path (AC-9)

If both lists are empty, echo `No candidates to review.` and exit. Idempotent — re-running with no candidates is a no-op.

### 3. Promote-review walkthrough

For each promote-review candidate, present 3 lines + 1 prompt — terse, no preamble:

```
Permission: <permission>
Recommended: <DELETE|TRIAGE>  (<reason>)
Decision? [approve / keep-local / triage] (default approve)
```

Map user input to a decision verb:
- `approve` → if recommendation was DELETE → `delete`. If recommendation was TRIAGE → `promote`. (TRIAGE recommendation means "manual review needed, lean toward keeping but make it official by promoting.")
- `keep-local` → `keep-local` (no-op, leaves entry in `settings.local.json`).
- `triage` → ask follow-up "delete or promote?" then map accordingly.

Append the decision to the buffer via the BTS-159 `decision-append` substrate (replaces the legacy Write+cat+rm dance — one validated call per row):

```bash
bash .ccanvil/scripts/permissions-audit.sh decision-append \
  --buffer "$DECISIONS" \
  --permission "<permission>" \
  --decision <delete|promote|keep-local>
```

The script validates the decision verb against the same schema `apply --decisions` uses; on validation failure it exits 2 and writes nothing.

### 4. DANGER walkthrough

For each DANGER entry without `accept_danger:true`, present:

```
Permission: <permission>  [DANGER: <matched_pattern>]
Action? [accept-danger / skip] (default skip)
```

If `accept-danger`:
- Prompt for: `risk` (1-line description of what could go wrong), `rationale` (why we accept the risk), `efficiency` (how often is this used / what does it save), `reviewer` (your name).
- Validate all four are non-empty and not "TODO" — re-prompt if invalid.
- Append via the BTS-159 substrate:
```bash
bash .ccanvil/scripts/permissions-audit.sh decision-append \
  --buffer "$DECISIONS" \
  --permission "<permission>" \
  --decision accept-danger \
  --risk "<risk>" \
  --rationale "<rationale>" \
  --efficiency "<efficiency>" \
  --reviewer "<reviewer>"
```
The script enforces the four-field non-empty / non-"TODO" check and emits the schema-correct JSON line; the skill only collects the prompts.

If `skip`: don't append anything. The DANGER entry stays unreviewed (will surface again next session).

### 5. Dispatch

By this point, steps 3 and 4 have appended one JSONL record per approved decision into `$DECISIONS` (created up front in step 1). Now dispatch:

```bash
bash .ccanvil/scripts/permissions-audit.sh apply --decisions "$DECISIONS"
```

Capture the JSON envelope `{applied, skipped, errors}`. On exit code 2 (validation), 3 (atomicity restore), or non-zero, surface the error to the user — `apply` will have already restored `.bak` files. On success (exit 0), echo:

```
Applied: <applied> | Skipped: <skipped> | Errors: <errors-len>
```

### 6. Cleanup

`rm "$PR_PROMOTE" "$PR_CHECK" "$DECISIONS"`.

## Rules

- `/permissions-review` is the canonical interactive review surface. Never bypass to direct file editing; always go through `apply --decisions`.
- Every mutation requires explicit user confirmation. Pre-checked defaults are a UX nicety, but a row is never auto-applied without user input.
- The substrate (`apply --decisions`) handles atomicity. The skill handles only the Q&A and dispatch. Don't re-implement validation in the skill — let the script reject malformed input via exit 2.
- When invoked at session boundaries via the `/stasis` or `/recall` nudge, run from `main` if possible (post-`/land`) so settings mutations don't mix with feature commits. Not enforced — judgment call.
- `/permissions-review` NEVER commits or pushes. Settings file mutations show up as uncommitted changes; user decides when to commit (typically as a one-line `chore(permissions): ...` on `main`).

## Out of scope

- Editing existing `accept_danger:true` log entries — `apply` only writes new entries. Updating an existing rationale stays manual via `permissions-audit.sh init` patch.
- Adding entries to `settings.local.json` — this skill only triages existing ones.
- Global cross-node sync — local mutations only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
