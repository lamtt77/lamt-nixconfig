{
  class = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  wsl = true;
  hasDisko = false;

  # Remote lifecycle commands fail closed until the real Windows endpoint is configured.
  deployment.wsl = {
    enable = true;
    windowsHost = "192.168.1.171";
    windowsUser = "lamt";
    distribution = "NixOS";
    installRoot = ''C:\WSL\NixOS'';
    transport = "auto";
  };

  role = "wsl";
  osFeatures = [
    ../../modules/os/feat/wsl/wsl-alived.nix
    ../../modules/os/feat/linux/services/openssh.nix
    {
      module = ../../modules/os/feat/services/tailscale.nix;
      args = {
        authKey = "tailscale_preauth_key";
      };
    }
    ../../modules/os/feat/linux/desktop/sway.nix
    ../../modules/os/feat/linux/desktop/bspwm-minimal.nix
  ];

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };
}
