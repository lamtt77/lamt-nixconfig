{
  inputs,
  lib,
  pkgs,
  mydefs,
  myargs,
  config,
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

  # Disable HTML/JSON options search documentation to optimize evaluation times
  documentation.enable = false;
  documentation.info.enable = false;

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

      substituters = lib.mkIf config.deployment.enableLocalCache [
        "https://cache.lamhub.com?priority=10"
      ];
      trusted-public-keys = lib.mkIf config.deployment.enableLocalCache [
        "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw="
      ];
      connect-timeout = 3;
      stalled-download-timeout = 10;
    };
  };
}
