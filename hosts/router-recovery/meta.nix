let
  mydefs = import ../../defines.nix;
in
{
  class = "nixos";
  role = "router";
  osFeatures = [
    ../../modules/os/feat/linux/services/router.nix
    ../../modules/os/feat/linux/services/pve-pxe.nix
  ];
  system = "x86_64-linux";
  username = "nixos";

  deployment = {
    nameservers = mydefs.networkingDefaults.nameservers ++ [ "1.1.1.1" ];
    vmid = "910";
    diskSize = "20";
    requireSecrets = true;
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
      net0 = "virtio,bridge=vmbr0";
      cores = "2";
      memory = "2048";
      iso.customPath = "arthurz2-dir:iso/nixos-minimal-26.05-x86_64-linux-nxd-built.iso";
      extraNetworks = [
        "virtio,bridge=vmbr1"
        "virtio,bridge=vmbrPxe"
      ];
      bootstrap = {
        interface = "net1";
        vlan = 10;
        subnet = builtins.elemAt mydefs.defaultNetworks 0;
      };
    };
  };
}
