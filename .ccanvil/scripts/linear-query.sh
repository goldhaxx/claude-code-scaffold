#!/usr/bin/env bash
# linear-query.sh — Linear GraphQL client wrapper for bash scripts.
#
# BTS-164: provides curl + jq + LINEAR_API_KEY env-var auth so docs-check.sh,
# radar-gather, operations.sh resolvers, etc. can read+write Linear without
# routing through MCP. Uniform path for scripts and skills; closes the
# read-path provider asymmetry (cmd_idea_count was opening the local JSONL
# log directly even on Linear-routed projects).
#
# Subcommands ship in phases:
#   v1 — viewer, list-issues, get-issue, list-states, list-labels, save-issue
#
# Auth: requires LINEAR_API_KEY in the environment for every subcommand
# except --help. Endpoint defaults to https://api.linear.app/graphql; tests
# override via LINEAR_QUERY_ENDPOINT.
#
# Exit codes:
#   0 — success
#   2 — usage / configuration error (missing env var, unknown subcommand)
#   3 — runtime error (network, API error response, malformed JSON)

set -euo pipefail

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: linear-query.sh <subcommand> [args...]

Subcommands:
  viewer                              Auth smoke test — returns {id, name} for the authenticated user.
  list-issues  [flags]                List issues. Flags: --project, --team, --state, --label, --limit.
  get-issue    <id>                   Fetch one issue by identifier (e.g., BTS-164).
  list-states  [flags]                List workflow states. Flags: --team.
  list-labels  [flags]                List labels. Flags: --team.
  save-issue   [flags]                Create or update an issue. Flags: --id, --title, --description,
                                      --state, --priority, --labels, --project, --team, --parent-id,
                                      --duplicate-of.

Environment:
  LINEAR_API_KEY        Required for every subcommand except --help.
                        Generate one at https://linear.app/settings/api.
  LINEAR_QUERY_ENDPOINT Optional override (default: https://api.linear.app/graphql).
                        Tests use this to point at a stub endpoint.

Exit codes:
  0  ok
  2  usage / configuration error (missing env var, unknown subcommand, bad flags)
  3  runtime error (network, API error, malformed response)
EOF
}

# Print to stderr and exit. First arg = exit code, rest = message.
_die() {
  local code="$1"; shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

# Walk up from $PWD looking for .git; when found AND LINEAR_API_KEY is unset
# AND a sibling .env exists, source it. Eliminates the per-shell
# `set -a; source .env; set +a` ritual that has to run before every Bash
# tool invocation that touches Linear (BTS-167).
#
# Walks $PWD only — not the script's own dirname — so test isolation works
# (tests cd into a controlled tmpdir) and the user-intent "my project's
# .env, found from where I am" stays the contract. If the script is invoked
# while $PWD is outside any git tree, no auto-source fires.
#
# Already-exported LINEAR_API_KEY always wins; .env is only consulted when
# the env var is unset (no override of operator intent).
_load_env_if_needed() {
  if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    return 0
  fi
  local dir
  dir="$(pwd -P 2>/dev/null)" || return 0
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -d "$dir/.git" ]]; then
      if [[ -f "$dir/.env" ]]; then
        # `set -a` exports every var assigned during the source step; the
        # script ships with `set -euo pipefail`, so a parse error in .env
        # surfaces as a non-zero exit rather than a silent skip (AC-6).
        # Note: `set +a` is unreachable when the source aborts under
        # `set -e` — that's harmless because the script exits entirely.
        # Don't refactor this into a sourced helper without revisiting
        # this scope leak.
        set -a
        # shellcheck disable=SC1091
        . "$dir/.env"
        set +a
      fi
      return 0
    fi
    dir="$(dirname "$dir")"
  done
}

# Every subcommand calls this before doing any work. Exits 2 with a clear
# remediation hint when the env var is missing.
_require_api_key() {
  _load_env_if_needed
  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    _die 2 "LINEAR_API_KEY not set. Export it (export LINEAR_API_KEY=<key>) or add LINEAR_API_KEY=<key> to .env at the project root. Generate a key at https://linear.app/settings/api."
  fi
}

