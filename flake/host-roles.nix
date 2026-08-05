{
  laptop = {
    tags = [ "client" ];
    osFeatures = [
      ../modules/os/feat/workstation.nix
    ];
  };
  workstation = {
    tags = [ "client" ];
    osFeatures = [
      ../modules/os/feat/workstation.nix
    ];
  };
  server = {
    server = true;
    tags = [ "server" ];
    osFeatures = [
      ../modules/os/feat/server.nix
    ];
  };
  # A build machine realizes its own system: infra/default.nix points its
  # builder at itself, which keeps NXD's builder-side evaluation so the flake
  # source is copied and evaluated there instead of pushing a whole derivation
  # closure.
  builder = {
    server = true;
    tags = [ "server" ];
    osFeatures = [
      ../modules/os/feat/server.nix
    ];
  };
  router = {
    server = true;
    hasDisko = true;
    tags = [ "infra" ];
    osFeatures = [
      ../modules/os/feat/server.nix
    ];
  };
  bootstrap = {
    tags = [ "bootstrap" ];
    buildSystem = false;
  };
  wsl = {
    wsl = true;
    tags = [ "wsl" ];
    osFeatures = [
      ../modules/os/feat/workstation.nix
    ];
  };
}
