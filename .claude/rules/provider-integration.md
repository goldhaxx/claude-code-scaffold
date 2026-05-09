---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/provider-migration-decision.md
manifest:
  id: provider-integration
  purpose: Codify the BTS-183 substrate-provider rule — anything reachable from operations.sh that integrates with an external provider exposing both MCP and shell-to-API surfaces (REST/GraphQL/CLI) MUST use the shell-to-API surface, never MCP. MCP is reserved for ad-hoc operator queries from interactive Claude sessions via claude.ai connectors. Captures the 7-row tradeoff matrix that justifies the choice and the OVERRIDE-pattern stubbing convention for tests.
  input:
    - "read-only: rule consumed when adding new operations.sh resolvers or extending wrappers"
  output:
    - "behavior-shape: forces new substrate verbs to land as shell-to-API subcommands first; rejects mechanism: mcp branches in operations.sh"
  side-effect:
    - "shapes-substrate-design (no file mutation; behavioral influence)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=mixed-mode-substrate-drift-then-200-LOC-dead-code-sweep | mitigation=/review-flag-or-stasis-determinism-review"
  contract:
    - http-for-substrate
    - mcp-for-operator-tools-only
    - new-verbs-land-as-wrapper-subcommands-first
    - never-add-mechanism-mcp-resolution-for-new-verbs
    - OVERRIDE-pattern-stubbing-for-tests
  anchor:
    - BTS-164 (Linear daily-driver migration MCP→http)
    - BTS-166 (substrate dispatch via http)
    - BTS-167 (.env auto-source)
    - BTS-183 (rule + dead-code sweep)
    - BTS-203 (LINEAR_QUERY_OVERRIDE stubbing pattern)
    - BTS-252 (manifest seed)
    - BTS-387 (atomized for tier-0)
---

# Provider Integration

Substrate uses **http (shell-to-API)**. MCP is reserved for ad-hoc operator queries inside interactive Claude sessions.

When integrating ccanvil substrate (anything reachable from `.ccanvil/scripts/operations.sh`) with an external provider that exposes both an MCP server AND a shell-to-API surface (REST/GraphQL/CLI), **always use the shell-to-API surface — never MCP**. New verbs land as wrapper subcommands first (e.g., `linear-query.sh save-issue`), then the operations.sh resolver references them.

**When adding a new operation to `operations.sh`:** never add a `mechanism: "mcp"` branch for a new verb. If the provider isn't yet wrapper-integrated, write the wrapper FIRST. Test via the OVERRIDE pattern (`LINEAR_QUERY_OVERRIDE`, etc.) — env var swap to stubbed script, mirrors BTS-203.

For the full http-vs-MCP tradeoff matrix, BTS-183 dead-code sweep context, and how-to-apply detail: see evidence anchor `docs/research/provider-migration-decision.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
