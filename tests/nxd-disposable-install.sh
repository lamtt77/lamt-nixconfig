#!/usr/bin/env bash
set -euo pipefail

: "${NXD_BIN:?set NXD_BIN to the reviewed nxd binary}"
: "${NXD_SOURCE:=.#nxdConfigurations.lamt}"
: "${NXD_SECRETS_REPO:=$HOME/lamt-secrets}"
export DEFAULT_SECRETS_SITE="${DEFAULT_SECRETS_SITE:-bar}"
export DEFAULT_SECRETS_REPO="$NXD_SECRETS_REPO"

readonly ALLOWED_TARGETS=" air15vm-test medo-test pve-test ubuntu-cloudinit-test "
readonly STATE_DIR=".nxd/e2e-install"
mkdir -p "$STATE_DIR"

applied_targets=()
cleanup_running=0

die() {
  echo "ERROR: $*" >&2
  exit 1
}

assert_allowed() {
  local target=$1
  [[ "$ALLOWED_TARGETS" == *" $target "* ]] ||
    die "refusing non-authorized disposable target: $target"
}

selected_targets() {
  jq -r '
    .spec.resources[]?
    | select(.kind == "deploymentTarget")
    | .id
    | sub("^deployment-target/"; "")
  ' "$1" | sort -u
}

create_approval() {
  local plan=$1 approval=$2
  "$NXD_BIN" approval create --plan "$plan" --out "$approval" \
    --principal "nxd-disposable-install@lamt-nixconfig"
  "$NXD_BIN" approval validate --plan "$plan" --approval "$approval" --format json >/dev/null
}

apply_plan() {
  local plan=$1 run_id=$2 approval="${plan%.json}.approval.json"
  if jq -e '.spec.approvalRequirements | length > 0' "$plan" >/dev/null; then
    create_approval "$plan" "$approval"
    "$NXD_BIN" apply "$plan" --approval "$approval" --parallel 4 --run-id "$run_id"
  else
    "$NXD_BIN" apply "$plan" --parallel 4 --run-id "$run_id"
  fi
  "$NXD_BIN" show run "$run_id" --format json |
    jq -e '.status == "succeeded"' >/dev/null
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  [[ "$cleanup_running" -eq 0 ]] || exit "$status"
  cleanup_running=1
  if ((${#applied_targets[@]})); then
    local selectors=() target plan approval run_id
    for target in "${applied_targets[@]}"; do
      assert_allowed "$target"
      if [[ "$target" == "air15vm-test" ]]; then
        selectors+=("vmware/$target")
      else
        selectors+=("guest/$target")
      fi
    done
    plan="$STATE_DIR/cleanup.plan.json"
    if "$NXD_BIN" plan "${selectors[@]}" --intent destroy --source "$NXD_SOURCE" --out "$plan"; then
      run_id="lamt-disposable-cleanup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
      if ! apply_plan "$plan" "$run_id"; then
        echo "cleanup apply failed; reviewed plan retained at $plan" >&2
        status=1
      else
        approval="${plan%.json}.approval.json"
        "$NXD_BIN" plan "${selectors[@]}" --intent destroy --source "$NXD_SOURCE" \
          --out "$STATE_DIR/cleanup-repeat.plan.json"
        jq -e 'all(.spec.actions[]?; .operation == "noop")' \
          "$STATE_DIR/cleanup-repeat.plan.json" >/dev/null || status=1
        rm -f "$approval"
      fi
    else
      echo "cleanup planning failed; exact selectors retained in diagnostics" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

run_lane() {
  local label=$1
  shift
  local selection="$STATE_DIR/$label.selection.json"
  "$NXD_BIN" show config "$@" --source "$NXD_SOURCE" --format json >"$selection"

  local targets=() target
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    assert_allowed "$target"
    targets+=("$target")
  done < <(selected_targets "$selection")
  ((${#targets[@]})) || die "$label selection contains no deployment targets"

  if [[ "$label" == "parallel-glob" ]]; then
    ((${#targets[@]} == 4)) || die "glob lane did not select all four authorized targets"
    for target in air15vm-test medo-test pve-test ubuntu-cloudinit-test; do
      [[ " ${targets[*]} " == *" $target "* ]] || die "glob lane omitted $target"
    done
  else
    ((${#targets[@]} == 1)) && [[ "${targets[0]}" == "ubuntu-cloudinit-test" ]] ||
      die "exact lane selected anything other than ubuntu-cloudinit-test"
  fi

  for target in "${targets[@]}"; do
    [[ " ${applied_targets[*]} " == *" $target "* ]] || applied_targets+=("$target")
  done
  local phase=1 plan plan_name action_count
  while ((phase <= 3)); do
    plan="$STATE_DIR/$label-phase$phase.plan.json"
    "$NXD_BIN" plan "$@" --intent install --install-mode replace \
      --source "$NXD_SOURCE" --out "$plan"
    plan_name=$(jq -r '.metadata.name // empty' "$plan")
    action_count=$(jq '.spec.actions | length' "$plan")
    ((action_count > 0)) || die "$label phase $phase produced an empty plan"
    apply_plan "$plan" "lamt-disposable-$label-phase$phase-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    [[ "$plan_name" == *enrollment* ]] || break
    phase=$((phase + 1))
  done
  ((phase <= 3)) || die "$label exceeded three enrollment/install phases"

	local verify_selectors=() infrastructure_selectors=() nix_selectors=()
	for target in "${targets[@]}"; do
		if [[ "$target" == "air15vm-test" ]]; then
			verify_selectors+=("target:$target")
			infrastructure_selectors+=("vmware/$target")
			nix_selectors+=("deployment-target/$target")
		elif [[ "$target" == "medo-test" ]]; then
			verify_selectors+=("target:$target")
			infrastructure_selectors+=("guest/$target")
			nix_selectors+=("deployment-target/$target")
		else
			verify_selectors+=("guest/$target")
			infrastructure_selectors+=("guest/$target")
		fi
  done
  "$NXD_BIN" verify "${verify_selectors[@]}" --source "$NXD_SOURCE" --format json >/dev/null
  "$NXD_BIN" plan "${infrastructure_selectors[@]}" --source "$NXD_SOURCE" \
    --out "$STATE_DIR/$label-infrastructure-repeat.plan.json"
  jq -e '(.spec.actions | length) == 0' "$STATE_DIR/$label-infrastructure-repeat.plan.json" >/dev/null
  if ((${#nix_selectors[@]})); then
    "$NXD_BIN" plan "${nix_selectors[@]}" --intent switch --source "$NXD_SOURCE" \
      --out "$STATE_DIR/$label-nix-repeat.plan.json"
    jq -e 'all(.spec.actions[]?; .operation == "noop")' \
      "$STATE_DIR/$label-nix-repeat.plan.json" >/dev/null
  fi
}

run_lane exact target:ubuntu-cloudinit-test
run_lane parallel-glob \
  'glob:air15vm-t*' \
  'glob:medo-t*' \
  'glob:pve-t*' \
  'glob:ubuntu-c*'
