{ inputs, lib, pkgs, username, ... }:

with lib;
let users = [ "root" username ];
in
  inputs.self.libx.mkUser { inherit username pkgs; darwin = pkgs.stdenv.isDarwin; } // {

  time.timeZone = inputs.self.mydefs.timeZone;

  nix = {
    package = pkgs.unstable.nixUnstable;

    # Allows Nix to execute builds inside cgroups
    extraOptions = ''
      builders-use-substitutes = true
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true

      # Prevent Nix from fetching the registry every time
      flake-registry = ${inputs.flake-registry}/flake-registry.json
    '';

    gc = {
      automatic = true;
      options = "--delete-older-than 15d";
    };

    settings = {
      max-jobs = 8;
      cores = 8;

      trusted-users = users;
      allowed-users = users;

      use-xdg-base-directories = true;
      auto-optimise-store = true;

      substituters = ["https://nix-community.cachix.org"];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  system = {
    configurationRevision = with inputs; mkIf (self ? rev) self.rev;
    activationScripts.diff = {
      supportsDryActivation = true;
      text = ''
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${pkgs.nix}/bin diff /run/current-system "$systemConfig"
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    gnumake
    unzip
  ];
}
