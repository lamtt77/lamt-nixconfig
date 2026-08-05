{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  role = "server";
  osFeatures = [
    ../../modules/os/feat/services/builders.nix
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/services/fail2ban.nix
    ../../modules/os/feat/linux/services/nginx.nix
    ../../modules/os/feat/linux/services/postfix.nix
    ../../modules/os/feat/linux/services/gitea/default.nix
    ../../modules/os/feat/linux/services/gitea-runner.nix
    ../../modules/os/feat/linux/services/headscale.nix
    ../../modules/os/feat/linux/services/acme.nix
    ../../modules/os/feat/services/tailscale.nix
    ../../modules/os/feat/linux/services/backup.nix
  ];

  deployment = {
    vmid = "103";
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
