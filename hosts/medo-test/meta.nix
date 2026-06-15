{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  role = "server";
  osFeatures = [
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        exitNode = true;
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/services/fail2ban.nix
  ];

  deployment = {
    vmid = "203";
    targetIp = "";
    lowMem = "yes";
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
