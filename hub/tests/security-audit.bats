#!/usr/bin/env bats
# Tests for scripts/security-audit.sh
#
# Each test creates an isolated git repo with specific scenarios.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/security-audit.sh"

setup() {
  REPO=$(mktemp -d)
  cd "$REPO"
  git init -q
  echo "# Clean project" > README.md
  git add -A && git commit -q -m "init"
}

teardown() {
  rm -rf "$REPO"
}


# =========================================================================
# Clean repo tests
# =========================================================================

@test "clean repo passes with exit 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PASS"
}

@test "clean repo JSON output shows pass:true" {
  result=$(bash "$SCRIPT" --json 2>/dev/null)
  echo "$result" | jq -e '.pass == true'
}


# =========================================================================
# Secret detection
# =========================================================================

@test "detects GitHub personal access token" {
  echo "token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234" > config.txt
  git add config.txt && git commit -q -m "add config"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CRITICAL"
  echo "$output" | grep -q "secret"
}

@test "detects AWS access key" {
  echo "aws_key = AKIAIOSFODNN7EXAMPLE" > creds.txt
  git add creds.txt && git commit -q -m "add creds"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CRITICAL"
}

@test "detects OpenAI/Anthropic API key" {
  echo "api_key = sk-proj1234567890abcdefghijklmnop" > key.txt
  git add key.txt && git commit -q -m "add key"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CRITICAL"
}


# =========================================================================
# PII detection
# =========================================================================

@test "detects absolute home path with OS username" {
  local user
  user=$(whoami)
  echo "path = /Users/$user/projects/secret" > paths.txt
  git add paths.txt && git commit -q -m "add paths"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "HIGH"
  echo "$output" | grep -q "pii"
}

@test "tilde paths do not trigger PII detection" {
  echo "path = ~/projects/myproject" > paths.txt
  git add paths.txt && git commit -q -m "add paths"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
}


# =========================================================================
# Dangerous file detection
# =========================================================================

@test "detects tracked .env file" {
  echo "SECRET=bad" > .env
  git add .env && git commit -q -m "add env"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "CRITICAL"
  echo "$output" | grep -q "dangerous-file"
}

@test "detects tracked .pem file" {
  echo "fake cert" > server.pem
  git add server.pem && git commit -q -m "add cert"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "dangerous-file"
}

@test "detects tracked SSH key" {
  echo "fake key" > id_rsa
  git add id_rsa && git commit -q -m "add key"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "dangerous-file"
}


# =========================================================================
# BTS-394: template-suffix carve-out (.example / .template / .sample)
# =========================================================================
# scan_dangerous_files used to flag canonical templates like .env.example
# because the broad `\.env\.` pattern matches any path containing `.env.`.
# Carve-out: skip files whose basename ends in `.example`, `.template`, or
# `.sample`. Other dangerous patterns are anchored with `$`, so they never
# match `.example`-suffixed paths in the first place — the carve-out is
# only ever exercised on the `\.env\.` matcher.

@test "BTS-394 AC-1: .env.example does not flag as dangerous-file" {
  echo "API_KEY=YOUR_KEY_HERE" > .env.example
  git add -A && git commit -q -m "add env template"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "dangerous-file"
}

@test "BTS-394 AC-2: .env.template and .env.sample do not flag as dangerous-file" {
  echo "API_KEY=YOUR_KEY_HERE" > .env.template
  echo "API_KEY=YOUR_KEY_HERE" > .env.sample
  git add -A && git commit -q -m "add template + sample"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "dangerous-file"
}

@test "BTS-394 AC-3: real .env / .env.local / .env.production still flag CRITICAL" {
  echo "SECRET=real" > .env
  echo "SECRET=real" > .env.local
  echo "SECRET=real" > .env.production
  echo "SECRET=real" > .env.development.local
  git add -A && git commit -q -m "add real env files"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  # Four dangerous-file findings, one per filename.
  [ "$(echo "$output" | grep -c "dangerous-file")" -eq 4 ]
  echo "$output" | grep -qE "dangerous-file[[:space:]]+\.env[[:space:]]"
  echo "$output" | grep -qE "dangerous-file[[:space:]]+\.env\.local"
  echo "$output" | grep -qE "dangerous-file[[:space:]]+\.env\.production"
  echo "$output" | grep -qE "dangerous-file[[:space:]]+\.env\.development\.local"
}

