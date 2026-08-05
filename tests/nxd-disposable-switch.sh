#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Authoritative disposable day-2 switch lane. Target selection, approval,
# mutation, verification, terminal journals, and repeats stay in NXD.
set -euo pipefail

: "${NXD_BIN:?set NXD_BIN to the reviewed nxd binary}"
: "${NXD_SWITCH_TARGET:?set NXD_SWITCH_TARGET to one disposable deployment target}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${NXD_CONFIG_JSON:=}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
: "${DEFAULT_SECRETS_REPO:=$NXD_SECRETS_REPO}"
export DEFAULT_SECRETS_REPO
export DEFAULT_SECRETS_SITE="${DEFAULT_SECRETS_SITE:-bar}"

set -f
switch_targets=($NXD_SWITCH_TARGET)
set +f
(( ${#switch_targets[@]} > 0 )) \
  || { echo "NXD_SWITCH_TARGET must name at least one disposable target" >&2; exit 1; }
for target in "${switch_targets[@]}"; do
  [[ "$target" == *-test ]] \
    || { echo "NXD_SWITCH_TARGET must contain only names ending in -test: $target" >&2; exit 1; }
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
NXD_BIN=$(command -v "$NXD_BIN" 2>/dev/null || realpath "$NXD_BIN")
state_dir="$repo_root/.nxd/e2e-switch"
mkdir -p "$state_dir"

config_args=()
if [[ -n "$NXD_CONFIG_JSON" ]]; then
  config_args=(--config-json "$NXD_CONFIG_JSON")
else
  config_args=(--source "$NXD_SOURCE")
fi

nxd() {
  "$NXD_BIN" "$@"
}

assert_disposable_target() {
  local selection=$1
  local target=$2
  nxd show config "deployment-target/$target" "${config_args[@]}" --format json >"$selection"
  jq -e --arg target "deployment-target/$target" '
    [.spec.resources[] | select(.kind == "deploymentTarget") | .id] == [$target]
  ' "$selection" >/dev/null
}

apply_switch() {
  local label=$1
  shift
  local plan="$state_dir/$label.plan.json"
  local approval="$state_dir/$label.approval.json"
  local run_id="lamt-disposable-switch-$label-$(date -u +%Y%m%dT%H%M%SZ)-$$"

  nxd plan "$@" --intent switch "${config_args[@]}" --out "$plan"

  if jq -e '.spec.approvalRequirements | length > 0' "$plan" >/dev/null; then
    nxd approval create --plan "$plan" --out "$approval" --principal "nxd-disposable-switch@lamt-nixconfig"
    nxd approval validate --plan "$plan" --approval "$approval" --format json >"$state_dir/$label.approval-validation.json"
    nxd apply "$plan" --approval "$approval" --run-id "$run_id"
  else
    nxd apply "$plan" --run-id "$run_id"
  fi

  nxd verify "$@" "${config_args[@]}" --format json >"$state_dir/$label.verify.json"
  jq -e '.kind == "VerificationReport" and .spec.status == "passed"' "$state_dir/$label.verify.json" >/dev/null
  nxd show run "$run_id" --format json >"$state_dir/$label.run.json"
  jq -e '.status == "succeeded"' "$state_dir/$label.run.json" >/dev/null

  nxd plan "$@" --intent switch "${config_args[@]}" --out "$state_dir/$label.repeat.plan.json"
  jq -e '[.spec.actions[]? | select(.operation != "noop")] | length == 0' \
    "$state_dir/$label.repeat.plan.json" >/dev/null
}

echo "Using NXD candidate: $NXD_BIN"
nxd --version
for target in "${switch_targets[@]}"; do
  assert_disposable_target "$state_dir/$target.selection.json" "$target"
done
selectors=("${switch_targets[@]/#/deployment-target/}")
apply_switch selected "${selectors[@]}"

echo "PASS: selected disposable switch lifecycle completed"
