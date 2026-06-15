{
  inputs,
  lib,
  ...
}:
with lib.my;
let
  mydefs = import ../defines.nix;

  resolveFeatures =
    features:
    map (
      feature:
      if builtins.typeOf feature == "path" then
        let
          f = import feature;
        in
        if builtins.isFunction f then
          let
            stdArgs = [
              "config"
              "lib"
              "pkgs"
              "my"
              "myargs"
              "inputs"
              "mydefs"
              "options"
              "modulesPath"
            ];
            fArgs = builtins.attrNames (builtins.functionArgs f);
          in
          if lib.intersectLists stdArgs fArgs == [ ] then f { } else feature
        else
          feature
      else if builtins.isAttrs feature && feature ? module then
        import feature.module (feature.args or { })
      else
        throw "Invalid feature entry: expected a path or { module, args ? {} }"
    ) features;

  coreOSModules =
    darwin: wsl:
    [
      ../modules/os/base
    ]
    ++ lib.optionals darwin [
      ../modules/os/base/darwin
    ]
    ++ lib.optionals (!darwin) (
      [
        ../modules/os/base/linux
      ]
      ++ lib.optionals wsl [
        ../modules/os/base/wsl
      ]
    );

  coreHMModules =
    darwin: wsl:
    [
      ../modules/hm/base
    ]
    ++ lib.optionals darwin [
      ../modules/hm/base/darwin
    ];
