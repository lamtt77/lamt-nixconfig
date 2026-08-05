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

  security.pki.certificates = lib.optional (
    config.nxd.binaryCache != null && config.nxd.binaryCache.caCertificate != ""
  ) config.nxd.binaryCache.caCertificate;

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

      # Disable synchronous disk writes for the Nix store database.
      # This significantly speeds up `nix copy` (e.g. for installer-secrets)
      # over SSH by removing fsync overhead on the builder/target.
      fsync-metadata = false;
      use-xdg-base-directories = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # When set, the daemon always trusts this cache. That lets untrusted
      # multi-user clients substitute without restricted --option overrides, and
      # lets trusted clients pass the same URL via extra-substituters.
      substituters = [
        "https://cache.nixos.org"
      ]
      ++ lib.optional (config.nxd.binaryCache != null) config.nxd.binaryCache.url;
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ]
      ++ lib.optional (config.nxd.binaryCache != null) config.nxd.binaryCache.publicKey;
      trusted-substituters = [
        "https://cache.nixos.org"
      ]
      ++ lib.optional (config.nxd.binaryCache != null) config.nxd.binaryCache.url;
      connect-timeout = 3;
      stalled-download-timeout = 10;
    };
  };
}
