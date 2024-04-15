{ config, pkgs, lib, inputs, ... }:

with lib;
{
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

    shells = with pkgs; [ bashInteractive zsh ];
  };

  nix = let
    filteredInputs = filterAttrs (n: _: n != "self") inputs;
    registryInputs = mapAttrs (_: v: { flake = v; }) filteredInputs;
    filteredNixPathInputs = filterAttrs (n: _: n != "nixpkgs"
                                               && n != "darwin"
                                               && n != "home-manager") filteredInputs;
    nixPathInputs  = mapAttrsToList (n: v: "${n}=${v}") filteredNixPathInputs;
  in {
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
  };
}
