#!/usr/bin/env bats
# Tests for the idea-triage-native feature.
# Covers the five-state lifecycle (triage → backlog / icebox / canceled / duplicate),
# agentic mutations via state IDs, Icebox review, and legacy migration.

OPS="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/operations.sh"
DOCS_CHECK="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/docs-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  PROJECT=$(mktemp -d)
  mkdir -p "$PROJECT/.ccanvil"
}

teardown() {
  rm -rf "$PROJECT"
}

# =========================================================================
# Step 1 — Local-log status vocabulary (triage/backlog/icebox/canceled/duplicate)
# Covers AC-1 (local half): capture writes status="triage".
# =========================================================================

@test "Step 1: cmd_idea_add writes status=triage (not legacy new)" {
  run bash "$DOCS_CHECK" idea-add "capture one" "$PROJECT"
  [ "$status" -eq 0 ]
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  [ -f "$ideas_log" ]
  run jq -r '.status' "$ideas_log"
  [ "$status" -eq 0 ]
  [ "$output" = "triage" ]
}

@test "Step 1: cmd_idea_list --status triage includes legacy status=new entries" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  cat > "$ideas_log" <<'EOF'
{"uid":"l1","created":1,"status":"new","title":"legacy","body":"legacy"}
{"uid":"n1","created":2,"status":"triage","title":"native","body":"native"}
{"uid":"b1","created":3,"status":"backlog","title":"promoted","body":"promoted"}
EOF
  run bash "$DOCS_CHECK" idea-list --status triage "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e '[.[].id] | contains(["l1", "n1"])'
}

@test "Step 1: cmd_idea_count sums legacy + new vocab into new-named counters" {
  local ideas_log="$PROJECT/.ccanvil/ideas.log"
  # 10 entries: one per legacy status, one per new-vocab status.
  # Expected collapse: new→triage, promoted→backlog, parked→icebox,
  # dismissed→canceled, merged→duplicate. Total count: 10.
  cat > "$ideas_log" <<'EOF'
{"uid":"l1","created":1,"status":"new","title":"a","body":"a"}
{"uid":"l2","created":2,"status":"promoted","title":"b","body":"b"}
{"uid":"l3","created":3,"status":"parked","title":"c","body":"c"}
{"uid":"l4","created":4,"status":"dismissed","title":"d","body":"d"}
{"uid":"l5","created":5,"status":"merged","title":"e","body":"e"}
{"uid":"n1","created":6,"status":"triage","title":"f","body":"f"}
{"uid":"n2","created":7,"status":"backlog","title":"g","body":"g"}
{"uid":"n3","created":8,"status":"icebox","title":"h","body":"h"}
{"uid":"n4","created":9,"status":"canceled","title":"i","body":"i"}
{"uid":"n5","created":10,"status":"duplicate","title":"j","body":"j"}
EOF
  run bash "$DOCS_CHECK" idea-count "$PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 10'
  echo "$output" | jq -e '.triage == 2'
  echo "$output" | jq -e '.backlog == 2'
  echo "$output" | jq -e '.icebox == 2'
  echo "$output" | jq -e '.canceled == 2'
  echo "$output" | jq -e '.duplicate == 2'
}
