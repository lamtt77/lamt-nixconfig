# Inventory guest (PVE VMID 101 on pve1). Backup-job membership; not a NixOS deploy target.
{
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;
  role = "server";

  deployment = {
    vmid = "101";
    requireSecrets = false;
    proxmox = {
      provider = "pve1";
      diskStorage = "arthurz2-lvm";
    };
  };
}
