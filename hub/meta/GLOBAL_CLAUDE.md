# Global Preferences

## Identity
- My name is [Your name]. Address me by name when clarifying decisions.
- I value first-principles thinking. Explain *why* before *how*.
- I prefer concise, direct communication. Skip preamble.

## Workflow Defaults
- Always run tests after making changes. Never skip verification.
- Commit early and often with conventional commit messages (feat:, fix:, refactor:, test:, docs:, chore:).
- When I say "plan this," write a plan to `docs/plan.md` before writing any code.
- When I say "spec this," create a specification in `docs/spec.md` with acceptance criteria before implementation.
- Prefer TypeScript over JavaScript unless the project explicitly uses JS.
- Use ESM imports, not CommonJS, unless the project requires otherwise.

## Communication Style
- If you're unsure about a requirement, ask before coding. Don't guess.
- When proposing architecture, give me 2-3 options with tradeoffs, not just one.
- After completing a task, give a one-line summary of what changed and what to verify.

## Context Management
- When I say "checkpoint," write current progress and next steps to `docs/checkpoint.md`.
- Before any large refactor, read the relevant test files first to understand expected behavior.
- Use sub-agents for research tasks. Keep the main session focused on implementation.

## Environment: Cloudflare WARP VPN
- This machine runs Cloudflare WARP (1.1.1.1), which intercepts TLS and installs its own root CA.
- When any tool fails with a TLS/SSL certificate error, read `.claude/rules/tls-troubleshooting.md` and auto-fix using the combined CA bundle at `~/.cloudflare-certs/combined-ca-bundle.pem`.
- NEVER disable TLS verification (NODE_TLS_REJECT_UNAUTHORIZED=0, --insecure, sslVerify=false). Always use the proper CA bundle fix.
- Run `/fix-certs` to diagnose and repair certificate issues on demand.
