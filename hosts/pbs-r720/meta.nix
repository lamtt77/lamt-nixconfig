# PBS appliance guest (Proxmox Backup Server), not a NixOS install target.
# Install OS with the unattended PBS ISO flow (same model as FCM fcmPBS*):
# PBS appliance lifecycle is owned by the canonical PVE/PBS resources.
# Do NOT use `nxd deploy` NixOS install for this host.
# After PBS is running, reconcile the canonical operation:pbs selection.
{
  # Not a nixosConfigurations system (see infra buildSystem filter).
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;
  role = "server";

  deployment = {
    vmid = "122";
    # Installer secrets for NixOS path are not used; PBS uses ISO answer + first-boot.
    requireSecrets = false;
    diskSize = "20";
    # Static address after PBS install (also site.hosts.pbs-r720 / PBS API origin).
    # targetIp is injected from infra site.hosts.
    proxmox = {
      provider = "pve2";
      diskStorage = "local-zfs";
      bios = "ovmf";
      diskBus = "scsi";
      scsiHw = "virtio-scsi-single";
      cores = "2";
      memory = "4096";
      # Site default LAN on pve2 (192.168.1.22 on vlan 10).
      net0 = "virtio,bridge=vmbr1,tag=10";
      # Unattended PBS ISO on shared ISO storage (never the NixOS minimal ISO).
      iso = {
        storage = "arthurz2-dir";
        customPath = "arthurz2-dir:iso/lamt-pbs-r720-auto.iso";
      };
    };
  };
}
