#!/usr/bin/env bash
# guard-workspace.sh — PreToolUse hook for Bash
# Blocks file-mutation verbs (rm, cp, mv, chmod, chown, bash, find, sort)
# AND read verbs with exfiltration risk (cat) when any absolute or
# tilde-prefixed path argument falls outside the workspace
# ($HOME/projects/) or whitelisted system temp dirs.
#
# `sort` is gated because of `-o FILE` (writer flag) and shell-redirect
# targets (BTS-157). Path-token iteration handles both incidentally;
# no special-casing for -o needed.
# `cat` is gated for read-side exfiltration: bash `cat ~/.ssh/id_*` etc.
# would otherwise pull sensitive files into Claude's context with no
# prompt. The bash route is intentionally tighter than the Read tool
# (BTS-153). ALLOW_OUTSIDE_WORKSPACE=1 bypass.
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
#   - Aliased / case-variant verbs (gsort, gfind on macOS Homebrew; Sort
#     capitalized; bat as a cat replacement) — the alternation is literal
#     and case-sensitive. Add to the verb list if/when they become
#     operationally relevant.
#   - Intentional friction: cat blocks force operators to either prefix
#     ALLOW_OUTSIDE_WORKSPACE=1 for ad-hoc system reads, or pivot to the
#     Read tool. Acceptable — read-tool asymmetry tracked via BTS-150.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Allow bypass with ALLOW_OUTSIDE_WORKSPACE=1
if [[ "$COMMAND" =~ ALLOW_OUTSIDE_WORKSPACE=1 ]]; then
  exit 0
fi

# BTS-151: skip git commit. The verb-leading regex below matches gated
# verbs anywhere in the command, so a commit message body that mentions
# `bash`/`cat`/etc activates the path scan, which then catches any
# path-shaped narrative string (`/stasis`, `/tmp/...`). Constant false
# positives; the workaround was always `commit -F` to a tmpfile. Same
# trade-off as guard-destructive: chained commands bypass.
#
# Env-prefix value can be unquoted (no spaces), double-quoted, or single-
# quoted — covers GIT_AUTHOR_NAME="Foo Bar" / GIT_COMMITTER_DATE="..."
# in addition to plain LANG=en_US.
if [[ "$COMMAND" =~ ^([A-Z_][A-Z0-9_]*=([^[:space:]\"\']*|\"[^\"]*\"|\'[^\']*\')[[:space:]]+)*git[[:space:]]+commit($|[[:space:]]) ]]; then
  exit 0
fi

# Only enforce for commands containing a gated file-mutation verb.
# Word-boundary match: verb must be at start, or after whitespace/;/|/&.
if [[ ! "$COMMAND" =~ (^|[[:space:]\;\|\&])(rm|cp|mv|chmod|chown|bash|find|sort|cat)([[:space:]]|$) ]]; then
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
