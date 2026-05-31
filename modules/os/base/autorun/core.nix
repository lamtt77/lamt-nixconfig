{
  inputs,
  lib,
  pkgs,
  mydefs,
  myargs,
  ...
}: let
  users = ["@wheel" myargs.username];
in {
  time.timeZone = mydefs.timeZone;

  # uncomment this to enable nixpath and flake registry for all servers
  # modules.os.base.nixpath-registry.nixpkgs.enable = true;

  nix = {
    package = lib.mkIf (!pkgs.stdenv.isDarwin) pkgs.unstable.nixVersions.latest;

    extraOptions = ''
      builders-use-substitutes = true
      experimental-features = nix-command flakes ${lib.optionalString pkgs.stdenv.isDarwin "lazy-trees"}
      # Prevent Nix from fetching the registry every time
      flake-registry = ${inputs.flake-registry}/flake-registry.json
    '';

    settings = {
      max-jobs = "auto";
      cores = 0;

      trusted-users = users;

      use-xdg-base-directories = true;

      substituters = [
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
    };
  };
}
