#!/usr/bin/env bash
# Re-execute a standalone test under a lightweight wall-clock timer. The child
# keeps its original traps and exit behavior; this wrapper only reports the
# outer test result and appends a machine-readable record.

nxd_test_timing_wrap() {
  local script="${1:?test script path is required}"
  shift
  if [[ "${NXD_TEST_TIMING_CHILD:-}" == "$script" ]]; then
    return 0
  fi

  local started finished duration status result timestamp log
  started=$(date +%s)
  set +e
  NXD_TEST_TIMING_CHILD="$script" bash "$script" "$@"
  status=$?
  set -e
  finished=$(date +%s)
  duration=$((finished - started))
  if ((status == 0)); then
    result="pass"
  else
    result="fail"
  fi
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  log="${NXD_TEST_TIMING_LOG:-.nxd/test-timings/timings.jsonl}"
  mkdir -p "$(dirname "$log")"
  printf '{"timestamp":"%s","test":"%s","status":"%s","exitCode":%d,"durationSeconds":%d}\n' \
    "$timestamp" "${script##*/}" "$result" "$status" "$duration" >>"$log"
  printf 'TIMING test=%s status=%s exit_code=%d duration=%ss\n' \
    "${script##*/}" "$result" "$status" "$duration" >&2
  exit "$status"
}

nxd_test_phase_start() {
  NXD_TEST_PHASE_NAME="${1:?phase name is required}"
  NXD_TEST_PHASE_STARTED=$(date +%s)
  printf 'PHASE start test=%s phase=%s\n' "${0##*/}" "$NXD_TEST_PHASE_NAME" >&2
}

nxd_test_phase_finish() {
  local finished duration
  finished=$(date +%s)
  duration=$((finished - NXD_TEST_PHASE_STARTED))
  printf 'PHASE finish test=%s phase=%s duration=%ss\n' \
    "${0##*/}" "$NXD_TEST_PHASE_NAME" "$duration" >&2
  unset NXD_TEST_PHASE_NAME NXD_TEST_PHASE_STARTED
}
