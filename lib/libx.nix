{ inputs, pkgsall, lib, ... }:

with lib.my;
{
  home-modules = { username, darwin, wsl, ... }: {
    imports = [
      # not needed anymore after the introduction of pkgsall!
      # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }

      ../profiles/${username}
    ] ++ (mapModulesRec' ../modules/hm/base import)
    ++ lib.optionals (darwin) (mapModulesRec' ../modules/hm/darwin import)
    ++ lib.optionals (!darwin) (mapModulesRec' ../modules/hm/linux import)
    ++ lib.optionals (wsl) (mapModulesRec' ../modules/hm/wsl import);
  };

  nixos-modules = { system, host, darwin, wsl, server }: [
    # not needed anymore after the introduction of pkgsall, will be duplicated if added!
    # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }
    { nixpkgs.pkgs = pkgsall.${system}; }

    # Bring in WSL if this is a WSL build
    (if wsl then inputs.nixos-wsl.nixosModules.wsl else {})

    (if server then ../modules/os/base/_server.nix else ../modules/os/base/_workstation.nix)
    (if darwin then inputs.agenix.darwinModules.default else inputs.agenix.nixosModules.default)

    ../hosts/${host}
  ] ++ (mapModulesRec' ../modules/os/base import)
  ++ lib.optionals (darwin) (mapModulesRec' ../modules/os/darwin import)
  # this will also load regardless of wsl status
  ++ lib.optionals (!darwin) (mapModulesRec' ../modules/os/linux import)
  # this will load additional wsl stuffs
  ++ lib.optionals (wsl) (mapModulesRec' ../modules/os/wsl import);

  mkPkgs = system: pkgs: overlays: import pkgs {
    inherit system overlays;

    config.allowUnfree = true;
    # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
    config.allowUnsupportedSystem = true;
  };

  # mkUser should run at nixos module level
  mkUser = { username, pkgs, darwin ? false }: with lib; let
    inherit (inputs.self) mydefs;
    isDefaultUser = (username == mydefs.defaultUsername);
  in {
    programs.zsh.enable = isDefaultUser;

    users = mkMerge [
      (mkIf darwin {
        # The user should already exist, but we need to set this up so Nix knows
        # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
        users.${username}.home = "/Users/${username}";
      })

      (mkIf (!darwin) {
        # NOTE this will have no password (locked-in, only accept ssh key authorization)
        # uncomment if you want to declaritively set password, follow these steps:
        #   1. mkpasswd -m sha-512 --salt "Anything"
        #   2. hashedPassword = the newly created password
        # users.mutableUsers = false;

        users.${username} = {
          isNormalUser = true;
          home = "/home/${username}";
          # TODO move "docker" setting to its module
          extraGroups = [ "docker" "wheel" ]; # Enable ‘sudo’ for the user.
          openssh.authorizedKeys.keys = mydefs.ssh-authorizedKeys;
        } // lib.optionalAttrs (isDefaultUser) {
          shell = pkgs.zsh;
        };
      })
    ];
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
  mkHost = { system, host, username, darwin ? false, wsl ? false, server ? false }: let
    # NixOS vs nix-darwin functions
    systemFunc = if darwin then inputs.darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
    nixosModules = nixos-modules { inherit system host darwin wsl server; };
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
  mkSystem = {system, host, username, darwin ? false, wsl ? false, server ? false }: let
    # NixOS vs nix-darwin functions
    systemFunc = if darwin then inputs.darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
    homeFunc = if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;
    nixosModules = nixos-modules { inherit system host darwin wsl server; };
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
