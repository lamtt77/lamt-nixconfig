#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# NXD canonical export smoke: eval stable/unstable parity, validate, build-only plan.
# Usage: NXD_BIN=$HOME/lab/nxd/target/debug/nxd ./tests/nxd-config-export.sh
set -euo pipefail

: "${NXD_BIN:=nxd}"
: "${DEFAULT_SECRETS_REPO:=$HOME/lamt-secrets}"
export DEFAULT_SECRETS_REPO
if ! command -v "$NXD_BIN" >/dev/null 2>&1; then
  echo "ERROR: NXD binary not found or not executable: $NXD_BIN" >&2
  exit 1
fi
echo "Using NXD candidate: $NXD_BIN"
nxd_input_args=()
# Flake input URL for nxd (modules/schemas), not the nxd binary ConfigSource env.
if [[ -n "${NXD_FLAKE_INPUT:-}" ]]; then
  nxd_input_args=(--override-input nxd "$NXD_FLAKE_INPUT")
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/lamt-nxd-integration.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

nxd_test_phase_start stable-canonical-eval
nix --extra-experimental-features "nix-command flakes" eval \
  --no-eval-cache \
  --json \
  "${nxd_input_args[@]}" \
  .#nxdConfigurations.lamt >"$tmp/stable.json"
nxd_test_phase_finish
nxd_test_phase_start unstable-canonical-eval
nix --extra-experimental-features "nix-command flakes" eval \
  --no-eval-cache \
  --json \
  "${nxd_input_args[@]}" \
  .#nxdConfigurations.lamtUnstable >"$tmp/unstable.json"
nxd_test_phase_finish

nxd_test_phase_start canonical-contract-assertions
diff -u "$tmp/stable.json" "$tmp/unstable.json"

