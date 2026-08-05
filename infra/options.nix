{ lib, ... }:
let
  hostType = lib.types.submodule {
    options = {
      targetIp = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
    };
  };

in
{
  options.site.providers = lib.mkOption {
    type = lib.types.attrs;
    default = { };
  };
  options.site.secrets = lib.mkOption {
    type = lib.types.attrs;
    default = { };
  };
  options.site.defaults.tailscaleNamespace = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  options.site.defaults.builderBySystem = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
  };

  options.site.defaults.sshIdentityPublicKey = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  options.site.vmware.isoDirectory = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  options.site.vmware.vmrun = lib.mkOption { type = lib.types.str; };
  options.site.vmware.vdiskmanager = lib.mkOption { type = lib.types.str; };
  options.site.vmware.installer = lib.mkOption { type = lib.types.str; };
  options.site.vmware.installerSha256 = lib.mkOption {
    type = lib.types.strMatching "[a-f0-9]{64}";
  };

  options.site.clusters = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.nodes = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
  };
  options.site.guests = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };

  options.site.hosts = lib.mkOption {
    type = lib.types.attrsOf hostType;
    default = { };
  };

  options.site.pveAccess = {
    provider = lib.mkOption { type = lib.types.str; };
    roles = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
    acls = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
    };
  };

  options.site.backupServers = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.datastores = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.backupNamespaces = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.accessPrincipals = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.accessGrants = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };
  options.site.storage = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };

  options.site.backupJobs = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
    description = "Cluster-wide PVE backup jobs projected as canonical backupJob resources.";
  };

  options.site.pveStorage = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
    description = "PVE storage definitions managed by NXD.";
  };
  options.site.pveStorageAttachments = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "PVE storage attachment presence-only assertions.";
  };
  options.site.pveStorageAbsent = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "PVE storage IDs asserting absence.";
  };
  options.site.pveHostBackups = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
    description = "PVE host backup production policies managed by NXD.";
  };
}