# POST a GraphQL query to Linear. Args:
#   $1 — the GraphQL query string
#   $2 — variables JSON (object), defaults to {}
# Emits the parsed response payload (the .data field) on stdout.
# Exits 3 with the GraphQL error message on stderr if the response carries
# an "errors" array.
_post_graphql() {
  local query="$1"
  # NOTE: do NOT use ${2:-{}} — bash parameter expansion reads only to the
  # first '}', making the default '{' and leaving a stray '}' as literal.
  local variables="${2:-}"
  [[ -z "$variables" ]] && variables='{}'
  local endpoint="${LINEAR_QUERY_ENDPOINT:-https://api.linear.app/graphql}"

  local body
  body=$(jq -nc --arg q "$query" --argjson v "$variables" '{query:$q,variables:$v}')

  local response rc
  response=$(
    curl -sS -X POST "$endpoint" \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body"
  )
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _die 3 "linear-query: HTTP request failed (curl exit $rc)"
  fi

  # GraphQL errors: surface the first one and exit 3. Linear's WAF and auth
  # layer both return 200 OK with an errors array, so HTTP status alone is
  # not a reliable signal.
  local err
  err=$(printf '%s' "$response" | jq -r '.errors[0].message // empty' 2>/dev/null || true)
  if [[ -n "$err" ]]; then
    _die 3 "linear-query: GraphQL error: $err"
  fi

  printf '%s' "$response" | jq '.data'
}

# -----------------------------------------------------------------------------
# Subcommand stubs (filled in by later steps in the BTS-164 plan)
# -----------------------------------------------------------------------------

cmd_viewer() {
  _require_api_key
  local query='query { viewer { id name } }'
  _post_graphql "$query" | jq '.viewer'
}

