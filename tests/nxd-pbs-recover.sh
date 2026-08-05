#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# PBS appliance recovery suite (pbs-r720-test).
#
# Side-effect-free by default (plan + verify). APPLY=1 enables apply with
# digest-bound approval.
#   REBUILD_PBS=1     — force guest recreate path
#   RUN_BACKUP_NOW=1  — after job apply, request a live job run (refused outright)
#   APPLY=1           — apply non-empty plans (default 0; applying is opt-in)
#   APPLY_PVE_INTEGRATION=1 — also apply reviewed production PVE storage/job plans
#   PLAN_INCLUDE_PBS=1 is implied.
#
set -euo pipefail

: "${NXD_BIN:=$HOME/lab/nxd/target/debug/nxd}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${APPLY:=0}"
: "${REBUILD_PBS:=0}"
: "${RUN_BACKUP_NOW:=0}"
: "${APPLY_PVE_INTEGRATION:=0}"
export DEFAULT_SECRETS_REPO="${DEFAULT_SECRETS_REPO:-$NXD_SECRETS_REPO}"
export PLAN_INCLUDE_PBS=1
export NXD_BIN NXD_SECRETS_REPO NXD_SOURCE DEFAULT_SECRETS_REPO

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
STATE_DIR="${REPO_ROOT}/.nxd/e2e-pbs-recover"
mkdir -p "$STATE_DIR"

if [[ ! -x "$NXD_BIN" ]] && ! command -v "$NXD_BIN" >/dev/null 2>&1; then
  echo "ERROR: NXD binary not found: $NXD_BIN" >&2
  exit 1
fi
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || echo "$NXD_BIN")

log() {
  echo
  echo "========================================="
  echo ">>> $1"
  echo "========================================="
}
die() { echo "ERROR: $*" >&2; exit 1; }

assert_no_secrets() {
  local plan=$1
  if grep -Eiq 'PVEAPIToken=|PBSAPIToken |BEGIN (OPENSSH |RSA |EC )?PRIVATE KEY|-----BEGIN AGE-SECRET' "$plan"; then
    die "plan embeds secret material: $plan"
  fi
}

plan_apply_verify() {
  local label=$1
  shift
  local apply_enabled=$APPLY
  if [[ "$label" == "storage" || "$label" == "backup" ]]; then
    apply_enabled=$APPLY_PVE_INTEGRATION
  fi
  local plan1="${STATE_DIR}/plan1-${label}.json"
  local plan2="${STATE_DIR}/plan2-${label}.json"
  log "Plan ${label}: $*"
  env -u NXD_SOURCE "$NXD_BIN" plan "$@" --config-json "$CFG" --out "$plan1"
  assert_no_secrets "$plan1"
  local count
  count=$(jq '.spec.actions | length' "$plan1")
  echo "plan1 actions=$count"
  jq -r '.spec.actions[]? | "\(.operation)\t\(.resource)\t\(.risk // "")"' "$plan1" | head -40 || true

  if [[ "$apply_enabled" == "1" && "$count" -gt 0 ]]; then
    local evidence="${STATE_DIR}/approval-${label}.json"
    local apply_args=("$plan1")
    # Reversible-only plans do not require approval evidence.
    if env -u NXD_SOURCE "$NXD_BIN" approval create \
      --plan "$plan1" \
      --out "$evidence" \
      --principal "nxd-pbs-recover@lamt-nixconfig" 2>/tmp/nxd-approval-err.$$; then
      apply_args+=(--approval "$evidence")
    else
      if ! grep -q "no approval requirements" /tmp/nxd-approval-err.$$ 2>/dev/null; then
        cat /tmp/nxd-approval-err.$$ >&2
        rm -f /tmp/nxd-approval-err.$$
        die "approval create failed for ${label}"
      fi
      echo "plan has no approval requirements; applying without evidence"
      rm -f /tmp/nxd-approval-err.$$
    fi
    log "Apply ${label}"
    env -u NXD_SOURCE "$NXD_BIN" apply "${apply_args[@]}"
  elif [[ "$count" -gt 0 && "$apply_enabled" != "1" ]]; then
    echo "WARN: non-empty ${label} plan is not authorized for apply" >&2
    return 0
  fi

  log "Verify ${label}"
  env -u NXD_SOURCE "$NXD_BIN" verify "$@" --config-json "$CFG"

  log "Second plan ${label} (expect 0 actions)"
  env -u NXD_SOURCE "$NXD_BIN" plan "$@" --config-json "$CFG" --out "$plan2"
  assert_no_secrets "$plan2"
  local count2
  count2=$(jq '.spec.actions | length' "$plan2")
  echo "plan2 actions=$count2"
  if [[ "$apply_enabled" == "1" && "$count2" -ne 0 ]]; then
    die "${label} second plan has $count2 actions (expected 0)"
  fi
}