in
rec {
  inherit resolveFeatures;

  # OS modules get full lib (for nixpkgs utils), HM modules only get lib.my to avoid conflicts
  mkSpecialArgs =
    {
      system,
      hostname,
      username,
      wsl ? false,
      darwin ? false,
      role ? null,
      libArg ? null,
    }:
    {
      inherit (lib) my;
      myargs = {
        inherit
          system
          hostname
          username
          wsl
          darwin
          role
          ;
      };
      inherit inputs mydefs;
    }
    // (if libArg != null then { lib = libArg; } else { });

  getSystemFunc =
    darwin: if darwin then inputs.darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
  getHomeFunc =
    darwin: if darwin then inputs.home-manager.darwinModules else inputs.home-manager.nixosModules;

  mkHomeManagerConfig =
    {
      username,
      system,
      hostname,
      wsl,
      darwin,
      role ? null,
      hmModules,
    }:
    {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "home-manager.backup";
      extraSpecialArgs = mkSpecialArgs {
        inherit
          system
          hostname
          username
          wsl
          darwin
          role
          ;
      };
      users.${username} = {
        inherit (hmModules) imports;
      };
    };

  baseModules = [ ../modules/shared/options.nix ];
  home-modules =
    {
      username,
      darwin,
      wsl,
      hmFeatures ? [ ],
      ...
    }:
    {
      imports =
        baseModules
        ++ [
          ../profiles/${username}
        ]
        ++ coreHMModules darwin wsl
        ++ resolveFeatures hmFeatures;
    };

  nixos-modules =
    {
      system,
      hostname,
      username,
      darwin,
      wsl,
      pkgs,
      osFeatures ? [ ],
    }:
    let
      conditionalModules = lib.flatten [
        (lib.optional wsl inputs.nixos-wsl.nixosModules.wsl)
        (if darwin then [ inputs.sops-nix.darwinModules.sops ] else [ inputs.sops-nix.nixosModules.sops ])
        (lib.optional (!darwin) inputs.impermanence.nixosModules.impermanence)
      ];
    in
    baseModules
    ++ [
      {
        nixpkgs.pkgs = pkgs;
        nixpkgs.hostPlatform = lib.mkDefault system;
      }
      ../hosts/${hostname}
    ]
    ++ conditionalModules
    ++ coreOSModules darwin wsl
    ++ resolveFeatures osFeatures;

  mkPkgs =
    {
      system,
      localSystem ? system,
      crossSystem ? null,
    }:
    nixpkgs: overlays:
    import nixpkgs {
      inherit localSystem crossSystem overlays;
      config.allowUnfree = true;
      config.allowUnsupportedSystem = true;
      config.allowBroken = true;
    };

  # mkUser should run at nixos module level
  mkUser =
    {
      username,
      pkgs,
      darwin ? false,
      extraGroups ? [ ],
      mydefs,
    }:
    with lib;
    let
      isDefaultUser = username == mydefs.defaultUsername;
      defaultGroups = [
        "docker"
        "wheel"
      ];
    in
    {
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

          users.${username} = {
            isNormalUser = true;
            home = "/home/${username}";
            extraGroups = defaultGroups ++ extraGroups;
            openssh.authorizedKeys.keys = [ "${mydefs.mySshAuthKey}" ];
          }
          // lib.optionalAttrs isDefaultUser {
            shell = pkgs.zsh;
          };
        })
      ];
    };

  # For additional users with embedded HM
  mkExtraUser =
    {
      username,
      pkgs,
      darwin ? false,
      extraGroups ? [ ],
      profile ? null,
      mydefs,
    }:
    lib.mkMerge [
      (mkUser {
        inherit
          username
          pkgs
          darwin
          extraGroups
          mydefs
          ;
      })
      {
        home-manager.users.${username} = {
          imports = lib.optional (profile != null) ../profiles/${profile};
          home = {
            inherit username;
            homeDirectory = if darwin then "/Users/${username}" else "/home/${username}";
          };
        };
      }
    ];

  # host without home-manager module inside
  mkHost =
    {
      system,
      hostname,
      username,
      darwin ? false,
      wsl ? false,
      role ? null,
      nixpkgs,
      mydefs,
      localSystem ? system,
      crossSystem ? null,
      osFeatures ? [ ],
    }:
    let
      systemFunc = getSystemFunc darwin;
      homeFunc = getHomeFunc darwin;
      pkgs = mkPkgs { inherit system localSystem crossSystem; } nixpkgs (
        lib.attrValues inputs.self.overlays
      );
      nixosModules = nixos-modules {
        inherit
          system
          hostname
          username
          darwin
          wsl
          pkgs
          osFeatures
          ;
      };
    in
    systemFunc {
      inherit system;

      specialArgs = mkSpecialArgs {
        inherit
          system
          hostname
          username
          wsl
          darwin
          role
          ;
        libArg = lib;
      };

      modules = nixosModules ++ [
        homeFunc.home-manager
        {
          home-manager.users.${username} = {
            home.stateVersion = mydefs.stateVersion;
          };
          user = username;
        }
      ];
    };

  # host in combination with home-manager as a module inside
  mkSystem =
    {
      system,
      hostname,
      username,
      nixpkgs,
      mydefs,
      darwin ? false,
      wsl ? false,
      role ? null,
      extraUsers ? [ ],
      localSystem ? system,
      crossSystem ? null,
      osFeatures ? [ ],
      hmFeatures ? [ ],
    }:
    let
      systemFunc = getSystemFunc darwin;
      homeFunc = getHomeFunc darwin;
      pkgs = mkPkgs { inherit system localSystem crossSystem; } nixpkgs (
        lib.attrValues inputs.self.overlays
      );
      nixosModules = nixos-modules {
        inherit
          system
          hostname
          username
          darwin
          wsl
          pkgs
          osFeatures
          ;
      };
      hmModules = home-modules {
        inherit
          username
          darwin
          wsl
          hmFeatures
          ;
      };
    in
    systemFunc rec {
      inherit system;

      specialArgs = mkSpecialArgs {
        inherit
          system
          hostname
          username
          wsl
          darwin
          role
          ;
        libArg = lib;
      };

      modules =
        nixosModules
        ++ [
          (mkUser {
            inherit
              username
              pkgs
              darwin
              mydefs
              ;
          })
          homeFunc.home-manager
          {
            home-manager = mkHomeManagerConfig {
              inherit
                username
                system
                hostname
                wsl
                darwin
                role
                hmModules
                ;
            };
            user = username;
          }
        ]
        ++ extraUsers;
    };

  # Standalone home-manager configuration
  mkHome =
    {
      system,
      hostname,
      username,
      nixpkgs,
      mydefs,
      darwin ? false,
      wsl ? false,
      role ? null,
      hmFeatures ? [ ],
    }:
    let
      overlays = lib.attrValues inputs.self.overlays;
      hmModules = home-modules {
        inherit
          username
          darwin
          wsl
          hmFeatures
          ;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs { inherit system; } nixpkgs overlays;
      extraSpecialArgs = mkSpecialArgs {
        inherit
          system
          hostname
          username
          wsl
          darwin
          role
          ;
      };
      modules = hmModules.imports;
    };
}
