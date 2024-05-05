{
  description = "LamT Nix System Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
    nixos-wsl.inputs.flake-utils.follows = "flake-utils";

    home-manager.url = "github:nix-community/home-manager/release-23.11";
    # home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    flake-utils.url = "github:numtide/flake-utils";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    flake-registry.url = "github:nixos/flake-registry";
    flake-registry.flake = false;

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "darwin";
    agenix.inputs.home-manager.follows = "home-manager";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";

    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs-unstable";
    emacs-overlay.inputs.nixpkgs-stable.follows = "nixpkgs";
    emacs-overlay.inputs.flake-utils.follows = "flake-utils";

    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    neovim-nightly-overlay.inputs.nixpkgs.follows = "nixpkgs-unstable";
    neovim-nightly-overlay.inputs.flake-parts.follows = "flake-parts";

    # Other packages
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs-unstable";
    zig.inputs.flake-utils.follows = "flake-utils";

    # LamT secrets stuff, remove this for building without secrets / agenix module
    # OR sudo nixos-rebuild switch --override-input mysecrets "" --flake '.#gaming'
    mysecrets.url = "git+ssh://git@tea.lamhub.com/lamtt77/lamt-secrets.git";
    mysecrets.flake = false;

    nvim-conform.url = "github:stevearc/conform.nvim/v5.2.1";
    nvim-conform.flake = false;
    nvim-treesitter.url = "github:nvim-treesitter/nvim-treesitter/v0.9.1";
    nvim-treesitter.flake = false;
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, darwin, hyprland, ... }@inputs: let
    mydefs = import ./defines.nix;
    lib = nixpkgs.lib.extend
      (final: prev: { my = import ./lib {inherit inputs pkgsall; lib = final;}; });

    inherit (lib) genAttrs attrValues;
    inherit (lib.my) mapModules mapModulesRec mkPkgs mkHome mkHost mkSystem;

    username = mydefs.defaultUsername;
    forAllSystems = genAttrs mydefs.systems;
    # we should run mkPkgs for nixpkgs and nixpkgs-unstable once and here only!
    pkgsall = forAllSystems (system: mkPkgs system nixpkgs (attrValues self.overlays));
    pkgsall-unstable = forAllSystems (system: mkPkgs system nixpkgs-unstable []);
  in {
    inherit mydefs;
    nivsrc = import ./nix/sources.nix;
    libx = lib.my // lib // home-manager.lib; # all libs in one!
    legacyPackages = pkgsall;

    # just to show list of modules in 'nix repl', actual import handled by 'libx'
    nixosModules = mapModulesRec ./modules/os import;
    homeManagerModules = mapModulesRec ./modules/hm import;

    # some pkgs require unfree/unsupported, thus pkgsall
    packages = forAllSystems (system:
      mapModules ./pkgs (p: pkgsall.${system}.callPackage p {})
    );

    overlaysDisko = {
      disko = final: prev: {
        disko = inputs.disko.packages.${prev.system}.disko;
      };
    };

    overlays = self.overlaysDisko // mapModules ./overlays import // {
      # custom packages (additions or modifications/builds)
      default = final: prev: {
        my = self.packages.${prev.system};
        # provide 'pkgs.unstable'
        unstable = pkgsall-unstable.${prev.system};
      };

      agenix = inputs.agenix.overlays.default;

      # use prebuilt emacs to reduce my built-time
      # emacs = inputs.emacs-overlay.overlay;

      neovim = inputs.neovim-nightly-overlay.overlay;
      zig = inputs.zig.overlays.default;

      customVim = (import ./nix/vim.nix {inherit inputs;});
    };

    # apps run by calling this flake directly
    # Github: nix run github:lamtt77/lamt-nixconfig#appname
    # Local: nix run '.#readme'
    apps = forAllSystems (system: import ./apps { inherit inputs; pkgs = pkgsall.${system}; });

    # formatter = forAllSystems (system: pkgsall.${system}.nixpkgs-fmt);
    formatter = forAllSystems (system: pkgsall.${system}.nixfmt-rfc-style);

    # Accessible through 'nix develop' or 'nix-shell' (legacy)
    devShells = forAllSystems (system: {
      default = pkgsall.${system}.callPackage ./shells/shell.nix { };
      node = pkgsall.${system}.callPackage ./shells/node.nix { };
      python = pkgsall.${system}.callPackage ./shells/python.nix { };
      pythonVenv = pkgsall.${system}.callPackage ./shells/pythonVenv.nix { };
      lint = pkgsall.${system}.callPackage ./shells/lint.nix { };
    });

    # templates = import ./templates;

    # nix build .#homeConfigurations."lamt_macair15-m2".activationPackage
    # '@' character does not work with 'nix repl'
    homeConfigurations = {
      "${username}_macair15-m2" = mkHome {
        system = "aarch64-darwin"; host = "macair15-m2"; inherit username; darwin = true;
      };
      # TODO
      # "vivi_vm-aarch64" = mkHome {
      #   system = "aarch64-linux"; host = "vm-aarch64"; username = "vivi";
      # };
    };

    # nix build .#darwinConfigurations.macair15-m2.system
    darwinConfigurations = {
      macair15-m2 = mkHost {
        system = "aarch64-darwin"; host = "macair15-m2"; inherit username; darwin = true;
      };

      macair15-m2-combined = mkSystem {
        system = "aarch64-darwin"; host = "macair15-m2"; inherit username; darwin = true;
      };
    };

    # nix build .#nixosConfigurations.macair15-m2.config.system.build.toplevel
    nixosConfigurations = {
      # just some testing here
      installer-base = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs username;};
        modules = [
          { nixpkgs.overlays = builtins.attrValues self.overlaysDisko;}
          ./hosts/installer-base
        ];
      };

      air15vm = mkSystem {system = "aarch64-linux"; host = "air15vm"; inherit username;};
      vm-esxi = mkSystem {system = "x86_64-linux"; host = "vm-esxi"; inherit username;};
      vm-wintel = mkSystem {system = "x86_64-linux"; host = "vm-wintel"; inherit username;};

      # nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder
      wsl = mkSystem {system = "x86_64-linux"; host = "wsl"; inherit username; wsl = true;};
      # currently Windows Arm for aarch64 only supports WSL v1,
      # while nixos-wsl requires WSL v2, so this may not be working well
      wsl-aarch64 = mkSystem {system = "aarch64-linux"; host = "wsl"; inherit username; wsl = true;};

      # servers
      avon = mkSystem {system = "x86_64-linux"; host = "avon"; username = "nixos"; server = true;};

      # game stuffs
      gaming = mkSystem {system = "x86_64-linux"; host = "gaming"; username = "vivi"; server = true;};
    };
  };
}
