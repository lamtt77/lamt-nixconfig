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
  hostsDir = ../hosts;
  mydefs = import ../defines.nix;

  # Dynamically extract option schema and defaults from options.nix
  evalOptions = lib.evalModules {
    modules = [ ../modules/shared/options.nix ];
  };
  defaultDeployment = evalOptions.config.deployment;

  # Recursive merge helper to overlay host-defined values onto defaults
  recursiveMerge =
    lhs: rhs:
    if builtins.isAttrs lhs && builtins.isAttrs rhs then
      builtins.listToAttrs (
        map (name: {
          name = name;
          value = if builtins.hasAttr name rhs then recursiveMerge lhs.${name} rhs.${name} else lhs.${name};
        }) (builtins.attrNames lhs)
      )
    else
      rhs;

  roleDefaults = import ./host-roles.nix;

  # Loader transforming raw meta.nix into complete FlakeMetadata shape
  loadHostMeta =
    name:
    let
      meta = import (hostsDir + "/${name}/meta.nix");
      role = meta.role or null;
      hasRole = role != null && builtins.hasAttr role roleDefaults;
      rDefaults = if hasRole then roleDefaults.${role} else { };
      getVal =
        key: default:
        if builtins.hasAttr key meta then
          meta.${key}
        else if builtins.hasAttr key rDefaults then
          rDefaults.${key}
        else
          default;
      roleDeployment = rDefaults.deployment or { };
      mergedDeployment = recursiveMerge (recursiveMerge defaultDeployment roleDeployment) (
        meta.deployment or { }
      );
      roleTags = rDefaults.tags or [ ];
      metaTags = meta.tags or [ ];
      implicitTag = if role != null then [ role ] else [ ];
      finalTags = lib.unique (implicitTag ++ roleTags ++ metaTags);
    in
    {
      class = meta.class;
      system = meta.system;
      user = meta.username or "nixos";
      role = role;
      tags = finalTags;
      server = getVal "server" false;
      wsl = getVal "wsl" false;
      hasDisko = getVal "hasDisko" false;
      home = getVal "home" false;
      buildSystem = getVal "buildSystem" true;
      cross = meta.cross or null;
      deployment = mergedDeployment;
    };

  # Discovers all hosts containing meta.nix
  hostDirs = builtins.attrNames (
    lib.filterAttrs (name: type: type == "directory" && !(builtins.substring 0 1 name == "_")) (
      builtins.readDir hostsDir
    )
  );

  hostMeta = builtins.listToAttrs (
    map (name: {
      name = name;
      value = loadHostMeta name;
    }) (builtins.filter (name: builtins.pathExists (hostsDir + "/${name}/meta.nix")) hostDirs)
  );
in
{
  # 1. Export lightweight deployment metadata for installer-rs fast-path
  flake.deploymentHosts = hostMeta;

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
        server = meta.server or false;
        wsl = meta.wsl or false;

        extraUsers = [
          (
            { ... }:
            {
              deployment = meta.deployment;
              user = meta.user;
            }
          )
        ];
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

      minimal-iso-vlan = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ../hosts/minimal-iso/default.nix
          (
            { ... }:
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              iso.vlan.enable = true;
            }
          )
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
      darwin = true;

      extraUsers = [
        (
          { ... }:
          {
            deployment = meta.deployment;
            user = meta.user;
          }
        )
      ];
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
        darwin = hostMeta.${name}.class == "darwin";
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
      server = meta.server or false;
      wsl = meta.wsl or false;
      localSystem = meta.cross.localSystem;
      crossSystem = meta.cross.crossSystem;

      extraUsers = [
        (
          { ... }:
          {
            deployment = meta.deployment;
            user = meta.user;
          }
        )
      ];
    }
  ) (lib.filterAttrs (name: meta: meta.cross != null) hostMeta);
}
