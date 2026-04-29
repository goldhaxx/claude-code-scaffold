#!/usr/bin/env bash
# permission-request-suppress-redundant.sh — PermissionRequest hook
# BTS-150: when Claude Code prompts for a Bash exact-form that's already
# covered by a broader allow pattern in .claude/settings.json, auto-allow
# with destination=session so the redundant exact-form never persists to
# .claude/settings.local.json. Closes the upstream source of the drift
# that BTS-144's promote-review classifier and BTS-149's /permissions-review
# clean up periodically.

# @manifest
# purpose: PermissionRequest hook (BTS-150) that intercepts redundant Bash exact-form permission prompts. When the requested command matches a broader allow pattern already in `.claude/settings.json` (token-prefix `Bash(<prefix>:*)`, path-prefix `Bash(<dir>/:*)`, or exact `Bash(<exact>)`), emits a `hookSpecificOutput` JSON with `decision.behavior=allow` + `destination=session` so the redundant rule never persists to `.claude/settings.local.json`. Closes the upstream of the drift that `/permissions-review` (BTS-149) cleans up periodically.
# input: stdin JSON envelope from Claude Code's PermissionRequest contract `{tool_name, tool_input:{command}, ...}`
# input: env CLAUDE_PROJECT_DIR (falls back to PWD for tests)
# input: file `.claude/settings.json` (`.permissions.allow[]` Bash patterns)
# output: stdout: `hookSpecificOutput` JSON envelope on intercept (allow + session-scoped rule)
# output: stdout: empty on passthrough (Claude Code's default prompt flow)
# output: exit-code 0 always (the decision rides in stdout JSON, not exit code)
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stdout-hook-decision
# failure-mode: never-fails | exit=0 | visible=passthrough-on-non-Bash-or-no-command-or-no-settings-or-no-match | mitigation=passthrough-is-the-default
# contract: never-blocks
# contract: passthrough-on-non-Bash-tool
# contract: passthrough-when-no-pattern-matches
# contract: session-scoped-rule-evaporates-at-session-end
# anchor: BTS-150 (origin)
# anchor: BTS-251 (manifest seed)
#
# Hook contract: receives a JSON envelope on stdin (tool_name, tool_input,
# permission_suggestions, etc.); emits a hookSpecificOutput JSON on stdout
# when it wants to intercept; emits nothing (exit 0) when it wants to
# passthrough to Claude Code's default prompt flow.
#
# Matching logic:
#   - Bash(<prefix>:*)  matches command iff command == <prefix> OR
#                       command starts with "<prefix> " OR
#                       <prefix> ends in '/' AND command starts with <prefix>
#                       (path-prefix style, e.g., .ccanvil/scripts/:*)
#   - Bash(<exact>)     matches command iff command == <exact>
#
# Tools other than Bash are passthrough (out of scope for this iteration).
# A PermissionRequest payload with no command field is also passthrough.
#
# Inputs (env):
#   CLAUDE_PROJECT_DIR — set by Claude Code; falls back to PWD for tests.
#
# Exit 0 always — the hook is non-blocking; the decision rides in stdout
# JSON when intercepting.

set -euo pipefail

input="$(cat)"

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

project_root="${CLAUDE_PROJECT_DIR:-$PWD}"
settings="$project_root/.claude/settings.json"
[[ ! -f "$settings" ]] && exit 0

# Extract Bash(...) entries from permissions.allow. jq handles missing
# keys deterministically — empty output if .permissions.allow is absent.
patterns=$(jq -r '.permissions.allow[]? | select(type == "string" and startswith("Bash(") and endswith(")"))' "$settings" 2>/dev/null || true)
[[ -z "$patterns" ]] && exit 0

matched=false
while IFS= read -r pat; do
  [[ -z "$pat" ]] && continue
  inner="${pat#Bash(}"
  inner="${inner%)}"

  if [[ "$inner" == *:\* ]]; then
    prefix="${inner%:\*}"
    # Token-prefix match: command equals prefix, or starts with prefix+space.
    if [[ "$cmd" == "$prefix" ]] || [[ "$cmd" == "$prefix "* ]]; then
      matched=true
      break
    fi
    # Path-prefix match: prefix ends in '/' and command starts with prefix.
    if [[ "$prefix" == */ ]] && [[ "$cmd" == "$prefix"* ]]; then
      matched=true
      break
    fi
  else
    # Exact-form match.
    if [[ "$cmd" == "$inner" ]]; then
      matched=true
      break
    fi
  fi
done <<< "$patterns"

$matched || exit 0

# Emit allow + session-scoped rule. The rule's ruleContent is the exact
# command form so any subsequent identical call in this session is matched
# by the in-memory rule and skips the prompt. session-scope means the rule
# evaporates at session end; nothing reaches settings.local.json.
# @side-effect: writes-stdout-hook-decision
# @failure-mode: never-fails
jq -n --arg cmd "$cmd" '{
  hookSpecificOutput: {
    hookEventName: "PermissionRequest",
    decision: {
      behavior: "allow",
      updatedPermissions: [
        {
          type: "addRules",
          rules: [{toolName: "Bash", ruleContent: $cmd}],
          behavior: "allow",
          destination: "session"
        }
      ]
    }
  }
}'
exit 0
