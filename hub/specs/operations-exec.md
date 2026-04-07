# Feature: operations.sh exec subcommand

> Feature: operations-exec
> Created: 1775601660
> Status: Complete

## Summary

Add an `exec` subcommand to operations.sh that resolves an operation AND executes it in one call (for bash-mechanism operations). This eliminates the resolve→parse→dispatch pattern that currently requires Claude to read JSON, check the mechanism, and conditionally run the command — a stochastic sequence for a deterministic operation.

## Job To Be Done

**When** a slash command needs to execute a routed operation (e.g., `/catchup` listing the backlog),
**I want** a single script call that resolves and executes,
**So that** Claude doesn't spend context on JSON parsing and conditional dispatch.

## Acceptance Criteria

- [ ] **AC-1:** `operations.sh exec <operation>` resolves the operation and, if mechanism is `bash`, executes the command and outputs its result directly.
- [ ] **AC-2:** If mechanism is `mcp`, `exec` outputs the resolution JSON (same as `resolve`) so Claude can call the MCP tool. Exit code 0.
- [ ] **AC-3:** If mechanism is `bash` and the command fails, `exec` propagates the exit code.
- [ ] **AC-4:** `exec` with an unknown operation exits with error (same as `resolve`).
- [ ] **AC-5:** All hub bats tests pass (354+).
- [ ] **AC-6:** New tests cover exec with bash mechanism, exec with MCP mechanism, and exec with invalid operation.

## Affected Files

| File | Change |
|------|--------|
| `preset/.ccanvil/scripts/operations.sh` | Add `cmd_exec` function and dispatch case |
| `hub/tests/operations.bats` | New tests for exec subcommand |
