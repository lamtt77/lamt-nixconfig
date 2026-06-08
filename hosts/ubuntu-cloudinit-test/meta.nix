{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = false;
  buildSystem = false;

  deployment = {
    vmid = "201";
    proxmox = {
      host = "192.168.1.15";
      bios = "seabios";
      diskBus = "virtio";
      cores = "1";
      memory = "1024";
      cloudInit = {
        image = "/mnt/pve/arthurz2-dir/images/ubuntu-22.04-server-cloudimg-amd64.img";
        user = "ubuntu";
        ipconfig0 = "ip=dhcp";
      };
    };
  };
}
