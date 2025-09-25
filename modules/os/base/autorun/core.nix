{
  inputs,
  config,
  lib,
  pkgs,
  mydefs,
  ...
}: let
  users = ["root" "@wheel"];
in {
  time.timeZone = mydefs.timeZone;

  # uncomment this to enable nixpath and flake registry for all servers
  # modules.os.base.nixpath-registry.nixpkgs.enable = true;

  nix = {
    package = pkgs.unstable.nixVersions.latest;

    extraOptions = ''
      builders-use-substitutes = true
      experimental-features = nix-command flakes
      # Prevent Nix from fetching the registry every time
      flake-registry = ${inputs.flake-registry}/flake-registry.json
    '';

    # optimise.automatic = true;

    settings = {
      max-jobs = "auto";
      # cores = 8;
      cores = 0;

      trusted-users = users;

      use-xdg-base-directories = true;

      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://cache.determinate.systems/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.determinate.systems-1:7IkJb2AM6tEZgYd2vYPF8yQ3okA6lDuEo8MgF3F4K4="
      ];
    };
  };

  system.activationScripts.buildManDb = {
    text = ''
      if [ ! -d /var/cache/man ] || [ -z "$(find /var/cache/man -name '*.gz' -mtime -7 2>/dev/null)" ]; then
        mkdir -p /var/cache/man
        mandb
      fi
    '';
    deps = [];
  };
}
