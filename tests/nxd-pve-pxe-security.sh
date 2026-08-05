#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Static security check: retired PVE bootstrap packages and insecure patterns.
# Usage: ./tests/nxd-pve-pxe-security.sh
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for legacy_path in \
  "$repo_root/apps/pve-bootstrap-server" \
  "$repo_root/pkgs/pve-bootstrap-server" \
  "$repo_root/pkgs/pve-answer-server"; do
  if [[ -e "$legacy_path" ]]; then
    echo "bootstrap security: retired implementation remains at $legacy_path" >&2
    exit 1
  fi
done

if rg -n \
  'changeme|pve-answer-server|pve-bootstrap-server|systemd\.services\.atftpd' \
  "$repo_root/modules" "$repo_root/hosts" "$repo_root/overlays" "$repo_root/pkgs"; then
  echo "bootstrap security: prohibited legacy behavior found" >&2
  exit 1
fi

module="$repo_root/modules/os/feat/linux/services/pve-pxe.nix"
manifest="$repo_root/pkgs/pve-pxe-assets/default.nix"
rg -Fq 'passwordSecretName != null || cfg.allowGeneratedCredential' "$module"
rg -Fq 'RuntimeDirectory = "nxd-pve-bootstrap"' "$module"
rg -Fq 'dnsmasqPath = "${pkgs.dnsmasq}/bin/dnsmasq"' "$module"
# Public NXD command dispatches to the linked PVE-owned adapter.
rg -Fq 'nxd bootstrap serve' "$module"
if rg -Fq 'nxd-provider-pve bootstrap-serve' "$module"; then
  echo "bootstrap security: retired provider executable path remains in pve-pxe.nix" >&2
  exit 1
fi
for artifact in ipxeUndionly ipxeEfi autoexec answerTemplate; do
  rg -Fq "\"$artifact\"" "$manifest"
done

first_boot="$repo_root/infra/proxmox/pxe/templates/first-boot.sh"
rg -Fq 'systemctl poweroff --no-block' "$first_boot"
rg -Fq 'update-initramfs -u -k all' "$first_boot"
rg -Fq 'update-grub' "$first_boot"
rg -Fq 'proxmox-boot-tool refresh' "$first_boot"
extract_line=$(rg -nF 'tar -xzvf /tmp/configs.tar.gz -C /' "$first_boot" | cut -d: -f1)
initramfs_line=$(rg -nF 'update-initramfs -u -k all' "$first_boot" | cut -d: -f1)
grub_line=$(rg -nF 'update-grub' "$first_boot" | cut -d: -f1)
refresh_line=$(rg -nF 'proxmox-boot-tool refresh' "$first_boot" | cut -d: -f1)
poweroff_line=$(rg -nF 'systemctl poweroff --no-block' "$first_boot" | cut -d: -f1)
if ! ((extract_line < initramfs_line
  && initramfs_line < grub_line
  && grub_line < refresh_line
  && refresh_line < poweroff_line)); then
  echo "PVE first boot must restore state before activating boot policy and powering off" >&2
  exit 1
fi
if rg -Fq 'qemu-guest-agent' "$first_boot"; then
  echo "PVE first boot must not depend on a QEMU guest agent" >&2
  exit 1
fi

ipxe="$repo_root/infra/proxmox/pxe/templates/autoexec.ipxe"
rg -Fq 'ramdisk_size=16777216' "$ipxe"
if rg -Fq 'ramdisk_size=2097152' "$ipxe"; then
  echo "PXE boot must retain the Proxmox installer ramdisk ceiling" >&2
  exit 1
fi

test ! -e "$repo_root/pkgs/pve-pxe-assets/targets.nix"
test ! -e "$repo_root/infra/proxmox/pxe/targets.nix"
state_root="$repo_root/infra/proxmox/state/pve"
for node in pve1 pve2 pve-test; do
  answer="$repo_root/infra/proxmox/pxe/targets/$node/answer.toml"
  test -f "$answer"
  rg -Fq "fqdn = \"$node.lamhub.com\"" "$answer"
done
for node in pve1 pve2; do
  test -f "$state_root/$node/etc/default/grub"
  test -f "$state_root/$node/etc/kernel/cmdline"
  test -f "$state_root/$node/etc/modprobe.d/zfs.conf"
done
rg -Fq 'root=ZFS=rpool/ROOT/pve-1 boot=zfs' \
  "$state_root/pve1/etc/kernel/cmdline"
