#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Authoritative disposable PVE PXE lane. All target observation and mutation
# goes through one NXD operation set and its linked first-party providers.
set -euo pipefail

: "${NXD_BIN:?set NXD_BIN to the reviewed nxd binary}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${NXD_CONFIG_JSON:=}"
: "${NXD_HOST_STATE_E2E:=0}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${DEFAULT_SECRETS_REPO:=$NXD_SECRETS_REPO}"
export DEFAULT_SECRETS_REPO
export DEFAULT_SECRETS_SITE="${DEFAULT_SECRETS_SITE:-bar}"
if [[ -z "$NXD_CONFIG_JSON" ]]; then
  export NXD_SOURCE
else
  unset NXD_SOURCE
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || realpath "$NXD_BIN")
state_dir="$repo_root/.nxd/e2e-pxe"
mkdir -p "$state_dir"

operation="operation:pve-pxe"
run_id="lamt-pve-pxe-$(date -u +%Y%m%dT%H%M%SZ)-$$"
install_plan="$state_dir/install.plan.json"
install_approval="$state_dir/install.approval.json"
destroy_plan="$state_dir/destroy.plan.json"
destroy_approval="$state_dir/destroy.approval.json"
mutation_started=0
cleanup_done=0

nxd() {
  "$NXD_BIN" "$@"
}

config_args=()
if [[ -n "$NXD_CONFIG_JSON" ]]; then
  config_args=(--config-json "$NXD_CONFIG_JSON")
else
  config_args=(--source "$NXD_SOURCE")
fi

assert_install_plan() {
  jq -e '
    (.spec.actions | length) == 1
    and .spec.actions[0].providerInstance == "provider/pve1"
    and .spec.actions[0].resource == "guest/pve-test"
    and .spec.actions[0].timeoutSeconds == 1800
    and .spec.actions[0].details.wire.details.desired.vmid == 911
    and (
      (
        .spec.actions[0].id == "pve:guest/pve-test:create"
        and .spec.actions[0].operation == "create"
        and .spec.actions[0].risk == "identity-critical"
      )
      or
      (
        .spec.actions[0].id == "pve:guest/pve-test:replace"
        and .spec.actions[0].operation == "update"
        and .spec.actions[0].risk == "destructive"
      )
    )
  ' "$1" >/dev/null
}

assert_destroy_plan() {
  jq -e '
    (.spec.actions | length) == 1
    and .spec.actions[0].id == "pve:guest/pve-test:delete"
    and .spec.actions[0].providerInstance == "provider/pve1"
    and .spec.actions[0].resource == "guest/pve-test"
    and .spec.actions[0].operation == "delete"
    and .spec.actions[0].risk == "destructive"
    and .spec.actions[0].details.wire.details.desired.vmid == 911
  ' "$1" >/dev/null
}