log "Evaluate canonical config"
CFG="$STATE_DIR/lamt.json"
# Prefer local nxd flake modules when developing (schemas/storage fields).
NXD_FLAKE_INPUT="${NXD_FLAKE_INPUT:-git+file://${HOME}/lab/nxd}"
nix eval --json --no-eval-cache \
  --override-input nxd "$NXD_FLAKE_INPUT" \
  "path:${REPO_ROOT}#nxdConfigurations.lamt" >"$CFG"

# --- selectors ---
PBS_SELECTORS=(
  backup-server/pbs-r720-test
  datastore/pbs-r720-test/arthurz2-pbs-test
  backup-namespace/pbs-r720-test/arthurz2-pbs-test/lamt-test
  access-principal/pbs-r720-test/pve-backup
  access-principal/pbs-r720-test/pve-backup-user
  access-grant/pbs-r720-test/pve-backup
  access-grant/pbs-r720-test/pve-backup-DatastoreReader
  access-grant/pbs-r720-test/pve-backup-user
  access-grant/pbs-r720-test/pve-backup-user-DatastoreReader
)
BOOTSTRAP_SELECTORS=(access-principal/pbs-r720-test/provision)
STORAGE_SELECTORS=(storage/pbs-r720-test-backup)
BACKUP_SELECTORS=(backup-job/lamt-workloads-to-pbs-r720-test)
GUEST_PBS=(backup-server/pbs-r720-test)
INSTALL_SELECTORS=(operation:pbs-installer)
IDENTITY_SELECTORS=(ssh-host-identity/pbs-r720-test deployment-target/pbs-r720-test)
CLEANUP_SELECTOR=(operation:pbs-installer-cleanup)

# Sanity: expected backup job structure
jq -e '
  [.spec.resources[] | select(.id=="backup-job/lamt-workloads-to-pbs-r720-test") | .guests[]]
  | index("guest/pbs-r720") == null and index("guest/pbs-r720-test") == null
' "$CFG" >/dev/null || die "backup job must not include PBS appliance guest"

identity_plan="$STATE_DIR/install-identity.json"
env -u NXD_SOURCE "$NXD_BIN" plan "${IDENTITY_SELECTORS[@]}" --config-json "$CFG" --out "$identity_plan"
assert_no_secrets "$identity_plan"

