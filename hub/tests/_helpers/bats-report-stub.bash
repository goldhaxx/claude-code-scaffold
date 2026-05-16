# BTS-507 — bypass helper for the BTS-281 module-manifest pre-warm step in
# `.ccanvil/scripts/bats-report.sh`. Any bats test that invokes bats-report.sh
# in a subshell would otherwise pay a ~7-min pre-warm toll per invocation.
#
# Usage (inside a `.bats` file):
#
#   load _helpers/bats-report-stub
#   setup() { stub_bats_report_prewarm; }
#
# Or call from `setup_file()` if the bats-report.sh invocation happens once
# per file. Writes a canonical zero-coverage manifest envelope to
# $BATS_FILE_TMPDIR and exports BTS_MANIFEST_VALIDATE_CACHE so bats-report.sh
# treats the cache as already populated.

stub_bats_report_prewarm() {
  local cache="$BATS_FILE_TMPDIR/bats-report-stub-cache.json"
  printf '%s\n' '{"coverage":{"covered":0,"total":0},"drift":[],"status":"ok"}' \
    > "$cache"
  export BTS_MANIFEST_VALIDATE_CACHE="$cache"
}
