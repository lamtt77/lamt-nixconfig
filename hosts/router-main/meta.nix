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
    vmid = "105";
    diskSize = "20";
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
      net0 = "virtio,bridge=vmbr0";
      extraNetworks = [
        "virtio,bridge=vmbr1"
      ];
      bootstrap = {
        interface = "net1";
        subnet = builtins.elemAt mydefs.defaultNetworks 0;
        vlan = 10;
      };
    };
  };
}
