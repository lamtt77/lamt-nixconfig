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
        router = "medo";
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/services/openssh.nix
    ../../modules/os/feat/linux/services/fail2ban.nix
  ];

  nxd.binaryCache = null;

  deployment = {
    lowMem = "yes";
    tailscaleNamespace = "cloud";
    digitalocean = {
      region = "sgp1";
      size = "s-1vcpu-1gb";
      image = "ubuntu-24-04-x64";
    };
  };
}
