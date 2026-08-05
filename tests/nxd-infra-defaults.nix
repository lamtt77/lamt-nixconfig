# Infra/site and host default evaluation (not NXD plan/apply).
# Usage: nix-instantiate --eval --strict tests/nxd-infra-defaults.nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;
  mydefs = import ../defines.nix;
  my = import ../lib/my.nix { inherit lib mydefs; };
  infra = import ../infra { inherit lib; };
  inherit (infra) hostMeta site;
  clusterNodes = lib.flatten (
    lib.mapAttrsToList (_: cluster: map (node: site.nodes.${node}) cluster.nodes) site.clusters
  );

  expect = name: condition: if condition then "PASSED" else throw "TEST FAILED: ${name}";
in
{
  providerDefaults = expect "providerDefaults" (
    lib.all (
      provider:
      provider.defaultIsoStorage == "arthurz2-dir"
      && provider.defaultDiskStorage == "arthurz2-lvm"
      && provider.defaultGateway == "192.168.1.1"
      && provider.defaultNetwork == "virtio,bridge=vmbr1,tag=10"
      && provider.defaultDiscoverySubnets == [ "192.168.1.0/24" ]
    ) clusterNodes
  );

  provisioningNetworkAccess = expect "provisioningNetworkAccess" (
    site.pveAccess.roles.NXDNetworkUser.privileges == [ "SDN.Use" ]
    && lib.all (acl: acl.path == "/sdn/zones/localnetwork" && acl.role == "NXDNetworkUser") (
      lib.filter (acl: lib.hasPrefix "network-localnetwork-" acl.id) site.pveAccess.acls
    )
    &&
      builtins.length (lib.filter (acl: lib.hasPrefix "network-localnetwork-" acl.id) site.pveAccess.acls)
      == 2
  );

  pveHostStateIdentityBinding = expect "pveHostStateIdentityBinding" (
    site.providers.pbs.pbs.config.hostStateTransports.pbs-r720.identityAgentBinding
    == "env/SSH_AUTH_SOCK"
    && !(lib.hasInfix "/Users/" site.providers.pbs.pbs.config.hostStateTransports.pbs-r720.identityAgentBinding)
    && lib.hasPrefix "ssh-ed25519 " site.providers.pbs.pbs.config.hostStateTransports.pbs-r720.identityPublicKey
  );

  inheritedProxmoxDefaults = expect "inheritedProxmoxDefaults" (
    let
      deployment = hostMeta."ubuntu-cloudinit-test".deployment;
    in
    deployment.proxmox.host == "192.168.1.15"
    && deployment.proxmox.node == "pve-dl360p"
    && deployment.proxmox.iso.storage == "arthurz2-dir"
    && deployment.proxmox.diskStorage == "arthurz2-lvm"
    && deployment.proxmox.net0 == "virtio,bridge=vmbr1,tag=10"
    && deployment.proxmox.bootstrap.gateway == "192.168.1.1"
    && deployment.proxmox.discoverySubnets == [ "192.168.1.0/24" ]
    && deployment.proxmox.bootstrap.subnet == ""
  );

  pxeUsesIsolatedNetwork = expect "pxeUsesIsolatedNetwork" (
    let
      deployment = hostMeta."pve-test".deployment;
    in
    deployment.proxmox.net0 == "virtio,bridge=vmbrPxe"
    && deployment.proxmox.iso.storage == "arthurz2-dir"
    && deployment.proxmox.diskStorage == "arthurz2-lvm"
    && deployment.proxmox.bootstrap.gateway == "192.168.1.1"
    && deployment.proxmox.discoverySubnets == [ "192.168.250.0/24" ]
    && deployment.proxmox.bootstrap.subnet == ""
  );

  tailscaleNamespace = expect "tailscaleNamespace" (
    hostMeta."ubuntu-cloudinit-test".deployment.tailscaleNamespace == "lamt"
    && hostMeta.fcmutils.deployment.tailscaleNamespace == "fcm"
  );

  vmwareIsoDirectory = expect "vmwareIsoDirectory" (
    hostMeta.air15vm.deployment.vmware.isoDirectory
    == "/Users/lamt/Virtual Machines.localized/VMWIsoImages"
  );

  vmwareRuntimePaths = expect "vmwareRuntimePaths" (
    lib.hasPrefix "/" site.vmware.vmrun
    && lib.hasPrefix "/" site.vmware.vdiskmanager
    && lib.hasPrefix site.vmware.isoDirectory site.vmware.installer
    && builtins.stringLength site.vmware.installerSha256 == 64
  );

  binaryCache = expect "binaryCache" (
    hostMeta."ubuntu-cloudinit-test".nxd.binaryCache.url == "https://cache.lamhub.com?priority=10"
    &&
      hostMeta."ubuntu-cloudinit-test".nxd.binaryCache.publicKey
      == "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw="
    &&
      hostMeta."ubuntu-cloudinit-test".deployment.binaryCache
      == hostMeta."ubuntu-cloudinit-test".nxd.binaryCache
    && hostMeta."medo-test".deployment.binaryCache == hostMeta."medo-test".nxd.binaryCache
    && hostMeta."medo-test".nxd.binaryCache.url == "https://cache.lamhub.com?priority=10"
    && hostMeta.medo.nxd.binaryCache == null
    && hostMeta.medo.deployment.binaryCache == null
  );

  fcmBinaryCache = expect "fcmBinaryCache" (
    hostMeta.fcmutils.deployment.binaryCache == mydefs.fcmBinaryCache
    && hostMeta.fcmbuilder.deployment.binaryCache == mydefs.fcmBinaryCache
    && mydefs.fcmBinaryCache.url == "https://192.168.7.10"
    && mydefs.fcmBinaryCache.caCertificate != ""
  );

  automaticBuilderPolicy = expect "automaticBuilderPolicy" (
    hostMeta.gaming.deployment.buildOn == "auto"
    && hostMeta.gaming.deployment.builder == "deploy@utils"
    && hostMeta.gaming.deployment.localEval == null
    && hostMeta.utils.deployment.buildOn == "auto"
    && hostMeta.utils.deployment.builder == "deploy@utils"
    && hostMeta.utils.deployment.localEval == null
    && hostMeta."medo-test".deployment.lowMem == "yes"
    && hostMeta."medo-test".deployment.builder == "deploy@utils"
    && hostMeta."macair15-m2".deployment.builder == ""
    && hostMeta."macair15-m2".deployment.localEval == null
  );

  infraHostAddresses = expect "infraHostAddresses" (
    my.hostAddress "utils" == "192.168.1.19"
    && my.hostAddress "pbs-r720" == "192.168.1.22"
    && my.pveNodeAddress "pve1" == "192.168.1.15"
    && my.pveNodeAddress "pve2" == "192.168.1.5"
    && hostMeta.utils.deployment.targetIp == my.hostAddress "utils"
    && hostMeta."pbs-r720".deployment.targetIp == my.hostAddress "pbs-r720"
  );

  inventoryOnlyGuestsHaveNoAuthoredEndpoint = expect "inventoryOnlyGuestsHaveNoAuthoredEndpoint" (
    !(builtins.hasAttr "freenas112R720" site.hosts)
    && !(builtins.hasAttr "vyos-1.3-rolling" site.hosts)
    && !(builtins.hasAttr "vyos-124-lambuilt28Mar2020" site.hosts)
  );

  pbsPolicyInInfra = expect "pbsPolicyInInfra" (
    site.backupServers ? "pbs-r720"
    && site.backupServers.pbs-r720.pveNode == "pve2"
    && site.datastores ? "pbs-r720/arthurz2-pbs"
    && site.datastores."pbs-r720/arthurz2-pbs".path == "/mnt/arthur_z2/PBS/pbs-r720"
  );
}
