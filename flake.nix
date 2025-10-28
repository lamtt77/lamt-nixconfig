{
  description = "LamT Nix System Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    # home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    flake-utils.url = "github:numtide/flake-utils";

    flake-registry.url = "github:nixos/flake-registry";
    flake-registry.flake = false;

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    darwin,
    flake-utils,
    ...
  } @ inputs: let
    mydefs = import ./defines.nix;
    # nixos modules can access all libs, hm modules only access to itself 'hm' and 'my'
    lib =
      nixpkgs.lib.extend (final: prev: {
        my = import ./lib {
          inherit inputs mydefs;
          lib = final;
        };
      })
      // home-manager.lib;

    inherit (lib) attrValues;
    inherit (lib.my) mapModules mkPkgs mkSystem mkHost mkHome;

    username = mydefs.defaultUsername;

    overlays = import ./overlays/overlays.nix {inherit inputs;};

    perSystem = flake-utils.lib.eachSystem mydefs.systems (system: let
      pkgs = mkPkgs {inherit system;} nixpkgs (attrValues self.overlays);
    in {
      # auto load all pkgs exclude pkgs/_manual
      packages = mapModules ./pkgs (p: pkgs.callPackage p {inherit inputs mydefs;});

      # apps run by calling this flake directly
      # Github: nix run github:lamtt77/lamt-nixconfig#appname
      # Local: nix run '.#readme'
      apps = import ./apps {inherit inputs pkgs mydefs;};

      # formatter
      formatter = pkgs.alejandra;

      # Accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = {
        default = pkgs.callPackage ./shells/shell.nix {};
        node = pkgs.callPackage ./shells/node.nix {};
        python = pkgs.callPackage ./shells/python.nix {};
        pythonVenv = pkgs.callPackage ./shells/pythonVenv.nix {};
        lint = pkgs.callPackage ./shells/lint.nix {};
      };

      legacyPackages = pkgs;
    });

    # nix build .#homeConfigurations.lamt_macair15-m2.activationPackage
    homeConfigurations = {
      "${username}_macair15-m2" = mkHome {
        system = "aarch64-darwin";
        hostname = "macair15-m2";
        inherit username nixpkgs mydefs;
        darwin = true;
      };
    };

    # nix build .#darwinConfigurations.macair15-m2.system
    darwinConfigurations = {
      macair15-m2 = mkSystem {
        system = "aarch64-darwin";
        hostname = "macair15-m2";
        inherit username nixpkgs mydefs;
        darwin = true;
      };
      # imac-m1 = mkSystem { system = "aarch64-darwin"; hostname = "imac-m1"; inherit username nixpkgs mydefs; darwin = true; };
      # macpro-intel = mkSystem { system = "x86_64-darwin"; hostname = "macpro-intel"; inherit username nixpkgs mydefs; darwin = true; };
    };

    # nix build .#nixosConfigurations.macair15-m2.config.system.build.toplevel
    nixosConfigurations = {
      air15vm = mkSystem {
        system = "aarch64-linux";
        hostname = "air15vm";
        inherit username nixpkgs mydefs;
      };
      # air15utm = mkSystem { system = "aarch64-linux"; hostname = "air15utm"; inherit username nixpkgs mydefs; };
      vm-esxi = mkSystem {
        system = "x86_64-linux";
        hostname = "vm-esxi";
        inherit username nixpkgs mydefs;
      };
      # vm-wintel = mkSystem { system = "x86_64-linux"; hostname = "vm-wintel"; inherit username nixpkgs mydefs; };

      # nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder
      wsl = mkSystem {
        system = "x86_64-linux";
        hostname = "wsl";
        inherit username nixpkgs mydefs;
        wsl = true;
      };
      # currently Windows Arm for aarch64 only supports WSL v1,
      # while nixos-wsl requires WSL v2, so this may not be working well
      # wsl-aarch64 = mkSystem { system = "aarch64-linux"; hostname = "wsl"; inherit username nixpkgs mydefs; wsl = true; };

      # installer
      installer-base = mkHost {
        system = "x86_64-linux";
        hostname = "installer-base";
        username = "root";
        inherit nixpkgs mydefs;
      };

      # servers
      avon = mkSystem {
        system = "x86_64-linux";
        hostname = "avon";
        username = "nixos";
        inherit nixpkgs mydefs;
        server = true;
      };

      avon-esxi = mkSystem {
        system = "x86_64-linux";
        hostname = "avon-esxi";
        username = "nixos";
        inherit nixpkgs mydefs;
        server = true;
      };

      # continuous integraion and utilities
      utils = mkSystem {
        system = "x86_64-linux";
        hostname = "utils";
        username = "deploy";
        inherit nixpkgs mydefs;
        server = true;
      };

      # game stuffs
      gaming = mkSystem {
        system = "x86_64-linux";
        hostname = "gaming";
        username = "vivi";
        inherit nixpkgs mydefs;
        server = true;
      };

      # DigitalOcean servers
      medo = mkSystem {
        system = "x86_64-linux";
        hostname = "medo";
        username = "nixos";
        inherit nixpkgs mydefs;
        server = true;
      };
    };

    crossNixosConfigurations = {
      gaming = mkSystem {
        system = "x86_64-linux";
        hostname = "gaming";
        username = "vivi";
        inherit nixpkgs mydefs;
        server = true;
        localSystem = "aarch64-linux";
        crossSystem = {config = "x86_64-unknown-linux-gnu";};
      };
      vm-esxi = mkSystem {
        system = "x86_64-linux";
        hostname = "vm-esxi";
        username = "nixos";
        inherit nixpkgs mydefs;
        server = true;
        localSystem = "aarch64-linux";
        crossSystem = {config = "x86_64-unknown-linux-gnu";};
      };
      wsl = mkSystem {
        system = "x86_64-linux";
        hostname = "wsl";
        username = "lamt";
        inherit nixpkgs mydefs;
        wsl = true;
        localSystem = "aarch64-linux";
        crossSystem = {config = "x86_64-unknown-linux-gnu";};
      };
    };
  in
    {
      inherit lib overlays darwinConfigurations nixosConfigurations homeConfigurations crossNixosConfigurations;
    }
    // perSystem;
}