@test "BTS-394 AC-4: other dangerous extensions still flag (.pem, id_rsa, .credentials)" {
  echo "fake cert" > server.pem
  echo "fake rsa" > id_rsa
  echo "fake creds" > app.credentials
  git add -A && git commit -q -m "add other dangerous files"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE "dangerous-file[[:space:]]+server\.pem"
  echo "$output" | grep -qE "dangerous-file[[:space:]]+id_rsa"
  echo "$output" | grep -qE "dangerous-file[[:space:]]+app\.credentials"
}

@test "BTS-394 AC-5: .env.example with real GitHub PAT still triggers secret CRITICAL" {
  echo "GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234" > .env.example
  git add -A && git commit -q -m "add template with real PAT"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "secret"
  # Per AC-5 the dangerous-file category should NOT fire on .env.example —
  # only the secret-content scan does.
  ! echo "$output" | grep -q "dangerous-file"
}

@test "BTS-394 AC-6: legacy .env.example::dangerous-file:: allowlist entry parses without error" {
  echo "API_KEY=YOUR_KEY_HERE" > .env.example
  cat > .security-audit-allowlist <<'EOF'
.env.example::dangerous-file::
EOF
  git add -A && git commit -q -m "add template + legacy allowlist"

  run --separate-stderr bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"malformed"* ]]
  [[ "$stderr" != *"ERROR"* ]]
}

@test "BTS-394 edge: .env.local.example (template-suffix wins) does not flag" {
  # Plausible downstream filename ("here's an example .env.local"). Matches
  # `\.env\.` AND ends in `.example` → carve-out fires, no finding.
  echo "API_KEY=YOUR_KEY_HERE" > .env.local.example
  git add -A && git commit -q -m "add nested template"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "dangerous-file"
}

@test "BTS-394 edge: .env.example.local (real-suffix wins) still flags CRITICAL" {
  # Plausible downstream filename (a `.local` override of an `.example`).
  # Matches `\.env\.` and ends in `.local`, NOT a template suffix → flag.
  echo "SECRET=real" > .env.example.local
  git add -A && git commit -q -m "add real env on top of example"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE "dangerous-file[[:space:]]+\.env\.example\.local"
}


# =========================================================================
# BTS-395: URI-scheme email-finding filter
# =========================================================================
# scan_tracked_files_emails used to flag connection-string URLs
# (postgresql://USER:PASSWORD@HOST.REGION/db) as MEDIUM email findings —
# the regex matched the URI's userinfo@host substring even though the line
# is not an email. Filter: skip lines whose $content contains a known
# DB-protocol URI-scheme prefix (postgres/postgresql/mongodb/redis/mysql/
# mssql/amqp + their +srv/ssl variants).

@test "BTS-395 AC-1: postgresql:// connection string does not flag as email" {
  echo 'DATABASE_URL=postgresql://USER:PASSWORD@HOST.REGION.aws.neon.tech/db' > .env.example
  git add -A && git commit -q -m "add postgres conn"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  # Match finding rows specifically, not the "Scanning ... email addresses" banner.
  ! echo "$output" | grep -qE "MEDIUM.*email"
}

@test "BTS-395 AC-2: 9 other DB connection-string schemes do not flag as email" {
  cat > .env.example <<'EOF'
PG_URL=postgres://u:p@db.host.com/x
MONGO_URL=mongodb://u:p@db.host.com/x
MONGO_SRV_URL=mongodb+srv://u:p@cluster.host.com/x
REDIS_URL=redis://u:p@cache.host.com:6379
REDISS_URL=rediss://u:p@cache.host.com:6379
MYSQL_URL=mysql://u:p@db.host.com/x
MSSQL_URL=mssql://u:p@db.host.com/x
AMQP_URL=amqp://u:p@queue.host.com:5672
AMQPS_URL=amqps://u:p@queue.host.com:5672
EOF
  git add -A && git commit -q -m "add 9 conn schemes"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE "MEDIUM.*email"
}

@test "BTS-395 AC-3: real email on a non-URI line still flags MEDIUM email" {
  echo 'CONTACT=admin@company.com' > config.txt
  git add -A && git commit -q -m "add contact"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "email"
  echo "$output" | grep -q "admin@company.com"
}

@test "BTS-395 AC-4: mixed file — connection string skipped, real email on separate line still flags" {
  cat > .env.example <<'EOF'
DATABASE_URL=postgresql://u:p@db.host.com/x
CONTACT=admin@company.com
EOF
  git add -A && git commit -q -m "add mixed content"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 1 ]
  # Exactly one email finding — only the contact line.
  [ "$(echo "$output" | grep -c "MEDIUM.*email")" -eq 1 ]
  echo "$output" | grep -q "admin@company.com"
  ! echo "$output" | grep -q "postgresql"
}

