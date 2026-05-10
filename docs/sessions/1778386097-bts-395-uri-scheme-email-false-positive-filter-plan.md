# Implementation Plan: Filter URI-scheme prefixes out of the email-finding scan

> Feature: bts-395-uri-scheme-email-false-positive-filter
> Work: linear:BTS-395
> Created: 1778384019
> Spec hash: 63a94a0a
> Based on: docs/spec.md

## Objective

Stop `scan_tracked_files_emails` from flagging connection-string lines (`postgresql://`, `mongodb://`, `redis://`, `mysql://`, `amqp://`, etc.) as MEDIUM `email` findings, while preserving real-email flagging, the existing `noreply@`/`@example.*` exclusions, and the allowlist surface.

## Sequence

Each step is one red-green-refactor cycle. Tests precede implementation. Mirrors the BTS-394 ship pattern (carve-out at the loop level, deterministic `case` statement).

### Step 1: AC-1 — postgres connection string no longer flags as email

* **Test:** In `hub/tests/security-audit.bats`, add `@test "BTS-395 AC-1: postgresql:// connection string does not flag as email"`. Fixture: `echo 'DATABASE_URL=postgresql://USER:PASSWORD@HOST.REGION.aws.neon.tech/db' > .env.example; git add -A && git commit -q -m "add postgres conn"`. Run `bash "$SCRIPT" --files-only`; assert `[ "$status" -eq 0 ]` and `! echo "$output" | grep -q "email"`.
* **Implement:** In `.ccanvil/scripts/security-audit.sh`'s `scan_tracked_files_emails` (\~L241), add a per-line `case "$content" in *postgresql://*|*postgres://*|*mongodb://*|*mongodb+srv://*|*redis://*|*rediss://*|*mysql://*|*mssql://*|*amqp://*|*amqps://*) continue ;; esac` immediately after the `IFS=:` read line and BEFORE the `local detail=` line.
* **Files:** `.ccanvil/scripts/security-audit.sh`, `hub/tests/security-audit.bats`.
* **Verify:** `bats hub/tests/security-audit.bats --filter 'BTS-395 AC-1'` RED on pre-impl, GREEN post-impl.

### Step 2: AC-2 — the other 9 schemes carved likewise

