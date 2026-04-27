# Feature: guard-destructive rm-rf detection scoped to combined flag clusters

> Feature: bts-202-guard-destructive-flag-cluster-tightening
> Work: linear:BTS-202
> Created: 1777327911
> Status: In Progress

## Summary

`guard-destructive.sh`'s rm-rf gate uses two independent regexes that scan the entire command line for `r`/`R`-bearing and `f`/`F`-bearing flags. When ANY unrelated `-r` flag (e.g., `jq -r`) appears alongside ANY unrelated `-f` flag (e.g., `rm -f /tmp/foo` — only force, not recursive), both conditions match across the line and the gate fires. Reproducible: `echo foo | jq -r .; rm -f /tmp/notreal` blocks even though no actual `rm -rf` is invoked.

This ship tightens the rm-rf detection per the ticket's recommended approach (C): require `r/R` AND `f/F` to appear in the SAME flag cluster (`-rf`, `-fr`, `-Rf`, `-rfv`, etc.), OR require both `--recursive` AND `--force` long forms on the line. Cross-token combinations like `-r` + `-f` (separately-spelled) are no longer detected — accepted trade-off; `rm -r -f` is unusual versus the canonical `rm -rf` footgun, and operators using deliberate split-flag forms can prefix `ALLOW_DESTRUCTIVE=1`.

## Job To Be Done

**When** I run a command that combines a tool with a `-r` flag (jq, grep, find, etc.) and a separate `rm -f` (force-only, not recursive),
**I want to** have the rm-rf gate NOT fire on the unrelated flag combination,
**So that** legitimate operations don't require `ALLOW_DESTRUCTIVE=1` bypass and the audit trail isn't polluted with bypass invocations.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `jq -r .` followed by `rm -f /path` (separate commands, same line, separated by `;` or `|` or `&&`) does NOT block. Origin reproducer.
- [ ] **AC-2:** Other unrelated `r`/`f` flag combos do NOT block: `grep -F ... ; rm -f x`, `git -C dir branch -r; rm -f y`, `find . -name '*.r' -print; rm -f z`. None of these are rm-rf footguns.
- [ ] **AC-3:** Canonical footguns still block: `rm -rf /tmp/x`, `rm -fr /tmp/x`, `rm -Rf /tmp/x`, `rm -fR /tmp/x`. Combined clusters in any letter order.
- [ ] **AC-4:** Cluster variations with extra letters still block: `rm -rfv /tmp`, `rm -vrf /tmp`, `rm -rfi /tmp`, `rm -fvR ~/foo`. Any cluster containing both r/R AND f/F.
- [ ] **AC-5:** Long-form combination still blocks: `rm --recursive --force /tmp`, `rm --force --recursive /tmp` (order-independent).
- [ ] **AC-6:** Split short-form `rm -r -f /tmp` is NOT caught (out-of-scope trade-off). Bats coverage records this as a documented non-block to make the trade-off explicit.
- [ ] **AC-7:** New bats `hub/tests/guard-destructive-flag-cluster.bats` covers AC-1 through AC-6 with the existing `_run_hook` pattern.
- [ ] **AC-8:** Full bats suite remains green at ≥ 1754 (post-BTS-210 baseline).

## Affected Files

| File | Change |
| -- | -- |
| `.claude/hooks/guard-destructive.sh` | Replace the two-regex cross-line scan with: combined-cluster regex (`r/R` AND `f/F` in same flag) + dual-long-form gate (`--recursive` AND `--force`). |
| `hub/tests/guard-destructive-flag-cluster.bats` | New bats covering AC-1 through AC-6. |

## Dependencies

* **Requires:** Nothing new.
* **Blocked by:** Nothing.

## Out of Scope

* Detecting split short-form `rm -r -f` / `rm -r --force` / `rm --recursive -f`. The original two-regex design caught these but at the cost of the false-positive class. Per ticket recommendation (C), accept the trade-off. Operators can `ALLOW_DESTRUCTIVE=1` for split forms; canonical `rm -rf` is still gated.
* Tokenizing the command and scoping flag detection to the rm invocation (approach A in the ticket). Larger refactor; not justified for this ship.
* Generic shell-flag false-positive audit across other guards.

## Implementation Notes

* **New regex set:**

  ```bash
  # Combined cluster: r/R AND f/F in the same flag token, any letter order
  rm_combined_cluster='(^|[[:space:]])-[a-zA-Z]*([rR][a-zA-Z]*[fF]|[fF][a-zA-Z]*[rR])[a-zA-Z]*([[:space:]]|=|$)'
  rm_long_recursive='(^|[[:space:]])--recursive([[:space:]]|=|$)'
  rm_long_force='(^|[[:space:]])--force([[:space:]]|=|$)'
  ```
* **Gate condition:**

  ```bash
  if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]] ]]; then
    trip=0
    if [[ "$COMMAND" =~ $rm_combined_cluster ]]; then
      trip=1
    elif [[ "$COMMAND" =~ $rm_long_recursive ]] && [[ "$COMMAND" =~ $rm_long_force ]]; then
      trip=1
    fi
    if (( trip == 1 )); then
      echo "BLOCKED: rm with recursive AND force flags deletes without prompt." >&2
      echo "  To bypass: ALLOW_DESTRUCTIVE=1 rm ..." >&2
      exit 2
    fi
  fi
  ```
* **Dual-long-form residual false-positive risk:** if the command line contains `rm` PLUS both `--recursive` and `--force` (potentially in unrelated commands like `cp --recursive --force foo bar; rm /tmp/y`), the gate still fires. Acceptable: long-form rm flags are uncommon, and the combination of `rm` + `--recursive` + `--force` on a single line is almost certainly an rm using long forms. Operators can prefix `ALLOW_DESTRUCTIVE=1` for the rare collision.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