jq -e '
  .apiVersion == "nxd.dev/v1alpha1"
  and .kind == "CanonicalConfig"
  and .metadata.name == "lamt"
  and (.spec.providerInstances | length) >= 1
  and ([.spec.resources[] | select(.kind == "guest")] | length) >= 1
  and ([.spec.resources[] | select(.kind == "deploymentTarget")] | length) >= 1
  and ([.spec.resources[] | select(
    .kind == "vmwareVm"
    and .id == "vmware/air15vm"
    and .provider == "provider/vmware"
    and .deploymentTarget == "deployment-target/air15vm"
    and (.installer.path | startswith("/"))
  )] | length) == 1
  and ([.spec.providerInstances[] | select(
    .id == "provider/vmware"
    and .arguments[0] == "--vmrun"
    and (.arguments[1] | startswith("/"))
    and .arguments[2] == "--vdiskmanager"
    and (.arguments[3] | startswith("/"))
  )] | length) == 1
  and ([.spec.resources[] | select(
    .id == "guest/ubuntu-cloudinit-test"
    and .provisioning.boot.kind == "cloudImage"
    and .provisioning.boot.image != ""
    and .provisioning.boot.user == "ubuntu"
    and .provisioning.boot.ipconfig0 == "ip=dhcp"
    and (.provisioning.boot.sshAuthorizedKeys | length) == 1
  )] | length) == 1
  and ([.spec.resources[] | select(.kind == "pveCluster") | .id] | sort) == ["pve-cluster/barcluster"]
  and ([.spec.resources[] | select(.kind == "pveNode") | .id] | sort) == [
    "pve-node/barcluster/pve1",
    "pve-node/barcluster/pve2"
  ]
  and ([.spec.resources[] | select(.kind == "backupJob")] | length) == 1
  and ([.spec.resources[] | select(.id == "backup-job/lamt-workloads-to-pbs-r720")] | length) == 1
  and ([.spec.resources[] | select(.id == "storage/pbs-r720-backup" and .storageType == "pbs")] | length) == 1
  and ([.spec.resources[] | select(
    .id == "datastore/pbs-r720/arthurz2-pbs"
    and .path == "/mnt/arthur_z2/PBS/pbs-r720"
    and .backingMount == {
      "source": "192.168.1.6:/mnt/arthur_z2/PBS",
      "mountPoint": "/mnt/arthur_z2/PBS",
      "fileSystem": "nfs",
      "options": ["defaults", "_netdev", "nofail", "x-systemd.automount", "vers=3"]
    }
  )] | length) == 1
  and ([.spec.resources[] | select(
    .id == "access-grant/pbs-r720/pve-backup"
    and .path == "/datastore/arthurz2-pbs/lamt"
  )] | length) == 1
  and ([.spec.resources[] | select(
    .id == "storage/pbs-r720-backup"
    and .pbsDatastore == "arthurz2-pbs"
  )] | length) == 1
  and (.spec.providerInstances[] | select(.id == "provider/pbs")
    | .config.hostStateTransports."pbs-r720"
    | .hostIdentity == "ssh-host-identity/pbs-r720"
      and .identityAgentBinding == "env/SSH_AUTH_SOCK"
      and (.identityPublicKey | startswith("ssh-ed25519 ")))
  and ([.spec.resources[] | select(.kind == "sshHostIdentity")] | length) == 23
  and ([.spec.resources[] | select(
    .id == "ssh-host-identity/router-recovery"
    and .publicBinding == "public/bar/hosts/router-recovery/identity"
  )] | length) == 1
  and ([.spec.providerInstances[].config.hostStateTransports? // {} | to_entries[] | .value
    | select(has("hostKey") or has("hostKeyFile") or has("proxyJumpHostKey"))] | length) == 0
  and ([.spec.resources[] | select(.id == "guest/vyos-1.3-rolling" and .vmid == 101)] | length) == 1
  and ([.spec.resources[] | select(.id == "guest/vyos-124-lambuilt28Mar2020" and .vmid == 108)] | length) == 1
  and ([.spec.resources[] | select(.id == "guest/freenas112R720" and .vmid == 113)] | length) == 1
  and ([.spec.resources[] | select(
    .id == "guest/pve-test"
    and .provisioning.networks == [
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrPxe",
      "virtio,bridge=vmbrTestWan"
    ]
  )] | length) == 1
  and ([.spec.secretBindings[] | select(
    .id == "secret/lamt-pve-api-token"
    or .id == "secret/pbs/pbs-r720/provision-token"
    or .id == "secret/pbs/pbs-r720/pve-backup-token"
  )] | sort_by(.id)) == [
    {
      "id": "secret/lamt-pve-api-token",
      "resolver": "sops-age",
      "reference": "bar/providers/pve.yaml#[\"token\"]"
    },
    {
      "id": "secret/pbs/pbs-r720/provision-token",
      "resolver": "sops-age",
      "reference": "bar/hosts/pbs-r720/pbs-r720.yaml#[\"provision-token\"]"
    },
    {
      "id": "secret/pbs/pbs-r720/pve-backup-token",
      "resolver": "sops-age",
      "reference": "bar/hosts/pbs-r720/pbs-r720.yaml#[\"pve-backup-token\"]"
    }
  ]
  and all(.spec.secretBindings[];
    (.reference | startswith("bar/pve.yaml") | not)
    and (.reference | startswith("bar/pbs.yaml") | not)
  )
  and ([.spec.artifactSets[] | .id] | sort) == [
    "artifact-set/nxd-kexec-aarch64",
    "artifact-set/nxd-kexec-x86_64"
  ]
' "$tmp/stable.json" >/dev/null
nxd_test_phase_finish

nxd_test_phase_start exact-target-inventory-parity
target_inventory_apply='inventories: builtins.mapAttrs (_: cfg: cfg // { spec = cfg.spec // { artifactSets = []; }; }) { inherit (inventories) macair15-m2 gaming; }'
nix --extra-experimental-features "nix-command flakes" eval \
  --no-eval-cache \
  --json \
  --apply "$target_inventory_apply" \
  "${nxd_input_args[@]}" \
  .#nxdTargetInventories.lamt >"$tmp/target-inventories-stable.json"
nix --extra-experimental-features "nix-command flakes" eval \
  --no-eval-cache \
  --json \
  --apply "$target_inventory_apply" \
  "${nxd_input_args[@]}" \
  .#nxdTargetInventories.lamtUnstable >"$tmp/target-inventories-unstable.json"
