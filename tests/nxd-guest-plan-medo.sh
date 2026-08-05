#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Side-effect-free plan smoke for guest/medo-test (PVE guest selector).
# Does not apply. Uses a single eval so path:nxd NAR churn cannot break mid-script.
#
# Asserts: inventory includes guest/medo-test, plan succeeds, no secret bytes.
# Action count may be non-zero when the lab guest is absent or drifted.
#
# Usage: ./tests/nxd-guest-plan-medo.sh
set -euo pipefail

: "${NXD_BIN:=$HOME/lab/nxd/target/debug/nxd}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
export DEFAULT_SECRETS_REPO="${DEFAULT_SECRETS_REPO:-$NXD_SECRETS_REPO}"

OUT="${TMPDIR:-/tmp}/lamt-medo-plan.json"
CFG="${TMPDIR:-/tmp}/lamt-nxd-config.json"

if [[ ! -d "$DEFAULT_SECRETS_REPO" ]]; then
  echo "SKIP: secrets repo not found at $DEFAULT_SECRETS_REPO" >&2
  exit 0
fi

if [[ ! -x "$NXD_BIN" ]] && ! command -v "$NXD_BIN" >/dev/null 2>&1; then
  echo "ERROR: NXD binary not found: $NXD_BIN" >&2
  exit 1
fi
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || echo "$NXD_BIN")

echo "Evaluating ${NXD_SOURCE} once → ${CFG}"
nix --extra-experimental-features "nix-command flakes" eval --json --no-eval-cache "${NXD_SOURCE}" >"${CFG}"

if ! jq -e '.spec.resources[] | select(.id == "guest/medo-test")' "${CFG}" >/dev/null; then
  echo "FAIL: guest/medo-test missing from canonical config" >&2
  exit 1
fi

echo "Planning guest/medo-test (no apply) with ${NXD_BIN}"
env -u NXD_SOURCE "$NXD_BIN" plan "guest/medo-test" \
  --config-json "${CFG}" \
  --out "${OUT}"

if grep -Eiq 'PVEAPIToken=|BEGIN (OPENSSH |RSA |EC )?PRIVATE KEY|-----BEGIN AGE-SECRET' "${OUT}"; then
  echo "FAIL: plan embeds secret material" >&2
  exit 1
fi

actions=$(jq '.spec.actions | length' "${OUT}")
echo "guest/medo-test plan actionCount=${actions}"
jq -r '.spec.actions[]? | "\(.operation)\t\(.resource)\t\(.risk // "")"' "${OUT}" | head -20 || true

# Converged lab: zero actions. Absent/drifted guest: non-zero is still a valid plan smoke.
if [[ "${actions}" == "0" ]]; then
  echo "PASS: guest/medo-test plan is zero-action (converged presence)"
else
  echo "PASS: guest/medo-test plan succeeded with ${actions} action(s) (drift or absent guest; no apply)"
fi
echo "plan: ${OUT}"
