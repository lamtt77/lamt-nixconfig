#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# PBS resource lifecycle (plan → optional apply → verify → replan).
#
# Default is gated off until PBS is installed and live on the lab API:
#   PLAN_INCLUDE_PBS=1 ./tests/nxd-pbs-inventory.sh
#
# Side-effect-free by default (plan + verify). APPLY=1 enables apply with
# digest-bound approval. First-boot token mint is NXD plan action
# install-bootstrap + confidential sink (not independent provider --apply).
#
# Usage:
#   PLAN_INCLUDE_PBS=1 NXD_BIN=$HOME/lab/nxd/target/debug/nxd \
#     ./tests/nxd-pbs-inventory.sh
#
# Env:
#   PLAN_INCLUDE_PBS   must be 1 or the script exits 0 (SKIP)
#   APPLY=1            optional apply after plan1
#   NXD_BIN, NXD_SOURCE, NXD_SECRETS_REPO / DEFAULT_SECRETS_REPO
set -euo pipefail

: "${NXD_BIN:=$HOME/lab/nxd/target/debug/nxd}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${PLAN_INCLUDE_PBS:=0}"
: "${APPLY:=0}"
export DEFAULT_SECRETS_REPO="${DEFAULT_SECRETS_REPO:-$NXD_SECRETS_REPO}"
export NXD_BIN NXD_SECRETS_REPO NXD_SOURCE DEFAULT_SECRETS_REPO PLAN_INCLUDE_PBS

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
STATE_DIR="${REPO_ROOT}/.nxd/e2e-pbs-lifecycle"
mkdir -p "$STATE_DIR"

if [[ "$PLAN_INCLUDE_PBS" != "1" ]]; then
  echo "SKIP: PLAN_INCLUDE_PBS!=1 (PBS not expected live). Set PLAN_INCLUDE_PBS=1 after pbs-r720 is installed."
  exit 0
fi

if [[ ! -x "$NXD_BIN" ]] && ! command -v "$NXD_BIN" >/dev/null 2>&1; then
  echo "ERROR: NXD binary not found or not executable: $NXD_BIN" >&2
  exit 1
fi
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || echo "$NXD_BIN")

if [[ ! -d "$DEFAULT_SECRETS_REPO" ]]; then
  echo "ERROR: secrets repo not found: $DEFAULT_SECRETS_REPO" >&2
  exit 1
fi

log() {
  echo
  echo "========================================="
  echo ">>> $1"
  echo "========================================="
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

assert_plan_has_no_secret_bytes() {
  local plan_path=$1
  if grep -Eiq \
    'PVEAPIToken=|PBSAPIToken=|BEGIN (OPENSSH |RSA |EC )?PRIVATE KEY|-----BEGIN AGE-SECRET|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' \
    "$plan_path"; then
    die "plan $plan_path appears to embed secret material"
  fi
}

log "Evaluate canonical config"
CFG="$STATE_DIR/lamt.json"
nix eval --json --no-eval-cache "$NXD_SOURCE" >"$CFG"

ORIGIN=$(jq -r '
  .spec.providerInstances[]
  | select(.id == "provider/pbs")
  | .config.servers
  | to_entries[0].value.origin // empty
' "$CFG")
if [[ -z "$ORIGIN" ]]; then
  die "provider/pbs origin missing from config"
fi
echo "PBS origin: $ORIGIN"

log "Select PBS inventory resources"
# shellcheck disable=SC2016
mapfile -t SELECTORS < <(jq -r '
  [
    .spec.resources[]
    | select(
        .kind == "backupServer"
        or .kind == "datastore"
        or .kind == "backupNamespace"
        or .kind == "accessPrincipal"
        or .kind == "accessGrant"
        or .kind == "backupRemote"
        or .kind == "syncJob"
        or .kind == "prunePolicy"
        or .kind == "verificationPolicy"
        or .kind == "pbsNotificationTarget"
        or .kind == "pbsNotificationMatcher"
      )
    | .id
  ]
  | sort
  | .[]
' "$CFG")

if [[ ${#SELECTORS[@]} -eq 0 ]]; then
  die "no PBS inventory resources in $NXD_SOURCE"
fi
echo "selectors (${#SELECTORS[@]}): ${SELECTORS[*]}"

PLAN1="$STATE_DIR/pbs-plan1.json"
PLAN2="$STATE_DIR/pbs-plan2.json"

log "Plan (side-effect-free)"
# --config-json conflicts with NXD_SOURCE / --source; use explicit config only.
if ! env -u NXD_SOURCE "$NXD_BIN" plan "${SELECTORS[@]}" \
  --config-json "$CFG" \
  --out "$PLAN1"; then
  die "PBS plan failed (origin=$ORIGIN). Check token binding, CA, and that PBS is reachable."
fi
assert_plan_has_no_secret_bytes "$PLAN1"
ACTION_COUNT=$(jq '.spec.actions | length' "$PLAN1")
echo "plan1 actions=$ACTION_COUNT"
jq -r '.spec.actions[]? | "\(.operation)\t\(.resource)\t\(.risk // "")"' "$PLAN1" | head -40 || true

if [[ "$APPLY" == "1" ]]; then
  log "APPLY=1: create approval and apply plan1"
  if [[ "$ACTION_COUNT" -gt 0 ]]; then
    EVIDENCE="$STATE_DIR/approval-plan1.json"
    "$NXD_BIN" approval create \
      --plan "$PLAN1" \
      --out "$EVIDENCE" \
      --principal "nxd-pbs-inventory@lamt-nixconfig"
    "$NXD_BIN" apply "$PLAN1" --approval "$EVIDENCE"
  else
    echo "plan1 empty — skip apply"
  fi
else
  echo "APPLY!=1 — plan only (no mutation)"
fi

log "Verify against live PBS"
env -u NXD_SOURCE "$NXD_BIN" verify "${SELECTORS[@]}" --config-json "$CFG"

log "Second plan (idempotency signal)"
env -u NXD_SOURCE "$NXD_BIN" plan "${SELECTORS[@]}" \
  --config-json "$CFG" \
  --out "$PLAN2"
assert_plan_has_no_secret_bytes "$PLAN2"
ACTION_COUNT2=$(jq '.spec.actions | length' "$PLAN2")
echo "plan2 actions=$ACTION_COUNT2"

if [[ "$APPLY" == "1" ]]; then
  if [[ "$ACTION_COUNT2" -ne 0 ]]; then
    die "second plan after apply still has $ACTION_COUNT2 actions (expected empty for idempotent converge)"
  fi
  echo "second plan empty — idempotent after apply"
else
  echo "note: without APPLY=1, plan2 may still list drift; not treated as failure"
fi

echo
echo "PASS: PBS lifecycle plan/verify completed (selectors=${#SELECTORS[@]} apply=$APPLY)"
echo "Plans: $STATE_DIR"
echo "Note: bootstrap dry-run is just pbs-ssh-bootstrap-dry-run; live mint is NXD plan install-bootstrap."
