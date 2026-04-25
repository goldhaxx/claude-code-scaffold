#!/usr/bin/env bash
# guard-workspace.sh — PreToolUse hook for Bash
# Blocks file-mutation verbs (rm, cp, mv, chmod, chown, bash) when any
# absolute or tilde-prefixed path argument falls outside the workspace
# ($HOME/projects/) or whitelisted system temp dirs.
#
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow
#
# Known limitations:
#   - Variable indirection (rm $SOMEPATH) — token does not start with /
#     or ~/, so it bypasses detection. Bash expands at runtime.
#   - Relative-path traversal (../../etc/x) — bypasses absolute-path check.
#   - Subshell expansion ($(cmd)) — literal substrings inside $(...) ARE
#     scanned, so most cases (like rm $(find /)) still trip on the literal /.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Allow bypass with ALLOW_OUTSIDE_WORKSPACE=1
if [[ "$COMMAND" =~ ALLOW_OUTSIDE_WORKSPACE=1 ]]; then
  exit 0
fi

# Only enforce for commands containing a gated file-mutation verb.
# Word-boundary match: verb must be at start, or after whitespace/;/|/&.
if [[ ! "$COMMAND" =~ (^|[[:space:]\;\|\&])(rm|cp|mv|chmod|chown|bash)([[:space:]]|$) ]]; then
  exit 0
fi

# Whitelisted absolute-path prefixes
WORKSPACE="$HOME/projects"
ALLOWED_ABS=(
  "$WORKSPACE/"
  "/tmp/"
  "/private/tmp/"
  "/var/folders/"
  "/private/var/folders/"
  "/dev/null"
  "/dev/stdin"
  "/dev/stdout"
  "/dev/stderr"
)

# Whitelisted tilde-path prefixes (literal ~/ in command strings)
ALLOWED_TILDE=(
  "~/projects/"
)

# Tokenize: strip quotes, then word-split on whitespace.
# This makes `bash -c "rm /etc/foo"` extract /etc/foo as a token.
NORMALIZED=$(echo "$COMMAND" | tr -d '"' | tr -d "'")

violation=""
for token in $NORMALIZED; do
  case "$token" in
    /?*)
      # Absolute path (≥1 char after the slash — bare `/` is ignored)
      ok=false
      for prefix in "${ALLOWED_ABS[@]}"; do
        case "$token" in
          "$prefix"*|"$prefix")
            ok=true
            break
            ;;
        esac
      done
      if ! $ok; then
        violation="$token"
        break
      fi
      ;;
    \~/*)
      # Tilde-prefixed path (literal in command string)
      ok=false
      for prefix in "${ALLOWED_TILDE[@]}"; do
        case "$token" in
          "$prefix"*)
            ok=true
            break
            ;;
        esac
      done
      if ! $ok; then
        violation="$token"
        break
      fi
      ;;
  esac
done

if [[ -n "$violation" ]]; then
  echo "BLOCKED: path '$violation' is outside the workspace ($WORKSPACE/)." >&2
  echo "  To bypass: ALLOW_OUTSIDE_WORKSPACE=1 <command>" >&2
  exit 2
fi

exit 0
