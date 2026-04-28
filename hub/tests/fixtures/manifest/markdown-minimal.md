---
manifest:
  purpose: Minimal markdown manifest fixture for validate marker-skip test
  input:
    - stdin
  output:
    - stdout
  side-effect:
    - writes-tmp-file
  failure-mode:
    - "missing-input | exit=1 | visible=stderr-message"
  contract:
    - idempotent
  anchor:
    - BTS-240
---

# Minimal Fixture

The body has no inline @failure-mode or @side-effect markers — drift-guard
must skip marker checks for `.md` paths.
