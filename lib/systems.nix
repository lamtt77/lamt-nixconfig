{
  inputs,
  lib,
  ...
}:
with lib.my; let
  mydefs = import ../defines.nix;
in {
  # OS modules get full lib (for nixpkgs utils), HM modules only get lib.my to avoid conflicts
  mkSpecialArgs = {
    system,
    hostname,
    username,
    wsl ? false,
    libArg ? null,
  }:
    {
      inherit (lib) my;
      myargs = {inherit system hostname username wsl;};
      inherit inputs mydefs;
    }
    // (
      if libArg != null
      then {lib = libArg;}
      else {}
    );

  getPlatformModules = {
    darwin,
    wsl,
  }:
    if darwin
    then (mapModulesRec' ../modules/os/darwin import)
    else (mapModulesRec' ../modules/os/linux import) ++ lib.optionals wsl (mapModulesRec' ../modules/os/wsl import);

  getSystemFunc = darwin:
    if darwin
    then inputs.darwin.lib.darwinSystem
    else inputs.nixpkgs.lib.nixosSystem;
  getHomeFunc = darwin:
    if darwin
    then inputs.home-manager.darwinModules
    else inputs.home-manager.nixosModules;

  mkHomeManagerConfig = {
    username,
    system,
    hostname,
    wsl,
    hmModules,
  }: {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "home-manager.backup";
    extraSpecialArgs = mkSpecialArgs {inherit system hostname username wsl;};
    users.${username} = {
      inherit (hmModules) imports;
    };
  };

  baseModules = [../modules/shared/options.nix];
  home-modules = {
    username,
    darwin,
    wsl,
    ...
  }: {
    imports =
      baseModules
      ++ [
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
    hostname,
    username,
    darwin,
    wsl,
    server,
    pkgs,
  }: let
    conditionalModules = lib.flatten [
      (lib.optional wsl inputs.nixos-wsl.nixosModules.wsl)
      (
        if server
        then [../modules/os/base/_server.nix]
        else [../modules/os/base/_workstation.nix]
      )
      (
        if darwin
        then [inputs.sops-nix.darwinModules.sops]
        else [inputs.sops-nix.nixosModules.sops]
      )
    ];
  in
    baseModules
    ++ [
      {nixpkgs.pkgs = pkgs;}
      ../hosts/${hostname}
    ]
    ++ conditionalModules ++ (mapModulesRec' ../modules/os/base import) ++ getPlatformModules {inherit darwin wsl;};

  mkPkgs = {
    system,
    localSystem ? system,
    crossSystem ? null,
  }: nixpkgs: overlays:
    import nixpkgs {
      inherit localSystem crossSystem overlays;
      config.allowUnfree = true;
      config.allowUnsupportedSystem = true;
      config.allowBroken = true;
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
    hostname,
    username,
    darwin ? false,
    wsl ? false,
    server ? false,
    nixpkgs,
    mydefs,
    localSystem ? system,
    crossSystem ? null,
  }: let
    systemFunc = getSystemFunc darwin;
    homeFunc = getHomeFunc darwin;
    pkgs = mkPkgs {inherit system localSystem crossSystem;} nixpkgs (lib.attrValues inputs.self.overlays);
    nixosModules = nixos-modules {
      inherit system hostname username darwin wsl server pkgs;
    };
  in
    systemFunc {
      inherit system;

      specialArgs = mkSpecialArgs {
        inherit system hostname username wsl;
        libArg = lib;
      };

      modules =
        nixosModules
        ++ [
          homeFunc.home-manager
          {
            home-manager.users.${username} = {
              home.stateVersion = mydefs.stateVersion;
            };
          }
        ];
    };

  # host in combination with home-manager as a module inside
  mkSystem = {
    system,
    hostname,
    username,
    nixpkgs,
    mydefs,
    darwin ? false,
    wsl ? false,
    server ? false,
    extraUsers ? [],
    localSystem ? system,
    crossSystem ? null,
  }: let
    systemFunc = getSystemFunc darwin;
    homeFunc = getHomeFunc darwin;
    pkgs = mkPkgs {inherit system localSystem crossSystem;} nixpkgs (lib.attrValues inputs.self.overlays);
    nixosModules = nixos-modules {inherit system hostname username darwin wsl server pkgs;};
    hmModules = home-modules {inherit username darwin wsl;};
  in
    systemFunc rec {
      inherit system;

      specialArgs = mkSpecialArgs {
        inherit system hostname username wsl;
        libArg = lib;
      };

      modules =
        nixosModules
        ++ [
          (mkUser {inherit username pkgs darwin mydefs;})
          homeFunc.home-manager
          {
            home-manager = mkHomeManagerConfig {inherit username system hostname wsl hmModules;};
          }
        ]
        ++ extraUsers;
    };

  # Standalone home-manager configuration
  mkHome = {
    system,
    hostname,
    username,
    nixpkgs,
    mydefs,
    darwin ? false,
    wsl ? false,
  }: let
    overlays = lib.attrValues inputs.self.overlays;
    hmModules = home-modules {inherit username darwin wsl;};
  in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs {inherit system;} nixpkgs overlays;
      extraSpecialArgs = mkSpecialArgs {inherit system hostname username wsl;};
      modules = hmModules.imports;
    };
}
