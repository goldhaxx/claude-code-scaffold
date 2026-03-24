# Hooks Reference

> Read when: Adding, modifying, or debugging hooks in `.claude/settings.json` or `.claude/hooks/`.

## What Hooks Are

Hooks are shell commands that Claude Code runs automatically at lifecycle events — completely outside Claude's reasoning loop. They cost zero context tokens.

**The principle:** If the rule is binary (always/never) and the check is computable, it's a hook, not a rule.

## Hook Types

| Type | How it works | Best for |
|------|-------------|----------|
| `command` | Shell script receives JSON on stdin, exit code controls action | File validation, formatting, security blocks, notifications |
| `http` | POST to a URL with event JSON body | Audit logging, team services, compliance |
| `prompt` | Single-turn Claude evaluation (Haiku by default) | Quick yes/no judgment calls |
| `agent` | Full subagent with Read/Grep/Glob access | Complex verification (test suites, codebase checks) |

## Events & Matchers

| Event | When it fires | Matcher filters on | Common matchers |
|-------|---------------|-------------------|-----------------|
| `PreToolUse` | Before tool executes | Tool name | `Write\|Edit\|MultiEdit`, `Bash` |
| `PostToolUse` | After tool succeeds | Tool name | `Write\|Edit\|MultiEdit`, `Bash` |
| `Stop` | Claude finishes responding | (none) | Always fires |
| `Notification` | Claude needs user input | Notification type | `permission_prompt` |
| `SessionStart` | Session begins | How it started | `startup`, `resume` |

## Exit Code Protocol (Command Hooks)

| Exit Code | Meaning | Behavior |
|-----------|---------|----------|
| **0** | Success | Action proceeds. Optional JSON on stdout for fine-grained control. |
| **2** | Block | Action prevented. Stderr becomes feedback to Claude. |
| **Other** | Non-blocking error | Action proceeds. Stderr logged in verbose mode only. |

**Critical:** Only exit 2 blocks an action. Exit 1 logs a warning but does NOT prevent the operation.

## JSON Input (stdin)

Every hook receives JSON on stdin with common fields:

```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "hook_event_name": "PreToolUse",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "content": "..."
  }
}
```

PostToolUse also includes `tool_output`. PostToolUseFailure includes `tool_error`.

## JSON Output (stdout, optional)

Exit 0 with JSON for fine-grained control:

```json
{
  "decision": "allow|deny|block",
  "reason": "Human-readable explanation",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask"
  }
}
```

## settings.json Schema

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-on-write.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Key fields:**
- `matcher`: Regex filtering which tool invocations trigger the hook. Empty string = everything.
- `type`: `command`, `http`, `prompt`, or `agent`
- `timeout`: Seconds before timeout (default: 10s command/http/prompt, 60s agent)
- `async`: Run in background without blocking (command hooks only)
- `statusMessage`: Custom spinner text while hook runs

## Writing Hook Scripts

### Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Your logic here...

exit 0  # allow
```

### Conventions

1. Scripts live in `.claude/hooks/` with descriptive names
2. Must be executable: `chmod +x .claude/hooks/my-hook.sh`
3. Reference via `$CLAUDE_PROJECT_DIR`: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/my-hook.sh`
4. Use `jq` to parse stdin JSON (require jq at top if needed)
5. Write block reasons to stderr, not stdout
6. Always exit 0 at the end (explicit allow) — don't fall through

### Anti-patterns

- **Inline shell in settings.json** — Hard to read, test, or version. Use script files.
- **Exit 1 for blocking** — Only exit 2 blocks. Exit 1 is a non-blocking warning.
- **Heavy processing in hooks** — Keep under 10 seconds. Use `async: true` for slow operations.
- **Suppressing errors with `|| true` on everything** — Catch specific errors, not all.

## Scaffold's Active Hooks

| Hook | Event | Script | What it does |
|------|-------|--------|-------------|
| File protection | PreToolUse (Write\|Edit\|MultiEdit) | `protect-files.sh` | Blocks writes to `.env`, credentials, `scaffold-framework.md`, generated dirs |
| Auto-format | PostToolUse (Write\|Edit\|MultiEdit) | `format-on-write.sh` | Runs project formatter (uncomment for your stack) |

## When to Add a Hook vs a Rule

| Situation | Use |
|-----------|-----|
| "Never write to .env files" | Hook (binary check on file path) |
| "Always format code after writing" | Hook (deterministic formatter call) |
| "Follow existing code patterns" | Rule (requires semantic understanding) |
| "Don't add unnecessary dependencies" | Rule (requires judgment about "unnecessary") |
| "Run tests after every file change" | Hook (deterministic test runner) |
| "Write descriptive test names" | Rule (requires understanding intent) |

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
