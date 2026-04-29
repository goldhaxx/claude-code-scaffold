#!/usr/bin/env bash
# guard-workspace.sh — PreToolUse hook for Bash
# Blocks file-mutation verbs (rm, cp, mv, chmod, chown, bash, find, sort)
# AND read verbs with exfiltration risk (cat) when any absolute or
# tilde-prefixed path argument falls outside the workspace
# ($HOME/projects/) or whitelisted system temp dirs.

# @manifest
# purpose: PreToolUse Bash workspace fence — block file-mutation verbs (rm, cp, mv, chmod, chown, bash, find, sort) and the exfiltration-risk read verb (cat) when any absolute or tilde-prefixed path argument falls outside the workspace ($HOME/projects/) or the whitelisted system temp dirs (/tmp/, /private/tmp/, /var/folders/, /private/var/folders/, /dev/{null,stdin,stdout,stderr}). Path-token shape gate: tokenize the command, scan for /-prefixed or ~/-prefixed arguments, block on any out-of-workspace path. Tolerates apostrophe-quoted paths (BTS-234), slash-command lexical fragments (BTS-173/210/234), and pure-slash jq operators (BTS-169). git commit carve-out (BTS-151) prevents narrative false-positives. ALLOW_OUTSIDE_WORKSPACE=1 bypass.
# input: stdin JSON envelope `{tool_input:{command}}` from Claude Code's PreToolUse contract
# input: env HOME (drives $WORKSPACE = $HOME/projects)
# input: env CLAUDE_PROJECT_DIR (used to lazy-build slash-command name allowlist from `.claude/commands/*.md` and `.claude/skills/<name>/`)
# output: exit-codes 0 allow / 2 block
# output: stderr on block: BLOCKED with offending path + bypass hint
# caller: .claude/settings.json
# depends-on: jq
# side-effect: writes-stderr-on-block
# failure-mode: out-of-workspace-path-blocked | exit=2 | visible=stderr-BLOCKED-with-offending-path-and-bypass-hint | mitigation=move-target-into-workspace-or-ALLOW_OUTSIDE_WORKSPACE=1-prefix
# contract: never-blocks-non-gated-verbs
# contract: env-prefix-bypass-via-ALLOW_OUTSIDE_WORKSPACE=1
# contract: git-commit-carve-out-prevents-narrative-false-positives
# contract: slash-command-name-allowlist-prevents-/idea-/recall-etc-false-positives
# contract: tolerates-apostrophe-quoting-on-path-tokens
# anchor: BTS-151 (git commit carve-out)
# anchor: BTS-153 (cat read-side gate)
# anchor: BTS-157 (sort -o gate via path-token iteration)
# anchor: BTS-169 (pure-slash jq operator passthrough)
# anchor: BTS-173 (slash-command lexical-fragment allowlist)
# anchor: BTS-210 (trailing-prose-punct tolerance on slash-command)
# anchor: BTS-234 (apostrophe-quoted path strip + 's possessive)
# anchor: BTS-251 (manifest seed)
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

# Tokenize: strip double-quotes, then word-split on whitespace.
# This makes `bash -c "rm /etc/foo"` extract /etc/foo as a token.
#
# BTS-234: do NOT strip single quotes globally — preserves apostrophe-s
# possessives (`/recall's wrap`) so the BTS-173 slash-command allowlist
# can recognize them. Per-token leading/trailing apostrophe strip below
# preserves the security fence for `'/etc/passwd'`-style quoted-path
# attacks.
NORMALIZED=$(echo "$COMMAND" | tr -d '"')

