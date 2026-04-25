#!/usr/bin/env bash
# guard-destructive.sh — PreToolUse hook for Bash
# Blocks destructive git operations: hard reset, force branch delete, remote delete, clean.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Allow bypass with ALLOW_DESTRUCTIVE=1
if [[ "$COMMAND" =~ ALLOW_DESTRUCTIVE=1 ]]; then
  exit 0
fi

# BTS-151: skip git commit. Commit messages routinely mention destructive-
# shape strings (e.g. "fix the rm -rf gate") that our regex matches
# anywhere in the literal command. False positives are constant; the only
# real bypass workaround is `git commit -F /tmp/msg.txt`. Trade-off: a
# chained command like `git commit -m "x" && rm -rf /` would skip the
# destructive scan. Operationally rare (tracked in spec out-of-scope).
#
# Env-prefix value can be unquoted (no spaces), double-quoted, or single-
# quoted — covers GIT_AUTHOR_NAME="Foo Bar" / GIT_COMMITTER_DATE="..."
# in addition to plain LANG=en_US.
if [[ "$COMMAND" =~ ^([A-Z_][A-Z0-9_]*=([^[:space:]\"\']*|\"[^\"]*\"|\'[^\']*\')[[:space:]]+)*git[[:space:]]+commit($|[[:space:]]) ]]; then
  exit 0
fi

# Block git reset --hard
if [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  echo "BLOCKED: git reset --hard discards commits and changes." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git reset --hard ..." >&2
  exit 2
fi

# Block git branch -D (force delete, uppercase D only)
if [[ "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D[[:space:]] || "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D$ ]]; then
  echo "BLOCKED: git branch -D force-deletes unmerged branches." >&2
  echo "  Use git branch -d for merged branches, or bypass: ALLOW_DESTRUCTIVE=1 git branch -D ..." >&2
  exit 2
fi

# Block git push origin --delete
if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+--delete ]]; then
  echo "BLOCKED: git push --delete removes remote branches." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git push origin --delete ..." >&2
  exit 2
fi

# Block git clean -f (any variant with -f flag)
if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  echo "BLOCKED: git clean -f permanently deletes untracked files." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git clean -f ..." >&2
  exit 2
fi

# Block destructive chmod numeric modes: 777/666 (world-writable), 000 (fully locked).
# -R variants included. Symbolic modes (a+w etc) intentionally allowed — the hook
# focuses on the catastrophic numeric-mode footguns.
if [[ "$COMMAND" =~ chmod[[:space:]]+(-R[[:space:]]+)?(777|666|000)([[:space:]]|$) ]]; then
  mode="${BASH_REMATCH[2]}"
  echo "BLOCKED: chmod $mode grants or denies world-permissions broadly." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 chmod $mode ..." >&2
  exit 2
fi

# Block rm with BOTH recursive (-r/-R/--recursive) AND force (-f/--force) flags.
# Path-agnostic: the recursive-force shape is the catastrophic footgun, regardless
# of target. Recursive-only (-r) and force-only (-f) are allowed — only the
# combination triggers the gate. (BTS-156)
#
# Detection is shape-based: word-anchor `rm` to avoid arm/form false positives,
# then check independently for ANY recursive flag and ANY force flag. This
# catches all combos: cluster `-rf`, split `-r -f`, mixed `-r --force`, and
# long-form `--recursive --force` (any order).
#
# Known gap: indirect invocations (`find ... | xargs rm -rf`, `sh -c 'rm -rf …'`
# from a here-string, etc.) reach rm via a wrapper. The hook only sees the
# literal command string; a wrapper-composed rm is not visible here. Tracked
# alongside BTS-155 (find -delete/-exec).
rm_recursive_re='(^|[[:space:]])(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|=|$)'
rm_force_re='(^|[[:space:]])(-[a-zA-Z]*[fF][a-zA-Z]*|--force)([[:space:]]|=|$)'
if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]] ]] \
   && [[ "$COMMAND" =~ $rm_recursive_re ]] \
   && [[ "$COMMAND" =~ $rm_force_re ]]; then
  echo "BLOCKED: rm with recursive AND force flags deletes without prompt." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 rm ..." >&2
  exit 2
fi

# Block find with -delete or -exec/-execdir/-okdir. Path-agnostic shape gate:
# `find` reaches mutation verbs through these embedded operators, bypassing the
# leading-verb regex that catches bare rm/cp/mv/chmod/chown. The traverse-and-
# mutate shape is the catastrophic footgun, regardless of target. Workspace-
# fence enforcement on out-of-workspace traversal is handled by guard-workspace
# (find added to its verb regex). (BTS-155)
#
# Word-anchor `find` to avoid xfind/findutils-substring false positives.
# The action-operator boundary uses plain whitespace; quoted name patterns
# like `-name '-delete'` are protected by the space *after* the closing
# quote, not by quote chars in the boundary class.
if [[ "$COMMAND" =~ (^|[[:space:]\;\|\&])find[[:space:]] ]] \
   && [[ "$COMMAND" =~ (^|[[:space:]])(-delete|-exec|-execdir|-okdir)([[:space:]]|$) ]]; then
  echo "BLOCKED: find with -delete or -exec/-execdir/-okdir traverses then mutates." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 find ..." >&2
  exit 2
fi

exit 0
