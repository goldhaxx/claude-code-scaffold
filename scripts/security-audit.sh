#!/usr/bin/env bash
# security-audit.sh — Deterministic PII and secrets scanner for git repos.
#
# Scans tracked files and git history for patterns that should not be
# in a public repository. Exit codes:
#   0 — no findings
#   1 — findings detected (details on stdout)
#   2 — usage error
#
# Usage:
#   security-audit.sh [--files-only] [--history-only] [--json]

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Get the current OS username to detect absolute home paths
OS_USER=$(whoami)
HOME_DIR="$HOME"

# Patterns that indicate secrets/tokens (regex, case-insensitive)
SECRET_PATTERNS=(
  'ghp_[A-Za-z0-9_]{36}'           # GitHub personal access token
  'gho_[A-Za-z0-9_]{36}'           # GitHub OAuth token
  'github_pat_[A-Za-z0-9_]{82}'    # GitHub fine-grained PAT
  'sk-[A-Za-z0-9]{20,}'            # OpenAI/Anthropic API key
  'Bearer [A-Za-z0-9\-._~+/]+=*'  # Bearer tokens
  'AKIA[0-9A-Z]{16}'               # AWS access key ID
  'xox[bpsa]-[A-Za-z0-9\-]+'      # Slack tokens
)

# Patterns that indicate PII (regex)
PII_PATTERNS=(
  "/Users/$OS_USER"                 # macOS absolute home path
  "/home/$OS_USER"                  # Linux absolute home path
  "C:\\\\Users\\\\$OS_USER"        # Windows absolute home path
)

# File extensions that should never be tracked
DANGEROUS_EXTENSIONS=(
  '\.env$'
  '\.env\.'
  '\.pem$'
  '\.key$'
  '\.p12$'
  '\.pfx$'
  '\.jks$'
  '\.keystore$'
  'id_rsa$'
  'id_ed25519$'
  'id_ecdsa$'
  '\.credentials$'
)

