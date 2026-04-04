#!/usr/bin/env bash
# fetch-license.sh — Download a license template from GitHub's API
#
# Usage: bash scripts/fetch-license.sh <license-key> <fullname> [output-file]
#
# Common license keys: mit, apache-2.0, gpl-3.0, bsd-2-clause, bsd-3-clause, unlicense
# Full list: gh api /licenses --jq '.[].key'
#
# Requires: gh (GitHub CLI), authenticated

set -euo pipefail

LICENSE_KEY="${1:?Usage: fetch-license.sh <license-key> <fullname> [output-file]}"
FULLNAME="${2:?Usage: fetch-license.sh <license-key> <fullname> [output-file]}"
OUTPUT="${3:-LICENSE}"
YEAR=$(date +%Y)

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh (GitHub CLI) is required. Install: brew install gh" >&2
  exit 1
fi

# Fetch license body from GitHub API
BODY=$(gh api "/licenses/${LICENSE_KEY}" --jq '.body' 2>/dev/null)
if [[ -z "$BODY" ]]; then
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

printf '%s\n' "$BODY" > "$OUTPUT"
echo "License written: ${LICENSE_KEY} → ${OUTPUT}"
