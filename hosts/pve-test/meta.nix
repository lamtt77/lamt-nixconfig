let
  mydefs = import ../../defines.nix;
in
{
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;

  deployment = {
    vmid = "911";
    targetIp = "192.168.250.10";
    sshProxyJump = "nixos@192.168.1.20";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "seabios";
      diskBus = "virtio";
      cores = "2";
      memory = "8192";
      network = "virtio,bridge=vmbrPxe";
      extraNetworks = [
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrTestWan"
      ];
      pxe = true;
    };
  };
}