diff -u "$tmp/target-inventories-stable.json" "$tmp/target-inventories-unstable.json"
for target in macair15-m2 gaming; do
  jq --arg target "$target" '.[$target]' \
    "$tmp/target-inventories-stable.json" >"$tmp/target-${target}-stable.json"
  jq -e --slurpfile full "$tmp/stable.json" '
    . as $target
    | ($full[0]) as $site
    | all($target.spec.resources[];
        . as $selected | any($site.spec.resources[]; .id == $selected.id and . == $selected))
    and all($target.spec.providerInstances[];
        . as $selected | any($site.spec.providerInstances[]; .id == $selected.id and . == $selected))
    and all($target.spec.secretBindings[];
        . as $selected | any($site.spec.secretBindings[]; .id == $selected.id and . == $selected))
  ' "$tmp/target-${target}-stable.json" >/dev/null
done
jq -e '
  ([.spec.resources[].id] | sort) == ["deployment-target/macair15-m2"]
  and ([.spec.providerInstances[].id] | sort) == ["provider/nix"]
  and (.spec.secretBindings | length) == 0
  and (
    .spec.resources[]
    | select(.id == "deployment-target/macair15-m2")
    | .metadata.deployment.builder == ""
      and .metadata.deployment.localEval == true
  )
' "$tmp/target-macair15-m2-stable.json" >/dev/null
jq -e '
  ([.spec.resources[].id] | sort)
    == ["deployment-target/gaming", "deployment-target/utils", "guest/gaming", "ssh-host-identity/gaming"]
  and ([.spec.providerInstances[].id] | sort) == ["provider/identity", "provider/nix", "provider/pve1"]
  and ([.spec.secretBindings[].id] | sort) == [
    "public/bar/hosts/gaming/identity",
    "secret/bar/hosts/gaming/ssh-host-ed25519",
    "secret/lamt-pve-api-token"
  ]
  and (
    .spec.resources[]
    | select(.id == "deployment-target/gaming")
    | .metadata.deployment.builder == "deploy@utils"
      and .metadata.deployment.localEval == false
  )
  and (
    .spec.resources[]
    | select(.id == "deployment-target/utils")
    | .metadata.deployment.builder == "deploy@utils"
      and .metadata.deployment.localEval == false
  )
' "$tmp/target-gaming-stable.json" >/dev/null
nxd_test_phase_finish

nxd_test_phase_start direct-source-validation
"$NXD_BIN" validate \
  --source .#nxdConfigurations.lamt \
  --format json >"$tmp/validation.json"
jq -e '
  .apiVersion == "nxd.dev/v1alpha1"
  and .kind == "ValidationReport"
  and .spec.resourceCount >= 1
' "$tmp/validation.json" >/dev/null
nxd_test_phase_finish

# Direct-source selection contracts: named sets, exact IDs, globs, stable
# ordering, mixed-provider selection, and empty-selection refusal.
nxd_test_phase_start direct-source-selection-contracts
"$NXD_BIN" show config operation:pve \
  --config-json "$tmp/stable.json" --format json >"$tmp/pve-selection.json"
jq -e '
  all(.spec.resources[]; (.kind != "pveRole" and .kind != "pveAcl"))
  and all(.spec.resources[]; (.id | contains("pbs-r720-test") | not))
' "$tmp/pve-selection.json" >/dev/null
"$NXD_BIN" show config operation:pve operation:pbs \
  --config-json "$tmp/stable.json" --format json >"$tmp/mixed-selection.json"
"$NXD_BIN" show config deployment-target/gaming \
  --config-json "$tmp/stable.json" --format json >"$tmp/exact-selection.json"
"$NXD_BIN" show config label:site=lamt \
  --config-json "$tmp/stable.json" --format json >"$tmp/label-selection.json"
"$NXD_BIN" show config provider:provider/pve1 \
  --config-json "$tmp/stable.json" --format json >"$tmp/provider-selection.json"
"$NXD_BIN" show config 'glob:*-test' \
  --config-json "$tmp/stable.json" --format json >"$tmp/glob-selection.json"
"$NXD_BIN" show config 'glob:*-test' \
  --config-json "$tmp/stable.json" --format json >"$tmp/glob-selection-repeat.json"
