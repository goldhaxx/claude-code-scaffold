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

# @manifest
# purpose: Deterministic PII + secrets scanner — grep tracked files (and optionally `git log -p`) for hard-coded patterns (GitHub PATs, OpenAI/Anthropic keys, AWS access-key IDs, Slack tokens, Bearer tokens), absolute home paths, real-looking emails, and dangerous file extensions (.env, .pem, *.key, id_rsa, *.credentials). Supports a 2-shape allowlist (file-only legacy + per-finding triple). Used as the deterministic pre-flight in /review and as a CI gate; complements /review's reasoning-based pass.
# input: --files-only (skip git history scan; faster pre-commit pre-flight)
# input: --history-only (skip file scan; full forensic pass over history)
# input: --json (emit `{findings:[{severity, category, location, detail}], total, pass}`)
# input: -h / --help (print usage and exit 0)
# input: env HOME (drives absolute-home-path PII pattern)
# input: env USER (`whoami` resolves OS_USER for path patterns)
# input: file `.security-audit-allowlist` (project-local, two-shape: legacy file-substr or `<file>::<category>::<detail>` triple per BTS-152)
# output: stdout (human-mode): findings table grouped by severity (CRITICAL / WARN / INFO) plus "PASS" or "N findings" footer
# output: stdout (--json): JSON envelope per the input description
# output: stderr: progress lines ("Security audit: <project>", "OS user: <user>")
# output: exit-codes 0 clean / 1 findings-detected / 2 not-a-git-repo or unknown-flag or malformed-allowlist
# caller: skill:/review
# caller: skill:/stasis
# caller: skill:/security-audit
# depends-on: git
# depends-on: jq
# depends-on: whoami
# side-effect: writes-stderr-progress
# failure-mode: not-a-git-repo | exit=2 | visible=stderr-error | mitigation=run-from-git-tree
# failure-mode: unknown-flag | exit=2 | visible=stderr-error | mitigation=use-supported-flag
# failure-mode: malformed-allowlist-line | exit=2 | visible=stderr-error-with-line-number | mitigation=fix-allowlist-syntax
# failure-mode: findings-detected | exit=1 | visible=stdout-findings-table | mitigation=remediate-or-allowlist
# contract: idempotent-on-rerun
# contract: allowlist-loads-when-present-no-error-when-absent
# anchor: BTS-251 (manifest seed)

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
# BTS-152: ALLOWLIST_ENTRIES carries two forms:
#   "file|<substring>"                 — legacy file-only match (silences ALL findings in matching files)
#   "triple|<file>|<category>|<detail>" — per-finding match (file substr AND category exact AND detail substr)
# Each entry is a pipe-delimited string because bash 3.2 (macOS default)
# lacks associative arrays-of-arrays.
ALLOWLIST_ENTRIES=(
  'file|security-audit.sh'              # This script itself
  'file|tls-troubleshooting.md'         # Documents cert paths as instructions
  'file|hooks-reference.md'             # Documents hook patterns
  'file|foundations.md'                 # Research document
  'file|.bats'                          # Test fixtures contain fake tokens/secrets by design
  'file|.security-audit-allowlist'      # The allowlist file itself documents patterns to silence
)

# Load optional project-local allowlist.
#
# Two formats supported:
#   <file-substring>                              — legacy file-only
#   <file-substring>::<category>::<detail-substr> — per-finding (BTS-152)
#
# Empty <category> or <detail-substring> in a triple acts as a wildcard
# for that segment. Empty <file-substring> is rejected (would silence
# everything globally). Triple lines must have exactly 3 ::-separated
# segments; malformed lines exit non-zero with a clear stderr message.
#
# Lines starting with '#' and blank lines are ignored; whitespace is trimmed.
PROJECT_ALLOWLIST_FILE=".security-audit-allowlist"
if [[ -f "$PROJECT_ALLOWLIST_FILE" ]]; then
  lineno=0
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    lineno=$((lineno + 1))
    trimmed="${raw_line#"${raw_line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]] && continue

    if [[ "$trimmed" == *"::"* ]]; then
      # Triple format. Use awk to split on `::` literal.
      parts=$(printf '%s' "$trimmed" | awk -F'::' '{print NF}')
      if [[ "$parts" -ne 3 ]]; then
        # @failure-mode: malformed-allowlist-line
        echo "ERROR: $PROJECT_ALLOWLIST_FILE:$lineno: malformed triple (expected exactly 3 ::-separated segments, got $parts): $trimmed" >&2
        exit 2
      fi
      file_part=$(printf '%s' "$trimmed" | awk -F'::' '{print $1}')
      cat_part=$(printf '%s' "$trimmed" | awk -F'::' '{print $2}')
      det_part=$(printf '%s' "$trimmed" | awk -F'::' '{print $3}')
      if [[ -z "$file_part" ]]; then
        echo "ERROR: $PROJECT_ALLOWLIST_FILE:$lineno: empty file-substring is not allowed (would silence all findings): $trimmed" >&2
        exit 2
      fi
      # Reject literal `|` in any segment — the in-memory representation
      # uses `|` as the field separator (bash 3.2 lacks better options).
      # Pipes in user input would corrupt the splitter in is_allowlisted.
      if [[ "$file_part" == *"|"* || "$cat_part" == *"|"* || "$det_part" == *"|"* ]]; then
        echo "ERROR: $PROJECT_ALLOWLIST_FILE:$lineno: segments must not contain '|' (reserved internal delimiter): $trimmed" >&2
        exit 2
      fi
      ALLOWLIST_ENTRIES+=("triple|$file_part|$cat_part|$det_part")
    else
      # Reject literal `|` in legacy file-only entries too (same rationale).
      if [[ "$trimmed" == *"|"* ]]; then
        echo "ERROR: $PROJECT_ALLOWLIST_FILE:$lineno: file-substring must not contain '|' (reserved internal delimiter): $trimmed" >&2
        exit 2
      fi
      ALLOWLIST_ENTRIES+=("file|$trimmed")
    fi
  done < "$PROJECT_ALLOWLIST_FILE"
