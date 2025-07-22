{ inputs, lib, pkgs, username, ... }:

with lib;
let users = [ "root" "@wheel" ];
in
  inputs.self.libx.mkUser { inherit username pkgs; darwin = pkgs.stdenv.isDarwin; } // {

  time.timeZone = inputs.self.mydefs.timeZone;

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

      trusted-users = users;

      use-xdg-base-directories = true;

      substituters = ["https://nix-community.cachix.org"];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  system = {
    # Let 'nixos-version --json' know about the Git revision of this flake.
    configurationRevision = with inputs; mkIf (self ? rev) self.rev;
  };
}
