Initialize a new project using the Claude Code development scaffold located at ~/projects/claude-code-scaffold.

1. Read ~/projects/claude-code-scaffold/README.md — it contains the complete file manifest and setup instructions.
2. Read ~/projects/claude-code-scaffold/SCAFFOLD_SYSTEM_PROMPT.md for the full specification of constraints and formatting rules.
3. Copy all project files from the scaffold into the current working directory following the Quick Start instructions. Skip Step 1 (global setup is already done). Make sure to copy:
   - `.claude/` directory (rules, commands, agents, skills, settings)
   - `docs/templates/` (persistent format guides)
   - `scripts/` (scaffold-sync.sh, fix-cloudflare-certs.sh)
   - `GUIDE.md` (scaffold guide with visual diagrams)
   - `SCAFFOLD_FRAMEWORK.md` (foundational research — read-only reference)
   - `CLAUDE.md` (project configuration template)
4. Ask me only two things:
   - Project name
   - One-line description of what it does
5. Replace the `[Project Name]` and `[One-line description.]` placeholders in the node-specific section (above `<!-- HUB-MANAGED-START -->`) of CLAUDE.md. Leave the hub-managed section (below the delimiter) untouched.
6. The tech stack, commands, and architecture will be determined later as we spec and build features. Do not ask me to choose a stack now.
7. Generate the initial node-specific section of GUIDE.md:
   - Scan `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, `.claude/skills/` for any files that are NOT from the scaffold (pre-existing local files).
   - If found: replace the placeholder node section with a summary listing each local file and its purpose.
   - If the project is empty (fresh init): leave the placeholder as-is ("No project-specific features yet").
8. Generate the scaffold lockfile by running: `./scripts/scaffold-sync.sh init ~/projects/claude-code-scaffold`
   This creates `.claude/scaffold.lock` which tracks the sync state between this project and the scaffold hub.
9. Validate: CLAUDE.md is under 80 lines. Commit the initialized scaffold with `git init && git add -A && git commit -m "chore: initialize project scaffold"`.
