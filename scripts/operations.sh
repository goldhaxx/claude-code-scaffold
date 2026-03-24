#!/usr/bin/env bash
# operations.sh — Mechanism-agnostic routing layer for scaffold operations.
#
# Reads .claude/scaffold.json and dispatches each scaffold operation to a
# pluggable provider via any supported mechanism (bash, mcp, cli, api, etc.).
# Zero-config projects resolve everything to local bash adapters.
#
# Exit codes:
#   0 — success
#   1 — operation error (unknown op, missing provider, invalid config)
#   2 — usage error
#
# Usage:
#   operations.sh resolve <operation> [args...] [--project-dir DIR]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

PROJECT_DIR="."

# ---------------------------------------------------------------------------
# Operations registry — all 17 defined operations
# ---------------------------------------------------------------------------

is_valid_operation() {
  case "$1" in
    backlog.list|backlog.create|backlog.prioritize|backlog.get) return 0 ;;
    spec.read|spec.write|spec.list|spec.activate|spec.complete) return 0 ;;
    plan.read|plan.write) return 0 ;;
    checkpoint.read|checkpoint.write) return 0 ;;
    status.get|status.update) return 0 ;;
    pr.create|pr.list) return 0 ;;
    review.run) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage: operations.sh resolve <operation> [args...] [--project-dir DIR]

Operations:
  backlog.{list,create,prioritize,get}
  spec.{read,write,list,activate,complete}
  plan.{read,write}
  checkpoint.{read,write}
  status.{get,update}
  pr.{create,list}
  review.run
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CMD=""
OPERATION=""
OP_ARGS=""

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    resolve|merge-config)
      CMD="$1"; shift
      # Next positional arg is the operation name
      if [[ $# -gt 0 && "$1" != --* ]]; then
        OPERATION="$1"; shift
      fi
      # Next positional arg (if any) is the operation argument (e.g., issue ID)
      if [[ $# -gt 0 && "$1" != --* ]]; then
        OP_ARGS="$1"; shift
      fi
      ;;
    --project-dir)
      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$CMD" ]] && usage
[[ "$CMD" == "resolve" && -z "$OPERATION" ]] && usage

# ---------------------------------------------------------------------------
# Config reading
# ---------------------------------------------------------------------------

CONFIG_FILE=""

# merge_scaffold_config — Merge scaffold.json (hub) with scaffold.local.json (node).
#
# Outputs the effective config JSON to stdout. Uses RFC 7396 deep merge
# via jq's * operator — node wins on conflict (permissive, Option A).
#
# Exit 0: success (even if both files are missing — outputs {}).
# Exit 1: a file exists but contains invalid JSON.
merge_scaffold_config() {
  local dir="$1"
  local hub_file="$dir/.claude/scaffold.json"
  local local_file="$dir/.claude/scaffold.local.json"

  # Neither file exists → empty config
  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    echo '{}'
    return 0
  fi

  # Validate hub file if it exists
  if [[ -f "$hub_file" ]]; then
    if ! jq empty "$hub_file" 2>/dev/null; then
      echo "ERROR: .claude/scaffold.json is not valid JSON" >&2
      return 1
    fi
  fi

  # Validate local file if it exists
  if [[ -f "$local_file" ]]; then
    if ! jq empty "$local_file" 2>/dev/null; then
      echo "ERROR: .claude/scaffold.local.json is not valid JSON" >&2
      return 1
    fi
  fi

  # Only hub file → return hub content
  if [[ -f "$hub_file" && ! -f "$local_file" ]]; then
    jq '.' "$hub_file"
    return 0
  fi

  # Only local file → return local content
  if [[ ! -f "$hub_file" && -f "$local_file" ]]; then
    jq '.' "$local_file"
    return 0
  fi

  # Both files exist → deep merge (node wins on conflict)
  jq -s '.[0] * .[1]' "$hub_file" "$local_file"
}

read_config() {
  local hub_file="$PROJECT_DIR/.claude/scaffold.json"
  local local_file="$PROJECT_DIR/.claude/scaffold.local.json"

  # No config files → all local (not an error)
  if [[ ! -f "$hub_file" && ! -f "$local_file" ]]; then
    CONFIG_FILE=""
    return 0
  fi

  # Merge configs into a temp file so downstream jq queries work unchanged
  local merged
  merged=$(merge_scaffold_config "$PROJECT_DIR") || exit 1

  CONFIG_FILE=$(mktemp)
  trap 'rm -f "$CONFIG_FILE"' EXIT
  echo "$merged" > "$CONFIG_FILE"
}

# Extract the routing group from an operation name (e.g., "backlog.list" → "backlog")
operation_group() {
  echo "${1%%.*}"
}

# ---------------------------------------------------------------------------
# Local adapter definitions
# ---------------------------------------------------------------------------

local_adapter() {
  local op="$1"
  local cmd="" output_contract=""

  case "$op" in
    # --- backlog ---
    backlog.list)
      cmd="scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","created"]'
      ;;
    backlog.create)
      cmd="scripts/docs-check.sh create-spec"
      output_contract='["feature_id","status"]'
      ;;
    backlog.prioritize)
      cmd="scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","priority"]'
      ;;
    backlog.get)
      cmd="cat docs/specs/${OP_ARGS}.md"
      output_contract='["feature_id","status","created","body"]'
      ;;
    # --- spec ---
    spec.read)
      cmd="cat docs/spec.md"
      output_contract='["feature_id","status","body"]'
      ;;
    spec.write)
      cmd="cp docs/templates/spec.md docs/spec.md"
      output_contract='["feature_id"]'
      ;;
    spec.list)
      cmd="scripts/docs-check.sh list-specs"
      output_contract='["feature_id","status","created"]'
      ;;
    spec.activate)
      cmd="scripts/docs-check.sh activate"
      output_contract='["feature_id","branch"]'
      ;;
    spec.complete)
      cmd="scripts/docs-check.sh complete"
      output_contract='["feature_id","status"]'
      ;;
    # --- plan ---
    plan.read)
      cmd="cat docs/plan.md"
      output_contract='["feature_id","spec_hash","body"]'
      ;;
    plan.write)
      cmd="cp docs/templates/plan.md docs/plan.md"
      output_contract='["feature_id"]'
      ;;
    # --- checkpoint ---
    checkpoint.read)
      cmd="cat docs/checkpoint.md"
      output_contract='["feature_id","plan_hash","body"]'
      ;;
    checkpoint.write)
      cmd="cp docs/templates/checkpoint.md docs/checkpoint.md"
      output_contract='["feature_id"]'
      ;;
    # --- status ---
    status.get)
      cmd="scripts/docs-check.sh status"
      output_contract='["spec","plan","checkpoint"]'
      ;;
    status.update)
      cmd="scripts/docs-check.sh validate"
      output_contract='["result","details"]'
      ;;
    # --- pr ---
    pr.create)
      cmd="gh pr create --draft"
      output_contract='["url","number"]'
      ;;
    pr.list)
      cmd="gh pr list --json number,title,state"
      output_contract='["number","title","state"]'
      ;;
    # --- review ---
    review.run)
      cmd="echo '{\"status\":\"not_implemented\",\"concerns\":[]}'"
      output_contract='["status","concerns"]'
      ;;
  esac

  jq -n --arg cmd "$cmd" --argjson output "$output_contract" \
    '{"provider":"local","mechanism":"bash","invocation":{"command":$cmd},"contract":{"output":$output}}'
}

