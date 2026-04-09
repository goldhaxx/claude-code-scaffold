Initialize a new project using the ccanvil preset located at ~/projects/ccanvil.

1. Read ~/projects/ccanvil/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/ccanvil/hub/meta/SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Bootstrap the sync script so preflight can run:
   ```bash
   mkdir -p .ccanvil/scripts
   cp ~/projects/ccanvil/preset/.ccanvil/scripts/ccanvil-sync.sh .ccanvil/scripts/ccanvil-sync.sh
   ```
4. Run the preflight scan to detect conflicts between hub preset and existing project files:
   ```bash
   bash .ccanvil/scripts/ccanvil-sync.sh init-preflight ~/projects/ccanvil
   ```
   This outputs a JSON plan classifying every file as: `copy` (new from hub), `skip` (already matches or local-only), `section-merge` (both sides have content, can merge via delimiters), or `review` (conflict — needs user decision).
5. **If conflicts exist** (summary.conflicts > 0): Present the plan as a table:
   | File | Action | Reason |
   Each `review` file needs a decision. Present the hub and local versions, explain the difference, and recommend one of: `copy` (take hub), `skip` (keep local), `overwrite` (replace local with hub), or `section-merge` (if delimiters can be added). Ask the user to approve, deny, or edit the plan before proceeding.
   **If no conflicts** (summary.conflicts == 0): Proceed directly — no pause needed.
6. Write the approved plan to `.ccanvil/init-plan.json` and execute it:
   ```bash
   bash .ccanvil/scripts/ccanvil-sync.sh init-apply ~/projects/ccanvil .ccanvil/init-plan.json
   ```
7. Create project-owned docs directory with placeholders (skip if files already exist):
   - `docs/spec.md` (copy from `.ccanvil/templates/spec.md`)
   - `docs/plan.md` (copy from `.ccanvil/templates/plan.md`)
   - `docs/checkpoint.md` (copy from `.ccanvil/templates/checkpoint.md`)
   - `docs/specs/` (empty directory for spec backlog)
   - `docs/roadmap.md` (copy from `.ccanvil/templates/roadmap.md`)
8. Copy the ISSUE_TEMPLATE directory (not covered by sync patterns):
   ```bash
   mkdir -p .github/ISSUE_TEMPLATE
   cp -R ~/projects/ccanvil/preset/.ccanvil/templates/github/ISSUE_TEMPLATE/ .github/ISSUE_TEMPLATE/
   ```
9. Ask me three things:
   - Project name
   - One-line description of what it does
   - License (MIT, Apache 2.0, GPL-3.0, BSD-2-Clause, BSD-3-Clause, Unlicense, or none)
10. If a license was chosen, run the fetch-license script (deterministic — do NOT write license text yourself):
   ```bash
   bash .ccanvil/scripts/fetch-license.sh <license-key> "<fullname>" LICENSE
   ```
   Use the license key mapping: MIT→mit, Apache 2.0→apache-2.0, GPL-3.0→gpl-3.0, BSD-2-Clause→bsd-2-clause, BSD-3-Clause→bsd-3-clause, Unlicense→unlicense.
   For fullname, use the git user name: `git config user.name`.
   If "none" was chosen, skip this step.
11. Replace the `[Project Name]` and `[One-line description.]` placeholders in:
   - CLAUDE.md (node-specific section above `<!-- HUB-MANAGED-START -->`). Leave hub-managed section untouched.
   - README.md (title and description)
   - CONTRIBUTING.md (title)
   Also replace `[owner]/[repo]` in README.md with the project directory name.
12. The tech stack, commands, and architecture will be determined later as we spec and build features. Do not ask me to choose a stack now.
13. Generate the initial node-specific section of `.ccanvil/guide/index.md`:
   - Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for any files that are NOT from the preset (pre-existing local files).
   - If found: add a summary listing each local file and its purpose below the `NODE-SPECIFIC-START` delimiter.
   - If the project is empty (fresh init): leave the placeholder as-is.
14. Generate the lockfile by running: `./.ccanvil/scripts/ccanvil-sync.sh init ~/projects/ccanvil`
    This creates `.ccanvil/ccanvil.lock` which tracks the sync state between this project and the hub.
15. Initialize git and install hooks:
    ```bash
    git init
    cp .ccanvil/templates/github/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
    ```
    Validate: CLAUDE.md is under 80 lines. Commit: `git add -A && git commit -m "chore: initialize project with ccanvil preset"`.
