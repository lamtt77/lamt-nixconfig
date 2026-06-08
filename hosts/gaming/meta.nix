{
  class = "nixos";
  system = "x86_64-linux";
  username = "vivi";
  server = true;
  hasDisko = true;

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };

  deployment = {
    targetIp = "";
    vmid = "110";
    proxmox = {
      host = "192.168.1.15";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
