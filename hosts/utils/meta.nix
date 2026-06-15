{
  class = "nixos";
  system = "x86_64-linux";
  username = "deploy";
  server = true;
  hasDisko = true;

  role = "server";
  osFeatures = [
    ../../modules/os/feat/linux/services/openssh.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/services/nginx.nix
    ../../modules/os/feat/linux/services/acme.nix
    {
      module = ../../modules/os/feat/linux/services/nix-cache.nix;
      args = {
        domain = "cache.lamhub.com";
        nginxProxy = true;
        signKeySecretName = "nix_cache_signing_key";
        acmeDomain = "lamhub.com";
      };
    }
  ];

  hmFeatures = [
    ../../profiles/lamt/dev.nix
  ];

  deployment = {
    targetIp = "192.168.1.19";
    vmid = "115";
    proxmox = {
      host = "192.168.1.15";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
