Initialize a new project using the ccanvil preset located at ~/projects/ccanvil.

1. Read ~/projects/ccanvil/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/ccanvil/hub/meta/SCAFFOLD_SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Copy distributable artifacts from `~/projects/ccanvil/preset/` into the current working directory:
   - `preset/.claude/` → `.claude/` (rules, commands, agents, skills, hooks, settings)
   - `preset/.ccanvil/scripts/` → `.ccanvil/scripts/` (ccanvil-sync.sh, security-audit.sh, etc.)
   - `preset/.ccanvil/guide/` → `.ccanvil/guide/` (split guide section files)
   - `preset/.ccanvil/templates/` → `.ccanvil/templates/` (persistent format guides)
   - `preset/CLAUDE.md` → `CLAUDE.md` (project configuration template)
   - `preset/.claudeignore` → `.claudeignore`
   - GitHub-ready files from `preset/.ccanvil/templates/github/`:
     - Copy `README.md` → project root `README.md`
     - Copy `CONTRIBUTING.md` → project root `CONTRIBUTING.md`
     - Copy `ISSUE_TEMPLATE/` → `.github/ISSUE_TEMPLATE/`
     - Copy `PULL_REQUEST_TEMPLATE.md` → `.github/PULL_REQUEST_TEMPLATE.md`
     - Copy `workflows/ci.yml` → `.github/workflows/ci.yml`
     - Copy `pre-push` → `.git/hooks/pre-push` (after git init)
   - Copy `preset/.ccanvil/templates/lint.json` → `.claude/lint.json`
4. Create project-owned docs directory with placeholders:
   - `docs/spec.md` (copy from `.ccanvil/templates/spec.md` or create empty placeholder)
   - `docs/plan.md` (copy from `.ccanvil/templates/plan.md` or create empty placeholder)
   - `docs/checkpoint.md` (copy from `.ccanvil/templates/checkpoint.md` or create empty placeholder)
   - `docs/specs/` (empty directory for spec backlog)
5. Ask me three things:
   - Project name
   - One-line description of what it does
   - License (MIT, Apache 2.0, GPL-3.0, BSD-2-Clause, BSD-3-Clause, Unlicense, or none)
6. If a license was chosen, run the fetch-license script (deterministic — do NOT write license text yourself):
   ```bash
   bash .ccanvil/scripts/fetch-license.sh <license-key> "<fullname>" LICENSE
   ```
   Use the license key mapping: MIT→mit, Apache 2.0→apache-2.0, GPL-3.0→gpl-3.0, BSD-2-Clause→bsd-2-clause, BSD-3-Clause→bsd-3-clause, Unlicense→unlicense.
   For fullname, use the git user name: `git config user.name`.
   If "none" was chosen, skip this step.
7. Replace the `[Project Name]` and `[One-line description.]` placeholders in:
   - CLAUDE.md (node-specific section above `<!-- HUB-MANAGED-START -->`). Leave hub-managed section untouched.
   - README.md (title and description)
   - CONTRIBUTING.md (title)
   Also replace `[owner]/[repo]` in README.md with the project directory name.
8. The tech stack, commands, and architecture will be determined later as we spec and build features. Do not ask me to choose a stack now.
9. Generate the initial node-specific section of `.ccanvil/guide/index.md`:
   - Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for any files that are NOT from the preset (pre-existing local files).
   - If found: add a summary listing each local file and its purpose below the `NODE-SPECIFIC-START` delimiter.
   - If the project is empty (fresh init): leave the placeholder as-is.
10. Generate the lockfile by running: `./.ccanvil/scripts/scaffold-sync.sh init ~/projects/ccanvil`
    This creates `.ccanvil/ccanvil.lock` which tracks the sync state between this project and the hub.
11. Initialize git and install hooks:
    ```bash
    git init
    cp .ccanvil/templates/github/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
    ```
    Validate: CLAUDE.md is under 80 lines. Commit: `git add -A && git commit -m "chore: initialize project with ccanvil preset"`.
