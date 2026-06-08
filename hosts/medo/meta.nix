{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  server = true;
  hasDisko = true;

  deployment = {
    lowMem = "yes";
    substituteOnDestination = true;
    tailscaleNamespace = "cloud";
    digitalocean = {
      region = "sgp1";
      size = "s-1vcpu-1gb";
      image = "ubuntu-24-04-x64";
    };
  };
}
