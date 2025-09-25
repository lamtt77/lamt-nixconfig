{
  inputs,
  lib,
  ...
}:
with lib.my; {
  home-modules = {
    username,
    darwin,
    wsl,
    ...
  }: {
    imports =
      [
        ../modules/shared/options.nix
        # not needed anymore after the introduction of pkgsall!
        # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }
        ../profiles/${username}
      ]
      ++ (mapModulesRec' ../modules/hm/base import)
      ++ lib.optionals darwin (mapModulesRec' ../modules/hm/darwin import)
      ++ lib.optionals (!darwin) (mapModulesRec' ../modules/hm/linux import)
      ++ lib.optionals wsl (mapModulesRec' ../modules/hm/wsl import);
  };

  nixos-modules = {
    system,
    host,
    username,
    darwin,
    wsl,
    server,
    pkgs,
  }: let
    # Proof of concept: my options accessible via config.user, etc
    myopts = {
      user = username;
    };
  in
    [
      ../modules/shared/options.nix
      # not needed anymore after the introduction of pkgsall, will be duplicated if added!
      # { nixpkgs.overlays = builtins.attrValues inputs.self.overlays; }
      {nixpkgs.pkgs = pkgs;}
      ../hosts/${host}

      (
        if wsl
        then inputs.nixos-wsl.nixosModules.wsl
        else {}
      )
      (
        if server
        then ../modules/os/base/_server.nix
        else ../modules/os/base/_workstation.nix
      )

      (
        if darwin
        then inputs.sops-nix.darwinModules.sops
        else inputs.sops-nix.nixosModules.sops
      )
    ]
    ++ [myopts]
    ++ (mapModulesRec' ../modules/os/base import)
    ++ lib.optionals darwin (mapModulesRec' ../modules/os/darwin import)
    # this will also load regardless of wsl status
    ++ lib.optionals (!darwin) (mapModulesRec' ../modules/os/linux import)
    # this will load additional wsl stuffs
    ++ lib.optionals wsl (mapModulesRec' ../modules/os/wsl import);

  mkPkgs = system: pkgs: overlays:
    import pkgs {
      inherit system overlays;

      config.allowUnfree = true;
      # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
      config.allowUnsupportedSystem = true;
    };

  # mkUser should run at nixos module level
  mkUser = {
    username,
    pkgs,
    darwin ? false,
    extraGroups ? [],
    mydefs,
  }:
    with lib; let
      isDefaultUser = username == mydefs.defaultUsername;
      defaultGroups = ["docker" "wheel"];
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

          users.${username} =
            {
              isNormalUser = true;
              home = "/home/${username}";
              extraGroups = defaultGroups ++ extraGroups;
              openssh.authorizedKeys.keys = ["${mydefs.mySshAuthKey}"];
            }
            // lib.optionalAttrs isDefaultUser {
              shell = pkgs.zsh;
            };
        })
      ];
    };

  # For additional users with embedded HM
  mkExtraUser = {
    username,
    pkgs,
    darwin ? false,
    extraGroups ? [],
    profile ? null,
    mydefs,
  }:
    lib.mkMerge [
      (mkUser {inherit username pkgs darwin extraGroups mydefs;})
      {
        home-manager.users.${username} = {
          imports = lib.optional (profile != null) ../profiles/${profile};
          home = {
            inherit username;
            homeDirectory =
              if darwin
              then "/Users/${username}"
              else "/home/${username}";
          };
        };
      }
    ];

  # host without home-manager module inside
  mkHost = {
    system,
    host,
    username,
    darwin ? false,
    wsl ? false,
    server ? false,
    pkgs ? null,
  }: let
    # NixOS vs nix-darwin functions
    systemFunc =
      if darwin
      then inputs.darwin.lib.darwinSystem
      else inputs.nixpkgs.lib.nixosSystem;
    nixosModules = nixos-modules {
      inherit
        system
        host
        username
        darwin
        wsl
        server
        ;
    };
  in
    systemFunc {
      inherit system;

      specialArgs = {
        inherit inputs lib;
        inherit (lib) my;
        currentSystem = system;
        hostname = host;
        isWSL = wsl;
        mydefs = import ../defines.nix;
      };

      modules = nixosModules;
    };

  # host in combination with home-manager as a module inside
  mkSystem = {
    system,
    host,
    username,
    nixpkgs,
    mydefs,
    darwin ? false,
    wsl ? false,
    server ? false,
    extraUsers ? [],
  }: let
    # NixOS vs nix-darwin functions
    systemFunc =
      if darwin
      then inputs.darwin.lib.darwinSystem
      else inputs.nixpkgs.lib.nixosSystem;
    homeFunc =
      if darwin
      then inputs.home-manager.darwinModules
      else inputs.home-manager.nixosModules;
    pkgs = mkPkgs system nixpkgs (lib.attrValues inputs.self.overlays);
    nixosModules = nixos-modules {
      inherit
        system
        host
        username
        darwin
        wsl
        server
        pkgs
        ;
    };
    hmModules = home-modules {inherit username darwin wsl;};
  in
    systemFunc rec {
      inherit system;

      specialArgs = {
        inherit inputs lib;
        inherit (lib) my;
        currentSystem = system;
        hostname = host;
        isWSL = wsl;
        mydefs = import ../defines.nix;
      };

      modules =
        nixosModules
        ++ [
          (mkUser {inherit username pkgs darwin mydefs;})
          homeFunc.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "home-manager.backup";
              extraSpecialArgs = {
                inherit inputs;
                inherit (lib) my;
                currentSystem = system;
                hostname = host;
                isWSL = wsl;
                mydefs = import ../defines.nix;
              };
              users.${username} = lib.mkMerge [hmModules {user = username;}];
            };
          }
         ]
        ++ extraUsers;
    };

  # Standalone home-manager configuration
  mkHome = {
    system,
    host,
    username,
    nixpkgs,
    mydefs,
    darwin ? false,
    wsl ? false,
  }: let
    overlays = lib.attrValues inputs.self.overlays;
    hmModules = home-modules {inherit username darwin wsl;};
  in inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = mkPkgs system nixpkgs overlays;

    extraSpecialArgs = {
      inherit inputs;
      inherit (lib) my;
      currentSystem = system;
      hostname = host;
      isWSL = wsl;
      mydefs = import ../defines.nix;
    };

    modules = hmModules.imports ++ [{user = username;}];
  };
}
