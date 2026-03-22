Review the current uncommitted changes using the code-reviewer sub-agent.

Delegate to the `code-reviewer` agent with this task:
"Review all uncommitted changes in this repository. Check for correctness, test coverage, security issues, performance concerns, and adherence to project conventions defined in CLAUDE.md."

After the code review completes, run the security audit (deterministic):

```bash
bash scripts/security-audit.sh --files-only
```

Then do a quick self-review per `.claude/rules/self-review.md`: were there any stochastic operations in this session that should become deterministic? If so, note them briefly.

Summarize all three checks (code review, security audit, self-review) and recommend whether to commit or what to fix first.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
