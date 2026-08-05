let
  mydefs = import ../../defines.nix;
in
{
  disposable = true;
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;

  deployment = {
    vmid = "911";
    diskSize = "20";
    sshProxyJump = "nixos@192.168.1.20";
    proxmox = {
      provider = "pve1";
      bios = "seabios";
      diskBus = "virtio";
      cores = "4";
      memory = "8196";
      discoverySubnets = [ "192.168.250.0/24" ];
      net0 = "virtio,bridge=vmbrPxe";
      extraNetworks = [
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrTestWan"
      ];
      pxe = true;
    };
  };
}
