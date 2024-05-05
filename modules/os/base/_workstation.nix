{ inputs, config, pkgs, lib, ... }:
let
  inherit (inputs) self;
in
with lib;
{
  environment = {
    etc = {
      nixpkgs.source = inputs.nixpkgs;
      nixpkgs-unstable.source = inputs.nixpkgs-unstable;
      darwin.source = inputs.darwin;
      home-manager.source = inputs.home-manager;
    };

    shells = with pkgs; [ bashInteractive zsh ];
  };

  nix = let
    filteredNixPathInputs = filterAttrs (n: _: n != "nixpkgs"
                                               && n != "nixpkgs-unstable"
                                               && n != "darwin"
                                               && n != "home-manager") inputs;
    nixPathInputs  = mapAttrsToList (n: v: "${n}=${v}") filteredNixPathInputs;
  in {
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';

    nixPath = nixPathInputs ++ [
      "nixpkgs-overlays=${self}/overlays"
      "nixpkgs=/etc/${config.environment.etc.nixpkgs.target}"
      "nixpkgs-unstable=/etc/${config.environment.etc.nixpkgs-unstable.target}"
      "darwin=/etc/${config.environment.etc.darwin.target}"
      "home-manager=/etc/${config.environment.etc.home-manager.target}"
    ];

    # take all inputs to registry for development workstation
    registry = mapAttrs (_: v: { flake = v; }) inputs;
  };
}
