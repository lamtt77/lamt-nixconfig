#!/usr/bin/env bash
set -euo pipefail

log="${1:-.nxd/test-timings/timings.jsonl}"
count="${2:-999999}"
if [[ ! -s "$log" ]]; then
  echo "No test timing records found at $log" >&2
  exit 0
fi

echo
echo "Test timing summary (slowest first):"
tail -n "$count" "$log" |
  jq -r '[.durationSeconds, .status, .test] | @tsv' |
  sort -nr |
  awk -F '\t' '{ printf "  %4ss  %-4s  %s\n", $1, $2, $3 }'