if [[ "$REBUILD_PBS" == "1" ]]; then
  [[ "$APPLY" == "1" ]] || die "REBUILD_PBS=1 requires APPLY=1"
  identity_count=$(jq '.spec.actions | length' "$identity_plan")
  if [[ "$identity_count" -gt 0 ]]; then
    identity_approval="$STATE_DIR/install-identity-approval.json"
    identity_apply_args=("$identity_plan")
    if env -u NXD_SOURCE "$NXD_BIN" approval create --plan "$identity_plan" \
      --out "$identity_approval" --principal "nxd-pbs-recover@lamt-nixconfig" 2>/dev/null; then
      identity_apply_args+=(--approval "$identity_approval")
    fi
    env -u NXD_SOURCE "$NXD_BIN" apply "${identity_apply_args[@]}"
  fi
  log "REBUILD_PBS=1: remove only disposable guest/923"
  cleanup_plan="$STATE_DIR/rebuild-cleanup.json"
  env -u NXD_SOURCE "$NXD_BIN" plan "${CLEANUP_SELECTOR[@]}" --config-json "$CFG" --out "$cleanup_plan"
  assert_no_secrets "$cleanup_plan"
  cleanup_count=$(jq '.spec.actions | length' "$cleanup_plan")
  if [[ "$cleanup_count" -gt 0 ]]; then
    jq -e '
      (.spec.actions | length) == 1
      and .spec.lifecycleIntent == "destroy"
      and .spec.actions[0].id == "pve:guest/pbs-r720-test:delete"
      and .spec.actions[0].providerInstance == "provider/pve2"
      and .spec.actions[0].resource == "guest/pbs-r720-test"
      and .spec.actions[0].operation == "delete"
      and .spec.actions[0].details.wire.details.desired.vmid == 923
    ' "$cleanup_plan" >/dev/null || die "rebuild cleanup is not the exact disposable guest/923 deletion"
    cleanup_approval="$STATE_DIR/rebuild-cleanup-approval.json"
    env -u NXD_SOURCE "$NXD_BIN" approval create --plan "$cleanup_plan" \
      --out "$cleanup_approval" --principal "nxd-pbs-recover@lamt-nixconfig"
    env -u NXD_SOURCE "$NXD_BIN" apply "$cleanup_plan" --approval "$cleanup_approval"
  fi

  log "Install disposable pbs-r720-test"
  for phase in 1 2 3 4 5; do
    install_plan="$STATE_DIR/install-phase${phase}.json"
    env -u NXD_SOURCE "$NXD_BIN" plan "${INSTALL_SELECTORS[@]}" --config-json "$CFG" --out "$install_plan"
    assert_no_secrets "$install_plan"
    install_count=$(jq '.spec.actions | length' "$install_plan")
    if [[ "$install_count" -eq 0 ]]; then
      break
    fi
    jq -e '
      all(.spec.actions[];
        (.resource == "backup-server/pbs-r720-test" and .providerInstance == "provider/pbs")
        or (.resource == "guest/pbs-r720-test" and .providerInstance == "provider/pve2")
        or (.resource == "ssh-host-identity/pbs-r720-test" and .providerInstance == "provider/identity")
        or (.providerInstance == "secret/sops-age" and (
          .resource == "ssh-host-identity/pbs-r720-test"
          or (.resource | startswith("public/bar/hosts/pbs-r720-test/"))
          or (.resource | startswith("secret/bar/hosts/pbs-r720-test/"))
        ))
      )
    ' "$install_plan" >/dev/null || die "installer phase contains an unrelated action"
    install_approval="$STATE_DIR/install-phase${phase}-approval.json"
    apply_args=("$install_plan")
    if env -u NXD_SOURCE "$NXD_BIN" approval create --plan "$install_plan" \
      --out "$install_approval" --principal "nxd-pbs-recover@lamt-nixconfig" 2>/dev/null; then
      apply_args+=(--approval "$install_approval")
    fi
    env -u NXD_SOURCE "$NXD_BIN" apply "${apply_args[@]}"
  done
  [[ "${install_count:-1}" -eq 0 ]] || die "installer did not converge within five phases"
  env -u NXD_SOURCE "$NXD_BIN" verify "${INSTALL_SELECTORS[@]}" --config-json "$CFG"
  env -u NXD_SOURCE "$NXD_BIN" plan "${INSTALL_SELECTORS[@]}" --config-json "$CFG" \
    --out "$STATE_DIR/install-repeat.json"
  jq -e '(.spec.actions | length) == 0' "$STATE_DIR/install-repeat.json" >/dev/null \
    || die "installer repeat is not zero-action"
elif [[ "$APPLY" != "1" ]]; then
  echo "Plan-only: installer identity actions=$(jq '.spec.actions | length' "$identity_plan")"
  echo "PASS: pbs-r720-test recovery preflight is side-effect-free (set REBUILD_PBS=1 APPLY=1 to rebuild)"
  exit 0
fi

log "Stage A: PBS API bootstrap (managed guest transport)"
plan_apply_verify bootstrap "${BOOTSTRAP_SELECTORS[@]}"

log "Stage B: PBS API policy (provider/pbs)"
plan_apply_verify pbs "${PBS_SELECTORS[@]}"

log "Stage C: PVE PBS storage definition (provider/pve2)"
plan_apply_verify storage "${STORAGE_SELECTORS[@]}"

log "Stage D: cluster backup job (provider/pve1)"
plan_apply_verify backup "${BACKUP_SELECTORS[@]}"

if [[ "$RUN_BACKUP_NOW" == "1" ]]; then
  log "RUN_BACKUP_NOW=1: not implemented as automatic production backup trigger (refuse silent)"
  die "live backup run requires an explicit operator runbook; set RUN_BACKUP_NOW=0"
fi

log "Stage E: server presence observe for pbs-r720-test (no destroy)"
# Side-effect-free plan of the PBS server only.
env -u NXD_SOURCE "$NXD_BIN" plan "${GUEST_PBS[@]}" --config-json "$CFG" --out "$STATE_DIR/plan-guest-pbs.json" || true
assert_no_secrets "$STATE_DIR/plan-guest-pbs.json"

echo
echo "PASS: nxd-pbs-recover completed (REBUILD_PBS=$REBUILD_PBS APPLY=$APPLY)"
echo "Plans: $STATE_DIR"
