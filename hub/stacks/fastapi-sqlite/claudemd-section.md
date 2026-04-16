<!-- STACK:fastapi-sqlite-START -->
## API-First Data Access

All data mutations go through FastAPI endpoints. The database is never mutated directly.

1. **Use the API.** Every INSERT, UPDATE, and DELETE goes through an API endpoint. Endpoints own business logic: computed fields, validations, and side effects.
2. **Enhance the API first.** If an endpoint doesn't exist for what you need, build it. Add the route, the Pydantic model, the handler — then call it.
3. **Direct SQL is a last resort.** Only with explicit user approval and a stated reason why the API cannot handle it. Prefix the command with `API_BYPASS=1` to pass the PreToolUse hook.
4. **Reads are fine.** `SELECT`, `PRAGMA`, `.schema`, `.tables` — read-only queries for debugging and analysis are always allowed.
5. **Schema setup is fine.** `CREATE TABLE`, migration scripts, and schema imports are infrastructure, not data mutations.
<!-- STACK:fastapi-sqlite-END -->
