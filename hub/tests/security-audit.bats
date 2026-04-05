#!/usr/bin/env bats
# Tests for scripts/security-audit.sh
#
# Each test creates an isolated git repo with specific scenarios.

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
  echo "SECRET=bad" > .env
  git add .env && git commit -q -m "add env"

  result=$(bash "$SCRIPT" --json 2>/dev/null || true)
  echo "$result" | jq -e '.findings | length > 0'
  echo "$result" | jq -e '.pass == false'
}
