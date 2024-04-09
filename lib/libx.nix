{ inputs, pkgsall, lib, ... }:

with lib.my;
{
  home-modules = { username, darwin, wsl, ... }: {
    imports = [
      # not needed anymore after the introduction of pkgsall!
      # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }

      ../modules/hm/base
      ../home/users/${username}
    ] ++ (mapModulesRec' ../modules/hm/base import)
    ++ lib.optionals (darwin) (mapModulesRec' ../modules/hm/darwin import)
    ++ lib.optionals (!darwin) (mapModulesRec' ../modules/hm/linux import);
  };

  nixos-modules = { system, host, darwin, wsl }: [
    # not needed anymore after the introduction of pkgsall, will be duplicated if added!
    # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }
    { nixpkgs.pkgs = pkgsall.${system}; }

    # Bring in WSL if this is a WSL build
    (if wsl then inputs.nixos-wsl.nixosModules.wsl else {})
    (if darwin then inputs.agenix.darwinModules.default else inputs.agenix.nixosModules.default)

    ../modules/os/base
    ../hosts/${host}.nix
  ] ++ (mapModulesRec' ../modules/os/base import)
  ++ lib.optionals (darwin) (mapModulesRec' ../modules/os/darwin import)
  ++ lib.optionals (!darwin) (mapModulesRec' ../modules/os/linux import)
  ++ lib.optionals (wsl) (mapModulesRec' ../modules/os/wsl import);

  mkPkgs = system: pkgs: extraOverlays: import pkgs {
    inherit system;
    config.allowUnfree = true;
    # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
    config.allowUnsupportedSystem = true;
    overlays = extraOverlays;
  };

  # standalone home-manager
  mkHome = { system, host, username, darwin ? false, wsl ? false }: let
    hmModules = home-modules { inherit username darwin wsl; };
  in inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = pkgsall.${system};

    extraSpecialArgs = {
      inherit inputs username;
      currentSystem = system;
      hostname = host;
      isWSL = wsl;
    };

    modules = hmModules.imports;
  };

  # host without home-manager module inside
  mkHost = { system, host, username, darwin ? false, wsl ? false }: let
    # NixOS vs nix-darwin functions
    systemFunc = if darwin then inputs.darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
    nixosModules = nixos-modules { inherit system host darwin wsl; };
  in systemFunc {
    inherit system;

    specialArgs = {
      inherit inputs username;
      currentSystem = system;
      hostname = host;
      isWSL = wsl;
    };

    modules = nixosModules;
  };

  # host in combination with home-manager as a module inside
  mkSystem = {system, host, username, darwin ? false, wsl ? false }: let
    # NixOS vs nix-darwin functions
    systemFunc = if darwin then inputs.darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
    homeFunc = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;
    nixosModules = nixos-modules { inherit system host darwin wsl; };
    hmModules = home-modules { inherit username darwin wsl; };
  in systemFunc rec {
    inherit system;

    specialArgs = {
      inherit inputs username;
      currentSystem = system;
      hostname = host;
      isWSL = wsl;
    };

    modules = nixosModules ++ [ homeFunc.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = specialArgs;
      home-manager.users.${username} = hmModules;
    }];
  };
}
