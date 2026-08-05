# Inventory guest (PVE VMID 108 on pve2). Backup-job membership; not a NixOS deploy target.
{
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;
  role = "server";

  deployment = {
    vmid = "108";
    requireSecrets = false;
    proxmox = {
      provider = "pve2";
      diskStorage = "arthurz2-lvm";
    };
  };
}
