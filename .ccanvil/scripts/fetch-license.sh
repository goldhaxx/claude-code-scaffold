#!/usr/bin/env bash
# fetch-license.sh — Download a license template from GitHub's API
#
# Usage: bash scripts/fetch-license.sh <license-key> <fullname> [output-file]
#
# Common license keys: mit, apache-2.0, gpl-3.0, bsd-2-clause, bsd-3-clause, unlicense
# Full list: gh api /licenses --jq '.[].key'
#
# Requires: gh (GitHub CLI), authenticated

# @manifest
# purpose: Pull a license template from GitHub's `/licenses/{key}` API, substitute year + copyright-owner placeholders, and write the result to a local file (default `LICENSE`). Used by /ccanvil-init's optional license step so a fresh node lands with a real LICENSE file under one command instead of paste-from-the-internet.
# input: positional <license-key> (e.g. mit, apache-2.0, gpl-3.0, bsd-2-clause, bsd-3-clause, unlicense — full list: gh api /licenses --jq '.[].key')
# input: positional <fullname> (copyright owner, substituted into [fullname] / [name of copyright owner] placeholders)
# input: positional [output-file] (defaults to `LICENSE` in CWD)
# output: file <output-file> with substituted license body
# output: stdout: `License written: <key> → <output>` on success
# output: exit-codes 0 ok / 1 missing-gh-or-unknown-key
# caller: global-commands/ccanvil-init.md
# depends-on: gh
# depends-on: date
# side-effect: writes-license-file
# failure-mode: missing-gh | exit=1 | visible=stderr-error-with-install-hint | mitigation=brew-install-gh
# failure-mode: unknown-license-key | exit=1 | visible=stderr-error-and-available-keys | mitigation=pick-from-listed-keys
# contract: idempotent-on-rerun
# contract: overwrites-output-file
# anchor: BTS-251 (manifest seed)

set -euo pipefail

LICENSE_KEY="${1:?Usage: fetch-license.sh <license-key> <fullname> [output-file]}"
FULLNAME="${2:?Usage: fetch-license.sh <license-key> <fullname> [output-file]}"
OUTPUT="${3:-LICENSE}"
YEAR=$(date +%Y)

if ! command -v gh >/dev/null 2>&1; then
  # @failure-mode: missing-gh
  echo "ERROR: gh (GitHub CLI) is required. Install: brew install gh" >&2
  exit 1
fi

# Fetch license body from GitHub API
BODY=$(gh api "/licenses/${LICENSE_KEY}" --jq '.body' 2>/dev/null)
if [[ -z "$BODY" ]]; then
  # @failure-mode: unknown-license-key
  echo "ERROR: Unknown license key '${LICENSE_KEY}'." >&2
  echo "Available keys:" >&2
  gh api /licenses --jq '.[].key' >&2
  exit 1
fi

# Replace common placeholders across license formats
BODY="${BODY//\[year\]/$YEAR}"
BODY="${BODY//\[yyyy\]/$YEAR}"
BODY="${BODY//\[fullname\]/$FULLNAME}"
BODY="${BODY//\[name of copyright owner\]/$FULLNAME}"

# @side-effect: writes-license-file
printf '%s\n' "$BODY" > "$OUTPUT"
echo "License written: ${LICENSE_KEY} → ${OUTPUT}"
