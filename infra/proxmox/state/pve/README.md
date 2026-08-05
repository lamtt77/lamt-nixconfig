# Reviewed LAMT PVE host state

This directory is the authoritative, filtered host-local state used by the PVE
installer artifacts. Its layout matches FCM:

```text
infra/proxmox/state/pve/<node>/etc/...
```

Only files intentionally safe to restore to that exact node belong here. The
PXE artifact builder rejects `/etc/pve` content: pmxcfs, cluster membership,
storage, access, notification, job, and guest state are owned by typed NXD PVE
resources or the separately authorized total-cluster recovery procedure.

Installation media, answer files, iPXE, and first-boot mechanics remain under
`pkgs/pve-pxe-assets`; they are not machine state. Captured package lists may
be kept as evidence but are never interpreted as an imperative package list.

Boot and module policy is captured from the real node, not copied between
sites. `pve1` currently boots legacy BIOS/GRUB; `pve2` boots UEFI through
`proxmox-boot-tool`. Both retained `/etc/default/grub` and
`/etc/kernel/cmdline` are preserved as host-local state, while first boot
activates only the loader appropriate to the installed firmware. Deliberate
`zfs.conf` and passthrough blacklists are retained; package defaults, ESP UUID
registries, generated initrds, and `/boot` output are not.