# Context patterns — these appear in documentation/rules and are OK
# We exclude matches inside these files from being flagged
ALLOWLIST_FILES=(
  'security-audit.sh'              # This script itself
  'tls-troubleshooting.md'         # Documents cert paths as instructions
  'hooks-reference.md'             # Documents hook patterns
  'scaffold-framework.md'          # Research document
  '.bats'                          # Test fixtures contain fake tokens/secrets by design
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

FINDINGS=()
JSON_MODE=false
FILES_ONLY=false
HISTORY_ONLY=false

add_finding() {
  local severity="$1"  # CRITICAL, HIGH, MEDIUM, LOW
  local category="$2"  # secret, pii, dangerous-file, email
  local location="$3"  # file:line or commit:hash
  local detail="$4"    # what was found (redacted)

  FINDINGS+=("$severity|$category|$location|$detail")
}

is_allowlisted() {
  local file="$1"
  for allowed in "${ALLOWLIST_FILES[@]}"; do
    if [[ "$file" == *"$allowed"* ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Scanners
# ---------------------------------------------------------------------------

scan_tracked_files_secrets() {
  echo "Scanning tracked files for secrets..." >&2
  for pattern in "${SECRET_PATTERNS[@]}"; do
    while IFS=: read -r file line content; do
      if ! is_allowlisted "$file"; then
        # Redact the actual secret value
        local redacted
        redacted=$(echo "$content" | sed -E "s/($pattern)/[REDACTED]/g")
        add_finding "CRITICAL" "secret" "$file:$line" "Secret pattern match: $redacted"
      fi
    done < <(git ls-files -z | xargs -0 grep -nE "$pattern" 2>/dev/null || true)
  done
}

scan_tracked_files_pii() {
  echo "Scanning tracked files for PII..." >&2
  for pattern in "${PII_PATTERNS[@]}"; do
    while IFS=: read -r file line content; do
      if ! is_allowlisted "$file"; then
        add_finding "HIGH" "pii" "$file:$line" "Absolute path with username: $content"
      fi
    done < <(git ls-files -z | xargs -0 grep -nF "$pattern" 2>/dev/null || true)
  done
}

scan_tracked_files_emails() {
  echo "Scanning tracked files for email addresses..." >&2
  # Match email-like patterns, excluding noreply and example.com
  while IFS=: read -r file line content; do
    if ! is_allowlisted "$file"; then
      # Skip noreply addresses and example domains
      if ! echo "$content" | grep -qE 'noreply@|@example\.(com|org|net)|@users\.noreply'; then
        add_finding "MEDIUM" "email" "$file:$line" "Email address found: $content"
      fi
    fi
  done < <(git ls-files -z | xargs -0 grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' 2>/dev/null || true)
}

scan_dangerous_files() {
  echo "Scanning for dangerous file types..." >&2
  for pattern in "${DANGEROUS_EXTENSIONS[@]}"; do
    while IFS= read -r file; do
      add_finding "CRITICAL" "dangerous-file" "$file" "Sensitive file type tracked in git"
    done < <(git ls-files | grep -E "$pattern" 2>/dev/null || true)
  done
}

scan_git_history_pii() {
  echo "Scanning git history for PII..." >&2

  # Check commit messages
  while IFS= read -r line; do
    local hash subject
    hash=$(echo "$line" | cut -d' ' -f1)
    subject=$(echo "$line" | cut -d' ' -f2-)
    for pattern in "${PII_PATTERNS[@]}"; do
      if echo "$subject" | grep -qF "$pattern"; then
        add_finding "HIGH" "pii" "commit:$hash" "Absolute path in commit message"
      fi
    done
  done < <(git log --all --format='%h %s %b' 2>/dev/null)

  # Check author emails (flag non-noreply)
  while IFS= read -r email; do
    if [[ -n "$email" ]] && ! echo "$email" | grep -qE 'noreply|@users\.noreply'; then
      # Check if it looks like a personal email (not a bot)
      if echo "$email" | grep -qE '@gmail\.|@yahoo\.|@hotmail\.|@outlook\.|@icloud\.|@proton'; then
        add_finding "MEDIUM" "email" "git-config" "Personal email in git author: $email"
      fi
    fi
  done < <(git log --all --format='%ae' | sort -u 2>/dev/null)
}

scan_git_history_secrets() {
  echo "Scanning git history for secrets..." >&2
  for pattern in "${SECRET_PATTERNS[@]}"; do
    while IFS= read -r hash; do
      if [[ -n "$hash" ]]; then
        add_finding "CRITICAL" "secret" "commit:$hash" "Secret pattern found in commit diff"
      fi
    done < <(git log --all -p --format='%h' -S "$pattern" 2>/dev/null | grep -E '^[0-9a-f]{7,}$' || true)
  done
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

print_findings() {
  if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    echo ""
    echo "PASS — No security findings detected."
    return 0
  fi

  echo ""
  echo "FINDINGS (${#FINDINGS[@]} total):"
  echo ""

  local critical=0 high=0 medium=0 low=0

  for finding in "${FINDINGS[@]}"; do
    IFS='|' read -r severity category location detail <<< "$finding"
    case "$severity" in
      CRITICAL) critical=$((critical + 1)) ;;
      HIGH)     high=$((high + 1)) ;;
      MEDIUM)   medium=$((medium + 1)) ;;
      LOW)      low=$((low + 1)) ;;
    esac
    printf "  [%-8s] %-16s %-40s %s\n" "$severity" "$category" "$location" "$detail"
  done

  echo ""
  echo "Summary: $critical critical, $high high, $medium medium, $low low"
  return 1
}

print_findings_json() {
  if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    echo '{"findings":[],"total":0,"pass":true}'
    return 0
  fi

  local result='[]'
  for finding in "${FINDINGS[@]}"; do
    IFS='|' read -r severity category location detail <<< "$finding"
    result=$(echo "$result" | jq \
      --arg s "$severity" --arg c "$category" --arg l "$location" --arg d "$detail" \
      '. + [{"severity": $s, "category": $c, "location": $l, "detail": $d}]')
  done
  echo "$result" | jq "{findings: ., total: length, pass: false}"
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files-only)  FILES_ONLY=true; shift ;;
    --history-only) HISTORY_ONLY=true; shift ;;
    --json)        JSON_MODE=true; shift ;;
    -h|--help)
      echo "Usage: security-audit.sh [--files-only] [--history-only] [--json]"
      echo ""
      echo "Scans tracked files and git history for secrets, PII, and dangerous files."
      echo "Exit 0 = clean, Exit 1 = findings detected."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Must be in a git repo
git rev-parse HEAD >/dev/null 2>&1 || { echo "ERROR: Not a git repository" >&2; exit 2; }

echo "Security audit: $(basename "$(pwd)")" >&2
echo "OS user: $OS_USER" >&2
echo "" >&2

if [[ "$HISTORY_ONLY" != "true" ]]; then
  scan_tracked_files_secrets
  scan_tracked_files_pii
  scan_tracked_files_emails
  scan_dangerous_files
fi

if [[ "$FILES_ONLY" != "true" ]]; then
  scan_git_history_pii
  scan_git_history_secrets
fi

if [[ "$JSON_MODE" == "true" ]]; then
  print_findings_json
else
  print_findings
fi