cleanup() {
  local status=${1:-0}
  trap - EXIT HUP INT TERM
  if [[ "$mutation_started" -eq 1 && "$cleanup_done" -eq 0 ]]; then
    echo "PXE lane cleanup: planning exact disposable target destruction" >&2
    if nxd plan "$operation" --intent destroy "${config_args[@]}" --out "$destroy_plan" \
      && assert_destroy_plan "$destroy_plan" \
      && nxd approval create --plan "$destroy_plan" --out "$destroy_approval" \
        --principal "nxd-pve-pxe@lamt-nixconfig" \
      && nxd apply "$destroy_plan" --approval "$destroy_approval" \
        --run-id "${run_id}-cleanup"; then
      cleanup_done=1
    else
      echo "PXE lane cleanup failed; reviewed plan retained at $destroy_plan" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap 'cleanup $?' EXIT HUP INT TERM

echo "Using NXD candidate: $NXD_BIN"
nxd --version

# The operation set is the only selector accepted by this lane. Assert that it
# resolves exactly the owner-approved provider-owned guest and canonical VMID;
# there are no legacy deployment targets, fallback endpoints, nodes, or VM IDs.
nxd show config "$operation" "${config_args[@]}" --format json >"$state_dir/selection.json"
jq -e '
  ([.spec.resources[] | select(.kind == "deploymentTarget")] | length == 0)
  and ([.spec.resources[] | select(
    .id == "guest/pve-test"
    and .vmid == 911
    and .provisioning.networks == [
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrTestWan"
    ]
  )] | length == 1)
' "$state_dir/selection.json" >/dev/null

nxd plan "$operation" \
  --intent install \
  --install-mode replace \
  "${config_args[@]}" \
  --out "$install_plan"
assert_install_plan "$install_plan"
nxd approval create \
  --plan "$install_plan" \
  --out "$install_approval" \
  --principal "nxd-pve-pxe@lamt-nixconfig"
nxd approval validate --plan "$install_plan" --approval "$install_approval" --format json \
  >"$state_dir/install.approval-validation.json"

mutation_started=1
nxd apply "$install_plan" --approval "$install_approval" --run-id "$run_id"
nxd verify "$operation" "${config_args[@]}" --format json >"$state_dir/verify.json"
jq -e '.kind == "VerificationReport" and .spec.status == "passed"' \
  "$state_dir/verify.json" >/dev/null
nxd show run "$run_id" --format json >"$state_dir/run.json"
jq -e '.status == "succeeded"' "$state_dir/run.json" >/dev/null

# Reconcile the provider-owned desired state without another install intent.
# This is the zero-action idempotency proof: there must be no mutation action left.
nxd plan "$operation" "${config_args[@]}" --out "$state_dir/repeat.plan.json"
jq -e '[.spec.actions[]? | select(.operation != "noop")] | length == 0' \
  "$state_dir/repeat.plan.json" >/dev/null

if [[ "$NXD_HOST_STATE_E2E" == 1 ]]; then
  if [[ -z "$NXD_CONFIG_JSON" ]]; then
    echo "NXD_HOST_STATE_E2E=1 requires NXD_CONFIG_JSON" >&2
    exit 1
  fi
  host_state_config="$state_dir/host-state-test-config.json"
  host_state_plan="$state_dir/host-state.plan.json"
  host_state_repeat="$state_dir/host-state-repeat.plan.json"
  host_state_capture="$state_dir/host-state-capture-${run_id}"
  host_state_path="/etc/apt/sources.list.d/nxd-host-state-e2e.sources"
  host_state_content=$'# NXD disposable host-state reconciliation proof.\nTypes: deb\nURIs: http://download.proxmox.com/debian/pve\nSuites: trixie\nComponents: pve-no-subscription\nEnabled: no\n'
  host_state_digest=$(printf '%s' "$host_state_content" | shasum -a 256 | awk '{print $1}')

  jq \
    --arg path "$host_state_path" \
    --arg content "$host_state_content" \
    --arg digest "$host_state_digest" \
    '(.spec.resources[] | select(.id == "pve-host-state/pve-test").files) += [{
      path: $path,
      content: $content,
      contentDigest: $digest,
      mode: "0644"
    }]' \
    "$NXD_CONFIG_JSON" >"$host_state_config"

  nxd plan pve-host-state/pve-test \
    --config-json "$host_state_config" \
    --out "$host_state_plan"
  jq -e '
    [.spec.actions[] | select(
      .resource == "pve-host-state/pve-test"
      and .operation == "update"
      and .risk == "service-impacting"
    )] | length == 1
  ' "$host_state_plan" >/dev/null
  nxd apply "$host_state_plan" \
    --run-id "${run_id}-host-state"
  nxd verify pve-host-state/pve-test \
    --config-json "$host_state_config" \
    --format json >"$state_dir/host-state-verify.json"
  jq -e '.kind == "VerificationReport" and .spec.status == "passed"' \
    "$state_dir/host-state-verify.json" >/dev/null
  nxd plan pve-host-state/pve-test \
    --config-json "$host_state_config" \
    --out "$host_state_repeat"
  jq -e '[.spec.actions[]? | select(.operation != "noop")] | length == 0' \
    "$host_state_repeat" >/dev/null
  nxd capture pve-host-state/pve-test \
    --config-json "$host_state_config" \
    --out "$host_state_capture" \
    --format json >"$state_dir/host-state-capture.json"
  jq -e '
    .status == "complete"
    and ([.outcomes[] | select(
      .node == "pve-host-state/pve-test"
      and .status == "captured"
    )] | length == 1)
  ' "$state_dir/host-state-capture.json" >/dev/null
  test -f "$host_state_capture/pve-test${host_state_path}"
  grep -Fxq '# NXD disposable host-state reconciliation proof.' \
    "$host_state_capture/pve-test${host_state_path}"
fi

cleanup 0
