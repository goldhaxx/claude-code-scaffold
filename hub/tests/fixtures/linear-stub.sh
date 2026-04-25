#!/usr/bin/env bash
# linear-stub.sh — bats fixture: shadow `curl` with a bash function for
# linear-query.sh testing. Source this in a bats setup() to intercept HTTP.
#
# Side-channel env vars (set by the test):
#   LINEAR_STUB_CAPTURE   path to capture raw curl args (one per line, then
#                         a separator line "<<BODY>>", then the -d body)
#   LINEAR_STUB_RESPONSE  path containing JSON the stub echoes to stdout
#
# When LINEAR_STUB_CAPTURE is unset, the stub silently discards the args.
# When LINEAR_STUB_RESPONSE is unset or missing, the stub emits "{}".

curl() {
  local capture="${LINEAR_STUB_CAPTURE:-/dev/null}"
  local response_file="${LINEAR_STUB_RESPONSE:-}"

  : > "$capture"

  # Capture each arg on its own line. Body (-d / --data) gets a sentinel
  # line so test grep can target headers vs body cleanly.
  local arg next_is_body=0
  for arg in "$@"; do
    if [[ "$next_is_body" -eq 1 ]]; then
      printf '<<BODY>>\n%s\n' "$arg" >> "$capture"
      next_is_body=0
      continue
    fi
    case "$arg" in
      -d|--data|--data-raw|--data-binary)
        printf '%s\n' "$arg" >> "$capture"
        next_is_body=1
        ;;
      *)
        printf '%s\n' "$arg" >> "$capture"
        ;;
    esac
  done

  if [[ -n "$response_file" && -f "$response_file" ]]; then
    cat "$response_file"
  else
    printf '{}\n'
  fi
}
export -f curl
