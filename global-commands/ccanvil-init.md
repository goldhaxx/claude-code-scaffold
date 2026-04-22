Initialize a new project using the ccanvil preset located at ~/projects/ccanvil, or retrofit it onto an existing project. (Invoked as /ccanvil-init.)

## Bootstrap and preflight

1. Read ~/projects/ccanvil/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/ccanvil/hub/meta/SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Bootstrap the sync script so preflight can run:
   ```bash
   mkdir -p .ccanvil/scripts
   cp ~/projects/ccanvil/.ccanvil/scripts/ccanvil-sync.sh .ccanvil/scripts/ccanvil-sync.sh
   ```
4. Run preflight and capture the detected project mode:
   ```bash
   bash .ccanvil/scripts/ccanvil-sync.sh init-preflight ~/projects/ccanvil > /tmp/ccanvil-preflight.json
   MODE=$(jq -r '.project_mode' /tmp/ccanvil-preflight.json)
   echo "Detected mode: $MODE"
   ```
   For a read-only dry-run outside this skill, users can run
   `bash .ccanvil/scripts/ccanvil-sync.sh retrofit-check ~/projects/ccanvil`
   which prints the same table this skill uses.

## Branch on project_mode

### already-initialized (AC-12, AC-13)

If `$MODE == "already-initialized"`, DO NOT proceed with the standard init flow. The project is already set up; this skill only refreshes it on request. Offer the user three options:

- **Update from hub** — run `/ccanvil-pull` (pre-check + pull-plan + auto-apply safe updates).
- **Re-register with hub** — run `bash .ccanvil/scripts/ccanvil-sync.sh register` only (refresh registry entry).
- **Abort** — exit without changes.

The already-initialized path does not run git init and does not write a `chore:` initialization commit. It's idempotent by design.

### fresh / source-no-git / mature-repo / partial-ccanvil — proceed with mode-aware init

Present the preflight plan as a table. Columns: **File** | **Hub** | **Local** | **Action** | **Reason**. Render via `bash .ccanvil/scripts/ccanvil-sync.sh retrofit-check ~/projects/ccanvil`, or emit the same shape from the JSON plan — both paths use a shared formatter.

Actions you may see:
- `copy` — new file from hub.
- `skip` — already matches hub, or (mature-repo / partial-ccanvil mode) local node-specific content preserved.
- `section-merge` — both sides have delimiters; merge hub section with local node section.
- `section-merge-create-delimiters` — mature CLAUDE.md without delimiters; the existing content becomes the node section and `<!-- HUB-MANAGED-START -->` is inserted before the hub section is appended. Local prose is preserved verbatim.
- `review` — conflicts requiring user decision.

**If any row has action = `review`** (summary.conflicts > 0): Ask the user to decide per-file. Accept: `copy`, `skip`, `overwrite`, or `section-merge`. Edit the plan accordingly before writing it.

**If summary.conflicts == 0**: Proceed directly — no pause needed.

5. Write the approved plan to `.ccanvil/init-plan.json` and execute it:
   ```bash
   bash .ccanvil/scripts/ccanvil-sync.sh init-apply ~/projects/ccanvil .ccanvil/init-plan.json
   ```

## Step 6 — Lifecycle docs placeholders (AC-10, AC-11)

For each of `docs/spec.md`, `docs/plan.md`, `docs/stasis.md`, `docs/roadmap.md`:

```bash
for f in docs/spec.md docs/plan.md docs/stasis.md docs/roadmap.md; do
  if [[ -s "$f" ]]; then
    echo "PRESERVED: $f"
  else
    mkdir -p "$(dirname "$f")"
    cp "$HUB/.ccanvil/templates/$(basename "$f")" "$f"
  fi
done
mkdir -p docs/specs
```

If `docs/stasis.md` was preserved AND contains a `> Feature: <id>` header, surface it in the post-init summary as: `detected in-progress feature: <id>`. This tells the user their mid-flight work is intact.

## Step 7 — Copy GitHub templates

```bash
mkdir -p .github/ISSUE_TEMPLATE
cp -R ~/projects/ccanvil/.ccanvil/templates/github/ISSUE_TEMPLATE/ .github/ISSUE_TEMPLATE/
```

## Step 8 — Project metadata

Ask the user:
- Project name
- One-line description of what it does
- License (MIT, Apache 2.0, GPL-3.0, BSD-2-Clause, BSD-3-Clause, Unlicense, or none)

If a license was chosen, run the fetch-license script (deterministic — do NOT write license text yourself):
```bash
bash .ccanvil/scripts/fetch-license.sh <license-key> "<fullname>" LICENSE
```
License key mapping: MIT→mit, Apache 2.0→apache-2.0, GPL-3.0→gpl-3.0, BSD-2-Clause→bsd-2-clause, BSD-3-Clause→bsd-3-clause, Unlicense→unlicense. Use `git config user.name` for fullname. Skip if "none".

Replace `[Project Name]` and `[One-line description.]` placeholders in:
- CLAUDE.md (node-specific section above `<!-- HUB-MANAGED-START -->`; leave hub-managed section untouched).
- README.md (title and description).
- CONTRIBUTING.md (title).
Also replace `[owner]/[repo]` in README.md with the project directory name.

## Step 9 — Guide generation

Generate the node-specific section of `.ccanvil/guide/index.md`:
- Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for non-preset files.
- If found: add a summary listing each local file and its purpose below the `NODE-SPECIFIC-START` delimiter.
- If none: leave the placeholder as-is.

## Step 10 — Register with hub

```bash
bash .ccanvil/scripts/ccanvil-sync.sh init ~/projects/ccanvil
```
This creates `.ccanvil/ccanvil.lock` and auto-registers the project in the hub's registry.

## Step 11 — Mode-aware git lifecycle (AC-8, AC-9)

Branch on `$MODE`:

**fresh / source-no-git** — full init:
```bash
git init
# Validate CLAUDE.md is under 80 lines, then:
git add -A && git commit -m "chore: initialize project with ccanvil preset"
```

**mature-repo / partial-ccanvil** — retrofit, preserve existing git history:
```bash
# Do NOT run `git init` — the repo already has commits.
git add -A && git commit -m "chore(ccanvil): retrofit preset onto existing project"
```

**already-initialized** — not reached (handled at the top of this skill).

### Pre-push hook — conditional install (AC-9)

```bash
HUB_HOOK=~/projects/ccanvil/.ccanvil/templates/github/pre-push
if [[ -f .git/hooks/pre-push ]] && \
   ! diff -q .git/hooks/pre-push "$HUB_HOOK" >/dev/null 2>&1; then
  echo "WARNING: existing pre-push hook differs from hub template — preserving local version"
else
  cp "$HUB_HOOK" .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
fi
```

The tech stack, commands, and architecture will be determined later as features are spec'd and built. Do not ask the user to choose a stack now.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