violation=""
for token in $NORMALIZED; do
  # BTS-169: pure-slash tokens (//, ///, ...) are jq's `//` alternative-
  # default operator. Sequences of 3+ slashes have no filesystem meaning
  # and no shell interpretation; all are safe to skip before path-shape
  # detection.
  [[ "$token" =~ ^/+$ ]] && continue

  # BTS-173: single-segment slash-prefixed tokens that match a KNOWN
  # slash-command name (entries in $CLAUDE_PROJECT_DIR/.claude/commands/
  # *.md or .claude/skills/<name>/) are lexical fragments, not filesystem
  # paths. The allowlist is built lazily on first match-attempt and
  # cached for the rest of the hook invocation. A purely syntactic rule
  # cannot disambiguate /idea (slash-command) from /etc (real path) —
  # both are short alphabetic-leading single-segment tokens. The
  # filesystem-rooted allowlist is the only deterministic path.
  #
  # BTS-210: tolerate a trailing run of prose punctuation on the
  # slash-command match. Set: ] ) . , ; : ! ? > " ' ` (closing/sentence-
  # terminating chars). Without this, prose like `/stasis).` or `/idea,`
  # falls through the allowlist check (regex anchored at $) and gets
  # blocked by the path scan. The capture group still extracts only
  # the slash-command name; trailing punct is OUTSIDE the capture.
  # `]` must be first inside the char class to be treated literally.
  #
  # BTS-234: tolerate an OPTIONAL `'s` possessive between the captured
  # name and the trailing-punct run. So `/recall's`, `/recall's.`, and
  # `/idea's,` all match. The allowlist still gates which name is
  # tolerated — `/unknown's` falls through to the path scan.
  slash_command_trailing_punct=']).,;:!?>"'"'"'`'
  # BTS-234: $'\'s' yields the literal apostrophe-s for the regex
  slash_command_possessive=$'(\'s)?'
  if [[ "$token" =~ ^/([a-zA-Z][a-zA-Z0-9_-]{0,29})${slash_command_possessive}[${slash_command_trailing_punct}]*$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    if [[ -z "${SLASH_COMMANDS+x}" ]]; then
      SLASH_COMMANDS=" "
      cmd_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/commands"
      if [[ -d "$cmd_dir" ]]; then
        for entry in "$cmd_dir"/*.md; do
          [[ -e "$entry" ]] || continue
          base="${entry##*/}"; base="${base%.md}"
          SLASH_COMMANDS+="$base "
        done
      fi
      skill_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/skills"
      if [[ -d "$skill_dir" ]]; then
        for entry in "$skill_dir"/*; do
          [[ -d "$entry" ]] || continue
          base="${entry##*/}"
          SLASH_COMMANDS+="$base "
        done
      fi
    fi
    if [[ "$SLASH_COMMANDS" == *" $candidate "* ]]; then
      continue
    fi
  fi

  # BTS-234: per-token apostrophe strip (leading and trailing) before
  # path-shape detection. Preserves the security fence for quoted-path
  # attacks like `rm '/etc/passwd'` (token is `'/etc/passwd'`, leading
  # `'` strip → `/etc/passwd'`, trailing `'` strip → `/etc/passwd`,
  # path-shape match fires, blocked). The slash-command allowlist
  # check above already used the unstripped `$token` for accurate
  # `'s` matching; this strip only affects the path-shape branch.
  path_token="${token#\'}"
  path_token="${path_token%\'}"

  case "$path_token" in
    /?*)
      # Absolute path (≥1 char after the slash — bare `/` is ignored)
      ok=false
      for prefix in "${ALLOWED_ABS[@]}"; do
        case "$path_token" in
          "$prefix"*|"$prefix")
            ok=true
            break
            ;;
        esac
      done
      if ! $ok; then
        violation="$path_token"
        break
      fi
      ;;
    \~/*)
      # Tilde-prefixed path (literal in command string)
      ok=false
      for prefix in "${ALLOWED_TILDE[@]}"; do
        case "$path_token" in
          "$prefix"*)
            ok=true
            break
            ;;
        esac
      done
      if ! $ok; then
        violation="$path_token"
        break
      fi
      ;;
  esac
done

if [[ -n "$violation" ]]; then
  # @failure-mode: out-of-workspace-path-blocked
  # @side-effect: writes-stderr-on-block
  echo "BLOCKED: path '$violation' is outside the workspace ($WORKSPACE/)." >&2
  echo "  To bypass: ALLOW_OUTSIDE_WORKSPACE=1 <command>" >&2
  exit 2
fi

exit 0
