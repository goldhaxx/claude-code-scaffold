#!/usr/bin/env bats
# BTS-116: ccanvil-sync.sh broadcast-resolve-auto — algorithmic resolution
# of .claude/ccanvil.json conflicts.
#
# Each test creates a minimal hub + node fixture pair with a synthetic
# lockfile (no full `init` invocation needed — the subcommand only reads
# .ccanvil/ccanvil.lock for hub_source and updates files[*] entries via
# the existing pull-apply primitives).

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/ccanvil-sync.sh"

setup() {
  HUB=$(mktemp -d)
  NODE=$(mktemp -d)

  mkdir -p "$HUB/.claude" "$NODE/.claude" "$NODE/.ccanvil"

  # Synthetic lockfile: hub_source + one tracked file entry.
  jq -n --arg hub "$HUB" '{
    hub_source: $hub,
    files: {
      ".claude/ccanvil.json": {
        hub_hash: "placeholder",
        local_hash: "placeholder",
        status: "modified"
      }
    }
  }' > "$NODE/.ccanvil/ccanvil.lock"
}

teardown() {
  rm -rf "$HUB" "$NODE"
}

# Helper: write JSON to both hub and node ccanvil.json.
_write_files() {
  local hub_json="$1"
  local local_json="$2"
  echo "$hub_json" > "$HUB/.claude/ccanvil.json"
  echo "$local_json" > "$NODE/.claude/ccanvil.json"
}

# =========================================================================
# AC-1: identical content → take-hub, applied=true
# =========================================================================

@test "AC-1: identical local and hub → resolution=take-hub, applied=true, exit 0" {
  set -e
  _write_files '{"hub":{"path":"~/projects/ccanvil"}}' '{"hub":{"path":"~/projects/ccanvil"}}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "take-hub"'
  echo "$output" | jq -e '.applied == true'
  echo "$output" | jq -e '.reason == "content-identical"'
  echo "$output" | jq -e '.file == ".claude/ccanvil.json"'
}

# =========================================================================
# AC-2: local-superset-of-hub → keep-local, applied=true
# =========================================================================

@test "AC-2: local has extra top-level key (hub-side values match) → keep-local, applied=true" {
  set -e
  _write_files \
    '{"hub":{"path":"~/projects/ccanvil"}}' \
    '{"hub":{"path":"~/projects/ccanvil"},"routing":{"idea":"linear"},"node_uuid":"abc-123"}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "keep-local"'
  echo "$output" | jq -e '.applied == true'
  echo "$output" | jq -e '.reason == "local-superset-of-hub"'
}

@test "AC-2 nested: local has extra key inside shared object → keep-local" {
  # Note: this is a key-level superset at top-level. Within shared keys,
  # values must deep-equal. Nested-extras INSIDE a shared key are a
  # value-divergence, not a superset.
  set -e
  _write_files \
    '{"hub":{"path":"~/p"}}' \
    '{"hub":{"path":"~/p"},"stacks":["fastapi-sqlite"]}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "keep-local"'
}

# =========================================================================
# AC-3: value-divergence on shared key → requires-review, exit 3
# =========================================================================

@test "AC-3: shared key with different values → requires-review, exit 3" {
  set -e   # BTS-127: halt on any assertion failure
  _write_files \
    '{"hub":{"path":"~/projects/ccanvil"}}' \
    '{"hub":{"path":"~/projects/different"}}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.resolution == "requires-review"'
  echo "$output" | jq -e '.reason == "value-divergence"'
  echo "$output" | jq -e '.applied == false'
  echo "$output" | jq -e '.divergent_keys | length > 0'
}

# =========================================================================
# AC-4: local removed key present in hub → requires-review
# =========================================================================

@test "AC-4: local removed a top-level key hub has → requires-review with removed_keys" {
  set -e   # BTS-127: halt on any assertion failure
  _write_files \
    '{"hub":{"path":"~/p"},"feature":"x"}' \
    '{"hub":{"path":"~/p"}}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.resolution == "requires-review"'
  echo "$output" | jq -e '.reason == "local-removed-keys"'
  echo "$output" | jq -e '.removed_keys | index("feature") != null'
}

# =========================================================================
# AC-5: --dry-run does not mutate
# =========================================================================

@test "AC-5: --dry-run on AC-1 case emits applied=false and leaves files untouched" {
  set -e
  _write_files '{"hub":{"path":"~/p"}}' '{"hub":{"path":"~/p"}}'
  pre_lock=$(cat "$NODE/.ccanvil/ccanvil.lock")
  pre_local=$(cat "$NODE/.claude/ccanvil.json")
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "take-hub"'
  echo "$output" | jq -e '.applied == false'
  [ "$(cat "$NODE/.ccanvil/ccanvil.lock")" = "$pre_lock" ]
  [ "$(cat "$NODE/.claude/ccanvil.json")" = "$pre_local" ]
}

# =========================================================================
# AC-6: not-a-node → exit 2
# =========================================================================

@test "AC-6: invoked outside a node (no .ccanvil/ccanvil.lock) → exit 2" {
  NOTNODE=$(mktemp -d)
  cd "$NOTNODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "not a ccanvil node"
  rm -rf "$NOTNODE"
}

# =========================================================================
# AC-7: no conflict (file matches hub) → resolution=no-conflict
# =========================================================================

@test "AC-7: both files missing → no-conflict, applied=false, exit 0" {
  set -e
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "no-conflict"'
  echo "$output" | jq -e '.applied == false'
}

# =========================================================================
# AC-8: drift-guard — keep-local updates lockfile
# =========================================================================

@test "AC-8: keep-local resolution updates lockfile.hub_hash to match hub" {
  set -e
  _write_files \
    '{"hub":{"path":"~/p"}}' \
    '{"hub":{"path":"~/p"},"extra":"key"}'
  cd "$NODE"
  run bash "$SCRIPT" broadcast-resolve-auto
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolution == "keep-local"'
  hub_hash_after=$(jq -r '.files[".claude/ccanvil.json"].hub_hash' "$NODE/.ccanvil/ccanvil.lock")
  hub_hash_expected=$(shasum -a 256 "$HUB/.claude/ccanvil.json" | awk '{print $1}')
  [ "$hub_hash_after" = "$hub_hash_expected" ]
}
