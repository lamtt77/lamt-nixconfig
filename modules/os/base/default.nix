{ config, pkgs, lib, inputs, username, ... }:

with lib;
let users = [ "root" username ];
in {
  # nix-darwin only has 'variables' attribute!
  environment.variables.DOTFILES = config.dotfiles.dir;
  environment.variables.DOTFILES_BIN = config.dotfiles.binDir;

  environment = {
    etc = {
      nixpkgs.source = inputs.nixpkgs;
      darwin.source = inputs.darwin;
      home-manager.source = inputs.home-manager;
      # self.source = inputs.self;
    };

    shells = with pkgs; [ bashInteractive zsh fish ];
  };

  nix =
    let filteredInputs = filterAttrs (n: _: n != "self") inputs;
        registryInputs = mapAttrs (_: v: { flake = v; }) filteredInputs;
        filteredNixPathInputs = filterAttrs (n: _: n != "nixpkgs"
                                            && n != "darwin"
                                            && n != "home-manager") filteredInputs;
        nixPathInputs  = mapAttrsToList (n: v: "${n}=${v}") filteredNixPathInputs;
    in {
      package = pkgs.unstable.nixUnstable;
      nixPath = nixPathInputs ++ [
        "nixpkgs-overlays=${config.dotfiles.dir}/overlays"
        "dotfiles=${config.dotfiles.dir}"
        "nixpkgs=/etc/${config.environment.etc.nixpkgs.target}"
        "darwin=/etc/${config.environment.etc.darwin.target}"
        "home-manager=/etc/${config.environment.etc.home-manager.target}"
      ];

      # make `nix run nixpkgs#nixpkgs` use the same nixpkgs as the one used by this flake.
      # nix.registry.nixpkgs.flake = inputs.nixpkgs;
      registry = registryInputs // { dotfiles.flake = inputs.self; };

      # Allows Nix to execute builds inside cgroups
      extraOptions = ''
        builders-use-substitutes = true
        experimental-features = nix-command flakes cgroups
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

        auto-optimise-store = true;

        substituters = [
          "https://nix-community.cachix.org"
          "https://hyprland.cachix.org"
        ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
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
    home-manager
    niv
    cachix
    git
    vim
    wget
    gnumake
    unzip
  ];
}
