{
  self,
  inputs,
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
  # Single normalized hosts + infra graph for systems, indexes, and NXD projection.
  infra = import ../infra { inherit lib; };
  inherit (infra) hostMeta;
  # OS/HM shared surface only: never inject deployment.* into system modules.
  hostExtras =
    meta:
    { ... }:
    {
      user = meta.user;
      nxd.binaryCache = meta.nxd.binaryCache;
    };
  nxdModules = selectedInfra: [
    (import ../nxd/default.nix {
      infra = selectedInfra;
      inherit inputs;
    })
  ];
  targetInventory =
    evaluator: name: _meta:
    inputs.nxd.lib.selectTargetInventory (evaluator { modules = nxdModules infra; }) name;
in
{
  # 1. Export the canonical NXD deployment and infrastructure model.
  flake.nxdConfigurations = rec {
    lamt = inputs.nxd.lib.evalConfiguration {
      modules = nxdModules infra;
    };
    lamtUnstable = inputs.nxd.lib.evalConfigurationUnstable {
      modules = nxdModules infra;
    };
    default = lamt;
  };

  flake.nxdTargetInventories = rec {
    lamt = builtins.mapAttrs (targetInventory inputs.nxd.lib.evalConfiguration) hostMeta;
    lamtUnstable = builtins.mapAttrs (targetInventory inputs.nxd.lib.evalConfigurationUnstable) hostMeta;
    default = lamt;
  };

  flake.nxdTargetOutputs = rec {
    lamt = inputs.nxd.lib.evalTargetOutputs {
      targetConfigurations = self.nixosConfigurations // self.darwinConfigurations;
    };
    lamtUnstable = inputs.nxd.lib.evalTargetOutputsUnstable {
      targetConfigurations = self.nixosConfigurations // self.darwinConfigurations;
    };
    default = lamt;
  };

  # 2. Build full NixOS Configurations
  flake.nixosConfigurations =
    (builtins.mapAttrs (
      name: meta:
      lib.my.mkSystem {
        system = meta.system;
        hostname = name;
        username = meta.user;
        inherit (inputs) nixpkgs;
        inherit mydefs;
        role = meta.role;
        wsl = meta.wsl or false;
        osFeatures = meta.osFeatures or [ ];
        hmFeatures = meta.hmFeatures or [ ];
        extraUsers = [ (hostExtras meta) ];
      }
    ) (lib.filterAttrs (name: meta: meta.class == "nixos" && meta.buildSystem) hostMeta))
    // {
      # Non-metadata minimal-isos configurations to maintain compatibility
      minimal-iso-aarch64 = inputs.nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ../hosts/minimal-iso/default.nix
          (
            { ... }:
            {
              nixpkgs.hostPlatform = "aarch64-linux";
            }
          )
        ];
      };

      minimal-iso-x86 = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ../hosts/minimal-iso/default.nix
          (
            { ... }:
            {
              nixpkgs.hostPlatform = "x86_64-linux";
            }
          )
        ];
      };

      minimal-wsl-x86 = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs.nixos-wsl.nixosModules.wsl
          ../hosts/minimal-wsl/default.nix
          {
            nixpkgs.hostPlatform = "x86_64-linux";
          }
        ];
      };

      cold-recovery-usb = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ../hosts/cold-recovery-usb/default.nix
          {
            nixpkgs.overlays = builtins.attrValues inputs.self.overlays;
          }
        ];
      };
    };

  # 3. Build full Darwin Configurations
  flake.darwinConfigurations = builtins.mapAttrs (
    name: meta:
    lib.my.mkSystem {
      system = meta.system;
      hostname = name;
      username = meta.user;
      inherit (inputs) nixpkgs;
      inherit mydefs;
      role = meta.role;
      darwin = true;
      osFeatures = meta.osFeatures or [ ];
      hmFeatures = meta.hmFeatures or [ ];
      extraUsers = [ (hostExtras meta) ];
    }
  ) (lib.filterAttrs (name: meta: meta.class == "darwin") hostMeta);

  # 4. Build Home Manager configurations
  flake.homeConfigurations = builtins.listToAttrs (
    map (name: {
      name = "${hostMeta.${name}.user}_${name}";
      value = lib.my.mkHome {
        system = hostMeta.${name}.system;
        hostname = name;
        username = hostMeta.${name}.user;
        inherit (inputs) nixpkgs;
        inherit mydefs;
        role = hostMeta.${name}.role;
        darwin = hostMeta.${name}.class == "darwin";
        wsl = hostMeta.${name}.wsl or false;
        hmFeatures = hostMeta.${name}.hmFeatures or [ ];
      };
    }) (builtins.attrNames (lib.filterAttrs (name: meta: meta.home or false) hostMeta))
  );

  # 5. Build cross-compilation system configurations
  flake.crossNixosConfigurations = builtins.mapAttrs (
    name: meta:
    lib.my.mkSystem {
      system = meta.system;
      hostname = name;
      username = meta.user;
      inherit (inputs) nixpkgs;
      inherit mydefs;
      role = meta.role;
      wsl = meta.wsl or false;
      localSystem = meta.cross.localSystem;
      crossSystem = meta.cross.crossSystem;
      osFeatures = meta.osFeatures or [ ];
      hmFeatures = meta.hmFeatures or [ ];
      extraUsers = [ (hostExtras meta) ];
    }
  ) (lib.filterAttrs (name: meta: meta.cross != null) hostMeta);
}
