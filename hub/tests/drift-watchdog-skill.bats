#!/usr/bin/env bats
# BTS-21 — drift-watchdog skill + agent drift-guards.
#
# These tests assert structural properties of the SKILL.md and agent prose.
# They guard against regression of the orchestration contract — what the skill
# does, which substrates it talks to, what it explicitly avoids.

bats_require_minimum_version 1.5.0

REPO_ROOT="$BATS_TEST_DIRNAME/../.."
SKILL="$REPO_ROOT/.claude/skills/drift-watchdog/SKILL.md"
AGENT="$REPO_ROOT/.claude/agents/drift-analyst.md"

# =========================================================================
# AC-3: drift-analyst agent
# =========================================================================

@test "AC-3: drift-analyst agent file exists" {
  [ -f "$AGENT" ]
}

@test "AC-3: drift-analyst frontmatter has name=drift-analyst" {
  set -e
  grep -q '^name: drift-analyst$' "$AGENT"
}

@test "AC-3: drift-analyst tools list is exactly Read, Grep, Glob, Bash(git log:*)" {
  set -e
  # Extract the tools list — lines starting with `  - ` between `tools:` and `model:`.
  local tools
  tools=$(awk '/^tools:/{flag=1;next} /^model:/{flag=0} flag && /^[[:space:]]*-[[:space:]]/' "$AGENT" \
    | sed 's/^[[:space:]]*-[[:space:]]*//')
  [ "$(echo "$tools" | grep -c .)" -eq 4 ]
  echo "$tools" | grep -qx 'Read'
  echo "$tools" | grep -qx 'Grep'
  echo "$tools" | grep -qx 'Glob'
  echo "$tools" | grep -qx 'Bash(git log:\*)'
}

@test "AC-3: drift-analyst model is haiku (cheap synthesis is sufficient)" {
  set -e
  grep -q '^model: haiku$' "$AGENT"
}

# =========================================================================
# AC-4: skill orchestration contract
# =========================================================================

@test "AC-4: skill exists" {
  [ -f "$SKILL" ]
}

@test "AC-4: skill mentions drift-watchdog-list" {
  grep -q 'drift-watchdog-list' "$SKILL"
}

@test "AC-4: skill mentions drift-analyst" {
  grep -q 'drift-analyst' "$SKILL"
}

@test "AC-4: skill references linear-query.sh save-issue (or equivalent http path)" {
  # The resolver-eval shape (linear-query.sh save-issue is what the resolver
  # emits for idea.add); accept either literal mention or the eval pattern.
  grep -qE 'linear-query\.sh save-issue|operations\.sh resolve idea\.add' "$SKILL"
}

@test "AC-4: skill includes the resolver eval pattern" {
  grep -qF 'eval "$(echo "$RESOLUTION" | jq -r' "$SKILL"
}

# =========================================================================
# AC-5: idempotency drift-guard
# =========================================================================

@test "AC-5: skill describes idempotency check via drift_key match against existing issues" {
  set -e
  grep -q 'drift_key' "$SKILL"
  grep -qiE 'idempoten|skip|dup' "$SKILL"
}

# =========================================================================
# AC-7: pending-log fallback
# =========================================================================

@test "AC-7: skill mentions idea-pending-append fallback" {
  grep -qF 'idea-pending-append' "$SKILL"
}

@test "AC-7: skill does NOT use wc -l (count via idea-pending-validate)" {
  ! grep -qE '\bwc -l\b' "$SKILL"
}

# =========================================================================
# AC-8: substrate purity (no MCP)
# =========================================================================

@test "AC-8: skill does NOT call mcp__claude_ai_Linear__save_issue directly" {
  ! grep -qF 'mcp__claude_ai_Linear__save_issue' "$SKILL"
}

@test "AC-8: skill does NOT call mcp__claude_ai_Linear__list_issues directly" {
  ! grep -qF 'mcp__claude_ai_Linear__list_issues' "$SKILL"
}

# =========================================================================
# AC-10: drift-watchdog label
# =========================================================================

@test "AC-10: skill includes drift-watchdog in --labels for create dispatch" {
  # linear-query.sh save-issue takes --labels (plural, comma-separated). The
  # resolver default is `--labels 'idea'`; the skill must override with
  # `--labels 'idea,drift-watchdog'` so both labels stick.
  grep -qF -- "--labels 'idea,drift-watchdog'" "$SKILL"
}

@test "AC-10: skill filters existing issues by drift-watchdog label" {
  grep -qF '"drift-watchdog"' "$SKILL"
}

# =========================================================================
# BTS-199: skill references the launchd-install wrapper
# =========================================================================

@test "BTS-199: skill references drift-watchdog-launchd-install wrapper" {
  grep -qF 'drift-watchdog-launchd-install' "$SKILL"
}

# =========================================================================
# BTS-200: per-create self-verification subsection
# =========================================================================

@test "BTS-200 AC-1: skill has Verify create landed subsection" {
  grep -qF 'Verify create landed' "$SKILL"
}

@test "BTS-200 AC-2: skill prescribes linear-query.sh get-issue verification" {
  grep -qF 'linear-query.sh get-issue' "$SKILL"
}

@test "BTS-200 AC-3: skill asserts drift-watchdog label is present in returned issue" {
  grep -qF '.labels | index("drift-watchdog")' "$SKILL"
}

@test "BTS-200 AC-4: skill queues failed verifications via idea-pending-append --op add" {
  grep -qF 'idea-pending-append --op add' "$SKILL"
}

@test "BTS-200 AC-5: skill anchors on BTS-200 and BTS-21" {
  set -e
  grep -qF 'BTS-200' "$SKILL"
  grep -qF 'BTS-21' "$SKILL"
}

@test "BTS-200 AC-6: skill explicitly says do not trust save-issue stdout — verify externally" {
  grep -qiE 'verify externally|do NOT.*save-issue|do not.*save-issue' "$SKILL"
}

@test "BTS-200 AC-7: skill mentions network-error fallback (queue to pending)" {
  grep -qiE 'network|queue to pending|pending log' "$SKILL"
}
