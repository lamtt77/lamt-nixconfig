#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Full disposable guest lifecycle on PVE (install → convert → day-2 → destroy).
#
# Covers:
#   install  → ubuntu-cloudinit-test (recreate cloud-init guest)
#   convert  → medo-test (in-place NixOS from cloud-init)
#   observe / build-only / boot / test / switch  (plans; apply switch if needed)
#   destroy  → medo-test (provider delete)
#
# Authority: hosts whose names end in -test only (owner-approved disposable).
# Requires network access to PVE lab and secrets repo.
#
# Usage:
#   NXD_BIN=$HOME/lab/nxd/target/debug/nxd ./tests/nxd-guest-lifecycle.sh
# This retained live consumer lane is invoked directly; provider and CLI
# contract checks own the mechanics shared with other lifecycle suites.
#
# Env:
#   NXD_BIN, NXD_SECRETS_REPO, NXD_SOURCE
#   HEADSCALE_API_ORIGIN, HEADSCALE_API_TOKEN  — required when install/convert hosts
#     declare Tailscale (nxd REST-only; no SSH CLI fallback). Optional load from
#     ~/.config/nxd/headscale.env
#   SKIP_DESTROY=1          — leave medo-test running after switch checks
#   SKIP_INSTALL=1          — skip cloud-init recreate (convert needs live source)
set -euo pipefail

HOST_CLOUDINIT="${HOST_CLOUDINIT:-ubuntu-cloudinit-test}"
HOST_DEST="${HOST_DEST:-medo-test}"
SSH_USER_CLOUDINIT="${SSH_USER_CLOUDINIT:-ubuntu}"
SSH_USER_NIXOS="${SSH_USER_NIXOS:-nixos}"

