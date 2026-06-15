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
    lowMem = "yes";
    enableLocalCache = false;
    tailscaleNamespace = "cloud";
    digitalocean = {
      region = "sgp1";
      size = "s-1vcpu-1gb";
      image = "ubuntu-24-04-x64";
    };
  };
}