@test "BTS-395 AC-5: legacy .env.example::email:: allowlist entry parses without error" {
  echo 'DATABASE_URL=postgresql://u:p@db.host.com/x' > .env.example
  cat > .security-audit-allowlist <<'EOF'
.env.example::email::
EOF
  git add -A && git commit -q -m "add postgres + legacy allowlist"

  run --separate-stderr bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"malformed"* ]]
  [[ "$stderr" != *"ERROR"* ]]
}

@test "BTS-395 AC-6: noreply@ and @example.com exclusions still silence email findings" {
  cat > emails.txt <<'EOF'
A=noreply@github.com
B=bot@example.com
C=alice@example.org
D=charlie@example.net
E=me@users.noreply.github.com
EOF
  git add -A && git commit -q -m "add excluded emails"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "MEDIUM.*email"
}


# =========================================================================
# Git history detection
# =========================================================================

@test "detects PII in commit messages" {
  local user
  user=$(whoami)
  git commit --allow-empty -q -m "deploy from /Users/$user/projects"

  run bash "$SCRIPT" --history-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pii"
  echo "$output" | grep -q "commit"
}


# =========================================================================
# Allowlist tests
# =========================================================================

@test "allowlisted files do not trigger findings" {
  # security-audit.sh itself contains secret patterns as literals
  cp "$SCRIPT" security-audit.sh
  git add security-audit.sh && git commit -q -m "add script"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
}

# =========================================================================
# BTS-152: per-finding allowlist (file::category::detail-substring)
# =========================================================================

@test "BTS-152 AC-1: legacy file-only allowlist still silences all findings in matched file" {
  echo 'token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234' > leaky.txt
  cat > .security-audit-allowlist <<'EOF'
leaky.txt
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
}

@test "BTS-152 AC-2: triple-format silences only matching category+detail" {
  local user
  user=$(whoami)
  # Create a file with one PII finding (Read(/Users/<user>/...) pattern).
  echo "Read(/Users/$user/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<EOF
settings.json::pii::Read(/Users/$user/
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  # The pii finding is silenced by the triple match → exit 0.
  [ "$status" -eq 0 ]
}

@test "BTS-152 AC-4: triple format does NOT silence findings of a different category in the same file" {
  local user
  user=$(whoami)
  # Two findings in one file: one pii (allowlisted), one secret (not allowlisted).
  cat > settings.json <<EOF
Read(/Users/$user/projects/foo)
token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234
EOF
  cat > .security-audit-allowlist <<EOF
settings.json::pii::Read(/Users/$user/
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  # The secret finding is NOT silenced → exit 1, output mentions secret.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "secret"
}

@test "BTS-152 AC-5: file-only and triple entries coexist in the same allowlist" {
  local user
  user=$(whoami)
  echo 'token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234' > leaky.txt
  echo "Read(/Users/$user/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<EOF
# legacy file-only entry
leaky.txt
# new triple-format entry
settings.json::pii::Read(/Users/$user/
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]
}

@test "BTS-152 AC-6 (error): malformed triple (fewer than 3 :: parts) is rejected at load time" {
  echo "Read(/Users/me/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<'EOF'
settings.json::pii
EOF
  git add -A && git commit -q -m "add fixture"

  run --separate-stderr bash "$SCRIPT" --files-only
  # Non-zero exit (malformed allowlist line is a load-time error).
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"allowlist"* ]] || [[ "$stderr" == *"malformed"* ]]
}

@test "BTS-152 AC-6 (error): triple with > 3 ::-segments is also rejected" {
  echo "Read(/Users/me/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<'EOF'
settings.json::pii::detail::extra
EOF
  git add -A && git commit -q -m "add fixture"

  run --separate-stderr bash "$SCRIPT" --files-only
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"malformed"* ]] || [[ "$stderr" == *"3 ::-separated"* ]]
}

@test "BTS-152: literal pipe in any allowlist segment is rejected (internal delimiter guard)" {
  echo "Read(/Users/me/projects/foo)" > settings.json
  # Pipe in detail segment — would corrupt the in-memory pipe-delimited
  # representation if not validated.
  cat > .security-audit-allowlist <<'EOF'
settings.json::pii::has|pipe
EOF
  git add -A && git commit -q -m "add fixture"

  run --separate-stderr bash "$SCRIPT" --files-only
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"|"* ]] || [[ "$stderr" == *"reserved"* ]]
}

