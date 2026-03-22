Initialize a new project using the Claude Code development scaffold located at ~/projects/claude-code-scaffold.

1. Read ~/projects/claude-code-scaffold/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/claude-code-scaffold/SCAFFOLD_SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Copy all project files from the scaffold into the current working directory following the Quick Start instructions. Skip Step 1 (global setup is already done). Make sure to copy:
   - `.claude/` directory (rules, commands, agents, skills, hooks, settings)
   - `docs/templates/` (persistent format guides, NOT the github/ subdirectory itself)
   - `scripts/` (scaffold-sync.sh, security-audit.sh, fix-cloudflare-certs.sh)
   - `GUIDE.md` (scaffold guide with visual diagrams)
   - `SCAFFOLD_FRAMEWORK.md` (foundational research — read-only reference)
   - `CLAUDE.md` (project configuration template)
   - GitHub-ready files from `docs/templates/github/`:
     - Copy `README.md` → project root `README.md`
     - Copy `CONTRIBUTING.md` → project root `CONTRIBUTING.md`
     - Copy `ISSUE_TEMPLATE/` → `.github/ISSUE_TEMPLATE/`
     - Copy `PULL_REQUEST_TEMPLATE.md` → `.github/PULL_REQUEST_TEMPLATE.md`
     - Copy `pre-push` → `.git/hooks/pre-push` (after git init)
   - Copy `docs/templates/lint.json` → `.claude/lint.json`
4. Ask me only two things:
   - Project name
   - One-line description of what it does
5. Replace the `[Project Name]` and `[One-line description.]` placeholders in:
   - CLAUDE.md (node-specific section above `<!-- HUB-MANAGED-START -->`). Leave hub-managed section untouched.
   - README.md (title and description)
   - CONTRIBUTING.md (title)
   Also replace `[owner]/[repo]` in README.md with the project directory name.
6. The tech stack, commands, and architecture will be determined later as we spec and build features. Do not ask me to choose a stack now.
7. Generate the initial node-specific section of GUIDE.md:
   - Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for any files that are NOT from the scaffold (pre-existing local files).
   - If found: replace the placeholder node section with a summary listing each local file and its purpose.
   - If the project is empty (fresh init): leave the placeholder as-is ("No project-specific features yet").
8. Generate the scaffold lockfile by running: `./scripts/scaffold-sync.sh init ~/projects/claude-code-scaffold`
   This creates `.claude/scaffold.lock` which tracks the sync state between this project and the scaffold hub.
9. Initialize git and install hooks:
   ```bash
   git init
   cp docs/templates/github/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
   ```
   Validate: CLAUDE.md is under 80 lines. Commit: `git add -A && git commit -m "chore: initialize project scaffold"`.
