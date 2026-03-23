# Implementation Plan: Modular Tool Integration Layer

> Feature: tool-integration
> Created: 1774299081
> Spec hash: 19d3f4c3
> Based on: docs/spec.md

## Objective

Build `scripts/operations.sh` — a mechanism-agnostic routing layer that resolves scaffold operations to local bash commands or external MCP tool instructions based on `.claude/scaffold.json` config.

## Sequence

### Step 1: Script skeleton + unknown operation error (AC-10)
- **Test:** `operations.sh resolve unknown.op` exits 1 with stderr containing `ERROR: unknown operation "unknown.op"`. `operations.sh` with no args prints usage and exits 2.
- **Implement:** Create `scripts/operations.sh` with shebang, `set -euo pipefail`, `usage()`, arg parsing (`resolve` subcommand + operation name), and a hardcoded operations registry that rejects unknown operations.
- **Files:** `scripts/operations.sh` (new), `tests/operations.bats` (new)
- **Verify:** `bats tests/operations.bats`

### Step 2: No-config local fallback + invalid JSON error (AC-11, AC-9)
- **Test 1:** `operations.sh resolve backlog.list` with no `.claude/scaffold.json` present outputs JSON with `"provider":"local","mechanism":"bash"` and a non-empty `invocation.command`. Exit 0.
- **Test 2:** `operations.sh resolve backlog.list` with invalid JSON in `.claude/scaffold.json` exits 1 with stderr `ERROR: .claude/scaffold.json is not valid JSON`.
- **Implement:** Config reading logic: check file existence (missing = all local), validate JSON with `jq empty`, extract integrations key (missing = all local). Define local adapter for `backlog.list` with command pointing to `docs-check.sh list-specs`.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 3: Full operations taxonomy — all 17 local resolves (AC-1)
- **Test:** For each of the 17 operations (`backlog.{list,create,prioritize,get}`, `spec.{read,write,list,activate,complete}`, `plan.{read,write}`, `checkpoint.{read,write}`, `status.{get,update}`, `pr.{create,list}`, `review.run`), verify `operations.sh resolve <op>` with no config returns JSON with `"provider":"local","mechanism":"bash"` and a non-empty `invocation.command`. Exit 0.
- **Implement:** Add local adapter definitions for all 17 operations. Map each to the corresponding `docs-check.sh` subcommand or file path. Operations without a current local implementation get placeholder commands.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 4: Config parsing — MCP resolve for backlog.list (AC-2)
- **Test:** Given fixture `scaffold.json` with `integrations.routing.backlog: "linear"` and `providers.linear: {mechanism: "mcp", project: "Test", team: "TestTeam"}`, `operations.sh resolve backlog.list` outputs JSON with `"provider":"linear","mechanism":"mcp"`, invocation containing `"tool":"mcp__claude_ai_Linear__list_issues"` and params from provider config, and a contract with output fields.
- **Implement:** Config-aware routing: read `integrations.routing.<group>` via jq, look up provider in `integrations.providers`, build MCP adapter response with tool name, params, and output contract. Define Linear MCP adapter for `backlog.list`.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 5: Missing provider error + partial routing fallback (AC-3, AC-4)
- **Test 1:** Fixture with `routing.backlog: "linear"` but no `providers.linear` exits 1 with stderr `ERROR: provider "linear" is configured for backlog but has no entry in integrations.providers`.
- **Test 2:** Fixture with only `routing.backlog: "linear"` (no other routing entries), `operations.sh resolve spec.read` returns local adapter, `operations.sh resolve backlog.list` returns linear MCP adapter.
- **Implement:** Provider existence validation before building MCP response. Fallback logic: missing routing entry for a group defaults to local.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 6: Local adapter schema compatibility (AC-5)
- **Test:** Run `operations.sh resolve backlog.list` (local mode), extract the command from invocation, execute it against a fixture `docs/specs/` directory with test spec files. Compare the output schema against direct `docs-check.sh list-specs` run on the same directory. Both produce arrays of `{feature_id, status, created}`.
- **Implement:** Ensure the local `backlog.list` command passes `--project-dir` or docs-dir argument so it targets the correct specs directory. Adjust command string if needed.
- **Files:** `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 7: backlog.get with Linear MCP routing + contract mapping (AC-6)
- **Test:** Given linear routing config, `operations.sh resolve backlog.get test-id` outputs JSON with `"mechanism":"mcp"`, `"tool":"mcp__claude_ai_Linear__get_issue"`, params including the id argument, and a contract mapping Linear fields (`identifier`, `title`, `state.name`, `priority`) to scaffold fields (`id`, `title`, `status`, `priority`).
- **Implement:** Add `backlog.get` MCP adapter with parameterized id from the resolve argument. Define field mapping in the contract object.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 8: Extensible mechanism field (AC-12)
- **Test:** Given fixture with `providers.custom: {mechanism: "webhook", url: "https://example.com"}` and `routing.backlog: "custom"`, `operations.sh resolve backlog.list` outputs JSON with `"mechanism":"webhook"`. The script does not reject the unknown mechanism value.
- **Implement:** Ensure mechanism field is read from provider config and passed through as-is. No validation against a closed set. For non-`mcp` external providers, output a generic invocation with the provider config as params.
- **Files:** `scripts/operations.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats`

### Step 9: scaffold.json integrations schema + scaffold-sync tracking (AC-8)
- **Test 1:** `.claude/scaffold.json` with both `features` and `integrations` keys passes `jq empty`.
- **Test 2:** `grep -q 'scaffold.json' scripts/scaffold-sync.sh` confirms `.claude/scaffold.json` is in TRACKED_PATTERNS.
- **Implement:** Update `.claude/scaffold.json` to include empty `integrations` key (no routing, no providers — local-only default). Add `.claude/scaffold.json` to `TRACKED_PATTERNS` array in `scaffold-sync.sh`.
- **Files:** `.claude/scaffold.json`, `scripts/scaffold-sync.sh`, `tests/operations.bats`
- **Verify:** `bats tests/operations.bats && bats tests/scaffold-sync.bats`

### Step 10: Wire /catchup command (AC-7)
- **Test:** `grep -q "operations.sh resolve backlog.list" .claude/commands/catchup.md` returns 0.
- **Implement:** Update step 0c in `.claude/commands/catchup.md`: call `operations.sh resolve backlog.list`, check the mechanism in the JSON response, if `bash` execute the command directly, if `mcp` instruct Claude to call the specified MCP tool with the given params.
- **Files:** `.claude/commands/catchup.md`
- **Verify:** `grep -q "operations.sh resolve backlog.list" .claude/commands/catchup.md`

### Step 11: Documentation update (CLAUDE.md, GUIDE.md)
- **Test:** `grep -q "operations.sh" CLAUDE.md && grep -q "operations.sh" GUIDE.md`
- **Implement:** Add `operations.sh resolve <operation>` to CLAUDE.md commands block (node section, above `HUB-MANAGED-START`). Add to GUIDE.md Command Reference table (hub section). Add integrations config schema documentation to GUIDE.md Configuration Layers section.
- **Files:** `CLAUDE.md`, `GUIDE.md`
- **Verify:** Full test suite passes: `bats tests/`

## Risks

- **macOS bash 3:** macOS ships bash 3 which lacks associative arrays. Use `case` statements for operation registry and adapter lookups instead.
- **Config schema evolution:** The `scaffold.json` integrations schema is new and will evolve. Use jq's `// "default"` fallback everywhere — unknown keys ignored, missing keys get defaults.
- **MCP tool name accuracy:** Linear MCP tool names must match what Claude Code exposes. Verify against `settings.local.json` allowlist entries.
- **Local adapter fidelity:** The `backlog.list` local command must produce output identical to `docs-check.sh list-specs`. Step 6 directly validates this with schema comparison.

## Definition of Done

- [ ] All 12 acceptance criteria from spec pass
- [ ] All existing tests still pass
- [ ] `operations.sh` follows established script pattern (set -euo pipefail, subcommand dispatch, JSON output)
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
