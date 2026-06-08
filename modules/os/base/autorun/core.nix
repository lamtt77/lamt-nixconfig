{
  inputs,
  lib,
  pkgs,
  mydefs,
  myargs,
  ...
}:
let
  users = [
    "@wheel"
    myargs.username
  ];
in
{
  time.timeZone = mydefs.timeZone;

  # enable nixpath and flake registry for all hosts
  modules.os.base.nixpath-registry.enable = true;

  nix = {
    package = lib.mkIf (!pkgs.stdenv.isDarwin) pkgs.unstable-nix;

    extraOptions = ''
      # Prevent Nix from fetching the registry every time
      flake-registry = ${inputs.flake-registry}/flake-registry.json
    '';

    settings = {
      max-jobs = "auto";
      cores = 0;

      trusted-users = users;

      use-xdg-base-directories = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # substituters = [
      #   "https://nix-community.cachix.org"
      #   "https://devenv.cachix.org"
      # ];
      # trusted-public-keys = [
      #   "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      #   "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      # ];
    };
  };
}
