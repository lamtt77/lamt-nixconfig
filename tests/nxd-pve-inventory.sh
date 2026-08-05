#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Side-effect-free PVE inventory reconcile (non-guest kinds).
#
# Covers plan + verify for topology, storage/network attachments, and access
# resources against the live PVE API. Does not select guests (those belong to
# nxd-guest-lifecycle / nxd-pve-pxe).
#
# Usage:
#   NXD_BIN=$HOME/lab/nxd/target/debug/nxd ./tests/nxd-pve-inventory.sh
#
# Env:
#   NXD_BIN, NXD_SOURCE, NXD_SECRETS_REPO / DEFAULT_SECRETS_REPO
#   APPLY=1  — optional apply of the first plan (requires live approval path;
#              only use when the operator accepts identity-critical/access churn)
set -euo pipefail

: "${NXD_BIN:=$HOME/lab/nxd/target/debug/nxd}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${APPLY:=0}"
export DEFAULT_SECRETS_REPO="${DEFAULT_SECRETS_REPO:-$NXD_SECRETS_REPO}"
export NXD_BIN NXD_SECRETS_REPO NXD_SOURCE DEFAULT_SECRETS_REPO

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
STATE_DIR="${REPO_ROOT}/.nxd/e2e-pve-inventory"
mkdir -p "$STATE_DIR"

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
  # Binding ids and digests are fine. Refuse material that looks like raw
  # credentials or private key PEM in the plan document.
  if grep -Eiq \
    'PVEAPIToken=|BEGIN (OPENSSH |RSA |EC )?PRIVATE KEY|-----BEGIN AGE-SECRET|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' \
    "$plan_path"; then
    die "plan $plan_path appears to embed secret material"
  fi
}

log "Evaluate canonical config"
CFG="$STATE_DIR/lamt.json"
# Prefer local nxd flake modules when developing (same as PBS disposable / PXE).
NXD_FLAKE_INPUT="${NXD_FLAKE_INPUT:-git+file://${HOME}/lab/nxd}"
nix eval --json --no-eval-cache \
  --override-input nxd "$NXD_FLAKE_INPUT" \
  .#nxdConfigurations.lamt >"$CFG"

log "Select non-guest PVE inventory resources (must declare provider)"
# pveCluster is topology metadata that now routes through a configured provider
# (03.1); managed inventory plan groups still select node/storage/access kinds.
# storageAttachment without definition fields is presence-only (PBS/backup
# dependency). Managed inventory here is definition-bearing storage only, plus
# access/network/node. Attachment-only rows are verified when PBS inventory runs.
# shellcheck disable=SC2016
mapfile -t SELECTORS < <(jq -r '
  [
    .spec.resources[]
    | select(
        (
          .kind == "pveNode"
          or (.kind == "storageAttachment" and (.storageType != null) and (.storageType != ""))
          or .kind == "networkAttachment"
          or .kind == "pveRole"
          or .kind == "pveAcl"
          or .kind == "pveNotificationTarget"
          or .kind == "pveNotificationMatcher"
        )
        and (.provider != null)
        and (.provider != "")
      )
    | .id
  ]
  | sort
  | .[]
' "$CFG")

if [[ ${#SELECTORS[@]} -eq 0 ]]; then
  die "no non-guest PVE inventory resources with provider in $NXD_SOURCE"
fi
echo "selectors (${#SELECTORS[@]}): ${SELECTORS[*]}"

# Plan/verify per provider instance (one operation must not mix providers).
mapfile -t PROVIDERS < <(jq -r '
  [
    .spec.resources[]
    | select(
        (
          .kind == "pveNode"
          or (.kind == "storageAttachment" and (.storageType != null) and (.storageType != ""))
          or .kind == "networkAttachment"
          or .kind == "pveRole"
          or .kind == "pveAcl"
          or .kind == "pveNotificationTarget"
          or .kind == "pveNotificationMatcher"
        )
        and (.provider != null)
        and (.provider != "")
      )
    | .provider
  ]
  | unique
  | .[]
' "$CFG")

TOTAL_ACTIONS=0
for provider in "${PROVIDERS[@]}"; do
  mapfile -t GROUP < <(jq -r --arg p "$provider" '
    [
      .spec.resources[]
      | select(
          (.provider == $p)
          and (
            .kind == "pveNode"
            or (.kind == "storageAttachment" and (.storageType != null) and (.storageType != ""))
            or .kind == "networkAttachment"
            or .kind == "pveRole"
            or .kind == "pveAcl"
            or .kind == "pveNotificationTarget"
            or .kind == "pveNotificationMatcher"
          )
        )
      | .id
    ]
    | sort
    | .[]
  ' "$CFG")
  [[ ${#GROUP[@]} -gt 0 ]] || continue
  safe_provider=${provider//\//_}
  PLAN1="$STATE_DIR/plan1-${safe_provider}.json"
  PLAN2="$STATE_DIR/plan2-${safe_provider}.json"

  log "Plan ${provider} (${#GROUP[@]} resources)"
  env -u NXD_SOURCE "$NXD_BIN" plan "${GROUP[@]}" \
    --config-json "$CFG" \
    --out "$PLAN1"
  assert_plan_has_no_secret_bytes "$PLAN1"
  count=$(jq '.spec.actions | length' "$PLAN1")
  TOTAL_ACTIONS=$((TOTAL_ACTIONS + count))
  echo "plan1 actions=$count"
  jq -r '.spec.actions[]? | "\(.operation)\t\(.resource)\t\(.risk // "")"' "$PLAN1" | head -40 || true

  if [[ "$APPLY" == "1" && "$count" -gt 0 ]]; then
    log "APPLY=1: apply ${provider}"
    EVIDENCE="$STATE_DIR/approval-${safe_provider}.json"
    env -u NXD_SOURCE "$NXD_BIN" approval create \
      --plan "$PLAN1" \
      --out "$EVIDENCE" \
      --principal "nxd-pve-inventory@lamt-nixconfig"
    env -u NXD_SOURCE "$NXD_BIN" apply "$PLAN1" --approval "$EVIDENCE"
  fi

  if [[ "$count" -eq 0 || "$APPLY" == "1" ]]; then
    log "Verify ${provider}"
    if ! env -u NXD_SOURCE "$NXD_BIN" verify "${GROUP[@]}" --config-json "$CFG"; then
      if [[ "$APPLY" == "1" ]]; then
        die "verify failed for ${provider} after apply"
      fi
      echo "WARN: verify reported drift for ${provider} (plan was non-empty; APPLY!=1)" >&2
    fi
  else
    echo "plan1 non-empty — skip verify until APPLY=1 or inventory is converged"
  fi

  log "Second plan ${provider}"
  env -u NXD_SOURCE "$NXD_BIN" plan "${GROUP[@]}" \
    --config-json "$CFG" \
    --out "$PLAN2"
  assert_plan_has_no_secret_bytes "$PLAN2"
  count2=$(jq '.spec.actions | length' "$PLAN2")
  echo "plan2 actions=$count2"
  if [[ "$APPLY" == "1" && "$count2" -ne 0 ]]; then
    die "${provider} still has $count2 actions after apply (expected empty)"
  fi
done

echo
echo "PASS: PVE inventory plan completed (selectors=${#SELECTORS[@]} providers=${#PROVIDERS[@]} apply=$APPLY first_plan_actions=$TOTAL_ACTIONS)"
echo "Plans: $STATE_DIR"
if [[ "$TOTAL_ACTIONS" -gt 0 && "$APPLY" != "1" ]]; then
  echo "note: non-zero plan actions mean live drift; re-run with APPLY=1 only with owner approval"
fi
