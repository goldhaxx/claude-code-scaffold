---
name: markdown-happy
description: "Test fixture for markdown manifest extract — BTS-240 Step 1"
manifest:
  purpose: Happy-path markdown manifest fixture
  routes-by: /markdown-happy
  input:
    - stdin
    - cli-flags
  output:
    - stdout
  caller:
    - fixture_caller
  depends-on:
    - jq
  side-effect:
    - writes-tmp-file
  failure-mode:
    - "missing-input | exit=1 | visible=stderr-message"
    - "parse-error | exit=2 | visible=stderr-message | mitigation=retry-with-fallback"
  contract:
    - idempotent
  anchor:
    - BTS-240 (origin)
---

# Markdown Happy Fixture

This is the body of the markdown file. It is not parsed by the manifest extractor.
