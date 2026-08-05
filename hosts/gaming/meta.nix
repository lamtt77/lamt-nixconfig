{
  class = "nixos";
  system = "x86_64-linux";
  username = "vivi";
  server = true;
  hasDisko = true;
  role = "server";

  osFeatures = [
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/gaming/minecraft-server.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        authKey = "tailscale_preauth_key";
      };
    }
  ];

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };

  deployment = {
    vmid = "110";
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
