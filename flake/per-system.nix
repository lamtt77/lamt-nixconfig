{ inputs, ... }:
{
  perSystem =
    {
      config,
      self',
      inputs',
      system,
      ...
    }:
    let
      lib =
        inputs.nixpkgs.lib.extend (
          final: prev: {
            my = import ../lib {
              inherit inputs;
              mydefs = import ../defines.nix;
              lib = final;
            };
          }
        )
        // inputs.home-manager.lib;
      mydefs = import ../defines.nix;
      pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
          allowBroken = true;
        };
        overlays = builtins.attrValues inputs.self.overlays;
      };
    in
    {
      # Expose owned packages under packages. Keep installer-rs as a temporary migration alias.
      packages = lib.my.mapPackages ../pkgs (p: pkgs.callPackage p { inherit inputs mydefs; }) // {
        installer-rs = self'.packages.nxd;
      };

      # apps
      apps = import ../apps { inherit inputs pkgs mydefs; };

      # formatter
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.rustfmt.enable = true;
        # TODO cleanup when drop installer2
        settings.global.excludes = [
          "apps/installer2/templates/**"
        ];
      };

      # devShells
      devShells = {
        default = pkgs.callPackage ../shells/shell.nix { inherit inputs; };
        node = pkgs.callPackage ../shells/node.nix { };
        python = pkgs.callPackage ../shells/python.nix { };
        pythonVenv = pkgs.callPackage ../shells/pythonVenv.nix { };
        lint = pkgs.callPackage ../shells/lint.nix { };
        rust = pkgs.callPackage ../shells/rust.nix { };
      };
    };
}
