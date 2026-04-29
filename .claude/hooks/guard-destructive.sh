#!/usr/bin/env bash
# guard-destructive.sh — PreToolUse hook for Bash
# Blocks destructive git operations: hard reset, force branch delete, remote delete, clean.
# Exit 2 = hard block (stderr becomes Claude's feedback)
# Exit 0 = allow

# @manifest
# purpose: PreToolUse Bash gate that blocks the canonical irreversible-or-catastrophic shell footguns — `git reset --hard`, `git branch -D`, `git push --delete`, `git clean -f`, `chmod 777|666|000`, `rm` with combined recursive+force flags (cluster `-rf` or both long forms `--recursive --force`), and `find` with `-delete`/`-exec`/`-execdir`/`-okdir`. Path-agnostic shape gates: the destructive verb shape is the catastrophic footgun regardless of target. ALLOW_DESTRUCTIVE=1 prefix bypass for deliberate use; BTS-151 carve-out for `git commit` so destructive-shape strings in commit messages don't trip the gate.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PreToolUse contract
# output: exit-codes 0 allow / 2 block (per matched gate)
# output: stderr on block: BLOCKED reason + bypass hint
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-block
# failure-mode: hard-reset-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=ALLOW_DESTRUCTIVE=1-prefix
# failure-mode: force-branch-delete-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=branch--d-for-merged-or-bypass
# failure-mode: remote-delete-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=ALLOW_DESTRUCTIVE=1-prefix
# failure-mode: clean-force-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=ALLOW_DESTRUCTIVE=1-prefix
# failure-mode: chmod-broad-mode-blocked | exit=2 | visible=stderr-BLOCKED-with-mode-and-bypass | mitigation=use-symbolic-mode-or-bypass
# failure-mode: rm-recursive-force-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=split-flags-or-bypass
# failure-mode: find-traverse-mutate-blocked | exit=2 | visible=stderr-BLOCKED-with-bypass-hint | mitigation=ALLOW_DESTRUCTIVE=1-prefix
# contract: never-blocks-non-matching-commands
# contract: env-prefix-bypass-via-ALLOW_DESTRUCTIVE=1
# contract: git-commit-carve-out-prevents-narrative-false-positives
# anchor: BTS-151 (git-commit carve-out)
# anchor: BTS-155 (find traverse-and-mutate gate)
# anchor: BTS-156 (rm recursive-force shape gate)
# anchor: BTS-157 (sort -o gate — handled in guard-workspace)
# anchor: BTS-202 (rm cluster-vs-cross-line refinement)
# anchor: BTS-251 (manifest seed)

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
  # @failure-mode: hard-reset-blocked
  # @side-effect: writes-stderr-on-block
  echo "BLOCKED: git reset --hard discards commits and changes." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git reset --hard ..." >&2
  exit 2
fi

# Block git branch -D (force delete, uppercase D only)
if [[ "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D[[:space:]] || "$COMMAND" =~ git[[:space:]]+branch[[:space:]]+-D$ ]]; then
  # @failure-mode: force-branch-delete-blocked
  echo "BLOCKED: git branch -D force-deletes unmerged branches." >&2
  echo "  Use git branch -d for merged branches, or bypass: ALLOW_DESTRUCTIVE=1 git branch -D ..." >&2
  exit 2
fi

# Block git push origin --delete
if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+--delete ]]; then
  # @failure-mode: remote-delete-blocked
  echo "BLOCKED: git push --delete removes remote branches." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git push origin --delete ..." >&2
  exit 2
fi

# Block git clean -f (any variant with -f flag)
if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  # @failure-mode: clean-force-blocked
  echo "BLOCKED: git clean -f permanently deletes untracked files." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 git clean -f ..." >&2
  exit 2
fi

# Block destructive chmod numeric modes: 777/666 (world-writable), 000 (fully locked).
# -R variants included. Symbolic modes (a+w etc) intentionally allowed — the hook
# focuses on the catastrophic numeric-mode footguns.
if [[ "$COMMAND" =~ chmod[[:space:]]+(-R[[:space:]]+)?(777|666|000)([[:space:]]|$) ]]; then
  mode="${BASH_REMATCH[2]}"
  # @failure-mode: chmod-broad-mode-blocked
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
# BTS-202: detect rm-rf footgun via combined flag cluster (r AND f in
# the SAME flag token) OR both --recursive AND --force long forms on
# the line. Replaces the prior cross-line scan that fired when ANY
# unrelated -r flag (e.g., `jq -r`) appeared alongside ANY unrelated
# -f flag (e.g., `rm -f` force-only). Trade-off: split short-form
# `rm -r -f` is no longer caught — operators using deliberate split
# flags can prefix ALLOW_DESTRUCTIVE=1; canonical `rm -rf` still gated.
rm_combined_cluster='(^|[[:space:]])-[a-zA-Z]*([rR][a-zA-Z]*[fF]|[fF][a-zA-Z]*[rR])[a-zA-Z]*([[:space:]]|=|$)'
rm_long_recursive='(^|[[:space:]])--recursive([[:space:]]|=|$)'
rm_long_force='(^|[[:space:]])--force([[:space:]]|=|$)'
if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]] ]]; then
  trip=0
  if [[ "$COMMAND" =~ $rm_combined_cluster ]]; then
    trip=1
  elif [[ "$COMMAND" =~ $rm_long_recursive ]] && [[ "$COMMAND" =~ $rm_long_force ]]; then
    trip=1
  fi
  if (( trip == 1 )); then
    # @failure-mode: rm-recursive-force-blocked
    echo "BLOCKED: rm with recursive AND force flags deletes without prompt." >&2
    echo "  To bypass: ALLOW_DESTRUCTIVE=1 rm ..." >&2
    exit 2
  fi
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
  # @failure-mode: find-traverse-mutate-blocked
  echo "BLOCKED: find with -delete or -exec/-execdir/-okdir traverses then mutates." >&2
  echo "  To bypass: ALLOW_DESTRUCTIVE=1 find ..." >&2
  exit 2
fi

exit 0
