#!/usr/bin/env bats
# BTS-277 — bats-report.sh defaults --jobs to perf-core count when available.
#
# Stubs sysctl (for hw.perflevel0.physicalcpu and hw.logicalcpu) and bats (to
# capture the --jobs value the wrapper would have passed) via a $WORK/bin
# PATH shim. Forces parallel branch via BATS_REPORT_HAS_PARALLEL=1.

bats_require_minimum_version 1.5.0

load _helpers/bats-report-stub

REPORT="$BATS_TEST_DIRNAME/../../.ccanvil/scripts/bats-report.sh"

setup() {
  stub_bats_report_prewarm
  WORK=$(mktemp -d)
  mkdir -p "$WORK/bin"
}

teardown() {
  rm -rf "$WORK"
}

# Build a sysctl shim that returns the given perf value for
# hw.perflevel0.physicalcpu and a fixed 16 for hw.logicalcpu.
seed_sysctl() {
  local perf="$1"
  cat > "$WORK/bin/sysctl" <<SHIM
#!/usr/bin/env bash
# args: typically -n <key>
key="\${@: -1}"
case "\$key" in
  hw.perflevel0.physicalcpu) printf '%s' '$perf' ;;
  hw.logicalcpu) printf '%s' '16' ;;
  *) exit 1 ;;
esac
SHIM
  chmod +x "$WORK/bin/sysctl"
}

# A bats shim that records its argv to $WORK/bats-args.log and exits 0.
seed_bats_shim() {
  cat > "$WORK/bin/bats" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WORK/bats-args.log"
exit 0
SHIM
  chmod +x "$WORK/bin/bats"
  # The shim needs $WORK exported into its env.
  export WORK
}

@test "AC-1: --parallel uses perf-core count when sysctl returns >= 2" {
  set -e
  seed_sysctl '12'
  seed_bats_shim
  PATH="$WORK/bin:$PATH" \
  BATS_REPORT_HAS_PARALLEL=1 \
  run bash "$REPORT" --parallel /dev/null
  [ "$status" -eq 0 ]
  grep -qE '^--jobs$' "$WORK/bats-args.log"
  jobs=$(awk '/^--jobs$/ {getline; print; exit}' "$WORK/bats-args.log")
  [ "$jobs" = "12" ]
}

@test "AC-1: --parallel falls back to logicalcpu/2 when perf sysctl is empty" {
  set -e
  seed_sysctl ''
  seed_bats_shim
  PATH="$WORK/bin:$PATH" \
  BATS_REPORT_HAS_PARALLEL=1 \
  run bash "$REPORT" --parallel /dev/null
  [ "$status" -eq 0 ]
  jobs=$(awk '/^--jobs$/ {getline; print; exit}' "$WORK/bats-args.log")
  [ "$jobs" = "8" ]  # 16 / 2
}

@test "AC-1: --parallel falls back when perf sysctl returns 0 or 1" {
  set -e
  seed_sysctl '1'
  seed_bats_shim
  PATH="$WORK/bin:$PATH" \
  BATS_REPORT_HAS_PARALLEL=1 \
  run bash "$REPORT" --parallel /dev/null
  [ "$status" -eq 0 ]
  jobs=$(awk '/^--jobs$/ {getline; print; exit}' "$WORK/bats-args.log")
  [ "$jobs" = "8" ]
}

@test "AC-1: BATS_REPORT_PERF_CORES env override wins over sysctl" {
  set -e
  seed_sysctl '12'
  seed_bats_shim
  PATH="$WORK/bin:$PATH" \
  BATS_REPORT_HAS_PARALLEL=1 \
  BATS_REPORT_PERF_CORES=4 \
  run bash "$REPORT" --parallel /dev/null
  [ "$status" -eq 0 ]
  jobs=$(awk '/^--jobs$/ {getline; print; exit}' "$WORK/bats-args.log")
  [ "$jobs" = "4" ]
}
