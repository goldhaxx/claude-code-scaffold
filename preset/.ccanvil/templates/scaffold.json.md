# scaffold.json — Configuration Template

`scaffold.json` is the hub-tracked configuration file for feature toggles and integration defaults.

## Override Pattern

Project-specific overrides go in `.claude/scaffold.local.json` (gitignored, never synced). The effective config is a deep merge of both files — local wins on conflict.

**Hub file** (`scaffold.json` — tracked, auto-updated on pull):
```json
{
  "features": {
    "pr_review": false
  }
}
```

**Local override** (`scaffold.local.json` — gitignored, node-only):
```json
{
  "integrations": {
    "routing": { "backlog": "linear" },
    "providers": {
      "linear": { "mechanism": "mcp", "project": "My Project", "team": "My Team" }
    }
  }
}
```

**Merge rule:** `jq -s '.[0] * .[1]'` — RFC 7396 deep merge, local wins. Arrays are replaced (not concatenated).

## Scripts that read the effective config

- `operations.sh resolve <op>` — reads routing and provider config
- `docs-check.sh config-get <key>` — reads feature toggles
