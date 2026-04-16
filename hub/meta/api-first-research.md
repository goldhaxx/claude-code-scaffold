# API-First Database Access: Research Summary

> Origin: taxes project (2026-04-15)
> Trigger: Direct SQL UPDATE bypassed FastAPI PATCH endpoint, skipping computed fields (deductible_amount, schedule_c_line), causing silent data corruption.

## The Problem

When an AI agent (or any automated tool) has direct database access alongside an API, it will take the shortest path — direct SQL. This bypasses business logic, computed fields, validations, and audit trails that the API enforces. The corruption is silent: data looks correct in the DB but is semantically wrong because derived fields weren't recomputed.

## Industry Precedents

### Bezos API Mandate (Amazon, 2002)
"All teams will henceforth expose their data and functionality through service interfaces. There will be no other form of interprocess communication allowed: no direct linking, no direct reads of another team's data store, no shared-memory model, no back-doors whatsoever. The only communication allowed is via service interface calls over the network. Anyone who doesn't do this will be fired."

**Key insight:** The mandate wasn't about technology — it was about ownership. When only one service writes to a table, that service owns the invariants.

### Stripe's DocDB Proxy
All database operations go through a Go proxy server. Engineers never touch databases directly. Every query is logged, rate-limited, and authorized through the proxy layer. This is the "single writer principle" applied at the infrastructure level.

### Google's NoPe (No Persons) Suite
Eliminates direct human access to production systems entirely:
- **Multi-Party Authorization (MPA):** No single person can authorize a production change
- **Access on Demand (AoD):** Temporary, audited access with automatic expiration
- **Safe Proxies:** All database interactions go through proxy services that enforce business rules
- **Binary Authorization for Borg (BAB):** Only reviewed, approved code runs in production

### GitLab Production Database Incident (2017)
An engineer ran `rm -rf` on a production database directory during a late-night debugging session. Direct access + fatigue + no guardrails = catastrophic data loss. Led to GitLab's shift toward proxy-based access and strict separation of concerns.

## Principles (Tech-Stack Agnostic)

### 1. Single Writer Principle
Only one service/process owns writes to a given table. The API is that writer. Everything else is a reader.

### 2. API Dogfooding
Internal tools, scripts, and AI agents use the same API as external consumers. If the API can't do something, the API gets enhanced — not bypassed.

### 3. Mutation Gating
A deterministic enforcement layer (hook, proxy, firewall rule) blocks direct mutations. This is not advisory — it physically prevents the bypass. The gate should:
- Block: INSERT, UPDATE, DELETE, DROP, ALTER, REPLACE
- Allow: SELECT, PRAGMA, schema inspection
- Allow: Schema setup (CREATE TABLE, migrations)
- Provide: An explicit bypass mechanism for emergencies (audited)

### 4. Reads Are Free
Read-only queries (SELECT, PRAGMA, .schema, .tables) are always allowed. They're essential for debugging, analysis, and understanding the data. The restriction is on mutations only.

## Enforcement Mechanisms

### For Claude Code / AI Agents
**PreToolUse hooks** — deterministic shell scripts that pattern-match tool inputs before execution:
- Check if the command targets a database file (`.db`, `sqlite3`, `psql`, etc.)
- Allow reads (SELECT, PRAGMA, schema inspection)
- Block mutations (INSERT, UPDATE, DELETE, DROP, ALTER, REPLACE)
- Strip CREATE TABLE/INDEX/VIEW before checking (schema setup is infrastructure)
- Provide an explicit bypass (`API_BYPASS=1`) for emergencies
- Zero false positives: only trigger when DB context is present (prevents `grep "UPDATE"` from blocking)

### For Production Systems
- **Database proxies:** Stripe DocDB, Teleport, StrongDM — all queries go through a proxy that enforces rules
- **Ephemeral credentials:** HashiCorp Vault issues short-lived, scoped DB credentials
- **SQL change workflows:** Bytebase, Flyway — schema changes go through review pipelines
- **Network-level isolation:** DB only accessible from the API service, not from developer machines

## Compliance Alignment

| Standard | Relevant Requirement |
|----------|---------------------|
| SOC 2 | CC6.1 — Logical access controls; direct unaudited DB access is a finding |
| HIPAA | Access controls on PHI; audit trails required for all data access |
| PCI-DSS | Requirement 7 — Restrict access to cardholder data by business need-to-know |
| GDPR | Article 25 — Data protection by design; Article 30 — Records of processing |

All effectively mandate that direct, unaudited database access is a compliance violation for sensitive data.

## Implementation Template

### CLAUDE.md Section (adapt per project)
```markdown
## API-First Data Access

All data mutations go through [FRAMEWORK] endpoints. The database is never mutated directly.

1. **Use the API.** Every INSERT, UPDATE, and DELETE goes through an endpoint in [API_FILE].
2. **Enhance the API first.** If an endpoint doesn't exist, build it.
3. **Direct SQL is a last resort.** Only with explicit user approval. Prefix with `API_BYPASS=1`.
4. **Reads are fine.** SELECT, PRAGMA, schema inspection — always allowed.
5. **Schema setup is fine.** CREATE TABLE, migrations — infrastructure, not data mutations.

A PreToolUse hook (`protect-db.sh`) enforces this deterministically.
```

### PreToolUse Hook (parameterize DB_PATTERN)
The hook needs three things:
1. **Context detection:** Is this command targeting a database? (match on tool name, file extension, CLI command)
2. **Mutation detection:** Does the command contain mutation keywords? (case-insensitive, after stripping schema setup)
3. **Bypass mechanism:** Is the explicit override present? (`API_BYPASS=1`)

### Test Suite Pattern
Test cases should cover:
- Mutations blocked (6+ keywords x case variations)
- Reads allowed (SELECT, PRAGMA, schema inspection)
- Schema setup allowed (CREATE TABLE, piped .sql files)
- False positives avoided (grep/echo/git containing keywords)
- Bypass works (API_BYPASS=1)
- Non-DB commands pass through

## Proven Implementations

| Project | Stack | API | Hook | Status |
|---------|-------|-----|------|--------|
| taxes | FastAPI + SQLite | `src/app.py` | `.claude/hooks/protect-db.sh` | Production, 24-case test suite |
| fieldnation-toolbox | FastAPI + SQLite | (adapted from taxes pre-guardrails) | **Missing — needs protect-db.sh** | At risk — agent already running direct SQL mutations |

**fieldnation-toolbox context:** This project adopted the FastAPI/SQLite stack by having Claude review the taxes project directly, but this happened before protect-db.sh and the API-first CLAUDE.md rules were added. The agent in that project is already executing direct SQL mutations against the database with no gating. This is the canonical example of why tech stack distribution needs to exist — ad-hoc stack borrowing creates drift when the source project evolves its guardrails.

## Sources

- Bezos API Mandate: Steve Yegge's "Google Platforms Rant" (2011, describing 2002 mandate)
- Stripe DocDB: Stripe engineering blog, "Online migrations at scale"
- Google NoPe: Google Security Blog, "Building Secure and Reliable Systems" (O'Reilly, 2020)
- GitLab incident: GitLab postmortem, "GitLab.com database incident" (2017-01-31)
- Teleport: goteleport.com — certificate-based database access proxy
- Bytebase: bytebase.com — SQL change workflow with DBA review
- HashiCorp Vault: vaultproject.io — dynamic secrets and ephemeral credentials
