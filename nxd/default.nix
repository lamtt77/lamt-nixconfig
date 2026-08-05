args@{ ... }:
{ lib, ... }:

let
  targetInventory = args.infra.targetInventory or false;
  headscaleEnabled = !targetInventory || args.infra.hostMeta ? medo-test;
  withOperationTag =
    operation: values:
    lib.mapAttrs (
      _name: value:
      value
      // {
        tags = lib.unique ((value.tags or [ ]) ++ [ "operation:${operation}" ]);
      }
    ) values;
in
{
  imports = [
    (import ./identities.nix args)
    (import ./operations.nix args)
    (import ./providers.nix args)
    (import ./secrets.nix args)
  ];
  nxd = {
    stack.name = "lamt";
    site.hosts = args.infra.hostMeta;
    site.clusters = withOperationTag "pve" args.infra.site.clusters;
    site.nodes = withOperationTag "pve" args.infra.site.nodes;
    site.guests = args.infra.site.guests;
    site.pveAccess = args.infra.site.pveAccess;
    site.pveStorage = withOperationTag "pve" args.infra.site.pveStorage;
    site.pveStorageAttachments = args.infra.site.pveStorageAttachments;
    site.pveStorageAbsent = args.infra.site.pveStorageAbsent;
    site.storage = args.infra.site.storage;
    site.backupJobs = args.infra.site.backupJobs;
    site.backupServers = withOperationTag "pbs" args.infra.site.backupServers;
    site.datastores = withOperationTag "pbs" args.infra.site.datastores;
    site.backupNamespaces = withOperationTag "pbs" args.infra.site.backupNamespaces;
    site.accessPrincipals = withOperationTag "pbs" args.infra.site.accessPrincipals;
    site.accessGrants = withOperationTag "pbs" args.infra.site.accessGrants;
    site.headscaleUsers = lib.mkIf headscaleEnabled {
      lamt = {
        provider = "provider/headscale";
        namespace = "lamt";
      };
    };
    site.pveHostStates = lib.mkIf (!targetInventory) {
      pve1 = {
        provider = "provider/pve1";
        nodeId = "pve1";
        hostname = "pve-dl360p";
        bootMode = "grub";
        source = ../infra/proxmox/state/pve/pve1;
      };
      pve2 = {
        provider = "provider/pve2";
        nodeId = "pve2";
        hostname = "pve2";
        bootMode = "uefi";
        source = ../infra/proxmox/state/pve/pve2;
      };
      pve-test = {
        provider = "provider/pve1";
        nodeId = "pve-test";
        hostname = "pve-test";
        bootMode = "none";
        source = ../infra/proxmox/state/pve/pve-test;
      };
    };
    site.pveHostBackups = lib.mkIf (!targetInventory) args.infra.site.pveHostBackups;
    site.vmware = {
      inherit (args.infra.site.vmware) installer installerSha256;
    };

  };
}