@test "BTS-152 AC-7 (edge): empty file-substring is rejected" {
  cat > .security-audit-allowlist <<'EOF'
::pii::some-detail
EOF
  git add -A && git commit -q -m "add fixture"

  run --separate-stderr bash "$SCRIPT" --files-only
  [ "$status" -ne 0 ]
}

@test "BTS-152 AC-3: unrecognized category in triple is harmless (no error, just doesn't match)" {
  local user
  user=$(whoami)
  echo "Read(/Users/$user/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<EOF
settings.json::nonsense-category::Read(/Users/$user/
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  # Unrecognized category doesn't match the pii finding → finding still surfaces.
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "pii"
}

@test "BTS-152 AC-7: empty detail-substring acts as wildcard for that segment" {
  local user
  user=$(whoami)
  echo "Read(/Users/$user/projects/foo)" > settings.json
  cat > .security-audit-allowlist <<EOF
settings.json::pii::
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  # Empty detail = match any pii finding in settings.json → silenced.
  [ "$status" -eq 0 ]
}

@test "BTS-152 AC-7: empty category acts as wildcard (matches any category in file)" {
  local user
  user=$(whoami)
  cat > settings.json <<EOF
Read(/Users/$user/projects/foo)
EOF
  # Format: <file>::<category>::<detail>. Empty category means double-colon
  # immediately followed by another double-colon: `settings.json::::Read(...)`.
  cat > .security-audit-allowlist <<EOF
settings.json::::Read(/Users/$user/
EOF
  git add -A && git commit -q -m "add fixture"

  run bash "$SCRIPT" --files-only
  # Empty category in the middle → matches pii finding by detail substring alone.
  [ "$status" -eq 0 ]
}


# =========================================================================
# History-scanner pathspec (regression for 7c474b2)
# =========================================================================
#
# Pathspec construction was '**${fpat}*', which doesn't bridge to nested
# paths because git's '**' only matches at path-component boundaries. A
# file-form allowlist entry like 'fn-atlas/captures/' did not exclude
# 'docs/fn-atlas/captures/...' from -S pickaxe-regex history scans.
# Fix: '**/${fpat}**' matches at any path depth and works for both
# top-level and nested entries.

@test "regression: file-form allowlist excludes nested-path commits from history scan" {
  mkdir -p docs/fn-atlas/captures
  echo "token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234" \
    > docs/fn-atlas/captures/snapshot.md
  cat > .security-audit-allowlist <<'EOF'
fn-atlas/captures/
EOF
  git add -A && git commit -q -m "add nested fixture"

  run bash "$SCRIPT" --history-only
  # Pre-fix: status would be 1 (CRITICAL on the nested commit because the
  # broken '**fn-atlas/captures/*' glob fails to exclude the path).
  # Post-fix: status is 0 — '**/fn-atlas/captures/**' bridges any depth.
  [ "$status" -eq 0 ]
}

@test "regression: file-form allowlist still excludes top-level paths from history scan" {
  echo "token = ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234" > leaky.txt
  cat > .security-audit-allowlist <<'EOF'
leaky.txt
EOF
  git add -A && git commit -q -m "add top-level fixture"

  run bash "$SCRIPT" --history-only
  # The new '**/${fpat}**' glob must continue to match top-level paths
  # (no leading subdir). Guards against over-correcting the nested fix.
  [ "$status" -eq 0 ]
}


# =========================================================================
# Flag tests
# =========================================================================

@test "--files-only skips history scan" {
  local user
  user=$(whoami)
  # Put PII in history only (not in current files)
  git commit --allow-empty -q -m "path /Users/$user/bad"

  run bash "$SCRIPT" --files-only
  [ "$status" -eq 0 ]  # Files are clean
}

@test "--history-only skips file scan" {
  echo "SECRET=bad" > .env
  git add .env && git commit -q -m "add env"

  # History has the .env commit, but --history-only checks messages/diffs, not filenames
  # The .env file should NOT be caught by history-only (that's a file scan)
  run bash "$SCRIPT" --history-only
  # History scan looks for PII patterns and secrets in diffs
  # The word "SECRET" alone doesn't match our token patterns
  [ "$status" -eq 0 ]
}

@test "JSON output is valid JSON" {
  set -e
  echo "SECRET=bad" > .env
  git add .env && git commit -q -m "add env"

  result=$(bash "$SCRIPT" --json 2>/dev/null || true)
  echo "$result" | jq -e '.findings | length > 0'
  echo "$result" | jq -e '.pass == false'
}