rg -Fq 'intel_iommu=on iommu=pt' \
  "$state_root/pve2/etc/kernel/cmdline"
rg -Fq 'blacklist qla2xxx' \
  "$state_root/pve2/etc/modprobe.d/pve-blacklist.conf"
rg -Fq 'blacklist mpt3sas' \
  "$state_root/pve2/etc/modprobe.d/pve-blacklist.conf"
if rg -n 'targetCfg|diskFilters|installerNetworkSource' \
  "$repo_root/pkgs/pve-pxe-assets"; then
  echo "PXE packaging must not construct target configuration from Nix inventory" >&2
  exit 1
fi
rg -Fq 'zstd -T0 -3 initrd -o initrd.zst' \
  "$repo_root/pkgs/pve-pxe-assets/default.nix"

for node in pve1 pve2 pve-test; do
  test -f "$state_root/$node/etc/network/interfaces"
  test -f "$state_root/$node/etc/resolv.conf"
  if [[ -e "$state_root/$node/etc/pve" ]]; then
    echo "bootstrap security: normal node state contains forbidden pmxcfs path for $node" >&2
    exit 1
  fi
done
for node in pve1 pve2; do
  rg -Fq 'Components: pve-no-subscription' \
    "$state_root/$node/etc/apt/sources.list.d/proxmox.sources"
done
# Physical-node capture preserves the operator's preferred disabled-extension
# convention, while the disposable authored state uses Deb822 Enabled: no.
test -f "$state_root/pve2/etc/apt/sources.list.d/pve-enterprise.disabled"
test -f "$state_root/pve2/etc/apt/sources.list.d/ceph.disabled"
test -f "$state_root/pve-test/etc/apt/sources.list.d/pve-no-subscription.sources"
rg -Fq 'Enabled: no' "$state_root/pve-test/etc/apt/sources.list.d/pve-enterprise.sources"
rg -Fq 'Enabled: no' "$state_root/pve-test/etc/apt/sources.list.d/ceph.sources"
rg -Fq 'normal PVE install state must not contain /etc/pve' \
  "$repo_root/pkgs/pve-pxe-assets/default.nix"
test -f "$repo_root/infra/proxmox/recovery/pve/barcluster/corosync.conf.in"
test -f "$repo_root/infra/proxmox/recovery/pve/barcluster/storage.cfg.in"

lane="$repo_root/tests/nxd-pve-pxe.sh"
if rg -n \
  'StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|(^|[[:space:]])qm([[:space:]]|$)|(^|[[:space:]])ssh([[:space:]]|$)|--force|read -[pr]|PROXMOX_HOST=|VMID=|TARGET_IP=' \
  "$lane"; then
  echo "bootstrap security: PXE lane contains direct mutation, insecure trust, prompt, force, or fallback state" >&2
  exit 1
fi
rg -Fq 'operation:pve-pxe' "$lane"
rg -Fq 'assert_install_plan "$install_plan"' "$lane"
rg -Fq 'assert_destroy_plan "$destroy_plan"' "$lane"
rg -Fq '.details.wire.details.desired.vmid == 911' "$lane"
rg -Fq 'nxd approval validate' "$lane"
rg -Fq 'nxd show run' "$lane"
rg -Fq 'zero-action' "$lane"

switch_lane="$repo_root/tests/nxd-disposable-switch.sh"
if rg -n \
  'StrictHostKeyChecking=no|UserKnownHostsFile=/dev/null|(^|[[:space:]])qm([[:space:]]|$)|(^|[[:space:]])ssh([[:space:]]|$)|--force|read -[pr]|TARGET_IP=|NXD_SWITCH_GLOB=' \
  "$switch_lane"; then
  echo "bootstrap security: disposable switch lane contains direct mutation, insecure trust, prompt, force, or fallback state" >&2
  exit 1
fi
rg -Fq 'NXD_SWITCH_TARGET:?set NXD_SWITCH_TARGET' "$switch_lane"
rg -Fq 'switch_targets=($NXD_SWITCH_TARGET)' "$switch_lane"
rg -Fq 'selectors=("${switch_targets[@]/#/deployment-target/}")' "$switch_lane"
rg -Fq 'nxd approval create' "$switch_lane"
rg -Fq 'nxd verify' "$switch_lane"
rg -Fq 'nxd show run' "$switch_lane"
rg -Fq 'repeat.plan.json' "$switch_lane"

echo "bootstrap security: passed"
