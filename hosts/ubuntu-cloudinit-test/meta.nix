{
  disposable = true;
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = false;
  buildSystem = false;

  deployment = {
    vmid = "201";
    diskSize = "20";
    proxmox = {
      provider = "pve1";
      bios = "seabios";
      diskBus = "virtio";
      cores = "1";
      memory = "1024";
      cloudInit = {
        image = "arthurz2-dir:import/ubuntu-22.04-server-cloudimg-amd64.qcow2";
        user = "ubuntu";
        ipconfig0 = "ip=dhcp";
      };
    };
  };
}
