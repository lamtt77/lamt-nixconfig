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