# ---------------------------------------------------------------------------
# MCP adapter definitions (Linear)
# ---------------------------------------------------------------------------

linear_mcp_adapter() {
  local op="$1" provider_config="$2" op_args="$3"
  local tool="" output_contract="" field_map=""
  local project team
  project=$(echo "$provider_config" | jq -r '.project // ""')
  team=$(echo "$provider_config" | jq -r '.team // ""')

  case "$op" in
    backlog.list)
      tool="mcp__claude_ai_Linear__list_issues"
      output_contract='["id","title","status","priority"]'
      field_map='{"identifier":"id","title":"title","state.name":"status","priority":"priority"}'
      jq -n --arg tool "$tool" --arg project "$project" --arg team "$team" \
        --argjson output "$output_contract" --argjson fmap "$field_map" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"project":$project,"team":$team}},"contract":{"output":$output,"field_map":$fmap}}'
      ;;
    backlog.get)
      tool="mcp__claude_ai_Linear__get_issue"
      output_contract='["id","title","status","priority","description"]'
      field_map='{"identifier":"id","title":"title","state.name":"status","priority":"priority"}'
      jq -n --arg tool "$tool" --arg id "$op_args" \
        --argjson output "$output_contract" --argjson fmap "$field_map" \
        '{"provider":"linear","mechanism":"mcp","invocation":{"tool":$tool,"params":{"id":$id}},"contract":{"output":$output,"field_map":$fmap}}'
      ;;
    *)
      # Unsupported operation for this provider — fall back to local
      local_adapter "$op"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# External provider adapter dispatch
# ---------------------------------------------------------------------------

external_adapter() {
  local op="$1" provider_name="$2" mechanism="$3" provider_config="$4" op_args="$5"

  case "$provider_name" in
    linear)
      linear_mcp_adapter "$op" "$provider_config" "$op_args"
      ;;
    *)
      # Generic passthrough for unknown providers
      jq -n --arg provider "$provider_name" --arg mechanism "$mechanism" \
        --argjson config "$provider_config" \
        '{"provider":$provider,"mechanism":$mechanism,"invocation":{"config":$config},"contract":{"output":[]}}'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_resolve() {
  local op="$1"

  # Validate operation name
  if ! is_valid_operation "$op"; then
    echo "ERROR: unknown operation \"$op\"" >&2
    exit 1
  fi

  # Read config (sets CONFIG_FILE or leaves empty)
  read_config

  # No config or no integrations key → local adapter
  if [[ -z "$CONFIG_FILE" ]]; then
    local_adapter "$op"
    return 0
  fi

  # Check for integrations.routing.<group>
  local group
  group=$(operation_group "$op")
  local routed_provider
  routed_provider=$(jq -r --arg g "$group" '.integrations.routing[$g] // "local"' "$CONFIG_FILE")

  if [[ "$routed_provider" == "local" ]]; then
    local_adapter "$op"
    return 0
  fi

  # Look up the provider config
  local provider_config
  provider_config=$(jq -c --arg p "$routed_provider" '.integrations.providers[$p] // null' "$CONFIG_FILE")

  if [[ "$provider_config" == "null" ]]; then
    echo "ERROR: provider \"$routed_provider\" is configured for $group but has no entry in integrations.providers" >&2
    exit 1
  fi

  local mechanism
  mechanism=$(echo "$provider_config" | jq -r '.mechanism // "bash"')

  external_adapter "$op" "$routed_provider" "$mechanism" "$provider_config" "$OP_ARGS"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$CMD" in
  resolve) cmd_resolve "$OPERATION" ;;
  merge-config) merge_scaffold_config "$PROJECT_DIR" ;;
  *) usage ;;
esac