* **Test:** Add `@test "BTS-395 AC-2: mongodb / redis / mysql / amqp / postgres connection strings do not flag as email"`. Multiple fixtures, one per scheme (postgres://, mongodb://, mongodb+srv://, redis://, rediss://, mysql://, mssql://, amqp://, amqps://). All on separate lines in the same `.env.example`. Assert `[ "$status" -eq 0 ]` and `! echo "$output" | grep -q "email"`.
* **Implement:** No code change — Step 1's case statement already covers all 10 schemes. This step exists to FAIL if Step 1's pattern was typoed (e.g., missed `mongodb+srv://`).
* **Files:** `hub/tests/security-audit.bats`.
* **Verify:** `bats … --filter 'BTS-395 AC-2'` GREEN.

### Step 3: AC-3 — real emails still flag (regression guard)

* **Test:** Add `@test "BTS-395 AC-3: real email on a non-URI line still flags MEDIUM email"`. Fixture: `echo 'CONTACT=admin@company.com' > config.txt`. Assert `[ "$status" -eq 1 ]` and `output` contains `email` finding for `admin@company.com`.
* **Implement:** No code change — case statement only matches lines containing URI-scheme prefixes; lines without them fall through to existing logic.
* **Files:** `hub/tests/security-audit.bats`.
* **Verify:** `bats … --filter 'BTS-395 AC-3'` GREEN.

### Step 4: AC-4 — mixed-content per-line granularity

* **Test:** Add `@test "BTS-395 AC-4: mixed file — connection string skipped, real email on separate line still flags"`. Fixture: file with TWO lines, one `postgresql://...@host.com/db` and one `CONTACT=admin@company.com`. Assert `[ "$status" -eq 1 ]` (because of the real email), exactly 1 `email` finding (only on the contact line), and the finding's location is the email line (not the postgres line).
* **Implement:** No code change — the per-line filter scope guarantees granularity by construction. This Step is a structural assertion that the loop processes lines independently.
* **Files:** `hub/tests/security-audit.bats`.
* **Verify:** `bats … --filter 'BTS-395 AC-4'` GREEN.

### Step 5: AC-5 — legacy downstream allowlist entry stays harmless

* **Test:** Add `@test "BTS-395 AC-5: legacy .env.example::email:: allowlist entry parses without error"`. Fixture: `.env.example` with a postgres URL AND a `.security-audit-allowlist` containing `.env.example::email::`. Assert exit 0 and no `WARN`/`ERROR`/`malformed` on stderr.
* **Implement:** No code change — allowlist parser already accepts the triple form; the URI-scheme filter runs before allowlist matching, making the entry redundant but legal.
* **Files:** `hub/tests/security-audit.bats`.
* **Verify:** `bats … --filter 'BTS-395 AC-5'` GREEN with `--separate-stderr`.

### Step 6: AC-6 — existing exclusions preserved

* **Test:** Add `@test "BTS-395 AC-6: noreply@ and @example.com exclusions still silence email findings"`. Fixture: tracked file with `noreply@github.com`, `bot@example.com`, `me@users.noreply.github.com`. Assert exit 0, no `email` findings.
* **Implement:** No code change — the URI-scheme filter is additive; the existing `grep -qE 'noreply@|@example\.(com|org|net)|@users\.noreply'` exclusion at line 248 still runs for non-URI-scheme lines.
* **Files:** `hub/tests/security-audit.bats`.
* **Verify:** `bats … --filter 'BTS-395 AC-6'` GREEN. Existing test "tilde paths do not trigger PII detection" and similar exclusion tests must remain GREEN.

### Step 7: Manifest update + full bats verification

* **Test:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json`. Confirm `drift == []`, `coverage.covered == coverage.total`, `status == "ok"`.
* **Implement:** Update `security-audit.sh` line 14 `# @manifest` `purpose:` to append "(connection-string URL substrings excluded per BTS-395)" alongside the existing BTS-394 qualifier.
* **Files:** `.ccanvil/scripts/security-audit.sh`.
* **Verify:** Manifest validate clean. Run `bash .ccanvil/scripts/bats-report.sh --parallel --progress` for full-suite gate (BTS-118/383 single-invocation).

## Risks

* **Substring false-suppression:** A non-URI line that happens to contain a string like `postgresql://` (e.g., a doc paragraph saying "if you use postgresql:// scheme...") would also be skipped. Acceptable — such lines are documentation prose, not real emails. The case statement matches substring-anywhere by design.
* **Scheme list drift:** New DB schemes (`clickhouse://`, `cockroachdb://`, etc.) would not be covered until added. Mitigation: scope-down per BTS-395's explicit list; capture follow-up if a downstream surfaces a new scheme. Documented in spec Out-of-Scope.
* **Test fixture cross-contamination:** Each bats test uses its own `mktemp -d` repo via `setup()` — no cross-test pollution. But fixtures must `git add -A && commit` because the email scanner reads `git ls-files`. Verified by mirroring BTS-394's test patterns.
* **Order-of-checks:** Place the case statement BEFORE `is_allowlisted` and BEFORE the noreply/`@example` filter. Reasoning: if a downstream operator has both a URI-scheme line AND a `.security-audit-allowlist` entry for the same file, the case statement should short-circuit early (the entry becomes redundant); putting case AFTER allowlist would still work but make the substrate behavior less obviously correct.

## Definition of Done

- [ ] AC-1 through AC-6 each have a passing bats test
- [ ] Existing `security-audit.bats` tests (36 — including BTS-152, 7c474b2 nested-path, BTS-394 carve-out) still pass
- [ ] Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel --progress`)
- [ ] `module-manifest.sh validate` clean: 194/194, drift 0
- [ ] `/review` clean (run before `/pr`)
- [ ] PR title `feat(bts-395-uri-scheme-email-false-positive-filter): Filter URI-scheme prefixes out of the email-finding scan`