cmd_list_issues() {
  _require_api_key

  local project="" team="" state="" label="" limit="50"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --team)    team="$2";    shift 2 ;;
      --state)   state="$2";   shift 2 ;;
      --label)   label="$2";   shift 2 ;;
      --limit)   limit="$2";   shift 2 ;;
      *) _die 2 "list-issues: unknown flag: $1" ;;
    esac
  done

  # Compose the IssueFilter object incrementally so callers only pay for
  # the dimensions they constrain. Linear's filter shape is canonical:
  # field: { type/name/id: { eq: value } }, with labels using `some`.
  local filter='{}'
  if [[ -n "$project" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$project" '. + {project:{name:{eq:$v}}}')
  fi
  if [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi
  if [[ -n "$state" ]]; then
    # BTS-175: auto-detect UUID-shaped values and filter by state.id.eq
    # rather than state.type.eq. Linear's IssueFilter accepts either form;
    # `save-issue --state` already treats the value as a stateId UUID, so
    # this aligns the list-issues semantics for symmetric state plumbing.
    if [[ "$state" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      filter=$(printf '%s' "$filter" | jq --arg v "$state" '. + {state:{id:{eq:$v}}}')
    else
      filter=$(printf '%s' "$filter" | jq --arg v "$state" '. + {state:{type:{eq:$v}}}')
    fi
  fi
  if [[ -n "$label" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$label" '. + {labels:{some:{name:{eq:$v}}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" --argjson n "$limit" '{filter:$f, first:$n}')

  local query='query ($filter: IssueFilter, $first: Int) {
    issues(filter: $filter, first: $first) {
      nodes {
        identifier title priority createdAt updatedAt
        state { name type id }
        labels { nodes { name } }
      }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.issues.nodes[] | {
    id: .identifier,
    title: .title,
    status: .state.name,
    statusType: .state.type,
    priority: (.priority // null),
    createdAt: .createdAt,
    updatedAt: .updatedAt,
    labels: [.labels.nodes[].name]
  }]'
}

cmd_get_issue() {
  _require_api_key
  if [[ $# -lt 1 ]]; then
    _die 2 "get-issue requires an issue identifier (e.g., BTS-164)"
  fi
  local id="$1"

  local variables
  variables=$(jq -nc --arg id "$id" '{id:$id}')

  local query='query ($id: String!) {
    issue(id: $id) {
      identifier title priority createdAt updatedAt description
      state { name type id }
      labels { nodes { name } }
    }
  }'

  _post_graphql "$query" "$variables" | jq '.issue | {
    id: .identifier,
    title: .title,
    status: .state.name,
    statusType: .state.type,
    priority: (.priority // null),
    createdAt: .createdAt,
    updatedAt: .updatedAt,
    description: .description,
    labels: [.labels.nodes[].name]
  }'
}

cmd_list_states() {
  _require_api_key
  local team=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team) team="$2"; shift 2 ;;
      *) _die 2 "list-states: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: WorkflowStateFilter) {
    workflowStates(filter: $filter) {
      nodes { id name type }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.workflowStates.nodes[] | {id, name, type}]'
}

cmd_list_labels() {
  _require_api_key
  local team="" team_id="" workspace_scoped=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --team)             team="$2";    shift 2 ;;
      --team-id)          team_id="$2"; shift 2 ;;
      --workspace-scoped) workspace_scoped=true; shift ;;
      *) _die 2 "list-labels: unknown flag: $1" ;;
    esac
  done

  # BTS-170: --workspace-scoped is mutually exclusive with team scoping —
  # workspace-scoped means "no team filter," not "team filter AND null."
  if $workspace_scoped && [[ -n "$team_id" || -n "$team" ]]; then
    _die 2 "list-labels: --workspace-scoped is mutually exclusive with --team / --team-id"
  fi

  # BTS-166: --team-id wins over --team for scoping (mirrors save-issue
  # precedence). Allows multi-team-aware callers to pass the already-known
  # UUID and skip a name-resolution roundtrip while still scoping the label
  # filter precisely.
  local filter='{}'
  if $workspace_scoped; then
    # BTS-170: Linear's NullableTeamFilter uses a direct boolean for `null`,
    # not the BooleanComparator wrapper. `{team:{null:true}}` matches labels
    # where team is null (workspace-scoped). Verified against live API
    # 2026-04-26 — `{team:{null:{eq:true}}}` is rejected.
    filter=$(printf '%s' "$filter" | jq '. + {team:{null:true}}')
  elif [[ -n "$team_id" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team_id" '. + {team:{id:{eq:$v}}}')
  elif [[ -n "$team" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$team" '. + {team:{name:{eq:$v}}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: IssueLabelFilter) {
    issueLabels(filter: $filter) {
      nodes { id name }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.issueLabels.nodes[] | {id, name}]'
}

# BTS-166: name-based create flags in save-issue need NAME→ID lookups for
# team and project. Both follow the same shape as list-labels: optional
# --name filter, returns [{id, name}].

cmd_list_teams() {
  _require_api_key
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) _die 2 "list-teams: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$name" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$name" '. + {name:{eq:$v}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: TeamFilter) {
    teams(filter: $filter) {
      nodes { id name key }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.teams.nodes[] | {id, name, key}]'
}

cmd_list_projects() {
  _require_api_key
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) _die 2 "list-projects: unknown flag: $1" ;;
    esac
  done

  local filter='{}'
  if [[ -n "$name" ]]; then
    filter=$(printf '%s' "$filter" | jq --arg v "$name" '. + {name:{eq:$v}}')
  fi

  local variables
  variables=$(jq -n --argjson f "$filter" '{filter:$f}')

  local query='query ($filter: ProjectFilter) {
    projects(filter: $filter) {
      nodes { id name slugId }
    }
  }'

  _post_graphql "$query" "$variables" | jq '[.projects.nodes[] | {id, name, slugId}]'
}

cmd_save_issue() {
  _require_api_key

  # Mode selector: presence of --id triggers update; absence triggers create.
  # Caller-provided IDs only — name resolution (team/project/label NAMES → IDs)
  # is the resolver's job in Step 7. The wrapper stays focused on transport.
  local id="" title="" description="" state=""
  local team_id="" project_id="" parent_id="" duplicate_of=""
  local priority="" label_ids=""
  local input_json=""
  local team_name="" project_name="" labels_csv=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)            id="$2";           shift 2 ;;
      --title)         title="$2";        shift 2 ;;
      --description)   description="$2";  shift 2 ;;
      --state)         state="$2";        shift 2 ;;
      --team-id)       team_id="$2";      shift 2 ;;
      --project-id)    project_id="$2";   shift 2 ;;
      --parent-id)     parent_id="$2";    shift 2 ;;
      --duplicate-of)  duplicate_of="$2"; shift 2 ;;
      --priority)      priority="$2";     shift 2 ;;
      --label-ids)     label_ids="$2";    shift 2 ;;
      --input-json)    input_json="$2";   shift 2 ;;
      --team)          team_name="$2";    shift 2 ;;
      --project)       project_name="$2"; shift 2 ;;
      --labels)        labels_csv="$2";   shift 2 ;;
      *) _die 2 "save-issue: unknown flag: $1" ;;
    esac
  done

  # BTS-166 AC-2: name-based create flags. Resolve NAME→ID via list-teams /
  # list-projects / list-labels when --*-id wasn't passed. -id flags take
  # precedence on collision (caller knows the UUID; skip the extra roundtrip).
  #
  # Round-trip cost for the all-names-no-ids path: 3 GraphQL calls before
  # the issueCreate (teams → projects → labels [+ optional teams again
  # internal to list-labels' team-name filter]). For high-frequency callers
  # that already have IDs in config, prefer --*-id to skip the lookups.
  if [[ -z "$team_id" && -n "$team_name" ]]; then
    team_id=$(cmd_list_teams --name "$team_name" | jq -r '.[0].id // ""')
    if [[ -z "$team_id" ]]; then
      _die 2 "save-issue: --team '$team_name' did not resolve to a team id"
    fi
  fi
  if [[ -z "$project_id" && -n "$project_name" ]]; then
    project_id=$(cmd_list_projects --name "$project_name" | jq -r '.[0].id // ""')
    if [[ -z "$project_id" ]]; then
      _die 2 "save-issue: --project '$project_name' did not resolve to a project id"
    fi
  fi
  if [[ -z "$label_ids" && -n "$labels_csv" ]]; then
    # Resolve each NAME → ID with proper team scoping. Prefer the resolved
    # team_id (UUID) when present; fall back to team_name. Without scoping,
    # multi-team workspaces could silently pick the wrong label when two
    # teams share a label name.
    local resolved_ids=""
    local IFS_old="$IFS"; IFS=,
    for label_name in $labels_csv; do
      local label_filter=()
      if [[ -n "$team_id" ]]; then
        label_filter=(--team-id "$team_id")
      elif [[ -n "$team_name" ]]; then
        label_filter=(--team "$team_name")
      fi
      local lid
      # Safe-expand for empty label_filter under `set -u` (bash 4.x quirk).
      lid=$(cmd_list_labels "${label_filter[@]+"${label_filter[@]}"}" | jq -r --arg n "$label_name" '.[] | select(.name == $n) | .id' | head -1)
      # BTS-170: when team-scoping was set but the team-scoped lookup found
      # no label by that name, fall through to a workspace-scoped lookup.
      # Workspace-scoped labels (team:null) are NOT included in the team
      # filter; without this fallback, e.g. `--labels idea` fails on
      # workspaces where 'idea' is workspace-scoped, not team-scoped.
      if [[ -z "$lid" && ${#label_filter[@]} -gt 0 ]]; then
        lid=$(cmd_list_labels --workspace-scoped | jq -r --arg n "$label_name" '.[] | select(.name == $n) | .id' | head -1)
      fi
      if [[ -z "$lid" ]]; then
        _die 2 "save-issue: --labels '$label_name' did not resolve to a label id"
      fi
      resolved_ids="${resolved_ids:+${resolved_ids},}${lid}"
    done
    IFS="$IFS_old"
    label_ids="$resolved_ids"
  fi

  # BTS-166 AC-1: --input-json -  reads a JSON object from stdin and seeds the
  # input object. CLI flags layered on top, so command-line values override
  # stdin fields on key collision (matches the typical "config + override" UX).
  local stdin_input='{}'
  if [[ -n "$input_json" ]]; then
    if [[ "$input_json" == "-" ]]; then
      stdin_input=$(cat)
    else
      _die 2 "save-issue: --input-json currently supports only '-' (stdin)"
    fi
    # Validate it's a JSON object before merging.
    if ! printf '%s' "$stdin_input" | jq -e 'type == "object"' >/dev/null 2>&1; then
      _die 2 "save-issue: --input-json - did not receive a valid JSON object on stdin"
    fi
  fi

  # Build the input object incrementally — Linear's IssueCreateInput and
  # IssueUpdateInput share the same field names for everything we set.
  # BTS-166: seed the input object from stdin-JSON when present. CLI flags
  # below merge on top, so flag values override stdin fields on collision.
  local input="$stdin_input"
  if [[ -n "$title" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$title" '. + {title:$v}')
  fi
  if [[ -n "$description" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$description" '. + {description:$v}')
  fi
  if [[ -n "$state" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$state" '. + {stateId:$v}')
  fi
  if [[ -n "$team_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$team_id" '. + {teamId:$v}')
  fi
  if [[ -n "$project_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$project_id" '. + {projectId:$v}')
  fi
  if [[ -n "$parent_id" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$parent_id" '. + {parentId:$v}')
  fi
  if [[ -n "$duplicate_of" ]]; then
    input=$(printf '%s' "$input" | jq --arg v "$duplicate_of" '. + {duplicateOf:$v}')
  fi
  if [[ -n "$priority" ]]; then
    input=$(printf '%s' "$input" | jq --argjson v "$priority" '. + {priority:$v}')
  fi
  if [[ -n "$label_ids" ]]; then
    # CSV → JSON array of strings.
    local arr
    arr=$(printf '%s' "$label_ids" | jq -R 'split(",")')
    input=$(printf '%s' "$input" | jq --argjson v "$arr" '. + {labelIds:$v}')
  fi

  if [[ -z "$id" ]]; then
    # Create mode. Required: title (in $title or stdin-JSON), team_id (same).
    # Linear's schema requires both; emitting a clear error here surfaces the
    # gap before the API call. Check the merged input, not just the flag vars,
    # so stdin-JSON-only callers (BTS-166) aren't flagged spuriously.
    if [[ -z "$(echo "$input" | jq -r '.title // ""')" ]]; then
      _die 2 "save-issue create requires --title"
    fi
    if [[ -z "$(echo "$input" | jq -r '.teamId // ""')" ]]; then
      _die 2 "save-issue create requires --team-id (use list-teams to discover)"
    fi

    local query='mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) { success issue { identifier title } }
    }'
    local variables
    variables=$(jq -n --argjson i "$input" '{input:$i}')
    _post_graphql "$query" "$variables" | jq '.issueCreate.issue | {
      id: .identifier,
      title: .title
    }'
  else
    # Update mode. Linear's issueUpdate accepts the same input shape minus
    # creation-only fields (teamId is rejected for update, but we already
    # don't add it for the update path's expected callers).
    local query='mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) { success issue { identifier title } }
    }'
    local variables
    variables=$(jq -n --arg id "$id" --argjson i "$input" '{id:$id, input:$i}')
    _post_graphql "$query" "$variables" | jq '.issueUpdate.issue | {
      id: .identifier,
      title: .title
    }'
  fi
}

# -----------------------------------------------------------------------------
# Dispatcher
# -----------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  local subcommand="$1"; shift

  case "$subcommand" in
    -h|--help|help)
      usage
      exit 0
      ;;
    viewer)       cmd_viewer       "$@" ;;
    list-issues)  cmd_list_issues  "$@" ;;
    get-issue)    cmd_get_issue    "$@" ;;
    list-states)  cmd_list_states  "$@" ;;
    list-labels)  cmd_list_labels  "$@" ;;
    list-teams)    cmd_list_teams    "$@" ;;
    list-projects) cmd_list_projects "$@" ;;
    save-issue)   cmd_save_issue   "$@" ;;
    *)
      _die 2 "Unknown subcommand: $subcommand. Run 'linear-query.sh --help' for usage."
      ;;
  esac
}

main "$@"
