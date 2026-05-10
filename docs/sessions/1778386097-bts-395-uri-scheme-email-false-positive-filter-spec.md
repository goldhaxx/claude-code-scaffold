# Feature: Filter URI-scheme prefixes out of the email-finding scan

> Feature: bts-395-uri-scheme-email-false-positive-filter
> Work: linear:BTS-395
> Created: 1778384019
> Subject: Filter URI-scheme prefixes out of the email-finding scan
> Status: In Progress

## Summary

`security-audit.sh`'s `scan_tracked_files_emails` flags lines containing connection-string URLs (`postgresql://USER:PASSWORD@HOST.REGION.aws.neon.tech/...`, `mongodb://...`, etc.) as MEDIUM `email` findings. The regex `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` matches the URI's `userinfo@host` substring even though the line is not an email at all. Every downstream node tracking a connection-string-shaped value in `.env.example` / README / config currently has to add a `.env.example::email::` allowlist entry to silence the noise. Skip lines whose `$content` contains a known DB-protocol URI-scheme prefix at the upstream so the workaround disappears across the fleet.

## Job To Be Done

**When** a downstream node tracks a database connection string template,
**I want to** run `bash .ccanvil/scripts/security-audit.sh` without it firing MEDIUM `email` findings on the URI's `userinfo@host` substring,
**So that** CI stays clean without per-node allowlist boilerplate while real email addresses keep getting flagged.

## Acceptance Criteria

- [ ] **AC-1:** **Given** a git repo tracking a `postgresql://USER:PASSWORD@HOST.REGION.aws.neon.tech/db` line in any tracked file, **when** `bash .ccanvil/scripts/security-audit.sh` runs, **then** no `email` finding is emitted for that line and exit is 0 (assuming the repo is otherwise clean).
- [ ] **AC-2:** When `mongodb://`, `mongodb+srv://`, `redis://`, `rediss://`, `mysql://`, `mssql://`, `amqp://`, `amqps://`, or `postgres://` connection strings appear on tracked lines (each with userinfo), no `email` finding is emitted for any of them. The filter covers the 10 DB-shape schemes documented in BTS-395.
- [ ] **AC-3 (no regression on real emails):** When a tracked file contains a real email like `admin@company.com` on a line WITHOUT any URI-scheme prefix, the audit STILL emits MEDIUM `email` for that line.
- [ ] **AC-4 (mixed-content line granularity):** When a tracked file has both a connection-string line AND a separate real-email line, the connection-string line is silently skipped and the real-email line still flags. Per-line filtering — not file-wide.
- [ ] **AC-5 (forward-compat):** Existing downstream nodes whose `.security-audit-allowlist` carries `.env.example::email::` (the pre-fix workaround) remain functional — the entry becomes redundant but harmless. No new error or warn surfaces from the unused allowlist line.
- [ ] **AC-6 (existing exclusions preserved):** Existing exclusions for `noreply@`, `@example.(com|org|net)`, and `@users.noreply` continue to silence those patterns. The new URI-scheme filter is additive, not a replacement.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/security-audit.sh` (`scan_tracked_files_emails` \~L241) | Modified — per-line URI-scheme prefix filter |
| `hub/tests/security-audit.bats` | Modified — add 6 ACs covering AC-1 through AC-6 |

## Dependencies

* **Requires:** none — self-contained substrate fix.
* **Blocked by:** none.

## Out of Scope

* Filtering `http://` / `https://` userinfo URLs (`https://user:pass@host.com/path`). The ticket's evidence is DB-connection-string-shaped; broader URL-userinfo filtering is a known additional false-positive surface that can be a follow-up if downstream sessions surface it. Stay narrow to the documented bug.
* Tightening the email regex itself (negative-lookbehind on `:` etc.) — `grep -E` doesn't support lookaround, and the cost-of-coverage analysis matches the BTS-394 shape: per-line filter is simpler and easier to test.
* Removing existing downstream `.env.example::email::` allowlist entries — out-of-scope coordination work; entries are harmless after the fix.

## Implementation Notes

* Pattern: per-line `case "$content" in` filter at the loop level (lines 244-251 of `security-audit.sh`), mirroring the BTS-394 carve-out shape. Place the case statement before the existing exclusion check (line 248) so URI-scheme lines short-circuit `continue` BEFORE both the `is_allowlisted` and `noreply@` filters fire.
* Suggested shape: `case "$content" in *postgresql://*|*postgres://*|*mongodb://*|*mongodb+srv://*|*redis://*|*rediss://*|*mysql://*|*mssql://*|*amqp://*|*amqps://*) continue ;; esac`. Single line, deterministic, readable.
* Manifest impact: script-level `# @manifest` block at line 14 already lists "real-looking emails" as a scanner target. After this fix, a brief qualifier in the `purpose:` line is appropriate (e.g., "(connection-string URL substrings excluded per BTS-395)") — same rationale as the BTS-394 manifest update. No new entry-point or side-effect.
* Test design: mirror the BTS-394 test patterns. Each test creates a fixture with the URL/email pattern, commits it (the email scanner reads `git ls-files`), runs `--files-only`, asserts on `$status` and grep on `$output`. RED-then-GREEN: AC-1/2/4 should FAIL pre-impl (the connection-string lines fire `email`); AC-3/5/6 are regression guards.
