{
  class = "nixos";
  role = "router";
  system = "x86_64-linux";
  username = "nixos";

  deployment = {
    targetIp = "192.168.1.2";
    vmid = "105";
    proxmox = {
      host = "192.168.1.15";
      bios = "ovmf";
      diskBus = "scsi";
      network = "virtio,bridge=vmbr0";
      extraNetworks = [
        "virtio,bridge=vmbr1"
      ];
      iso = {
        type = "vlan";
      };
    };
  };
}
