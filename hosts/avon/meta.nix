{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  deployment = {
    targetIp = "192.168.1.18";
    vmid = "103";
    proxmox = {
      host = "192.168.1.15";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
