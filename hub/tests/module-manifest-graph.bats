#!/usr/bin/env bats
# BTS-269: cmd_graph — cross-substrate cohesion graph emitter.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.ccanvil/scripts/module-manifest.sh"
}

# AC-7: unknown --format → exit 2 with stderr error.
@test "graph: unknown --format exits 2 with supported-formats stderr" {
  run bash "$SCRIPT" graph --format yaml
  [ "$status" -eq 2 ]
  [[ "$output" =~ "unknown --format" ]]
  [[ "$output" =~ "json" ]]
}

# AC-1: empty/missing allowlist → empty envelope, status ok.
@test "graph: empty allowlist emits empty envelope (exit 0)" {
  set -e
  empty_allow="$BATS_TEST_TMPDIR/empty-allow.txt"
  : > "$empty_allow"
  run bash "$SCRIPT" graph --allowlist "$empty_allow"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.nodes == []'
  echo "$output" | jq -e '.edges == []'
  echo "$output" | jq -e '.cross_cluster_edges == []'
  echo "$output" | jq -e '.status == "ok"'
}

# AC-2 + AC-3 + AC-5: small allowlist with cross-cluster edge surfaces correctly.
@test "graph: tiny allowlist with command→agent edge → 1 cross_cluster_edge" {
  set -e
  tiny="$BATS_TEST_TMPDIR/tiny-allow.txt"
  cat > "$tiny" <<EOAL
.claude/agents/code-reviewer.md
.claude/commands/pr.md
EOAL
  run bash "$SCRIPT" graph --allowlist "$tiny"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.nodes | length == 2'
  # The pr command's manifest declares code-reviewer as a caller — agent ↔ command crosses.
  echo "$output" | jq -e '.cross_cluster_edges | length >= 1'
  echo "$output" | jq -e '[.cross_cluster_edges[] | select(.from_cluster == "command" and .to_cluster == "agent")] | length >= 1'
}

# AC-2: cluster classification matches path prefix.
@test "graph: nodes assigned to correct clusters" {
  set -e
  multi="$BATS_TEST_TMPDIR/multi-allow.txt"
  cat > "$multi" <<EOAL
.ccanvil/scripts/module-manifest.sh:cmd_extract
.claude/hooks/protect-main.sh
.claude/skills/spec/SKILL.md:spec
.claude/rules/tdd.md
.claude/agents/code-reviewer.md
.claude/commands/pr.md
EOAL
  run bash "$SCRIPT" graph --allowlist "$multi"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "script")] | length == 1'
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "hook")] | length == 1'
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "skill")] | length == 1'
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "rule")] | length == 1'
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "agent")] | length == 1'
  echo "$output" | jq -e '[.nodes[] | select(.cluster == "command")] | length == 1'
}

# AC-6: --format dot emits Graphviz source.
@test "graph: --format dot emits digraph G with subgraph clusters" {
  set -e
  tiny="$BATS_TEST_TMPDIR/dot-allow.txt"
  cat > "$tiny" <<EOAL
.claude/agents/code-reviewer.md
.claude/commands/pr.md
EOAL
  run bash "$SCRIPT" graph --format dot --allowlist "$tiny"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "digraph G" ]]
  [[ "$output" =~ "subgraph cluster_agent" ]]
  [[ "$output" =~ "subgraph cluster_command" ]]
  [[ "$output" =~ "color=red" ]]   # cross-cluster edges styled red
}
