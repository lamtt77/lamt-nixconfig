{ inputs, lib, pkgs, username, ... }:

with lib;
let users = [ "root" username ];
in
  inputs.self.libx.mkUser { inherit username pkgs; darwin = pkgs.stdenv.isDarwin; } // {

  time.timeZone = inputs.self.mydefs.timeZone;
  # systemd.services.systemd-timesyncd.wantedBy = [ "multi-user.target" ];
  # systemd.timers.systemd-timesyncd = { timerConfig.OnCalendar = "hourly"; };

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

    # Store management
    gc.automatic = true;
    gc.options = "--delete-older-than 15d";
    optimise.automatic = true;

    settings = {
      max-jobs = "auto";
      # cores = 8;

      trusted-users = users;
      allowed-users = users;

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

    activationScripts.diff = {
      supportsDryActivation = true;
      text = ''
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${pkgs.nix}/bin diff /run/current-system "$systemConfig"
      '';
    };
  };
}