if [[ -f "${HOME}/.config/nxd/headscale.env" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.config/nxd/headscale.env"
fi

: "${NXD_BIN:=$HOME/lab/nxd/target/debug/nxd}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
# Core lifecycle staging resolves its external installer-secret input through
# DEFAULT_SECRETS_REPO. Keep the test's established NXD_SECRETS_REPO override
# as the operator-facing variable and bridge it explicitly.
export DEFAULT_SECRETS_SITE="${DEFAULT_SECRETS_SITE:-bar}"
export DEFAULT_SECRETS_REPO="$NXD_SECRETS_REPO"
export NXD_BIN NXD_SECRETS_REPO NXD_SOURCE DEFAULT_SECRETS_REPO DEFAULT_SECRETS_SITE
export HEADSCALE_API_ORIGIN="${HEADSCALE_API_ORIGIN:-}"
export HEADSCALE_API_TOKEN="${HEADSCALE_API_TOKEN:-}"

if [[ -z "${HEADSCALE_API_ORIGIN}" || -z "${HEADSCALE_API_TOKEN}" ]]; then
  echo "WARN: HEADSCALE_API_* unset — convert/install fails if hosts declare Tailscale auth keys"
  echo "  set HEADSCALE_API_ORIGIN + HEADSCALE_API_TOKEN, or source ~/.config/nxd/headscale.env"
else
  echo "Headscale REST: origin=${HEADSCALE_API_ORIGIN} token_len=${#HEADSCALE_API_TOKEN}"
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

assert_host_is_test() {
  local host=$1
  [[ "$host" == *-test ]] || die "refusing non-disposable host '$host' (must end with -test)"
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
assert_host_is_test "$HOST_CLOUDINIT"
assert_host_is_test "$HOST_DEST"

if [[ ! -x "$NXD_BIN" ]] && ! command -v "$NXD_BIN" >/dev/null 2>&1; then
  die "NXD binary not found or not executable: $NXD_BIN"
fi
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || echo "$NXD_BIN")
STATE_DIR="${REPO_ROOT}/.nxd/e2e-lifecycle"
mkdir -p "$STATE_DIR"
TRANSIENT_KNOWN_HOSTS="$STATE_DIR/transient-known-hosts"
STABLE_KNOWN_HOSTS="$STATE_DIR/stable-known-hosts"
: >"$TRANSIENT_KNOWN_HOSTS"
: >"$STABLE_KNOWN_HOSTS"
SSH_COMMON=(-A -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
run_sequence=0
mutation_started=0
cleanup_done=0
SUMMARY="$STATE_DIR/summary.tsv"
: >"$SUMMARY"
echo -e "stage\tintent\thost\tresult\tdetail" >>"$SUMMARY"

record() {
  local stage=$1 intent=$2 host=$3 result=$4 detail=${5:-}
  echo -e "${stage}\t${intent}\t${host}\t${result}\t${detail}" >>"$SUMMARY"
  echo "RECORD ${stage} intent=${intent} host=${host} → ${result} ${detail}"
}

nxd() {
  "$NXD_BIN" "$@"
}

ssh_transient() {
  ssh "${SSH_COMMON[@]}" -o UserKnownHostsFile="$TRANSIENT_KNOWN_HOSTS" \
    -o StrictHostKeyChecking=accept-new "$@"
}

ssh_stable() {
  ssh "${SSH_COMMON[@]}" -o UserKnownHostsFile="$STABLE_KNOWN_HOSTS" \
    -o StrictHostKeyChecking=yes "$@"
}

prepare_stable_known_hosts() {
  local hostname=$1
  local ip=$2
  local identity="$NXD_SECRETS_REPO/bar/hosts/$hostname/identity.json"
  [[ -s "$identity" ]] || die "stable public identity document is missing: $identity"
  local key
  key=$(jq -er '.publicKey | select(type == "string" and startswith("ssh-ed25519 "))' "$identity") \
    || die "stable public identity document has no valid Ed25519 public key: $identity"
  key=$(awk '{ print $1 " " $2 }' <<<"$key")
  printf '%s %s\n%s %s\n' "$hostname" "$key" "$ip" "$key" >"$STABLE_KNOWN_HOSTS"
  chmod 600 "$STABLE_KNOWN_HOSTS"
}

write_approval() {
  local plan_path=$1
  local evidence_path=$2
  nxd approval create \
    --plan "$plan_path" \
    --out "$evidence_path" \
    --principal "nxd-guest-lifecycle@lamt-nixconfig"
}

apply_with_approval() {
  local plan_path=$1
  local evidence
  evidence="$STATE_DIR/approval-$(basename "$plan_path" .json).json"
  run_sequence=$((run_sequence + 1))
  local run_id
  run_id="lamt-guest-lifecycle-${run_sequence}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mutation_started=1
  if jq -e '.spec.approvalRequirements | length > 0' "$plan_path" >/dev/null; then
    write_approval "$plan_path" "$evidence"
    nxd approval validate --plan "$plan_path" --approval "$evidence" --format json >/dev/null
    nxd apply "$plan_path" --approval "$evidence" --run-id "$run_id"
  else
    nxd apply "$plan_path" --run-id "$run_id"
  fi
  nxd show run "$run_id" --format json >"$STATE_DIR/run-${run_sequence}.json"
  jq -e '.status == "succeeded"' "$STATE_DIR/run-${run_sequence}.json" >/dev/null
}

cleanup() {
  local status=${1:-0}
  trap - EXIT HUP INT TERM
  if [[ "$mutation_started" -eq 1 && "$cleanup_done" -eq 0 ]]; then
    echo "Lifecycle cleanup: planning exact disposable source destruction" >&2
    local plan="$STATE_DIR/trap-destroy-${HOST_CLOUDINIT}.plan.json"
    if nxd plan "deployment-target/${HOST_CLOUDINIT}" --intent destroy \
      --source "$NXD_SOURCE" --out "$plan" \
      && apply_with_approval "$plan"; then
      cleanup_done=1
    else
      echo "Lifecycle cleanup failed; reviewed plan retained at $plan" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

# Option A: install/convert may first emit an enrollment-only plan (preauth
# create + sink). Apply it, then replan until the host lifecycle plan remains.
# Usage: plan_and_apply_lifecycle_phases <stage> <intent> <host> <plan_stem> \
#          [extra nxd plan args...]
plan_and_apply_lifecycle_phases() {
  local stage=$1
  local intent=$2
  local host=$3
  local plan_stem=$4
  shift 4
  local max_phases=3
  local phase=1
  while [[ "$phase" -le "$max_phases" ]]; do
    local plan_path="$STATE_DIR/${plan_stem}-phase${phase}.plan.json"
    log "Stage ${stage} phase ${phase}: plan ${intent} for ${host}"
    nxd plan "deployment-target/${host}" \
      --source "$NXD_SOURCE" \
      --out "$plan_path" \
      "$@"
    local plan_name
    plan_name=$(jq -r '.metadata.name // empty' "$plan_path" 2>/dev/null || true)
    local action_count
    action_count=$(jq '.spec.actions | length' "$plan_path" 2>/dev/null || echo 0)
    if [[ "$action_count" -eq 0 ]]; then
      die "stage ${stage} phase ${phase}: empty plan for ${host}"
    fi
    apply_with_approval "$plan_path"
    if [[ "$plan_name" == *enrollment* ]]; then
      echo "Applied enrollment-only plan; replanning for host lifecycle phase."
      phase=$((phase + 1))
      continue
    fi
    record "$stage" "$intent" "$host" "pass" "phases=$phase plan=$plan_name"
    return 0
  done
  die "stage ${stage}: exceeded ${max_phases} plan/apply phases for ${host}"
}

# Plan a lifecycle intent. Optional third arg is a full host spec such as
# `medo-test=192.168.1.10` (operation-scoped endpoint override for post-convert
# day-2 work when inventory still points at a different guest identity).
plan_intent() {
  local host=$1
  local intent=$2
  local host_spec=${3:-$host}
  local out="$STATE_DIR/${intent}-${host}.plan.json"
  rm -f "$out"
  if ! nxd plan "$host_spec" \
    --intent "$intent" \
    --source "$NXD_SOURCE" \
    --out "$out" >/dev/null
  then
    die "plan failed for intent=$intent host_spec=$host_spec"
  fi
  [[ -f "$out" ]] || die "plan did not write $out"
  local non_noop
  non_noop=$(jq '[.spec.actions[]? | select(.operation != "noop")] | length' "$out")
  printf '%s|%s\n' "$out" "$non_noop"
}

wait_ssh() {
  local user=$1
  local ip=$2
  local label=$3
  local trust=${4:-transient}
  local reachable=false
  for i in $(seq 1 40); do
    echo "Checking ${label} reachability ($i/40)..."
    if nc -z -w 2 "$ip" 22 2>/dev/null; then
      if [[ "$trust" == "stable" ]] \
        && ssh_stable "${user}@${ip}" "echo ready" >/dev/null 2>&1; then
        reachable=true
        break
      elif [[ "$trust" == "transient" ]] \
        && ssh_transient "${user}@${ip}" "echo ready" >/dev/null 2>&1; then
        reachable=true
        break
      fi
    fi
    sleep 5
  done
  [[ "$reachable" == true ]] || die "${label} SSH not reachable within timeout"
}

echo "Using NXD candidate: $NXD_BIN"
nxd --version
record "meta" "version" "-" "ok" "$(nxd --version 2>&1 | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# Stage 1: install (cloud-init recreate)
# ---------------------------------------------------------------------------
if [[ "${SKIP_INSTALL:-}" == "1" ]]; then
  log "Stage 1: SKIP_INSTALL=1 — skip cloud-init install"
  record "1" "install" "$HOST_CLOUDINIT" "skip" "SKIP_INSTALL=1"
else
	plan_and_apply_lifecycle_phases \
    "1" \
    "install" \
    "$HOST_CLOUDINIT" \
    "install-${HOST_CLOUDINIT}" \
    --intent install \
    --install-mode replace
fi

# ---------------------------------------------------------------------------
# Stage 2: resolve IP + wait cloud-init SSH
# ---------------------------------------------------------------------------
log "Stage 2: Resolve $HOST_CLOUDINIT IP and wait for cloud-init SSH"
TARGET_IP=$(nxd info "$HOST_CLOUDINIT" --ip --wait | tr -d '\r\n[:space:]')
[[ -n "$TARGET_IP" ]] || die "failed to resolve IP for $HOST_CLOUDINIT"
echo "Target IP: $TARGET_IP"
wait_ssh "$SSH_USER_CLOUDINIT" "$TARGET_IP" "cloud-init" transient
record "2" "observe-ssh" "$HOST_CLOUDINIT" "pass" "ip=$TARGET_IP"


# ---------------------------------------------------------------------------
# Stage 3: convert → medo-test
# ---------------------------------------------------------------------------
log "Stage 3: Plan+apply convert $HOST_DEST from ${SSH_USER_CLOUDINIT}@${HOST_CLOUDINIT}"
export NXD_CONVERT_FROM="${SSH_USER_CLOUDINIT}@${HOST_CLOUDINIT}"
# Option A two-phase: phase 1 may be enrollment-only (preauth create+sink);
# phase 2 replans after restaged secrets and runs the Nix convert lifecycle.
plan_and_apply_lifecycle_phases \
  "3" \
  "convert" \
  "$HOST_DEST" \
  "convert-${HOST_DEST}" \
  --intent convert \
  --convert-from "$NXD_CONVERT_FROM"

# ---------------------------------------------------------------------------
# Stage 4–5: wait NixOS + verify identity
# ---------------------------------------------------------------------------
log "Stage 4: Re-resolve converted source VM and wait for NixOS SSH as $SSH_USER_NIXOS"
# The converted machine retains the reviewed source provider identity/VMID, but
# its DHCP lease may change across the forced reboot.  Re-observe that durable
# source resource instead of retaining the pre-takeover address or resolving
# the independently configured destination VM.
TARGET_IP=$(nxd info "$HOST_CLOUDINIT" --ip --wait | tr -d '\r\n[:space:]')
[[ -n "$TARGET_IP" ]] || die "failed to re-resolve converted source VM $HOST_CLOUDINIT"
echo "Converted source VM IP: $TARGET_IP"
prepare_stable_known_hosts "$HOST_DEST" "$TARGET_IP"
wait_ssh "$SSH_USER_NIXOS" "$TARGET_IP" "NixOS" stable
record "4" "ssh" "$HOST_DEST" "pass" "ip=$TARGET_IP"

log "Stage 5: Verify hostname / nixos-version"
ACTUAL_HOSTNAME=$(ssh_stable "${SSH_USER_NIXOS}@${TARGET_IP}" "hostname" | tr -d '\r\n[:space:]')
NIXOS_VER=$(ssh_stable "${SSH_USER_NIXOS}@${TARGET_IP}" "nixos-version")
echo "hostname=$ACTUAL_HOSTNAME nixos-version=$NIXOS_VER"
[[ "$ACTUAL_HOSTNAME" == "$HOST_DEST" ]] || die "hostname mismatch: expected $HOST_DEST got $ACTUAL_HOSTNAME"
record "5" "verify" "$HOST_DEST" "pass" "hostname=$ACTUAL_HOSTNAME ver=$NIXOS_VER"

# Day-2 activation plans resolve the host by name (inventory/tailnet). Wait until
# hostname SSH works — IP-only SSH is not enough after convert reboot.
log "Stage 5b: Wait for hostname SSH as ${SSH_USER_NIXOS}@${HOST_DEST}"
HOST_REACHABLE=false
for i in $(seq 1 60); do
  echo "Checking hostname reachability ($i/60)..."
  if ssh_stable "${SSH_USER_NIXOS}@${HOST_DEST}" "echo ready" >/dev/null 2>&1; then
    HOST_REACHABLE=true
    break
  fi
  # Also accept inventory-resolved IP once nxd info works by name.
  if RESOLVED=$(nxd info "$HOST_DEST" --ip 2>/dev/null | tr -d '\r\n[:space:]'); then
    if [[ -n "$RESOLVED" ]] && ssh_stable "${SSH_USER_NIXOS}@${RESOLVED}" "echo ready" >/dev/null 2>&1; then
      # Prefer waiting for name when possible; continue until name works or timeout.
      if ssh_stable "${SSH_USER_NIXOS}@${HOST_DEST}" "echo ready" >/dev/null 2>&1; then
        HOST_REACHABLE=true
        break
      fi
    fi
  fi
  sleep 5
done
if [[ "$HOST_REACHABLE" != true ]]; then
  echo "WARN: hostname ${HOST_DEST} still unreachable; day-2 plans may be non-noop due to observe failure"
  record "5b" "hostname-ssh" "$HOST_DEST" "warn" "timeout"
else
  record "5b" "hostname-ssh" "$HOST_DEST" "pass" "ok"
fi

# ---------------------------------------------------------------------------
# Stage 6: day-2 intent matrix (pure activation + build-only)
# ---------------------------------------------------------------------------
# After convert, the live machine is still the cloud-init source guest (VMID of
# $HOST_CLOUDINIT) with hostname $HOST_DEST. Inventory for $HOST_DEST often
# points at a different guest that is absent. Day-2 switch/boot/test therefore
# use the convert-time IP as an operation-scoped endpoint override so NXD can
# prove canonical SSH identity under topology drift (design: host=IP).
log "Stage 6: Day-2 lifecycle intent matrix on $HOST_DEST"
DAY2_SPEC="$HOST_DEST"
if [[ -n "${TARGET_IP:-}" ]]; then
  DAY2_SPEC="${HOST_DEST}=${TARGET_IP}"
  echo "Day-2 endpoint override: $DAY2_SPEC (post-convert live address)"
fi

# When the independently configured destination guest is absent, only the
# exact operation-scoped IP may bridge the in-place conversion's topology
# drift. A preceding replacement test may intentionally leave that guest
# present; in that case its provider-attested endpoint makes the plain plan
# valid, while this lifecycle continues to select the converted source through
# the explicit endpoint and canonical SSH identity.
OWNING_GUEST_IP=$(nxd info "$HOST_DEST" --ip 2>/dev/null | tr -d '\r\n[:space:]' || true)
if [[ -z "$OWNING_GUEST_IP" ]]; then
  if nxd plan "deployment-target/${HOST_DEST}" --intent switch \
    --source "$NXD_SOURCE" --out "$STATE_DIR/no-override.plan.json" >/dev/null 2>&1; then
    die "absent provider guest unexpectedly allowed switch without endpoint override"
  fi
else
  record "6a" "topology-drift-refusal" "$HOST_DEST" "skip" \
    "owning guest present at ${OWNING_GUEST_IP}; exact converted endpoint remains selected"
fi
if nxd plan "${HOST_DEST}=127.0.0.1" --intent switch \
  --source "$NXD_SOURCE" --out "$STATE_DIR/mismatched-key.plan.json" >/dev/null 2>&1; then
  die "mismatched endpoint identity unexpectedly produced a switch plan"
fi
for intent in observe build-only boot test switch; do
  # observe/build-only do not require a live endpoint; keep plain target.
  if [[ "$intent" == "observe" || "$intent" == "build-only" ]]; then
    result=$(plan_intent "$HOST_DEST" "$intent")
  else
    result=$(plan_intent "$HOST_DEST" "$intent" "$DAY2_SPEC")
  fi
  plan_path=${result%%|*}
  non_noop=${result##*|}
  echo "intent=$intent non_noop=$non_noop plan=$plan_path"
  record "6" "$intent" "$HOST_DEST" "pass" "non_noop=$non_noop"
done

PLAN_SW="$STATE_DIR/switch-${HOST_DEST}.plan.json"
SW_NON=$(jq '[.spec.actions[]? | select(.operation != "noop")] | length' "$PLAN_SW")
if [[ "$SW_NON" != "0" ]]; then
  if [[ "$HOST_REACHABLE" != true ]]; then
    die "switch plan is non-noop but hostname SSH is down; refuse apply (likely observe failure)"
  fi
  log "Stage 6b: Replan and apply non-noop switch (fresh provider digests)"
  # Replan immediately before apply so executable digests match the running NXD.
  result=$(plan_intent "$HOST_DEST" "switch" "$DAY2_SPEC")
  PLAN_SW=${result%%|*}
  SW_NON=${result##*|}
  apply_with_approval "$PLAN_SW"
  record "6b" "switch-apply" "$HOST_DEST" "pass" "non_noop=$SW_NON"
else
  echo "switch already current — skip apply"
  record "6b" "switch-apply" "$HOST_DEST" "skip" "noop"
fi

log "Stage 6c: Verify zero-action repeat for the exact endpoint override"
result=$(plan_intent "$HOST_DEST" "switch" "$DAY2_SPEC")
repeat_non_noop=${result##*|}
[[ "$repeat_non_noop" == "0" ]] || die "repeat switch is not idempotent: $repeat_non_noop actions"
record "6c" "switch-repeat" "$HOST_DEST" "pass" "zero-action"

# ---------------------------------------------------------------------------
# Stage 7: destroy (optional)
# ---------------------------------------------------------------------------
if [[ "${SKIP_DESTROY:-}" == "1" ]]; then
  log "Stage 7: SKIP_DESTROY=1 — leave converted guest running"
  record "7" "destroy" "$HOST_CLOUDINIT" "skip" "SKIP_DESTROY=1"
  cleanup_done=1
else
  # Convert mutates the cloud-init source guest in place. Destroy that guest,
  # not the separate inventory identity for $HOST_DEST (often a different VMID).
  log "Stage 7: Plan+apply destroy for converted source guest $HOST_CLOUDINIT"
  PLAN_D="$STATE_DIR/destroy-${HOST_CLOUDINIT}.plan.json"
  nxd plan "deployment-target/${HOST_CLOUDINIT}" \
    --intent destroy \
    --source "$NXD_SOURCE" \
    --out "$PLAN_D"
  apply_with_approval "$PLAN_D"
  cleanup_done=1
  record "7" "destroy" "$HOST_CLOUDINIT" "pass" "applied converted source guest"

  log "Stage 7b: Post-destroy observe plan for $HOST_CLOUDINIT"
  plan_intent "$HOST_CLOUDINIT" "observe" >/dev/null
  record "7b" "observe" "$HOST_CLOUDINIT" "pass" "post-destroy"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "Lifecycle disposable E2E summary"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo
echo "Plans and evidence: $STATE_DIR"
echo "PASS: full lifecycle disposable test completed"
cleanup 0
