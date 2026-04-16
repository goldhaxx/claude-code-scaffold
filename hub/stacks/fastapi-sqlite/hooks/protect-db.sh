#!/usr/bin/env bash
# protect-db.sh — PreToolUse hook for Bash
# Blocks direct SQL mutations (INSERT/UPDATE/DELETE/DROP/ALTER/REPLACE)
# against .db files or via sqlite3 invocations.
# Enforces the API-first data access principle: all mutations go through
# FastAPI endpoints, never direct SQL.
#
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# --- Context check: is this a database command? ---
# Must involve sqlite3 or a .db file to be relevant.
# This prevents false positives on grep "UPDATE", echo "DELETE", etc.
if [[ ! "$COMMAND" =~ sqlite3 ]] && [[ ! "$COMMAND" =~ \.db ]]; then
  exit 0
fi

# --- Allow bypass with API_BYPASS=1 ---
if [[ "$COMMAND" =~ API_BYPASS=1 ]]; then
  echo "WARNING: API-first bypass active. Direct SQL mutation allowed by user override." >&2
  exit 0
fi

# --- Allow read-only operations ---
# SELECT, PRAGMA, .schema, .tables, .headers, .mode are read-only
# CREATE TABLE is schema setup, not data mutation
# Piped schema files (cat schema.sql | sqlite3) are infrastructure

# Check for piped schema setup: cat *.sql | sqlite3
if [[ "$COMMAND" =~ \.sql[[:space:]]*\|[[:space:]]*sqlite3 ]]; then
  exit 0
fi

# Check for mutation keywords (case-insensitive)
UPPER_CMD=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

# Strip CREATE TABLE/CREATE INDEX statements before checking for mutations
STRIPPED_CMD=$(echo "$UPPER_CMD" | sed -E 's/CREATE[[:space:]]+(TABLE|INDEX|VIEW|TRIGGER)[[:space:]]+[^;]*(;|$)//g')

# Check for mutation keywords in the remaining command
if echo "$STRIPPED_CMD" | grep -qE '\b(INSERT|UPDATE|DELETE|DROP|ALTER|REPLACE)\b'; then
  echo "BLOCKED: Direct SQL mutation detected. Use the API instead." >&2
  echo "  All data mutations must go through API endpoints." >&2
  echo "  If the API lacks this functionality, enhance it first." >&2
  echo "  Emergency bypass: prefix with API_BYPASS=1" >&2
  exit 2
fi

exit 0