fi

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
  # BTS-152: accept (file, category, detail) for per-finding matching.
  # Falls back to legacy file-only behavior when only $file is provided
  # (callers that pre-date the change still work).
  local file="$1"
  local category="${2:-}"
  local detail="${3:-}"

  for entry in "${ALLOWLIST_ENTRIES[@]}"; do
    case "$entry" in
      file\|*)
        local fpat="${entry#file|}"
        if [[ "$file" == *"$fpat"* ]]; then
          return 0
        fi
        ;;
      triple\|*)
        # Strip leading "triple|" then split the remainder on |.
        local rest="${entry#triple|}"
        local fpat="${rest%%|*}"; rest="${rest#"$fpat"|}"
        local cpat="${rest%%|*}"; rest="${rest#"$cpat"|}"
        local dpat="$rest"

        # File substring is required (validated at load time).
        [[ "$file" == *"$fpat"* ]] || continue
        # Category: empty pattern matches anything.
        [[ -z "$cpat" || "$category" == "$cpat" ]] || continue
        # Detail: empty pattern matches anything; otherwise substring match.
        [[ -z "$dpat" || "$detail" == *"$dpat"* ]] || continue
        return 0
        ;;
    esac
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
      # Redact the actual secret value
      local redacted detail
      redacted=$(echo "$content" | sed -E "s/($pattern)/[REDACTED]/g")
      detail="Secret pattern match: $redacted"
      if ! is_allowlisted "$file" "secret" "$detail"; then
        add_finding "CRITICAL" "secret" "$file:$line" "$detail"
      fi
    done < <(git ls-files -z | xargs -0 grep -nE "$pattern" 2>/dev/null || true)
  done
}

scan_tracked_files_pii() {
  echo "Scanning tracked files for PII..." >&2
  for pattern in "${PII_PATTERNS[@]}"; do
    while IFS=: read -r file line content; do
      local detail="Absolute path with username: $content"
      if ! is_allowlisted "$file" "pii" "$detail"; then
        add_finding "HIGH" "pii" "$file:$line" "$detail"
      fi
    done < <(git ls-files -z | xargs -0 grep -nF "$pattern" 2>/dev/null || true)
  done
}

scan_tracked_files_emails() {
  echo "Scanning tracked files for email addresses..." >&2
  # Match email-like patterns, excluding noreply and example.com
  while IFS=: read -r file line content; do
    local detail="Email address found: $content"
    if ! is_allowlisted "$file" "email" "$detail"; then
      # Skip noreply addresses and example domains
      if ! echo "$content" | grep -qE 'noreply@|@example\.(com|org|net)|@users\.noreply'; then
        add_finding "MEDIUM" "email" "$file:$line" "$detail"
      fi
    fi
  done < <(git ls-files -z | xargs -0 grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' 2>/dev/null || true)
}

scan_dangerous_files() {
  echo "Scanning for dangerous file types..." >&2
  for pattern in "${DANGEROUS_EXTENSIONS[@]}"; do
    while IFS= read -r file; do
      local detail="Sensitive file type tracked in git"
      if ! is_allowlisted "$file" "dangerous-file" "$detail"; then
        add_finding "CRITICAL" "dangerous-file" "$file" "$detail"
      fi
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

  # Build pathspec exclusions from file-form ALLOWLIST_ENTRIES so the audit
  # script's own pattern definitions (and other documentation containing
  # example tokens) don't trigger false positives. Without this, -S matches
  # the literal regex strings inside SECRET_PATTERNS when the script itself
  # appears in a commit diff. BTS-152: triple-form entries do not affect
  # history scanning — the history pickaxe operates at the file/diff level
  # and emits per-commit findings without populating the detail/category
  # fields a triple would match against. Triples filter file-scan findings
  # only; if you need to silence a finding in history, use a file-only
  # entry. Documented in .security-audit-allowlist header.
  local pathspec_args=('.')
  for entry in "${ALLOWLIST_ENTRIES[@]}"; do
    case "$entry" in
      file\|*)
        local fpat="${entry#file|}"
        pathspec_args+=(":(exclude,glob)**${fpat}*")
        ;;
    esac
  done

  for pattern in "${SECRET_PATTERNS[@]}"; do
    while IFS= read -r hash; do
      if [[ -n "$hash" ]]; then
        add_finding "CRITICAL" "secret" "commit:$hash" "Secret pattern found in commit diff"
      fi
    done < <(git log --all -p --format='%h' --pickaxe-regex -S "$pattern" -- "${pathspec_args[@]}" 2>/dev/null | grep -E '^[0-9a-f]{7,}$' || true)
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
  # @failure-mode: findings-detected
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
    *)
      # @failure-mode: unknown-flag
      echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Must be in a git repo
# @failure-mode: not-a-git-repo
git rev-parse HEAD >/dev/null 2>&1 || { echo "ERROR: Not a git repository" >&2; exit 2; }

# @side-effect: writes-stderr-progress
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
