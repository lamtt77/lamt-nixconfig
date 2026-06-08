{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  deployment = {
    vmid = "203";
    targetIp = "";
    lowMem = "yes";
    substituteOnDestination = true;
    diskSize = "20";
    proxmox = {
      host = "192.168.1.15";
      bios = "seabios";
      diskBus = "virtio";
      cores = "1";
      memory = "1024";
    };
  };
}
