Initialize a new project using the Claude Code development scaffold located at ~/projects/claude-code-scaffold.

1. Read ~/projects/claude-code-scaffold/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/claude-code-scaffold/SCAFFOLD_SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Copy all project files from the scaffold into the current working directory following the Quick Start instructions. Skip Step 1 (global setup is already done). Make sure to copy:
   - `.claude/` directory (rules, commands, agents, skills, hooks, settings)
   - `docs/templates/` (persistent format guides, NOT the github/ subdirectory itself)
   - `scripts/` (scaffold-sync.sh, security-audit.sh, fix-cloudflare-certs.sh, fetch-license.sh)
   - `docs/scaffold-guide/` (scaffold guide — split into section files)
   - `docs/scaffold-guide/scaffold-framework.md` (foundational research — read-only reference)
   - `CLAUDE.md` (project configuration template)
   - GitHub-ready files from `docs/templates/github/`:
     - Copy `README.md` → project root `README.md`
     - Copy `CONTRIBUTING.md` → project root `CONTRIBUTING.md`
     - Copy `ISSUE_TEMPLATE/` → `.github/ISSUE_TEMPLATE/`
     - Copy `PULL_REQUEST_TEMPLATE.md` → `.github/PULL_REQUEST_TEMPLATE.md`
     - Copy `workflows/ci.yml` → `.github/workflows/ci.yml`
     - Copy `pre-push` → `.git/hooks/pre-push` (after git init)
   - Copy `docs/templates/lint.json` → `.claude/lint.json`
4. Ask me three things:
   - Project name
   - One-line description of what it does
   - License (MIT, Apache 2.0, GPL-3.0, BSD-2-Clause, BSD-3-Clause, Unlicense, or none)
5. If a license was chosen, run the fetch-license script (deterministic — do NOT write license text yourself):
   ```bash
   bash scripts/fetch-license.sh <license-key> "<fullname>" LICENSE
   ```
   Use the license key mapping: MIT→mit, Apache 2.0→apache-2.0, GPL-3.0→gpl-3.0, BSD-2-Clause→bsd-2-clause, BSD-3-Clause→bsd-3-clause, Unlicense→unlicense.
   For fullname, use the git user name: `git config user.name`.
   If "none" was chosen, skip this step.
6. Replace the `[Project Name]` and `[One-line description.]` placeholders in:
   - CLAUDE.md (node-specific section above `<!-- HUB-MANAGED-START -->`). Leave hub-managed section untouched.
   - README.md (title and description)
   - CONTRIBUTING.md (title)
   Also replace `[owner]/[repo]` in README.md with the project directory name.
7. The tech stack, commands, and architecture will be determined later as we spec and build features. Do not ask me to choose a stack now.
8. Generate the initial node-specific section of `docs/scaffold-guide/index.md`:
   - Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for any files that are NOT from the scaffold (pre-existing local files).
   - If found: add a summary listing each local file and its purpose below the `NODE-SPECIFIC-START` delimiter.
   - If the project is empty (fresh init): leave the placeholder as-is.
9. Generate the scaffold lockfile by running: `./scripts/scaffold-sync.sh init ~/projects/claude-code-scaffold`
   This creates `.claude/scaffold.lock` which tracks the sync state between this project and the scaffold hub.
10. Initialize git and install hooks:
   ```bash
   git init
   cp docs/templates/github/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
   ```
   Validate: CLAUDE.md is under 80 lines. Commit: `git add -A && git commit -m "chore: initialize project scaffold"`.
