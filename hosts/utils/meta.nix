{
  class = "nixos";
  system = "x86_64-linux";
  username = "deploy";
  server = true;
  hasDisko = true;

  role = "builder";
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
      module = ../../modules/os/feat/linux/services/nix-cache-server.nix;
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
    vmid = "115";
    proxmox = {
      provider = "pve1";
      bios = "ovmf";
      diskBus = "scsi";
    };
  };
}
