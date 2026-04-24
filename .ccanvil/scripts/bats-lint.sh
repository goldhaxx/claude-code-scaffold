#!/usr/bin/env bash
# BTS-127 — bats-lint.sh
#
# Flag bats tests with ≥2 jq -e assertions and no `set -e` at the top of the
# block. In bats, a test passes iff the last statement returns 0, so sequential
# jq -e assertions leak failures silently. See .claude/rules/tdd.md for the
# convention; this script enforces it.
#
# Usage:
#   bats-lint.sh <dir-or-file>
#
# Exit codes:
#   0 — no violations
#   1 — one or more leaky blocks found (file:line printed to stderr)
#   2 — usage error

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "ERROR: missing target" >&2
  echo "" >&2
  echo "Usage:" >&2
  echo "  bats-lint.sh <dir-or-file>" >&2
  exit 2
fi

TARGET="$1"

if [[ ! -e "$TARGET" ]]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 2
fi

violations=0

lint_file() {
  local file="$1"
  local in_block=0 depth=0 jq_count=0 set_e_seen=0 block_line=0
  local in_heredoc=0 heredoc_delim=""
  local line_no=0 line opens closes trimmed

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    # Heredoc body: skip all per-line analysis until the end delimiter.
    # The delimiter line is either exactly $heredoc_delim, or (for `<<-`) any
    # amount of leading tabs followed by the delimiter.
    if (( in_heredoc )); then
      trimmed="${line#"${line%%[! 	]*}"}"
      if [[ "$trimmed" == "$heredoc_delim" ]]; then
        in_heredoc=0
      fi
      continue
    fi

    if (( in_block == 0 )); then
      if [[ "$line" =~ ^@test.*\{ ]]; then
        in_block=1
        jq_count=0
        set_e_seen=0
        block_line=$line_no
        opens=$(printf '%s' "$line" | tr -cd '{' | wc -c | tr -d ' ')
        closes=$(printf '%s' "$line" | tr -cd '}' | wc -c | tr -d ' ')
        depth=$((opens - closes))
        if (( depth <= 0 )); then
          in_block=0
        fi
      fi
      continue
    fi

    # Detect a heredoc opening on this line. We still do brace counting on
    # this line (the `<<` line may itself contain block-level braces), but we
    # skip jq/set-e detection from the next line through the end delimiter.
    if [[ "$line" =~ \<\<-?[[:space:]]*[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]? ]]; then
      heredoc_delim="${BASH_REMATCH[1]}"
      in_heredoc=1
    fi

    # `run jq -e` captures exit code into $status and cannot leak — skip.
    if [[ "$line" =~ run[[:space:]]+.*jq[[:space:]]+-e ]]; then
      :
    elif [[ "$line" =~ jq[[:space:]]+-e ]]; then
      jq_count=$((jq_count + 1))
    elif (( jq_count == 0 )) && [[ "$line" =~ ^[[:space:]]*set[[:space:]]+-e ]]; then
      set_e_seen=1
    fi

    opens=$(printf '%s' "$line" | tr -cd '{' | wc -c | tr -d ' ')
    closes=$(printf '%s' "$line" | tr -cd '}' | wc -c | tr -d ' ')
    depth=$((depth + opens - closes))

    if (( depth <= 0 )); then
      if (( jq_count >= 2 && set_e_seen == 0 )); then
        printf '%s:%d: leaky jq -e pattern (%d jq -e calls, no set -e)\n' \
          "$file" "$block_line" "$jq_count" >&2
        violations=$((violations + 1))
      fi
      in_block=0
      depth=0
      jq_count=0
      set_e_seen=0
      in_heredoc=0
      heredoc_delim=""
    fi
  done < "$file"
}

if [[ -d "$TARGET" ]]; then
  files_list=$(find "$TARGET" -name '*.bats' -type f 2>/dev/null | sort)
else
  files_list="$TARGET"
fi

if [[ -n "$files_list" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    lint_file "$file"
  done <<< "$files_list"
fi

if (( violations > 0 )); then
  exit 1
fi
exit 0