diff -u "$tmp/glob-selection.json" "$tmp/glob-selection-repeat.json"
jq -e '
  ([.spec.resources[].id] == ([.spec.resources[].id] | sort))
  and ([.spec.resources[] | select(.kind == "guest")] | length) >= 1
  and (all(
    .spec.resources[] | select(.kind == "guest");
    (.id | endswith("-test") | not)
  ))
' "$tmp/pve-selection.json" >/dev/null
jq -e '.spec.resources | length >= 1' "$tmp/mixed-selection.json" >/dev/null
jq -e '[.spec.resources[].id] == ["deployment-target/gaming"]' "$tmp/exact-selection.json" >/dev/null
jq -e '.spec.resources | length >= 1' "$tmp/label-selection.json" >/dev/null
jq -e 'all(.spec.resources[]; .provider == "provider/pve1")' "$tmp/provider-selection.json" >/dev/null
jq -e '.spec.resources | length >= 1' "$tmp/glob-selection.json" >/dev/null
if "$NXD_BIN" show config 'glob:no-such-nxd-target-*' \
  --config-json "$tmp/stable.json" --format json >"$tmp/empty.out" 2>"$tmp/empty.err"; then
  echo "empty glob selection unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'matched no resources' "$tmp/empty.err"
if "$NXD_BIN" show config pve-test \
  --config-json "$tmp/stable.json" --format json >"$tmp/ambiguous.out" 2>"$tmp/ambiguous.err"; then
  echo "ambiguous bare selection unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'ambiguous' "$tmp/ambiguous.err"

if "$NXD_BIN" plan --config-json "$tmp/stable.json" >"$tmp/plan.out" 2>"$tmp/plan.err"; then
  echo "unscoped canonical plan unexpectedly succeeded" >&2
  exit 1
fi
test -s "$tmp/plan.err"
nxd_test_phase_finish

# Rust-only lifecycle recipes must never rewrite the consumer lock implicitly.
nxd_test_phase_start consumer-boundary-assertions
test "$(grep -Ec 'nix flake (lock|update).*--override-input nxd' justfile)" -eq 2
if grep -q '_ensure_path_nxd' justfile; then
  echo "legacy path-pin helper remains in justfile" >&2
  exit 1
fi
test "$(grep -Ec '\| jq|\$\(jq' justfile)" -eq 2
if grep -Eq '(^|[[:space:]])(ssh|scp|sops)([[:space:]]|$)' justfile; then
  echo "direct SSH or secret tooling remains in justfile" >&2
  exit 1
fi
if grep -Eq -- '--config-json|nxd-provider-|python3 -m|NXD_(APPLY|APPROVAL|LEGACY)' justfile; then
  echo "legacy provider or consumer orchestration remains in justfile" >&2
  exit 1
fi
grep -q 'nxdConfigurations.lamt' justfile
grep -q 'plan operation:pve' justfile
grep -q 'plan operation:pbs' justfile
nxd_test_phase_finish

deployment_target="deployment-target/gaming"
test -n "$deployment_target"
nxd_test_phase_start build-only-plan
"$NXD_BIN" plan "$deployment_target" \
  --intent build-only \
  --source .#nxdConfigurations.lamt \
  --out "$tmp/build-only-plan.json"
jq -e '
  .spec.lifecycleIntent == "build-only"
  and (.spec.actions | length) == 1
  and (.spec.actions[0].operation == "update" or .spec.actions[0].operation == "noop")
  and .spec.actions[0].details.wire.details.lifecycleIntent == "build-only"
  and .spec.actions[0].details.wire.details.phase == "build"
  and .spec.actions[0].details.wire.details.lifecyclePhases == ["prepare"]
  and .spec.actions[0].secretReferences == []
' "$tmp/build-only-plan.json" >/dev/null
nxd_test_phase_finish

nxd_test_phase_start install-refusal-plan
if "$NXD_BIN" plan "$deployment_target" --intent install --install-mode create \
  --source .#nxdConfigurations.lamt \
  --out "$tmp/install-plan.json" >"$tmp/install.out" 2>"$tmp/install.err"; then
  echo "create-only install unexpectedly accepted an existing owning guest" >&2
  exit 1
fi
grep -q 'guest/gaming already exists; use deploy --reinstall' "$tmp/install.err"
nxd_test_phase_finish

echo "LAMT canonical NXD deployment/guest export: passed"
